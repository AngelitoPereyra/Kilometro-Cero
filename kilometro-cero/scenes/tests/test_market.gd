extends Node3D
## Prueba de la tarea 59: mercado (Economy, StationGoods, Market y MarketUI; D87, D96).
## Primero la lógica pura con una economía propia; después la escena: ciudad --(c_p)-- pueblo
## --(p_m)-- maderera, el tren con la plataforma vacía y el jugador en la ciudad. Al terminar
## vuelve a cargar la escena limpia para jugar (ver CONTROLES).

const CONTROLES: String = "WASD: caminar · F: cabina, mercado o tablero · T: pasa un día · P: suma $500\nComprá troncos en la maderera (el tren tiene que estar detenido en la estación) y vendelos donde faltan (ciudad, o el pueblo desde el nivel 2)."
const LOG_PATH: String = "res://data/items/log.tres"
## Pesos con que arranca la partida para jugar.
const START_MONEY: int = 500

## Ya se corrieron las comprobaciones: al recargar la escena queda solo para jugar.
static var _probado: bool = false

@onready var _ida: Path3D = $Ida
@onready var _ramal: Path3D = $Ramal
@onready var _loco: Vehicle = $Ida/Locomotive
@onready var _flatcar: Wagon = $Ida/Flatcar
@onready var _pueblo: Station = $Pueblo
@onready var _maderera: Station = $Maderera
@onready var _ciudad: Station = $Ciudad
@onready var _player: Player = $Player
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0
var _ventas: Array = []


func _ready() -> void:
	EventBus.item_traded.connect(func(station_id: StringName, item_id: StringName, amount: int, total: int) -> void: _ventas.append([station_id, item_id, amount, total]))
	if _probado:
		GameState.money = START_MONEY
		return
	_probado = true
	_probar_stock()
	_probar_precios()
	_probar_compra()
	_probar_venta()
	_probar_guardado()
	await _esperar_fisica(4)
	await _probar_escena()

	if _fallos == 0:
		print("Mercado: todas las comprobaciones pasaron.")
	else:
		push_error("Mercado: fallaron %d comprobaciones." % _fallos)
	# Partida limpia para jugar.
	GameState.money = 0
	GameState.reset_production()
	get_tree().reload_current_scene.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	var tecla := event as InputEventKey
	if tecla == null or not tecla.pressed or tecla.echo:
		return
	match tecla.physical_keycode:
		KEY_T:
			GameState.clock.advance(GameClock.HOURS_PER_DAY)
		KEY_P:
			GameState.add_money(START_MONEY)


func _process(_delta: float) -> void:
	var economia: Economy = GameState.economy
	var lineas: PackedStringArray = [CONTROLES, "Día %d · $%d · plataforma: %d troncos" % [
		GameState.clock.current_day, GameState.money, _flatcar.get_cargo().get_total() if _flatcar.get_cargo() != null else 0]]
	for estacion: Station in [_ciudad, _pueblo, _maderera]:
		var id: StringName = estacion.get_station_id()
		var estado: String = "mercado: %d troncos, a $%d, paga $%d" % [economia.get_stock_of(id, &"log"), economia.get_buy_price(id, &"log"), economia.get_sell_price(id, &"log")] if economia.has_market(id) else "sin mercado"
		lineas.append("%s · %s" % [estacion.describe(), estado])
	var cerca: Interactable = Interactable.find_nearest(get_tree(), _player.global_position, _player)
	if cerca != null:
		lineas.append("F: " + cerca.get_prompt())
	_hud.text = "\n".join(lineas)


# --- Lógica pura ---


func _probar_stock() -> void:
	var economia: Economy = _economia_hito()
	var modelo: ProductionModel = economia.production
	_comprobar(economia.get_stock(&"maderera") == _dic({&"log": 45}), "La maderera arranca con 3 días de producción (45 troncos)")
	_comprobar(economia.get_stock_of(&"pueblo", &"log") == 0 and economia.get_stock_of(&"ciudad", &"log") == 0, "Pueblo y ciudad no producen troncos: sin stock de troncos")
	_comprobar(economia.has_market(&"maderera") and economia.has_market(&"ciudad") and not economia.has_market(&"pueblo"), "Mercado en la maderera y la ciudad; el pueblo abre en el nivel 2")
	modelo.set_level(&"pueblo", 2)
	_comprobar(economia.has_market(&"pueblo"), "En el nivel 2 el pueblo abre su mercado")

	_comprobar(economia.record_buy(&"maderera", &"log", 30) == 240 and economia.get_stock_of(&"maderera", &"log") == 15, "Comprar 30 troncos a $8 cuesta $240 y quedan 15")
	_pasar_dia(economia)
	_comprobar(economia.get_stock_of(&"maderera", &"log") == 30, "Un día después junta 15 más")
	_pasar_dia(economia)
	_pasar_dia(economia)
	_comprobar(economia.get_stock_of(&"maderera", &"log") == 45, "No pasa del tope de 3 días (45)")

	economia.record_buy(&"maderera", &"log", 45)
	modelo.add_flow(&"maderera", &"pueblo", &"log", 10)
	_pasar_dia(economia)
	_comprobar(economia.get_stock_of(&"maderera", &"log") == 5, "Con un flujo de 10, el stock junta solo los 5 libres")
	modelo.connection_check = func(_desde: StringName, _hasta: StringName) -> bool: return false
	_pasar_dia(economia)
	_comprobar(economia.get_stock_of(&"maderera", &"log") == 20, "Con el flujo cortado junta los 15 (no salieron)")


func _probar_precios() -> void:
	var economia: Economy = _economia_hito()
	_comprobar(economia.get_buy_price(&"maderera", &"log") == 8 and economia.get_sell_price(&"maderera", &"log") == 6, "En la maderera el tronco vale $8 y paga $6 (barato donde se produce)")
	_comprobar(economia.get_buy_price(&"ciudad", &"log") == 15 and economia.get_sell_price(&"ciudad", &"log") == 12, "En la ciudad, que lo necesita: $15 y paga $12")
	economia.production.add_flow(&"maderera", &"pueblo", &"log", 10)
	_comprobar(economia.get_buy_price(&"pueblo", &"log") == 10 and economia.get_sell_price(&"pueblo", &"log") == 8, "En el pueblo con el consumo cubierto: precio normal $10 y paga $8")
	var sin_valor := _objeto(&"pebble", "piedrita", 0.0)
	economia.register_item(sin_valor)
	_comprobar(economia.get_buy_price(&"maderera", &"pebble") == 0 and economia.why_not_buy(&"maderera", &"pebble", 100, 10) == &"no_value", "Lo que no tiene valor no se comercia")
	var parejo: bool = true
	for estacion: StringName in [&"maderera", &"pueblo", &"ciudad"]:
		parejo = parejo and economia.get_sell_price(estacion, &"log") < economia.get_buy_price(estacion, &"log")
	_comprobar(parejo, "En todas las estaciones el mercado paga menos de lo que cobra (sin ganancia en el mismo lugar)")


func _probar_compra() -> void:
	var economia: Economy = _economia_hito()
	_comprobar(economia.plan_buy(&"maderera", &"log", 100, 10000, 100) == 45, "Se compra hasta lo que hay en stock (45)")
	_comprobar(economia.plan_buy(&"maderera", &"log", 100, 20, 100) == 2, "Con $20 alcanzan 2 troncos de $8")
	_comprobar(economia.plan_buy(&"maderera", &"log", 100, 10000, 3) == 3, "Con lugar para 3 se compran 3")
	_comprobar(economia.plan_buy(&"pueblo", &"log", 10, 10000, 100) == 0 and economia.why_not_buy(&"pueblo", &"log", 10000, 100) == &"closed", "Con el mercado cerrado no se compra")
	_comprobar(economia.why_not_buy(&"maderera", &"log", 5, 100) == &"no_money" and economia.why_not_buy(&"maderera", &"log", 100, 0) == &"no_room", "Motivos: sin plata, sin lugar")
	_comprobar(economia.why_not_buy(&"ciudad", &"log", 100, 100) == &"no_stock" and economia.why_not_buy(&"maderera", &"log", 100, 100) == &"", "Motivos: sin stock; en la maderera se puede")


func _probar_venta() -> void:
	var economia: Economy = _economia_hito()
	_comprobar(economia.plan_sell(&"ciudad", &"log", 30, 20) == 20 and economia.record_sell(&"ciudad", &"log", 20) == 240, "La ciudad compra 20 troncos a $12: $240")
	_comprobar(economia.get_stock_of(&"ciudad", &"log") == 20, "Lo vendido queda en el stock de la ciudad")
	_comprobar(economia.plan_sell(&"pueblo", &"log", 5, 5) == 0, "El pueblo sin mercado no compra")
	var piel := _objeto(&"fur", "piel", 5.0)
	_comprobar(economia.record_sell(&"ciudad", &"fur", 3, piel) == 12 and economia.name_of(&"fur") == "piel", "Algo que la ciudad no conocía también se vende ($4 cada piel) y queda registrado")
	_comprobar(economia.get_buy_price(&"ciudad", &"fur") == 5, "Y se puede volver a comprar a $5")
	economia.record_sell(&"ciudad", &"log", 200)
	_comprobar(economia.get_stock_of(&"ciudad", &"log") == 220, "Lo vendido no tiene tope")


func _probar_guardado() -> void:
	var economia: Economy = _economia_hito()
	economia.record_buy(&"maderera", &"log", 40)
	economia.record_sell(&"ciudad", &"log", 7)
	var guardado: Dictionary = JSON.parse_string(JSON.stringify(economia.to_dict()))
	var modelo := ProductionModel.new()
	var copia := Economy.new(modelo)
	copia.load_dict(guardado)
	for archivo: String in ["maderera", "pueblo", "ciudad"]:
		var datos: StationData = load("res://data/stations/%s.tres" % archivo)
		modelo.add_station(datos)
		copia.add_station(datos)
	_comprobar(copia.get_stock(&"maderera") == _dic({&"log": 5}) and copia.get_stock_of(&"ciudad", &"log") == 7, "El stock vuelve del guardado y no se rellena al registrar las estaciones")


# --- Escena ---


func _probar_escena() -> void:
	GameState.money = START_MONEY
	var mercado_pueblo: Market = _pueblo.get_node("Mercado")
	var mercado_maderera: Market = _maderera.get_node("Mercado")
	_comprobar(_ciudad.get_node("Mercado") is Market and mercado_maderera.is_open(), "Las tres plantillas tienen Mercado; el de la maderera está abierto")
	_comprobar(not mercado_pueblo.is_open() and not mercado_pueblo.can_interact(_player) and mercado_pueblo.build_text() == "Mercado cerrado: abre en el nivel 2", "El del pueblo está cerrado: %s" % mercado_pueblo.build_text())
	_comprobar(mercado_maderera.build_text().contains("tronco: 45 · a $8 (te paga $6)"), "El cartel de la maderera muestra stock y precios:\n%s" % mercado_maderera.build_text())

	# El tren llega a la maderera y el jugador va al mercado.
	_loco.place_on(_ramal, 138.0)
	await _esperar_fisica(6)
	_comprobar(_maderera.get_stopped_trains() == ([_loco] as Array[Vehicle]), "El tren está detenido en la maderera")
	_player.global_position = mercado_maderera.global_position + Vector3(1.5, 0.2, 0)
	await _esperar_fisica(2)
	_comprobar(Interactable.find_nearest(get_tree(), _player.global_position, _player) == mercado_maderera, "Lo más cercano para la F es el mercado")
	_comprobar(_player.try_interact(), "F abre el mercado")
	var ventana: MarketUI = mercado_maderera.get_ui()
	_comprobar(ventana.is_open() and not _player.controls_enabled and not GameState.clock_running, "La ventana abierta apaga los controles y pausa el reloj")
	_comprobar(ventana.get_row_count() == 1 and ventana.get_title_text() == "Mercado de Maderera · tenés $500", "Una fila (tronco) y el título con la plata: %s" % ventana.get_title_text())

	_comprobar(ventana.press_buy(&"log", 10) == 10 and _flatcar.get_cargo().get_total() == 10 and GameState.money == 420, "Comprar 10: se cargan en la plataforma y se pagan $80")
	_comprobar(_ventas == [[&"maderera", &"log", 10, 80]] and GameState.economy.get_stock_of(&"maderera", &"log") == 35, "Se avisó la compra y quedan 35 en la maderera")
	_comprobar(ventana.press_buy(&"log", Market.ALL) == 10 and _flatcar.get_cargo().get_total() == 20 and GameState.money == 340, "Comprar todo: solo entran 10 más (la plataforma lleva 20)")
	_comprobar(ventana.press_buy(&"log", 1) == 0 and ventana.get_status_text().begins_with("No hay lugar"), "Llena: no compra y avisa: %s" % ventana.get_status_text())
	ventana.set_open(false)
	_comprobar(not ventana.is_open() and _player.controls_enabled and GameState.clock_running, "Al cerrar vuelven los controles y el reloj")

	# En el pueblo: cerrado en el nivel 1; en el nivel 2 compra caro lo que le falta.
	_loco.place_on(_ida, 140.0)
	await _esperar_fisica(6)
	_comprobar(_pueblo.get_stopped_trains() == ([_loco] as Array[Vehicle]), "El tren está detenido en el pueblo")
	_comprobar(mercado_pueblo.sell(&"log", 5, _player) == 0, "Con el mercado cerrado no se vende")
	_pueblo.set_level(2)
	_comprobar(mercado_pueblo.is_open() and GameState.economy.get_sell_price(&"pueblo", &"log") == 12, "Nivel 2: abre y paga $12 por tronco (le faltan)")
	_comprobar(mercado_pueblo.sell(&"log", Market.ALL, _player) == 20 and _flatcar.get_cargo().get_total() == 0 and GameState.money == 580, "Vender todo: se descargan los 20 troncos y se cobran $240")
	_comprobar(_ventas.back() == [&"pueblo", &"log", -20, 240] and GameState.economy.get_stock_of(&"pueblo", &"log") == 20, "Se avisó la venta y el pueblo los tiene en stock")
	_comprobar(mercado_pueblo.buy(&"log", 5, _player) == 5 and GameState.money == 505 and _flatcar.get_cargo().get_total() == 5, "Recomprar 5 cuesta $15 cada uno")
	var tablero: StationBoard = _pueblo.get_node("Tablero")
	_comprobar(tablero.get_available() == _dic({&"log": 5}), "El tablero sigue viendo la carga del tren")

	# Objetos chicos: se venden y se compran desde la mochila.
	var piel := _objeto(&"fur", "piel", 5.0)
	var mochila: Inventory = _player.get_backpack()
	mochila.try_store(ItemStack.new(piel, 4))
	_player.global_position = mercado_pueblo.global_position + Vector3(1.5, 0.2, 0)
	await _esperar_fisica(2)
	var filas: Array[Dictionary] = mercado_pueblo.get_rows(_player)
	_comprobar(filas.size() == 2 and filas[1]["item_id"] == &"fur" and filas[1]["have"] == 4 and filas[1]["sell_price"] == 4, "Las pieles de la mochila aparecen en el mercado (te paga $4)")
	_comprobar(mercado_pueblo.sell(&"fur", 3, _player) == 3 and mochila.count_of(&"fur") == 1 and GameState.money == 517, "Se venden 3 pieles de la mochila")
	_comprobar(mercado_pueblo.buy(&"fur", 2, _player) == 2 and mochila.count_of(&"fur") == 3 and GameState.money == 507, "Se compran 2 pieles: van a la mochila")
	GameState.money = 0
	_comprobar(mercado_pueblo.buy(&"log", 1, _player) == 0 and mercado_pueblo.why_not_buy(&"log", _player) == "No te alcanza la plata.", "Sin plata no se compra")

	# Pasa un día: la maderera repone su stock.
	GameState.clock.advance(GameClock.HOURS_PER_DAY)
	_comprobar(GameState.economy.get_stock_of(&"maderera", &"log") == 40, "Un día después la maderera tiene 40 (25 + 15)")


# --- Ayudas ---


func _economia_hito() -> Economy:
	var modelo := ProductionModel.new()
	var economia := Economy.new(modelo)
	for archivo: String in ["maderera", "pueblo", "ciudad"]:
		var datos: StationData = load("res://data/stations/%s.tres" % archivo)
		modelo.add_station(datos)
		economia.add_station(datos)
	return economia


func _pasar_dia(economia: Economy) -> void:
	economia.production.advance_day()
	economia.advance_day()


func _objeto(id: StringName, nombre: String, valor: float) -> ItemData:
	var objeto := ItemData.new()
	objeto.id = id
	objeto.display_name = nombre
	objeto.base_value = valor
	return objeto


func _dic(valores: Dictionary) -> Dictionary[StringName, int]:
	var resultado: Dictionary[StringName, int] = {}
	for clave: StringName in valores:
		resultado[clave] = valores[clave]
	return resultado


func _esperar_fisica(pasos: int) -> void:
	for i: int in pasos:
		await get_tree().physics_frame


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
