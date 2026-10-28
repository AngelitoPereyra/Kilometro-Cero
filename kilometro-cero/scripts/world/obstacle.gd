class_name Obstacle
extends Node3D
## Obstáculo que corta un tramo (tarea 55, D78): un árbol caído, una piedra. Mientras exista,
## el tramo queda cortado (RailNetwork.add_blocker) para la economía y las misiones; desde la
## tarea 62.3 los trenes entran igual y frenan a unos metros de él
## (RailNetwork.get_obstacle_stops); al despejarse
## (su hijo Clearable, o clear() por código) se borra y, si no queda otro obstáculo en ese
## tramo, el tramo vuelve a abrirse.
## Se apoya sobre la vía: si `segment_id` queda vacío, toma el tramo de la vía más cercana
## (a menos de `snap_distance`). Necesita un RailNetwork en la escena.

## Se despejó (justo antes de borrarse).
signal cleared

const GROUP: StringName = &"obstacles"

## Tramo que corta. Vacío: el de la vía más cercana.
@export var segment_id: StringName
## Hasta qué distancia de una vía se lo considera encima de ella (si `segment_id` está vacío).
@export_range(0.5, 50.0, 0.5, "suffix:m") var snap_distance: float = 6.0

var _network: RailNetwork
var _registered: bool = false
var _cleared: bool = false


## La vía más cercana a `point` (en el mundo) a menos de `max_distance`, o null.
static func find_track_near(tree: SceneTree, point: Vector3, max_distance: float) -> TrackSegment:
	var best: TrackSegment = null
	var best_distance: float = max_distance
	for node: Node in tree.get_nodes_in_group(TrackSegment.GROUP):
		var track := node as TrackSegment
		if track == null:
			continue
		var path: Path3D = track.get_track_path()
		if path == null or path.curve == null or path.curve.point_count < 2:
			continue
		var local: Vector3 = path.to_local(point)
		var closest: Vector3 = path.to_global(path.curve.get_closest_point(local))
		var distance: float = closest.distance_to(point)
		if distance <= best_distance:
			best = track
			best_distance = distance
	return best


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	# Diferido: las vías y la red tienen que estar en el árbol.
	_register.call_deferred()


func _exit_tree() -> void:
	_unregister()


## Si está cortando un tramo ahora.
func is_blocking() -> bool:
	return _registered


func get_network() -> RailNetwork:
	return _network


## Lo despeja: avisa, libera el tramo y se borra. Lo llama su Clearable al terminar.
func clear() -> void:
	if _cleared:
		return
	_cleared = true
	var cut_segment: StringName = segment_id
	_unregister()
	cleared.emit()
	EventBus.obstacle_cleared.emit(cut_segment)
	queue_free()


## El Clearable hijo, o null (un obstáculo sin él solo se despeja por código, por ejemplo
## con una misión).
func get_clearable() -> Clearable:
	for child: Node in get_children():
		var clearable := child as Clearable
		if clearable != null:
			return clearable
	return null


func _register() -> void:
	if _registered or _cleared or not is_inside_tree():
		return
	_network = RailNetwork.find_in(get_tree())
	if _network == null:
		push_warning("Obstacle %s: no hay un RailNetwork en la escena, así que no corta ningún tramo." % name)
		return
	if segment_id == &"":
		var track: TrackSegment = find_track_near(get_tree(), global_position, snap_distance)
		if track == null:
			push_warning("Obstacle %s: no hay ninguna vía a menos de %.1f m; no corta nada." % [name, snap_distance])
			return
		segment_id = track.segment_id
	_registered = _network.add_blocker(segment_id, self)
	if not _registered:
		push_warning("Obstacle %s: el tramo '%s' no existe en la red." % [name, segment_id])


func _unregister() -> void:
	if not _registered:
		return
	_registered = false
	if is_instance_valid(_network):
		_network.remove_blocker(segment_id, self)
