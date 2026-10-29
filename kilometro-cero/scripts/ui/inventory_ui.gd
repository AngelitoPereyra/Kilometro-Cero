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
## Tarea 62.8 (D124): tres pestañas. "Mochila" (lo de arriba), "Agenda" (estaciones, misiones,
## flujos y horarios de los automáticos) y "Tren" (el tren del jugador vagón por vagón, con lo que
## lleva cada uno). Los textos los arma AgendaText; `agenda_extra` (opcional, lo pone la escena)
## devuelve renglones más para la agenda. Con la ventana abierta, 1, 2 y 3 cambian de pestaña.

signal toggled(is_open: bool)

enum Tab { BACKPACK, AGENDA, TRAIN }

const TAB_NAMES: Array[String] = ["Mochila", "Agenda", "Tren"]
const TEXT_SIZE: Vector2 = Vector2(760.0, 460.0)
## Colores de la ventana (tarea 62.8, pedido de Batmi): fondo crema clarito, tinta oscura, ranuras
## de un crema más tostado con borde marrón para que se vean.
const CREAM: Color = Color(0.96, 0.93, 0.84)
const CREAM_DARK: Color = Color(0.86, 0.8, 0.66)
const CREAM_HOVER: Color = Color(0.91, 0.86, 0.74)
const INK: Color = Color(0.17, 0.13, 0.09)
const BORDER: Color = Color(0.48, 0.36, 0.22)

## Si queda vacío, usa el padre.
@export var player: Player
@export_range(1, 12, 1) var columns: int = 5
@export var slot_size: Vector2 = Vector2(84.0, 84.0)

## func() -> PackedStringArray: renglones que la escena suma a la agenda (tarea 62.8).
var agenda_extra: Callable

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
var _tabs: TabContainer
var _agenda: RichTextLabel
var _train: RichTextLabel
# El último tren que manejó el jugador: se sigue mostrando al bajarse.
var _last_train_head: Vehicle


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
		&"container_full":
			return "Ahí no entra nada de lo que llevás en la mochila."
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
	elif _open and event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key: Key = (event as InputEventKey).physical_keycode
		if key >= KEY_1 and key <= KEY_3:
			show_tab(key - KEY_1)
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
		_refresh_texts()
	else:
		GameState.clock_running = _clock_was_running
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	toggled.emit(value)


## Muestra la pestaña `tab` (Tab.BACKPACK, AGENDA o TRAIN) y rearma su texto.
func show_tab(tab: int) -> void:
	if _tabs == null or tab < 0 or tab >= _tabs.get_tab_count():
		return
	_tabs.current_tab = tab
	_refresh_texts()


func get_current_tab() -> int:
	return _tabs.current_tab if _tabs != null else Tab.BACKPACK


## Los textos de la agenda y del tren, como se ven (BBCode), para las pruebas.
func get_agenda_text() -> String:
	return _agenda.text if _agenda != null else ""


func get_train_text() -> String:
	return _train.text if _train != null else ""


## El tren del jugador: el de la cabina donde está o, si no, el último que manejó, o el de la
## cabina libre más cercana (de un tren que no es automático). Vacío si no hay ninguno.
func find_player_train() -> Array[Vehicle]:
	var cab: Cab = player.get_cab() if player != null else null
	if cab != null and cab.get_vehicle() != null:
		_last_train_head = cab.get_vehicle()
	if is_instance_valid(_last_train_head) and _last_train_head.is_inside_tree():
		return _last_train_head.get_train()
	var best: Vehicle = null
	var best_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group(Cab.GROUP):
		var other := node as Cab
		var vehicle: Vehicle = other.get_vehicle() if other != null else null
		if vehicle == null or vehicle.automatic:
			continue
		var distance: float = vehicle.global_position.distance_to(player.global_position)
		if distance < best_distance:
			best = vehicle
			best_distance = distance
	return best.get_train() if best != null else ([] as Array[Vehicle])


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
	# Más oscuro que los carteles de pantalla, para que no se confundan (tarea 62.8).
	shade.color = Color(0.0, 0.0, 0.0, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(center)

	var panel := PanelContainer.new()
	panel.theme = _make_theme()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)
	_tabs = TabContainer.new()
	# Sin foco: el TAB siempre cierra (no navega entre pestañas).
	_tabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
	_tabs.tab_changed.connect(func(_tab: int) -> void: _refresh_texts())
	outer.add_child(_tabs)
	# La mochila ocupa la misma caja que la agenda y el tren: también va en una caja con barra.
	var backpack_scroll := ScrollContainer.new()
	backpack_scroll.custom_minimum_size = TEXT_SIZE
	backpack_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(backpack_scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	backpack_scroll.add_child(column)

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
	help.text = "Clic en una ranura: a la mano"
	help.modulate = Color(1.0, 1.0, 1.0, 0.6)
	column.add_child(help)

	_agenda = _make_text_tab()
	_train = _make_text_tab()
	for index: int in TAB_NAMES.size():
		_tabs.set_tab_title(index, "%d · %s" % [index + 1, TAB_NAMES[index]])
	var keys := Label.new()
	keys.text = "1, 2, 3: pestañas · TAB, G o Esc: cerrar"
	keys.modulate = Color(1.0, 1.0, 1.0, 0.6)
	outer.add_child(keys)


# El tema de la ventana: crema clarito con tinta oscura, pestañas y ranuras que se distinguen.
func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.set_stylebox(&"panel", &"PanelContainer", _box(CREAM, CREAM, 8, 0))
	theme.set_stylebox(&"panel", &"TabContainer", _box(CREAM, BORDER, 4, 1))
	theme.set_stylebox(&"tab_selected", &"TabContainer", _box(CREAM, BORDER, 4, 1))
	theme.set_stylebox(&"tab_unselected", &"TabContainer", _box(CREAM_DARK, BORDER, 4, 1))
	theme.set_stylebox(&"tab_hovered", &"TabContainer", _box(CREAM_HOVER, BORDER, 4, 1))
	for color_name: StringName in [&"font_selected_color", &"font_unselected_color", &"font_hovered_color"]:
		theme.set_color(color_name, &"TabContainer", INK)
	theme.set_color(&"font_color", &"Label", INK)
	theme.set_color(&"default_color", &"RichTextLabel", INK)
	theme.set_stylebox(&"normal", &"Button", _box(CREAM_DARK, BORDER, 4, 2))
	theme.set_stylebox(&"hover", &"Button", _box(CREAM_HOVER, BORDER, 4, 2))
	theme.set_stylebox(&"pressed", &"Button", _box(CREAM, BORDER, 4, 2))
	for color_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		theme.set_color(color_name, &"Button", INK)
	return theme


static func _box(fill: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(6.0)
	return box


# Una pestaña de texto con barra para bajar (agenda y tren).
func _make_text_tab() -> RichTextLabel:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = TEXT_SIZE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 17)
	text.add_theme_font_size_override("bold_font_size", 17)
	scroll.add_child(text)
	return text


# Vuelve a escribir la agenda y el tren (al abrir y al cambiar de pestaña).
func _refresh_texts() -> void:
	if _agenda == null or not is_inside_tree():
		return
	var extra := PackedStringArray()
	if agenda_extra.is_valid():
		extra = agenda_extra.call()
	_agenda.text = AgendaText.agenda(GameState.missions, GameState.production, AutoTrains.find_in(get_tree()), extra)
	_train.text = AgendaText.train(find_player_train(), GameState.missions)


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
