class_name InventoryUI
extends CanvasLayer
## Interfaz mínima del inventario (tarea 49, D72). TAB o G (acción `inventory`) la abre
## y la cierra; Esc también la cierra. Muestra las ranuras de la mochila y la mano.
## Clic en una ranura: pasa una unidad a la mano (Grabber.take_from_backpack).
## Clic en la mano: la guarda en la mochila (Grabber.stow_held).
## Abierta, libera el mouse, pausa el reloj de juego y apaga los controles del jugador.
## Arma sus nodos por código: en la escena es solo un CanvasLayer con este script,
## hijo directo de Player (o con `player` asignado desde el inspector).
## No tiene lógica de inventario: observa señales y le pide todo al Grabber.

signal toggled(is_open: bool)

## Si queda vacío, usa el padre.
@export var player: Player
@export_range(1, 12, 1) var columns: int = 5
@export var slot_size: Vector2 = Vector2(84.0, 84.0)

var _open: bool = false
var _clock_was_running: bool = true
var _grabber: Grabber
var _backpack: Inventory
var _hands: Hands

var _title: Label
var _grid: GridContainer
var _hand_button: Button
var _status: Label
var _slot_buttons: Array[Button] = []


## Texto de una ranura o de la mano: nombre y, si hay más de uno, la cantidad;
## si tiene durabilidad, el porcentaje. Vacío si no hay nada. Lógica pura.
static func slot_text(stack: ItemStack) -> String:
	if stack == null or stack.item == null:
		return ""
	var item_name: String = stack.item.display_name
	if item_name.is_empty():
		item_name = String(stack.item.id)
	var text: String = item_name
	if stack.quantity > 1:
		text += "\nx%d" % stack.quantity
	if stack.has_durability():
		text += "\n%d %%" % roundi(stack.durability * 100.0)
	return text


## Mensaje para un motivo de Grabber.grab_failed. Lógica pura.
static func failure_text(reason: StringName) -> String:
	match reason:
		&"container_empty":
			return "Esa ranura está vacía."
		&"hands_empty":
			return "No tenés nada en la mano."
		&"no_room":
			return "Lo que tenés en la mano no entra en la mochila."
		&"too_big":
			return "Eso no se puede llevar en la mano."
		_:
			return ""


func _ready() -> void:
	layer = 10
	visible = false
	if player == null:
		player = get_parent() as Player
	if player == null:
		push_error("InventoryUI necesita un Player: ponela como hija directa o asignalo en el inspector.")
		set_process_input(false)
		return
	_build()
	# Player termina de armar la mochila en su _ready, que corre DESPUÉS del de sus hijos.
	if player.is_node_ready():
		_connect_player()
	else:
		player.ready.connect(_connect_player, CONNECT_ONE_SHOT)


func _input(event: InputEvent) -> void:
	# En _input y no en _unhandled_input: un botón con foco se quedaría con el TAB.
	if event.is_action_pressed(&"inventory"):
		# Con otra ventana abierta (el mercado apaga los controles) no se abre encima.
		if not _open and not player.controls_enabled:
			return
		set_open(not _open)
		get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed(&"ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _open


func set_open(value: bool) -> void:
	if value == _open or _backpack == null:
		return
	_open = value
	visible = value
	player.set_controls_enabled(not value)
	if value:
		# Se recuerda cómo estaba el reloj: si otro menú ya lo había pausado, se respeta.
		_clock_was_running = GameState.clock_running
		GameState.clock_running = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_status.text = ""
		_refresh()
	else:
		GameState.clock_running = _clock_was_running
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	toggled.emit(value)


## Lo mismo que un clic en la ranura `slot` (sirve para las pruebas).
func press_slot(slot: int) -> void:
	_on_slot_pressed(slot)


## Lo mismo que un clic en la mano.
func press_hand() -> void:
	_on_hand_pressed()


## Texto que muestra ahora la ranura `slot` (para las pruebas).
func get_slot_button_text(slot: int) -> String:
	return _slot_buttons[slot].text if slot >= 0 and slot < _slot_buttons.size() else ""


func get_hand_text() -> String:
	return _hand_button.text if _hand_button != null else ""


func get_status_text() -> String:
	return _status.text if _status != null else ""


func _connect_player() -> void:
	_backpack = player.get_backpack()
	_hands = player.get_hands()
	for child: Node in player.get_children():
		var grabber := child as Grabber
		if grabber != null:
			_grabber = grabber
			break
	if _backpack == null or _hands == null or _grabber == null:
		push_error("InventoryUI: el Player necesita Backpack (Inventory), Hands y Grabber como hijos directos.")
		set_process_input(false)
		return
	_backpack.slots_changed.connect(_refresh)
	_hands.hands_changed.connect(_refresh)
	_grabber.grab_failed.connect(_on_grab_failed)
	_refresh()


func _build() -> void:
	# Fondo oscuro a pantalla completa. Se queda con todos los clics (MOUSE_FILTER_STOP):
	# así un clic fuera del panel no le devuelve el mouse a la cámara.
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	_title = Label.new()
	column.add_child(_title)
	_grid = GridContainer.new()
	_grid.columns = columns
	column.add_child(_grid)

	var hand_row := HBoxContainer.new()
	var hand_label := Label.new()
	hand_label.text = "Mano:"
	hand_row.add_child(hand_label)
	_hand_button = _make_button()
	_hand_button.pressed.connect(_on_hand_pressed)
	hand_row.add_child(_hand_button)
	column.add_child(hand_row)

	_status = Label.new()
	column.add_child(_status)
	var help := Label.new()
	help.text = "Clic en una ranura: a la mano · TAB, G o Esc: cerrar"
	help.modulate = Color(1.0, 1.0, 1.0, 0.6)
	column.add_child(help)


func _make_button() -> Button:
	var button := Button.new()
	button.custom_minimum_size = slot_size
	# Sin foco: TAB y las flechas no navegan entre botones, y TAB siempre cierra.
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	return button


# Rearma los botones si cambió la cantidad de ranuras (otra BackpackData) y
# actualiza los textos. Se llama con cada cambio de la mochila o de la mano.
func _refresh() -> void:
	if _backpack == null:
		return
	var count: int = _backpack.get_slot_count()
	if _slot_buttons.size() != count:
		for button: Button in _slot_buttons:
			button.queue_free()
		_slot_buttons.clear()
		for i: int in count:
			var button: Button = _make_button()
			button.pressed.connect(_on_slot_pressed.bind(i))
			_grid.add_child(button)
			_slot_buttons.append(button)
	for i: int in count:
		_fill_button(_slot_buttons[i], _backpack.peek(i))
	_fill_button(_hand_button, _hands.get_held())
	if _hands.is_empty():
		_hand_button.text = "vacía"
	_hand_button.tooltip_text = "Clic: guardar en la mochila"
	_title.text = "Mochila · %d / %d ranuras" % [_backpack.get_used_slot_count(), count]


func _fill_button(button: Button, stack: ItemStack) -> void:
	button.text = slot_text(stack)
	button.icon = stack.item.icon if stack != null else null
	button.tooltip_text = "" if stack == null else String(stack.item.id)


func _on_slot_pressed(slot: int) -> void:
	if _grabber != null and _grabber.take_from_backpack(slot):
		_status.text = ""


func _on_hand_pressed() -> void:
	if _grabber != null and _grabber.stow_held():
		_status.text = ""


func _on_grab_failed(reason: StringName) -> void:
	if _open:
		_status.text = failure_text(reason)
