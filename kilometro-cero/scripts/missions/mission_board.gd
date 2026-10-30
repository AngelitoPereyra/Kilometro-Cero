class_name MissionBoard
extends RefCounted
## Las misiones de la partida (D80, tarea 58). Lógica pura, como el ProductionModel al que
## mira; GameState tiene la instancia del juego (GameState.missions) y le da las consultas a la
## red y a la escena.
## - Principales: salen solas. Por cada objeto que una estación consume y que ningún flujo tiene
##   comprometido (ProductionModel.get_uncommitted_needs) hay una principal activa. Para cumplirla
##   hay que entregar una primera carga en la estación (Mission.FIRST_DELIVERY_DAYS días de
##   consumo) y que haya un productor con producción libre suficiente y conectado (habilitando
##   los tramos cortados del camino). Al cumplirla crea el flujo y el consumo queda cubierto.
##   Si ningún productor tiene libre lo suficiente, queda esperando: ahí entran las secundarias.
## - Secundarias: se registran desde sus datos (MissionGiver), quedan disponibles al llegar la
##   estación a su nivel y con las previas cumplidas, se toman hablando con un poblador y al
##   cumplirse suman producción extra permanente o familias con oficio (tarea 62b.2) y pesos,
##   que cobra GameState.
## Las entregas se aprueban en el tablero de la estación (StationBoard): nada se entrega solo.
## - Pasajeros (tarea 60b): una principal de pasajeros (ItemData.PASSENGER_TAG) se entrega
##   abriendo las puertas del coche en la estación (PassengerTraffic), no en el tablero. La de
##   un especialista pide una primera carga de uno solo. Sus flujos van y vuelven (round_trip).
## - Principales con aviso (tarea 62b.3, D128): en una estación con quien da sus principales
##   (`register_main_giver`, lo hace MissionGiver.main_station) el jugador no lleva la primera
##   carga. Etapas (`get_stage`): abrir el camino, avisarle (`report`) y, si el camino tiene un
##   tramo que abrió el jugador (`opened_check`) y que todavía no estrenó ningún tren
##   (`is_christened`), el viaje inaugural, que es opcional (ajuste de Batmi): el tablero del
##   productor lo ofrece (`get_offers_at`) y si el jugador lo toma (`take_inaugural`) el Ferrocarril
##   arma el tren prestado ya cargado (`inaugural_started`; lo pone BorrowedTrains) y el jugador lo
##   maneja y entrega como siempre (tablero o puertas); si no lo toma, al terminar el día lo trae
##   el Ferrocarril y se cumple sola. Sin tramo por estrenar, al avisar se cumple sola. Cada
##   principal cumplida estrena los tramos de su camino.
## - Obras (tarea 62b.4, D127, D130): una secundaria de tipo obra (MissionData.Kind.BUILD) no recibe
##   nada en el tablero: sus materiales se llevan a su ConstructionSite (`plan_build`,
##   `deliver_build`), que solo toma lo que trae el jugador (nunca lo de un automático ni del tren
##   prestado). Con todo entregado se cumple como cualquier secundaria.
## - Encargos y mudanzas (tarea 62b.6, D130): un encargo paga además lo entregado a un múltiplo del
##   precio de mercado (`get_order_payment`, con `price_check`); una mudanza deja al cumplirse una
##   familia del jugador con nombre (ProductionModel.add_player_family) y solo se desbloquea si la
##   estación todavía tiene lugar para ella (tope de D129). La gente de una mudanza espera en
##   `MissionData.passenger_from` y sube gratis al abrir las puertas ahí.

## Una misión nueva: una principal que nace (ya activa) o una secundaria que se puede conseguir.
signal mission_available(mission: Mission)
## Se tomó una secundaria.
signal mission_started(mission: Mission)
## Se entregó algo para una misión.
signal mission_progressed(mission: Mission)
signal mission_completed(mission: Mission)
## Una principal que ya no hace falta (otro flujo cubrió ese consumo).
signal mission_removed(mission: Mission)
## Se avisó una principal con viaje inaugural: el tablero del productor ofrece el tren prestado.
signal inaugural_offered(mission: Mission)
## El jugador tomó el tren prestado: su primera carga va en él (tarea 62b.3).
signal inaugural_started(mission: Mission)

## Etapa de una principal con aviso (tarea 62b.3): abrir el camino, avisarle a quien la da, tren
## prestado ofrecido en el tablero, viaje inaugural en curso, cumplida (o por cumplirse sola).
enum Stage { OPEN_ROUTE, REPORT, OFFER, INAUGURAL, DONE }

var production: ProductionModel
## Tramos del camino más corto entre dos estaciones, también por los cortados:
## func(from, to) -> Variant (Array[StringName], o null si no hay camino). Vacío: sin red, todo
## queda a un paso.
var route_finder: Callable = Callable()
## Largo de un camino: func(route: Array[StringName]) -> float. Vacío: cantidad de tramos.
var route_length: Callable = Callable()
## Si un tramo está abierto: func(segment_id) -> bool. Vacío: todos abiertos.
var segment_check: Callable = Callable()
## Cuántos nodos quedan en un grupo: func(group) -> int. Vacío: ninguno.
var zone_count: Callable = Callable()
## El flujo de una principal cumplida empieza el día siguiente (tarea 62.4, D120, idea de Batmi):
## la primera entrega es la del jugador y el tren sale recién al otro día. Apagado (como antes de
## la 62.4) empieza enseguida; lo prende la escena del Hito A.
var flows_start_next_day: bool = false
## Si el jugador abrió un tramo (estuvo cortado y ahora no, tarea 62b.3): func(segment_id) -> bool.
## Vacío: ninguno (nunca hay viaje inaugural).
var opened_check: Callable = Callable()
## Precio de mercado de un objeto en una estación, para los encargos (tarea 62b.6):
## func(station_id, item_id) -> int. Vacío o 0: el valor base del objeto (ItemData.base_value).
var price_check: Callable = Callable()

# id -> misión, en orden de creación.
var _missions: Dictionary[StringName, Mission] = {}
# Secundarias guardadas que todavía no se registraron (id -> diccionario).
var _saved: Dictionary = {}
# "estación:objeto" -> cuántas principales nacieron (para sus ids).
var _main_counts: Dictionary = {}
var _refreshing: bool = false
var _dirty: bool = false
# Estación -> nombre de quien da sus principales (tarea 62b.3).
var _main_givers: Dictionary[StringName, String] = {}
# Tramos que ya estrenó un tren del Ferrocarril (tarea 62b.3).
var _christened: Dictionary[StringName, bool] = {}
# Secundaria -> nombre de quien la da (para los avisos del HUD y el tablero).
var _side_givers: Dictionary[StringName, String] = {}


func _init(model: ProductionModel = null) -> void:
	production = model if model != null else ProductionModel.new()
	production.level_changed.connect(func(_station_id: StringName, _level: int) -> void: refresh())
	production.flow_added.connect(func(_flow: ProductionFlow) -> void: refresh())
	production.flow_removed.connect(func(_flow: ProductionFlow) -> void: refresh())
	# Una familia nueva cambia lo que pide y lo que da la estación (tarea 62b.2).
	production.family_added.connect(func(_station_id: StringName, _occupation: OccupationData, _origin: int) -> void: refresh())
	production.day_processed.connect(_on_day_processed)


## Suma una secundaria desde sus datos. Si ya estaba (otra escena, un guardado), la conserva.
func register_side(mission_data: MissionData) -> Mission:
	if mission_data == null or mission_data.id == &"":
		push_warning("MissionBoard: misión sin datos o sin id.")
		return null
	var known: Mission = _missions.get(mission_data.id)
	if known != null:
		known.data = mission_data
		return known
	var mission: Mission = Mission.create_side(mission_data)
	# La familia de una mudanza tiene que estar registrada para ver si hay lugar (tarea 62b.6).
	if mission_data.reward_family != null and production.get_occupation(mission_data.reward_family.id) == null:
		production.add_occupation(mission_data.reward_family)
	if _saved.has(mission_data.id):
		mission.apply_dict(_saved[mission_data.id])
		_saved.erase(mission_data.id)
	_missions[mission.id] = mission
	refresh()
	return mission


func get_mission(mission_id: StringName) -> Mission:
	return _missions.get(mission_id)


func is_completed(mission_id: StringName) -> bool:
	var mission: Mission = get_mission(mission_id)
	return mission != null and mission.is_completed()


## Todas, en orden de creación.
func get_missions() -> Array[Mission]:
	var result: Array[Mission] = []
	result.assign(_missions.values())
	return result


## Las principales de una estación que no se cumplieron (activas).
func get_main_missions(station_id: StringName) -> Array[Mission]:
	var result: Array[Mission] = []
	for mission: Mission in _missions.values():
		if mission.main and mission.station_id == station_id and mission.is_active():
			result.append(mission)
	return result


## Las secundarias de una estación que ya se pueden ver (disponibles, en curso o cumplidas).
func get_side_missions(station_id: StringName) -> Array[Mission]:
	var result: Array[Mission] = []
	for mission: Mission in _missions.values():
		if not mission.main and mission.station_id == station_id and mission.state != Mission.State.LOCKED:
			result.append(mission)
	return result


## Las activas de una estación: primero las principales.
func get_active_missions(station_id: StringName) -> Array[Mission]:
	var result: Array[Mission] = get_main_missions(station_id)
	for mission: Mission in get_side_missions(station_id):
		if mission.is_active():
			result.append(mission)
	return result


## Toma una secundaria disponible. False si no existe o no estaba disponible.
func start(mission_id: StringName) -> bool:
	var mission: Mission = get_mission(mission_id)
	if mission == null or mission.state != Mission.State.AVAILABLE:
		return false
	mission.state = Mission.State.ACTIVE
	mission_started.emit(mission)
	refresh()
	return true


## Olvida todo.
func clear() -> void:
	_missions.clear()
	_saved.clear()
	_main_counts.clear()
	_main_givers.clear()
	_christened.clear()
	_side_givers.clear()


# --- Principales con aviso (tarea 62b.3, D128) ---


## Anota quién da las principales de una estación (lo hace MissionGiver.main_station al empezar).
## Desde ahí, sus principales piden aviso.
func register_main_giver(station_id: StringName, speaker: String) -> void:
	if station_id == &"":
		return
	_main_givers[station_id] = speaker
	refresh()


## Anota quién da una secundaria (lo hace MissionGiver al empezar).
func set_side_giver(mission_id: StringName, speaker: String) -> void:
	_side_givers[mission_id] = speaker


## El nombre de quien da una secundaria ("Doña Rosa"), o vacío.
func get_side_giver(mission_id: StringName) -> String:
	return _side_givers.get(mission_id, "")


func has_main_giver(station_id: StringName) -> bool:
	return _main_givers.has(station_id)


## El nombre de quien da las principales de la estación ("Doña Clara"), o vacío.
func get_main_giver(station_id: StringName) -> String:
	return _main_givers.get(station_id, "")


## Si la principal pide aviso (su estación tiene quien la da).
func needs_report(mission: Mission) -> bool:
	return mission != null and mission.main and _main_givers.has(mission.station_id)


## Si la misión recibe entregas del jugador en el tablero: todas, salvo las principales con aviso
## que no están en el viaje inaugural (su carga la trae el Ferrocarril) y las obras (se entregan en
## su ConstructionSite, tarea 62b.4).
func accepts_deliveries(mission: Mission) -> bool:
	return mission != null and not is_build(mission) and (not needs_report(mission) or mission.inaugural)


## La etapa de una principal con aviso. Las demás: DONE si está cumplida y OPEN_ROUTE si no.
func get_stage(mission: Mission) -> Stage:
	if mission == null or mission.is_completed():
		return Stage.DONE
	if mission.inaugural:
		return Stage.INAUGURAL
	if mission.offered:
		return Stage.OFFER
	if mission.reported:
		return Stage.DONE
	if not needs_report(mission):
		return Stage.OPEN_ROUTE
	var source: StringName = find_source(mission)
	if source == &"" or not production.are_connected(source, mission.station_id):
		return Stage.OPEN_ROUTE
	return Stage.REPORT


## Si ya se le puede avisar (camino abierto y productor con lo necesario).
func can_report(mission: Mission) -> bool:
	return mission != null and mission.is_active() and needs_report(mission) and get_stage(mission) == Stage.REPORT


## Avisa que el camino está habilitado. Con un tramo abierto por el jugador sin estrenar, el tablero
## del productor ofrece el tren prestado (`inaugural_offered`); si no, el Ferrocarril manda la carga
## y la principal se cumple. False si todavía no se podía avisar.
func report(mission_id: StringName) -> bool:
	var mission: Mission = get_mission(mission_id)
	if not can_report(mission):
		return false
	var source: StringName = find_source(mission)
	mission.source_id = source
	mission.reported = true
	mission.offered = not get_unchristened_segments(source, mission.station_id).is_empty()
	if mission.offered:
		inaugural_offered.emit(mission)
	else:
		_send_load(mission)
	refresh()
	return true


## Las principales cuyo tren prestado ofrece el tablero de esta estación (la productora).
func get_offers_at(station_id: StringName) -> Array[Mission]:
	var result: Array[Mission] = []
	for mission: Mission in _missions.values():
		if mission.main and mission.is_active() and mission.offered and find_source(mission) == station_id:
			result.append(mission)
	return result


## El jugador toma el tren prestado ofrecido: empieza el viaje inaugural (`inaugural_started`).
func take_inaugural(mission_id: StringName) -> bool:
	var mission: Mission = get_mission(mission_id)
	if mission == null or not mission.is_active() or not mission.offered:
		return false
	mission.offered = false
	mission.inaugural = true
	inaugural_started.emit(mission)
	refresh()
	return true


# El Ferrocarril trae la primera carga solo: la principal se cumple.
func _send_load(mission: Mission) -> void:
	mission.offered = false
	for item_id: StringName in mission.required:
		mission.delivered[item_id] = mission.required[item_id]


# Al terminar el día, los trenes prestados que nadie tomó los trae el Ferrocarril.
func _on_day_processed() -> void:
	for mission: Mission in get_missions():
		if mission.main and mission.is_active() and mission.offered:
			_send_load(mission)
	refresh()


## Los tramos del camino entre dos estaciones que abrió el jugador y que todavía no estrenó ningún
## tren (los del viaje inaugural).
func get_unchristened_segments(from: StringName, to: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var route: Variant = _find_route(from, to)
	if route == null or not opened_check.is_valid():
		return result
	for segment_id: StringName in route:
		if bool(opened_check.call(segment_id)) and not is_christened(segment_id):
			result.append(segment_id)
	return result


## Si un tren del Ferrocarril ya pasó por el tramo (una principal cumplida lo tenía en su camino).
func is_christened(segment_id: StringName) -> bool:
	return _christened.has(segment_id)


## Marca como estrenados los tramos del camino entre dos estaciones.
func christen_route(from: StringName, to: StringName) -> void:
	var route: Variant = _find_route(from, to)
	if route == null:
		return
	for segment_id: StringName in route:
		_christened[segment_id] = true


# --- Entregas ---


## Cuánto aceptarían las misiones activas de la estación de lo que hay disponible
## (id de objeto -> unidades). El tablero lo muestra antes de aprobar.
func plan_delivery(station_id: StringName, available: Dictionary[StringName, int]) -> Dictionary[StringName, int]:
	var plan: Dictionary[StringName, int] = {}
	var wanted: Dictionary[StringName, int] = {}
	for mission: Mission in get_active_missions(station_id):
		if not accepts_deliveries(mission):
			continue
		var remaining: Dictionary[StringName, int] = mission.get_remaining()
		for item_id: StringName in remaining:
			wanted[item_id] = wanted.get(item_id, 0) + remaining[item_id]
	for item_id: StringName in available:
		var amount: int = mini(available[item_id], wanted.get(item_id, 0))
		if amount > 0:
			plan[item_id] = amount
	return plan


## Entrega en la estación: se reparte entre sus misiones activas (primero las principales, de la
## más vieja a la más nueva) y cumple las que se completan. Devuelve cuánto aceptó.
func deliver(station_id: StringName, item_id: StringName, amount: int) -> int:
	var accepted: int = 0
	for mission: Mission in get_active_missions(station_id):
		if accepted >= amount:
			break
		if not accepts_deliveries(mission):
			continue
		var taken: int = mission.add_delivery(item_id, amount - accepted)
		if taken > 0:
			accepted += taken
			mission_progressed.emit(mission)
	if accepted > 0:
		refresh()
	return accepted


# --- Obras (tarea 62b.4) ---


## Si la misión es una obra (sus materiales van a su ConstructionSite, no al tablero).
func is_build(mission: Mission) -> bool:
	return mission != null and not mission.main and mission.kind == MissionData.Kind.BUILD


## Cuánto aceptaría la obra en curso de lo que hay disponible (id de objeto -> unidades).
func plan_build(mission_id: StringName, available: Dictionary[StringName, int]) -> Dictionary[StringName, int]:
	var plan: Dictionary[StringName, int] = {}
	var mission: Mission = get_mission(mission_id)
	if not is_build(mission) or not mission.is_active():
		return plan
	var remaining: Dictionary[StringName, int] = mission.get_remaining()
	for item_id: StringName in remaining:
		var amount: int = mini(remaining[item_id], available.get(item_id, 0))
		if amount > 0:
			plan[item_id] = amount
	return plan


## Entrega materiales a una obra en curso; con todo entregado se cumple. Devuelve cuánto aceptó.
func deliver_build(mission_id: StringName, item_id: StringName, amount: int) -> int:
	var mission: Mission = get_mission(mission_id)
	if not is_build(mission) or not mission.is_active() or amount <= 0:
		return 0
	var accepted: int = mission.add_delivery(item_id, amount)
	if accepted > 0:
		mission_progressed.emit(mission)
		refresh()
	return accepted


## Qué parte de los materiales ya llegó: de 0 a 1 (1 si está cumplida).
func get_build_progress(mission: Mission) -> float:
	if mission == null:
		return 0.0
	if mission.is_completed():
		return 1.0
	var total: int = 0
	var done: int = 0
	for item_id: StringName in mission.required:
		total += mission.required[item_id]
		done += mini(mission.delivered.get(item_id, 0), mission.required[item_id])
	return float(done) / float(total) if total > 0 else 0.0


# --- Encargos y mudanzas (tarea 62b.6) ---


## Si la secundaria es un encargo (paga a múltiplo del mercado).
func is_order(mission: Mission) -> bool:
	return mission != null and mission.data != null and mission.data.is_order()


## Si la secundaria es una mudanza (deja una familia del jugador).
func is_move(mission: Mission) -> bool:
	return mission != null and mission.data != null and mission.data.is_move()


## Lo que paga un encargo por lo que pide: múltiplo × precio de mercado en su estación × unidades.
## 0 si no es un encargo.
func get_order_payment(mission: Mission) -> int:
	if not is_order(mission):
		return 0
	var total: float = 0.0
	for item_id: StringName in mission.required:
		total += float(get_market_price(mission.station_id, item_id) * mission.required[item_id])
	return roundi(total * mission.data.pays_market_multiplier)


## El precio de mercado de un objeto en una estación (price_check); sin consulta o sin precio, su
## valor base.
func get_market_price(station_id: StringName, item_id: StringName) -> int:
	var price: int = int(price_check.call(station_id, item_id)) if price_check.is_valid() else 0
	if price <= 0:
		var item: ItemData = find_item(item_id)
		price = roundi(item.base_value) if item != null else 0
	return price


## Los pesos que cobra el jugador al cumplir una secundaria: los fijos más lo del encargo (cumplida,
## lo que se cobró: el precio del mercado puede cambiar después).
func get_reward_money(mission: Mission) -> int:
	if mission == null or mission.data == null:
		return 0
	if mission.is_completed():
		return mission.paid
	return mission.data.reward_money + get_order_payment(mission)


## Si una mudanza tiene lugar en su estación (tope del jugador, D129). True si no es una mudanza.
func has_room_for_family(mission: Mission) -> bool:
	if not is_move(mission):
		return true
	return production.can_add_player_family(mission.data.get_reward_station(), mission.data.reward_family.id)


## Si la gente de la misión sube gratis aunque la estación no la tenga en su stock (la familia de
## una mudanza espera en `passenger_from`).
func boards_without_stock(mission: Mission) -> bool:
	return mission != null and not mission.main and mission.data != null and mission.data.passenger_from != &""


# --- Textos ---


## El nombre de un objeto según los datos de las estaciones y de las misiones (el id si no lo
## encuentra).
func name_of(item_id: StringName) -> String:
	var item: ItemData = find_item(item_id)
	return item.display_name if item != null else String(item_id)


## El ItemData de un objeto según los datos de las estaciones y de las misiones, o null.
func find_item(item_id: StringName) -> ItemData:
	for station_id: StringName in production.get_station_ids():
		var item: ItemData = production.get_data(station_id).find_item(item_id)
		if item != null:
			return item
	# Los oficios registrados (también los que habilita solo un rasgo, tarea 62b.2).
	for occupation: OccupationData in production.get_occupations():
		var known: ItemData = occupation.find_item(item_id)
		if known != null:
			return known
	for mission: Mission in _missions.values():
		if mission.data != null:
			for entry: ItemAmount in mission.data.delivery + mission.data.reward_production:
				if entry != null and entry.item != null and entry.item.id == item_id:
					return entry.item
			var families: Array[OccupationData] = mission.data.reward_families.duplicate()
			if mission.data.reward_family != null:
				families.append(mission.data.reward_family)
			for occupation: OccupationData in families:
				var found: ItemData = occupation.find_item(item_id) if occupation != null else null
				if found != null:
					return found
	return null


## Si el objeto es un pasajero (tarea 60b).
func is_passenger(item_id: StringName) -> bool:
	return ItemData.is_passenger(find_item(item_id))


## La primera carga de una principal de `amount` por día: Mission.FIRST_DELIVERY_DAYS días de
## consumo, o uno solo si es un especialista (D103, tarea 60b).
func first_delivery(item_id: StringName, amount: int) -> int:
	if ItemData.is_specialist(find_item(item_id)):
		return amount
	return amount * Mission.FIRST_DELIVERY_DAYS


## Las misiones activas de pasajeros que salen de una estación: las principales cuyo productor
## elegido es esa estación y, desde la tarea 62, las secundarias de entrega que piden gente
## que sale de ahí (`passenger_source`).
func get_passenger_missions_from(station_id: StringName) -> Array[Mission]:
	var result: Array[Mission] = []
	for mission: Mission in _missions.values():
		for item_id: StringName in get_passenger_needs(mission):
			if passenger_source(mission, item_id) == station_id:
				result.append(mission)
				break
	return result


## Los pasajeros que todavía espera una misión activa (id -> unidades): la principal de
## pasajeros o una secundaria de entrega que pide gente (tarea 62). Vacío si no espera a nadie.
func get_passenger_needs(mission: Mission) -> Dictionary[StringName, int]:
	var needs: Dictionary[StringName, int] = {}
	if mission == null or not mission.is_active() or mission.kind != MissionData.Kind.DELIVERY or not accepts_deliveries(mission):
		return needs
	var remaining: Dictionary[StringName, int] = mission.get_remaining()
	for item_id: StringName in remaining:
		if remaining[item_id] > 0 and is_passenger(item_id):
			needs[item_id] = remaining[item_id]
	return needs


## De qué estación sale la gente de una misión: en una principal, su productor elegido
## (find_source); en una secundaria (tarea 62), la estación más cerca que produce ese pasajero,
## primero las conectadas. Vacío si no hay ninguna.
func passenger_source(mission: Mission, item_id: StringName) -> StringName:
	if mission == null:
		return &""
	if mission.main:
		return find_source(mission) if mission.item_id == item_id else &""
	# Mudanza (tarea 62b.6): la familia espera donde dicen sus datos.
	if mission.data != null and mission.data.passenger_from != &"":
		return mission.data.passenger_from
	var best: StringName = &""
	var best_connected: bool = false
	var best_length: float = INF
	for station_id: StringName in production.get_station_ids():
		if station_id == mission.station_id or production.get_production(station_id).get(item_id, 0) <= 0:
			continue
		var route: Variant = _find_route(station_id, mission.station_id)
		if route == null:
			continue
		var connected: bool = production.are_connected(station_id, mission.station_id)
		var length: float = _length_of(route)
		if best == &"" or (connected and not best_connected) or (connected == best_connected and length < best_length):
			best = station_id
			best_connected = connected
			best_length = length
	return best


## Si alguna misión activa (de cualquier estación, principal o secundaria) espera este pasajero.
func is_reserved_passenger(item_id: StringName) -> bool:
	for mission: Mission in _missions.values():
		if get_passenger_needs(mission).has(item_id):
			return true
	return false


## Si a la estación ya le llegó `item_id` con una misión cumplida (tarea 62: la maestra de una
## secundaria abre la escuela aunque no tenga flujo).
func has_delivered(station_id: StringName, item_id: StringName) -> bool:
	for mission: Mission in _missions.values():
		if mission.station_id == station_id and mission.is_completed() and mission.delivered.get(item_id, 0) > 0:
			return true
	return false


## El nombre de una estación (el id si no la conoce).
func station_name(station_id: StringName) -> String:
	var data: StationData = production.get_data(station_id)
	return data.display_name if data != null and not data.display_name.is_empty() else String(station_id)


## "Abastecer con 10 tronco por día" o el título de la secundaria.
func get_title(mission: Mission) -> String:
	if mission.data != null:
		return mission.data.title
	if is_passenger(mission.item_id):
		return "Traer %d %s por día" % [mission.flow_amount, name_of(mission.item_id)]
	return "Abastecer con %d %s por día" % [mission.flow_amount, name_of(mission.item_id)]


# --- Principales: de dónde sale el flujo ---


## El productor para una principal: entre los que tienen libre todo el flujo, primero los
## conectados y después el camino más corto (contando los tramos cortados). &"" si no hay.
func find_source(mission: Mission) -> StringName:
	if mission == null or not mission.main:
		return &""
	# Avisada (tarea 62b.3): la que se eligió al avisar, de donde sale el tren prestado.
	if mission.reported and mission.source_id != &"":
		return mission.source_id
	var best: StringName = &""
	var best_connected: bool = false
	var best_length: float = INF
	for station_id: StringName in production.get_station_ids():
		if station_id == mission.station_id:
			continue
		if production.get_free_production(station_id).get(mission.item_id, 0) < mission.flow_amount:
			continue
		var route: Variant = _find_route(station_id, mission.station_id)
		if route == null:
			continue
		var connected: bool = production.are_connected(station_id, mission.station_id)
		var length: float = _length_of(route)
		if best == &"" or (connected and not best_connected) or (connected == best_connected and length < best_length):
			best = station_id
			best_connected = connected
			best_length = length
	return best


## Los tramos cortados del camino entre el productor y la estación (vacío si están conectados).
func get_cut_segments(mission: Mission) -> Array[StringName]:
	var cut: Array[StringName] = []
	var source: StringName = find_source(mission)
	if source == &"":
		return cut
	var route: Variant = _find_route(source, mission.station_id)
	if route == null:
		return cut
	for segment_id: StringName in route:
		if not _is_open(segment_id):
			cut.append(segment_id)
	return cut


## Qué le falta a una misión, para el tablero: "Entregar 20 log", "Habilitar el tramo m_p"...
## Vacío si ya está lista (o cumplida).
func get_pending_steps(mission: Mission) -> PackedStringArray:
	var steps: PackedStringArray = []
	if mission == null or mission.is_completed():
		return steps
	if needs_report(mission):
		return _report_steps(mission)
	if mission.main:
		var source: StringName = find_source(mission)
		if source == &"":
			steps.append("Producción insuficiente: nadie tiene %d %s por día libres" % [mission.flow_amount, name_of(mission.item_id)])
		else:
			var cut: Array[StringName] = get_cut_segments(mission)
			for segment_id: StringName in cut:
				steps.append("Habilitar el tramo %s (hacia %s)" % [segment_id, station_name(source)])
			if cut.is_empty() and not production.are_connected(source, mission.station_id):
				steps.append("Conectar con %s" % station_name(source))
	match mission.kind:
		MissionData.Kind.OPEN_SEGMENT:
			if not _is_open(mission.data.segment_id):
				steps.append("Habilitar el tramo %s" % mission.data.segment_id)
		MissionData.Kind.CLEAR_ZONE:
			var left: int = _zone_left(mission.data.zone_group)
			if left > 0:
				steps.append("Despejar la zona (quedan %d)" % left)
	var remaining: Dictionary[StringName, int] = mission.get_remaining()
	for item_id: StringName in remaining:
		if is_passenger(item_id) and (mission.main or mission.kind == MissionData.Kind.DELIVERY):
			# Las secundarias con gente también (la maestra, la familia de una mudanza; tarea 62b.6).
			var source_id: StringName = passenger_source(mission, item_id)
			if source_id != &"":
				steps.append("Traer %d %s desde %s (abrí las puertas del coche en las dos estaciones)" % [remaining[item_id], name_of(item_id), station_name(source_id)])
			elif not mission.main:
				steps.append("Traer %d %s en el coche" % [remaining[item_id], name_of(item_id)])
		elif is_build(mission):
			steps.append("Llevar %d %s a la obra (F en su cartel)" % [remaining[item_id], name_of(item_id)])
		else:
			steps.append("Entregar %d %s" % [remaining[item_id], name_of(item_id)])
	if is_order(mission) and not remaining.is_empty():
		steps.append("Paga $%d al entregar todo" % get_reward_money(mission))
	return steps


# Los pasos de una principal con aviso (tarea 62b.3).
func _report_steps(mission: Mission) -> PackedStringArray:
	var steps: PackedStringArray = []
	var source: StringName = find_source(mission)
	var giver: String = get_main_giver(mission.station_id)
	match get_stage(mission):
		Stage.OPEN_ROUTE:
			if source == &"":
				steps.append("Producción insuficiente: nadie tiene %d %s por día libres" % [mission.flow_amount, name_of(mission.item_id)])
				return steps
			var cut: Array[StringName] = get_cut_segments(mission)
			for segment_id: StringName in cut:
				steps.append("Habilitar el tramo %s (hacia %s)" % [segment_id, station_name(source)])
			if cut.is_empty():
				steps.append("Conectar con %s" % station_name(source))
			steps.append("Después, avisarle a %s en %s" % [giver, station_name(mission.station_id)])
		Stage.REPORT:
			steps.append("Avisarle a %s en %s que el camino a %s está habilitado" % [giver, station_name(mission.station_id), station_name(source)])
		Stage.OFFER:
			steps.append("Si querés llevar vos el tren prestado: F en el tablero de %s (si no, mañana lo trae el Ferrocarril)" % station_name(source))
		Stage.INAUGURAL:
			steps.append("Llevar el tren prestado de %s a %s (el maquinista está enfermo)" % [station_name(source), station_name(mission.station_id)])
			var remaining: Dictionary[StringName, int] = mission.get_remaining()
			for item_id: StringName in remaining:
				if is_passenger(item_id):
					steps.append("Abrir las puertas del coche en %s (%d %s)" % [station_name(mission.station_id), remaining[item_id], name_of(item_id)])
				else:
					steps.append("Entregar %d %s en el tablero de %s" % [remaining[item_id], name_of(item_id), station_name(mission.station_id)])
	return steps


# --- Actualización ---


## Crea y saca principales, desbloquea secundarias y cumple lo que esté listo. Se llama sola
## con los cambios del modelo de producción; GameState la llama también cuando cambia la red o
## se despeja algo.
func refresh() -> void:
	if _refreshing:
		_dirty = true
		return
	_refreshing = true
	_dirty = true
	var rounds: int = 0
	while _dirty and rounds < 10:
		_dirty = false
		rounds += 1
		_update_main_missions()
		_unlock_side_missions()
		_complete_ready_missions()
	_refreshing = false


func _update_main_missions() -> void:
	# Lo que piden las estaciones sin flujo: estación -> objeto -> unidades por día.
	var needs: Dictionary = {}
	for station_id: StringName in production.get_station_ids():
		needs[station_id] = production.get_uncommitted_needs(station_id)
	for mission: Mission in get_missions():
		# Una estación que todavía no se registró (partida recién cargada) conserva su principal.
		if not mission.main or not mission.is_active() or not production.has_station(mission.station_id):
			continue
		var amount: int = needs.get(mission.station_id, {}).get(mission.item_id, 0)
		if amount <= 0:
			_missions.erase(mission.id)
			mission_removed.emit(mission)
			continue
		var first: int = first_delivery(mission.item_id, amount)
		if mission.reported:
			# Avisada (tarea 62b.3): la carga ya salió (o está en el tren prestado); solo el flujo cambia.
			mission.flow_amount = amount
		elif amount != mission.flow_amount or mission.required.get(mission.item_id, 0) != first:
			mission.flow_amount = amount
			mission.required = {mission.item_id: first}
			mission.delivered[mission.item_id] = mini(mission.delivered.get(mission.item_id, 0), first)
		needs[mission.station_id].erase(mission.item_id)
	for station_id: StringName in needs:
		for item_id: StringName in needs[station_id]:
			var key: String = "%s:%s" % [station_id, item_id]
			_main_counts[key] = int(_main_counts.get(key, 0)) + 1
			var mission: Mission = Mission.create_main(station_id, item_id, needs[station_id][item_id])
			mission.required = {item_id: first_delivery(item_id, mission.flow_amount)}
			mission.id = StringName("%s:%d" % [mission.id, _main_counts[key]])
			_missions[mission.id] = mission
			mission_available.emit(mission)


func _unlock_side_missions() -> void:
	for mission: Mission in get_missions():
		if mission.main or mission.state != Mission.State.LOCKED or mission.data == null:
			continue
		if production.get_level(mission.station_id) < mission.data.min_level:
			continue
		var ready: bool = true
		for required_id: StringName in mission.data.requires:
			if not is_completed(required_id):
				ready = false
				break
		# Una mudanza espera a que la estación tenga lugar para otra familia del jugador (D129).
		if ready and has_room_for_family(mission):
			mission.state = Mission.State.AVAILABLE
			mission_available.emit(mission)


func _complete_ready_missions() -> void:
	for mission: Mission in get_missions():
		if mission.is_active() and _is_ready(mission):
			_complete(mission)


func _is_ready(mission: Mission) -> bool:
	if not mission.is_delivery_done():
		return false
	if mission.main:
		var source: StringName = find_source(mission)
		return source != &"" and production.are_connected(source, mission.station_id)
	match mission.kind:
		MissionData.Kind.OPEN_SEGMENT:
			return _is_open(mission.data.segment_id)
		MissionData.Kind.CLEAR_ZONE:
			return _zone_left(mission.data.zone_group) == 0
	return true


func _complete(mission: Mission) -> void:
	# Lo que paga se fija antes de los premios: la familia nueva puede cambiar los precios.
	var paid: int = get_reward_money(mission)
	mission.state = Mission.State.COMPLETED
	mission.paid = paid
	if mission.main:
		var source: StringName = find_source(mission)
		mission.flow = production.add_flow(source, mission.station_id, mission.item_id, mission.flow_amount, is_passenger(mission.item_id), flows_start_next_day)
		mission.inaugural = false
		# Su camino ya lo estrenó un tren (tarea 62b.3): el prestado o el del flujo.
		christen_route(source, mission.station_id)
	elif mission.data != null:
		for entry: ItemAmount in mission.data.reward_production:
			if entry != null and entry.item != null:
				production.add_production_bonus(mission.data.get_reward_station(), entry.item.id, entry.amount)
		# Las familias de premio (tarea 62b.2): su oficio puede no estar registrado todavía.
		for occupation: OccupationData in mission.data.reward_families:
			if occupation != null and production.add_occupation(occupation):
				production.add_family(mission.data.get_reward_station(), occupation.id, ProductionModel.FamilyOrigin.EXTRA)
		# La familia de una mudanza se queda como vecina del jugador (tarea 62b.6). Si el lugar se
		# ocupó mientras tanto, llega igual (no se pierde lo hecho) pero sin pasar el tope.
		var family: OccupationData = mission.data.reward_family
		if family != null and production.add_occupation(family):
			var reward_station: StringName = mission.data.get_reward_station()
			if not production.add_player_family(reward_station, family.id, mission.data.reward_family_name):
				push_warning("MissionBoard: '%s' no tenía lugar para otra familia del jugador; %s llega como familia extra." % [reward_station, mission.data.reward_family_name])
				production.add_family(reward_station, family.id, ProductionModel.FamilyOrigin.EXTRA, mission.data.reward_family_name)
	mission_completed.emit(mission)
	_dirty = true


func _find_route(from: StringName, to: StringName) -> Variant:
	if not route_finder.is_valid():
		return [] as Array[StringName]
	return route_finder.call(from, to)


func _length_of(route: Variant) -> float:
	if route_length.is_valid():
		return float(route_length.call(route))
	return float((route as Array).size())


func _is_open(segment_id: StringName) -> bool:
	return not segment_check.is_valid() or bool(segment_check.call(segment_id))


func _zone_left(group: StringName) -> int:
	return int(zone_count.call(group)) if zone_count.is_valid() else 0


# --- Guardado (tarea 65) ---


func to_dict() -> Dictionary:
	var missions: Array = []
	for mission: Mission in _missions.values():
		missions.append(mission.to_dict())
	# Las secundarias guardadas que esta escena no registró se conservan.
	for mission_id: StringName in _saved:
		missions.append(_saved[mission_id])
	var christened: Array = []
	for segment_id: StringName in _christened:
		christened.append(String(segment_id))
	return {"missions": missions, "main_counts": _main_counts.duplicate(), "christened": christened}


## Carga el estado. Las principales vuelven solas; las secundarias se unen a sus datos al
## registrarse (antes o después de cargar).
func load_dict(values: Dictionary) -> void:
	var registered: Array[MissionData] = []
	for mission: Mission in _missions.values():
		if not mission.main and mission.data != null:
			registered.append(mission.data)
	_missions.clear()
	_saved.clear()
	_main_counts = (values.get("main_counts", {}) as Dictionary).duplicate()
	_christened.clear()
	for segment_id: Variant in values.get("christened", []):
		_christened[StringName(str(segment_id))] = true
	for entry: Dictionary in values.get("missions", []):
		if bool(entry.get("main", false)):
			var mission: Mission = Mission.main_from_dict(entry)
			mission.id = StringName(entry.get("id", ""))
			_missions[mission.id] = mission
		else:
			_saved[StringName(entry.get("id", ""))] = entry
	for mission_data: MissionData in registered:
		register_side(mission_data)
	refresh()
