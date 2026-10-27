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
## Vías de estación y cambios (tarea 61b, D112, D113): las StationTrack no son tramos (no entran
## al grafo) sino las vías de una estación. Debajo del grafo la red arma la capa física: une las
## puntas de vía que se tocan (a menos de JOIN_DISTANCE y mirando para lados opuestos) cuando una
## de las dos es de estación, y donde una punta sigue por dos o más vías hay un cambio
## (TrackSwitch) con su palanca (SwitchLever). Los vehículos preguntan por dónde seguir con
## next_piece. Donde no hay vías de estación (escenas viejas) sigue mandando next_track.
## Vía doble en una estación (tarea 61b.4): las dos vías del tramo se juntan en la punta de la
## estación (las dibuja así quien arma la escena). Ahí cada vía es la aguja de un cambio hacia las
## vías de la estación y, al salir, cada tren toma solo la vía de su sentido (sin palanca).
## Entradas cerradas (tarea 61b, D114): un semáforo en rojo cierra la entrada de un tramo desde
## una estación (set_entry_closed). Para el tren del jugador es como un tramo cortado en ese
## sentido: no entra. Los automáticos no lo miran (entran solo con su reserva, ver AutoTrains).

## Grupo del nodo RailNetwork, para que los vehículos lo encuentren sin apuntarlo (D42).
const GROUP: StringName = &"rail_network"
## Lo más lejos que pueden estar dos puntas de vía para unirse (tarea 61b).
const JOIN_DISTANCE: float = 1.0
## Coseno mínimo entre una punta y la opuesta de la otra vía: tienen que seguir derecho.
const JOIN_ALIGNMENT: float = 0.9
## Dónde va la palanca de un cambio: metros hacia atrás de la aguja y al costado de la vía.
const LEVER_BACK: float = 3.0
const LEVER_SIDE: float = 3.0

## Se movió un cambio (con la palanca o un automático).
signal switch_changed(track_switch: TrackSwitch)

## Si la red pone una palanca junto a cada cambio (las pruebas sin jugador pueden apagarlas).
@export var levers_enabled: bool = true

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
# station_id -> Array con sus StationTrack (tarea 61b; sin tipo: pueden quedar borradas).
var _station_tracks: Dictionary = {}
# "curva:punta" -> Array de [Path3D, bool entra por el final]: por dónde sigue esa punta.
var _links: Dictionary = {}
# "curva:punta" de la aguja -> TrackSwitch.
var _switch_at: Dictionary = {}
var _switches: Array[TrackSwitch] = []
# "curva:punta" de la aguja -> estado, para no perderlo al rearmar la red.
var _switch_states: Dictionary = {}
var _next_switch_id: int = 1
# Mientras un automático mueve un cambio al pasar: no hay que rehacer su propia ruta.
var _choosing: bool = false
# "tramo|estación" -> true: entradas cerradas por un semáforo en rojo.
var _closed_entries: Dictionary = {}


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
	_build_links()
	for warning: String in validate():
		push_warning("RailNetwork: " + warning)


## Si el grafo ya está armado (después del primer cuadro de la escena).
func is_built() -> bool:
	return _built


## Vacía el grafo (sin tocar las vías).
func clear() -> void:
	for segment_id: StringName in _tracks:
		for track: TrackSegment in _tracks[segment_id]:
			if is_instance_valid(track) and track.state_changed.is_connected(_on_track_state_changed):
				track.state_changed.disconnect(_on_track_state_changed)
	_tracks.clear()
	_stations.clear()
	_station_tracks.clear()
	_links.clear()
	_switch_at.clear()
	for track_switch: TrackSwitch in _switches:
		if is_instance_valid(track_switch.lever):
			track_switch.lever.queue_free()
	_switches.clear()


## Suma una vía al grafo. Sin `segment_id` o sin sus dos estaciones queda afuera.
## Lo usa rebuild(); también sirve para armar una red en una prueba sin escena.
func add_track(track: TrackSegment) -> void:
	_built = true
	var station_track := track as StationTrack
	if station_track != null:
		var station: StringName = station_track.get_station_id()
		if not _station_tracks.has(station):
			_station_tracks[station] = []
		var own: Array = _station_tracks[station]
		if not own.has(station_track):
			own.append(station_track)
		return
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
## en orden. Vacío si no hay camino (o si `from` y `to` son la misma estación). Con
## `through_cut` también pasa por los cortados (tarea 58: qué tramos habilitar para una conexión).
func find_route(from: StringName, to: StringName, through_cut: bool = false) -> Array[StringName]:
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
			if is_cut(segment_id) and not through_cut:
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


## El largo total de una lista de tramos (por ejemplo, la que devuelve find_route).
func get_route_length(route: Array[StringName]) -> float:
	var total: float = 0.0
	for segment_id: StringName in route:
		total += get_segment_length(segment_id)
	return total


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
			if track != null and not (track is StationTrack) and (track.segment_id == &"" or track.from_station == &"" or track.to_station == &""):
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
			# Tarea 61b: a una estación con vías propias, el tramo tiene que llegar a una punta.
			for at_end: bool in [false, true]:
				var station: StringName = track.to_station if at_end else track.from_station
				if has_station_tracks(station) and track.get_track_path() != null \
						and track.get_track_path().is_inside_tree() and not has_links(track.get_track_path(), at_end):
					warnings.append("el tramo %s no llega a una punta de las vías de %s (a menos de %.0f m): ahí el tren salta como antes." % [segment_id, station, JOIN_DISTANCE])
	return warnings


## Las vías de una estación (tarea 61b), habilitadas o no.
func get_station_tracks(station: StringName) -> Array[StationTrack]:
	_ensure_built()
	var list: Array[StationTrack] = []
	# Las de una estación que se borró de la escena quedan afuera.
	for node: Variant in _station_tracks.get(station, []):
		if is_instance_valid(node):
			list.append(node as StationTrack)
	return list


## Si la estación tiene vías propias habilitadas (si no, sigue siendo un punto como antes).
func has_station_tracks(station: StringName) -> bool:
	for station_track: StationTrack in get_station_tracks(station):
		if station_track.enabled:
			return true
	return false


## Los cambios de toda la red.
func get_switches() -> Array[TrackSwitch]:
	_ensure_built()
	return _switches.duplicate()


## Los cambios de una estación.
func get_switches_at(station: StringName) -> Array[TrackSwitch]:
	var list: Array[TrackSwitch] = []
	for track_switch: TrackSwitch in get_switches():
		if track_switch.station_id == station:
			list.append(track_switch)
	return list


## El cambio cuya aguja es esa punta de curva, o null.
func find_switch(path: Path3D, at_end: bool) -> TrackSwitch:
	_ensure_built()
	return _switch_at.get(_end_key(path, at_end)) as TrackSwitch


## Si esa punta de curva está unida por cercanía a otras vías (capa física, tarea 61b).
func has_links(path: Path3D, at_end: bool) -> bool:
	_ensure_built()
	return _links.has(_end_key(path, at_end))


## Las vías por las que sigue esa punta: [Path3D, bool entra por el final de la curva].
func get_links(path: Path3D, at_end: bool) -> Array:
	_ensure_built()
	return (_links.get(_end_key(path, at_end), []) as Array).duplicate(true)


## Por dónde sale un tren por esa punta sin mirar la palanca: en la vía doble, la vía de su
## sentido; si no, la primera de get_links. Vacío si ahí termina.
func get_exit(path: Path3D, at_end: bool) -> Array:
	var links: Array = get_links(path, at_end)
	if links.size() > 1 and _is_way_choice(links):
		return _way_for(links, [])
	return links[0] if not links.is_empty() else []


## Por dónde sigue un vehículo que sale de `path` por su final (`at_end`) o su principio:
## [Path3D, bool entra por el final de esa curva], o vacío si ahí termina (tope, punta de línea,
## tramo cortado o cruce sin destino). En un cambio, la vía que marca la palanca; si el tren tiene
## Vehicle.switch_chooser (los automáticos), la que elige él, y la palanca se mueve sola. Pasar un
## cambio de talón lo deja puesto hacia la vía de donde viene el tren. Una de
## `prefer` gana siempre (al volver marcha atrás hacia un vehículo del mismo tren). Sin capa
## física en esa punta, decide next_track como en la tarea 54.
func next_piece(path: Path3D, at_end: bool, vehicle: Vehicle = null, prefer: Array = []) -> Array:
	_ensure_built()
	var key: String = _end_key(path, at_end)
	if _links.has(key):
		var options: Array = _links[key]
		var chosen: Array = options[0]
		if options.size() > 1 and _switch_at.has(key):
			chosen = options[_choose(_switch_at[key], vehicle, prefer)]
		elif options.size() > 1:
			chosen = _way_for(options, prefer)
			_trail(path, at_end, chosen)
		elif options.size() == 1:
			_trail(path, at_end, chosen)
		var next: TrackSegment = track_of(chosen[0])
		if next != null and next.is_cut():
			return []
		# Volver marcha atrás a una vía donde ya está el mismo tren se puede siempre.
		if next != null and not prefer.has(chosen[0]) and not may_enter(vehicle, next, next.to_station if chosen[1] else next.from_station):
			return []
		return chosen.duplicate()
	var track: TrackSegment = track_of(path)
	if track == null or track is StationTrack:
		return []
	var station: StringName = track.to_station if at_end else track.from_station
	var destination: StringName = vehicle.get_head().destination if vehicle != null else &""
	var following: TrackSegment = next_track(track, station, destination)
	if following == null or following.get_track_path() == null or not may_enter(vehicle, following, station):
		return []
	return [following.get_track_path(), following.from_station != station]


## Cierra (semáforo en rojo) o abre la entrada del tramo desde una estación. Al cerrarla, los
## trenes que ya habían mirado por dónde seguir vuelven a preguntar.
func set_entry_closed(segment_id: StringName, station: StringName, closed: bool) -> void:
	var key: String = "%s|%s" % [segment_id, station]
	if closed == _closed_entries.has(key):
		return
	if closed:
		_closed_entries[key] = true
		_forget_routes()
	else:
		_closed_entries.erase(key)


func is_entry_closed(segment_id: StringName, station: StringName) -> bool:
	return _closed_entries.has("%s|%s" % [segment_id, station])


## Si `vehicle` puede entrar a la vía `track` desde `station`: no, si es el tren del jugador (o
## uno suelto) y esa entrada está cerrada. Las vías de estación y los automáticos, siempre.
func may_enter(vehicle: Vehicle, track: TrackSegment, station: StringName) -> bool:
	if vehicle == null or track == null or track is StationTrack:
		return true
	if vehicle.get_head().automatic:
		return true
	return not is_entry_closed(track.segment_id, station)


## Vuelve a unir las puntas y armar los cambios sin rearmar el grafo (al habilitar una vía de
## estación, por ejemplo). Los cambios conservan su posición.
func rebuild_links() -> void:
	if _built:
		_build_links()


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


# Arma la capa física: une las puntas que se tocan cuando una de las dos es de estación y crea
# un cambio donde una punta sigue por varias vías.
func _build_links() -> void:
	_links.clear()
	_switch_at.clear()
	for track_switch: TrackSwitch in _switches:
		if is_instance_valid(track_switch.lever):
			track_switch.lever.queue_free()
	_switches.clear()
	var ends: Array = []
	var tracks: Array[TrackSegment] = []
	for segment_id: StringName in _tracks:
		tracks.append_array(_tracks[segment_id])
	for station: StringName in _station_tracks:
		for station_track: StationTrack in get_station_tracks(station):
			if station_track.enabled:
				tracks.append(station_track)
	for track: TrackSegment in tracks:
		var path: Path3D = track.get_track_path()
		if path == null or path.curve == null or not path.is_inside_tree() or path.curve.get_baked_length() <= 0.0:
			continue
		for at_end: bool in [false, true]:
			ends.append(_end_info(track, path, at_end))
	for i: int in ends.size():
		for j: int in range(i + 1, ends.size()):
			var a: Dictionary = ends[i]
			var b: Dictionary = ends[j]
			if a.path == b.path or not (a.track is StationTrack or b.track is StationTrack):
				continue
			if (a.point as Vector3).distance_to(b.point) > JOIN_DISTANCE:
				continue
			if (a.out as Vector3).dot(b.out) > -JOIN_ALIGNMENT:
				continue
			_add_link(a, b)
			_add_link(b, a)
	for info: Dictionary in ends:
		var key: String = _end_key(info.path, info.at_end)
		if _links.has(key) and (_links[key] as Array).size() > 1 and not _is_way_choice(_links[key]):
			_make_switch(info)


func _add_link(from: Dictionary, to: Dictionary) -> void:
	var key: String = _end_key(from.path, from.at_end)
	if not _links.has(key):
		_links[key] = []
	(_links[key] as Array).append([to.path, to.at_end])


# Una punta de vía: dónde está y hacia dónde sale un tren que la deja (global).
func _end_info(track: TrackSegment, path: Path3D, at_end: bool) -> Dictionary:
	var curve: Curve3D = path.curve
	var length: float = curve.get_baked_length()
	var step: float = minf(0.5, length)
	var tip: Vector3 = path.global_transform * curve.sample_baked(length if at_end else 0.0)
	var inner: Vector3 = path.global_transform * curve.sample_baked(length - step if at_end else step)
	return {"track": track, "path": path, "at_end": at_end, "point": tip, "out": (tip - inner).normalized()}


func _make_switch(toe: Dictionary) -> void:
	var key: String = _end_key(toe.path, toe.at_end)
	var track_switch := TrackSwitch.new()
	track_switch.id = _next_switch_id
	_next_switch_id += 1
	track_switch.toe_path = toe.path
	track_switch.toe_at_end = toe.at_end
	track_switch.point = toe.point
	track_switch.direction = Vector3(toe.out.x, 0.0, toe.out.z).normalized()
	track_switch.options = _links[key]
	for index: int in track_switch.option_count():
		var station_track := track_switch.get_option_track(index) as StationTrack
		if station_track != null:
			track_switch.station_id = station_track.get_station_id()
			break
	if toe.track is StationTrack:
		track_switch.station_id = (toe.track as StationTrack).get_station_id()
	var state: int = -1
	if _switch_states.has(key) and int(_switch_states[key]) < track_switch.option_count():
		state = int(_switch_states[key])
	else:
		for index: int in track_switch.option_count():
			if track_switch.is_main_option(index):
				state = index
				break
	track_switch.state = maxi(0, state)
	_switch_states[key] = track_switch.state
	track_switch.state_changed.connect(_on_switch_state_changed.bind(track_switch, key))
	_switches.append(track_switch)
	_switch_at[key] = track_switch
	if levers_enabled and is_inside_tree():
		var lever := SwitchLever.new()
		lever.name = "Palanca%d" % track_switch.id
		add_child(lever)
		lever.global_position = _lever_position(track_switch)
		lever.track_switch = track_switch
		track_switch.lever = lever


# Al costado de la vía, unos metros antes de la aguja y del lado contrario a donde se abren las vías.
func _lever_position(track_switch: TrackSwitch) -> Vector3:
	var forward: Vector3 = track_switch.direction
	if forward.length_squared() < 0.01:
		forward = Vector3.FORWARD
	var side: Vector3 = forward.cross(Vector3.UP).normalized()
	var spread: float = 0.0
	for index: int in track_switch.option_count():
		var path: Path3D = track_switch.get_option_path(index)
		var length: float = path.curve.get_baked_length()
		var from_end: bool = track_switch.options[index][1]
		var probe: Vector3 = path.global_transform * path.curve.sample_baked(maxf(0.0, length - 15.0) if from_end else minf(15.0, length))
		spread += (probe - track_switch.point).dot(side)
	var away: float = -1.0 if spread > 0.0 else 1.0
	return track_switch.point - forward * LEVER_BACK + side * LEVER_SIDE * away


# Elige la salida de un cambio para un vehículo (ver next_piece).
func _choose(track_switch: TrackSwitch, vehicle: Vehicle, prefer: Array) -> int:
	for index: int in track_switch.option_count():
		if prefer.has(track_switch.get_option_path(index)):
			return index
	if vehicle != null:
		var head: Vehicle = vehicle.get_head()
		if head.switch_chooser.is_valid():
			var wanted: int = int(head.switch_chooser.call(track_switch))
			if wanted >= 0 and wanted < track_switch.option_count():
				_choosing = true
				track_switch.set_state(wanted, true)
				_choosing = false
				return wanted
	return track_switch.state


# Un tren que pasa un cambio de talón (desde una de sus vías hacia la aguja) lo deja puesto hacia
# la vía de donde viene, como pasa al talonar una aguja: así, si vuelve, vuelve por la misma.
func _trail(path: Path3D, at_end: bool, toe: Array) -> void:
	var track_switch: TrackSwitch = _switch_at.get(_end_key(toe[0], toe[1])) as TrackSwitch
	if track_switch == null:
		return
	for index: int in track_switch.option_count():
		if track_switch.get_option_path(index) == path and bool(track_switch.options[index][1]) == at_end:
			_choosing = true
			track_switch.set_state(index, true)
			_choosing = false
			return


func _on_switch_state_changed(state: int, track_switch: TrackSwitch, key: String) -> void:
	_switch_states[key] = state
	if not _choosing:
		_forget_routes()
	switch_changed.emit(track_switch)


# Los trenes que ya habían mirado por dónde seguir vuelven a preguntar.
func _forget_routes() -> void:
	if not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group(Vehicle.GROUP):
		var vehicle := node as Vehicle
		if vehicle != null and vehicle.front == null:
			vehicle.forget_route_ahead()


# Si las salidas son las dos vías de un mismo tramo de vía doble (la punta de una vía de estación
# donde llega la vía doble, tarea 61b.4): ahí no hay palanca, cada tren toma la de su sentido.
static func _is_way_choice(options: Array) -> bool:
	var segment_id: StringName = &""
	for option: Array in options:
		var track: TrackSegment = track_of(option[0])
		if track == null or track is StationTrack or track.segment_id == &"":
			return false
		if segment_id != &"" and track.segment_id != segment_id:
			return false
		segment_id = track.segment_id
	return true


# La vía de su sentido (D81): la que se recorre desde su principio. Gana una de `prefer` (volver
# marcha atrás a la vía donde ya está el tren).
static func _way_for(options: Array, prefer: Array) -> Array:
	for option: Array in options:
		if prefer.has(option[0]):
			return option
	for option: Array in options:
		if not bool(option[1]):
			return option
	return options[0]


static func _end_key(path: Path3D, at_end: bool) -> String:
	return "%d:%d" % [path.get_instance_id() if path != null else 0, 1 if at_end else 0]
