@tool
class_name TerrainCarve
extends Path3D
## Un arroyo que el Terrain cava (tarea 62c.3c): la curva va por la orilla (su y es la altura del
## campo); el terreno baja hasta `depth` debajo, con un cauce de `half_width` y barrancas de
## `bank_width`, aunque haya una vía encima (por eso la vía lo cruza con un puente). Se dibuja el
## agua como una cinta. Después de mover la curva en el editor hay que rehacer el terreno.

const WATER_NODE_NAME: String = "Agua"
const WATER_STEP: float = 4.0

@export_range(0.5, 30.0, 0.5, "suffix:m") var depth: float = 3.5
@export_range(0.5, 40.0, 0.5, "suffix:m") var half_width: float = 4.0
@export_range(1.0, 80.0, 0.5, "suffix:m") var bank_width: float = 10.0
## Altura del agua sobre el fondo del cauce.
@export_range(0.0, 30.0, 0.1, "suffix:m") var water_depth: float = 1.4
@export var water_color: Color = Color(0.32, 0.45, 0.5, 0.85)


func _ready() -> void:
	build_water()


## Hasta dónde llega lo que cava, desde la curva.
func get_reach() -> float:
	return half_width + bank_width


## Lógica pura: cuánto queda de la altura del campo a esa distancia de la curva (0 en el cauce, 1
## pasada la barranca).
static func carve_weight(distance: float, half: float, bank: float) -> float:
	return smoothstep(half, half + bank, distance)


## La cinta de agua a lo largo de la curva.
func build_water() -> void:
	if curve == null or curve.point_count < 2:
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length: float = curve.get_baked_length()
	var steps: int = ceili(length / WATER_STEP)
	var width: float = half_width + 1.0
	var previous: Array[Vector3] = []
	for k: int in steps + 1:
		var at: float = minf(k * WATER_STEP, length)
		var point: Vector3 = curve.sample_baked(at)
		var ahead: Vector3 = curve.sample_baked(minf(at + 1.0, length)) - curve.sample_baked(maxf(at - 1.0, 0.0))
		var side: Vector3 = Vector3(-ahead.z, 0.0, ahead.x).normalized() * width
		var water: Vector3 = point + Vector3.DOWN * (depth - water_depth)
		var current: Array[Vector3] = [water - side, water + side]
		if not previous.is_empty():
			for corner: Vector3 in [previous[0], previous[1], current[1], previous[0], current[1], current[0]]:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(corner)
		previous = current
	var material := StandardMaterial3D.new()
	material.albedo_color = water_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.15
	var instance: MeshInstance3D = get_node_or_null(WATER_NODE_NAME) as MeshInstance3D
	if instance == null:
		instance = MeshInstance3D.new()
		instance.name = WATER_NODE_NAME
		add_child(instance)
	instance.mesh = surface.commit()
	instance.material_override = material
