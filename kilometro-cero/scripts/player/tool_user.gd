class_name ToolUser
extends Node
## Usa las herramientas clave (tarea 55, D83 y D91): con el clic izquierdo (`use_tool`) golpea
## lo más cercano que se pueda trabajar (un ToolTarget: Clearable u Harvestable) si el jugador
## tiene la herramienta que pide. No hay que elegirla: tenerla alcanza.
## Hijo directo de Player. No actúa en la cabina ni con los controles apagados.

## Cada golpe que se dio. `finished` es true si con ese golpe se terminó.
signal used(target: ToolTarget, finished: bool)
## No se pudo: &"nothing_near" o &"missing_tool" (con el nombre de la herramienta que falta).
signal use_failed(reason: StringName, tool_name: String)

## Tiempo mínimo entre golpes con el clic (solo para la entrada del jugador).
@export_range(0.0, 2.0, 0.05, "suffix:s") var swing_seconds: float = 0.35

var _player: Player
var _last_swing_ms: int = -100000


## Texto para la interfaz. Lógica pura.
static func failure_text(reason: StringName, tool_name: String) -> String:
	match reason:
		&"nothing_near":
			return "No hay nada para trabajar cerca."
		&"missing_tool":
			return "Hace falta: %s." % tool_name
	return ""


## El más cercano de `targets` disponible y al alcance desde `point`, o null.
static func nearest_target(targets: Array[ToolTarget], point: Vector3) -> ToolTarget:
	var best: ToolTarget = null
	var best_distance: float = INF
	for target: ToolTarget in targets:
		if target == null or not target.is_available() or not target.can_reach(point):
			continue
		var distance: float = target.horizontal_distance_to(point)
		if distance < best_distance:
			best = target
			best_distance = distance
	return best


func _ready() -> void:
	_player = get_parent() as Player
	if _player == null:
		push_error("ToolUser debe ser hijo directo de un Player.")
		set_process_unhandled_input(false)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"use_tool"):
		return
	if not _player.controls_enabled or _player.is_in_cab():
		return
	var now: int = Time.get_ticks_msec()
	if float(now - _last_swing_ms) / 1000.0 < swing_seconds:
		return
	_last_swing_ms = now
	try_use()


## Lo que golpearía ahora (lo más cercano al alcance), o null.
func find_target() -> ToolTarget:
	var targets: Array[ToolTarget] = []
	for node: Node in get_tree().get_nodes_in_group(ToolTarget.GROUP):
		var target := node as ToolTarget
		if target != null:
			targets.append(target)
	return nearest_target(targets, _player.global_position)


## Da un golpe. Devuelve false (y avisa por `use_failed`) si no había nada o falta la herramienta.
func try_use() -> bool:
	var target: ToolTarget = find_target()
	if target == null:
		use_failed.emit(&"nothing_near", "")
		return false
	var key_items: KeyItems = _player.get_key_items()
	if key_items == null or not key_items.has(target.get_required_tool_id()):
		use_failed.emit(&"missing_tool", target.get_required_tool_name())
		return false
	var tool_id: StringName = target.get_required_tool_id()
	var done: bool = target.hit()
	EventBus.tool_used.emit(tool_id)
	used.emit(target, done)
	return true
