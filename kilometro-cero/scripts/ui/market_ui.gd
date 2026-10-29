class_name MarketUI
extends CanvasLayer
## Ventana del mercado (tarea 59). La abre Market con F y la cierra Esc, F, TAB o G.
## Una ficha por objeto: cuánto tiene la estación, a cuánto lo vende, cuánto tenés al alcance
## (vagones de la bahía de carga o, sin bahía, del tren detenido; mano y mochila), cuánto te
## paga, y botones para comprar o vender 1, 10, todo lo que se pueda o un vagón (tarea 62.9b).
## Con el mismo aspecto que el TAB (InventoryUI.make_theme, tarea 62.9b): caja crema de tamaño
## fijo con barra para bajar, así no se sale de la pantalla.
## Abierta, libera el mouse, pausa el reloj y apaga los controles del jugador, como el inventario
## (InventoryUI).
## Arma sus nodos por código. No tiene lógica de mercado: le pide todo a Market.

signal toggled(is_open: bool)

const STEPS: Array[int] = [1, 10]
## Lo mismo que las pestañas del TAB.
const BOX_SIZE: Vector2 = Vector2(760.0, 460.0)
const FONT_SIZE: int = 17

var _market: Market
var _player: Player
var _open: bool = false
var _clock_was_running: bool = true
# Cerrada con F: los controles vuelven recién al soltarla, si no Player volvería a abrirla en
# el mismo cuadro (lee la F con is_action_just_pressed).
var _waiting_release: bool = false

var _title: Label
var _rows: VBoxContainer
var _status: Label


func _ready() -> void:
	layer = 11
	visible = false
	_build()
	EventBus.money_changed.connect(func(_money: int) -> void: _refresh())


func _process(_delta: float) -> void:
	if _waiting_release and not Input.is_action_pressed(&"interact"):
		_waiting_release = false
		if _player != null and not _open:
			_player.set_controls_enabled(true)


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"interact") or event.is_action_pressed(&"inventory"):
		set_open(false)
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _open


## Abre la ventana para ese mercado y ese jugador.
func open_for(market: Market, player: Player) -> void:
	_market = market
	_player = player
	set_open(true)


func set_open(value: bool) -> void:
	if value == _open or _market == null:
		return
	_open = value
	visible = value
	_waiting_release = not value and Input.is_action_pressed(&"interact")
	if _player != null and not _waiting_release:
		_player.set_controls_enabled(not value)
	if value:
		# Si otro menú ya había pausado el reloj, se respeta al cerrar.
		_clock_was_running = GameState.clock_running
		GameState.clock_running = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_status.text = ""
		_refresh()
	else:
		GameState.clock_running = _clock_was_running
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	toggled.emit(value)


## Lo mismo que un botón de comprar (Market.ALL: todo). Devuelve cuántas compró.
func press_buy(item_id: StringName, amount: int) -> int:
	var reason: String = _market.why_not_buy(item_id, _player)
	var bought: int = _market.buy(item_id, amount, _player)
	if bought > 0:
		_status.text = "Compraste %d %s." % [bought, GameState.economy.name_of(item_id)]
		if _market.buys_to_bay():
			_status.text += " Se cargan de a poco en la bahía de carga."
	else:
		_status.text = reason
	_refresh()
	return bought


## Lo mismo que un botón de vender. Devuelve cuántas vendió.
func press_sell(item_id: StringName, amount: int) -> int:
	var reason: String = _market.why_not_sell(item_id, _player)
	var sold: int = _market.sell(item_id, amount, _player)
	var queued: int = _market.get_last_sell_queued()
	if sold > 0 and queued > 0:
		_status.text = "Vendiste %d %s: %d se descargan de la bahía y se cobran al bajar." % [sold, GameState.economy.name_of(item_id), queued]
	elif sold > 0:
		_status.text = "Vendiste %d %s." % [sold, GameState.economy.name_of(item_id)]
	else:
		_status.text = reason
	_refresh()
	return sold


## "Comprar vagón" (tarea 62.9b): lo que llena el primer vagón con lugar. Devuelve cuántas compró.
func press_buy_wagon(item_id: StringName) -> int:
	var amount: int = _market.wagon_amount_to_buy(item_id, _player)
	if amount <= 0:
		_status.text = "No hay un vagón con lugar: estacionalo en la bahía de carga (o frená el tren en la estación si no tiene)."
		return 0
	return press_buy(item_id, amount)


## "Vender vagón": lo que lleva el primer vagón que lo tiene. Devuelve cuántas vendió.
func press_sell_wagon(item_id: StringName) -> int:
	var amount: int = _market.wagon_amount_to_sell(item_id, _player)
	if amount <= 0:
		_status.text = "Ningún vagón lleva eso (en la bahía de carga o en el tren detenido)."
		return 0
	return press_sell(item_id, amount)


func get_title_text() -> String:
	return _title.text if _title != null else ""


func get_status_text() -> String:
	return _status.text if _status != null else ""


## Cuántas fichas de objetos muestra.
func get_row_count() -> int:
	return _rows.get_child_count() if _rows != null else 0


func _build() -> void:
	# Fondo oscuro que se queda con los clics, como InventoryUI (y tan oscuro como ella).
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(center)

	var panel := PanelContainer.new()
	panel.theme = InventoryUI.make_theme()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", FONT_SIZE + 3)
	outer.add_child(_title)
	# La caja con borde, como el contenido de una pestaña del TAB.
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", InventoryUI.make_theme().get_stylebox(&"panel", &"TabContainer"))
	outer.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = BOX_SIZE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 14)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(BOX_SIZE.x, 0.0)
	outer.add_child(_status)
	var help := Label.new()
	help.text = "Lo comprado se carga de a poco en los vagones de la bahía de carga (sin bahía, en el tren detenido) o va a la mochila · Esc, F o TAB: cerrar"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(BOX_SIZE.x, 0.0)
	help.modulate = Color(1.0, 1.0, 1.0, 0.6)
	outer.add_child(help)


# Rearma las fichas con lo que dice el mercado ahora.
func _refresh() -> void:
	if not _open or _market == null:
		return
	_title.text = "Mercado de %s · tenés $%d" % [_market.get_station().get_display_name(), GameState.money]
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var rows: Array[Dictionary] = _market.get_rows(_player)
	for row: Dictionary in rows:
		_rows.add_child(_make_row(row))
	if rows.is_empty():
		_status.text = "La estación no tiene mercadería y no tenés nada para vender."


# Una ficha: el objeto con sus números en un renglón y abajo los botones de comprar y vender.
func _make_row(row: Dictionary) -> VBoxContainer:
	var item_id: StringName = row["item_id"]
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 4)
	var info := Label.new()
	info.add_theme_font_size_override("font_size", FONT_SIZE)
	var price: String = "a $%d" % row["buy_price"] if row["buy_price"] > 0 else "no lo vende"
	var pays: String = "te paga $%d" % row["sell_price"] if row["sell_price"] > 0 else "no lo compra"
	var item_name: String = str(row["name"])
	item_name = item_name.substr(0, 1).to_upper() + item_name.substr(1)
	info.text = "%s · en la estación %d, %s · tenés %d, %s" % [item_name, row["stock"], price, row["have"], pays]
	block.add_child(info)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	block.add_child(buttons)
	buttons.add_child(_make_label("Comprar"))
	for step: int in STEPS:
		buttons.add_child(_make_button(str(step), press_buy.bind(item_id, step)))
	buttons.add_child(_make_button("Todo", press_buy.bind(item_id, Market.ALL)))
	buttons.add_child(_make_button("Vagón", press_buy_wagon.bind(item_id)))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(24.0, 0.0)
	buttons.add_child(gap)
	buttons.add_child(_make_label("Vender"))
	for step: int in STEPS:
		buttons.add_child(_make_button(str(step), press_sell.bind(item_id, step)))
	buttons.add_child(_make_button("Todo", press_sell.bind(item_id, Market.ALL)))
	buttons.add_child(_make_button("Vagón", press_sell_wagon.bind(item_id)))
	return block


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _make_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(56.0, 0.0)
	# Sin foco: TAB y las flechas no navegan entre botones.
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void: action.call())
	return button
