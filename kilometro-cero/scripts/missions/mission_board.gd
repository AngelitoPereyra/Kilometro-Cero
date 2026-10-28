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
##   cumplirse suman producción extra permanente (y pesos, que cobra GameState).
## Las entregas se aprueban en el tablero de la estación (StationBoard): nada se entrega solo.
## - Pasajeros (tarea 60b): una principal de pasajeros (ItemData.PASSENGER_TAG) se entrega
##   abriendo las puertas del coche en la estación (PassengerTraffic), no en el tablero. La de
##   un especialista pide una primera carga de uno solo. Sus flujos van y vuelven (round_trip).

## Una misión nueva: una principal que nace (ya activa) o una secundaria que se puede conseguir.
signal mission_available(mission: Mission)
## Se tomó una secundaria.
signal mission_started(mission: Mission)
## Se entregó algo para una misión.
signal mission_progressed(mission: Mission)
signal mission_completed(mission: Mission)
## Una principal que ya no hace falta (otro flujo cubrió ese consumo).
signal mission_removed(mission: Mission)

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

# id -> misión, en orden de creación.
var _missions: Dictionary[StringName, Mission] = {}
# Secundarias guardadas que todavía no se registraron (id -> diccionario).
var _saved: Dictionary = {}
# "estación:objeto" -> cuántas principales nacieron (para sus ids).
var _main_counts: Dictionary = {}
var _refreshing: bool = false
var _dirty: bool = false


func _init(model: ProductionModel = null) -> void:
	production = model if model != null else ProductionModel.new()
	production.level_changed.connect(func(_station_id: StringName, _level: int) -> void: refresh())
	production.flow_added.connect(func(_flow: ProductionFlow) -> void: refresh())
	production.flow_removed.connect(func(_flow: ProductionFlow) -> void: refresh())
	production.day_processed.connect(refresh)


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


# --- Entregas ---


## Cuánto aceptarían las misiones activas de la estación de lo que hay disponible
## (id de objeto -> unidades). El tablero lo muestra antes de aprobar.
func plan_delivery(station_id: StringName, available: Dictionary[StringName, int]) -> Dictionary[StringName, int]:
	var plan: Dictionary[StringName, int] = {}
	var wanted: Dictionary[StringName, int] = {}
	for mission: Mission in get_active_missions(station_id):
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
		var taken: int = mission.add_delivery(item_id, amount - accepted)
		if taken > 0:
			accepted += taken
			mission_progressed.emit(mission)
	if accepted > 0:
		refresh()
	return accepted


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
	for mission: Mission in _missions.values():
		if mission.data != null:
			for entry: ItemAmount in mission.data.delivery + mission.data.reward_production:
				if entry != null and entry.item != null and entry.item.id == item_id:
					return entry.item
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
	if mission == null or not mission.is_active() or mission.kind != MissionData.Kind.DELIVERY:
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
		if mission.main and is_passenger(item_id):
			var source_id: StringName = find_source(mission)
			if source_id != &"":
				steps.append("Traer %d %s desde %s (abrí las puertas del coche en las dos estaciones)" % [remaining[item_id], name_of(item_id), station_name(source_id)])
		else:
			steps.append("Entregar %d %s" % [remaining[item_id], name_of(item_id)])
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
		if amount != mission.flow_amount or mission.required.get(mission.item_id, 0) != first:
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
		if ready:
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
	mission.state = Mission.State.COMPLETED
	if mission.main:
		mission.flow = production.add_flow(find_source(mission), mission.station_id, mission.item_id, mission.flow_amount, is_passenger(mission.item_id), flows_start_next_day)
	elif mission.data != null:
		for entry: ItemAmount in mission.data.reward_production:
			if entry != null and entry.item != null:
				production.add_production_bonus(mission.data.get_reward_station(), entry.item.id, entry.amount)
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
	return {"missions": missions, "main_counts": _main_counts.duplicate()}


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
