class_name Economy
extends RefCounted
## Mercados y precios (D87, D96, tarea 59). Lógica pura: no sabe de escenas ni del dinero del
## jugador. GameState es dueño de una instancia (GameState.economy), la avanza un día después
## del modelo de producción y cobra o paga lo que dicen record_buy y record_sell.
## - Stock: cada estación junta lo que su producción no mandó por flujos ese día (la producción
##   libre de verdad, D95), hasta STOCK_DAYS días de su producción. Lo que vende el jugador
##   también entra al stock, sin tope. Una estación nueva arranca con el stock lleno.
## - Precios, solo en pesos (D96): el valor base del objeto (ItemData.base_value) por un factor
##   según la necesidad local: barato donde se produce, caro donde falta (consumo sin cubrir
##   hoy), normal en el resto. El mercado paga menos de lo que cobra (SELL_RATIO), así comprar y
##   vender en la misma estación nunca deja ganancia.
## - Solo comercia una estación con mercado abierto en su nivel (StationData.has_market) y solo
##   objetos con valor (base_value mayor a 0).

## Cambió el stock de una estación.
signal stock_changed(station_id: StringName)

## Días de producción que entran en el stock de una estación.
const STOCK_DAYS: int = 3
## Precio donde se produce el objeto.
const PRODUCER_FACTOR: float = 0.75
## Precio donde falta (la estación lo consume y hoy no le llega todo).
const NEED_FACTOR: float = 1.5
## Lo que paga el mercado al comprarle al jugador, sobre su precio de venta.
const SELL_RATIO: float = 0.8

var production: ProductionModel

# station_id -> (id de objeto -> unidades). Una estación está acá desde que se registró o se
# cargó de un guardado (así no se vuelve a llenar al registrarse).
var _stock: Dictionary[StringName, Dictionary] = {}
# id de objeto -> ItemData, para armar pilas al vender y mostrar nombres.
var _items: Dictionary[StringName, ItemData] = {}


func _init(model: ProductionModel = null) -> void:
	production = model if model != null else ProductionModel.new()


## Registra una estación: conoce sus objetos y, si es nueva, le llena el stock. La estación
## tiene que estar registrada antes en el modelo de producción (para saber su nivel).
func add_station(data: StationData) -> void:
	if data == null or data.id == &"":
		return
	for entry: ItemAmount in _amounts_of(data):
		register_item(entry.item)
	# Lo que piden y dan los oficios registrados en el modelo (bioma y rasgos, tarea 62b.2).
	for occupation: OccupationData in production.get_occupations():
		register_occupation(occupation)
	if _stock.has(data.id):
		return
	_stock[data.id] = {}
	for item_id: StringName in production.get_production(data.id):
		_stock[data.id][item_id] = get_stock_cap(data.id, item_id)
	stock_changed.emit(data.id)


## Recuerda un tipo de objeto (para armar pilas y mostrar su nombre).
func register_item(item: ItemData) -> void:
	if item != null and item.id != &"":
		_items[item.id] = item


## Recuerda los objetos que pide y da un oficio (tarea 62b.2).
func register_occupation(occupation: OccupationData) -> void:
	if occupation == null:
		return
	for entry: ItemAmount in occupation.needs + occupation.produces:
		if entry != null:
			register_item(entry.item)


func get_item(item_id: StringName) -> ItemData:
	return _items.get(item_id)


func name_of(item_id: StringName) -> String:
	var item: ItemData = get_item(item_id)
	return item.display_name if item != null and not item.display_name.is_empty() else String(item_id)


## Si un objeto se puede comprar y vender (tiene valor).
static func is_tradable(item: ItemData) -> bool:
	return item != null and item.base_value > 0.0


## Si la estación tiene el mercado abierto en su nivel actual.
func has_market(station_id: StringName) -> bool:
	var data: StationData = production.get_data(station_id)
	return data != null and data.has_market(production.get_level(station_id))


# --- Stock ---


## El stock de la estación (id de objeto -> unidades, sin los que quedaron en 0).
func get_stock(station_id: StringName) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	var stock: Dictionary = _stock.get(station_id, {})
	for item_id: StringName in stock:
		if int(stock[item_id]) > 0:
			result[item_id] = int(stock[item_id])
	return result


func get_stock_of(station_id: StringName, item_id: StringName) -> int:
	return int(_stock.get(station_id, {}).get(item_id, 0))


## Hasta cuánto junta por día (lo vendido por el jugador puede pasarlo).
func get_stock_cap(station_id: StringName, item_id: StringName) -> int:
	return production.get_production(station_id).get(item_id, 0) * STOCK_DAYS


## Suma (o resta, con negativo) unidades al stock, sin tope y sin bajar de 0.
func add_stock(station_id: StringName, item_id: StringName, amount: int) -> void:
	if station_id == &"" or item_id == &"" or amount == 0:
		return
	var stock: Dictionary = _stock.get(station_id, {})
	stock[item_id] = maxi(0, int(stock.get(item_id, 0)) + amount)
	_stock[station_id] = stock
	stock_changed.emit(station_id)


## Junta el día: a cada estación le entra lo que produjo y no salió por flujos (usa lo que
## entregó cada flujo ese día, ProductionFlow.last_delivered), hasta el tope. Se llama después
## de ProductionModel.advance_day.
func advance_day() -> void:
	for station_id: StringName in production.get_station_ids():
		var left: Dictionary[StringName, int] = production.get_production(station_id)
		for flow: ProductionFlow in production.get_flows_from(station_id):
			if left.has(flow.item_id):
				left[flow.item_id] = maxi(0, left[flow.item_id] - flow.last_delivered)
		var changed: bool = false
		for item_id: StringName in left:
			var current: int = get_stock_of(station_id, item_id)
			var added: int = mini(left[item_id], get_stock_cap(station_id, item_id) - current)
			if added > 0:
				var stock: Dictionary = _stock.get(station_id, {})
				stock[item_id] = current + added
				_stock[station_id] = stock
				changed = true
		if changed:
			stock_changed.emit(station_id)


# --- Precios ---


## Factor del precio local: PRODUCER_FACTOR donde se produce, NEED_FACTOR donde falta hoy, 1
## en el resto.
func get_price_factor(station_id: StringName, item_id: StringName) -> float:
	if production.get_production(station_id).get(item_id, 0) > 0:
		return PRODUCER_FACTOR
	if production.get_missing(station_id).has(item_id):
		return NEED_FACTOR
	return 1.0


## Lo que cobra la estación por unidad (0 si el objeto no tiene valor o no lo conoce).
func get_buy_price(station_id: StringName, item_id: StringName) -> int:
	var item: ItemData = get_item(item_id)
	if not is_tradable(item):
		return 0
	return maxi(1, roundi(item.base_value * get_price_factor(station_id, item_id)))


## Lo que paga la estación por unidad (0 si el objeto no tiene valor o no lo conoce).
func get_sell_price(station_id: StringName, item_id: StringName) -> int:
	var item: ItemData = get_item(item_id)
	if not is_tradable(item):
		return 0
	return maxi(1, floori(item.base_value * get_price_factor(station_id, item_id) * SELL_RATIO + 0.001))


# --- Compra y venta ---


## Cuántas unidades puede comprar el jugador: lo que pide, limitado por el stock, la plata
## (`money`) y el lugar donde llevarlas (`room`). 0 si no hay mercado o el objeto no tiene valor.
func plan_buy(station_id: StringName, item_id: StringName, wanted: int, money: int, room: int) -> int:
	var price: int = get_buy_price(station_id, item_id)
	if not has_market(station_id) or price <= 0 or wanted <= 0:
		return 0
	@warning_ignore("integer_division")
	var affordable: int = money / price
	return maxi(0, mini(mini(wanted, get_stock_of(station_id, item_id)), mini(affordable, room)))


## Por qué no se puede comprar ni una unidad (&"" si se puede): &"closed", &"no_value",
## &"no_stock", &"no_money" o &"no_room".
func why_not_buy(station_id: StringName, item_id: StringName, money: int, room: int) -> StringName:
	if not has_market(station_id):
		return &"closed"
	var price: int = get_buy_price(station_id, item_id)
	if price <= 0:
		return &"no_value"
	if get_stock_of(station_id, item_id) <= 0:
		return &"no_stock"
	if money < price:
		return &"no_money"
	if room <= 0:
		return &"no_room"
	return &""


## Anota una compra ya hecha: saca `amount` del stock. Devuelve lo que cuesta en total.
func record_buy(station_id: StringName, item_id: StringName, amount: int) -> int:
	if amount <= 0:
		return 0
	var total: int = get_buy_price(station_id, item_id) * amount
	add_stock(station_id, item_id, -amount)
	return total


## Cuántas puede vender el jugador de las que tiene (`have`). 0 sin mercado o sin valor.
func plan_sell(station_id: StringName, item_id: StringName, wanted: int, have: int) -> int:
	if not has_market(station_id) or get_sell_price(station_id, item_id) <= 0:
		return 0
	return maxi(0, mini(wanted, have))


## Anota una venta ya hecha: el objeto entra al stock (sin tope). Devuelve lo que se cobra en
## total. Si se pasa `item`, se registra (puede ser algo que la estación no conocía).
func record_sell(station_id: StringName, item_id: StringName, amount: int, item: ItemData = null) -> int:
	register_item(item)
	if amount <= 0:
		return 0
	var total: int = get_sell_price(station_id, item_id) * amount
	add_stock(station_id, item_id, amount)
	return total


# --- Guardado (tarea 65) ---


func to_dict() -> Dictionary:
	var stock: Dictionary = {}
	for station_id: StringName in _stock:
		var items: Dictionary = {}
		for item_id: StringName in _stock[station_id]:
			items[String(item_id)] = int(_stock[station_id][item_id])
		stock[String(station_id)] = items
	return {"stock": stock}


## Carga el stock. Las estaciones cargadas no se vuelven a llenar al registrarse.
func load_dict(values: Dictionary) -> void:
	_stock.clear()
	var stock: Dictionary = values.get("stock", {})
	for key: String in stock:
		var items: Dictionary = {}
		for item_key: String in stock[key]:
			items[StringName(item_key)] = int(stock[key][item_key])
		_stock[StringName(key)] = items


func _amounts_of(data: StationData) -> Array[ItemAmount]:
	var result: Array[ItemAmount] = []
	result.append_array(data.production)
	for level: StationLevelData in data.levels:
		if level != null:
			result.append_array(level.needs)
			result.append_array(level.extra_production)
	var valid: Array[ItemAmount] = []
	for entry: ItemAmount in result:
		if entry != null and entry.item != null:
			valid.append(entry)
	return valid
