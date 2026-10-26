class_name StationBoard
extends Interactable
## Tablero de una estación (D80, tarea 58): nodo "Tablero" de las plantillas de estación (hijo
## directo o nieto de la Station). Muestra el estado del lugar en su Label3D "Texto": nivel,
## crecimiento, las misiones principales con sus pasos, las secundarias y lo que se puede
## entregar. Nada se descarga solo: F en el tablero aprueba la entrega, que saca de los vagones
## de los trenes detenidos en la estación, de la mano y de la mochila del jugador solo lo que
## piden las misiones (en ese orden; de la mano, solo si se entrega todo lo que sostiene).
## Lo que hay al alcance lo junta StationGoods (tarea 59, lo comparte con el mercado).

## Se aprobó una entrega: id de objeto -> unidades entregadas.
signal delivered(amounts: Dictionary[StringName, int])

const TEXT_PATH: NodePath = ^"Texto"
## Cada cuánto (s) se vuelve a escribir el texto.
const REFRESH_TIME: float = 0.5
## Cuánto (s) queda a la vista el aviso de la última entrega.
const MESSAGE_TIME: float = 4.0

var _station: Station
var _label: Label3D
var _timer: float = 0.0
var _message: String = ""
var _message_left: float = 0.0


func _ready() -> void:
	_station = _find_station()
	_label = get_node_or_null(TEXT_PATH) as Label3D
	if Engine.is_editor_hint():
		return
	if _station == null:
		push_warning("StationBoard %s: no está dentro de una Station." % name)
	update_text()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			_message = ""
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH_TIME
		update_text()


func get_station() -> Station:
	return _station


func get_prompt() -> String:
	var plan: Dictionary[StringName, int] = get_delivery_plan()
	return "Entregar " + _amounts_text(plan) if not plan.is_empty() else "Mirar el tablero"


## Lo que hay para entregar ahora: vagones de los trenes detenidos, la mano y la mochila del
## jugador (id de objeto -> unidades). `player` null: el que esté en la zona de la estación.
func get_available(player: Player = null) -> Dictionary[StringName, int]:
	return StationGoods.new(_station, player).get_available()


## Lo que aceptarían las misiones de lo disponible (lo que entregaría F ahora).
func get_delivery_plan(player: Player = null) -> Dictionary[StringName, int]:
	if _station == null:
		return {}
	return GameState.missions.plan_delivery(_station.get_station_id(), get_available(player))


## Aprueba la entrega: saca lo del plan (vagones, mano y mochila, en ese orden), lo
## entrega a las misiones y lo avisa (EventBus.contribution_delivered). Devuelve lo entregado.
func deliver(player: Player = null) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	if _station == null:
		return result
	var station_id: StringName = _station.get_station_id()
	var goods := StationGoods.new(_station, player)
	var plan: Dictionary[StringName, int] = GameState.missions.plan_delivery(station_id, goods.get_available())
	for item_id: StringName in plan:
		var taken: int = goods.take(item_id, plan[item_id])
		if taken <= 0:
			continue
		var accepted: int = GameState.missions.deliver(station_id, item_id, taken)
		if accepted < taken:
			# No debería pasar (el plan es de recién), pero nada se pierde: vuelve a la mochila
			# o al primer vagón que lo acepte.
			_give_back(goods, item_id, taken - accepted)
		if accepted > 0:
			result[item_id] = accepted
			EventBus.contribution_delivered.emit(station_id, item_id, accepted)
	if not result.is_empty():
		_message = "Entregaste " + _amounts_text(result)
		_message_left = MESSAGE_TIME
		delivered.emit(result)
	update_text()
	return result


func _on_interact(player: Player) -> void:
	deliver(player)


## Escribe el estado en el Label3D "Texto" (también lo devuelve, para pruebas).
func update_text() -> String:
	var text: String = build_text()
	if _label != null:
		_label.text = text
	return text


func build_text() -> String:
	if _station == null or _station.data == null:
		return "(tablero sin estación)"
	var board: MissionBoard = GameState.missions
	var station_id: StringName = _station.get_station_id()
	var lines: PackedStringArray = [_station.describe()]
	var days: int = _station.get_days_to_grow()
	if days > 0:
		var growing: String = "creciendo" if _station.get_missing().is_empty() else "estancado"
		lines.append("%s: %d de %d días" % [growing, _station.get_growth_progress(), days])
	var mains: Array[Mission] = board.get_main_missions(station_id)
	if not mains.is_empty():
		lines.append("— Principales —")
		for mission: Mission in mains:
			lines.append(_mission_line(board, mission))
	var sides: Array[Mission] = board.get_side_missions(station_id)
	var shown_sides: PackedStringArray = []
	for mission: Mission in sides:
		if mission.state != Mission.State.AVAILABLE:
			shown_sides.append(_mission_line(board, mission))
	if not shown_sides.is_empty():
		lines.append("— Secundarias —")
		lines.append_array(shown_sides)
	var plan: Dictionary[StringName, int] = get_delivery_plan()
	if not plan.is_empty():
		lines.append("F: entregar " + _amounts_text(plan))
	if not _message.is_empty():
		lines.append(_message)
	return "\n".join(lines)


func _mission_line(board: MissionBoard, mission: Mission) -> String:
	if mission.is_completed():
		return "✓ " + board.get_title(mission)
	var steps: PackedStringArray = board.get_pending_steps(mission)
	if steps.is_empty():
		return "· %s: listo" % board.get_title(mission)
	return "· %s: %s" % [board.get_title(mission), "; ".join(steps)]


func _amounts_text(amounts: Dictionary[StringName, int]) -> String:
	var parts: PackedStringArray = []
	for item_id: StringName in amounts:
		parts.append("%d %s" % [amounts[item_id], GameState.missions.name_of(item_id)])
	return ", ".join(parts)


func _find_station() -> Station:
	var node: Node = get_parent()
	while node != null:
		if node is Station:
			return node
		node = node.get_parent()
	return null


func _give_back(goods: StationGoods, item_id: StringName, amount: int) -> void:
	var item: ItemData = goods.find_item(item_id)
	if item == null and _station.data != null:
		item = _station.data.find_item(item_id)
	var stored: int = goods.store(item, amount)
	if stored < amount:
		push_warning("StationBoard: no se pudieron devolver %d %s." % [amount - stored, item_id])
