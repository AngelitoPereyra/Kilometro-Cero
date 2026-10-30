class_name HorizonRing
extends MeshInstance3D
## Horizonte (tarea 62c.3c, D136): un anillo de lomas y sierras lejanas alrededor del Terrain, que
## con la niebla del ambiente tapa el borde de la maqueta (nunca se ve la mesa, sección 3 del GDD).
## Sale del borde del terreno a su altura, sube a las lomas a `margin` metros y baja por detrás.
## Del lado sur (z menor que `sierra_from_z`) son más altas: las sierras de Tandilia.

const STEP: float = 40.0

@export_range(50.0, 3000.0, 10.0, "suffix:m") var margin: float = 450.0
@export_range(0.0, 500.0, 1.0, "suffix:m") var hill_height: float = 35.0
@export_range(0.0, 500.0, 1.0, "suffix:m") var sierra_height: float = 110.0
@export var sierra_from_z: float = -1800.0
@export var near_color: Color = Color(0.43, 0.52, 0.36)
@export var far_color: Color = Color(0.55, 0.6, 0.66)
@export var noise_seed: int = 7


func _ready() -> void:
	build()


## Lógica pura: la altura de las lomas del horizonte en ese punto del borde.
static func hill_at(noise: FastNoiseLite, point: Vector2, base: float, sierra: float, sierra_z: float) -> float:
	var wave: float = noise.get_noise_2d(point.x, point.y) * 0.5 + 0.5
	var high: float = smoothstep(sierra_z, sierra_z - 600.0, point.y)
	return base * (0.4 + wave) + sierra * high * (0.5 + wave * 0.8)


func build() -> void:
	var terrain := get_tree().get_first_node_in_group(Terrain.GROUP) as Terrain if is_inside_tree() else null
	if terrain == null:
		return
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = 0.004
	var half: Vector2 = terrain.size * 0.5 - Vector2.ONE * 2.0
	var center := Vector2(terrain.global_position.x, terrain.global_position.z)
	var border: Array[Vector2] = _rectangle(center, half)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array[Array] = []
	for index: int in border.size():
		var inner: Vector2 = border[index]
		var outward: Vector2 = _outward(border, index)
		var ground: float = terrain.height_at(Vector3(inner.x, 0.0, inner.y))
		ground = 0.0 if is_nan(ground) else ground
		var crest: Vector2 = inner + outward * margin
		var behind: Vector2 = inner + outward * margin * 1.8
		var top: float = hill_at(noise, crest, hill_height, sierra_height, sierra_from_z)
		rows.append([Vector3(inner.x, ground, inner.y), Vector3(crest.x, maxf(top, ground), crest.y), Vector3(behind.x, -40.0, behind.y)])
	var colors: Array[Color] = [near_color, near_color.lerp(far_color, 0.7), far_color]
	for index: int in rows.size():
		var current: Array = rows[index]
		var following: Array = rows[(index + 1) % rows.size()]
		for band: int in 2:
			var quad: Array[int] = [0, 1, 2, 0, 2, 3]
			var corners: Array[Vector3] = [current[band], following[band], following[band + 1], current[band + 1]]
			var shades: Array[Color] = [colors[band], colors[band], colors[band + 1], colors[band + 1]]
			for corner: int in quad:
				surface.set_color(shades[corner])
				surface.add_vertex(to_local(corners[corner]))
	surface.generate_normals()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	mesh = surface.commit()
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# El borde del terreno, de a STEP metros, dando la vuelta.
func _rectangle(center: Vector2, half: Vector2) -> Array[Vector2]:
	var corners: Array[Vector2] = [center + Vector2(-half.x, -half.y), center + Vector2(half.x, -half.y), center + Vector2(half.x, half.y), center + Vector2(-half.x, half.y)]
	var points: Array[Vector2] = []
	for side: int in 4:
		var from: Vector2 = corners[side]
		var to: Vector2 = corners[(side + 1) % 4]
		var steps: int = maxi(ceili(from.distance_to(to) / STEP), 1)
		for k: int in steps:
			points.append(from.lerp(to, float(k) / steps))
	return points


# Hacia afuera en ese punto del borde (en las esquinas, en diagonal).
func _outward(border: Array[Vector2], index: int) -> Vector2:
	var before: Vector2 = border[(index - 1 + border.size()) % border.size()]
	var after: Vector2 = border[(index + 1) % border.size()]
	var along: Vector2 = (after - before).normalized()
	return Vector2(along.y, -along.x)
