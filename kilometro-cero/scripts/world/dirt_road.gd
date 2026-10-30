class_name DirtRoad
extends Path3D
## Camino de tierra (tarea 62c.3c): una cinta que sigue el terreno a lo largo de la curva (su y no
## importa). BiomeScatter no pone pasto encima y TrackDecor deja el hueco del paso a nivel.

const STEP: float = 3.0
const LIFT: float = 0.06

@export_range(1.0, 20.0, 0.5, "suffix:m") var width: float = 4.0
@export var color: Color = Color(0.6, 0.5, 0.36)


func _ready() -> void:
	build()


## Si un punto (global, sin mirar la altura) está sobre el camino, con `margin` de más a cada lado.
func is_on_road(global_point: Vector3, margin: float = 0.0) -> bool:
	if curve == null or curve.point_count < 2:
		return false
	var local: Vector3 = to_local(global_point)
	var closest: Vector3 = curve.get_closest_point(local)
	return Vector2(local.x - closest.x, local.z - closest.z).length() <= width * 0.5 + margin


func build() -> void:
	if curve == null or curve.point_count < 2:
		return
	var terrain := get_tree().get_first_node_in_group(Terrain.GROUP) as Terrain if is_inside_tree() else null
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length: float = curve.get_baked_length()
	var previous: Array[Vector3] = []
	for k: int in ceili(length / STEP) + 1:
		var at: float = minf(k * STEP, length)
		var point: Vector3 = curve.sample_baked(at)
		var ahead: Vector3 = curve.sample_baked(minf(at + 1.0, length)) - curve.sample_baked(maxf(at - 1.0, 0.0))
		var side: Vector3 = Vector3(-ahead.z, 0.0, ahead.x).normalized() * width * 0.5
		var current: Array[Vector3] = [_on_ground(terrain, point - side), _on_ground(terrain, point + side)]
		if not previous.is_empty():
			for corner: Vector3 in [previous[0], previous[1], current[1], previous[0], current[1], current[0]]:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(corner)
		previous = current
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var instance := get_node_or_null(^"Cinta") as MeshInstance3D
	if instance == null:
		instance = MeshInstance3D.new()
		instance.name = "Cinta"
		add_child(instance)
	instance.mesh = surface.commit()
	instance.material_override = material


# Un punto local de la curva, apoyado en el terreno (en local).
func _on_ground(terrain: Terrain, local: Vector3) -> Vector3:
	if terrain == null:
		return local
	var ground: float = terrain.height_at(to_global(local))
	if is_nan(ground):
		return local
	return to_local(Vector3(to_global(local).x, ground + LIFT, to_global(local).z))
