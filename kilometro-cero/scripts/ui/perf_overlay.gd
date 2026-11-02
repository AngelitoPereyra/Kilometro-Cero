class_name PerfOverlay
extends CanvasLayer
## Medidor de rendimiento (tarea 62c.3f): F3 (acción `debug_stats`) muestra arriba a la izquierda
## los cuadros por segundo, cuánto tarda cada parte del cuadro, las llamadas de dibujo y lo que hay
## en la escena (nodos, vehículos, personajes). Sirve para ver qué crece con los días y causa
## tirones. Lo suma la escena del Hito A; anda también con el juego en pausa.

const REFRESH_TIME: float = 0.5

var _label: Label
var _left: float = 0.0
# El peor cuadro desde el último refresco (ms).
var _worst_ms: float = 0.0


## Lógica pura: el texto del medidor con esos números.
static func format_stats(stats: Dictionary) -> String:
	var lines: PackedStringArray = [
		"%d cuadros/s · peor cuadro %.0f ms" % [stats.get("fps", 0), stats.get("worst_ms", 0.0)],
		"Proceso %.1f ms · física %.1f ms" % [stats.get("process_ms", 0.0), stats.get("physics_ms", 0.0)],
		"Dibujo: %d llamadas · %d objetos · %d mil triángulos" % [stats.get("draw_calls", 0), stats.get("objects", 0), int(stats.get("primitives", 0) / 1000.0)],
		"Nodos %d · vehículos %d (%d a la vista) · personajes %d" % [stats.get("nodes", 0), stats.get("vehicles", 0), stats.get("vehicles_visible", 0), stats.get("figures", 0)],
	]
	return "\n".join(lines)


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.position = Vector2(12.0, 12.0)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.85))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_label.add_theme_constant_override("outline_size", 5)
	add_child(_label)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action(&"debug_stats") and event.is_action_pressed(&"debug_stats"):
		visible = not visible
		_left = 0.0
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_worst_ms = maxf(_worst_ms, delta * 1000.0)
	if not visible:
		return
	_left -= delta
	if _left > 0.0:
		return
	_left = REFRESH_TIME
	_label.text = format_stats(collect())
	_worst_ms = 0.0


## Los números de ahora.
func collect() -> Dictionary:
	var vehicles: Array[Node] = get_tree().get_nodes_in_group(Vehicle.GROUP)
	var shown: int = 0
	for node: Node in vehicles:
		if (node as Node3D).is_visible_in_tree():
			shown += 1
	return {
		"fps": int(Performance.get_monitor(Performance.TIME_FPS)),
		"worst_ms": _worst_ms,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"vehicles": vehicles.size(),
		"vehicles_visible": shown,
		"figures": get_tree().get_nodes_in_group(BigHeadFigure.GROUP).size(),
	}
