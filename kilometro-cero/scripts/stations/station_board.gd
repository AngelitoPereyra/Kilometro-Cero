class_name StationBoard
extends Interactable
## Tablero de una estación (D80, tarea 58): nodo "Tablero" de las plantillas de estación (hijo
## directo o nieto de la Station). Muestra el estado del lugar en su Label3D "Texto": nivel,
## crecimiento, las misiones principales con sus pasos, las secundarias y lo que se puede
## entregar. Nada se descarga solo: F en el tablero aprueba la entrega, que saca de los vagones
## de los trenes detenidos en la estación, de la mano y de la mochila del jugador solo lo que
## piden las misiones (en ese orden; de la mano, solo si se entrega todo lo que sostiene).

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
	var plan: Dictionary[StringName, int] = get_delivery_plan(_player_or(null))
	return "Entregar " + _amounts_text(plan) if not plan.is_empty() else "Mirar el tablero"


## Lo que hay para entregar ahora: vagones de los trenes detenidos, la mano y la mochila del
## jugador (id de objeto -> unidades). `player` null: el que esté en la zona de la estación.
func get_available(player: Player = null) -> Dictionary[StringName, int]:
	var available: Dictionary[StringName, int] = {}
	for cargo: StorageContainer in _get_cargos():
		for index: int in cargo.get_stack_count():
			var stack: ItemStack = cargo.peek(index)
			available[stack.item.id] = available.get(stack.item.id, 0) + stack.quantity
	var held: ItemStack = _get_held(player)
	if held != null:
		available[held.item.id] = available.get(held.item.id, 0) + held.quantity
	var backpack: Inventory = _get_backpack(player)
	if backpack != null:
		for slot: int in backpack.get_slot_count():
			var stack: ItemStack = backpack.peek(slot)
			if stack != null:
				available[stack.item.id] = available.get(stack.item.id, 0) + stack.quantity
	return available


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
	var plan: Dictionary[StringName, int] = get_delivery_plan(player)
	for item_id: StringName in plan:
		var taken: int = _take(item_id, plan[item_id], player)
		if taken <= 0:
			continue
		var accepted: int = GameState.missions.deliver(station_id, item_id, taken)
		if accepted < taken:
			# No debería pasar (el plan es de recién), pero nada se pierde: vuelve a la mochila
			# o al primer vagón que lo acepte.
			_give_back(item_id, taken - accepted, player)
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


func _player_or(player: Player) -> Player:
	if player != null:
		return player
	return _station.get_present_player() if _station != null else null


func _get_backpack(player: Player) -> Inventory:
	var who: Player = _player_or(player)
	return who.get_backpack() if who != null else null


# Lo que el jugador tiene en la mano, si lo sostiene su Grabber (si no, no se puede entregar).
func _get_held(player: Player) -> ItemStack:
	var grabber: Grabber = _get_grabber(player)
	var item: WorldItem = grabber.get_held_item() if grabber != null else null
	return item.stack if item != null else null


func _get_grabber(player: Player) -> Grabber:
	var who: Player = _player_or(player)
	if who == null:
		return null
	for child: Node in who.get_children():
		if child is Grabber:
			return child
	return null


# Las cargas de los vagones de los trenes detenidos en la estación.
func _get_cargos() -> Array[StorageContainer]:
	var cargos: Array[StorageContainer] = []
	if _station == null:
		return cargos
	for head: Vehicle in _station.get_stopped_trains():
		for vehicle: Vehicle in head.get_train():
			var wagon := vehicle as Wagon
			if wagon != null and wagon.get_cargo() != null:
				cargos.append(wagon.get_cargo())
	return cargos


# Saca hasta `amount` del objeto: vagones, mano (solo entera) y mochila, en ese orden.
func _take(item_id: StringName, amount: int, player: Player) -> int:
	var taken: int = 0
	for cargo: StorageContainer in _get_cargos():
		for index: int in range(cargo.get_stack_count() - 1, -1, -1):
			if taken >= amount:
				return taken
			if cargo.peek(index).item.id == item_id:
				var stack: ItemStack = cargo.take(index, amount - taken)
				taken += stack.quantity if stack != null else 0
	var held: ItemStack = _get_held(player)
	if held != null and held.item.id == item_id and held.quantity <= amount - taken:
		var consumed: ItemStack = _get_grabber(player).consume_held()
		taken += consumed.quantity if consumed != null else 0
	var backpack: Inventory = _get_backpack(player)
	if backpack != null:
		for slot: int in backpack.get_slot_count():
			if taken >= amount:
				break
			var current: ItemStack = backpack.peek(slot)
			if current != null and current.item.id == item_id:
				var stack: ItemStack = backpack.take(slot, amount - taken)
				taken += stack.quantity if stack != null else 0
	return taken


func _give_back(item_id: StringName, amount: int, player: Player) -> void:
	var item: ItemData = null
	if _station != null and _station.data != null:
		item = _station.data.find_item(item_id)
	if item == null:
		push_warning("StationBoard: no se pudieron devolver %d %s." % [amount, item_id])
		return
	var leftover: ItemStack = ItemStack.new(item, amount)
	for cargo: StorageContainer in _get_cargos():
		leftover = cargo.try_store(leftover)
		if leftover == null:
			return
	var backpack: Inventory = _get_backpack(player)
	if backpack != null:
		leftover = backpack.try_store(leftover)
	if leftover != null:
		push_warning("StationBoard: no se pudieron devolver %d %s." % [leftover.quantity, item_id])
