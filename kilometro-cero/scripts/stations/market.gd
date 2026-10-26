class_name Market
extends Interactable
## Mercado de una estación (D87, D96, tarea 59): nodo "Mercado" de las plantillas de estación
## (hijo directo o nieto de la Station). Solo pesos. Abre si el nivel de la estación tiene
## mercado (StationData.has_market); cerrado, F no lo usa y el cartel dice desde qué nivel abre.
## F abre la ventana del mercado (MarketUI): ahí se compra lo que la estación tiene en stock y se
## vende lo que el jugador tiene al alcance (StationGoods: vagones del tren detenido, mano y
## mochila). Lo comprado se carga en los vagones del tren detenido y después en la mochila
## ("cargar desde la estación"). Precios y stock: GameState.economy (Economy); el dinero,
## GameState.money. Su Label3D "Texto" muestra el stock y los precios.

## Se compró (amount positivo) o vendió (negativo) algo; `total` en pesos.
signal traded(item_id: StringName, amount: int, total: int)

const TEXT_PATH: NodePath = ^"Texto"
## Cada cuánto (s) se vuelve a escribir el cartel.
const REFRESH_TIME: float = 0.5
## Cantidad que significa "todo lo que se pueda".
const ALL: int = 9999

var _station: Station
var _label: Label3D
var _ui: MarketUI
var _timer: float = 0.0


## Mensaje para un motivo de Economy.why_not_buy o why_not_sell. Lógica pura.
static func reason_text(reason: StringName) -> String:
	match reason:
		&"closed":
			return "El mercado está cerrado."
		&"no_value":
			return "Eso no se compra ni se vende acá."
		&"no_stock":
			return "No queda en la estación."
		&"no_money":
			return "No te alcanza la plata."
		&"no_room":
			return "No hay lugar: traé el tren y frená en la estación, o hacé lugar en la mochila."
		&"nothing":
			return "No tenés para vender (vagones del tren detenido, mano o mochila)."
		_:
			return ""


func _ready() -> void:
	_station = _find_station()
	_label = get_node_or_null(TEXT_PATH) as Label3D
	if _station == null:
		push_warning("Market %s: no está dentro de una Station." % name)
	update_text()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH_TIME
		update_text()


func get_station() -> Station:
	return _station


func get_station_id() -> StringName:
	return _station.get_station_id() if _station != null else &""


## Si el mercado está abierto en el nivel actual de la estación.
func is_open() -> bool:
	return _station != null and GameState.economy.has_market(get_station_id())


## El primer nivel con mercado (0 si nunca abre).
func get_opening_level() -> int:
	if _station == null or _station.data == null:
		return 0
	for index: int in _station.data.levels.size():
		var level: StationLevelData = _station.data.levels[index]
		if level != null and level.market:
			return index + 1
	return 0


func can_interact(player: Player) -> bool:
	return super.can_interact(player) and is_open()


func get_prompt() -> String:
	return "Comerciar en el mercado"


## La ventana del mercado (la arma la primera vez).
func get_ui() -> MarketUI:
	if _ui == null:
		_ui = MarketUI.new()
		add_child(_ui)
	return _ui


func _on_interact(player: Player) -> void:
	get_ui().open_for(self, player)


## Una fila por objeto que se puede comerciar: lo que la estación tiene en stock y lo que el
## jugador tiene al alcance con valor. Cada fila: item_id, name, stock, buy_price (0: no se
## vende acá), sell_price y have.
func get_rows(player: Player = null) -> Array[Dictionary]:
	var economy: Economy = GameState.economy
	var station_id: StringName = get_station_id()
	var goods := StationGoods.new(_station, player)
	var available: Dictionary[StringName, int] = goods.get_available()
	var ids: Array[StringName] = []
	for item_id: StringName in economy.get_stock(station_id):
		ids.append(item_id)
	for item_id: StringName in available:
		economy.register_item(goods.find_item(item_id))
		if not ids.has(item_id) and Economy.is_tradable(economy.get_item(item_id)):
			ids.append(item_id)
	var rows: Array[Dictionary] = []
	for item_id: StringName in ids:
		rows.append({
			"item_id": item_id,
			"name": economy.name_of(item_id),
			"stock": economy.get_stock_of(station_id, item_id),
			"buy_price": economy.get_buy_price(station_id, item_id),
			"sell_price": economy.get_sell_price(station_id, item_id),
			"have": available.get(item_id, 0),
		})
	return rows


## Cuántas compraría ahora de las `wanted` que se piden (stock, plata y lugar).
func get_buy_amount(item_id: StringName, wanted: int, player: Player = null) -> int:
	var goods := StationGoods.new(_station, player)
	var room: int = goods.room_for(GameState.economy.get_item(item_id))
	return GameState.economy.plan_buy(get_station_id(), item_id, wanted, GameState.money, room)


## Compra hasta `amount` (ALL: todo lo que se pueda), lo carga en los vagones del tren detenido
## y en la mochila, y lo cobra. Devuelve cuántas compró.
func buy(item_id: StringName, amount: int, player: Player = null) -> int:
	var economy: Economy = GameState.economy
	var goods := StationGoods.new(_station, player)
	var item: ItemData = economy.get_item(item_id)
	var planned: int = economy.plan_buy(get_station_id(), item_id, amount, GameState.money, goods.room_for(item))
	if planned <= 0:
		return 0
	var stored: int = goods.store(item, planned)
	var total: int = economy.record_buy(get_station_id(), item_id, stored)
	_finish_trade(item_id, stored, total)
	return stored


## Por qué no se puede comprar ni una ("" si se puede).
func why_not_buy(item_id: StringName, player: Player = null) -> String:
	var goods := StationGoods.new(_station, player)
	var room: int = goods.room_for(GameState.economy.get_item(item_id))
	return reason_text(GameState.economy.why_not_buy(get_station_id(), item_id, GameState.money, room))


## Vende hasta `amount` (ALL: todo) de lo que el jugador tiene al alcance y lo cobra. Devuelve
## cuántas vendió.
func sell(item_id: StringName, amount: int, player: Player = null) -> int:
	var economy: Economy = GameState.economy
	var goods := StationGoods.new(_station, player)
	var item: ItemData = goods.find_item(item_id)
	economy.register_item(item)
	var planned: int = economy.plan_sell(get_station_id(), item_id, amount, goods.count_of(item_id))
	if planned <= 0:
		return 0
	var taken: int = goods.take(item_id, planned)
	var total: int = economy.record_sell(get_station_id(), item_id, taken, item)
	_finish_trade(item_id, -taken, total)
	return taken


## Por qué no se puede vender ni una ("" si se puede).
func why_not_sell(item_id: StringName, player: Player = null) -> String:
	var economy: Economy = GameState.economy
	if not is_open():
		return reason_text(&"closed")
	if economy.get_sell_price(get_station_id(), item_id) <= 0:
		return reason_text(&"no_value")
	if StationGoods.new(_station, player).count_of(item_id) <= 0:
		return reason_text(&"nothing")
	return ""


## Escribe el cartel en el Label3D "Texto" (también lo devuelve, para pruebas).
func update_text() -> String:
	var text: String = build_text()
	if _label != null:
		_label.text = text
	return text


func build_text() -> String:
	if _station == null:
		return "(mercado sin estación)"
	if not is_open():
		var opening: int = get_opening_level()
		return "Mercado cerrado" + (": abre en el nivel %d" % opening if opening > 0 else "")
	var economy: Economy = GameState.economy
	var station_id: StringName = get_station_id()
	var lines: PackedStringArray = ["Mercado · F para comerciar"]
	var stock: Dictionary[StringName, int] = economy.get_stock(station_id)
	if stock.is_empty():
		lines.append("Sin mercadería")
	for item_id: StringName in stock:
		lines.append("%s: %d · a $%d (te paga $%d)" % [economy.name_of(item_id), stock[item_id],
				economy.get_buy_price(station_id, item_id), economy.get_sell_price(station_id, item_id)])
	return "\n".join(lines)


func _finish_trade(item_id: StringName, amount: int, total: int) -> void:
	if amount == 0:
		return
	GameState.add_money(-total if amount > 0 else total)
	EventBus.item_traded.emit(get_station_id(), item_id, amount, total)
	traded.emit(item_id, amount, total)
	update_text()


func _find_station() -> Station:
	var node: Node = get_parent()
	while node != null:
		if node is Station:
			return node
		node = node.get_parent()
	return null
