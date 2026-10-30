@tool
class_name TrackBuilder
extends Node3D
## Repite un módulo recto de vía a lo largo de la curva del Path3D padre (D31).
## Las curvas salen gratis: cada módulo se orienta según la curva en su punto.
## Es @tool para ver el resultado dentro del editor mientras armás la escena.
##
## Usa un MultiMesh: dibuja todos los módulos con una sola llamada a la GPU.
## Con cientos de módulos por tramo, un nodo por módulo sería mucho más caro (D15).

const MODULES_NODE_NAME: String = "Modules"
# Tolerancia para que un error de redondeo al medir la curva (199.9999 m en vez de
# 200 m) no haga perder el último módulo.
const LENGTH_EPSILON_M: float = 0.001
# Colores del placeholder (riel y óxido de Palette, tarea 62c.3e). El módulo definitivo usará un
# parámetro "wear" en su shader. Cambia su propio color: LookPainter no lo repinta (KEEP_META).
const COLOR_HEALTHY: Color = Color(0.357, 0.376, 0.408)
const COLOR_WORN: Color = Color(0.541, 0.290, 0.165)

## Malla del módulo recto. Su origen va en el centro del módulo y su largo corre por el eje Z.
@export var module_mesh: Mesh:
	set(value):
		module_mesh = value
		rebuild()

## Largo de cada módulo sobre la curva.
@export_range(1.0, 50.0, 0.1, "suffix:m") var module_length: float = 5.0:
	set(value):
		module_length = value
		rebuild()

## Material opcional. Si queda vacío se usa uno gris que se tiñe de óxido con el desgaste.
@export var module_material: Material:
	set(value):
		module_material = value
		rebuild()

## De acá se lee el desgaste. Cuando su condición cambia, se actualiza el color.
@export var segment: TrackSegment:
	set(value):
		if segment != null and segment.condition_changed.is_connected(_on_condition_changed):
			segment.condition_changed.disconnect(_on_condition_changed)
		segment = value
		if segment != null:
			segment.condition_changed.connect(_on_condition_changed)
		_apply_wear()
		update_configuration_warnings()

var _path: Path3D
# Copia propia del material: si teñiéramos el recurso compartido, todos los tramos
# del juego cambiarían de color a la vez (el mismo problema de D33).
var _material: Material


## Cuántos módulos enteros entran en un tramo. Un resto menor a un módulo queda sin rieles.
static func module_count(track_length: float, module_size: float) -> int:
	if module_size <= 0.0 or track_length <= 0.0:
		return 0
	return floori((track_length + LENGTH_EPSILON_M) / module_size)


## Distancia desde el inicio de la curva hasta el centro del módulo `index`.
static func module_offset(index: int, module_size: float) -> float:
	return (index + 0.5) * module_size


func _ready() -> void:
	_path = get_parent() as Path3D
	if _path != null and not _path.curve_changed.is_connected(rebuild):
		# Al mover un punto de la curva en el editor, los módulos se regeneran solos.
		_path.curve_changed.connect(rebuild)
	rebuild()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not (get_parent() is Path3D):
		warnings.append("TrackBuilder debe ser hijo de un Path3D (por ejemplo ManualTrack).")
	if module_mesh == null:
		warnings.append("Asigná una malla en Module Mesh.")
	if segment == null:
		warnings.append("Asigná un TrackSegment en Segment: de ahí sale el desgaste.")
	return warnings


## Regenera todos los módulos. Se llama sola cuando cambia algo; no hace falta llamarla a mano.
func rebuild() -> void:
	# Los setters de los @export corren al cargar la escena, antes de _ready().
	if not is_node_ready():
		return
	var instance: MultiMeshInstance3D = _get_or_create_modules()
	var curve: Curve3D = _path.curve if _path != null else null
	if curve == null or curve.point_count < 2 or module_mesh == null:
		instance.multimesh = null
		update_configuration_warnings()
		return

	var count: int = module_count(curve.get_baked_length(), module_length)
	var multimesh := MultiMesh.new()
	# El formato se define antes de la cantidad: cambiarlo después borra las instancias.
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = module_mesh
	multimesh.instance_count = count
	for i: int in count:
		# Posición y orientación de la curva en el centro del módulo.
		multimesh.set_instance_transform(i, curve.sample_baked_with_rotation(module_offset(i, module_length), true))
	instance.multimesh = multimesh

	_material = _make_material()
	instance.material_override = _material
	_apply_wear()
	update_configuration_warnings()


## Nodo que dibuja los módulos (lo usa la escena de prueba). Null si todavía no se generó.
func get_modules_instance() -> MultiMeshInstance3D:
	return get_node_or_null(MODULES_NODE_NAME) as MultiMeshInstance3D


# Mismo criterio que la línea de ManualTrack: se reutiliza el nodo y no se le asigna
# `owner`, así que no se guarda en el .tscn: se regenera cada vez.
func _get_or_create_modules() -> MultiMeshInstance3D:
	var instance: MultiMeshInstance3D = get_modules_instance()
	if instance == null:
		instance = MultiMeshInstance3D.new()
		instance.name = MODULES_NODE_NAME
		instance.set_meta(LookPainter.KEEP_META, true)
		add_child(instance)
	return instance


func _make_material() -> Material:
	if module_material != null:
		return module_material.duplicate() as Material
	var placeholder := StandardMaterial3D.new()
	placeholder.albedo_color = COLOR_HEALTHY
	return placeholder


func _on_condition_changed(_condition: float) -> void:
	_apply_wear()


func _apply_wear() -> void:
	if _material == null or segment == null:
		return
	var wear: float = segment.get_wear()
	var standard := _material as StandardMaterial3D
	if standard != null:
		standard.albedo_color = COLOR_HEALTHY.lerp(COLOR_WORN, wear)
		return
	var custom := _material as ShaderMaterial
	if custom != null:
		custom.set_shader_parameter(&"wear", wear)
