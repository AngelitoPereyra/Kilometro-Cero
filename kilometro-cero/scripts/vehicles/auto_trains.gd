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
## llegada, espera en su estación. Carteles de señal (RailSignal, D117): en cada punta de cada
## tramo hay un cartel de línea (salida a la línea y entrada a la estación) y en cada vía de
## estación, pasando el cambio, uno con su salida y su entrada; todos los prende este nodo.
## Paso por las vías de estación (tarea 61e.2, D117): cada punta de la estación se maneja sola.
## Junto al cartel de cada vía que no es la principal hay una palanca (TrackLever) para pedir el paso
## (entrar o salir por esa punta); sin pedirlo (o sin StationTrack.spring_exit) su salida queda en
## rojo para el tren del jugador, que frena en el cartel (RailNetwork.set_exit_stop). La principal
## no pide: sale en verde si ninguna otra vía trabó el cambio y lo que sigue está libre. La palanca
## madre de cada cambio (RailNetwork) reserva una vía para entrar: queda bloqueada en sus dos puntas
## (entradas en rojo) y ningún automático la elige. La
## principal manda: mientras por ella va un tren hacia esa punta (o un automático va a salir por
## ahí), las otras vías no salen a la línea por esa punta. La maniobra de vuelta reserva el tramo
## al que se asoma recién cuando va a salir a él.
## La salida de un tramo está en rojo mientras está ocupado; un tramo reservado además cierra su
## entrada para el tren del jugador (RailNetwork.set_entry_closed): es como si estuviera
## cortado hasta que el automático lo deja. En la vía doble no hace falta reservar: cada uno va
## por la suya.
## Bloques de la vía doble (tarea 61e.3): cada vía de un tramo doble se parte en bloques de más o
## menos `block_length`, con un cartel de bloque (RailSignal.Kind.BLOCK) al principio de cada uno
## (el primero empieza en el cartel de salida). Un cartel está en rojo si hay algo en su bloque (un
## vehículo o un automático lejos del jugador) y en amarillo si el próximo (o la entrada a la
## estación de llegada) está en rojo. En el rojo frena cualquier tren (RailNetwork.set_block_stops),
## así dos trenes van por la misma vía uno atrás del otro: un automático sale apenas se libera el
## primer bloque, y lejos del jugador tampoco pasa un cartel en rojo. El cartel de salida a la línea
## también se pone en amarillo, en la vía simple si la entrada de la otra punta está en rojo.
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
## Troncales (D118, tarea 61d): si en el mundo hay líneas marcadas a mano (TrunkLine), los flujos
## con sus dos estaciones en una línea no van en el tren de su conexión sino en una troncal de
## la línea: una de carga (todo lo que no es gente) y otra de pasajeros. Cada una va de punta a
## punta del pedazo de la línea que usan sus flujos y se estira cuando aparece uno más lejos (la
## punta donde está parada queda; la lejana cambia enseguida). Sus vagones salen del tramo más
## cargado (TrunkPlanner) y lo que no entra en lo que arrastra la locomotora va en otro servicio
## del mismo recorrido, a otra hora. Lo que no va por una línea sigue con el tren de su conexión.
## Paradas y prioridad (tarea 61d.2): la troncal para media hora en cada estación del medio de su
## recorrido, a la ida y a la vuelta (en la principal si está libre): en cada una baja y sube lo
## que haga falta (Batmi, 2026-10-28); reserva de parada en parada (AutoTrainRun.hop_to). Si varios piden vía a la vez, la troncal va
## primero. Lleva una locomotora en cada punta: no da la vuelta, a la vuelta la de adelante es la
## de la cola (la que tira, la de la cabeza del tren, empuja; lejos es igual).
## Carga y tablero (tarea 61d.3): cada vagón de una troncal muestra lo que lleva en el pedazo que
## sale de la estación donde está (al parar baja lo que llega y sube lo que sigue), y el tablero
## de cada estación del medio dice a qué hora para la troncal a la ida y a la vuelta, según su
## horario.
## Trabados y perdidos (tarea 62.4, D120): un automático trabado STUCK_SECONDS en el camino (por
## ejemplo, de frente con el tren del jugador en una vía simple) vuelve a la estación de donde salió
## si lo de atrás está libre (AutoTrainRun.turn_back), espera y prueba otra vez. Uno de verdad que
## se salió de su recorrido (su locomotora en una vía que no es de su viaje) frena, avisa con un
## warning y vuelve a su recorrido (desaparece y lo retoma como número).
## Guardados (tarea 62.4, D120, idea de Batmi para el Hito A, hasta que haya playas de maniobra):
## con `park_hidden`, un tren parado en su punta se guarda HIDE_AFTER_HOURS después de llegar (no
## ocupa vía ni se ve) y vuelve SHOW_BEFORE_HOURS antes de su salida, en una vía libre de su
## estación (si no hay, espera). El primer viaje de un tren nuevo sale a su horario.

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
const BOXCAR_SCENE: String = "res://scenes/vehicles/boxcar.tscn"
const LOCOMOTIVE_DATA: String = "res://data/vehicles/locomotive.tres"
const FLATCAR_DATA: String = "res://data/vehicles/flatcar.tres"
const COACH_DATA: String = "res://data/vehicles/passenger_coach.tres"
const BOXCAR_DATA: String = "res://data/vehicles/boxcar.tres"
const KIND_FLATCAR: StringName = &"flatcar"
const KIND_COACH: StringName = &"coach"
## Vagón cerrado (tarea 62): lo que acepta boxcar.tres (el cemento).
const KIND_BOXCAR: StringName = &"boxcar"
## Motivos de las troncales (tarea 61d): carga y pasajeros van en trenes distintos.
const TRUNK_CARGO: String = "carga"
const TRUNK_PASSENGERS: String = "pasajeros"
## En qué vía para un tren al llegar, en orden de preferencia: la de carga, la de cruce y la
## principal. La troncal de pasajeros para en la principal, junto al andén (tarea 61d.3, Batmi):
## así la gente no cruza la vía del tren de carga.
const DEFAULT_TRACK_ROLES: Array = [StationTrack.Role.FREIGHT, StationTrack.Role.SIDING, StationTrack.Role.MAIN]
const PASSENGER_TRACK_ROLES: Array = [StationTrack.Role.MAIN, StationTrack.Role.SIDING, StationTrack.Role.FREIGHT]
## Acelerador con que andan (fracción de la velocidad máxima), también lejos del jugador.
const AUTO_THROTTLE: float = 0.7
## Primer horario de ida y cuántas horas después sale el tren siguiente (provisorio).
const FIRST_HOUR: float = 7.0
const HOUR_STEP: float = 2.0
const SCHEDULE_SLOTS: int = 4
## Segundos trabado (acelerando sin moverse) antes de tocar la bocina y avisar que espera.
const BLOCKED_TIME: float = 2.0
## Dónde van los carteles de línea: metros dentro del tramo desde la estación y al costado de la vía.
const SIGNAL_OFFSET: float = 8.0
const SIGNAL_SIDE: float = 3.0
const ARRIVING_SUFFIX: String = "|llegada"
## Lo que dice un automático parado ante un cartel de bloque en rojo (tarea 61e.3).
const SIGNAL_WAIT: String = "esperando cartel en verde"
## Un automático que llega a una estación por el tramo (_arriving_auto): ninguno, todavía antes
## del cartel de entrada o ya pasado.
const ARRIVING_NONE: int = 0
const ARRIVING_BEFORE: int = 1
const ARRIVING_PAST: int = 2
## Carteles de vía de estación (D117): metros que se aparta una vía de la recta para quedar del otro
## lado de la división, cuánto más allá va el cartel, dónde va si ninguna se aparta y al costado.
const TRACK_FOULING_LATERAL: float = 3.5
const TRACK_SIGNAL_MARGIN: float = 12.0
const TRACK_SIGNAL_DEFAULT: float = 15.0
const TRACK_SIGNAL_SIDE: float = 2.5
## Cuántos metros hacia el cambio, desde el cartel de vía, va su palanca (tarea 61e.2).
const TRACK_LEVER_AHEAD: float = 2.0
## Por encima de esta velocidad (m/s) un tren en la principal la ocupa (tarea 61e.2).
const MAIN_BUSY_SPEED: float = 0.1
## Horas antes de su salida que un tren reserva su viaje (15 minutos, D114).
const RESERVE_AHEAD_HOURS: float = 0.25
## Lejos del jugador, cuánto tarda en dar la vuelta (horas de juego).
const TURN_HOURS: float = 0.25
## Segundos trabado en el camino antes de volver a la estación de donde salió (tarea 62.4).
## Cuántos cambios seguidos mira, a lo sumo, una luz de entrada (tarea 62.6).
const MAX_SWITCH_CHAIN: int = 6
const STUCK_SECONDS: float = 15.0
## Segundos con la locomotora fuera de su recorrido: a los primeros frena, al final vuelve a él.
const LOST_BRAKE_SECONDS: float = 0.5
const LOST_SECONDS: float = 2.0
## Con park_hidden (tarea 62.4): horas después de llegar en que se guarda y antes de salir en que vuelve.
const HIDE_AFTER_HOURS: float = 0.5
const SHOW_BEFORE_HOURS: float = 0.5
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
## Largo de cada bloque de la vía doble (tarea 61e.3): entre carteles de bloque. Las vías más cortas
## que esto (sin contar la salida y la llegada) quedan en un solo bloque.
@export_range(20.0, 2000.0, 1.0, "suffix:m") var block_length: float = 400.0
## Guarda los trenes parados en su punta entre viaje y viaje (tarea 62.4): no ocupan vía. Apagado,
## como antes, esperan en su vía.
@export var park_hidden: bool = false

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
# "tramo|estación" -> RailSignal de línea ("tramo|estación|llegada" en la vía que llega de la doble).
var _signals: Dictionary = {}
# "@estación/Vía|A" o "|B" -> RailSignal de vía de estación (D117).
var _track_signals: Dictionary = {}
# "tramo|estación de donde sale la vía|n" -> RailSignal: los carteles de bloque (tarea 61e.3).
var _block_signals: Dictionary = {}
# run.id -> segundos trabado
var _blocked: Dictionary = {}
# run.id -> segundos trabado lejos del jugador (tarea 62.4).
var _stuck: Dictionary = {}
# run.id -> segundos con la locomotora fuera de su recorrido (tarea 62.4).
var _lost: Dictionary = {}
## Troncales (tarea 61d): id del viaje -> {"line": ids de la línea, "low" y "high": las puntas
## que usan sus flujos, "flows", "passengers", "service"}.
var _trunk_targets: Dictionary = {}
var _signature: String = ""
var _next_id: int = 1
var _refresh_left: float = 0.0
var _loco_data: VehicleData
var _flatcar_data: WagonData
var _coach_data: WagonData
var _boxcar_data: WagonData


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_loco_data = load(LOCOMOTIVE_DATA) as VehicleData
	_flatcar_data = load(FLATCAR_DATA) as WagonData
	_coach_data = load(COACH_DATA) as WagonData
	_boxcar_data = load(BOXCAR_DATA) as WagonData


## El AutoTrains de la escena, o null.
static func find_in(tree: SceneTree) -> AutoTrains:
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP) as AutoTrains


## La próxima salida de un tren automático después de `after` (horas absolutas), o INF si no hay
## (tarea 62.6: la T del Hito A adelanta el reloj hasta ahí).
func next_departure(after: float) -> float:
	var best: float = INF
	for run: AutoTrainRun in _runs:
		if not run.is_moving() and run.due > after:
			best = minf(best, run.due)
	return best


## Hora absoluta del juego (horas desde el principio de la partida).
static func now_hours() -> float:
	return float(GameState.clock.current_day - 1) * GameClock.HOURS_PER_DAY + GameState.clock.time_of_day


## La clave de una conexión: las dos estaciones en orden alfabético.
static func connection_key(a: StringName, b: StringName) -> String:
	return "%s|%s" % ([a, b] if String(a) < String(b) else [b, a])


## Los vagones de un tren (lógica pura): por cada flujo, del más viejo al más nuevo, los que
## hacen falta para su carga por día (`capacities`: tipo -> lugares), sin pasar de
## `max_wagons`. La gente va en coche y lo demás en plataforma; con `kind_of` (func(item_id) ->
## tipo, tarea 62) cada carga va en su tipo de vagón (el cemento en el cerrado). "dir": 1 de
## `home` hacia la otra estación, -1 al revés, 0 si el flujo va y vuelve.
static func plan_wagons(flows: Array[ProductionFlow], home: StringName, is_passenger: Callable, capacities: Dictionary, max_wagons: int, kind_of: Callable = Callable()) -> Array[Dictionary]:
	var wagons: Array[Dictionary] = []
	for flow: ProductionFlow in flows:
		var kind: StringName = KIND_COACH if is_passenger.call(flow.item_id) else KIND_FLATCAR
		if kind_of.is_valid():
			kind = kind_of.call(flow.item_id)
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
		if run.serves(station_id):
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


## El cartel de línea de la punta del tramo en esa estación (en la vía doble, el de la vía que
## sale de ella), o null.
func get_signal(segment_id: StringName, station_id: StringName) -> RailSignal:
	var found: Variant = _signals.get("%s|%s" % [segment_id, station_id])
	return found if is_instance_valid(found) else null


## Texto de los trenes de una estación para el tablero (vacío si no pasa ninguno).
func describe_at(station_id: StringName) -> PackedStringArray:
	var lines: PackedStringArray = []
	for run: AutoTrainRun in get_runs_at(station_id):
		lines.append(run.status_text(_station_name) + _pass_text(run, station_id))
	return lines


## Revisa los flujos ahora (normalmente lo hace solo cada REFRESH_TIME).
func sync_flows() -> void:
	# Los que empiezan mañana todavía no llevan tren (tarea 62.4).
	var flows: Array[ProductionFlow] = GameState.production.get_running_flows() if GameState.production != null else [] as Array[ProductionFlow]
	var lines: Array[Array] = []
	for line: TrunkLine in TrunkLine.find_all(get_tree() if is_inside_tree() else null):
		var ids: Array[StringName] = line.get_station_ids()
		if ids.size() >= 2:
			lines.append(ids)
	var parts: PackedStringArray = []
	for ids: Array in lines:
		parts.append("L:" + "-".join(PackedStringArray(ids)))
	for flow: ProductionFlow in flows:
		parts.append("%d:%s:%s:%s:%d:%s:%s" % [flow.id, flow.from_station, flow.to_station, flow.item_id, flow.amount, flow.round_trip, flow.custom_name])
	var signature: String = ",".join(parts)
	if signature == _signature:
		return
	_signature = signature
	var groups: Dictionary = {}
	var order: Array[String] = []
	# Troncales (tarea 61d): los flujos de cada línea, por motivo.
	var by_line: Dictionary = {}
	var line_order: Array[String] = []
	for flow: ProductionFlow in flows:
		var line_index: int = _line_for(flow, lines)
		var key: String = connection_key(flow.from_station, flow.to_station)
		var bucket: Dictionary = groups
		if line_index >= 0:
			key = "%d|%s" % [line_index, TRUNK_PASSENGERS if _is_passenger(flow.item_id) else TRUNK_CARGO]
			bucket = by_line
		if not bucket.has(key):
			bucket[key] = [] as Array[ProductionFlow]
			if line_index >= 0:
				line_order.append(key)
			else:
				order.append(key)
		(bucket[key] as Array[ProductionFlow]).append(flow)
	var trunks: Dictionary = {}
	for line_key: String in line_order:
		var line: Array[StringName] = lines[int(line_key.get_slice("|", 0))]
		var motive: String = line_key.get_slice("|", 1)
		var kind: StringName = KIND_COACH if motive == TRUNK_PASSENGERS else KIND_FLATCAR
		var services: Array = TrunkPlanner.split_services(by_line[line_key], line, _capacity(kind), _max_wagons(), _kind_of_callable(), _capacities())
		for index: int in services.size():
			var key: String = "troncal|%s|%s|%d" % ["-".join(PackedStringArray(line)), motive, index + 1]
			trunks[key] = {"line": line, "flows": services[index], "passengers": motive == TRUNK_PASSENGERS, "service": index + 1}
			order.append(key)
	for run: AutoTrainRun in _runs.duplicate():
		if not groups.has(_run_key(run)) and not trunks.has(_run_key(run)):
			_remove_run(run)
	for key: String in order:
		var run: AutoTrainRun = _find_run(key)
		if trunks.has(key):
			if run == null:
				run = _create_trunk_run(key, trunks[key])
			_update_trunk_run(run, trunks[key])
			continue
		var group: Array[ProductionFlow] = groups[key]
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
			if run.is_trunk() and _apply_trunk_span(run):
				_refresh_trunk(run)
			if park_hidden and _update_parking(run, now):
				continue
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
				if not is_spawned(run):
					_check_stuck_far(run, delta)
	# Si varios piden a la vez, primero el que lleva más carga (D114).
	asking.sort_custom(_goes_first)
	for run: AutoTrainRun in asking:
		_try_depart(run, now)


## Para el guardado (tarea 65): los viajes por conexión.
func to_dict() -> Dictionary:
	var runs: Array = []
	for run: AutoTrainRun in _runs:
		var values: Dictionary = run.to_dict()
		values["key"] = _run_key(run)
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
			if run.is_trunk():
				# La troncal pudo haber cambiado de puntas: retoma las suyas.
				run.home = StringName(saved.get("home", run.home))
				run.away = StringName(saved.get("away", run.away))
				_refresh_trunk(run)
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
		if _run_key(run) == key:
			return run
	return null


# La clave de un viaje: la de su troncal o la de su conexión.
static func _run_key(run: AutoTrainRun) -> String:
	return run.trunk_key if run.is_trunk() else connection_key(run.home, run.away)


func _create_run(first: ProductionFlow) -> AutoTrainRun:
	var run := AutoTrainRun.new()
	run.home = first.from_station
	run.away = first.to_station
	_start_run(run)
	return run


# Le da id, largo y horario a un viaje nuevo y lo suma.
func _start_run(run: AutoTrainRun) -> void:
	run.id = _next_id
	_next_id += 1
	run.loco_length = _loco_data.length if _loco_data != null else 10.0
	var now: float = now_hours()
	run.set_schedule(FIRST_HOUR + HOUR_STEP * float(_runs.size() % SCHEDULE_SLOTS), now)
	if park_hidden:
		# Guardado (62.4): el primer viaje sale a su horario y el tren aparece un rato antes.
		run.hidden = run.due - now > SHOW_BEFORE_HOURS
		if run.hidden:
			run.waiting = _hidden_text(run)
	else:
		# El primer viaje sale apenas nace el flujo; después sigue su horario.
		run.due = now + AutoTrainRun.MIN_DWELL_HOURS
	_runs.append(run)
	train_added.emit(run)


func _update_run(run: AutoTrainRun, flows: Array[ProductionFlow]) -> void:
	run.flow_ids.clear()
	for flow: ProductionFlow in flows:
		run.flow_ids.append(flow.id)
	run.display_name = FlowNames.train_name(flows, _find_item, _station_name)
	_set_wagons(run, plan_wagons(flows, run.home, _is_passenger, _capacities(), _max_wagons(), _kind_of_callable()))


func _capacity(kind: StringName) -> int:
	var data: WagonData = _wagon_data(kind)
	if data != null:
		return data.capacity
	return 10 if kind == KIND_COACH else (40 if kind == KIND_BOXCAR else 20)


# Lugares de cada tipo de vagón (tarea 62).
func _capacities() -> Dictionary:
	return {KIND_FLATCAR: _capacity(KIND_FLATCAR), KIND_COACH: _capacity(KIND_COACH), KIND_BOXCAR: _capacity(KIND_BOXCAR)}


## El tipo de vagón de un objeto (tarea 62): coche si es gente, vagón cerrado si lo acepta
## boxcar.tres (el cemento) y si no plataforma.
func kind_for(item_id: StringName) -> StringName:
	if _is_passenger(item_id):
		return KIND_COACH
	var item: ItemData = _find_item(item_id)
	if item != null and _boxcar_data != null:
		for tag: StringName in item.tags:
			if _boxcar_data.accepted_tags.has(tag):
				return KIND_BOXCAR
	return KIND_FLATCAR


func _kind_of_callable() -> Callable:
	return kind_for


func _max_wagons() -> int:
	return _loco_data.max_wagons if _loco_data != null else 4


func _set_wagons(run: AutoTrainRun, wagons: Array[Dictionary]) -> void:
	var changed: bool = wagons != run.wagons
	run.wagons = wagons
	var lengths: Array[float] = []
	for wagon: Dictionary in wagons:
		lengths.append(_wagon_data(wagon["kind"]).length if _wagon_data(wagon["kind"]) != null else 10.0)
	if run.is_trunk():
		# La locomotora de la cola (tarea 61d.2).
		lengths.append(run.loco_length)
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
	_trunk_targets.erase(run.id)
	_blocked.erase(run.id)
	_stuck.erase(run.id)
	_lost.erase(run.id)
	_reserved.erase(run.id)
	_requested.erase(run.id)
	_maneuvers.erase(run.id)
	_update_signals()
	train_removed.emit(run)


# --- Troncales (tarea 61d, D118) ---

# La primera línea por donde va el flujo, o -1.
static func _line_for(flow: ProductionFlow, lines: Array[Array]) -> int:
	for index: int in lines.size():
		var line: Array[StringName] = lines[index]
		if TrunkPlanner.fits(flow, line):
			return index
	return -1


func _create_trunk_run(key: String, info: Dictionary) -> AutoTrainRun:
	var line: Array[StringName] = info["line"]
	var reach: Vector2i = _trunk_reach(info["flows"], line)
	var run := AutoTrainRun.new()
	run.trunk_key = key
	run.home = line[reach.x]
	run.away = line[reach.y]
	_start_run(run)
	return run


func _update_trunk_run(run: AutoTrainRun, info: Dictionary) -> void:
	var line: Array[StringName] = info["line"]
	var flows: Array[ProductionFlow] = info["flows"]
	var reach: Vector2i = _trunk_reach(flows, line)
	_trunk_targets[run.id] = {"line": line, "low": line[reach.x], "high": line[reach.y], "flows": flows, "passengers": info["passengers"], "service": info["service"]}
	_apply_trunk_span(run)
	_refresh_trunk(run)


# Estira o acorta el recorrido hacia lo que usan sus flujos: solo parada (sin viaje reservado ni
# maniobra), deja la punta donde está y cambia la lejana. Si la punta donde está también cambió,
# se corrige al llegar a la otra. Devuelve true si cambió algo.
func _apply_trunk_span(run: AutoTrainRun) -> bool:
	var target: Dictionary = _trunk_targets.get(run.id, {})
	if target.is_empty() or run.is_moving() or run.dwelling or _maneuvers.has(run.id) or _requested.has(run.id) or _has_trip_reserved(run):
		return false
	var line: Array[StringName] = target["line"]
	var low: StringName = target["low"]
	var high: StringName = target["high"]
	var at_home: bool = run.state == AutoTrainRun.State.AT_HOME
	var here: StringName = run.home if at_home else run.away
	var far: StringName = run.away if at_home else run.home
	# La punta lejana nueva queda del mismo lado que la de antes.
	var new_far: StringName = high if line.find(far) >= line.find(here) else low
	if new_far == here:
		new_far = low if new_far == high else high
	if new_far == far:
		return false
	if at_home:
		run.away = new_far
	else:
		run.home = new_far
	return true


# Nombre, recorrido y vagones de una troncal según sus flujos y sus puntas de ahora.
func _refresh_trunk(run: AutoTrainRun) -> void:
	var target: Dictionary = _trunk_targets.get(run.id, {})
	if target.is_empty():
		return
	var line: Array[StringName] = target["line"]
	var flows: Array[ProductionFlow] = target["flows"]
	var passengers: bool = target["passengers"]
	run.flow_ids.clear()
	for flow: ProductionFlow in flows:
		run.flow_ids.append(flow.id)
	run.stops = TrunkPlanner.stops(line, run.home, run.away)
	run.display_name = FlowNames.trunk_name(flows, passengers, target["low"], target["high"], _station_name, int(target["service"]))
	var kind: StringName = KIND_COACH if passengers else KIND_FLATCAR
	_set_wagons(run, TrunkPlanner.plan_wagons(flows, line, run.home, run.away, kind, _capacity(kind), _max_wagons(), _kind_of_callable(), _capacities()))


# Las puntas de una troncal: lo que usan sus flujos, estirado hasta una ciudad (61d.2).
func _trunk_reach(flows: Array[ProductionFlow], line: Array[StringName]) -> Vector2i:
	var hubs: Array[bool] = []
	for station_id: StringName in line:
		var data: StationData = GameState.production.get_data(station_id) if GameState.production != null else null
		hubs.append(data != null and (data.type == StationData.StationType.CITY or data.type == StationData.StationType.PORT))
	return TrunkPlanner.anchor(TrunkPlanner.span(flows, line), hubs)


# La próxima parada de una troncal desde donde está (tarea 61d.2): la estación siguiente de su
# recorrido en el sentido del viaje (para en todas); "" si la siguiente es la punta.
func _next_stop(run: AutoTrainRun) -> StringName:
	var route: Array[StringName] = run.stops.duplicate()
	if not run.is_outbound():
		route.reverse()
	var start: int = route.find(run.leg_from())
	if start < 0 or start + 1 >= route.size() - 1:
		return &""
	return route[start + 1]


# Para el tablero de una estación del medio de una troncal (61d.3): a qué hora para, a la ida y a
# la vuelta, según su horario (sin contar demoras). "" si no es troncal o es una punta.
func _pass_text(run: AutoTrainRun, station_id: StringName) -> String:
	if not run.is_trunk() or station_id == run.home or station_id == run.away or not run.stops.has(station_id):
		return ""
	var parts: PackedStringArray = []
	for outbound: bool in [true, false]:
		var route: Array[StringName] = run.stops.duplicate()
		if not outbound:
			route.reverse()
		var hours: float = 0.0
		for index: int in range(1, route.size()):
			hours += _travel_hours(route[index - 1], route[index])
			if route[index] == station_id:
				break
			hours += AutoTrainRun.MIN_DWELL_HOURS
		var start: float = run.out_hour if outbound else run.back_hour
		parts.append("a la %s %s" % ["ida" if outbound else "vuelta", AutoTrainRun.hour_text(start + hours)])
	return " · para acá " + ", ".join(parts)


# Cuánto tarda lejos del jugador de una estación a otra (horas de juego).
func _travel_hours(from: StringName, to: StringName) -> float:
	var network: RailNetwork = _network()
	if network == null:
		return 0.0
	var meters: float = 0.0
	for segment_id: StringName in network.find_route(from, to, true):
		meters += network.get_segment_length(segment_id)
	var per_hour: float = _abstract_speed() / GameClock.hours_per_real_second(GameState.DAY_LENGTH_MINUTES)
	return meters / per_hour if per_hour > 0.0 else 0.0


# Las vías donde prefiere parar (61d.3): la troncal de pasajeros en la principal; los demás, en la
# de carga o la de cruce.
func _track_roles(run: AutoTrainRun) -> Array:
	var target: Dictionary = _trunk_targets.get(run.id, {})
	if run.is_trunk() and bool(target.get("passengers", false)):
		return PASSENGER_TRACK_ROLES
	return DEFAULT_TRACK_ROLES


# Cuántos vehículos tiene el tren en la escena: locomotora, vagones y, en las troncales, la
# locomotora de la cola.
static func _train_size(run: AutoTrainRun) -> int:
	return run.wagons.size() + (2 if run.is_trunk() else 1)


func _wagon_data(kind: StringName) -> WagonData:
	match kind:
		KIND_COACH:
			return _coach_data
		KIND_BOXCAR:
			return _boxcar_data
	return _flatcar_data


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
	if run.is_trunk():
		# De parada en parada (61d.2): hasta la próxima estación donde sube o baja algo.
		run.hop_to = _next_stop(run)
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
	# La troncal siempre primero (tarea 61d.2).
	if a.is_trunk() != b.is_trunk():
		return a.is_trunk()
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
		start = _pick_track(run, leaving, false, _track_roles(run))
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
				chosen = _pick_track(run, arriving, strict, _track_roles(run))
				if chosen.is_empty():
					return {"error": "esperando vía libre en %s" % _station_name(station)}
			else:
				for option: Array in arriving:
					if (option[0] as StationTrack).is_main():
						chosen = option
				# Si en la principal hay otro tren parado, pasa por otra vía libre (61d.2).
				if not chosen.is_empty() and _pick_track(run, [chosen], true).is_empty():
					var other: Array = _pick_track(run, arriving, true)
					if not other.is_empty():
						chosen = other
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
func _pick_track(run: AutoTrainRun, options: Array, strict: bool, roles: Array = DEFAULT_TRACK_ROLES) -> Array:
	var ordered: Array = []
	for role: StationTrack.Role in roles:
		for option: Array in options:
			if (option[0] as StationTrack).role == role:
				ordered.append(option)
	var own: Array[Vehicle] = get_train(run)
	var network: RailNetwork = _network()
	for option: Array in ordered:
		var station_track: StationTrack = option[0]
		var holder: int = get_token_holder(_section_of(station_track))
		var reserved: bool = network != null and network.is_track_reserved(station_track.get_track_path())
		if (holder == 0 or holder == run.id) and not reserved and not _path_has_foreign(station_track.get_track_path(), own):
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
			if path != null and (_path_has_foreign(path, own) or network.is_track_reserved(path)):
				return "vía ocupada"
			continue
		if network.is_double(piece):
			# En la vía doble solo importa la de su sentido y en ella el primer bloque: los que
			# siguen los cuida su cartel (tarea 61e.3).
			var track: TrackSegment = network.track_leaving(piece, entry)
			if track != null and _block_busy(network, track, 0, run, true):
				return "vía ocupada"
		else:
			var holder: int = get_token_holder(piece)
			if holder != 0 and holder != run.id:
				return "esperando vía libre"
			if _has_foreign_vehicle(network, piece, run):
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
		if train.size() != _train_size(run):
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


# Hay en el tramo un vehículo que no es de este tren (el del jugador, uno suelto u otro
# automático). Sin `run`, cualquier vehículo. Con `skip_loose`, los vagones sueltos no cuentan.
func _has_foreign_vehicle(network: RailNetwork, segment_id: StringName, run: AutoTrainRun, skip_loose: bool = false) -> bool:
	var own: Array[Vehicle] = []
	if run != null:
		own = get_train(run)
	for track: TrackSegment in network.get_tracks(segment_id):
		if _path_has_foreign(track.get_track_path(), own, skip_loose):
			return true
	return false


# Hay en la curva un vehículo que no es de `own`. Con `skip_loose`, los vagones sueltos no
# cuentan (tarea 62.3).
static func _path_has_foreign(path: Path3D, own: Array[Vehicle], skip_loose: bool = false) -> bool:
	if path == null:
		return false
	for child: Node in path.get_children():
		var vehicle := child as Vehicle
		if vehicle != null and not own.has(vehicle) and not vehicle.is_queued_for_deletion() and not (skip_loose and is_loose(vehicle)):
			return true
	return false


## Si el vehículo es parte de un grupo de vagones sueltos (tarea 62.3): sin locomotora y sin ser
## de un automático (el coche de regalo, los vagones que dejó el jugador). Para los carteles que
## frenan al tren del jugador no ocupan la vía: así puede entrar a engancharlos. Los automáticos
## los siguen contando.
static func is_loose(vehicle: Vehicle) -> bool:
	if vehicle == null or vehicle.automatic:
		return false
	for part: Vehicle in vehicle.get_train():
		if not (part.data is WagonData):
			return false
	return true


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


# --- Trabados, perdidos y guardados (tarea 62.4, D120) ---

# Lejos del jugador: cuenta el tiempo que no avanza por un vehículo adelante y, pasado
# STUCK_SECONDS, vuelve a la estación de donde salió.
func _check_stuck_far(run: AutoTrainRun, delta: float) -> void:
	if run.waiting != "esperando vía libre":
		_stuck.erase(run.id)
		return
	var time: float = float(_stuck.get(run.id, 0.0)) + delta
	if time >= STUCK_SECONDS:
		_try_turn_back(run)
		time = 0.0
	_stuck[run.id] = time


# Vuelve a la estación de donde salió el pedazo de viaje (AutoTrainRun.turn_back) si lo que tiene
# atrás está libre: ningún tramo de vía doble (iría de contramano), nada reservado por otro y
# ningún vehículo detrás de su cola. Reserva el camino de vuelta y suelta el resto. Devuelve si
# pudo.
func _try_turn_back(run: AutoTrainRun) -> bool:
	var network: RailNetwork = _network()
	if network == null or not run.is_moving() or run.leg.is_empty() or _maneuvers.has(run.id):
		return false
	var head_index: int = run.locate(run.position + run.lead_offset())[0]
	if head_index < 0:
		return false
	var sections: Array[StringName] = []
	for index: int in head_index + 1:
		var piece: StringName = run.leg[index]
		if AutoTrainRun.is_station_piece(piece):
			var path: Path3D = _station_track_path(network, piece)
			if path == null or network.is_track_reserved(path):
				return false
		elif network.is_double(piece):
			return false
		var section: StringName = AutoTrainRun.piece_section(piece)
		var holder: int = get_token_holder(section)
		if holder != 0 and holder != run.id:
			return false
		sections.append(section)
	# Nada detrás de la cola (en el camino de vuelta).
	var tail: float = run.position - run.trail_offset()
	var own: Array[Vehicle] = get_train(run)
	for node: Node in get_tree().get_nodes_in_group(Vehicle.GROUP):
		var vehicle := node as Vehicle
		if vehicle == null or vehicle.data == null or own.has(vehicle) or vehicle.is_queued_for_deletion():
			continue
		var at: float = _leg_coordinate(run, vehicle)
		if not is_nan(at) and at - vehicle.data.length * 0.5 < tail:
			return false
	var origin: StringName = run.leg_from()
	_release_tokens(run)
	for section: StringName in sections:
		_tokens[section] = run.id
	run.turn_back()
	_blocked.erase(run.id)
	_stuck.erase(run.id)
	var train: Array[Vehicle] = get_train(run)
	if not train.is_empty():
		train[0].destination = run.leg_to()
		train[0].forget_route_ahead()
	_update_signals()
	print("AutoTrains: el %s estaba trabado y vuelve a %s." % [run.display_name, _station_name(origin)])
	return true


# Un tren de verdad cuya locomotora quedó fuera de su recorrido (no debería pasar): avisa y vuelve
# a ser un número en su recorrido, donde estaba la última vez; reaparece ahí si hay lugar.
func _rescue(run: AutoTrainRun, loco: Vehicle) -> void:
	var path := loco.get_parent() as Path3D
	var track: TrackSegment = RailNetwork.track_of(path)
	var where: String = "?"
	if track != null and track.segment_id != &"":
		where = String(track.segment_id)
	elif path != null:
		where = String(path.name)
	push_warning("AutoTrains: el %s se salió de su recorrido (está en %s; su viaje: %s). Vuelve a su recorrido." % [run.display_name, where, ", ".join(PackedStringArray(run.leg))])
	_lost.erase(run.id)
	_blocked.erase(run.id)
	_despawn(run)


# Con park_hidden: guarda al tren parado en su punta o lo vuelve a sacar antes de su salida.
# Devuelve true si queda guardado (no sale ni reserva todavía).
func _update_parking(run: AutoTrainRun, now: float) -> bool:
	if run.hidden:
		if now >= run.due - SHOW_BEFORE_HOURS:
			_try_show(run)
		return run.hidden
	if _can_hide(run, now):
		_hide(run)
		return true
	return false


func _can_hide(run: AutoTrainRun, now: float) -> bool:
	if run.is_moving() or run.dwelling or _maneuvers.has(run.id) or _requested.has(run.id) or _has_trip_reserved(run):
		return false
	if run.arrived_at < 0.0 or now < run.arrived_at + HIDE_AFTER_HOURS or run.due - now <= SHOW_BEFORE_HOURS:
		return false
	return not _player_aboard(get_train(run))


func _hide(run: AutoTrainRun) -> void:
	if run.needs_turn:
		# Guardado da la vuelta solo.
		_finish_turn(run, _turn_is_plain(run))
	_despawn(run)
	_release_tokens(run)
	run.leg.clear()
	run.leg_lengths.clear()
	run.position = 0.0
	run.hidden = true
	run.waiting = _hidden_text(run)
	_blocked.erase(run.id)
	_update_signals()


# Vuelve a la estación donde se guardó, en una vía libre (si no hay, sigue guardado y espera).
func _try_show(run: AutoTrainRun) -> void:
	var network: RailNetwork = _network()
	if network == null:
		return
	var from: StringName = run.leg_from()
	var route: Array[StringName] = network.find_route(from, run.leg_to(), true)
	if route.is_empty():
		run.waiting = "vía cortada"
		return
	var leaving: Array = _station_options(network, route[0], from, false)
	if not leaving.is_empty():
		var start: Array = _pick_track(run, leaving, true, _track_roles(run))
		if start.is_empty():
			run.waiting = "esperando vía libre en %s" % _station_name(from)
			return
		var station_track: StationTrack = start[0]
		var pieces: Array[StringName] = [AutoTrainRun.station_piece(from, station_track.get_track_path().name, start[1])]
		var lengths: Array[float] = [station_track.get_length()]
		run.leg = pieces
		run.leg_lengths = lengths
	run.hidden = false
	if not _plan_parked_leg(run):
		run.leg.clear()
		run.leg_lengths.clear()
		run.hidden = true
		return
	run.waiting = ""
	_update_signals()


func _hidden_text(run: AutoTrainRun) -> String:
	return "guardado hasta las %s" % AutoTrainRun.hour_text(run.due - SHOW_BEFORE_HOURS)


# --- Carteles de señal (D114, D117) ---

# Los carteles de línea de un tramo: uno en cada punta de cada vía, unos metros adentro, antes del
# cambio de la estación. En la vía simple la cara de adelante (hacia la estación) es la salida a la
# línea y la de atrás, la entrada a la estación. En la vía doble, la vía que sale de una estación
# lleva la salida y la que llega, la entrada; la cara de contramano queda en rojo.
func _ensure_signals(network: RailNetwork, segment_id: StringName) -> void:
	if not signals_enabled:
		return
	var double: bool = network.is_double(segment_id)
	for track: TrackSegment in network.get_tracks(segment_id):
		var path: Path3D = track.get_track_path()
		if path == null or path.curve == null or not path.is_inside_tree() or path.curve.get_baked_length() < SIGNAL_OFFSET * 2.0:
			continue
		for station_id: StringName in [track.from_station, track.to_station]:
			var leaving: bool = station_id == track.from_station
			var key: String = _line_key(segment_id, station_id, double and not leaving)
			if _signals.has(key) and is_instance_valid(_signals[key]):
				continue
			var length: float = path.curve.get_baked_length()
			var at: float = SIGNAL_OFFSET if leaving else length - SIGNAL_OFFSET
			var point: Vector3 = path.global_transform * path.curve.sample_baked(at)
			var ahead: Vector3 = path.global_transform * path.curve.sample_baked(minf(at + 1.0, length))
			var behind_point: Vector3 = path.global_transform * path.curve.sample_baked(maxf(at - 1.0, 0.0))
			var tangent: Vector3 = (ahead - behind_point).normalized()
			# Hacia la línea, saliendo de esa estación.
			var into: Vector3 = tangent if leaving else -tangent
			# A la derecha del tren que lo lee: el que sale o, en la vía doble que llega, el que entra.
			var reader: Vector3 = -into if double and not leaving else into
			var side: Vector3 = reader.cross(Vector3.UP).normalized()
			var signal_node := RailSignal.new()
			signal_node.name = "Cartel_%s_%s%s" % [segment_id, station_id, "_llegada" if double and not leaving else ""]
			signal_node.kind = RailSignal.Kind.LINE
			signal_node.segment_id = segment_id
			signal_node.station_id = station_id
			add_child(signal_node)
			signal_node.global_position = point + side * SIGNAL_SIDE
			# La cara de adelante la leen los que salen de la estación: mira hacia la estación.
			signal_node.face_towards(-into)
			_signals[key] = signal_node
	if double:
		_ensure_block_signals(network, segment_id)


static func _line_key(segment_id: StringName, station_id: StringName, arriving: bool) -> String:
	return "%s|%s%s" % [segment_id, station_id, ARRIVING_SUFFIX if arriving else ""]


# Los carteles de las vías de estación (D117): en cada punta de cada vía que da a un cambio, del
# otro lado de la división (pasando el punto donde se separa de las otras vías). Saca los de las
# vías que ya no están.
func _ensure_track_signals(network: RailNetwork) -> void:
	var wanted: Dictionary = {}
	for station_id: StringName in network.get_station_ids():
		if not network.has_station_tracks(station_id):
			continue
		for station_track: StationTrack in network.get_station_tracks(station_id):
			var path: Path3D = station_track.get_track_path()
			if not station_track.enabled or station_track.role == StationTrack.Role.HEADSHUNT or path == null \
					or path.curve == null or not path.is_inside_tree():
				continue
			for at_end: bool in [false, true]:
				var exit: Array = network.get_exit(path, at_end)
				if exit.is_empty() or network.find_switch(exit[0], exit[1]) == null:
					continue
				var key: String = "%s|%s" % [_section_of(station_track), "B" if at_end else "A"]
				wanted[key] = true
				if _track_signals.has(key) and is_instance_valid(_track_signals[key]):
					continue
				_track_signals[key] = _make_track_signal(network, station_track, at_end, exit)
	for key: String in _track_signals.keys():
		if wanted.has(key):
			continue
		var old_signal: RailSignal = _track_signals[key] if is_instance_valid(_track_signals[key]) else null
		if old_signal != null:
			if is_instance_valid(old_signal.station_track) and old_signal.station_track.get_track_path() != null:
				network.set_exit_stop(old_signal.station_track.get_track_path(), old_signal.at_end, -1.0)
			old_signal.queue_free()
		_track_signals.erase(key)


func _make_track_signal(network: RailNetwork, station_track: StationTrack, at_end: bool, exit: Array) -> RailSignal:
	var path: Path3D = station_track.get_track_path()
	var length: float = path.curve.get_baked_length()
	# Todas las vías de esa punta ponen su cartel a la misma distancia: donde ya se separó la que
	# más tarda en separarse.
	var distance: float = 0.0
	var track_switch: TrackSwitch = network.find_switch(exit[0], exit[1])
	for index: int in track_switch.option_count():
		var option_path: Path3D = track_switch.get_option_path(index)
		if option_path != null and option_path.curve != null and RailNetwork.track_of(option_path) is StationTrack:
			distance = maxf(distance, _diverge_distance(option_path, bool(track_switch.options[index][1])))
	distance = TRACK_SIGNAL_DEFAULT if distance <= 0.0 else distance + TRACK_SIGNAL_MARGIN
	var at: float = _offset_at_depth(path, at_end, distance)
	var point: Vector3 = path.global_transform * path.curve.sample_baked(at)
	var ahead: Vector3 = path.global_transform * path.curve.sample_baked(minf(at + 1.0, length))
	var behind_point: Vector3 = path.global_transform * path.curve.sample_baked(maxf(at - 1.0, 0.0))
	var tangent: Vector3 = (ahead - behind_point).normalized()
	# Hacia la punta: a la derecha del tren que sale por ella.
	var toward_end: Vector3 = tangent if at_end else -tangent
	var side: Vector3 = toward_end.cross(Vector3.UP).normalized()
	var signal_node := RailSignal.new()
	signal_node.name = "Cartel_%s_%s_%s" % [station_track.get_station_id(), path.name, "B" if at_end else "A"]
	signal_node.kind = RailSignal.Kind.TRACK
	signal_node.station_track = station_track
	signal_node.at_end = at_end
	signal_node.station_id = station_track.get_station_id()
	signal_node.track_offset = at
	add_child(signal_node)
	signal_node.global_position = point + side * TRACK_SIGNAL_SIDE
	# La cara de adelante la lee el tren de esta vía que va hacia la punta.
	signal_node.face_towards(-toward_end)
	if network.levers_enabled and not station_track.is_main():
		var lever := TrackLever.new()
		lever.name = "Palanca"
		lever.network = network
		lever.station_track = station_track
		lever.at_end = at_end
		lever.signal_node = signal_node
		signal_node.add_child(lever)
		# El cartel mira hacia adentro de la estación (+Z): el cambio queda hacia -Z.
		lever.position = Vector3(0.0, 0.0, -TRACK_LEVER_AHEAD)
	return signal_node


# A qué profundidad desde la punta (`at_end`: el final de la curva), medida a lo largo de la recta
# por donde llega, la vía ya se apartó TRACK_FOULING_LATERAL de esa recta; 0 si no se aparta (la
# principal). Se mide en la recta y no sobre la curva para que todas queden a la misma altura.
static func _diverge_distance(path: Path3D, at_end: bool) -> float:
	var curve: Curve3D = path.curve
	var length: float = curve.get_baked_length()
	if length <= 1.0:
		return 0.0
	var tip: Vector3 = curve.sample_baked(length if at_end else 0.0)
	var inner: Vector3 = curve.sample_baked(length - 0.5 if at_end else 0.5)
	var into: Vector3 = (inner - tip).normalized()
	var reach: float = 1.0
	while reach < length * 0.5:
		var offset: Vector3 = curve.sample_baked(length - reach if at_end else reach) - tip
		if (offset - into * offset.dot(into)).length() >= TRACK_FOULING_LATERAL:
			return offset.dot(into)
		reach += 1.0
	return 0.0


# El avance de la curva cuyo punto está a `depth` metros de la punta, medidos a lo largo de la recta
# por donde llega (sin pasar de casi la mitad de la vía).
static func _offset_at_depth(path: Path3D, at_end: bool, depth: float) -> float:
	var curve: Curve3D = path.curve
	var length: float = curve.get_baked_length()
	var tip: Vector3 = curve.sample_baked(length if at_end else 0.0)
	var inner: Vector3 = curve.sample_baked(length - 0.5 if at_end else 0.5)
	var into: Vector3 = (inner - tip).normalized()
	var reach: float = 0.0
	while reach < length * 0.45:
		var offset: Vector3 = curve.sample_baked(length - reach if at_end else reach) - tip
		if offset.dot(into) >= depth:
			break
		reach += 0.25
	reach = minf(reach, length * 0.45)
	return length - reach if at_end else reach


## El cartel de una vía de estación en su punta B (`at_end`) o A, o null.
func get_track_signal(station_track: StationTrack, at_end: bool) -> RailSignal:
	if station_track == null:
		return null
	var found: Variant = _track_signals.get("%s|%s" % [_section_of(station_track), "B" if at_end else "A"])
	return found if is_instance_valid(found) else null


func _update_signals() -> void:
	var network: RailNetwork = _network()
	if network == null:
		return
	if signals_enabled:
		for segment_id: StringName in network.get_segment_ids():
			_ensure_signals(network, segment_id)
		_ensure_track_signals(network)
	for key: String in _signals:
		var signal_node: RailSignal = _signals[key] if is_instance_valid(_signals[key]) else null
		if signal_node == null:
			continue
		var entry: RailSignal.Aspect = _entry_aspect(network, signal_node.segment_id, signal_node.station_id)
		var double: bool = network.is_double(signal_node.segment_id)
		if double == key.ends_with(ARRIVING_SUFFIX):
			# Con el cambio trabado por una palanca, el jugador pidió entrar ahí (a una vía ocupada, para
			# enganchar): entra con precaución aunque esté en rojo.
			var asked: TrackSwitch = _entry_switch(network, signal_node.segment_id, signal_node.station_id)
			_set_entry_stop(network, signal_node.segment_id, signal_node.station_id, entry == RailSignal.Aspect.RED and not (asked != null and asked.is_locked()))
		if key.ends_with(ARRIVING_SUFFIX):
			# Vía doble, la que llega: adelante es contramano.
			signal_node.set_aspects(RailSignal.Aspect.RED, entry)
			continue
		var state: Array = _signal_state(network, signal_node.segment_id, signal_node.station_id)
		var back: RailSignal.Aspect = RailSignal.Aspect.RED if double else entry
		var front: RailSignal.Aspect = _clear_aspect(network, signal_node.segment_id, signal_node.station_id) if state[0] else RailSignal.Aspect.RED
		signal_node.set_aspects(front, back)
		network.set_entry_closed(signal_node.segment_id, signal_node.station_id, state[1])
	for segment_id: StringName in network.get_segment_ids():
		if network.is_double(segment_id):
			for way: TrackSegment in network.get_tracks(segment_id):
				_update_way(network, way)
	for key: String in _track_signals:
		var track_signal: RailSignal = _track_signals[key] if is_instance_valid(_track_signals[key]) else null
		if track_signal == null or not is_instance_valid(track_signal.station_track):
			continue
		track_signal.set_aspects(_track_exit_aspect(network, track_signal.station_track, track_signal.at_end), _track_entry_aspect(track_signal.station_track, track_signal.at_end))
		var track_path: Path3D = track_signal.station_track.get_track_path()
		if track_path != null:
			network.set_exit_stop(track_path, track_signal.at_end, -1.0 if track_signal.clear else track_signal.track_offset)


# La entrada a `station` desde el tramo (la cara de atrás del cartel de línea): verde si la vía a
# la que lleva el cambio está libre. Un automático que viene hacia la estación ya tiene su vía
# reservada: verde para él. Sin vías de estación, rojo si hay un automático parado en esa punta.
func _entry_aspect(network: RailNetwork, segment_id: StringName, station: StringName) -> RailSignal.Aspect:
	match _arriving_auto(network, segment_id, station):
		ARRIVING_BEFORE:
			return RailSignal.Aspect.GREEN
		ARRIVING_PAST:
			# Ya pasó el cartel: detrás de él vuelve al rojo (tarea 61e.3).
			return RailSignal.Aspect.RED
	if not network.has_station_tracks(station):
		return RailSignal.Aspect.RED if _parked_run_at(station, segment_id, null) != null else RailSignal.Aspect.GREEN
	var target: Path3D = _entry_target(network, segment_id, station)
	if target == null:
		return RailSignal.Aspect.RED
	var section: StringName = _section_of_path(network, target)
	if section != &"" and get_token_holder(section) != 0:
		return RailSignal.Aspect.RED
	return RailSignal.Aspect.RED if _path_has_foreign(target, [], true) else RailSignal.Aspect.GREEN


# El cambio que encuentra un tren que llega a `station` por el tramo, o null.
func _entry_switch(network: RailNetwork, segment_id: StringName, station: StringName) -> TrackSwitch:
	for track: TrackSegment in network.get_tracks(segment_id):
		if track.to_station != station and not (track.from_station == station and not network.is_double(segment_id)):
			continue
		var path: Path3D = track.get_track_path()
		if path != null:
			return network.find_switch(path, track.to_station == station)
	return null


# La vía de estación a la que lleva el cambio para un tren que llega por el tramo, o null.
func _entry_target(network: RailNetwork, segment_id: StringName, station: StringName) -> Path3D:
	for track: TrackSegment in network.get_tracks(segment_id):
		if track.to_station != station and not (track.from_station == station and not network.is_double(segment_id)):
			continue
		var path: Path3D = track.get_track_path()
		if path == null:
			continue
		var at_end: bool = track.to_station == station
		var track_switch: TrackSwitch = network.find_switch(path, at_end)
		if track_switch != null:
			return track_switch.get_option_path(track_switch.state)
		var links: Array = network.get_links(path, at_end)
		return (links[0] as Array)[0] as Path3D if links.size() == 1 else null
	return null


# Dónde frena el tren del jugador ante la entrada en rojo a `station` desde el tramo (tarea 61e.3):
# en el cartel de línea de esa punta, yendo hacia la estación (en la vía doble, por la vía que
# llega). Los automáticos no lo miran: entran con su vía reservada.
func _set_entry_stop(network: RailNetwork, segment_id: StringName, station: StringName, red: bool) -> void:
	for track: TrackSegment in network.get_tracks(segment_id):
		var path: Path3D = track.get_track_path()
		if path == null or path.curve == null:
			continue
		var length: float = path.curve.get_baked_length()
		if track.to_station == station:
			network.set_exit_stop(path, true, length - SIGNAL_OFFSET if red else -1.0)
		elif track.from_station == station and not network.is_double(segment_id):
			network.set_exit_stop(path, false, SIGNAL_OFFSET if red else -1.0)


# Un automático que va por el tramo hacia `station` y todavía no llegó a la punta: ARRIVING_BEFORE si
# su punta todavía no pasó el cartel de entrada, ARRIVING_PAST si ya lo pasó; si no, ARRIVING_NONE.
func _arriving_auto(network: RailNetwork, segment_id: StringName, station: StringName) -> int:
	var found: int = ARRIVING_NONE
	for run: AutoTrainRun in _runs:
		if not run.is_moving():
			continue
		for index: int in run.leg.size():
			if run.leg[index] != segment_id or run.segment_entry(index, network.other_end) == station:
				continue
			var end: float = run.segment_start(index) + run.leg_lengths[index]
			if run.position >= end:
				continue
			if run.position + run.lead_offset() > end - SIGNAL_OFFSET:
				return ARRIVING_PAST
			found = ARRIVING_BEFORE
	return found


# La salida de una vía de estación por una punta (la cara de adelante de su cartel): verde si se
# pidió el paso con su palanca (el cambio puesto y trabado para esta vía; con spring_exit no hace
# falta; la principal no pide: le alcanza con que ninguna otra vía haya trabado el cambio) y lo que
# sigue está libre (el tramo, con la salida de su cartel de línea en verde y sin reserva de otro; la
# cola de maniobras, sin nadie). Hacia la línea, si no es la principal, además la principal no
# tiene que necesitar esa punta (D117: la principal manda). Un automático que sale por ahí con su
# viaje reservado la tiene en verde; si la vía la reservó otro automático, rojo.
func _track_exit_aspect(network: RailNetwork, station_track: StationTrack, at_end: bool) -> RailSignal.Aspect:
	var path: Path3D = station_track.get_track_path()
	var holder: AutoTrainRun = get_run(get_token_holder(_section_of(station_track)))
	if holder != null and (holder.is_moving() or _has_trip_reserved(holder)) and _leaves_through(network, holder, path, at_end):
		return RailSignal.Aspect.GREEN
	if holder != null:
		# La tiene un automático (parado, llegando o maniobrando): no es una salida para otro.
		return RailSignal.Aspect.RED
	var exit: Array = network.get_exit(path, at_end)
	if exit.is_empty():
		return RailSignal.Aspect.RED
	var track_switch: TrackSwitch = network.find_switch(exit[0], exit[1])
	if track_switch != null and not station_track.trails_freely():
		if station_track.is_main():
			if track_switch.is_locked():
				return RailSignal.Aspect.RED
		elif not network.is_route_requested(path, at_end):
			return RailSignal.Aspect.RED
	var beyond: TrackSegment = RailNetwork.track_of(exit[0])
	if beyond != null and not (beyond is StationTrack):
		if not station_track.is_main() and track_switch != null and _main_busy(network, track_switch, _vehicles_on(path)):
			return RailSignal.Aspect.RED
		# Un tramo reservado es del automático que lo reservó (por su vía, ya contestado arriba).
		if not network.is_double(beyond.segment_id) and get_token_holder(beyond.segment_id) != 0:
			return RailSignal.Aspect.RED
		var state: Array = _signal_state(network, beyond.segment_id, station_track.get_station_id())
		return RailSignal.Aspect.GREEN if state[0] else RailSignal.Aspect.RED
	return RailSignal.Aspect.RED if _path_has_foreign(exit[0], _vehicles_on(path)) else RailSignal.Aspect.GREEN


# La entrada a una vía de estación por la punta `at_end` (la cara de atrás de su cartel). Si la
# tiene un automático que está llegando o pasando, verde para él. Reservada por una palanca madre
# (tarea 62.4, pedido de Batmi: la luz tiene que ser la de la vía elegida): verde en la punta por
# donde se reservó y rojo en la otra. Si no, verde solo si el cambio de esa punta está puesto
# para esta vía y la vía está libre (los vagones sueltos no cuentan); las demás vías de esa punta
# quedan en rojo.
func _track_entry_aspect(station_track: StationTrack, at_end: bool) -> RailSignal.Aspect:
	var path: Path3D = station_track.get_track_path()
	var network: RailNetwork = _network()
	if network != null and network.is_track_reserved(path):
		if not network.is_reserved(path, at_end):
			return RailSignal.Aspect.RED
		return RailSignal.Aspect.RED if _path_has_foreign(path, [], true) else RailSignal.Aspect.GREEN
	var holder_id: int = get_token_holder(_section_of(station_track))
	if holder_id != 0:
		var run: AutoTrainRun = get_run(holder_id)
		if run == null or not run.is_moving():
			return RailSignal.Aspect.RED
		return RailSignal.Aspect.RED if _path_has_foreign(path, get_train(run)) else RailSignal.Aspect.GREEN
	if network != null and (not _switches_lead_to(network, path, at_end) or _switch_taken(network, path, at_end)):
		return RailSignal.Aspect.RED
	return RailSignal.Aspect.RED if _path_has_foreign(path, [], true) else RailSignal.Aspect.GREEN


# Si otra vía del cambio de esa punta la tiene un automático que está pasando por el cambio
# (tarea 62.6, la falla que vio Batmi en la maderera y en la ciudad): el automático mueve el cambio
# recién al llegar, así que hasta entonces la principal mostraba verde junto con la anexa.
func _switch_taken(network: RailNetwork, path: Path3D, at_end: bool) -> bool:
	var exit: Array = network.get_exit(path, at_end)
	var track_switch: TrackSwitch = network.find_switch(exit[0], exit[1]) if not exit.is_empty() else null
	if track_switch == null:
		return false
	for index: int in track_switch.option_count():
		var other: Path3D = track_switch.get_option_path(index)
		var other_track := RailNetwork.track_of(other) as StationTrack
		if other == path or other_track == null:
			continue
		var holder: AutoTrainRun = get_run(get_token_holder(_section_of(other_track)))
		if holder != null and holder.is_moving() and _uses_end(network, holder, other, bool(track_switch.options[index][1])):
			return true
	return false


# Si el viaje del automático entra a la vía `path` o sale de ella por esa punta.
func _uses_end(network: RailNetwork, run: AutoTrainRun, path: Path3D, at_end: bool) -> bool:
	if _leaves_through(network, run, path, at_end):
		return true
	for index: int in range(1, run.leg.size()):
		var piece: StringName = run.leg[index]
		# Entra por el final de la curva yendo hacia el principio (y al revés).
		if AutoTrainRun.is_station_piece(piece) and _station_track_path(network, piece) == path and AutoTrainRun.piece_forward(piece) != at_end:
			return true
	return false


# Si todos los cambios entre la punta `at_end` de `path` y la línea están puestos hacia esta vía
# (tarea 62.6): en las estaciones con varias vías el cambio de la vía puede estar después de otro
# (línea → cambio 1 → cambio 2 → anexa), y con el primero hacia la principal la anexa no recibe
# a nadie aunque el segundo apunte a ella. Sigue hasta llegar a un tramo o a una punta sin cambio.
func _switches_lead_to(network: RailNetwork, path: Path3D, at_end: bool) -> bool:
	var current: Path3D = path
	var current_end: bool = at_end
	for _step: int in MAX_SWITCH_CHAIN:
		var exit: Array = network.get_exit(current, current_end)
		if exit.is_empty():
			return true
		var beyond: Path3D = exit[0]
		var track_switch: TrackSwitch = network.find_switch(beyond, exit[1])
		if track_switch == null:
			return true
		if track_switch.get_option_path(track_switch.state) != current:
			return false
		var track: TrackSegment = RailNetwork.track_of(beyond)
		if track != null and not (track is StationTrack):
			return true
		# Sigue por la otra punta de lo que hay después del cambio.
		current = beyond
		current_end = not bool(exit[1])
	return true


# Si la principal necesita la punta del cambio `track_switch` (D117, cada punta de la estación se
# maneja sola): un automático que va a salir de la principal por ahí, o cualquier tren que anda por
# la principal hacia esa punta. No cuentan los trenes de `own` (el que quiere salir).
func _main_busy(network: RailNetwork, track_switch: TrackSwitch, own: Array[Vehicle]) -> bool:
	var own_heads: Array[Vehicle] = []
	for vehicle: Vehicle in own:
		own_heads.append(vehicle.get_head())
	for index: int in track_switch.option_count():
		var main_track := track_switch.get_option_track(index) as StationTrack
		if main_track == null or not main_track.is_main():
			continue
		var path: Path3D = track_switch.get_option_path(index)
		# La punta de la principal que da a este cambio.
		var main_end: bool = bool(track_switch.options[index][1])
		var holder: AutoTrainRun = get_run(get_token_holder(_section_of(main_track)))
		if holder != null and (holder.is_moving() or _has_trip_reserved(holder)) and _leaves_through(network, holder, path, main_end):
			return true
		for vehicle: Vehicle in _vehicles_on(path):
			if own_heads.has(vehicle.get_head()):
				continue
			# Avance por segundo sobre la curva: positivo, hacia su final.
			var along: float = vehicle.get_head().speed * float(vehicle.get_curve_direction())
			if (along if main_end else -along) > MAIN_BUSY_SPEED:
				return true
	return false


# Si un tren parado ya reservó su próximo viaje: tiene algo más que la vía donde está.
func _has_trip_reserved(run: AutoTrainRun) -> bool:
	if _maneuvers.has(run.id):
		# Lo que reservó la maniobra no es su viaje.
		return false
	for index: int in range(1, run.leg.size()):
		var section: StringName = AutoTrainRun.piece_section(run.leg[index])
		if section != &"" and get_token_holder(section) == run.id:
			return true
	return false


# Si el viaje sale de la curva `path` por su final (`at_end`) o su principio hacia otro pedazo.
func _leaves_through(network: RailNetwork, run: AutoTrainRun, path: Path3D, at_end: bool) -> bool:
	for index: int in run.leg.size() - 1:
		var spot: Array = _piece_at(network, run, index)
		if not spot.is_empty() and spot[0] == path and bool(spot[1]) == at_end:
			return true
	return false


static func _vehicles_on(path: Path3D) -> Array[Vehicle]:
	var list: Array[Vehicle] = []
	for child: Node in path.get_children():
		var vehicle := child as Vehicle
		if vehicle != null:
			list.append(vehicle)
	return list


# El semáforo de entrada al tramo desde `station` (D114): [verde, cierra la entrada al tren del
# jugador]. Mira por dónde va cada tren (lo que detectaría un sensor a la entrada y a la salida de
# cada tramo):
# - Vía simple reservada por un automático: verde del lado por donde él entra (mientras no
#   entró) y rojo del otro; el tren del jugador no entra por ninguno de los dos.
# - Un automático dentro (de verdad o lejos, como un número) o parado en una punta (estación sin
#   vías propias): rojo y cerrado.
# - Un vehículo cualquiera dentro (el del jugador, uno suelto): rojo, pero solo avisa.
# - Vía doble (tarea 61e.3): rojo si hay algo en el primer bloque de la vía de su sentido, sin
#   cerrar (el tren del jugador frena en el cartel); los bloques que siguen tienen su cartel.
func _signal_state(network: RailNetwork, segment_id: StringName, station: StringName) -> Array:
	var double: bool = network.is_double(segment_id)
	if not double and _auto_inside(segment_id):
		return [false, true]
	for track: TrackSegment in network.get_tracks(segment_id):
		for end_station: StringName in [track.from_station, track.to_station]:
			if _parked_run_at(end_station, segment_id, null) != null:
				return [false, true]
	if double:
		# Vía doble (tarea 61e.3): la salida mira el primer bloque de la vía de su sentido; los que
		# siguen tienen su cartel, así que el tren del jugador puede ir atrás de un automático.
		var way: TrackSegment = network.track_leaving(segment_id, station)
		return [way != null and not _block_busy(network, way, 0), false]
	var holder: AutoTrainRun = get_run(get_token_holder(segment_id))
	if holder != null:
		return [_entry_of(network, holder, segment_id) == station and not _has_foreign_vehicle(network, segment_id, holder), true]
	if _has_foreign_vehicle(network, segment_id, null, true):
		return [false, false]
	return [true, false]


# Por qué estación entra el viaje del tren al tramo, o &"".
func _entry_of(network: RailNetwork, run: AutoTrainRun, segment_id: StringName) -> StringName:
	for index: int in run.leg.size():
		if run.leg[index] == segment_id:
			return run.segment_entry(index, network.other_end)
	return &""


# Si algún automático en viaje ocupa el tramo: de verdad, con un vehículo en la curva, o lejos,
# por su posición en el viaje.
func _auto_inside(segment_id: StringName) -> bool:
	for run: AutoTrainRun in _runs:
		if not run.is_moving():
			continue
		var low: float = run.position - run.trail_offset()
		var high: float = run.position + run.lead_offset()
		for index: int in run.leg.size():
			if run.leg[index] != segment_id:
				continue
			var start: float = run.segment_start(index)
			if high > start and low < start + run.leg_lengths[index]:
				return true
	return false


# --- Bloques de la vía doble (tarea 61e.3) ---

## Dónde empieza cada bloque de una vía de vía doble de largo `length` (avances de su curva): el
## primero en el cartel de salida (SIGNAL_OFFSET) y los otros parejos, cada `block` más o menos,
## sin contar la salida y la llegada. El último llega hasta el final de la vía.
static func block_starts(length: float, block: float) -> PackedFloat64Array:
	var starts := PackedFloat64Array([SIGNAL_OFFSET])
	var usable: float = length - SIGNAL_OFFSET * 2.0
	if usable <= 0.0 or block <= 0.0:
		return starts
	var count: int = maxi(1, roundi(usable / block))
	for index: int in range(1, count):
		starts.append(SIGNAL_OFFSET + usable * float(index) / float(count))
	return starts


## El cartel de bloque `index` (1 es el primero después de la salida) de la vía que sale de
## `station_id` en el tramo, o null.
func get_block_signal(segment_id: StringName, station_id: StringName, index: int) -> RailSignal:
	var found: Variant = _block_signals.get("%s|%s|%d" % [segment_id, station_id, index])
	return found if is_instance_valid(found) else null


static func _block_key(way: TrackSegment, index: int) -> String:
	return "%s|%s|%d" % [way.segment_id, way.from_station, index]


# Los carteles de bloque de las dos vías de un tramo doble, al principio de cada bloque menos el
# primero (ese lo marca el cartel de salida).
func _ensure_block_signals(network: RailNetwork, segment_id: StringName) -> void:
	for way: TrackSegment in network.get_tracks(segment_id):
		var path: Path3D = way.get_track_path()
		if path == null or path.curve == null or not path.is_inside_tree():
			continue
		var starts: PackedFloat64Array = block_starts(path.curve.get_baked_length(), block_length)
		for index: int in range(1, starts.size()):
			var key: String = _block_key(way, index)
			if _block_signals.has(key) and is_instance_valid(_block_signals[key]):
				continue
			_block_signals[key] = _make_block_signal(network, way, index, starts[index])


func _make_block_signal(network: RailNetwork, way: TrackSegment, index: int, at: float) -> RailSignal:
	var path: Path3D = way.get_track_path()
	var length: float = path.curve.get_baked_length()
	var point: Vector3 = path.global_transform * path.curve.sample_baked(at)
	var ahead: Vector3 = path.global_transform * path.curve.sample_baked(minf(at + 1.0, length))
	var behind_point: Vector3 = path.global_transform * path.curve.sample_baked(maxf(at - 1.0, 0.0))
	var tangent: Vector3 = (ahead - behind_point).normalized()
	# A la derecha del tren que lo lee; si la otra vía queda de ese lado, en el medio de las dos.
	var side: Vector3 = tangent.cross(Vector3.UP).normalized()
	var gap: float = SIGNAL_SIDE
	for other: TrackSegment in network.get_tracks(way.segment_id):
		var other_path: Path3D = other.get_track_path()
		if other == way or other_path == null or other_path.curve == null:
			continue
		var near: Vector3 = other_path.global_transform * other_path.curve.get_closest_point(other_path.global_transform.affine_inverse() * point)
		var across: float = (near - point).dot(side)
		if across > 0.0:
			gap = minf(gap, across * 0.5)
	var signal_node := RailSignal.new()
	signal_node.name = "Bloque_%s_%s_%d" % [way.segment_id, way.from_station, index]
	signal_node.kind = RailSignal.Kind.BLOCK
	signal_node.segment_id = way.segment_id
	signal_node.station_id = way.from_station
	signal_node.block_index = index
	signal_node.track_offset = at
	add_child(signal_node)
	signal_node.global_position = point + side * gap
	# La cara de adelante la leen los que vienen por la vía en su sentido.
	signal_node.face_towards(-tangent)
	return signal_node


# Si entre `low` y `high` (avances de su curva) de la vía `way` hay un vehículo o un automático
# lejos del jugador. Sin contar el tren de `except`.
func _way_busy(network: RailNetwork, way: TrackSegment, low: float, high: float, except: AutoTrainRun = null) -> bool:
	var own: Array[Vehicle] = []
	if except != null:
		own = get_train(except)
	var path: Path3D = way.get_track_path()
	if path != null:
		for child: Node in path.get_children():
			var vehicle := child as Vehicle
			if vehicle == null or vehicle.data == null or vehicle.is_queued_for_deletion() or own.has(vehicle):
				continue
			var half: float = vehicle.data.length * 0.5
			if vehicle.progress + half > low and vehicle.progress - half < high:
				return true
	var length: float = way.get_length()
	for run: AutoTrainRun in _runs:
		if run == except or not run.is_moving() or is_spawned(run):
			continue
		for index: int in run.leg.size():
			if run.leg[index] != way.segment_id or network.track_leaving(way.segment_id, run.segment_entry(index, network.other_end)) != way:
				continue
			var scale: float = run.leg_lengths[index] / length if length > 0.0 else 1.0
			var start: float = run.segment_start(index)
			var tail: float = (run.position - run.trail_offset() - start) / scale
			var head: float = (run.position + run.lead_offset() - start) / scale
			if head > low and tail < high:
				return true
	return false


# Si el bloque `index` de la vía está ocupado. Con `from_start`, el primero se cuenta desde el
# principio de la vía y no desde el cartel de salida (para salir hace falta toda la punta libre).
func _block_busy(network: RailNetwork, way: TrackSegment, index: int, except: AutoTrainRun = null, from_start: bool = false) -> bool:
	var length: float = way.get_length()
	var starts: PackedFloat64Array = block_starts(length, block_length)
	if index < 0 or index >= starts.size():
		return false
	var low: float = 0.0 if from_start and index == 0 else starts[index]
	var high: float = starts[index + 1] if index + 1 < starts.size() else length
	return _way_busy(network, way, low, high, except)


# El cartel del bloque `index` de la vía, sabiendo qué bloques están ocupados: rojo si el suyo;
# amarillo si el que sigue (o, en el último, la entrada a la estación de llegada); si no, verde.
func _block_aspect(network: RailNetwork, way: TrackSegment, busy: Array[bool], index: int) -> RailSignal.Aspect:
	if busy[index]:
		return RailSignal.Aspect.RED
	var next_red: bool = busy[index + 1] if index + 1 < busy.size() \
			else _entry_aspect(network, way.segment_id, way.to_station) == RailSignal.Aspect.RED
	return RailSignal.Aspect.YELLOW if next_red else RailSignal.Aspect.GREEN


func _busy_blocks(network: RailNetwork, way: TrackSegment) -> Array[bool]:
	var busy: Array[bool] = []
	for index: int in block_starts(way.get_length(), block_length).size():
		busy.append(_block_busy(network, way, index))
	return busy


# La salida a la línea que deja pasar: amarillo si el próximo cartel está en rojo (en la vía doble,
# el del segundo bloque o la entrada de la otra punta; en la simple, la entrada de la otra punta).
func _clear_aspect(network: RailNetwork, segment_id: StringName, station: StringName) -> RailSignal.Aspect:
	if network.is_double(segment_id):
		var way: TrackSegment = network.track_leaving(segment_id, station)
		if way == null:
			return RailSignal.Aspect.GREEN
		var busy: Array[bool] = _busy_blocks(network, way)
		busy[0] = false
		return _block_aspect(network, way, busy, 0)
	var far_red: bool = _entry_aspect(network, segment_id, network.other_end(segment_id, station)) == RailSignal.Aspect.RED
	return RailSignal.Aspect.YELLOW if far_red else RailSignal.Aspect.GREEN


# Prende los carteles de bloque de una vía y anota en la red dónde frenan los trenes: la salida a la
# línea si su bloque está ocupado y cada cartel de bloque en rojo.
func _update_way(network: RailNetwork, way: TrackSegment) -> void:
	var path: Path3D = way.get_track_path()
	if path == null or path.curve == null:
		return
	var starts: PackedFloat64Array = block_starts(path.curve.get_baked_length(), block_length)
	var busy: Array[bool] = _busy_blocks(network, way)
	var stops := PackedFloat64Array()
	# En la salida, solo si el rojo es por el primer bloque (si es por un automático parado en una
	# estación sin vías propias, el tren del jugador ya no entra: RailNetwork.set_entry_closed).
	if get_signal(way.segment_id, way.from_station) != null and busy[0]:
		stops.append(SIGNAL_OFFSET)
	for index: int in range(1, starts.size()):
		var block_signal: RailSignal = get_block_signal(way.segment_id, way.from_station, index)
		if block_signal == null:
			continue
		var aspect: RailSignal.Aspect = _block_aspect(network, way, busy, index)
		block_signal.set_aspects(aspect, RailSignal.Aspect.RED)
		if aspect == RailSignal.Aspect.RED:
			stops.append(starts[index])
	network.set_block_stops(path, true, stops)


# Hasta dónde puede llegar el centro de la locomotora por los carteles de bloque en rojo de la vía
# doble: SIGNAL_STOP_MARGIN antes del primero que tiene adelante; INF si no hay ninguno.
func _block_limit(network: RailNetwork, run: AutoTrainRun) -> float:
	var lead: float = run.lead_offset()
	var front_tip: float = run.position + lead
	for index: int in run.leg.size():
		var piece: StringName = run.leg[index]
		var start: float = run.segment_start(index)
		if AutoTrainRun.is_station_piece(piece) or start + run.leg_lengths[index] < front_tip - 0.05 or not network.is_double(piece):
			continue
		var way: TrackSegment = network.track_leaving(piece, run.segment_entry(index, network.other_end))
		var path: Path3D = way.get_track_path() if way != null else null
		if path == null:
			continue
		var length: float = way.get_length()
		var scale: float = run.leg_lengths[index] / length if length > 0.0 else 1.0
		var first: float = INF
		for stop: float in network.get_block_stops(path, true):
			var at: float = start + stop * scale
			if at >= front_tip - 0.05:
				first = minf(first, at)
		if first < INF:
			return first - Vehicle.SIGNAL_STOP_MARGIN - lead
	return INF


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
	return minf(limit, _block_limit(network, run))


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
			# Lejos es todo el tren: en la vuelta la locomotora se aleja de los vagones (cola, mesa).
			var far: bool = observer == null or _nearest_distance(observer as Vector3, train) > despawn_distance
			if far and not _player_aboard(train):
				_despawn(run)
		elif observer != null:
			var spot: Variant = _world_position(run)
			if spot != null and (observer as Vector3).distance_to(spot) <= spawn_distance:
				_spawn(run)


# Lo más cerca de `observer` que está un vehículo del tren (en la vuelta, los vagones esperan
# desenganchados mientras la locomotora se aleja).
static func _nearest_distance(observer: Vector3, train: Array[Vehicle]) -> float:
	var nearest: float = INF
	for vehicle: Vehicle in train:
		nearest = minf(nearest, observer.distance_to(vehicle.global_position))
	return nearest


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
	if network == null or run.hidden:
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
	if network == null or run.is_moving() or run.hidden:
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
		var scene_path: String = FLATCAR_SCENE
		match wagon_entry["kind"]:
			KIND_COACH:
				scene_path = COACH_SCENE
			KIND_BOXCAR:
				scene_path = BOXCAR_SCENE
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
	if run.is_trunk():
		# Locomotora de la cola (61d.2): mira para el otro lado y va adelante a la vuelta.
		var tail_loco := (load(LOCOMOTIVE_SCENE) as PackedScene).instantiate() as Vehicle
		tail_loco.name = "%s_Cola" % loco.name
		tail_loco.automatic = true
		tail_loco.reversed = loco.reversed
		distance += Vehicle.coupling_distance(previous, tail_loco.data.length)
		path.add_child(tail_loco)
		tail_loco.progress = progress - dir * distance
		if loco.get_tail().couple(tail_loco):
			tail_loco.model_yaw = PI
			train.append(tail_loco)
		else:
			push_warning("AutoTrains: no se pudo enganchar la locomotora de la cola del %s." % run.display_name)
			tail_loco.queue_free()
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
			wagon.set_display_load(_shown_units(run, entry, dir))


# Lo que se ve en un vagón. En una troncal (61d.3), lo que lleva en el pedazo que sale de la
# estación donde está (o de donde salió) hacia la siguiente del recorrido, en el sentido `dir`.
func _shown_units(run: AutoTrainRun, entry: Dictionary, dir: int) -> int:
	var entry_dir: int = int(entry["dir"])
	if not run.is_trunk() or not entry.has("loads"):
		return int(entry["units"]) if entry_dir == 0 or entry_dir == dir else 0
	var here: int = run.stops.find(run.leg_from())
	var next: int = here + (1 if run.is_outbound() else -1)
	if here < 0 or next < 0 or next >= run.stops.size():
		return 0
	var total: int = 0
	for part: Dictionary in entry["loads"]:
		var part_dir: int = int(part["dir"])
		if part_dir != 0 and part_dir != dir:
			continue
		var a: int = run.stops.find(part["from"])
		var b: int = run.stops.find(part["to"])
		if a >= 0 and b >= 0 and mini(a, b) <= mini(here, next) and maxi(here, next) <= maxi(a, b):
			total += int(part["units"])
	return total


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
	if is_nan(at):
		# La locomotora no está en ninguna vía de su viaje (tarea 62.4): se perdió.
		var lost: float = float(_lost.get(run.id, 0.0)) + delta
		_lost[run.id] = lost
		if lost >= LOST_SECONDS:
			_rescue(run, loco)
			return
		if lost >= LOST_BRAKE_SECONDS:
			loco.throttle = 0.0
			loco.brake = 1.0
			return
	else:
		_lost.erase(run.id)
		run.set_position(at)
	loco.destination = run.leg_to()
	var left: float = run.remaining()
	var moving: float = absf(loco.speed)
	if left <= 0.5 and moving < 0.2:
		run.finish_hop(now_hours())
		_on_arrived(run)
		return
	var stopping: float = moving * moving / (2.0 * loco.data.braking) + 0.3
	var network: RailNetwork = _network()
	# Un cartel de bloque en rojo adelante (tarea 61e.3): frena antes, como en la llegada.
	var held: bool = network != null and _block_limit(network, run) - run.position <= stopping
	if held:
		run.waiting = SIGNAL_WAIT
	elif run.waiting == SIGNAL_WAIT:
		run.waiting = ""
	if left <= stopping or held:
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
		if time >= STUCK_SECONDS:
			# Trabado hace rato (tarea 62.4): vuelve a la estación de donde salió, si puede.
			_try_turn_back(run)
			time = BLOCKED_TIME
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
	if run.is_trunk() or run.dwelling:
		# La troncal tiene una locomotora en cada punta (61d.2): no da la vuelta.
		return
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
	# El tramo al que se asoma del lado cercano se reserva recién cuando va a salir a él (D117: cada
	# punta de la estación se maneja sola; mientras tanto el otro lado queda libre).
	var near_is_line: bool = not (RailNetwork.track_of(beyond_near) is StationTrack)
	if other == null or not _path_is_free(network, run, beyond_far, train) \
			or (not near_is_line and not _path_is_free(network, run, beyond_near, train)):
		return false
	var taken: Array[StringName] = []
	var first_paths: Array[Path3D] = [other.get_track_path(), beyond_far]
	if not near_is_line:
		first_paths.append(beyond_near)
	for path: Path3D in first_paths:
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
	_maneuvers[run.id] = {"steps": steps, "index": 0, "time": 0.0, "table": table, "track": plan["track"], "taken": taken,
			"yaw": loco.model_yaw, "pending": beyond_near if near_is_line else null}
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
			if not _take_pending(run, maneuver, current["path"]):
				# Espera a que se libere el tramo al que tiene que asomarse.
				loco.throttle = 0.0
				loco.brake = 1.0
				run.waiting = "esperando vía libre para dar la vuelta"
				return
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


# Si la maniobra ya puede ir a `path`: si es el tramo que dejó para después, lo reserva si está libre.
func _take_pending(run: AutoTrainRun, maneuver: Dictionary, path: Path3D) -> bool:
	var pending: Variant = maneuver.get("pending")
	if pending == null or pending != path:
		return true
	var network: RailNetwork = _network()
	if network == null or not _path_is_free(network, run, path, get_train(run)):
		return false
	var section: StringName = _section_of_path(network, path)
	if section != &"" and get_token_holder(section) == 0:
		_tokens[section] = run.id
		(maneuver["taken"] as Array).append(section)
	maneuver["pending"] = null
	run.waiting = "dando la vuelta"
	_update_signals()
	return true


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
