class_name AutoTrains
extends Node
## Trenes automáticos de los flujos permanentes (D81, D106, D110, tarea 61). Va un solo nodo
## "TrenesAutomaticos" en el mundo (como la RailNetwork). Mira los flujos de
## GameState.production y arma un viaje (AutoTrainRun) por cada conexión entre dos estaciones:
## el primer flujo de una conexión crea el tren y los que vienen después en la misma conexión
## (en cualquier sentido) le suman vagones, hasta lo que arrastra la locomotora
## (VehicleData.max_wagons).
## Horarios: cada tren sale de su estación a su hora de ida y vuelve a su hora de vuelta (los
## trenes nuevos se escalonan cada HOUR_STEP horas); si llega tarde, sale apenas puede.
## Reservas (el bastón por dentro, D110, D114): un tren solo sale si reservó todo su viaje: los
## tramos de vía simple (ningún otro automático los tiene), las vías de estación por donde pasa
## (la principal en las del medio) y una vía libre en la de llegada (la de carga, la de cruce o,
## si no hay otra, la principal). Ninguna vía de su camino puede tener otro vehículo (en la
## doble, la de su sentido). Reserva RESERVE_AHEAD_HOURS antes de su hora y va devolviendo cada
## tramo y cada vía apenas los deja atrás; al llegar se queda solo con la vía donde para. Una
## maniobra de vuelta espera si un tren que ya está por salir necesita lo que ella usaría. Si dos lo quieren a la vez, gana el que
## lleva más carga y, si llevan lo mismo, el que lo pidió primero. Si no hay vía libre en la
## llegada, espera en su estación. A la entrada de los tramos de vía simple hay semáforos
## (RailSignal): rojo mientras el tramo está ocupado. Un tramo reservado además cierra su
## entrada para el tren del jugador (RailNetwork.set_entry_closed): es como si estuviera
## cortado hasta que el automático lo deja. En la vía doble no hace falta reservar: cada uno va
## por la suya.
## Vías de estación (tarea 61b): donde la estación tiene vías propias, el viaje pasa por ellas
## (AutoTrainRun.station_piece), el tren para centrado en su vía y mueve los cambios solo
## (Vehicle.switch_chooser). Donde no (escenas de antes), la estación sigue siendo un punto y
## un automático parado ahí tapa el tramo, como antes.
## Vuelta (tarea 61b.3, D115): al llegar a una estación con vías propias la locomotora rodea el
## tren por otra vía y se engancha del otro lado, para volver adelante. Cerca del jugador lo hace
## de verdad: se desengancha, sale por una punta (a la cola de maniobras o al tramo), vuelve por
## otra vía hasta pasar la otra punta y entra a la vía del tren hasta tocarlo. Si al final de la
## cola hay mesa giratoria, la locomotora gira ahí y vuelve de frente; si no, va "de culata"
## (Vehicle.model_yaw). Reserva lo que usa mientras maniobra. Lejos es una espera de TURN_HOURS.
## Cerca del jugador (spawn_distance) el tren aparece de verdad sobre la vía y se maneja solo;
## lejos es solo un número (AutoTrainRun.advance), que tampoco pasa por encima de otros trenes
## ni entra a un tramo cortado. Nunca desaparece de golpe a la vista: si se cruza de frente con
## el tren del jugador, frena, toca la bocina y espera a que el otro le deje la vía.
## La entrega sigue siendo la del ProductionModel una vez por día (D95): el tren es la cara del
## flujo, su carga es de adorno (no se descarga, no cuenta en el tablero ni en el mercado).

signal train_added(run: AutoTrainRun)
signal train_removed(run: AutoTrainRun)
signal train_departed(run: AutoTrainRun)
signal train_arrived(run: AutoTrainRun)
signal train_spawned(run: AutoTrainRun)
signal train_despawned(run: AutoTrainRun)

const GROUP: StringName = &"auto_trains"
const LOCOMOTIVE_SCENE: String = "res://scenes/vehicles/locomotive.tscn"
const FLATCAR_SCENE: String = "res://scenes/vehicles/flatcar.tscn"
const COACH_SCENE: String = "res://scenes/vehicles/passenger_coach.tscn"
const LOCOMOTIVE_DATA: String = "res://data/vehicles/locomotive.tres"
const FLATCAR_DATA: String = "res://data/vehicles/flatcar.tres"
const COACH_DATA: String = "res://data/vehicles/passenger_coach.tres"
const KIND_FLATCAR: StringName = &"flatcar"
const KIND_COACH: StringName = &"coach"
## Acelerador con que andan (fracción de la velocidad máxima), también lejos del jugador.
const AUTO_THROTTLE: float = 0.7
## Primer horario de ida y cuántas horas después sale el tren siguiente (provisorio).
const FIRST_HOUR: float = 7.0
const HOUR_STEP: float = 2.0
const SCHEDULE_SLOTS: int = 4
## Segundos trabado (acelerando sin moverse) antes de tocar la bocina y avisar que espera.
const BLOCKED_TIME: float = 2.0
## Dónde van los semáforos: metros dentro del tramo desde la estación y al costado de la vía.
const SIGNAL_OFFSET: float = 8.0
const SIGNAL_SIDE: float = 3.0
## Horas antes de su salida que un tren reserva su viaje (15 minutos, D114).
const RESERVE_AHEAD_HOURS: float = 0.25
## Lejos del jugador, cuánto tarda en dar la vuelta (horas de juego).
const TURN_HOURS: float = 0.25
## Acelerador de la locomotora mientras maniobra y segundos que tarda la mesa en girar.
const MANEUVER_THROTTLE: float = 0.6
const TURN_SECONDS: float = 4.0
## Metros que la locomotora pasa de una punta (además de su largo) para que el cambio quede libre.
const CLEAR_MARGIN: float = 3.0
## Metros que la cola tiene que dejar atrás un tramo o una vía para devolverlo (pasar el cambio).
const PASSED_CLEARANCE: float = 25.0
## Cada cuánto (s) se revisan los flujos, los semáforos y si un tren aparece o desaparece.
const REFRESH_TIME: float = 0.25
const LABEL_HEIGHT: float = 5.5
const LABEL_RANGE: float = 80.0

## Hasta qué distancia del jugador (de la cámara) el tren está de verdad en la vía.
@export_range(10.0, 1000.0, 1.0, "suffix:m") var spawn_distance: float = 120.0
## Más lejos que esto, vuelve a ser solo un número.
@export_range(10.0, 1500.0, 1.0, "suffix:m") var despawn_distance: float = 160.0
@export var signals_enabled: bool = true

var _runs: Array[AutoTrainRun] = []
# run.id -> Array[Vehicle], de la locomotora hacia atrás.
var _trains: Dictionary = {}
# segment_id o vía de estación ("@pueblo/Cruce1") -> run.id que la tiene reservada.
var _tokens: Dictionary = {}
# run.id -> true: ya reservó el próximo viaje y espera su hora.
var _reserved: Dictionary = {}
# run.id -> hora en que empezó a pedir la reserva (para el desempate).
var _requested: Dictionary = {}
# run.id -> maniobra de vuelta en curso, cerca del jugador (ver _start_maneuver).
var _maneuvers: Dictionary = {}
# "tramo|estación" -> RailSignal
var _signals: Dictionary = {}
# run.id -> segundos trabado
var _blocked: Dictionary = {}
var _signature: String = ""
var _next_id: int = 1
var _refresh_left: float = 0.0
var _loco_data: VehicleData
var _flatcar_data: WagonData
var _coach_data: WagonData


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_loco_data = load(LOCOMOTIVE_DATA) as VehicleData
	_flatcar_data = load(FLATCAR_DATA) as WagonData
	_coach_data = load(COACH_DATA) as WagonData


## El AutoTrains de la escena, o null.
static func find_in(tree: SceneTree) -> AutoTrains:
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP) as AutoTrains


## Hora absoluta del juego (horas desde el principio de la partida).
static func now_hours() -> float:
	return float(GameState.clock.current_day - 1) * GameClock.HOURS_PER_DAY + GameState.clock.time_of_day


## La clave de una conexión: las dos estaciones en orden alfabético.
static func connection_key(a: StringName, b: StringName) -> String:
	return "%s|%s" % ([a, b] if String(a) < String(b) else [b, a])


## Los vagones de un tren (lógica pura): por cada flujo, del más viejo al más nuevo, los que
## hacen falta para su carga por día (`capacities`: tipo -> lugares), sin pasar de
## `max_wagons`. La gente va en coche y lo demás en plataforma. "dir": 1 de `home` hacia la otra
## estación, -1 al revés, 0 si el flujo va y vuelve.
static func plan_wagons(flows: Array[ProductionFlow], home: StringName, is_passenger: Callable, capacities: Dictionary, max_wagons: int) -> Array[Dictionary]:
	var wagons: Array[Dictionary] = []
	for flow: ProductionFlow in flows:
		var kind: StringName = KIND_COACH if is_passenger.call(flow.item_id) else KIND_FLATCAR
		var capacity: int = maxi(int(capacities.get(kind, 1)), 1)
		var dir: int = 0 if flow.round_trip else (1 if flow.from_station == home else -1)
		var left: int = maxi(flow.amount, 1)
		while left > 0:
			if wagons.size() >= max_wagons:
				return wagons
			var units: int = mini(left, capacity)
			wagons.append({"kind": kind, "item": flow.item_id, "dir": dir, "units": units})
			left -= units
	return wagons


## Lo que ocupa el tren detrás del centro de la locomotora (lógica pura, como Vehicle).
static func length_behind(loco_length: float, wagon_lengths: Array[float]) -> float:
	if wagon_lengths.is_empty():
		return loco_length * 0.5
	var behind: float = wagon_lengths.back() * 0.5
	var previous: float = loco_length
	for length: float in wagon_lengths:
		behind += Vehicle.coupling_distance(previous, length)
		previous = length
	return behind


func get_runs() -> Array[AutoTrainRun]:
	return _runs.duplicate()


func get_run(run_id: int) -> AutoTrainRun:
	for run: AutoTrainRun in _runs:
		if run.id == run_id:
			return run
	return null


## Los trenes que pasan por una estación (salen o llegan a ella).
func get_runs_at(station_id: StringName) -> Array[AutoTrainRun]:
	var found: Array[AutoTrainRun] = []
	for run: AutoTrainRun in _runs:
		if run.home == station_id or run.away == station_id:
			found.append(run)
	return found


## Los vehículos del tren si está en la escena (locomotora primero), o vacío.
func get_train(run: AutoTrainRun) -> Array[Vehicle]:
	var train: Array[Vehicle] = []
	if run != null and _trains.has(run.id):
		for vehicle: Variant in _trains[run.id]:
			if is_instance_valid(vehicle):
				train.append(vehicle)
	return train


func is_spawned(run: AutoTrainRun) -> bool:
	return not get_train(run).is_empty()


## Quién tiene reservado el tramo o la vía de estación ("@pueblo/Cruce1"), por id de viaje, o 0.
func get_token_holder(segment_id: StringName) -> int:
	return int(_tokens.get(segment_id, 0))


func get_signal(segment_id: StringName, station_id: StringName) -> RailSignal:
	var found: Variant = _signals.get("%s|%s" % [segment_id, station_id])
	return found if is_instance_valid(found) else null


## Texto de los trenes de una estación para el tablero (vacío si no pasa ninguno).
func describe_at(station_id: StringName) -> PackedStringArray:
	var lines: PackedStringArray = []
	for run: AutoTrainRun in get_runs_at(station_id):
		lines.append(run.status_text(_station_name))
	return lines


## Revisa los flujos ahora (normalmente lo hace solo cada REFRESH_TIME).
func sync_flows() -> void:
	var flows: Array[ProductionFlow] = GameState.production.get_flows() if GameState.production != null else [] as Array[ProductionFlow]
	var parts: PackedStringArray = []
	for flow: ProductionFlow in flows:
		parts.append("%d:%s:%s:%s:%d:%s:%s" % [flow.id, flow.from_station, flow.to_station, flow.item_id, flow.amount, flow.round_trip, flow.custom_name])
	var signature: String = ",".join(parts)
	if signature == _signature:
		return
	_signature = signature
	var groups: Dictionary = {}
	var order: Array[String] = []
	for flow: ProductionFlow in flows:
		var key: String = connection_key(flow.from_station, flow.to_station)
		if not groups.has(key):
			groups[key] = [] as Array[ProductionFlow]
			order.append(key)
		(groups[key] as Array[ProductionFlow]).append(flow)
	for run: AutoTrainRun in _runs.duplicate():
		if not groups.has(connection_key(run.home, run.away)):
			_remove_run(run)
	for key: String in order:
		var group: Array[ProductionFlow] = groups[key]
		var run: AutoTrainRun = _find_run(key)
		if run == null:
			run = _create_run(group[0])
		_update_run(run, group)


## Un paso de los trenes que no están en la escena y de las salidas (lo llama _process; público
## para las pruebas).
func step(delta: float) -> void:
	var now: float = now_hours()
	var speed: float = _abstract_speed()
	var asking: Array[AutoTrainRun] = []
	for run: AutoTrainRun in _runs.duplicate():
		if not run.is_moving():
			if run.leg.is_empty():
				_plan_parked_leg(run)
			if run.needs_turn:
				_step_turn(run, now)
			if now >= run.due - RESERVE_AHEAD_HOURS:
				if not _requested.has(run.id):
					_requested[run.id] = now
				asking.append(run)
		else:
			if not is_spawned(run) and run.advance(speed * delta, now, _abstract_limit(run)):
				_on_arrived(run)
			elif run.is_moving():
				_release_passed(run)
	# Si varios piden a la vez, primero el que lleva más carga (D114).
	asking.sort_custom(_goes_first)
	for run: AutoTrainRun in asking:
		_try_depart(run, now)


## Para el guardado (tarea 65): los viajes por conexión.
func to_dict() -> Dictionary:
	var runs: Array = []
	for run: AutoTrainRun in _runs:
		var values: Dictionary = run.to_dict()
		values["key"] = connection_key(run.home, run.away)
		runs.append(values)
	return {"next_id": _next_id, "runs": runs}


## Al cargar, después de que existan los flujos: cada viaje retoma su estado.
func load_dict(values: Dictionary) -> void:
	sync_flows()
	_next_id = maxi(_next_id, int(values.get("next_id", 1)))
	for entry: Variant in values.get("runs", []):
		var saved: Dictionary = entry
		var run: AutoTrainRun = _find_run(String(saved.get("key", "")))
		if run != null:
			_despawn(run)
			run.load_dict(saved)
	_restore_reservations()


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_TIME
		sync_flows()
		_update_spawns()
		_update_signals()
	step(delta)


func _physics_process(delta: float) -> void:
	for run: AutoTrainRun in _runs.duplicate():
		if is_spawned(run):
			_drive(run, delta)


func _find_run(key: String) -> AutoTrainRun:
	for run: AutoTrainRun in _runs:
		if connection_key(run.home, run.away) == key:
			return run
	return null


func _create_run(first: ProductionFlow) -> AutoTrainRun:
	var run := AutoTrainRun.new()
	run.id = _next_id
	_next_id += 1
	run.home = first.from_station
	run.away = first.to_station
	run.loco_length = _loco_data.length if _loco_data != null else 10.0
	var now: float = now_hours()
	run.set_schedule(FIRST_HOUR + HOUR_STEP * float(_runs.size() % SCHEDULE_SLOTS), now)
	# El primer viaje sale apenas nace el flujo; después sigue su horario.
	run.due = now + AutoTrainRun.MIN_DWELL_HOURS
	_runs.append(run)
	train_added.emit(run)
	return run


func _update_run(run: AutoTrainRun, flows: Array[ProductionFlow]) -> void:
	run.flow_ids.clear()
	for flow: ProductionFlow in flows:
		run.flow_ids.append(flow.id)
	run.display_name = FlowNames.train_name(flows, _find_item, _station_name)
	var capacities: Dictionary = {
		KIND_FLATCAR: _flatcar_data.capacity if _flatcar_data != null else 20,
		KIND_COACH: _coach_data.capacity if _coach_data != null else 10,
	}
	var max_wagons: int = _loco_data.max_wagons if _loco_data != null else 4
	var wagons: Array[Dictionary] = plan_wagons(flows, run.home, _is_passenger, capacities, max_wagons)
	var changed: bool = wagons != run.wagons
	run.wagons = wagons
	var lengths: Array[float] = []
	for wagon: Dictionary in wagons:
		lengths.append(_wagon_data(wagon["kind"]).length if _wagon_data(wagon["kind"]) != null else 10.0)
	run.behind = length_behind(run.loco_length, lengths)
	# Un tren en la escena cambia de vagones parado en una estación; si viaja, al llegar.
	if changed and is_spawned(run) and not run.is_moving():
		_despawn(run)
	elif is_spawned(run):
		_set_label(run)


func _remove_run(run: AutoTrainRun) -> void:
	_despawn(run)
	_release_tokens(run)
	_runs.erase(run)
	_blocked.erase(run.id)
	_reserved.erase(run.id)
	_requested.erase(run.id)
	_maneuvers.erase(run.id)
	_update_signals()
	train_removed.emit(run)


func _wagon_data(kind: StringName) -> WagonData:
	return _coach_data if kind == KIND_COACH else _flatcar_data


func _abstract_speed() -> float:
	return (_loco_data.max_speed if _loco_data != null else 12.0) * AUTO_THROTTLE


func _network() -> RailNetwork:
	return RailNetwork.find_in(get_tree()) if is_inside_tree() else null


func _find_item(item_id: StringName) -> ItemData:
	return GameState.missions.find_item(item_id) if GameState.missions != null else null


func _is_passenger(item_id: StringName) -> bool:
	return ItemData.is_passenger(_find_item(item_id))


func _station_name(station_id: StringName) -> String:
	return GameState.missions.station_name(station_id) if GameState.missions != null else String(station_id)


# --- Salidas y bastón ---

# Primero reserva el viaje (desde RESERVE_AHEAD_HOURS antes); a su hora, sale.
func _try_depart(run: AutoTrainRun, now: float) -> void:
	var network: RailNetwork = _network()
	if network == null:
		return
	if not _reserved.has(run.id):
		var plan: Dictionary = _plan_leg(network, run, false)
		if plan.has("error"):
			run.waiting = plan["error"]
			return
		var pieces: Array[StringName] = plan["pieces"]
		var problem: String = _check_sections(network, run, pieces)
		if problem != "":
			run.waiting = problem
			return
		_reserve(network, run, pieces)
		# Parado, el viaje empieza por la vía donde está: la posición no cambia.
		run.leg = pieces
		run.leg_lengths = plan["lengths"]
		run.position = run.start_position()
		run.waiting = ""
		_update_signals()
	if not run.is_due(now):
		return
	if run.needs_turn:
		if _maneuvers.has(run.id):
			# Ya es la hora, pero está dando la vuelta: sale al terminar.
			return
		if is_spawned(run):
			# No pudo maniobrar (otra vía ocupada): sale empujando, como antes.
			run.needs_turn = false
			run.turn_until = -1.0
		else:
			_finish_turn(run, _turn_is_plain(run))
	# Mientras esperaba su hora se pudo cortar un tramo.
	for piece: StringName in run.leg:
		if not AutoTrainRun.is_station_piece(piece) and network.is_cut(piece):
			_cancel_reservation(run)
			run.waiting = "vía cortada"
			return
	# El tren de verdad tiene que quedar en la vía de salida (en la vía doble, la de su sentido).
	var was_spawned: bool = is_spawned(run)
	if not run.depart(run.leg.duplicate(), run.leg_lengths.duplicate()):
		return
	_reserved.erase(run.id)
	_requested.erase(run.id)
	if was_spawned and not _train_on_leg(run):
		_despawn(run)
		_spawn(run)
	if is_spawned(run):
		_apply_loads(run)
		get_train(run)[0].destination = run.leg_to()
	_update_signals()
	train_departed.emit(run)


# Quién reserva primero: el que lleva más carga; si llevan lo mismo, el que pidió antes (D114).
func _goes_first(a: AutoTrainRun, b: AutoTrainRun) -> bool:
	var cargo_a: int = _cargo(a)
	var cargo_b: int = _cargo(b)
	if cargo_a != cargo_b:
		return cargo_a > cargo_b
	var asked_a: float = float(_requested.get(a.id, 0.0))
	var asked_b: float = float(_requested.get(b.id, 0.0))
	if not is_equal_approx(asked_a, asked_b):
		return asked_a < asked_b
	return a.id < b.id


# Lo que lleva el tren: unidades de carga y pasajeros.
static func _cargo(run: AutoTrainRun) -> int:
	var total: int = 0
	for wagon: Dictionary in run.wagons:
		total += int(wagon["units"])
	return total


# El próximo viaje: los tramos del camino más corto y, en las estaciones con vías propias, la
# vía donde está parado, la principal en las del medio y una libre en la de llegada (con
# `strict` en false, si no hay libre, cualquiera). {"pieces", "lengths"} o {"error": texto}.
func _plan_leg(network: RailNetwork, run: AutoTrainRun, through_cut: bool, strict: bool = true) -> Dictionary:
	var from: StringName = run.leg_from()
	var to: StringName = run.leg_to()
	var route: Array[StringName] = network.find_route(from, to, through_cut)
	if route.is_empty():
		return {"error": "vía cortada"}
	var pieces: Array[StringName] = []
	var lengths: Array[float] = []
	var leaving: Array = _station_options(network, route[0], from, false)
	var parked: StringName = run.leg[0] if not run.leg.is_empty() and AutoTrainRun.is_station_piece(run.leg[0]) and AutoTrainRun.piece_station(run.leg[0]) == from else &""
	var start: Array = []
	if parked != &"":
		for option: Array in leaving:
			if (option[0] as StationTrack).get_track_path().name == AutoTrainRun.piece_track_name(parked):
				start = option
	elif run.leg.is_empty():
		start = _pick_track(run, leaving, false)
	if not start.is_empty():
		# Sale por la punta que toca el tramo: si es el final de su curva, va hacia el final.
		_append_station_piece(pieces, lengths, from, start[0], start[1])
	var entry: StringName = from
	for index: int in route.size():
		var segment_id: StringName = route[index]
		pieces.append(segment_id)
		lengths.append(network.get_segment_length(segment_id))
		var station: StringName = network.other_end(segment_id, entry)
		var arriving: Array = _station_options(network, segment_id, station, true)
		if not arriving.is_empty():
			var chosen: Array = []
			if index == route.size() - 1:
				chosen = _pick_track(run, arriving, strict)
				if chosen.is_empty():
					return {"error": "esperando vía libre en %s" % _station_name(station)}
			else:
				for option: Array in arriving:
					if (option[0] as StationTrack).is_main():
						chosen = option
			if not chosen.is_empty():
				# Entra por la punta que toca el tramo: si es el principio de su curva, va hacia el final.
				_append_station_piece(pieces, lengths, station, chosen[0], not chosen[1])
		entry = station
	return {"pieces": pieces, "lengths": lengths}


func _append_station_piece(pieces: Array[StringName], lengths: Array[float], station: StringName, station_track: StationTrack, forward: bool) -> void:
	pieces.append(AutoTrainRun.station_piece(station, station_track.get_track_path().name, forward))
	lengths.append(station_track.get_length())


# Las vías de `station` que toca la punta del tramo (la vía que llega o, con `arriving` en false,
# la que sale; en la simple, la única): [StationTrack, bool la toca por el final de su curva].
func _station_options(network: RailNetwork, segment_id: StringName, station: StringName, arriving: bool) -> Array:
	var tracks: Array[TrackSegment] = network.get_tracks(segment_id)
	var line: TrackSegment = null
	if tracks.size() == 1:
		line = tracks[0]
	else:
		for track: TrackSegment in tracks:
			if (track.to_station == station if arriving else track.from_station == station):
				line = track
	var found: Array = []
	if line == null or line.get_track_path() == null:
		return found
	for link: Array in network.get_links(line.get_track_path(), line.to_station == station):
		var station_track := RailNetwork.track_of(link[0]) as StationTrack
		if station_track != null and station_track.enabled:
			found.append([station_track, link[1]])
	return found


# La vía donde para: la de carga, si no la de cruce, si no la principal; la primera libre (sin
# reserva de otro ni vehículos). Sin `strict`, si no hay libre, la primera.
func _pick_track(run: AutoTrainRun, options: Array, strict: bool) -> Array:
	var ordered: Array = []
	for role: StationTrack.Role in [StationTrack.Role.FREIGHT, StationTrack.Role.SIDING, StationTrack.Role.MAIN]:
		for option: Array in options:
			if (option[0] as StationTrack).role == role:
				ordered.append(option)
	var own: Array[Vehicle] = get_train(run)
	for option: Array in ordered:
		var station_track: StationTrack = option[0]
		var holder: int = get_token_holder(_section_of(station_track))
		if (holder == 0 or holder == run.id) and not _path_has_foreign(station_track.get_track_path(), own):
			return option
	if strict or ordered.is_empty():
		return []
	return ordered[0]


static func _section_of(station_track: StationTrack) -> StringName:
	return StringName("@%s/%s" % [station_track.get_station_id(), station_track.get_track_path().name])


# Por qué no puede reservar ese viaje, o "" si puede.
func _check_sections(network: RailNetwork, run: AutoTrainRun, pieces: Array[StringName]) -> String:
	var own: Array[Vehicle] = get_train(run)
	var entry: StringName = run.leg_from()
	for piece: StringName in pieces:
		if AutoTrainRun.is_station_piece(piece):
			var holder: int = get_token_holder(AutoTrainRun.piece_section(piece))
			if holder != 0 and holder != run.id:
				return "esperando vía libre en %s" % _station_name(AutoTrainRun.piece_station(piece))
			var path: Path3D = _station_track_path(network, piece)
			if path != null and _path_has_foreign(path, own):
				return "vía ocupada"
			continue
		var double: bool = network.is_double(piece)
		if not double:
			var holder: int = get_token_holder(piece)
			if holder != 0 and holder != run.id:
				return "esperando vía libre"
		# En la vía doble solo importa la de su sentido.
		var track: TrackSegment = network.track_leaving(piece, entry) if double else null
		if _has_foreign_vehicle(network, piece, run, track):
			return "vía ocupada"
		var next_entry: StringName = network.other_end(piece, entry)
		# Otro automático parado en una estación del medio sin vías propias tapa la vía.
		if next_entry != run.leg_to() and _parked_run_at(next_entry, piece, run) != null:
			return "vía ocupada"
		entry = next_entry
	return ""


func _reserve(network: RailNetwork, run: AutoTrainRun, pieces: Array[StringName]) -> void:
	for piece: StringName in pieces:
		if AutoTrainRun.is_station_piece(piece):
			_tokens[AutoTrainRun.piece_section(piece)] = run.id
		else:
			if not network.is_double(piece):
				_tokens[piece] = run.id
			_ensure_signals(network, piece)


# Devuelve la reserva del próximo viaje (se cortó un tramo): se queda con su vía de estación.
func _cancel_reservation(run: AutoTrainRun) -> void:
	_release_tokens(run, _parked_section(run))
	_reserved.erase(run.id)
	_update_signals()


# La vía de estación donde está parado (o donde arranca su viaje), o &"".
func _parked_section(run: AutoTrainRun) -> StringName:
	if run.is_moving() or run.leg.is_empty() or not AutoTrainRun.is_station_piece(run.leg[0]):
		return &""
	return AutoTrainRun.piece_section(run.leg[0])


# Al cargar: cada tren vuelve a reservar lo que tenía (el viaje si viaja, su vía si está parado).
func _restore_reservations() -> void:
	var network: RailNetwork = _network()
	_tokens.clear()
	_reserved.clear()
	_requested.clear()
	if network == null:
		return
	for run: AutoTrainRun in _runs:
		if run.is_moving():
			_reserve(network, run, run.leg)
		elif _parked_section(run) != &"":
			_tokens[_parked_section(run)] = run.id
	_update_signals()


func _on_arrived(run: AutoTrainRun) -> void:
	# Se queda con la vía de estación donde paró.
	_release_tokens(run, _parked_section(run))
	_blocked.erase(run.id)
	_plan_turn_after_arrival(run)
	var train: Array[Vehicle] = get_train(run)
	if not train.is_empty():
		train[0].throttle = 0.0
		train[0].brake = 1.0
		# Cambió de vagones mientras viajaba: los cambia ahora, parado.
		if train.size() - 1 != run.wagons.size():
			_despawn(run)
		else:
			_apply_loads(run)
	_update_signals()
	train_arrived.emit(run)


# Devuelve lo que el tren ya dejó atrás entero (D114: de estación en estación), así otro puede
# salir apenas pasó y no recién cuando llega.
func _release_passed(run: AutoTrainRun) -> void:
	var tail: float = run.position - run.trail_offset()
	var released: bool = false
	for index: int in run.leg.size():
		if run.segment_start(index) + run.leg_lengths[index] >= tail - PASSED_CLEARANCE:
			break
		var section: StringName = AutoTrainRun.piece_section(run.leg[index])
		if get_token_holder(section) == run.id:
			_tokens.erase(section)
			released = true
	if released:
		_update_signals()


func _release_tokens(run: AutoTrainRun, keep: StringName = &"") -> void:
	for section: Variant in _tokens.keys():
		if int(_tokens[section]) == run.id and StringName(section) != keep:
			_tokens.erase(section)


# Hay en el tramo (o solo en su vía `only`) un vehículo que no es de este tren (el del jugador,
# uno suelto u otro automático). Sin `run`, cualquier vehículo.
func _has_foreign_vehicle(network: RailNetwork, segment_id: StringName, run: AutoTrainRun, only: TrackSegment = null) -> bool:
	var own: Array[Vehicle] = []
	if run != null:
		own = get_train(run)
	for track: TrackSegment in network.get_tracks(segment_id):
		if only != null and track != only:
			continue
		if _path_has_foreign(track.get_track_path(), own):
			return true
	return false


# Hay en la curva un vehículo que no es de `own`.
static func _path_has_foreign(path: Path3D, own: Array[Vehicle]) -> bool:
	if path == null:
		return false
	for child: Node in path.get_children():
		var vehicle := child as Vehicle
		if vehicle != null and not own.has(vehicle) and not vehicle.is_queued_for_deletion():
			return true
	return false


# Un automático (que no sea `except`) parado en `station` con el tren dentro de `segment_id`:
# parado, su viaje ya está dado vuelta y empieza por el tramo donde quedó.
func _parked_run_at(station: StringName, segment_id: StringName, except: AutoTrainRun) -> AutoTrainRun:
	for other: AutoTrainRun in _runs:
		if other == except or other.is_moving() or other.leg.is_empty():
			continue
		if other.leg_from() == station and other.leg[0] == segment_id:
			return other
	return null


# Si hay algo en el tramo de vía simple: un automático con el bastón, un vehículo cualquiera o
# un automático parado en una de sus puntas.
func is_segment_busy(segment_id: StringName) -> bool:
	if get_token_holder(segment_id) != 0:
		return true
	var network: RailNetwork = _network()
	if network == null:
		return false
	if _has_foreign_vehicle(network, segment_id, null):
		return true
	for track: TrackSegment in network.get_tracks(segment_id):
		for station_id: StringName in [track.from_station, track.to_station]:
			if _parked_run_at(station_id, segment_id, null) != null:
				return true
	return false


# --- Semáforos ---

func _ensure_signals(network: RailNetwork, segment_id: StringName) -> void:
	if not signals_enabled:
		return
	var double: bool = network.is_double(segment_id)
	for track: TrackSegment in network.get_tracks(segment_id):
		# En la vía doble cada vía tiene un solo sentido: semáforo solo donde se entra a ella.
		var entries: Array[StringName] = [track.from_station]
		if not double:
			entries.append(track.to_station)
		for station_id: StringName in entries:
			var key: String = "%s|%s" % [segment_id, station_id]
			if _signals.has(key) and is_instance_valid(_signals[key]):
				continue
			var path: Path3D = track.get_track_path()
			if path == null or path.curve == null or path.curve.get_baked_length() < SIGNAL_OFFSET * 2.0:
				continue
			var length: float = path.curve.get_baked_length()
			var at: float = SIGNAL_OFFSET if station_id == track.from_station else length - SIGNAL_OFFSET
			var point: Vector3 = path.global_transform * path.curve.sample_baked(at)
			var ahead: Vector3 = path.global_transform * path.curve.sample_baked(minf(at + 1.0, length))
			var behind_point: Vector3 = path.global_transform * path.curve.sample_baked(maxf(at - 1.0, 0.0))
			var tangent: Vector3 = (ahead - behind_point).normalized()
			# Del lado derecho de quien entra al tramo desde esa estación.
			var into: Vector3 = tangent if station_id == track.from_station else -tangent
			var side: Vector3 = into.cross(Vector3.UP).normalized()
			var signal_node := RailSignal.new()
			signal_node.name = "Semaforo_%s_%s" % [segment_id, station_id]
			signal_node.segment_id = segment_id
			signal_node.station_id = station_id
			add_child(signal_node)
			signal_node.global_position = point + side * SIGNAL_SIDE
			_signals[key] = signal_node


func _update_signals() -> void:
	var network: RailNetwork = _network()
	if network == null:
		return
	for key: String in _signals:
		var signal_node: RailSignal = _signals[key] if is_instance_valid(_signals[key]) else null
		if signal_node == null:
			continue
		var state: Array = _signal_state(network, signal_node.segment_id, signal_node.station_id)
		signal_node.set_clear(state[0])
		network.set_entry_closed(signal_node.segment_id, signal_node.station_id, state[1])


# El semáforo de entrada al tramo desde `station` (D114): [verde, cierra la entrada al tren del
# jugador]. Mira por dónde va cada tren (lo que detectaría un sensor a la entrada y a la salida de
# cada tramo):
# - Vía simple reservada por un automático: verde del lado por donde él entra (mientras no
#   entró) y rojo del otro; el tren del jugador no entra por ninguno de los dos.
# - Un automático dentro (de verdad o lejos, como un número) o parado en una punta (estación sin
#   vías propias): rojo y cerrado. En la vía doble, solo la vía de su sentido.
# - Un vehículo cualquiera dentro (el del jugador, uno suelto): rojo, pero solo avisa.
func _signal_state(network: RailNetwork, segment_id: StringName, station: StringName) -> Array:
	var double: bool = network.is_double(segment_id)
	var way: TrackSegment = network.track_leaving(segment_id, station) if double else null
	if _auto_inside(network, segment_id, way):
		return [false, true]
	for track: TrackSegment in network.get_tracks(segment_id):
		for end_station: StringName in [track.from_station, track.to_station]:
			if _parked_run_at(end_station, segment_id, null) != null:
				return [false, true]
	var holder: AutoTrainRun = get_run(get_token_holder(segment_id)) if not double else null
	if holder != null:
		return [_entry_of(network, holder, segment_id) == station and not _has_foreign_vehicle(network, segment_id, holder), true]
	if _has_foreign_vehicle(network, segment_id, null, way):
		return [false, false]
	return [true, false]


# Por qué estación entra el viaje del tren al tramo, o &"".
func _entry_of(network: RailNetwork, run: AutoTrainRun, segment_id: StringName) -> StringName:
	for index: int in run.leg.size():
		if run.leg[index] == segment_id:
			return run.segment_entry(index, network.other_end)
	return &""


# Si algún automático en viaje ocupa el tramo (o, con `way`, esa vía de la vía doble): de verdad,
# con un vehículo en la curva, o lejos, por su posición en el viaje.
func _auto_inside(network: RailNetwork, segment_id: StringName, way: TrackSegment) -> bool:
	for run: AutoTrainRun in _runs:
		if not run.is_moving():
			continue
		var low: float = run.position - run.trail_offset()
		var high: float = run.position + run.lead_offset()
		for index: int in run.leg.size():
			if run.leg[index] != segment_id:
				continue
			if way != null and network.track_leaving(segment_id, run.segment_entry(index, network.other_end)) != way:
				continue
			var start: float = run.segment_start(index)
			if high > start and low < start + run.leg_lengths[index]:
				return true
	return false


# --- Lejos del jugador: solo un número ---

# Hasta dónde puede llegar el centro de la locomotora sin pisar a otro tren ni entrar a un
# tramo cortado.
func _abstract_limit(run: AutoTrainRun) -> float:
	var network: RailNetwork = _network()
	if network == null:
		return INF
	var limit: float = INF
	var lead: float = run.lead_offset()
	var front_tip: float = run.position + lead
	for index: int in run.leg.size():
		var start: float = run.segment_start(index)
		if start >= front_tip - 0.01 and not AutoTrainRun.is_station_piece(run.leg[index]) and network.is_cut(run.leg[index]):
			limit = minf(limit, start - AutoTrainRun.STOP_MARGIN - lead)
			break
	var own: Array[Vehicle] = get_train(run)
	for node: Node in get_tree().get_nodes_in_group(Vehicle.GROUP):
		var vehicle := node as Vehicle
		if vehicle == null or vehicle.data == null or own.has(vehicle) or vehicle.is_queued_for_deletion():
			continue
		var at: float = _leg_coordinate(run, vehicle)
		if is_nan(at):
			continue
		var near_tip: float = at - vehicle.data.length * 0.5
		if near_tip >= front_tip - 0.01:
			limit = minf(limit, near_tip - Vehicle.COUPLING_GAP - lead)
	return limit


# Coordenada sobre el viaje del centro de un vehículo que está en una vía del viaje (la de su
# sentido), o NAN.
func _leg_coordinate(run: AutoTrainRun, vehicle: Vehicle) -> float:
	var network: RailNetwork = _network()
	var path := vehicle.get_parent() as Path3D
	var track: TrackSegment = RailNetwork.track_of(path)
	if network == null or track == null or run.leg.is_empty():
		return NAN
	var best: float = NAN
	for index: int in run.leg.size():
		var piece: StringName = run.leg[index]
		if AutoTrainRun.is_station_piece(piece) != (track is StationTrack):
			continue
		if not AutoTrainRun.is_station_piece(piece) and piece != track.segment_id:
			continue
		var spot: Array = _piece_at(network, run, index)
		if spot.is_empty() or spot[0] != path:
			continue
		var track_length: float = track.get_length()
		var along: float = vehicle.progress if spot[1] else track_length - vehicle.progress
		var scale: float = run.leg_lengths[index] / track_length if track_length > 0.0 else 1.0
		var at: float = run.segment_start(index) + along * scale
		# Si el viaje pasa dos veces por el mismo tramo, la más cercana al tren.
		if is_nan(best) or absf(at - run.position) < absf(best - run.position):
			best = at
	return best


# La curva del pedazo `index` del viaje y si se la recorre hacia su final: [Path3D, bool], o
# vacío. En la vía doble, la vía de su sentido.
func _piece_at(network: RailNetwork, run: AutoTrainRun, index: int) -> Array:
	var piece: StringName = run.leg[index]
	if AutoTrainRun.is_station_piece(piece):
		var station_path: Path3D = _station_track_path(network, piece)
		return [] if station_path == null else [station_path, AutoTrainRun.piece_forward(piece)]
	var entry: StringName = run.segment_entry(index, network.other_end)
	var track: TrackSegment = network.track_leaving(piece, entry)
	if track == null or track.get_track_path() == null:
		return []
	return [track.get_track_path(), track.from_station == entry]


# La curva de una vía de estación del viaje ("@pueblo/Cruce1/f"), o null.
func _station_track_path(network: RailNetwork, piece: StringName) -> Path3D:
	var track_name: String = AutoTrainRun.piece_track_name(piece)
	for station_track: StationTrack in network.get_station_tracks(AutoTrainRun.piece_station(piece)):
		var path: Path3D = station_track.get_track_path()
		if path != null and path.name == track_name:
			return path
	return null


# Por dónde sigue el tren en un cambio (Vehicle.switch_chooser): la salida que es parte de su
# viaje, o -1 (la que marca la palanca).
func _choose_switch(track_switch: TrackSwitch, run: AutoTrainRun) -> int:
	var network: RailNetwork = _network()
	if network == null:
		return -1
	for index: int in run.leg.size():
		var spot: Array = _piece_at(network, run, index)
		if spot.is_empty():
			continue
		for option: int in track_switch.option_count():
			if track_switch.get_option_path(option) == spot[0]:
				return option
	return -1


# --- Aparecer y desaparecer ---

func _observer_position() -> Variant:
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport != null else null
	if camera != null:
		return camera.global_position
	for player: Player in _find_players():
		return player.global_position
	return null


func _update_spawns() -> void:
	var observer: Variant = _observer_position()
	for run: AutoTrainRun in _runs:
		var train: Array[Vehicle] = get_train(run)
		if not train.is_empty():
			var far: bool = observer == null or (observer as Vector3).distance_to(train[0].global_position) > despawn_distance
			if far and not _player_aboard(train):
				_despawn(run)
		elif observer != null:
			var spot: Variant = _world_position(run)
			if spot != null and (observer as Vector3).distance_to(spot) <= spawn_distance:
				_spawn(run)


func _player_aboard(train: Array[Vehicle]) -> bool:
	for player: Player in _find_players():
		if train.has(player.get_platform()):
			return true
	return false


func _find_players() -> Array[Player]:
	var players: Array[Player] = []
	var scene: Node = get_tree().current_scene
	if scene == null:
		return players
	for node: Node in scene.find_children("*", "CharacterBody3D", true, false):
		if node is Player:
			players.append(node)
	return players


# Dónde va (o dónde quedaría) la locomotora: [curva, avance, mira hacia el final] o vacío si
# no hay viaje.
func _placement(run: AutoTrainRun) -> Array:
	var network: RailNetwork = _network()
	if network == null:
		return []
	if run.leg.is_empty() and not _plan_parked_leg(run):
		return []
	var spot: Array = run.locate(run.position)
	var index: int = spot[0]
	if index < 0:
		return []
	var piece_spot: Array = _piece_at(network, run, index)
	if piece_spot.is_empty():
		return []
	var path: Path3D = piece_spot[0]
	var track_length: float = path.curve.get_baked_length()
	var scale: float = track_length / run.leg_lengths[index] if run.leg_lengths[index] > 0.0 else 1.0
	var along: float = float(spot[1]) * scale
	var forward: bool = piece_spot[1]
	var progress: float = along if forward else track_length - along
	# Si la locomotora va adelante mira hacia donde va; si empuja, hacia atrás.
	var faces_end: bool = forward == run.loco_leads
	return [path, progress, faces_end, index]


# Un tren parado que todavía no tiene viaje (recién creado): le arma el próximo, para saber
# dónde está parado. Devuelve false si no hay camino.
func _plan_parked_leg(run: AutoTrainRun) -> bool:
	var network: RailNetwork = _network()
	if network == null or run.is_moving():
		return false
	var plan: Dictionary = _plan_leg(network, run, true, false)
	if plan.has("error"):
		return false
	var pieces: Array[StringName] = plan["pieces"]
	run.leg = pieces
	run.leg_lengths = plan["lengths"]
	run.position = run.start_position()
	# En una estación con vías propias se queda con la vía donde está parado.
	var parked: StringName = _parked_section(run)
	if parked != &"" and get_token_holder(parked) == 0:
		_tokens[parked] = run.id
	for piece: StringName in pieces:
		if not AutoTrainRun.is_station_piece(piece):
			_ensure_signals(network, piece)
	return true


func _world_position(run: AutoTrainRun) -> Variant:
	var placement: Array = _placement(run)
	if placement.is_empty():
		return null
	var path: Path3D = placement[0]
	return path.global_transform * path.curve.sample_baked(placement[1])


# Si el tren entero entra en el tramo donde está la locomotora y ese lugar está libre.
func _can_spawn_at(run: AutoTrainRun, placement: Array) -> bool:
	var index: int = placement[3]
	var start: float = run.segment_start(index)
	var end: float = start + run.leg_lengths[index]
	var low: float = run.position - run.trail_offset()
	var high: float = run.position + run.lead_offset()
	if low < start - 0.01 or high > end + 0.01:
		return false
	var path: Path3D = placement[0]
	for child: Node in path.get_children():
		var vehicle := child as Vehicle
		if vehicle == null or vehicle.data == null or vehicle.is_queued_for_deletion():
			continue
		var at: float = _leg_coordinate(run, vehicle)
		if is_nan(at):
			return false
		var half: float = vehicle.data.length * 0.5 + Vehicle.COUPLING_GAP
		if at + half > low and at - half < high:
			return false
	return true


func _spawn(run: AutoTrainRun) -> void:
	if is_spawned(run):
		return
	var placement: Array = _placement(run)
	if placement.is_empty() or not _can_spawn_at(run, placement):
		return
	var path: Path3D = placement[0]
	var progress: float = placement[1]
	var faces_end: bool = placement[2]
	var loco := (load(LOCOMOTIVE_SCENE) as PackedScene).instantiate() as Vehicle
	loco.name = "TrenAutomatico%d" % run.id
	loco.automatic = true
	loco.switch_chooser = _choose_switch.bind(run)
	loco.reversed = not faces_end
	path.add_child(loco)
	loco.place_on(path, progress, not faces_end)
	var train: Array = [loco]
	var dir: float = 1.0 if faces_end else -1.0
	var distance: float = 0.0
	var previous: float = loco.data.length
	for index: int in run.wagons.size():
		var wagon_entry: Dictionary = run.wagons[index]
		var scene_path: String = COACH_SCENE if wagon_entry["kind"] == KIND_COACH else FLATCAR_SCENE
		var wagon := (load(scene_path) as PackedScene).instantiate() as Wagon
		wagon.name = "%s_Vagon%d" % [loco.name, index + 1]
		wagon.automatic = true
		wagon.reversed = loco.reversed
		distance += Vehicle.coupling_distance(previous, wagon.data.length)
		previous = wagon.data.length
		path.add_child(wagon)
		wagon.progress = progress - dir * distance
		for node: Node in wagon.find_children("*", "", true, false):
			if node is StorageArea:
				node.queue_free()
		if not loco.get_tail().couple(wagon):
			push_warning("AutoTrains: no se pudo enganchar el vagón %d del %s." % [index + 1, run.display_name])
			wagon.queue_free()
			continue
		train.append(wagon)
	loco.destination = run.leg_to()
	loco.throttle = 0.0
	loco.brake = 0.0 if run.is_moving() else 1.0
	loco.model_yaw = PI if run.loco_flipped else 0.0
	_trains[run.id] = train
	# Si estaba dando la vuelta lejos, ahora la hace de verdad.
	run.turn_until = -1.0
	_set_label(run)
	_apply_loads(run)
	train_spawned.emit(run)


func _despawn(run: AutoTrainRun) -> void:
	if not _trains.has(run.id):
		return
	if _maneuvers.has(run.id):
		# A medio maniobrar y lejos: la termina de golpe (nadie lo ve).
		var plain: bool = _maneuvers[run.id]["table"] == null
		_end_maneuver(run)
		_finish_turn(run, plain)
	var train: Array[Vehicle] = get_train(run)
	_trains.erase(run.id)
	for vehicle: Vehicle in train:
		vehicle.queue_free()
	train_despawned.emit(run)


# Si el tren de verdad está sobre la primera vía del viaje (en la vía doble, la de su sentido).
func _train_on_leg(run: AutoTrainRun) -> bool:
	var train: Array[Vehicle] = get_train(run)
	return not train.is_empty() and not is_nan(_leg_coordinate(run, train[0]))


func _set_label(run: AutoTrainRun) -> void:
	var train: Array[Vehicle] = get_train(run)
	if train.is_empty():
		return
	var label := train[0].get_node_or_null(^"Nombre") as Label3D
	if label == null:
		label = Label3D.new()
		label.name = "Nombre"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 0.02
		label.font_size = 40
		label.outline_size = 10
		label.position = Vector3(0.0, LABEL_HEIGHT, 0.0)
		label.visibility_range_end = LABEL_RANGE
		train[0].add_child(label)
	label.text = run.display_name


# La carga de adorno: lo que va en el sentido del viaje actual (o del próximo, si está parado).
func _apply_loads(run: AutoTrainRun) -> void:
	var train: Array[Vehicle] = get_train(run)
	var dir: int = run.cargo_dir()
	for index: int in run.wagons.size():
		if index + 1 >= train.size():
			break
		var wagon := train[index + 1] as Wagon
		var entry: Dictionary = run.wagons[index]
		if wagon != null:
			var entry_dir: int = int(entry["dir"])
			wagon.set_display_load(int(entry["units"]) if entry_dir == 0 or entry_dir == dir else 0)


# --- Cerca del jugador: el tren de verdad se maneja solo ---

func _drive(run: AutoTrainRun, delta: float) -> void:
	var train: Array[Vehicle] = get_train(run)
	var loco: Vehicle = train[0]
	if _maneuvers.has(run.id):
		_drive_maneuver(run, loco, delta)
		return
	if not run.is_moving():
		loco.throttle = 0.0
		loco.brake = 1.0
		return
	var at: float = _leg_coordinate(run, loco)
	if not is_nan(at):
		run.set_position(at)
	loco.destination = run.leg_to()
	var left: float = run.remaining()
	var moving: float = absf(loco.speed)
	if left <= 0.5 and moving < 0.2:
		run.arrive(now_hours())
		_on_arrived(run)
		return
	var stopping: float = moving * moving / (2.0 * loco.data.braking) + 0.3
	if left <= stopping:
		loco.throttle = 0.0
		loco.brake = 1.0
	else:
		loco.brake = 0.0
		loco.throttle = AUTO_THROTTLE * (1.0 if run.loco_leads else -1.0)
	# Trabado: acelera y no se mueve (otro tren adelante, un tramo cortado).
	if loco.throttle != 0.0 and moving < 0.05:
		var time: float = float(_blocked.get(run.id, 0.0)) + delta
		if time >= BLOCKED_TIME and float(_blocked.get(run.id, 0.0)) < BLOCKED_TIME:
			run.waiting = "esperando vía libre"
			var cab: Cab = _find_cab(loco)
			if cab != null:
				cab.sound_horn()
		_blocked[run.id] = time
	else:
		_blocked[run.id] = 0.0
		if run.waiting == "esperando vía libre":
			run.waiting = ""


static func _find_cab(loco: Vehicle) -> Cab:
	for node: Node in loco.find_children("*", "", true, false):
		if node is Cab:
			return node
	return null


# --- La vuelta (tarea 61b.3, D115) ---

# Al llegar: si la estación tiene vías propias y por dónde rodear el tren, tiene que dar la vuelta.
# Una locomotora sola solo cambia de sentido (va de culata).
func _plan_turn_after_arrival(run: AutoTrainRun) -> void:
	run.needs_turn = false
	run.turn_until = -1.0
	var network: RailNetwork = _network()
	if network == null or run.loco_leads or run.leg.is_empty() or not AutoTrainRun.is_station_piece(run.leg[0]):
		return
	if run.wagons.is_empty():
		run.loco_leads = true
		run.loco_flipped = not run.loco_flipped
		run.position = run.start_position()
		var train: Array[Vehicle] = get_train(run)
		if not train.is_empty():
			train[0].place_on(train[0].get_parent() as Path3D, train[0].progress, not train[0].reversed)
			train[0].model_yaw = PI if run.loco_flipped else 0.0
		return
	var plan: Dictionary = _turn_plan(network, run)
	run.needs_turn = not plan.is_empty() and not (plan["others"] as Array).is_empty()


# Un paso de la vuelta de un tren parado: cerca, empieza la maniobra apenas tiene lo que necesita;
# lejos, espera TURN_HOURS.
func _step_turn(run: AutoTrainRun, now: float) -> void:
	if _maneuvers.has(run.id):
		return
	if is_spawned(run):
		if not _start_maneuver(run):
			run.waiting = "esperando para dar la vuelta"
		return
	if run.turn_until < 0.0:
		run.turn_until = now + TURN_HOURS
		run.waiting = "dando la vuelta"
	elif now >= run.turn_until:
		_finish_turn(run, _turn_is_plain(run))


# Si la vuelta es sin mesa giratoria (la locomotora queda de culata).
func _turn_is_plain(run: AutoTrainRun) -> bool:
	var network: RailNetwork = _network()
	var plan: Dictionary = _turn_plan(network, run) if network != null else {}
	return plan.is_empty() or plan["table"] == null


# Dio la vuelta: la locomotora va adelante en el próximo viaje.
func _finish_turn(run: AutoTrainRun, plain: bool) -> void:
	run.loco_leads = true
	if plain:
		run.loco_flipped = not run.loco_flipped
	run.needs_turn = false
	run.turn_until = -1.0
	run.position = run.start_position()
	if run.waiting == "dando la vuelta" or run.waiting == "esperando para dar la vuelta":
		run.waiting = ""


# Cómo puede dar la vuelta en la vía donde está parado: la vía ("track"), si la punta lejana (la
# de la locomotora) es el final de su curva ("far_at_end"), lo que sigue después de cada punta
# ("beyond_far", "beyond_near": [Path3D, bool entra por su final]), las otras vías por donde
# rodear ("others", la principal primero) y la mesa giratoria de la punta lejana ("table", si
# no va de culata: una de culata sale de frente rodeando sin mesa). Vacío si no se puede.
func _turn_plan(network: RailNetwork, run: AutoTrainRun) -> Dictionary:
	if run.leg.is_empty() or not AutoTrainRun.is_station_piece(run.leg[0]):
		return {}
	var piece: StringName = run.leg[0]
	var path: Path3D = _station_track_path(network, piece)
	if path == null:
		return {}
	var far_at_end: bool = not AutoTrainRun.piece_forward(piece)
	var beyond_far: Array = network.get_exit(path, far_at_end)
	var beyond_near: Array = network.get_exit(path, not far_at_end)
	if beyond_far.is_empty() or beyond_near.is_empty():
		return {}
	var others: Array[StationTrack] = []
	for station_track: StationTrack in network.get_station_tracks(AutoTrainRun.piece_station(piece)):
		var other: Path3D = station_track.get_track_path()
		if not station_track.enabled or other == path or station_track.role == StationTrack.Role.HEADSHUNT:
			continue
		if not _links_to(network, other, far_at_end, beyond_far[0]) or not _links_to(network, other, not far_at_end, beyond_near[0]):
			continue
		if station_track.is_main():
			others.push_front(station_track)
		else:
			others.append(station_track)
	var vias := path.get_parent() as StationTracks
	var table: Node3D = vias.get_turntable(beyond_far[0]) if vias != null else null
	if run.loco_flipped:
		table = null
	return {"track": path, "far_at_end": far_at_end, "beyond_far": beyond_far, "beyond_near": beyond_near, "others": others, "table": table}


static func _links_to(network: RailNetwork, path: Path3D, at_end: bool, target: Path3D) -> bool:
	for link: Array in network.get_links(path, at_end):
		if link[0] == target:
			return true
	return false


# Lo que se reserva de una curva (un tramo de vía simple o una vía de estación), o &"" (vía doble).
func _section_of_path(network: RailNetwork, path: Path3D) -> StringName:
	var track: TrackSegment = RailNetwork.track_of(path)
	if track is StationTrack:
		return _section_of(track as StationTrack)
	if track == null or network.is_double(track.segment_id):
		return &""
	return track.segment_id


# Empieza la maniobra de verdad si están libres la otra vía y lo que hay después de las puntas.
# Devuelve false si todavía no se puede.
func _start_maneuver(run: AutoTrainRun) -> bool:
	var network: RailNetwork = _network()
	var train: Array[Vehicle] = get_train(run)
	if network == null or train.size() < 2:
		return false
	var plan: Dictionary = _turn_plan(network, run)
	if plan.is_empty():
		run.needs_turn = false
		return false
	var loco: Vehicle = train[0]
	var beyond_far: Path3D = plan["beyond_far"][0]
	var beyond_near: Path3D = plan["beyond_near"][0]
	var other: StationTrack = null
	for candidate: StationTrack in plan["others"]:
		if _path_is_free(network, run, candidate.get_track_path(), train):
			other = candidate
			break
	if other == null or not _path_is_free(network, run, beyond_far, train) or not _path_is_free(network, run, beyond_near, train):
		return false
	var taken: Array[StringName] = []
	for path: Path3D in [other.get_track_path(), beyond_far, beyond_near]:
		var section: StringName = _section_of_path(network, path)
		if section != &"" and get_token_holder(section) == 0:
			_tokens[section] = run.id
			taken.append(section)
	var reach: float = loco.data.length + CLEAR_MARGIN
	var steps: Array[Dictionary] = []
	var table: Node3D = plan["table"]
	if table != null:
		var vias := (plan["track"] as Path3D).get_parent() as StationTracks
		steps.append({"kind": "move", "sign": 1.0, "path": beyond_far, "at": vias.turntable_spot(beyond_far), "choose": [beyond_far]})
		steps.append({"kind": "turn"})
		steps.append({"kind": "move", "sign": 1.0, "path": beyond_near, "at": _beyond_spot(plan["beyond_near"], reach, loco), "choose": [other.get_track_path(), beyond_near]})
		steps.append({"kind": "couple", "sign": -1.0, "choose": [plan["track"]]})
	else:
		steps.append({"kind": "move", "sign": 1.0, "path": beyond_far, "at": _beyond_spot(plan["beyond_far"], reach, loco), "choose": [beyond_far]})
		steps.append({"kind": "move", "sign": -1.0, "path": beyond_near, "at": _beyond_spot(plan["beyond_near"], reach, loco), "choose": [other.get_track_path(), beyond_near]})
		steps.append({"kind": "couple", "sign": 1.0, "choose": [plan["track"]]})
	loco.uncouple_rear()
	loco.forget_route_ahead()
	_maneuvers[run.id] = {"steps": steps, "index": 0, "time": 0.0, "table": table, "track": plan["track"], "taken": taken, "yaw": loco.model_yaw}
	loco.switch_chooser = _maneuver_chooser.bind(steps[0]["choose"])
	run.waiting = "dando la vuelta"
	_update_signals()
	return true


# Si la curva no tiene vehículos ajenos ni la reservó otro, y ningún tren que ya tendría que
# estar reservando su viaje la necesita: maniobrar espera, salir a horario no.
func _path_is_free(network: RailNetwork, run: AutoTrainRun, path: Path3D, own: Array[Vehicle]) -> bool:
	var section: StringName = _section_of_path(network, path)
	var holder: int = get_token_holder(section) if section != &"" else 0
	if (holder != 0 and holder != run.id) or _path_has_foreign(path, own):
		return false
	if section == &"":
		return true
	var now: float = now_hours()
	for other: AutoTrainRun in _runs:
		if other == run or other.is_moving() or _reserved.has(other.id) or now < other.due - RESERVE_AHEAD_HOURS:
			continue
		for piece: StringName in other.leg:
			if AutoTrainRun.piece_section(piece) == section:
				return false
	return true


# Dónde para la locomotora pasada una punta: [curva, entra por su final], `reach` metros adentro.
static func _beyond_spot(beyond: Array, reach: float, loco: Vehicle) -> float:
	var path: Path3D = beyond[0]
	var length: float = path.curve.get_baked_length()
	var half: float = loco.data.length * 0.5 + 1.0
	var at: float = length - reach if beyond[1] else reach
	return clampf(at, minf(half, length * 0.5), maxf(length - half, length * 0.5))


# En un cambio, la salida que está en `prefer` (o la que marca la palanca).
static func _maneuver_chooser(track_switch: TrackSwitch, prefer: Array) -> int:
	for option: int in track_switch.option_count():
		if prefer.has(track_switch.get_option_path(option)):
			return option
	return -1


# Maneja la locomotora suelta paso a paso por la maniobra.
func _drive_maneuver(run: AutoTrainRun, loco: Vehicle, delta: float) -> void:
	var maneuver: Dictionary = _maneuvers[run.id]
	var steps: Array[Dictionary] = maneuver["steps"]
	var current: Dictionary = steps[int(maneuver["index"])]
	var moving: float = absf(loco.speed)
	var done: bool = false
	match String(current["kind"]):
		"move":
			var on_path: bool = loco.get_parent() == current["path"]
			var left: float = INF
			if on_path:
				left = (float(current["at"]) - loco.progress) * float(current["sign"]) * float(loco.get_curve_direction())
			if on_path and left <= 0.5 and moving < 0.05:
				done = true
			elif on_path and left <= moving * moving / (2.0 * loco.data.braking) + 0.3:
				loco.throttle = 0.0
				loco.brake = 1.0
			else:
				loco.brake = 0.0
				loco.throttle = MANEUVER_THROTTLE * float(current["sign"])
		"turn":
			loco.throttle = 0.0
			loco.brake = 1.0
			maneuver["time"] = float(maneuver["time"]) + delta
			var turned: float = minf(float(maneuver["time"]) / TURN_SECONDS, 1.0)
			loco.model_yaw = float(maneuver["yaw"]) + PI * turned
			var table: Node3D = maneuver["table"]
			if is_instance_valid(table):
				table.rotation.y = PI * turned
			if turned >= 1.0:
				# Ya mira para el otro lado: el modelo vuelve a su lugar y el vehículo cambia de sentido.
				loco.place_on(loco.get_parent() as Path3D, loco.progress, not loco.reversed)
				loco.model_yaw = float(maneuver["yaw"])
				done = true
		"couple":
			loco.brake = 0.0
			loco.throttle = MANEUVER_THROTTLE * float(current["sign"])
			if loco.get_parent() == maneuver["track"]:
				maneuver["time"] = float(maneuver["time"]) + delta
				# Tocó el tren: se enganchó con la cola o la ruta no lo deja seguir.
				if loco.rear != null or (float(maneuver["time"]) > 0.5 and moving < 0.01):
					_complete_maneuver(run)
					return
	if not done:
		return
	maneuver["index"] = int(maneuver["index"]) + 1
	maneuver["time"] = 0.0
	loco.throttle = 0.0
	loco.brake = 1.0
	loco.switch_chooser = _maneuver_chooser.bind(steps[int(maneuver["index"])]["choose"]) if steps[int(maneuver["index"])].has("choose") else _maneuver_chooser.bind([])
	# La ruta guarda por dónde vino: que vuelva a preguntar en los cambios.
	loco.forget_route_ahead()


# La locomotora llegó al otro lado del tren: engancha los vagones (del más cercano al más lejano).
# Sin mesa, la locomotora cambia de sentido sin girar (queda de culata).
func _complete_maneuver(run: AutoTrainRun) -> void:
	var plain: bool = _maneuvers[run.id]["table"] == null
	var train: Array[Vehicle] = get_train(run)
	var loco: Vehicle = train[0]
	var wagons: Array[Vehicle] = train.slice(1)
	var from: Vector3 = loco.global_position
	wagons.sort_custom(func(a: Vehicle, b: Vehicle) -> bool: return a.global_position.distance_to(from) < b.global_position.distance_to(from))
	loco.uncouple_rear()
	for wagon: Vehicle in wagons:
		wagon.uncouple_rear()
	loco.throttle = 0.0
	loco.brake = 1.0
	loco.speed = 0.0
	if plain:
		loco.place_on(loco.get_parent() as Path3D, loco.progress, not loco.reversed)
	var ordered: Array = [loco]
	for wagon: Vehicle in wagons:
		if loco.get_tail().couple(wagon):
			ordered.append(wagon)
		else:
			push_warning("AutoTrains: al dar la vuelta no se pudo enganchar un vagón del %s." % run.display_name)
			wagon.queue_free()
	_trains[run.id] = ordered
	_end_maneuver(run)
	_finish_turn(run, plain)
	loco.model_yaw = PI if run.loco_flipped else 0.0
	var at: float = _leg_coordinate(run, loco)
	if not is_nan(at):
		run.set_position(at)
	_apply_loads(run)


# Devuelve lo que reservó para maniobrar y le vuelve a dar a la locomotora su elección de cambios.
func _end_maneuver(run: AutoTrainRun) -> void:
	var maneuver: Dictionary = _maneuvers[run.id]
	_maneuvers.erase(run.id)
	# Lo que ya es parte del próximo viaje reservado queda reservado.
	var kept: Array[StringName] = []
	if _reserved.has(run.id):
		for piece: StringName in run.leg:
			kept.append(AutoTrainRun.piece_section(piece))
	for section: StringName in maneuver["taken"]:
		if get_token_holder(section) == run.id and not kept.has(section):
			_tokens.erase(section)
	var train: Array[Vehicle] = get_train(run)
	if not train.is_empty():
		train[0].switch_chooser = _choose_switch.bind(run)
	var table: Node3D = maneuver["table"]
	if is_instance_valid(table):
		table.rotation.y = 0.0
	_update_signals()
