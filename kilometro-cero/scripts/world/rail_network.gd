class_name RailNetwork
extends Node
## Red ferroviaria (tarea 54, D78 y D81): un grafo con las estaciones como nodos y los tramos
## como aristas. No dibuja nada: lo arma con los TrackSegment de la escena (cada uno dice su
## tramo y sus dos estaciones) y responde por dónde sigue un tren al llegar a una estación,
## qué tramos están cortados y si dos estaciones están conectadas.
## Va un solo nodo RailNetwork en el mundo, en cualquier lugar de la escena. Sin él, los
## vehículos se frenan al final de su curva como antes.
## El estado de un tramo vive en sus vías: si cambia en una (desde acá, desde el inspector o
## desde un obstáculo), la red lo copia a la otra vía y lo avisa por
## EventBus.segment_state_changed.
## Bloqueos (tarea 55): un obstáculo (Obstacle) u otra cosa que corta un tramo se anota con
## add_blocker. Mientras un tramo tenga bloqueos queda cortado y no se lo puede abrir; al irse
## el último, vuelve al estado que tenía antes (abierto si estaba cortado).

## Grupo del nodo RailNetwork, para que los vehículos lo encuentren sin apuntarlo (D42).
const GROUP: StringName = &"rail_network"

# segment_id -> Array[TrackSegment] (una vía, o dos si es doble).
var _tracks: Dictionary = {}
# station_id -> Array[StringName] con los tramos que llegan a esa estación.
var _stations: Dictionary = {}
var _built: bool = false
# Mientras se copia el estado de una vía a su gemela, para avisar una sola vez.
var _syncing: bool = false
# segment_id -> Array[Object] con lo que lo corta. No se borra al rearmar la red.
var _blockers: Dictionary = {}
# segment_id -> State al que vuelve cuando se va el último bloqueo.
var _state_before_block: Dictionary = {}


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	# Diferido: las vías que están después en la escena todavía pueden no estar listas.
	rebuild.call_deferred()


## El RailNetwork de la escena, o null si no hay.
static func find_in(tree: SceneTree) -> RailNetwork:
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP) as RailNetwork


## Vuelve a armar el grafo con todas las vías de la escena.
func rebuild() -> void:
	clear()
	if is_inside_tree():
		for node: Node in get_tree().get_nodes_in_group(TrackSegment.GROUP):
			var track := node as TrackSegment
			if track != null:
				add_track(track)
	_built = true
	for warning: String in validate():
		push_warning("RailNetwork: " + warning)


## Vacía el grafo (sin tocar las vías).
func clear() -> void:
	for segment_id: StringName in _tracks:
		for track: TrackSegment in _tracks[segment_id]:
			if is_instance_valid(track) and track.state_changed.is_connected(_on_track_state_changed):
				track.state_changed.disconnect(_on_track_state_changed)
	_tracks.clear()
	_stations.clear()


## Suma una vía al grafo. Sin `segment_id` o sin sus dos estaciones queda afuera.
## Lo usa rebuild(); también sirve para armar una red en una prueba sin escena.
func add_track(track: TrackSegment) -> void:
	_built = true
	if track == null or track.segment_id == &"" or track.from_station == &"" or track.to_station == &"":
		return
	if not _tracks.has(track.segment_id):
		_tracks[track.segment_id] = [] as Array[TrackSegment]
	var list: Array[TrackSegment] = _tracks[track.segment_id]
	if list.has(track):
		return
	if is_blocked(track.segment_id):
		track.state = TrackSegment.State.CUT
	elif not list.is_empty() and list[0].state != track.state:
		# Las dos vías de un tramo tienen un solo estado: manda la primera.
		track.state = list[0].state
	list.append(track)
	for station: StringName in [track.from_station, track.to_station]:
		if not _stations.has(station):
			_stations[station] = [] as Array[StringName]
		var segments: Array[StringName] = _stations[station]
		if not segments.has(track.segment_id):
			segments.append(track.segment_id)
	track.state_changed.connect(_on_track_state_changed.bind(track))


func get_station_ids() -> Array[StringName]:
	_ensure_built()
	var ids: Array[StringName] = []
	ids.assign(_stations.keys())
	return ids


func get_segment_ids() -> Array[StringName]:
	_ensure_built()
	var ids: Array[StringName] = []
	ids.assign(_tracks.keys())
	return ids


func has_segment(segment_id: StringName) -> bool:
	_ensure_built()
	return _tracks.has(segment_id)


## Las vías de un tramo (una, o dos si es doble).
func get_tracks(segment_id: StringName) -> Array[TrackSegment]:
	_ensure_built()
	var list: Array[TrackSegment] = []
	if _tracks.has(segment_id):
		list.assign(_tracks[segment_id])
	return list


func is_double(segment_id: StringName) -> bool:
	return get_tracks(segment_id).size() >= 2


## Los tramos que llegan a una estación.
func get_segments_at(station: StringName) -> Array[StringName]:
	_ensure_built()
	var list: Array[StringName] = []
	if _stations.has(station):
		list.assign(_stations[station])
	return list


## La estación del otro extremo del tramo, o &"" si `station` no es un extremo suyo.
func other_end(segment_id: StringName, station: StringName) -> StringName:
	var tracks: Array[TrackSegment] = get_tracks(segment_id)
	return tracks[0].other_station(station) if not tracks.is_empty() else &""


## Estado del tramo. Un tramo que no existe cuenta como cortado.
func get_state(segment_id: StringName) -> TrackSegment.State:
	var tracks: Array[TrackSegment] = get_tracks(segment_id)
	return tracks[0].state if not tracks.is_empty() else TrackSegment.State.CUT


## Cambia el estado del tramo en todas sus vías. Devuelve false si el tramo no existe, o si
## tiene bloqueos y se lo quiere abrir.
func set_state(segment_id: StringName, value: TrackSegment.State) -> bool:
	var tracks: Array[TrackSegment] = get_tracks(segment_id)
	if tracks.is_empty():
		return false
	if value != TrackSegment.State.CUT and is_blocked(segment_id):
		return false
	# Alcanza con la primera: _on_track_state_changed copia a la otra y avisa.
	tracks[0].state = value
	return true


func is_cut(segment_id: StringName) -> bool:
	return get_state(segment_id) == TrackSegment.State.CUT


## Anota algo que corta el tramo (un obstáculo). El tramo pasa a cortado; el estado que
## tenía se recuerda para cuando se vaya el último bloqueo. Devuelve false si no existe.
func add_blocker(segment_id: StringName, blocker: Object) -> bool:
	if blocker == null or not has_segment(segment_id):
		return false
	var list: Array = get_blockers(segment_id)
	if list.has(blocker):
		return true
	if list.is_empty():
		var before: TrackSegment.State = get_state(segment_id)
		_state_before_block[segment_id] = TrackSegment.State.OPEN if before == TrackSegment.State.CUT else before
	list.append(blocker)
	_blockers[segment_id] = list
	set_state(segment_id, TrackSegment.State.CUT)
	return true


## Saca un bloqueo. Si era el último, el tramo vuelve al estado de antes. Devuelve false si
## ese bloqueo no estaba anotado.
func remove_blocker(segment_id: StringName, blocker: Object) -> bool:
	var list: Array = get_blockers(segment_id)
	if not list.has(blocker):
		return false
	list.erase(blocker)
	if not list.is_empty():
		_blockers[segment_id] = list
		return true
	_blockers.erase(segment_id)
	var restore: TrackSegment.State = _state_before_block.get(segment_id, TrackSegment.State.OPEN)
	_state_before_block.erase(segment_id)
	set_state(segment_id, restore)
	return true


## Lo que corta el tramo ahora (los que ya no existen se descartan).
func get_blockers(segment_id: StringName) -> Array:
	var alive: Array = []
	for blocker: Variant in _blockers.get(segment_id, []):
		if is_instance_valid(blocker):
			alive.append(blocker)
	return alive


func is_blocked(segment_id: StringName) -> bool:
	return not get_blockers(segment_id).is_empty()


## Largo del tramo: el de su vía más corta.
func get_segment_length(segment_id: StringName) -> float:
	var length: float = INF
	for track: TrackSegment in get_tracks(segment_id):
		length = minf(length, track.get_length())
	return length if length != INF else 0.0


## Los tramos para ir de `from` a `to` por el camino más corto sin pasar por tramos cortados,
## en orden. Vacío si no hay camino (o si `from` y `to` son la misma estación).
func find_route(from: StringName, to: StringName) -> Array[StringName]:
	_ensure_built()
	var route: Array[StringName] = []
	if from == to or not _stations.has(from) or not _stations.has(to):
		return route
	# Dijkstra: la red es chica (decenas de estaciones), alcanza con buscar el mínimo a mano.
	var distance: Dictionary = {from: 0.0}
	var came_by: Dictionary = {}
	var pending: Array[StringName] = [from]
	var done: Dictionary = {}
	while not pending.is_empty():
		var best: int = 0
		for i: int in range(1, pending.size()):
			if distance[pending[i]] < distance[pending[best]]:
				best = i
		var station: StringName = pending[best]
		pending.remove_at(best)
		if station == to:
			break
		done[station] = true
		for segment_id: StringName in _stations[station]:
			if is_cut(segment_id):
				continue
			var next: StringName = other_end(segment_id, station)
			if done.has(next):
				continue
			var total: float = distance[station] + get_segment_length(segment_id)
			if not distance.has(next) or total < distance[next]:
				if not distance.has(next):
					pending.append(next)
				distance[next] = total
				came_by[next] = segment_id
	if not came_by.has(to):
		return route
	var cursor: StringName = to
	while cursor != from:
		var segment_id: StringName = came_by[cursor]
		route.push_front(segment_id)
		cursor = other_end(segment_id, cursor)
	return route


## Si se puede ir de una estación a la otra sin pasar por tramos cortados.
func are_connected(from: StringName, to: StringName) -> bool:
	if from == to:
		return has_station(from)
	return not find_route(from, to).is_empty()


func has_station(station: StringName) -> bool:
	_ensure_built()
	return _stations.has(station)


## Por qué vía sigue un tren que sale de la vía `current` por la estación `station`, o null si
## ahí termina (punta de línea, tramo cortado o un cruce sin destino que lo decida). Reglas:
## - Si a la estación llega un solo tramo más, ese.
## - Si llegan varios, el primero del camino más corto a `destination`.
## - Un tramo cortado no se toma nunca (el tren se frena al final de su vía).
## - En un tramo con vía doble, la que sale de esta estación (cada tren usa la de su sentido).
func next_track(current: TrackSegment, station: StringName, destination: StringName = &"") -> TrackSegment:
	_ensure_built()
	var current_id: StringName = current.segment_id if current != null else &""
	var options: Array[StringName] = []
	for segment_id: StringName in get_segments_at(station):
		if segment_id != current_id:
			options.append(segment_id)
	var chosen: StringName = &""
	if options.size() == 1:
		chosen = options[0]
	elif options.size() > 1 and destination != &"" and destination != station:
		var route: Array[StringName] = find_route(station, destination)
		if not route.is_empty() and options.has(route[0]):
			chosen = route[0]
	if chosen == &"" or is_cut(chosen):
		return null
	return track_leaving(chosen, station)


## La vía del tramo que sale de `station` (su avance 0 está ahí); si no hay, cualquiera.
func track_leaving(segment_id: StringName, station: StringName) -> TrackSegment:
	var tracks: Array[TrackSegment] = get_tracks(segment_id)
	for track: TrackSegment in tracks:
		if track.from_station == station:
			return track
	for track: TrackSegment in tracks:
		if track.to_station == station:
			return track
	return null


## La vía (TrackSegment) de una curva, o null.
static func track_of(path: Path3D) -> TrackSegment:
	if path == null:
		return null
	for child: Node in path.get_children():
		var track := child as TrackSegment
		if track != null:
			return track
	return null


## Problemas de armado de la red, en texto (vacío si está bien). Se avisan al armarla.
func validate() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if is_inside_tree():
		for node: Node in get_tree().get_nodes_in_group(TrackSegment.GROUP):
			var track := node as TrackSegment
			if track != null and (track.segment_id == &"" or track.from_station == &"" or track.to_station == &""):
				warnings.append("la vía %s no tiene tramo o estaciones: queda fuera de la red." % track.get_parent().name)
	for segment_id: StringName in _tracks:
		var tracks: Array[TrackSegment] = _tracks[segment_id]
		if tracks.size() > 2:
			warnings.append("el tramo %s tiene %d vías (como mucho son dos)." % [segment_id, tracks.size()])
		for track: TrackSegment in tracks:
			if track.from_station == track.to_station:
				warnings.append("el tramo %s empieza y termina en la misma estación." % segment_id)
			if track.get_track_path() == null:
				warnings.append("una vía del tramo %s no cuelga de un Path3D." % segment_id)
			var ends: Array[StringName] = [tracks[0].from_station, tracks[0].to_station]
			if not ends.has(track.from_station) or not ends.has(track.to_station):
				warnings.append("las vías del tramo %s no unen las mismas estaciones." % segment_id)
	return warnings


func _ensure_built() -> void:
	if not _built:
		rebuild()


func _on_track_state_changed(value: TrackSegment.State, track: TrackSegment) -> void:
	if _syncing:
		return
	if value != TrackSegment.State.CUT and is_blocked(track.segment_id):
		# Se lo quiso abrir desde el inspector o por código con un obstáculo encima: sigue cortado.
		push_warning("RailNetwork: el tramo %s tiene un obstáculo; sigue cortado hasta despejarlo." % track.segment_id)
		_syncing = true
		track.state = TrackSegment.State.CUT
		_syncing = false
		return
	_syncing = true
	for other: TrackSegment in get_tracks(track.segment_id):
		other.state = value
	_syncing = false
	EventBus.segment_state_changed.emit(track.segment_id, value)
