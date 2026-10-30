class_name PassengerTraffic
extends RefCounted
## Pasajeros (D99, D103, tarea 60b). Lógica pura, como el ProductionModel, el MissionBoard y la
## Economy a los que mira; GameState tiene la instancia del juego (GameState.passengers).
## Los pasajeros son objetos con la etiqueta ItemData.PASSENGER_TAG: se producen en las
## estaciones (la ciudad da colonos, maestras y pasajeros comunes), esperan en su stock y solo
## viajan en coches de pasajeros. Nunca van a la mano, a la mochila ni a una grúa.
## Al abrir las puertas de un coche detenido en una estación (PassengerCoach.set_doors), pasa
## esto, en orden (plan_exchange y apply_exchange):
## 1. Bajan los reservados para las principales de esa estación y se entregan a las misiones.
## 2. Bajan los sobrantes (los que ninguna principal espera) según la demanda del lugar: siempre
##    hay (DEMAND_PER_LEVEL por el nivel, por día). Cada WORKERS_PER_UNIT que bajan suman una
##    unidad de lo que produce la estación a su stock (gente que viene a trabajar).
## 3. Suben gratis los que faltan para las principales que salen de esa estación (reservados),
##    primero los especialistas.
## 4. Con los lugares que quedan suben sobrantes del stock, que pagan FARE cada uno al subir.
## La familia de una mudanza (tarea 62b.6) espera en su estación aunque no esté en el stock: sube
## gratis en el paso 3 (MissionBoard.boards_without_stock).
## También lleva el coche que regala la ciudad (D103): aparece en reparación en el taller de la
## ciudad con el primer pedido de pasajeros, se repara con materiales (CoachGift) y sale una sola
## vez por partida.

## Cambió el estado del coche de regalo.
signal coach_state_changed(state: CoachState)
## Se hizo un intercambio de pasajeros en una estación (el resultado de plan_exchange).
signal exchanged(station_id: StringName, result: Dictionary)

## NONE: nadie pidió pasajeros. REPAIRING: está en el taller esperando materiales. READY:
## reparado, falta sacarlo a la vía. DELIVERED: ya está en la vía (o enganchado).
enum CoachState { NONE, REPAIRING, READY, DELIVERED }

const COACH_STATE_NAMES: Array[String] = ["sin pedido", "en reparación", "listo", "entregado"]
## Tarifa mínima en pesos que paga cada pasajero sobrante al subir.
const FARE: int = 2
## Pasajeros sobrantes que una estación recibe por día y por nivel, según su tipo
## (StationData.StationType: ciudad, pueblo, carga, puerto).
const DEMAND_PER_LEVEL: Array[int] = [8, 4, 3, 8]
## Pasajeros sobrantes que tienen que bajar para sumar una unidad de producción al stock.
const WORKERS_PER_UNIT: int = 2

var production: ProductionModel
var missions: MissionBoard
var economy: Economy
var coach_state: CoachState = CoachState.NONE
## La ciudad que regala el coche (su taller lo muestra).
var gift_station: StringName = &""
## Lo entregado para reparar el coche: id de objeto -> unidades.
var repair_delivered: Dictionary[StringName, int] = {}

# station_id -> pasajeros sobrantes que ya bajaron hoy.
var _demand_used: Dictionary[StringName, int] = {}
# station_id -> pasajeros que bajaron y todavía no llegan a sumar una unidad.
var _workers: Dictionary[StringName, int] = {}


func _init(board: MissionBoard = null, market: Economy = null) -> void:
	missions = board if board != null else MissionBoard.new()
	production = missions.production
	economy = market if market != null else Economy.new(production)
	missions.mission_available.connect(_on_mission_available)


static func coach_state_name(value: CoachState) -> String:
	return COACH_STATE_NAMES[value]


## Olvida el coche y las demandas (partida nueva).
func clear() -> void:
	coach_state = CoachState.NONE
	gift_station = &""
	repair_delivered.clear()
	_demand_used.clear()
	_workers.clear()


## Un día nuevo: vuelve la demanda. Se llama después de Economy.advance_day.
func advance_day() -> void:
	_demand_used.clear()


# --- Demanda ---


## Pasajeros sobrantes que la estación recibe por día en su nivel.
func get_demand(station_id: StringName) -> int:
	var data: StationData = production.get_data(station_id)
	if data == null:
		return 0
	return DEMAND_PER_LEVEL[data.type] * production.get_level(station_id)


## Los que todavía puede recibir hoy.
func get_demand_left(station_id: StringName) -> int:
	return maxi(0, get_demand(station_id) - _demand_used.get(station_id, 0))


## Lo que suma al stock la gente que baja: lo primero que produce que no sea un pasajero
## (&"" si no produce nada).
func get_work_product(station_id: StringName) -> StringName:
	for item_id: StringName in production.get_production(station_id):
		if not is_passenger(item_id):
			return item_id
	return &""


func is_passenger(item_id: StringName) -> bool:
	return ItemData.is_passenger(economy.get_item(item_id)) or missions.is_passenger(item_id)


# --- Intercambio al abrir las puertas ---


## Qué pasaría al abrir las puertas de un coche en la estación. `aboard`: pasajeros a bordo
## (id -> unidades); `capacity`: lugares del coche. Devuelve un diccionario con:
## "mission" (bajan para las principales de acá), "alight" (sobrantes que bajan), "board_free"
## (suben reservados), "board_paid" (sobrantes que suben) y "fare" (pesos que pagan).
func plan_exchange(station_id: StringName, aboard: Dictionary[StringName, int], capacity: int) -> Dictionary:
	var to_mission: Dictionary[StringName, int] = {}
	var alight: Dictionary[StringName, int] = {}
	var board_free: Dictionary[StringName, int] = {}
	var board_paid: Dictionary[StringName, int] = {}
	var left: Dictionary[StringName, int] = aboard.duplicate()
	# 1. Los reservados para las misiones de esta estación (principales y, desde la 62,
	# secundarias que piden gente).
	var wanted: Dictionary[StringName, int] = {}
	for mission: Mission in missions.get_active_missions(station_id):
		var mission_needs: Dictionary[StringName, int] = missions.get_passenger_needs(mission)
		for item_id: StringName in mission_needs:
			wanted[item_id] = wanted.get(item_id, 0) + mission_needs[item_id]
	for item_id: StringName in left:
		var amount: int = mini(left[item_id], wanted.get(item_id, 0))
		if amount > 0:
			to_mission[item_id] = amount
			left[item_id] -= amount
	# 2. Los sobrantes, según la demanda del lugar.
	var demand: int = get_demand_left(station_id)
	for item_id: StringName in left:
		if missions.is_reserved_passenger(item_id):
			continue
		var amount: int = mini(left[item_id], demand)
		if amount > 0:
			alight[item_id] = amount
			left[item_id] -= amount
			demand -= amount
	var seats: int = capacity - _sum(left)
	# 3. Suben gratis los que faltan para las misiones que salen de acá.
	var needed: Dictionary[StringName, int] = {}
	# Los que esperan fuera del stock (la familia de una mudanza, tarea 62b.6).
	var waiting: Dictionary[StringName, int] = {}
	for mission: Mission in missions.get_passenger_missions_from(station_id):
		var mission_needs: Dictionary[StringName, int] = missions.get_passenger_needs(mission)
		for item_id: StringName in mission_needs:
			if missions.passenger_source(mission, item_id) == station_id:
				needed[item_id] = needed.get(item_id, 0) + mission_needs[item_id]
				if missions.boards_without_stock(mission):
					waiting[item_id] = waiting.get(item_id, 0) + mission_needs[item_id]
	# Primero los especialistas: son pocos y abren edificios.
	var order: Array[StringName] = []
	for item_id: StringName in needed:
		if ItemData.is_specialist(economy.get_item(item_id)):
			order.push_front(item_id)
		else:
			order.append(item_id)
	for item_id: StringName in order:
		var amount: int = mini(mini(needed[item_id] - left.get(item_id, 0), economy.get_stock_of(station_id, item_id) + waiting.get(item_id, 0)), seats)
		if amount > 0:
			board_free[item_id] = amount
			seats -= amount
	# 4. Con los lugares libres, sobrantes que pagan.
	var fare: int = 0
	var stock: Dictionary[StringName, int] = economy.get_stock(station_id)
	for item_id: StringName in stock:
		if seats <= 0:
			break
		# Los especialistas solo viajan para su misión.
		if not is_passenger(item_id) or missions.is_reserved_passenger(item_id) or ItemData.is_specialist(economy.get_item(item_id)):
			continue
		var amount: int = mini(stock[item_id] - board_free.get(item_id, 0), seats)
		if amount > 0:
			board_paid[item_id] = amount
			seats -= amount
			fare += amount * FARE
	return {"mission": to_mission, "alight": alight, "board_free": board_free, "board_paid": board_paid, "fare": fare}


## Aplica un plan de plan_exchange (la gente ya se movió en el coche): entrega a las misiones,
## gasta la demanda, suma el trabajo de los que bajaron y saca del stock a los que subieron.
## Agrega "work" (id -> unidades sumadas al stock) al plan. Devuelve la tarifa cobrada.
func apply_exchange(station_id: StringName, plan: Dictionary) -> int:
	var to_mission: Dictionary = plan.get("mission", {})
	for item_id: StringName in to_mission:
		missions.deliver(station_id, item_id, int(to_mission[item_id]))
	var alighted: int = _sum(plan.get("alight", {}))
	var work: Dictionary[StringName, int] = {}
	if alighted > 0:
		_demand_used[station_id] = _demand_used.get(station_id, 0) + alighted
		var workers: int = _workers.get(station_id, 0) + alighted
		var product: StringName = get_work_product(station_id)
		var units: int = floori(float(workers) / float(WORKERS_PER_UNIT))
		if product != &"" and units > 0:
			economy.add_stock(station_id, product, units)
			work[product] = units
		_workers[station_id] = workers % WORKERS_PER_UNIT
	for key: String in ["board_free", "board_paid"]:
		var boarded: Dictionary = plan.get(key, {})
		for item_id: StringName in boarded:
			# Solo sale del stock lo que estaba (la familia de una mudanza esperaba afuera).
			var from_stock: int = mini(int(boarded[item_id]), economy.get_stock_of(station_id, item_id))
			if from_stock > 0:
				economy.add_stock(station_id, item_id, -from_stock)
	plan["work"] = work
	exchanged.emit(station_id, plan)
	return int(plan.get("fare", 0))


# --- Coche de regalo ---


## La ciudad ofrece el coche (lo deja en reparación en su taller). False si ya se ofreció.
func offer_coach(station_id: StringName) -> bool:
	if coach_state != CoachState.NONE or station_id == &"":
		return false
	gift_station = station_id
	_set_coach_state(CoachState.REPAIRING)
	return true


## Lo que falta entregar para reparar el coche, según lo que cuesta (id -> unidades).
func get_repair_remaining(cost: Dictionary[StringName, int]) -> Dictionary[StringName, int]:
	var remaining: Dictionary[StringName, int] = {}
	for item_id: StringName in cost:
		var lacking: int = cost[item_id] - repair_delivered.get(item_id, 0)
		if lacking > 0:
			remaining[item_id] = lacking
	return remaining


## Suma materiales a la reparación sin pasarse; al completarla el coche queda listo. Devuelve
## cuánto aceptó.
func add_repair(item_id: StringName, amount: int, cost: Dictionary[StringName, int]) -> int:
	if coach_state != CoachState.REPAIRING:
		return 0
	var accepted: int = mini(amount, get_repair_remaining(cost).get(item_id, 0))
	if accepted > 0:
		repair_delivered[item_id] = repair_delivered.get(item_id, 0) + accepted
	if get_repair_remaining(cost).is_empty():
		_set_coach_state(CoachState.READY)
	return accepted


## El coche ya salió a la vía.
func mark_coach_delivered() -> void:
	if coach_state == CoachState.READY:
		_set_coach_state(CoachState.DELIVERED)


## Si hay una principal de pasajeros activa y el coche todavía no se ofreció, lo ofrece. Se
## llama sola con cada principal nueva; el taller (CoachGift) la vuelve a llamar por si la
## principal nació antes de que la ciudad se registrara.
func check_offer() -> void:
	if coach_state != CoachState.NONE:
		return
	for mission: Mission in missions.get_missions():
		if mission.main and mission.is_active() and is_passenger(mission.item_id) and offer_coach(_gift_city_for(mission)):
			return


func _on_mission_available(mission: Mission) -> void:
	if coach_state == CoachState.NONE and mission.main and is_passenger(mission.item_id):
		offer_coach(_gift_city_for(mission))


# La ciudad de donde salen los pasajeros; si no es una ciudad, la primera ciudad registrada.
func _gift_city_for(mission: Mission) -> StringName:
	var source: StringName = missions.find_source(mission)
	var source_data: StationData = production.get_data(source)
	if source_data != null and source_data.type == StationData.StationType.CITY:
		return source
	for station_id: StringName in production.get_station_ids():
		if production.get_data(station_id).type == StationData.StationType.CITY:
			return station_id
	return source


func _set_coach_state(value: CoachState) -> void:
	coach_state = value
	coach_state_changed.emit(value)


static func _sum(amounts: Dictionary) -> int:
	var total: int = 0
	for key: Variant in amounts:
		total += int(amounts[key])
	return total


# --- Guardado (tarea 65) ---


func to_dict() -> Dictionary:
	var repair: Dictionary = {}
	for item_id: StringName in repair_delivered:
		repair[String(item_id)] = repair_delivered[item_id]
	var used: Dictionary = {}
	for station_id: StringName in _demand_used:
		used[String(station_id)] = _demand_used[station_id]
	var workers: Dictionary = {}
	for station_id: StringName in _workers:
		workers[String(station_id)] = _workers[station_id]
	return {"coach": coach_state, "gift_station": String(gift_station), "repair": repair, "demand_used": used, "workers": workers}


func load_dict(values: Dictionary) -> void:
	clear()
	coach_state = int(values.get("coach", CoachState.NONE)) as CoachState
	gift_station = StringName(values.get("gift_station", ""))
	var repair: Dictionary = values.get("repair", {})
	for key: String in repair:
		repair_delivered[StringName(key)] = int(repair[key])
	var used: Dictionary = values.get("demand_used", {})
	for key: String in used:
		_demand_used[StringName(key)] = int(used[key])
	var workers: Dictionary = values.get("workers", {})
	for key: String in workers:
		_workers[StringName(key)] = int(workers[key])
