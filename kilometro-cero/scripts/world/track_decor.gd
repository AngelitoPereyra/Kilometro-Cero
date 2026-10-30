class_name TrackDecor
extends Node3D
## Lo que acompaña a la vía (tarea 62c.3b, D136): postes de telégrafo con dos cables que cuelgan,
## alambrados a los dos lados y mojones de kilómetro. Va como hijo del Path3D de un tramo y se pone
## solo a lo largo de la curva, apoyado en el terreno. Deja libres las estaciones, los lotes, los
## caminos (el paso a nivel), los arroyos (el puente) y las otras vías (el ramal que sale en Y de un
## empalme, tarea 62c.3d). Los kilómetros son reales (D135: 20 km por cada km de maqueta).

const POLE_HEIGHT: float = 7.0
const ARM_WIDTH: float = 1.6
const POST_HEIGHT: float = 1.3
const FENCE_STRANDS: Array[float] = [0.4, 0.75, 1.1]
const WIRE_SAG: float = 0.6
const WIRE_SEGMENTS: int = 6
const CLEAR_MARGIN: float = 2.0
## Lo más cerca que puede quedar algo de otra vía (la que sale de un empalme).
const OTHER_TRACK_CLEARANCE: float = 5.0

## Lado de los postes de telégrafo respecto de hacia dónde va la curva (1 o -1).
@export_range(-1, 1, 2) var pole_side: int = -1
@export_range(2.0, 40.0, 0.5, "suffix:m") var pole_offset: float = 7.0
@export_range(10.0, 200.0, 1.0, "suffix:m") var pole_spacing: float = 50.0
@export_range(2.0, 40.0, 0.5, "suffix:m") var fence_offset: float = 11.0
@export_range(1.0, 20.0, 0.5, "suffix:m") var post_spacing: float = 5.0
@export_range(20.0, 2000.0, 5.0, "suffix:m") var milestone_spacing: float = 250.0
@export var km_per_meter: float = 0.02
## Kilómetro del comienzo de la curva (el de la cabecera).
@export var start_km: float = 0.0

var _poles: PackedVector3Array = PackedVector3Array()
var _posts: PackedVector3Array = PackedVector3Array()
var _milestones: Array[Dictionary] = []
var _terrain: Terrain
var _blockers: Array[Node3D] = []
var _other_tracks: Array[Path3D] = []


func _ready() -> void:
	build()


func get_pole_positions() -> PackedVector3Array:
	return _poles


func get_post_positions() -> PackedVector3Array:
	return _posts


## [{position: Vector3, km: int}]
func get_milestones() -> Array[Dictionary]:
	return _milestones


## Lógica pura: el kilómetro real a esa distancia del comienzo.
static func km_at(offset: float, start: float, per_meter: float) -> int:
	return roundi(start + offset * per_meter)


func build() -> void:
	for child: Node in get_children():
		child.queue_free()
	_poles.clear()
	_posts.clear()
	_milestones.clear()
	var path := get_parent() as Path3D
	if path == null or path.curve == null or path.curve.point_count < 2:
		return
	_terrain = get_tree().get_first_node_in_group(Terrain.GROUP) as Terrain
	_collect_blockers()
	var curve: Curve3D = path.curve
	var length: float = curve.get_baked_length()
	var pole_transforms: Array[Transform3D] = []
	var arm_ends: Array = []
	var at: float = pole_spacing * 0.5
	while at < length:
		var frame: Transform3D = _frame(path, at)
		var spot: Vector3 = _ground(frame.origin + frame.basis.x * pole_offset * pole_side)
		if _is_free(spot):
			_poles.append(spot)
			pole_transforms.append(Transform3D(frame.basis, spot))
			var top: Vector3 = spot + Vector3.UP * (POLE_HEIGHT - 0.4)
			arm_ends.append([top - frame.basis.x * ARM_WIDTH * 0.45, top + frame.basis.x * ARM_WIDTH * 0.45, at])
		else:
			arm_ends.append(null)
		at += pole_spacing
	var post_transforms: Array[Transform3D] = []
	var strands: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
	at = 0.0
	while at < length:
		var frame: Transform3D = _frame(path, at)
		for side_index: int in 2:
			var side: float = 1.0 if side_index == 0 else -1.0
			var spot: Vector3 = _ground(frame.origin + frame.basis.x * fence_offset * side)
			if _is_free(spot):
				_posts.append(spot)
				post_transforms.append(Transform3D(frame.basis, spot))
				strands[side_index].append(spot)
			else:
				strands[side_index].append(Vector3(NAN, NAN, NAN))
		at += post_spacing
	at = milestone_spacing
	while at < length:
		var frame: Transform3D = _frame(path, at)
		var spot: Vector3 = _ground(frame.origin + frame.basis.x * 3.5 * pole_side)
		if _is_free(spot):
			_add_milestone(spot, frame.basis, km_at(at, start_km, km_per_meter))
		at += milestone_spacing
	_add_multimesh("Postes", _cylinder(0.1, 0.14, POLE_HEIGHT), Vector3(0.0, POLE_HEIGHT * 0.5, 0.0), pole_transforms, Color(0.36, 0.27, 0.18))
	_add_multimesh("Crucetas", _box(Vector3(ARM_WIDTH, 0.1, 0.1)), Vector3(0.0, POLE_HEIGHT - 0.4, 0.0), pole_transforms, Color(0.36, 0.27, 0.18))
	_add_multimesh("PostesAlambrado", _cylinder(0.05, 0.06, POST_HEIGHT), Vector3(0.0, POST_HEIGHT * 0.5, 0.0), post_transforms, Color(0.45, 0.36, 0.25))
	_add_lines("Cables", _telegraph_lines(arm_ends), Color(0.12, 0.12, 0.12))
	_add_lines("Alambres", _fence_lines(strands), Color(0.35, 0.35, 0.35))


func _telegraph_lines(arm_ends: Array) -> PackedVector3Array:
	var lines := PackedVector3Array()
	for index: int in range(1, arm_ends.size()):
		if arm_ends[index] == null or arm_ends[index - 1] == null:
			continue
		for wire: int in 2:
			var from: Vector3 = arm_ends[index - 1][wire]
			var to: Vector3 = arm_ends[index][wire]
			for segment: int in WIRE_SEGMENTS:
				lines.append(_sagged(from, to, float(segment) / WIRE_SEGMENTS))
				lines.append(_sagged(from, to, float(segment + 1) / WIRE_SEGMENTS))
	return lines


func _fence_lines(strands: Array[PackedVector3Array]) -> PackedVector3Array:
	var lines := PackedVector3Array()
	for strand: PackedVector3Array in strands:
		for index: int in range(1, strand.size()):
			if is_nan(strand[index].x) or is_nan(strand[index - 1].x):
				continue
			for height: float in FENCE_STRANDS:
				lines.append(strand[index - 1] + Vector3.UP * height)
				lines.append(strand[index] + Vector3.UP * height)
	return lines


## Lógica pura: un punto del cable entre dos postes, colgado en el medio.
static func _sagged(from: Vector3, to: Vector3, t: float) -> Vector3:
	return from.lerp(to, t) + Vector3.DOWN * WIRE_SAG * 4.0 * t * (1.0 - t)


func _add_milestone(spot: Vector3, facing: Basis, km: int) -> void:
	var stone := MeshInstance3D.new()
	stone.name = "Mojon%d" % km
	stone.mesh = _box(Vector3(0.3, 0.7, 0.2))
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.9, 0.88, 0.82)
	stone.material_override = material
	add_child(stone)
	stone.global_transform = Transform3D(facing, spot + Vector3.UP * 0.35)
	var label := Label3D.new()
	label.text = "km %d" % km
	label.font_size = 40
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	stone.add_child(label)
	label.position = Vector3(0.0, 0.7, 0.0)
	_milestones.append({"position": spot, "km": km})


func _add_multimesh(node_name: String, mesh: Mesh, offset: Vector3, transforms: Array[Transform3D], color: Color) -> void:
	if transforms.is_empty():
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.append_from(mesh, 0, Transform3D(Basis.IDENTITY, offset))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = surface.commit()
	multimesh.instance_count = transforms.size()
	var to_local_space: Transform3D = global_transform.affine_inverse()
	for index: int in transforms.size():
		multimesh.set_instance_transform(index, to_local_space * transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	instance.material_override = material
	add_child(instance)


func _add_lines(node_name: String, points: PackedVector3Array, color: Color) -> void:
	if points.is_empty():
		return
	var to_local_space: Transform3D = global_transform.affine_inverse()
	var local := PackedVector3Array()
	local.resize(points.size())
	for index: int in points.size():
		local[index] = to_local_space * points[index]
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = local
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	add_child(instance)


# Marco global en ese punto de la curva: x al costado, z hacia donde va, y arriba.
func _frame(path: Path3D, at: float) -> Transform3D:
	var curve: Curve3D = path.curve
	var length: float = curve.get_baked_length()
	var point: Vector3 = path.to_global(curve.sample_baked(at))
	var ahead: Vector3 = path.to_global(curve.sample_baked(minf(at + 1.0, length))) - path.to_global(curve.sample_baked(maxf(at - 1.0, 0.0)))
	ahead.y = 0.0
	if ahead.length() < 0.001:
		ahead = Vector3.FORWARD
	ahead = ahead.normalized()
	var right: Vector3 = Vector3.UP.cross(ahead).normalized()
	return Transform3D(Basis(right, Vector3.UP, ahead), point)


func _ground(point: Vector3) -> Vector3:
	if _terrain == null:
		return point
	var ground: float = _terrain.height_at(point)
	return Vector3(point.x, ground, point.z) if not is_nan(ground) else point


func _collect_blockers() -> void:
	_blockers.clear()
	var root: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	var owner_scene: Node = owner if owner != null else root
	_other_tracks.clear()
	var own: Node = get_parent()
	for node: Node in owner_scene.find_children("*", "", true, false):
		if node is Station or node is TrackLot or node is DirtRoad:
			_blockers.append(node as Node3D)
		elif node is TrackBuilder and node.get_parent() != own and node.get_parent() is Path3D:
			var other := node.get_parent() as Path3D
			if other.curve != null and other.curve.point_count >= 2 and not _other_tracks.has(other):
				_other_tracks.append(other)


# Fuera de estaciones, lotes, caminos, arroyos y otras vías.
func _is_free(spot: Vector3) -> bool:
	if _terrain != null and _terrain.is_carved(spot):
		return false
	for other: Path3D in _other_tracks:
		var closest: Vector3 = other.to_global(other.curve.get_closest_point(other.to_local(spot)))
		if Vector2(closest.x - spot.x, closest.z - spot.z).length() < OTHER_TRACK_CLEARANCE:
			return false
	for blocker: Node3D in _blockers:
		if blocker is DirtRoad:
			if (blocker as DirtRoad).is_on_road(spot, CLEAR_MARGIN + 2.0):
				return false
			continue
		var half: Vector2 = (_terrain.station_flat_size * 0.5 if _terrain != null else Vector2(60.0, 130.0)) if blocker is Station else (blocker as TrackLot).get_size() * 0.5
		var inside: Vector3 = blocker.global_transform.affine_inverse() * spot
		if Terrain.rect_distance(Vector2(inside.x, inside.z), half + Vector2.ONE * CLEAR_MARGIN) <= 0.0:
			return false
	return true


static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 6
	mesh.rings = 1
	return mesh


static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh
