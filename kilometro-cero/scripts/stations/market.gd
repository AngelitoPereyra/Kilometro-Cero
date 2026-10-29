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
## Con punto de carga (LoadingBay, tarea 62.9a, D125; hijo de la Station con su bahía de carga),
## el tren detenido en el andén ya no cuenta: lo comprado se carga de a poco en los vagones
## estacionados en la bahía (sin vagones ahí, va a la mochila) y lo que se vende de esos vagones
## se descarga de a poco y se cobra a medida que baja. La mano y la mochila se venden en el acto.

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
var _bay: LoadingBay
# De la última venta, cuántas quedaron pedidas al punto de carga (se cobran al bajar).
var _last_sell_queued: int = 0


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
			return "No hay lugar: estacioná vagones en la bahía de carga (o frená el tren en la estación si no tiene), o hacé lugar en la mochila."
		&"nothing":
			return "No tenés para vender (vagones en la bahía o del tren detenido, mano o mochila)."
		_:
			return ""


func _ready() -> void:
	_station = _find_station()
	_label = get_node_or_null(TEXT_PATH) as Label3D
	if _station == null:
		push_warning("Market %s: no está dentro de una Station." % name)
	else:
		for child: Node in _station.get_children():
			if child is LoadingBay:
				_bay = child as LoadingBay
				_bay.unloaded.connect(_on_bay_unloaded)
				break
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


## El punto de carga de la estación si tiene bahía habilitada (si no, null: trabaja con el tren
## detenido, como antes de la 62.9a).
func get_bay() -> LoadingBay:
	return _bay if _bay != null and _bay.is_usable() else null


## Si lo que se compre ahora va a los vagones de la bahía (hay bahía y vagones ahí).
func buys_to_bay() -> bool:
	var bay: LoadingBay = get_bay()
	return bay != null and bay.has_wagons()


## De la última venta, cuántas se van a descargar de la bahía (se cobran al bajar).
func get_last_sell_queued() -> int:
	return _last_sell_queued


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
	var goods: StationGoods = _goods(player)
	var available: Dictionary[StringName, int] = goods.get_available()
	var bay: LoadingBay = get_bay()
	if bay != null:
		var in_bay: Dictionary[StringName, int] = bay.get_available()
		for item_id: StringName in in_bay:
			available[item_id] = available.get(item_id, 0) + in_bay[item_id]
	var ids: Array[StringName] = []
	for item_id: StringName in economy.get_stock(station_id):
		# Lo que no tiene valor (los pasajeros, tarea 60b) no se comercia.
		if Economy.is_tradable(economy.get_item(item_id)):
			ids.append(item_id)
	for item_id: StringName in available:
		economy.register_item(_find_item(goods, item_id))
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
	var room: int = _room_for(GameState.economy.get_item(item_id), player)
	return GameState.economy.plan_buy(get_station_id(), item_id, wanted, GameState.money, room)


## Compra hasta `amount` (ALL: todo lo que se pueda) y lo cobra. Lo pide al punto de carga si hay
## vagones en la bahía; si no, lo carga en los vagones del tren detenido (sin bahía) y en la
## mochila. Devuelve cuántas compró.
func buy(item_id: StringName, amount: int, player: Player = null) -> int:
	var economy: Economy = GameState.economy
	var item: ItemData = economy.get_item(item_id)
	var planned: int = economy.plan_buy(get_station_id(), item_id, amount, GameState.money, _room_for(item, player))
	if planned <= 0:
		return 0
	var stored: int = planned
	if buys_to_bay():
		get_bay().order_load(item, planned)
	else:
		stored = _goods(player).store(item, planned)
	var total: int = economy.record_buy(get_station_id(), item_id, stored)
	_finish_trade(item_id, stored, total)
	return stored


## Cuántas de `item_id` llenan un vagón (tarea 62.9b, botón "Comprar vagón"): el lugar libre del
## primer vagón que lo acepta (en la bahía; sin bahía, del tren detenido), sin pasar de lo que
## todavía entra en la bahía. 0 si no hay vagón con lugar.
func wagon_amount_to_buy(item_id: StringName, player: Player = null) -> int:
	var item: ItemData = GameState.economy.get_item(item_id)
	if item == null:
		return 0
	var bay: LoadingBay = get_bay()
	var cargos: Array[StorageContainer] = bay.get_cargos() if bay != null else StationGoods.new(_station, player).get_cargos()
	for cargo: StorageContainer in cargos:
		var free: int = cargo.can_store_amount(ItemStack.new(item, maxi(1, cargo.capacity)))
		if free > 0:
			return mini(free, bay.room_for(item)) if bay != null else free
	return 0


## Cuántas de `item_id` vacían un vagón (botón "Vender vagón"): lo que lleva el primer vagón que
## lo tiene (en la bahía, sin contar lo ya pedido; sin bahía, del tren detenido). 0 si no hay.
func wagon_amount_to_sell(item_id: StringName, player: Player = null) -> int:
	var bay: LoadingBay = get_bay()
	var cargos: Array[StorageContainer] = bay.get_cargos() if bay != null else StationGoods.new(_station, player).get_cargos()
	for cargo: StorageContainer in cargos:
		var count: int = cargo.count_of(item_id)
		if count > 0:
			return mini(count, bay.count_of(item_id)) if bay != null else count
	return 0


## Por qué no se puede comprar ni una ("" si se puede).
func why_not_buy(item_id: StringName, player: Player = null) -> String:
	var room: int = _room_for(GameState.economy.get_item(item_id), player)
	return reason_text(GameState.economy.why_not_buy(get_station_id(), item_id, GameState.money, room))


## Vende hasta `amount` (ALL: todo) de lo que el jugador tiene al alcance. Lo de la mano y la
## mochila (y sin bahía, lo del tren detenido) se cobra en el acto; lo que falta se pide al punto
## de carga, que lo descarga de a poco y se cobra al bajar (get_last_sell_queued). Devuelve
## cuántas vendió, contando las pedidas.
func sell(item_id: StringName, amount: int, player: Player = null) -> int:
	var economy: Economy = GameState.economy
	var goods: StationGoods = _goods(player)
	var bay: LoadingBay = get_bay()
	var item: ItemData = _find_item(goods, item_id)
	economy.register_item(item)
	_last_sell_queued = 0
	var have: int = goods.count_of(item_id) + (bay.count_of(item_id) if bay != null else 0)
	var planned: int = economy.plan_sell(get_station_id(), item_id, amount, have)
	if planned <= 0:
		return 0
	var taken: int = goods.take(item_id, planned)
	if taken > 0:
		var total: int = economy.record_sell(get_station_id(), item_id, taken, item)
		_finish_trade(item_id, -taken, total)
	if bay != null and taken < planned:
		_last_sell_queued = bay.order_unload(item_id, planned - taken)
	return taken + _last_sell_queued


## Por qué no se puede vender ni una ("" si se puede).
func why_not_sell(item_id: StringName, player: Player = null) -> String:
	var economy: Economy = GameState.economy
	if not is_open():
		return reason_text(&"closed")
	if economy.get_sell_price(get_station_id(), item_id) <= 0:
		return reason_text(&"no_value")
	var bay: LoadingBay = get_bay()
	if _goods(player).count_of(item_id) + (bay.count_of(item_id) if bay != null else 0) <= 0:
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


# Lo que el jugador tiene al alcance sin el punto de carga (con bahía, sin los vagones).
func _goods(player: Player) -> StationGoods:
	return StationGoods.new(_station, player, get_bay() == null)


# Cuántas de `item` se pueden comprar por lugar: en la bahía si hay vagones ahí; si no, en el tren
# detenido (sin bahía) y la mochila.
func _room_for(item: ItemData, player: Player) -> int:
	if buys_to_bay():
		return get_bay().room_for(item)
	return _goods(player).room_for(item)


func _find_item(goods: StationGoods, item_id: StringName) -> ItemData:
	var item: ItemData = goods.find_item(item_id)
	var bay: LoadingBay = get_bay()
	if item == null and bay != null:
		item = bay.find_item(item_id)
	return item


# El punto de carga bajó lo vendido: se cobra ahora, al precio de ahora.
func _on_bay_unloaded(item_id: StringName, amount: int) -> void:
	var total: int = GameState.economy.record_sell(get_station_id(), item_id, amount)
	_finish_trade(item_id, -amount, total)


func _find_station() -> Station:
	var node: Node = get_parent()
	while node != null:
		if node is Station:
			return node
		node = node.get_parent()
	return null
