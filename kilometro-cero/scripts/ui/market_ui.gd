class_name MarketUI
extends CanvasLayer
## Ventana del mercado (tarea 59). La abre Market con F y la cierra Esc, F, TAB o G.
## Una fila por objeto: cuánto tiene la estación, a cuánto lo vende, cuánto tenés al alcance
## (vagones del tren detenido, mano y mochila), cuánto te paga, y botones para comprar o vender
## 1, 10 o todo lo que se pueda. Abierta, libera el mouse, pausa el reloj y apaga los controles
## del jugador, como el inventario (InventoryUI).
## Arma sus nodos por código. No tiene lógica de mercado: le pide todo a Market.

signal toggled(is_open: bool)

const COLUMNS: int = 11
const STEPS: Array[int] = [1, 10]

var _market: Market
var _player: Player
var _open: bool = false
var _clock_was_running: bool = true
# Cerrada con F: los controles vuelven recién al soltarla, si no Player volvería a abrirla en
# el mismo cuadro (lee la F con is_action_just_pressed).
var _waiting_release: bool = false

var _title: Label
var _grid: GridContainer
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
	else:
		_status.text = reason
	_refresh()
	return bought


## Lo mismo que un botón de vender. Devuelve cuántas vendió.
func press_sell(item_id: StringName, amount: int) -> int:
	var reason: String = _market.why_not_sell(item_id, _player)
	var sold: int = _market.sell(item_id, amount, _player)
	if sold > 0:
		_status.text = "Vendiste %d %s." % [sold, GameState.economy.name_of(item_id)]
	else:
		_status.text = reason
	_refresh()
	return sold


func get_title_text() -> String:
	return _title.text if _title != null else ""


func get_status_text() -> String:
	return _status.text if _status != null else ""


## Cuántas filas de objetos muestra (sin el encabezado).
func get_row_count() -> int:
	@warning_ignore("integer_division")
	return maxi(0, _grid.get_child_count() / COLUMNS - 1) if _grid != null else 0


func _build() -> void:
	# Fondo oscuro que se queda con los clics, como InventoryUI.
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
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 12)
	column.add_child(_grid)
	_status = Label.new()
	column.add_child(_status)
	var help := Label.new()
	help.text = "Lo comprado se carga en los vagones del tren detenido y en la mochila · Esc, F o TAB: cerrar"
	help.modulate = Color(1.0, 1.0, 1.0, 0.6)
	column.add_child(help)


# Rearma las filas con lo que dice el mercado ahora.
func _refresh() -> void:
	if not _open or _market == null:
		return
	_title.text = "Mercado de %s · tenés $%d" % [_market.get_station().get_display_name(), GameState.money]
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for header: String in ["Objeto", "En la estación", "Precio", "Tenés", "Te paga", "", "", "", "", "", ""]:
		_add_label(header).modulate = Color(1.0, 1.0, 1.0, 0.7)
	var rows: Array[Dictionary] = _market.get_rows(_player)
	for row: Dictionary in rows:
		var item_id: StringName = row["item_id"]
		_add_label(row["name"])
		_add_label(str(row["stock"]))
		_add_label("$%d" % row["buy_price"] if row["buy_price"] > 0 else "—")
		_add_label(str(row["have"]))
		_add_label("$%d" % row["sell_price"] if row["sell_price"] > 0 else "—")
		for step: int in STEPS:
			_add_button("Comprar %d" % step, press_buy.bind(item_id, step))
		_add_button("Comprar todo", press_buy.bind(item_id, Market.ALL))
		for step: int in STEPS:
			_add_button("Vender %d" % step, press_sell.bind(item_id, step))
		_add_button("Vender todo", press_sell.bind(item_id, Market.ALL))
	if rows.is_empty():
		_status.text = "La estación no tiene mercadería y no tenés nada para vender."


func _add_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	_grid.add_child(label)
	return label


func _add_button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	# Sin foco: TAB y las flechas no navegan entre botones.
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void: action.call())
	_grid.add_child(button)
