@tool
class_name ManualTrack
extends Path3D
## Vía hecha a mano (D13): un Path3D con ayudas para armarla y verla.
## Es @tool para que el botón del inspector y la línea de depuración funcionen
## dentro del editor, no solo al ejecutar el juego.

const DEBUG_LINE_NAME: String = "DebugLine"
# La línea se eleva un poco para que no quede pegada al piso y titile (z-fighting).
const DEBUG_LINE_LIFT: float = 0.05

## Largo del tramo que genera el botón. Cambiarlo no mueve la curva ya creada:
## hay que volver a tocar el botón.
@export_range(10.0, 5000.0, 1.0, "suffix:m") var length_m: float = 200.0

## Dibuja una línea naranja sobre la curva para verla también al ejecutar el juego.
@export var show_debug_line: bool = true:
	set(value):
		show_debug_line = value
		_refresh_debug_line()

## Botón del inspector: reemplaza la curva por una recta de `length_m` metros.
@export_tool_button("Generar tramo recto", "Curve3D") var generate_button: Callable = generate_straight


func _ready() -> void:
	# Si la escena se guardó sin curva, arrancamos con una recta para que
	# nunca haya un Path3D vacío.
	if curve == null:
		generate_straight()
	# Al mover un punto a mano en el editor, la línea se actualiza sola.
	if not curve_changed.is_connected(_refresh_debug_line):
		curve_changed.connect(_refresh_debug_line)
	_refresh_debug_line()


func generate_straight() -> void:
	var new_curve := Curve3D.new()
	# En Godot "adelante" es -Z: la vía corre hacia el fondo de la escena.
	new_curve.add_point(Vector3.ZERO)
	new_curve.add_point(Vector3(0.0, 0.0, -length_m))
	curve = new_curve
	_refresh_debug_line()


# Es idempotente: reutiliza el mismo nodo hijo y solo cambia su malla.
# No le asignamos `owner`, así que la línea no se guarda en el .tscn.
func _refresh_debug_line() -> void:
	if not is_inside_tree():
		return
	var line := get_node_or_null(DEBUG_LINE_NAME) as MeshInstance3D
	if line == null:
		line = MeshInstance3D.new()
		line.name = DEBUG_LINE_NAME
		add_child(line)
	if not show_debug_line or curve == null or curve.point_count < 2:
		line.mesh = null
		return
	line.mesh = _build_line_mesh()


func _build_line_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point: Vector3 in curve.get_baked_points():
		mesh.surface_add_vertex(point + Vector3.UP * DEBUG_LINE_LIFT)
	mesh.surface_end()

	var material := StandardMaterial3D.new()
	# Sin sombreado: el color se ve igual con cualquier luz.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.ORANGE_RED
	mesh.surface_set_material(0, material)
	return mesh
