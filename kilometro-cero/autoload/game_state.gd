extends Node
## Estado de la partida. Es dueño del reloj del juego (D34), del modelo de producción
## (D79, tarea 57: lo avanza un día en cada día nuevo y reemite sus cambios de nivel), de las
## misiones (D80, tarea 58), de los mercados (Economy, tarea 59), de los pasajeros
## (PassengerTraffic, tarea 60b) y del dinero (solo pesos, D96).
## Los demás datos entran cuando un sistema los necesite.

## Minutos reales que dura un día de juego (D34). Vivía en NeedsConfig, que se borró (D75).
const DAY_LENGTH_MINUTES: float = 24.0

var clock: GameClock = GameClock.new()
## Permite pausar el tiempo (por ejemplo, en menús) sin tocar nada más.
var clock_running: bool = true
## Multiplicador de la velocidad del tiempo: 1.0 = normal. Sirve para depurar y, más
## adelante, para comprimir el tiempo en viajes largos.
var time_scale: float = 1.0
## Niveles de las estaciones y flujos permanentes. Cada Station se registra al empezar.
var production: ProductionModel
## Misiones principales y secundarias (tarea 58). Se rehace con reset_production.
var missions: MissionBoard
## Stock y precios de los mercados (tarea 59). Se rehace con reset_production.
var economy: Economy
## Pasajeros: demanda, intercambios y el coche que regala la ciudad (tarea 60b).
var passengers: PassengerTraffic
## Pesos del jugador (D96, sin trueque). Lo cobran las misiones y lo mueve el mercado.
var money: int = 0

var _hours_per_second: float = 0.0


func _ready() -> void:
	_hours_per_second = GameClock.hours_per_real_second(DAY_LENGTH_MINUTES)
	# El reloj no conoce al EventBus (es lógica pura): GameState hace de puente.
	clock.day_started.connect(_on_day_started)
	clock.time_advanced.connect(_on_time_advanced)
	reset_production()
	EventBus.station_level_changed.connect(_on_station_level_changed)
	# La red y los obstáculos cambian lo que piden las misiones (tramos y zonas).
	EventBus.segment_state_changed.connect(func(_segment_id: StringName, _state: int) -> void: _refresh_missions.call_deferred())
	EventBus.obstacle_cleared.connect(func(_segment_id: StringName) -> void: _refresh_missions.call_deferred())
	# Un golpe puede terminar de despejar algo de una zona (misiones de despejar zona).
	EventBus.tool_used.connect(func(_tool_id: StringName) -> void: _refresh_missions.call_deferred())


func _process(delta: float) -> void:
	if clock_running:
		clock.advance(delta * _hours_per_second * time_scale)


## Empieza un modelo de producción, un tablero de misiones, mercados y pasajeros vacíos
## (partida nueva, pruebas).
## Las estaciones y los pobladores de la escena tienen que volver a registrarse (Station y
## MissionGiver lo hacen en su _ready).
func reset_production() -> void:
	if production != null and production.level_changed.is_connected(_on_production_level_changed):
		production.level_changed.disconnect(_on_production_level_changed)
	production = ProductionModel.new()
	production.connection_check = _are_connected
	# Todos los oficios, también los que habilita solo un rasgo (hacheros con monte, tarea 62b.2).
	for occupation: OccupationData in OccupationData.load_all():
		production.add_occupation(occupation)
	production.level_changed.connect(_on_production_level_changed)
	economy = Economy.new(production)
	missions = MissionBoard.new(production)
	missions.route_finder = _find_route
	missions.route_length = _route_length
	missions.segment_check = _is_segment_open
	missions.zone_count = _count_zone
	missions.opened_check = _was_opened
	# Los encargos pagan a múltiplo del precio del mercado de su estación (tarea 62b.6).
	missions.price_check = economy.get_buy_price
	missions.mission_available.connect(func(mission: Mission) -> void: EventBus.mission_available.emit(mission.id))
	missions.mission_started.connect(func(mission: Mission) -> void: EventBus.mission_started.emit(mission.id))
	missions.mission_progressed.connect(func(mission: Mission) -> void: EventBus.mission_progressed.emit(mission.id))
	missions.mission_completed.connect(_on_mission_completed)
	passengers = PassengerTraffic.new(missions, economy)
	passengers.coach_state_changed.connect(func(state: PassengerTraffic.CoachState) -> void: EventBus.coach_gift_changed.emit(state))


## Suma (o resta, con negativo) pesos y lo avisa por EventBus.money_changed.
func add_money(amount: int) -> void:
	if amount == 0:
		return
	money += amount
	EventBus.money_changed.emit(money)


func _on_day_started(day: int) -> void:
	# Primero el modelo, así quien escucha day_started ya ve los niveles del día nuevo. El
	# mercado junta después lo que la producción no mandó por flujos.
	production.advance_day()
	economy.advance_day()
	passengers.advance_day()
	EventBus.day_started.emit(day)


# Sin red en la escena, todo cuenta como conectado (pruebas sin vías).
func _are_connected(from: StringName, to: StringName) -> bool:
	var network: RailNetwork = RailNetwork.find_in(get_tree())
	return network == null or network.are_connected(from, to)


# Para las misiones: el camino también por los cortados; null si no hay. Sin red, todo a un paso.
func _find_route(from: StringName, to: StringName) -> Variant:
	var network: RailNetwork = RailNetwork.find_in(get_tree())
	if network == null:
		return [] as Array[StringName]
	if not network.has_station(from) or not network.has_station(to):
		return null
	var route: Array[StringName] = network.find_route(from, to, true)
	if route.is_empty():
		return null
	return route


func _route_length(route: Array) -> float:
	var network: RailNetwork = RailNetwork.find_in(get_tree())
	if network == null:
		return float(route.size())
	var segments: Array[StringName] = []
	segments.assign(route)
	return network.get_route_length(segments)


func _is_segment_open(segment_id: StringName) -> bool:
	var network: RailNetwork = RailNetwork.find_in(get_tree())
	return network != null and network.has_segment(segment_id) and not network.is_cut(segment_id)


# Si el jugador abrió el tramo (tarea 62b.3): estuvo cortado y ahora no.
func _was_opened(segment_id: StringName) -> bool:
	var network: RailNetwork = RailNetwork.find_in(get_tree())
	return network != null and network.was_opened(segment_id)


# Lo que queda en un grupo, sin contar lo que se está borrando.
func _count_zone(group: StringName) -> int:
	var left: int = 0
	for node: Node in get_tree().get_nodes_in_group(group):
		if not node.is_queued_for_deletion():
			left += 1
	return left


func _refresh_missions() -> void:
	missions.refresh()


func _on_mission_completed(mission: Mission) -> void:
	if mission.data != null:
		# Con lo que paga un encargo (tarea 62b.6).
		add_money(missions.get_reward_money(mission))
		# La producción extra puede ser de algo nuevo: el mercado tiene que conocerlo.
		for entry: ItemAmount in mission.data.reward_production:
			if entry != null:
				economy.register_item(entry.item)
		# Y las familias de premio pueden producir algo nuevo (tarea 62b.2).
		for occupation: OccupationData in mission.data.reward_families:
			if occupation != null:
				economy.register_occupation(occupation)
		if mission.data.reward_family != null:
			economy.register_occupation(mission.data.reward_family)
	EventBus.mission_completed.emit(mission.id)


func _on_production_level_changed(station_id: StringName, level: int) -> void:
	EventBus.station_level_changed.emit(station_id, level)


# Un nivel cambiado desde la escena (Station.set_level) se copia al modelo sin reavisarlo.
func _on_station_level_changed(station_id: StringName, level: int) -> void:
	production.set_level(station_id, level, false)
	missions.refresh()


func _on_time_advanced(hours: float) -> void:
	EventBus.time_advanced.emit(hours)
