@tool
class_name StationTracks
extends Node3D
## Arma las vías de una estación (tarea 61b, D112): un nodo "Vias" dentro de la plantilla, en el
## origen de la estación, que genera una curva por vía con su StationTrack y sus rieles
## (TrackBuilder). Todas van a lo largo del eje Z, de la punta A (-half_length) a la punta B
## (+half_length): la principal derecha en `main_offset` (X) y cada vía de cruce o de carga sale de
## la misma aguja con una curva en S hasta su X y vuelve a la principal en la otra punta. Los tramos
## de línea tienen que terminar en las puntas, sobre la principal (RailNetwork une a menos de 1 m).
## Las vías de cruce se habilitan en orden: `base_track_count` al empezar (contando la principal)
## y, con `grow_with_flows`, una más cada `flows_per_track` flujos que tocan la estación por encima
## de los que entran (la ciudad). Las de carga están siempre.
## En juego, en cada punta donde no llega ningún tramo pone una cola de maniobras (tarea 61b.3):
## una vía corta hacia afuera para que la locomotora pueda pasar de una vía a otra y rodear su
## tren; con `turntable`, al final de la cola hay una mesa giratoria para dar vuelta la locomotora,
## con su palanca (TurntableLever) para que el jugador gire la suya (tarea 61e).
## Si en juego ningún tramo llega a sus puntas (escenas armadas antes de la 61b), se apaga sola
## (también el AndenIsla de la plantilla) y la estación sigue siendo un punto, con un aviso. Es @tool para ver las vías en el editor; lo
## generado no se guarda en la escena.

const TRACK_MODULE_SIZE: Vector3 = Vector3(1.6, 0.2, 4.8)
## Separación de referencia entre vías: a más distancia de la principal, la curva es más larga.
const REFERENCE_SPACING: float = 7.0
const REFRESH_TIME: float = 1.0
## Un tramo que termina a menos de esto de una punta sin llegar a unirse se avisa (seguro es un error).
const NEAR_MISS: float = 30.0
const TURNTABLE_RADIUS: float = 7.0

## Media longitud de las vías: las puntas quedan en Z = -half_length y +half_length.
@export_range(20.0, 300.0, 1.0, "suffix:m") var half_length: float = 60.0:
	set(value):
		half_length = value
		_queue_build()
## Largo de la curva en S de una vía a 7 m de la principal (más lejos, más larga).
@export_range(5.0, 80.0, 1.0, "suffix:m") var turnout_length: float = 20.0:
	set(value):
		turnout_length = value
		_queue_build()
## X de la vía principal.
@export var main_offset: float = 0.0:
	set(value):
		main_offset = value
		_queue_build()
## X de cada vía de cruce, en el orden en que se habilitan.
@export var siding_offsets: PackedFloat32Array = PackedFloat32Array([7.0]):
	set(value):
		siding_offsets = value
		_queue_build()
## X de cada vía de carga (con entrada y salida propias; siempre habilitadas).
@export var freight_offsets: PackedFloat32Array = PackedFloat32Array():
	set(value):
		freight_offsets = value
		_queue_build()
## Vías habilitadas al empezar, contando la principal (sin las de carga).
@export_range(1, 10) var base_track_count: int = 2:
	set(value):
		base_track_count = value
		_queue_build()
## Suma vías de cruce según los flujos de la estación (la ciudad, D112).
@export var grow_with_flows: bool = false
## Flujos por vía que no es la principal.
@export_range(1, 10) var flows_per_track: int = 2
## Largo de las colas de maniobras de las puntas sin tramo.
@export_range(15.0, 60.0, 1.0, "suffix:m") var headshunt_length: float = 25.0
## Pone una mesa giratoria al final de cada cola de maniobras (la ciudad y la de carga, D115).
@export var turntable: bool = false

var _tracks: Array[StationTrack] = []
var _build_queued: bool = false
var _refresh_left: float = 0.0
var _connected: bool = true
# Vías habilitadas (contando la principal): no baja, como el crecimiento de los pueblos (D79).
var _enabled_count: int = 0
# Curva de una cola de maniobras -> su mesa giratoria (MeshInstance3D).
var _turntables: Dictionary = {}


func _ready() -> void:
	_build()
	if not Engine.is_editor_hint():
		# Ya está toda la escena en el árbol: se puede mirar dónde terminan los tramos.
		_check_connected()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not grow_with_flows or not _connected:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH_TIME
	refresh_enabled()


## Las vías generadas: la principal primero, después las de cruce y las de carga.
func get_tracks() -> Array[StationTrack]:
	return _tracks.duplicate()


func get_main_track() -> StationTrack:
	return _tracks[0] if not _tracks.is_empty() else null


## La mesa giratoria al final de una cola de maniobras (la curva de la cola), o null.
func get_turntable(headshunt: Path3D) -> Node3D:
	var found: Variant = _turntables.get(headshunt)
	return found if is_instance_valid(found) else null


## Dónde para la locomotora sobre la mesa (avance sobre la curva de la cola: la cola sale de la
## punta, así que el avance crece hacia afuera).
func turntable_spot(headshunt: Path3D) -> float:
	return maxf(0.0, headshunt.curve.get_baked_length() - TURNTABLE_RADIUS)


## Cuántas vías tienen que estar habilitadas ahora, contando la principal y sin las de carga.
func desired_track_count(flow_count: int) -> int:
	var max_count: int = 1 + siding_offsets.size()
	if not grow_with_flows:
		return clampi(base_track_count, 1, max_count)
	return tracks_for_flows(flow_count, base_track_count, flows_per_track, max_count)


## Cuántas vías de cruce lleva una ciudad con `flow_count` flujos (lógica pura, para las pruebas).
static func tracks_for_flows(flow_count: int, base_count: int, per_track: int, max_count: int) -> int:
	var covered: int = maxi(0, base_count - 1) * per_track
	var count: int = base_count + ceili(maxf(0.0, flow_count - covered) / float(maxi(1, per_track)))
	return clampi(count, 1, max_count)


## Las puntas de la estación (global): [punta A, punta B].
func get_ends() -> Array[Vector3]:
	var ends: Array[Vector3] = [
		to_global(Vector3(main_offset, 0.0, -half_length)),
		to_global(Vector3(main_offset, 0.0, half_length)),
	]
	return ends


## Habilita las vías de cruce que tocan según los flujos de la estación (nunca las vuelve a
## sacar). Devuelve si cambió algo.
func refresh_enabled() -> bool:
	var station_id: StringName = _station_id()
	var flows: int = 0
	if station_id != &"" and GameState.production != null:
		for flow: ProductionFlow in GameState.production.get_flows():
			if flow.from_station == station_id or flow.to_station == station_id:
				flows += 1
	return _apply_count(desired_track_count(flows))


## Cuántas vías están habilitadas, contando la principal y sin las de carga.
func get_enabled_count() -> int:
	return _enabled_count


func _apply_count(wanted: int) -> bool:
	var count: int = maxi(wanted, _enabled_count)
	_enabled_count = count
	var changed: bool = false
	var siding_index: int = 0
	for track: StationTrack in _tracks:
		var want: bool = _connected
		if track.role == StationTrack.Role.SIDING:
			siding_index += 1
			want = _connected and siding_index < count
		if track.enabled != want:
			track.enabled = want
			changed = true
	if changed and not Engine.is_editor_hint():
		var network: RailNetwork = RailNetwork.find_in(get_tree()) if is_inside_tree() else null
		if network != null:
			network.rebuild_links()
	return changed


func _queue_build() -> void:
	if not is_node_ready() or _build_queued:
		return
	_build_queued = true
	_build.call_deferred()


func _build() -> void:
	_build_queued = false
	for child: Node in get_children():
		if child is Path3D and child.has_meta(&"station_tracks"):
			remove_child(child)
			child.queue_free()
	_tracks.clear()
	_turntables.clear()
	_add_track("Principal", StationTrack.Role.MAIN, main_offset, "")
	for i: int in siding_offsets.size():
		_add_track("Cruce%d" % (i + 1), StationTrack.Role.SIDING, siding_offsets[i], "" if siding_offsets.size() == 1 else "vía de cruce %d" % (i + 1))
	for i: int in freight_offsets.size():
		_add_track("Carga%d" % (i + 1), StationTrack.Role.FREIGHT, freight_offsets[i], "" if freight_offsets.size() == 1 else "vía de carga %d" % (i + 1))
	_enabled_count = 0
	_apply_count(desired_track_count(0))


func _add_track(node_name: String, role: StationTrack.Role, x: float, label: String, curve: Curve3D = null) -> StationTrack:
	var path := Path3D.new()
	path.name = node_name
	path.set_meta(&"station_tracks", true)
	path.curve = curve if curve != null else _make_curve(x)
	var track := StationTrack.new()
	track.name = "Via"
	track.role = role
	track.display_name = label
	track.condition = 1.0
	path.add_child(track)
	var builder := TrackBuilder.new()
	builder.name = "TrackBuilder"
	var mesh := BoxMesh.new()
	mesh.size = TRACK_MODULE_SIZE
	builder.module_mesh = mesh
	builder.segment = track
	path.add_child(builder)
	add_child(path)
	_tracks.append(track)
	return track


# Una cola de maniobras desde la punta A (`at_b` en false) o B hacia afuera, con su mesa.
func _add_headshunt(at_b: bool) -> void:
	var side: float = 1.0 if at_b else -1.0
	var curve := Curve3D.new()
	curve.add_point(Vector3(main_offset, 0.0, side * half_length))
	curve.add_point(Vector3(main_offset, 0.0, side * (half_length + headshunt_length)))
	var track: StationTrack = _add_track("Cola%s" % ("B" if at_b else "A"), StationTrack.Role.HEADSHUNT, main_offset, "", curve)
	if not turntable:
		return
	var table := MeshInstance3D.new()
	table.name = "MesaGiratoria%s" % ("B" if at_b else "A")
	table.set_meta(&"station_tracks", true)
	var mesh := CylinderMesh.new()
	mesh.top_radius = TURNTABLE_RADIUS
	mesh.bottom_radius = TURNTABLE_RADIUS
	mesh.height = 0.12
	table.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.36, 0.3)
	table.material_override = material
	add_child(table)
	table.position = Vector3(main_offset, 0.02, side * (half_length + headshunt_length - TURNTABLE_RADIUS))
	_turntables[track.get_track_path()] = table
	# La palanca para que el jugador gire su locomotora (tarea 61e).
	var lever := TurntableLever.new()
	lever.name = "PalancaMesa%s" % ("B" if at_b else "A")
	lever.set_meta(&"station_tracks", true)
	lever.table = table
	lever.headshunt = track.get_track_path()
	lever.radius = TURNTABLE_RADIUS
	lever.spot = turntable_spot(track.get_track_path())
	add_child(lever)
	lever.position = Vector3(main_offset + TURNTABLE_RADIUS + 1.5, 0.0, table.position.z)


# Recta para la principal; para las otras, curva en S desde la aguja de cada punta.
func _make_curve(x: float) -> Curve3D:
	var curve := Curve3D.new()
	var start := Vector3(main_offset, 0.0, -half_length)
	var finish := Vector3(main_offset, 0.0, half_length)
	var offset: float = absf(x - main_offset)
	if offset < 0.01:
		curve.add_point(start)
		curve.add_point(finish)
		return curve
	var turnout: float = minf(turnout_length * sqrt(maxf(1.0, offset / REFERENCE_SPACING)), half_length * 0.9)
	var handle := Vector3(0.0, 0.0, turnout * 0.5)
	curve.add_point(start, Vector3.ZERO, handle)
	curve.add_point(Vector3(x, 0.0, -half_length + turnout), -handle, Vector3.ZERO)
	curve.add_point(Vector3(x, 0.0, half_length - turnout), Vector3.ZERO, handle)
	curve.add_point(finish, -handle, Vector3.ZERO)
	return curve


func _station_id() -> StringName:
	var station := get_parent() as Station
	return station.data.id if station != null and station.data != null else &""


# Si ningún tramo de línea llega a una punta, las vías se apagan y la estación queda como antes.
func _check_connected() -> void:
	if not is_inside_tree():
		return
	var ends: Array[Vector3] = get_ends()
	# Lo más cerca que quedó una punta de tramo: si está cerca pero no llega, seguro se quiso unir.
	var nearest: float = INF
	var reached: Array[bool] = [false, false]
	for node: Node in get_tree().get_nodes_in_group(TrackSegment.GROUP):
		var track := node as TrackSegment
		if track == null or track is StationTrack or track.get_track_path() == null:
			continue
		var path: Path3D = track.get_track_path()
		if path.curve == null or path.curve.point_count < 2:
			continue
		var length: float = path.curve.get_baked_length()
		for at: float in [0.0, length]:
			var tip: Vector3 = path.global_transform * path.curve.sample_baked(at)
			for i: int in ends.size():
				var gap: float = tip.distance_to(ends[i])
				nearest = minf(nearest, gap)
				if gap <= RailNetwork.JOIN_DISTANCE:
					reached[i] = true
	if nearest <= RailNetwork.JOIN_DISTANCE:
		for i: int in ends.size():
			if not reached[i]:
				_add_headshunt(i == 1)
		var network: RailNetwork = RailNetwork.find_in(get_tree())
		if network != null and network.is_built():
			for track: StationTrack in _tracks:
				network.add_track(track)
			network.rebuild_links()
		if grow_with_flows:
			refresh_enabled()
		return
	_connected = false
	_apply_count(0)
	# El andén isla de la plantilla queda entre vías que no están: se esconde (y no choca).
	var island := get_parent().get_node_or_null(^"AndenIsla") as Node3D
	if island != null:
		island.visible = false
		island.process_mode = Node.PROCESS_MODE_DISABLED
	if nearest < NEAR_MISS:
		push_warning("StationTracks de %s: el tramo más cercano termina a %.1f m de una punta (Z = ±%.0f) y no llega; la estación sigue siendo un punto como antes de la tarea 61b." % [_station_id(), nearest, half_length])
