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
## Bastón (vía simple): un tren solo sale si tiene el bastón de todos los tramos de vía simple
## de su viaje (ningún otro automático lo tiene), ninguna vía de su camino tiene otro vehículo
## (en la doble, la de su sentido) y no hay otro automático parado en una estación del medio;
## lo devuelve al llegar. A la entrada de esos tramos hay semáforos (RailSignal): rojo mientras
## el tramo está ocupado (alguien tiene el bastón, hay un vehículo o un automático quedó parado
## en una punta, porque las estaciones todavía no tienen vía propia y el tren parado queda
## dentro del tramo). En la vía doble no hace falta bastón: cada uno va por la suya.
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
# segment_id -> run.id que tiene el bastón.
var _tokens: Dictionary = {}
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


## Quién tiene el bastón del tramo (id de viaje), o 0.
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
	for run: AutoTrainRun in _runs.duplicate():
		if not run.is_moving():
			if run.leg.is_empty():
				_plan_parked_leg(run)
			_try_depart(run, now)
		elif not is_spawned(run):
			if run.advance(speed * delta, now, _abstract_limit(run)):
				_on_arrived(run)


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

func _try_depart(run: AutoTrainRun, now: float) -> void:
	if not run.is_due(now):
		return
	var network: RailNetwork = _network()
	if network == null:
		return
	var route: Array[StringName] = network.find_route(run.leg_from(), run.leg_to())
	if route.is_empty():
		run.waiting = "vía cortada"
		return
	var entry: StringName = run.leg_from()
	for index: int in route.size():
		var segment_id: StringName = route[index]
		var double: bool = network.is_double(segment_id)
		if not double:
			var holder: int = get_token_holder(segment_id)
			if holder != 0 and holder != run.id:
				run.waiting = "esperando el bastón"
				return
		# En la vía doble solo importa la de su sentido.
		var track: TrackSegment = network.track_leaving(segment_id, entry) if double else null
		if _has_foreign_vehicle(network, segment_id, run, track):
			run.waiting = "vía ocupada"
			return
		var next_entry: StringName = network.other_end(segment_id, entry)
		# Otro automático parado en una estación del medio del viaje tapa la vía.
		if index < route.size() - 1 and _parked_run_at(next_entry, segment_id, run) != null:
			run.waiting = "vía ocupada"
			return
		entry = next_entry
	var lengths: Array[float] = []
	for segment_id: StringName in route:
		lengths.append(network.get_segment_length(segment_id))
	# El tren de verdad tiene que quedar en la vía de salida (en la vía doble, la de su sentido).
	var was_spawned: bool = is_spawned(run)
	if not run.depart(route, lengths):
		return
	for segment_id: StringName in route:
		if not network.is_double(segment_id):
			_tokens[segment_id] = run.id
			_ensure_signals(network, segment_id)
	if was_spawned and not _train_on_leg(run):
		_despawn(run)
		_spawn(run)
	if is_spawned(run):
		_apply_loads(run)
		get_train(run)[0].destination = run.leg_to()
	_update_signals()
	train_departed.emit(run)


func _on_arrived(run: AutoTrainRun) -> void:
	_release_tokens(run)
	_blocked.erase(run.id)
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


func _release_tokens(run: AutoTrainRun) -> void:
	for segment_id: Variant in _tokens.keys():
		if int(_tokens[segment_id]) == run.id:
			_tokens.erase(segment_id)


# Hay en el tramo (o solo en su vía `only`) un vehículo que no es de este tren (el del jugador,
# uno suelto u otro automático). Sin `run`, cualquier vehículo.
func _has_foreign_vehicle(network: RailNetwork, segment_id: StringName, run: AutoTrainRun, only: TrackSegment = null) -> bool:
	var own: Array[Vehicle] = []
	if run != null:
		own = get_train(run)
	for track: TrackSegment in network.get_tracks(segment_id):
		if only != null and track != only:
			continue
		var path: Path3D = track.get_track_path()
		if path == null:
			continue
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
	for track: TrackSegment in network.get_tracks(segment_id):
		for station_id: StringName in [track.from_station, track.to_station]:
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
	for key: String in _signals:
		var signal_node: RailSignal = _signals[key] if is_instance_valid(_signals[key]) else null
		if signal_node != null:
			signal_node.set_clear(not is_segment_busy(signal_node.segment_id))


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
		if start >= front_tip - 0.01 and network.is_cut(run.leg[index]):
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
		if run.leg[index] != track.segment_id:
			continue
		var entry: StringName = run.segment_entry(index, network.other_end)
		if network.is_double(track.segment_id) and network.track_leaving(track.segment_id, entry) != track:
			continue
		var track_length: float = track.get_length()
		var along: float = vehicle.progress if track.from_station == entry else track_length - vehicle.progress
		var scale: float = run.leg_lengths[index] / track_length if track_length > 0.0 else 1.0
		var at: float = run.segment_start(index) + along * scale
		# Si el viaje pasa dos veces por el mismo tramo, la más cercana al tren.
		if is_nan(best) or absf(at - run.position) < absf(best - run.position):
			best = at
	return best


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
	var entry: StringName = run.segment_entry(index, network.other_end)
	var track: TrackSegment = network.track_leaving(run.leg[index], entry)
	if track == null or track.get_track_path() == null:
		return []
	var track_length: float = track.get_length()
	var scale: float = track_length / run.leg_lengths[index] if run.leg_lengths[index] > 0.0 else 1.0
	var along: float = float(spot[1]) * scale
	var forward: bool = track.from_station == entry
	var progress: float = along if forward else track_length - along
	# A la ida la locomotora mira hacia donde va; a la vuelta, hacia atrás.
	var faces_end: bool = forward == run.is_outbound()
	return [track.get_track_path(), progress, faces_end, index]


# Un tren parado que todavía no tiene viaje (recién creado): le arma el próximo, para saber
# dónde está parado. Devuelve false si no hay camino.
func _plan_parked_leg(run: AutoTrainRun) -> bool:
	var network: RailNetwork = _network()
	if network == null or run.is_moving():
		return false
	var route: Array[StringName] = network.find_route(run.leg_from(), run.leg_to(), true)
	if route.is_empty():
		return false
	var lengths: Array[float] = []
	for segment_id: StringName in route:
		lengths.append(network.get_segment_length(segment_id))
	run.leg = route
	run.leg_lengths = lengths
	run.position = run.start_position()
	if not network.is_double(route[0]):
		_ensure_signals(network, route[0])
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
	_trains[run.id] = train
	_set_label(run)
	_apply_loads(run)
	train_spawned.emit(run)


func _despawn(run: AutoTrainRun) -> void:
	if not _trains.has(run.id):
		return
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
		loco.throttle = AUTO_THROTTLE * (1.0 if run.is_outbound() else -1.0)
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
