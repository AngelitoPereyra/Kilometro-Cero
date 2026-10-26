extends Node3D
## Prueba de la tarea 60b: pasajeros (PassengerTraffic, PassengerCoach, CoachGift,
## ArrivalBuilding; D99, D103). Primero la lógica pura con modelos propios; después la escena:
## ciudad --(c_p)-- pueblo, el tren con la plataforma y el jugador en la ciudad. El coche sale
## del taller de la ciudad, se engancha marcha atrás y lleva colonos y la maestra con las
## puertas. Al terminar vuelve a cargar la escena limpia para jugar (ver CONTROLES).

const CONTROLES: String = "WASD: caminar · F: cabina, tablero, mercado o taller · O (en la cabina): abrir o cerrar las puertas\nT: pasa un día · R: 10 troncos a la plataforma · N: pueblo al nivel 2 · B: pueblo al nivel 3\nArreglá el coche en el taller de la ciudad (10 troncos), engánchalo marcha atrás, abrí las puertas en la ciudad y en el pueblo."
const LOG_PATH: String = "res://data/items/log.tres"
const SETTLERS_PATH: String = "res://data/items/settlers.tres"
const TEACHER_PATH: String = "res://data/items/teacher.tres"
const TRAVELERS_PATH: String = "res://data/items/travelers.tres"

## Ya se corrieron las comprobaciones: al recargar la escena queda solo para jugar.
static var _probado: bool = false

@onready var _linea: Path3D = $Linea
@onready var _loco: Vehicle = $Linea/Locomotive
@onready var _flatcar: Wagon = $Linea/Flatcar
@onready var _ciudad: Station = $Ciudad
@onready var _pueblo: Station = $Pueblo
@onready var _player: Player = $Player
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0
var _intercambios: Array = []


func _ready() -> void:
	_asegurar_tecla_puertas()
	EventBus.passengers_exchanged.connect(func(station_id: StringName, bajaron: int, subieron: int, tarifa: int) -> void: _intercambios.append([station_id, bajaron, subieron, tarifa]))
	if _probado:
		_preparar_juego.call_deferred()
		return
	_probado = true
	_probar_objetos()
	_probar_misiones()
	_probar_intercambio()
	_probar_demanda_y_trabajo()
	_probar_maestra()
	_probar_coche_regalo()
	_probar_guardado()
	await _esperar_fisica(4)
	await _probar_escena()

	if _fallos == 0:
		print("Pasajeros: todas las comprobaciones pasaron.")
	else:
		push_error("Pasajeros: fallaron %d comprobaciones." % _fallos)
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
		KEY_R:
			_flatcar.get_cargo().try_store(ItemStack.new(load(LOG_PATH), 10))
		KEY_N:
			_pueblo.set_level(2)
		KEY_B:
			_pueblo.set_level(3)


func _process(_delta: float) -> void:
	var coche: PassengerCoach = _buscar_coche()
	var traffic: PassengerTraffic = GameState.passengers
	var lineas: PackedStringArray = [CONTROLES, "Día %d · $%d · plataforma: %d troncos · coche: %s" % [
		GameState.clock.current_day, GameState.money, _flatcar.get_cargo().get_total() if _flatcar.get_cargo() != null else 0,
		PassengerTraffic.coach_state_name(traffic.coach_state)]]
	if coche != null:
		lineas.append("En el coche: %s · puertas %s" % [_texto(coche.get_aboard()), "abiertas" if coche.doors_open else "cerradas"])
	for estacion: Station in [_ciudad, _pueblo]:
		var id: StringName = estacion.get_station_id()
		lineas.append("%s · esperan %s · demanda hoy %d" % [estacion.describe(), _texto(_pasajeros_en_stock(id)), traffic.get_demand_left(id)])
	for flujo: ProductionFlow in GameState.production.get_flows():
		lineas.append("Flujo: " + flujo.describe())
	var cerca: Interactable = Interactable.find_nearest(get_tree(), _player.global_position, _player)
	if cerca != null:
		lineas.append("F: " + cerca.get_prompt())
	_hud.text = "\n".join(lineas)


func _preparar_juego() -> void:
	GameState.money = 0
	_pueblo.set_level(2)
	_flatcar.get_cargo().try_store(ItemStack.new(load(LOG_PATH), 10))


# La acción de las puertas la crea tools/setup_project.gd; si todavía no se corrió, la prueba
# la agrega para poder jugar.
func _asegurar_tecla_puertas() -> void:
	if InputMap.has_action(&"doors"):
		return
	InputMap.add_action(&"doors")
	var tecla := InputEventKey.new()
	tecla.physical_keycode = KEY_O
	InputMap.action_add_event(&"doors", tecla)


# --- Lógica pura ---


func _probar_objetos() -> void:
	var colono: ItemData = load(SETTLERS_PATH)
	var maestra: ItemData = load(TEACHER_PATH)
	var tronco: ItemData = load(LOG_PATH)
	_comprobar(ItemData.is_passenger(colono) and ItemData.is_passenger(maestra) and ItemData.is_passenger(load(TRAVELERS_PATH)), "Colono, maestra y pasajero son pasajeros")
	_comprobar(ItemData.is_specialist(maestra) and not ItemData.is_specialist(colono) and not ItemData.is_passenger(tronco), "La maestra es especialista; el tronco no es pasajero")
	_comprobar(not Economy.is_tradable(colono) and not Economy.is_tradable(maestra), "Los pasajeros no se compran ni se venden")
	var coche := StorageContainer.new()
	var datos: WagonData = load("res://data/vehicles/passenger_coach.tres")
	coche.configure(datos.capacity, datos.accepted_tags)
	var plataforma := StorageContainer.new()
	var datos_plataforma: WagonData = load("res://data/vehicles/flatcar.tres")
	plataforma.configure(datos_plataforma.capacity, datos_plataforma.accepted_tags)
	_comprobar(datos.cargo_type == WagonData.CargoType.PASSENGER and datos.capacity == 10, "El coche es de pasajeros y tiene 10 lugares")
	_comprobar(coche.accepts(colono) and not coche.accepts(tronco) and not plataforma.accepts(colono), "Al coche solo suben pasajeros; a la plataforma no")
	var mochila := Inventory.new()
	mochila.setup(load("res://data/items/backpack_basic.tres"))
	_comprobar(not mochila.accepts(colono) and mochila.can_store_amount(ItemStack.new(colono, 1)) == 0, "Un colono no entra en la mochila")
	coche.free()
	plataforma.free()
	mochila.free()


func _probar_misiones() -> void:
	var traffic: PassengerTraffic = _trafico_hito()
	var tablero: MissionBoard = traffic.missions
	tablero.production.set_level(&"pueblo", 2)
	var colonos: Mission = _principal(tablero, &"pueblo", &"settlers")
	_comprobar(colonos != null and colonos.flow_amount == 5 and colonos.required == _dic({&"settlers": 10}), "El pueblo nivel 2 pide 5 colonos por día: primera carga de 10 (un viaje)")
	_comprobar(colonos != null and tablero.get_title(colonos) == "Traer 5 colono por día", "Título: %s" % [tablero.get_title(colonos) if colonos != null else ""])
	_comprobar(colonos != null and tablero.find_source(colonos) == &"ciudad", "Los colonos salen de la ciudad")
	var pasos: PackedStringArray = tablero.get_pending_steps(colonos) if colonos != null else PackedStringArray()
	_comprobar(pasos.size() == 1 and pasos[0].begins_with("Traer 10 colono desde Ciudad"), "Paso pendiente: %s" % [pasos])
	_comprobar(tablero.get_passenger_missions_from(&"ciudad") == [colonos] and tablero.is_reserved_passenger(&"settlers") and not tablero.is_reserved_passenger(&"travelers"), "La ciudad tiene que mandar los colonos reservados; los pasajeros comunes no lo están")
	_comprobar(traffic.coach_state == PassengerTraffic.CoachState.REPAIRING and traffic.gift_station == &"ciudad", "Con el pedido, la ciudad deja el coche en reparación en su taller")


func _probar_intercambio() -> void:
	var traffic: PassengerTraffic = _trafico_hito()
	var tablero: MissionBoard = traffic.missions
	var economia: Economy = traffic.economy
	tablero.production.set_level(&"pueblo", 2)
	_comprobar(economia.get_stock_of(&"ciudad", &"settlers") == 30 and economia.get_stock_of(&"ciudad", &"travelers") == 30, "La ciudad arranca con 30 colonos y 30 pasajeros esperando")

	var plan: Dictionary = traffic.plan_exchange(&"ciudad", _dic({}), 10)
	_comprobar(plan["board_free"] == _dic({&"settlers": 10}) and plan["board_paid"].is_empty() and plan["fare"] == 0, "En la ciudad suben gratis los 10 colonos reservados (coche lleno)")
	plan = traffic.plan_exchange(&"ciudad", _dic({}), 14)
	_comprobar(plan["board_free"] == _dic({&"settlers": 10}) and plan["board_paid"] == _dic({&"travelers": 4}) and plan["fare"] == 8, "Con 14 lugares: 10 colonos gratis y 4 pasajeros que pagan $2 cada uno")
	_comprobar(traffic.apply_exchange(&"ciudad", plan) == 8, "Al aplicar se cobra la tarifa")
	_comprobar(economia.get_stock_of(&"ciudad", &"settlers") == 20 and economia.get_stock_of(&"ciudad", &"travelers") == 26, "Salen del stock de la ciudad")
	_comprobar(traffic.plan_exchange(&"ciudad", _dic({&"settlers": 10, &"travelers": 4}), 14)["board_free"].is_empty(), "Con los colonos a bordo no sube ninguno más")

	plan = traffic.plan_exchange(&"maderera", _dic({&"settlers": 10, &"travelers": 4}), 14)
	_comprobar(plan["mission"].is_empty() and plan["alight"] == _dic({&"travelers": 3}), "En la maderera los colonos siguen (reservados) y bajan 3 pasajeros (su demanda)")

	plan = traffic.plan_exchange(&"pueblo", _dic({&"settlers": 10, &"travelers": 4}), 14)
	_comprobar(plan["mission"] == _dic({&"settlers": 10}) and plan["alight"] == _dic({&"travelers": 4}), "En el pueblo bajan los 10 colonos para la misión y los 4 pasajeros")
	_comprobar(plan["board_paid"] == _dic({&"travelers": 9}) and plan["fare"] == 18, "Y suben 9 pasajeros del pueblo hacia la ciudad ($18)")
	traffic.apply_exchange(&"pueblo", plan)
	var colonos: Mission = _principal_cumplida(tablero, &"pueblo", &"settlers")
	_comprobar(colonos != null and colonos.flow != null and colonos.flow.round_trip and colonos.flow.describe() == "5 settlers de ciudad a pueblo, ida y vuelta", "Cumplida: nace el flujo de 5 colonos por día de ida y vuelta")
	_comprobar(not tablero.is_reserved_passenger(&"settlers"), "Sin principal activa, los colonos ya no están reservados")


func _probar_demanda_y_trabajo() -> void:
	var traffic: PassengerTraffic = _trafico_hito()
	var economia: Economy = traffic.economy
	_comprobar(traffic.get_demand(&"ciudad") == 8 and traffic.get_demand(&"pueblo") == 4 and traffic.get_demand(&"maderera") == 3, "Demanda por día: ciudad 8, pueblo 4, maderera 3 (nivel 1)")
	traffic.production.set_level(&"pueblo", 2)
	_comprobar(traffic.get_demand(&"pueblo") == 8, "El pueblo en nivel 2 recibe 8")
	_comprobar(traffic.get_work_product(&"maderera") == &"log" and traffic.get_work_product(&"pueblo") == &"", "La gente que baja en la maderera trabaja en los troncos; el pueblo no produce cosas todavía")
	economia.record_buy(&"maderera", &"log", 45)
	var plan: Dictionary = traffic.plan_exchange(&"maderera", _dic({&"travelers": 5}), 10)
	traffic.apply_exchange(&"maderera", plan)
	_comprobar(plan["alight"] == _dic({&"travelers": 3}) and plan["work"] == _dic({&"log": 1}) and economia.get_stock_of(&"maderera", &"log") == 1, "Bajan 3 (la demanda): suman 1 tronco al stock y queda 1 persona para la próxima")
	_comprobar(traffic.get_demand_left(&"maderera") == 0 and traffic.plan_exchange(&"maderera", _dic({&"travelers": 2}), 10)["alight"].is_empty(), "Sin demanda hoy, nadie más baja ahí")
	traffic.advance_day()
	plan = traffic.plan_exchange(&"maderera", _dic({&"travelers": 2}), 10)
	traffic.apply_exchange(&"maderera", plan)
	_comprobar(plan["alight"] == _dic({&"travelers": 2}) and plan["work"] == _dic({&"log": 1}), "Al otro día vuelve la demanda: bajan 2 y con el que sobraba suman otro tronco")


func _probar_maestra() -> void:
	var traffic: PassengerTraffic = _trafico_hito()
	var tablero: MissionBoard = traffic.missions
	tablero.production.set_level(&"pueblo", 3)
	var maestra: Mission = _principal(tablero, &"pueblo", &"teacher")
	_comprobar(maestra != null and maestra.flow_amount == 1 and maestra.required == _dic({&"teacher": 1}), "El pueblo nivel 3 pide una maestra: primera carga de una sola")
	var plan: Dictionary = traffic.plan_exchange(&"ciudad", _dic({}), 10)
	_comprobar(plan["board_free"] == _dic({&"teacher": 1, &"settlers": 9}), "La maestra sube primero y gratis (después 9 de los colonos que también se piden)")
	traffic.apply_exchange(&"ciudad", plan)
	traffic.apply_exchange(&"pueblo", traffic.plan_exchange(&"pueblo", _dic({&"teacher": 1}), 10))
	maestra = _principal_cumplida(tablero, &"pueblo", &"teacher")
	_comprobar(maestra != null and maestra.flow != null and maestra.flow.round_trip and maestra.flow.amount == 1, "Al llegar nace un flujo de 1 maestra por día, de ida y vuelta")
	var otra: PassengerTraffic = _trafico_hito()
	_comprobar(otra.plan_exchange(&"ciudad", _dic({}), 10)["board_paid"].get(&"teacher", 0) == 0, "Sin pedido, la maestra no sube como pasajera común")


func _probar_coche_regalo() -> void:
	var traffic: PassengerTraffic = _trafico_hito()
	_comprobar(traffic.coach_state == PassengerTraffic.CoachState.NONE, "Sin pedidos de pasajeros no hay coche")
	traffic.production.set_level(&"pueblo", 2)
	var costo: Dictionary[StringName, int] = _dic({&"log": 10})
	_comprobar(traffic.add_repair(&"log", 4, costo) == 4 and traffic.get_repair_remaining(costo) == _dic({&"log": 6}), "Con 4 troncos faltan 6")
	_comprobar(traffic.add_repair(&"log", 10, costo) == 6 and traffic.coach_state == PassengerTraffic.CoachState.READY, "Con 6 más queda listo (no acepta de más)")
	_comprobar(not traffic.offer_coach(&"ciudad"), "Se regala una sola vez")
	traffic.mark_coach_delivered()
	_comprobar(traffic.coach_state == PassengerTraffic.CoachState.DELIVERED, "Al salir a la vía queda entregado")


func _probar_guardado() -> void:
	var traffic: PassengerTraffic = _trafico_hito()
	traffic.production.set_level(&"pueblo", 2)
	traffic.add_repair(&"log", 3, _dic({&"log": 10}))
	traffic.apply_exchange(&"maderera", traffic.plan_exchange(&"maderera", _dic({&"travelers": 1}), 10))
	var guardado: Dictionary = JSON.parse_string(JSON.stringify(traffic.to_dict()))
	var copia: PassengerTraffic = _trafico_hito()
	copia.load_dict(guardado)
	_comprobar(copia.coach_state == PassengerTraffic.CoachState.REPAIRING and copia.gift_station == &"ciudad" and copia.repair_delivered == _dic({&"log": 3}), "El coche en reparación vuelve del guardado")
	_comprobar(copia.get_demand_left(&"maderera") == 2, "La demanda usada hoy también")
	var flujo := ProductionFlow.new(&"ciudad", &"pueblo", &"settlers", 5)
	flujo.round_trip = true
	_comprobar(ProductionFlow.from_dict(JSON.parse_string(JSON.stringify(flujo.to_dict()))).round_trip, "El flujo de ida y vuelta se guarda")


# --- Escena ---


func _probar_escena() -> void:
	var tablero_pueblo: StationBoard = _pueblo.get_node("Tablero")
	var taller: CoachGift = _ciudad.get_node("Taller")
	var cab: Cab = _loco.get_node("Cab")
	var traffic: PassengerTraffic = GameState.passengers
	_comprobar(taller.get_state() == PassengerTraffic.CoachState.NONE and not taller.get_node("CocheEnReparacion").visible, "Sin pedidos, el taller está vacío")

	_pueblo.set_level(2)
	await _esperar_fisica(2)
	taller.refresh()
	_comprobar(taller.get_state() == PassengerTraffic.CoachState.REPAIRING and taller.get_node("CocheEnReparacion").visible, "Con el pedido de colonos, el taller de la ciudad muestra el coche en reparación")
	_comprobar(tablero_pueblo.build_text().contains("repararlo en el taller de Ciudad"), "El tablero del pueblo dice dónde está el coche")
	_comprobar(cab.toggle_doors() == false, "Sin coche no hay puertas que abrir")

	# Reparación con troncos de la plataforma (el tren está detenido en la ciudad).
	_flatcar.get_cargo().try_store(ItemStack.new(load(LOG_PATH), 12))
	_player.global_position = taller.global_position + Vector3(2, 0.3, 0)
	await _esperar_fisica(3)
	_comprobar(_ciudad.get_stopped_trains().has(_loco), "El tren está detenido en la ciudad")
	_comprobar(taller.get_repair_plan(_player) == _dic({&"log": 10}) and taller.can_interact(_player), "F en el taller entregaría 10 troncos")
	_comprobar(taller.repair(_player) == _dic({&"log": 10}) and _flatcar.get_cargo().get_total() == 2, "Se entregan los 10 troncos de la plataforma")
	var coche: PassengerCoach = taller.get_coach()
	_comprobar(coche != null and traffic.coach_state == PassengerTraffic.CoachState.DELIVERED and coche.get_parent() == _linea, "Reparado, el coche sale a la vía")
	if coche == null:
		return
	_comprobar(absf(coche.progress - 10.0) < 0.5, "Sale frente a la salida del taller (avance %.1f)" % coche.progress)
	_comprobar(not taller.can_interact(_player), "El taller ya no pide nada")

	# Enganche: marcha atrás hasta tocarlo con la cola.
	_loco.throttle = -0.5
	var pasos: int = 0
	while coche.front == null and pasos < 900:
		await get_tree().physics_frame
		pasos += 1
	_loco.throttle = 0.0
	_loco.brake = 1.0
	_comprobar(coche.front == _flatcar, "Marcha atrás, la cola toca el coche y se engancha (tren mixto)")
	pasos = 0
	while absf(_loco.speed) > 0.05 and pasos < 300:
		await get_tree().physics_frame
		pasos += 1
	_loco.brake = 0.0
	await _esperar_fisica(3)
	_comprobar(_ciudad.get_stopped_trains().has(_loco), "El tren mixto queda detenido en la ciudad")

	# Puertas en la ciudad: suben los 10 colonos reservados, gratis.
	_intercambios.clear()
	_comprobar(cab.toggle_doors() and coche.doors_open, "O en la cabina abre las puertas")
	_comprobar(coche.get_aboard() == _dic({&"settlers": 10}) and GameState.money == 0, "Suben los 10 colonos gratis: el coche va lleno")
	_comprobar(_intercambios == [[&"ciudad", 0, 10, 0]], "Se avisa el intercambio (EventBus.passengers_exchanged)")
	_comprobar(_sentados(coche) == 10 and not coche.get_node("Visual/Puertas").visible, "Se ven 10 sentados y las puertas abiertas")
	_comprobar(tablero_pueblo.get_available().is_empty(), "El tablero no ofrece entregar pasajeros")
	_comprobar(cab.toggle_doors() and not coche.doors_open, "O otra vez las cierra")

	# Al pueblo (se ubica el tren en la estación).
	_loco.place_on(_linea, 250.0)
	await _esperar_fisica(4)
	_comprobar(_pueblo.get_stopped_trains().has(_loco), "El tren está en el pueblo")
	_comprobar(cab.toggle_doors(), "Se abren las puertas en el pueblo")
	var colonos: Mission = _principal_cumplida(GameState.missions, &"pueblo", &"settlers")
	_comprobar(colonos != null and colonos.flow != null and colonos.flow.round_trip, "Bajan los colonos: la principal se cumple y nace el flujo de ida y vuelta")
	_comprobar(coche.get_aboard() == _dic({&"travelers": 9}) and GameState.money == 18, "Suben 9 pasajeros del pueblo hacia la ciudad y pagan $18")

	# Las puertas se cierran solas al arrancar.
	_loco.throttle = 0.5
	pasos = 0
	while coche.doors_open and pasos < 300:
		await get_tree().physics_frame
		pasos += 1
	_comprobar(not coche.doors_open, "Al arrancar, las puertas se cierran solas")
	_loco.throttle = 0.0
	_loco.brake = 1.0
	await _esperar_fisica(60)
	_loco.brake = 0.0
	_loco.place_on(_linea, 140.0)
	await _esperar_fisica(4)
	_comprobar(not cab.toggle_doors() and not coche.doors_open, "Entre estaciones no se abren")

	# La maestra: el pueblo en nivel 3 la pide; viaja y abre la escuela.
	var escuela: ArrivalBuilding = _pueblo.get_node("Niveles/Nivel3/Escuela")
	_pueblo.set_level(3)
	await _esperar_fisica(2)
	_comprobar(not escuela.visible, "Sin maestra no hay escuela")
	_loco.place_on(_linea, 40.0)
	await _esperar_fisica(4)
	cab.toggle_doors()
	_comprobar(coche.get_aboard().get(&"teacher", 0) == 1 and _intercambios.back()[1] == 8, "En la ciudad bajan 8 pasajeros (su demanda) y sube la maestra")
	cab.toggle_doors()
	_loco.place_on(_linea, 250.0)
	await _esperar_fisica(4)
	cab.toggle_doors()
	_comprobar(coche.get_aboard().get(&"teacher", 0) == 0 and _principal_cumplida(GameState.missions, &"pueblo", &"teacher") != null, "En el pueblo baja la maestra y se cumple su principal")
	await get_tree().create_timer(0.7).timeout
	_comprobar(escuela.visible and escuela.is_open(), "Aparece la escuela")

	# Nunca a la mano.
	var grabber: Grabber = _player.get_node("Grabber")
	_comprobar(grabber._plan_for(ItemStack.new(load(SETTLERS_PATH), 1)) == &"passenger" and coche.get_node_or_null("ZonaDeCarga") == null, "Los pasajeros no se agarran: el coche no tiene zona de carga")


# --- Ayudas ---


func _trafico_hito() -> PassengerTraffic:
	var modelo := ProductionModel.new()
	var economia := Economy.new(modelo)
	var tablero := MissionBoard.new(modelo)
	var traffic := PassengerTraffic.new(tablero, economia)
	for archivo: String in ["maderera", "pueblo", "ciudad"]:
		var datos: StationData = load("res://data/stations/%s.tres" % archivo)
		modelo.add_station(datos)
		economia.add_station(datos)
	tablero.refresh()
	traffic.check_offer()
	return traffic


func _principal(tablero: MissionBoard, estacion: StringName, objeto: StringName) -> Mission:
	for mision: Mission in tablero.get_main_missions(estacion):
		if mision.item_id == objeto:
			return mision
	return null


func _principal_cumplida(tablero: MissionBoard, estacion: StringName, objeto: StringName) -> Mission:
	for mision: Mission in tablero.get_missions():
		if mision.main and mision.station_id == estacion and mision.item_id == objeto and mision.is_completed():
			return mision
	return null


func _buscar_coche() -> PassengerCoach:
	for nodo: Node in _linea.get_children():
		if nodo is PassengerCoach:
			return nodo
	return null


func _sentados(coche: PassengerCoach) -> int:
	var cuantos: int = 0
	for figura: Node in coche.get_node("Visual/Pasajeros").get_children():
		if (figura as Node3D).visible:
			cuantos += 1
	return cuantos


func _pasajeros_en_stock(estacion: StringName) -> Dictionary[StringName, int]:
	var resultado: Dictionary[StringName, int] = {}
	var stock: Dictionary[StringName, int] = GameState.economy.get_stock(estacion)
	for objeto: StringName in stock:
		if GameState.passengers.is_passenger(objeto):
			resultado[objeto] = stock[objeto]
	return resultado


func _texto(cantidades: Dictionary) -> String:
	if cantidades.is_empty():
		return "nadie"
	var partes: PackedStringArray = []
	for objeto: StringName in cantidades:
		partes.append("%d %s" % [cantidades[objeto], GameState.economy.name_of(objeto)])
	return ", ".join(partes)


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
