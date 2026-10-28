class_name AutoTrainRun
extends RefCounted
## El viaje de un tren automático (D81, D110, tarea 61): un tren por conexión entre dos
## estaciones (`home` y `away`), que lleva los flujos permanentes de esa conexión en los dos
## sentidos. Va y vuelve según su horario: sale de `home` a `out_hour` y vuelve de `away` a
## `back_hour`; si llega tarde, sale apenas puede. Sale con la locomotora adelante; al llegar,
## si la estación tiene vías propias, la locomotora rodea el tren (tarea 61b.3, D115) y vuelve
## adelante (`loco_leads`); si no, vuelve marcha atrás, empujando, como antes.
## Lógica pura: no conoce la escena. Quien lo maneja (AutoTrains) le da el camino al salir y lo
## hace avanzar: lejos del jugador con advance() (solo un número), cerca copiando la posición
## del tren de verdad con set_position(). La entrega de los flujos la sigue haciendo el
## ProductionModel una vez por día (D95): el tren es solo cómo se ve el flujo.
## Posiciones en metros sobre el tramo de viaje ("leg"): 0 en la estación de salida. La posición
## es la del centro de la locomotora.
## Vías de estación (tarea 61b, D112, D114): en una estación con vías propias, el viaje también
## pasa por ellas. Esos pedazos del viaje se escriben "@estación/vía/f" (o "/r"): la vía por su
## nombre de nodo (Principal, Cruce1, Carga1) y si se la recorre hacia el final de su curva (f) o
## hacia el principio (r). Ahí el tren para centrado en la vía y no en la punta.
## Troncales (D118, tarea 61d): el viaje de una troncal tiene `trunk_key` y va de punta a punta
## del pedazo de la línea que usan sus flujos (`home` es la punta de donde salió primero);
## `stops` son las estaciones de la línea que recorre, en orden de `home` a `away`.
## Paradas (tarea 61d.2): una troncal va de parada en parada. `hop_to` es la estación del medio
## donde termina el pedazo de viaje actual ("" si va hasta la punta); al llegar ahí espera
## MIN_DWELL_HOURS (`dwelling`, sin dejar de ir de ida o de vuelta) y sigue desde `hop_from`.
## Vuelta atrás (tarea 62.4, D120): un tren trabado en el camino (turn_back) vuelve a la estación de
## donde salió como si fuera una parada: ahí espera MIN_DWELL_HOURS y prueba de nuevo el mismo viaje.
## Guardado (tarea 62.4, D120): con AutoTrains.park_hidden, un tren parado en su punta se guarda
## (`hidden`): no está en ninguna vía hasta poco antes de su salida.

enum State { AT_HOME, OUTBOUND, AT_AWAY, INBOUND }

const STATE_NAMES: Array[String] = ["en %s", "viajando a %s", "en %s", "volviendo a %s"]
## Lo que queda libre entre la punta del tren y la estación al parar.
const STOP_MARGIN: float = 3.0
## Horas mínimas que espera en una estación al llegar, aunque ya sea su hora de salida.
const MIN_DWELL_HOURS: float = 0.5
## Horas entre la salida de ida y la de vuelta (provisorio, D110).
const BACK_AFTER_HOURS: float = 6.0

var id: int = 0
var home: StringName
var away: StringName
## El nombre que se ve en el cartel y en el tablero (D106).
var display_name: String = ""
## Ids de los ProductionFlow que lleva (del más viejo al más nuevo).
var flow_ids: Array[int] = []
## Vagones, de la locomotora hacia atrás: {"kind": &"flatcar" o &"coach", "item": id,
## "dir": 1 ida, -1 vuelta, 0 los dos sentidos, "units": unidades por viaje}.
var wagons: Array[Dictionary] = []
## Hora del día de la salida de ida y de la de vuelta.
var out_hour: float = 7.0
var back_hour: float = 13.0
var state: State = State.AT_HOME
## Hora absoluta (horas desde el principio de la partida) de la próxima salida.
var due: float = 0.0
## Centro de la locomotora sobre el tramo de viaje.
var position: float = 0.0
## Los tramos del viaje actual (en orden desde la estación de salida) y sus largos.
var leg: Array[StringName] = []
var leg_lengths: Array[float] = []
## Por qué está parado, si lo está: "" o un texto ("vía cortada", "vía ocupada", "esperando vía libre").
var waiting: String = ""
## Largo de la locomotora y del tren detrás del centro de la locomotora.
var loco_length: float = 10.0
var behind: float = 0.0
## Si en el viaje actual (o el próximo, parado) la locomotora va adelante; si no, empuja.
var loco_leads: bool = true
## Si la locomotora va "de culata" (dio la vuelta al tren sin mesa giratoria): solo cómo se ve.
var loco_flipped: bool = false
## Parado: todavía tiene que rodear el tren para volver con la locomotora adelante.
var needs_turn: bool = false
## Lejos del jugador la vuelta es una espera: hasta qué hora (absoluta), o -1.
var turn_until: float = -1.0
## Troncal (tarea 61d): la clave de su línea, motivo y servicio ("" si es el tren de una conexión).
var trunk_key: String = ""
## Troncal: las estaciones de la línea entre `home` y `away`, en ese orden (vacío si no es troncal).
var stops: Array[StringName] = []
## Troncal (tarea 61d.2): de qué estación del medio salió el pedazo de viaje actual ("" si de la
## punta), hasta cuál va ("" si hasta la punta) y si está parada en una del medio.
var hop_from: StringName = &""
var hop_to: StringName = &""
var dwelling: bool = false
## Tarea 62.4: vuelve a la estación de donde salió (turn_back) y cuándo llegó a su punta (hora
## absoluta, -1 si todavía no viajó).
var turned_back: bool = false
var arrived_at: float = -1.0
## Tarea 62.4: guardado fuera de las vías hasta poco antes de su salida (AutoTrains.park_hidden).
var hidden: bool = false


## Una hora del día que vuelve cada día: la primera vez que llega en `after` o después.
static func next_occurrence(hour_of_day: float, after: float) -> float:
	var day_start: float = floorf(after / GameClock.HOURS_PER_DAY) * GameClock.HOURS_PER_DAY
	var at: float = day_start + hour_of_day
	if at < after:
		at += GameClock.HOURS_PER_DAY
	return at


## "07:00".
static func hour_text(hour_of_day: float) -> String:
	return GameClock.format_time(fposmod(hour_of_day, GameClock.HOURS_PER_DAY))


## Pone el horario (la vuelta BACK_AFTER_HOURS después de la ida) y la primera salida.
func set_schedule(hour_out: float, now: float) -> void:
	out_hour = fposmod(hour_out, GameClock.HOURS_PER_DAY)
	back_hour = fposmod(out_hour + BACK_AFTER_HOURS, GameClock.HOURS_PER_DAY)
	if state == State.AT_HOME:
		due = next_occurrence(out_hour, now)
	elif state == State.AT_AWAY:
		due = next_occurrence(back_hour, now)


## Si es una troncal de una línea (tarea 61d) y no el tren de una conexión.
func is_trunk() -> bool:
	return not trunk_key.is_empty()


## Si el viaje pasa por la estación: sale o llega ahí o, si es troncal, está en su recorrido.
func serves(station_id: StringName) -> bool:
	return home == station_id or away == station_id or stops.has(station_id)


func is_moving() -> bool:
	return (state == State.OUTBOUND or state == State.INBOUND) and not dwelling


## Si el viaje actual (o el próximo, parado en una estación) es de ida.
func is_outbound() -> bool:
	return state == State.OUTBOUND or state == State.AT_HOME


## La estación de donde sale el viaje actual o el próximo.
func leg_from() -> StringName:
	if hop_from != &"":
		return hop_from
	return home if is_outbound() else away


func leg_to() -> StringName:
	if hop_to != &"":
		return hop_to
	return away if is_outbound() else home


## Hacia dónde va la carga que se ve: 1 ida, -1 vuelta.
func cargo_dir() -> int:
	return 1 if is_outbound() else -1


## Del centro de la locomotora a la punta que va adelante, y a la de atrás: adelante va la
## locomotora o, si empuja, los vagones.
func lead_offset() -> float:
	return loco_length * 0.5 if loco_leads else behind


func trail_offset() -> float:
	return behind if loco_leads else loco_length * 0.5


## Si un pedazo del viaje es una vía de estación ("@pueblo/Cruce1/f") y no un tramo.
static func is_station_piece(piece: StringName) -> bool:
	return String(piece).begins_with("@")


## El pedazo de viaje de una vía de estación (`forward`: hacia el final de su curva).
static func station_piece(station: StringName, track_name: String, forward: bool) -> StringName:
	return StringName("@%s/%s/%s" % [station, track_name, "f" if forward else "r"])


static func piece_station(piece: StringName) -> StringName:
	return StringName(String(piece).substr(1).get_slice("/", 0))


static func piece_track_name(piece: StringName) -> String:
	return String(piece).get_slice("/", 1)


static func piece_forward(piece: StringName) -> bool:
	return String(piece).get_slice("/", 2) == "f"


## Lo que se reserva de un pedazo: el tramo, o la vía de estación sin el sentido ("@pueblo/Cruce1").
static func piece_section(piece: StringName) -> StringName:
	if not is_station_piece(piece):
		return piece
	return StringName("@%s/%s" % [piece_station(piece), piece_track_name(piece)])


## El mismo pedazo recorrido al revés.
static func flip_piece(piece: StringName) -> StringName:
	if not is_station_piece(piece):
		return piece
	return station_piece(piece_station(piece), piece_track_name(piece), not piece_forward(piece))


func get_leg_length() -> float:
	var total: float = 0.0
	for length: float in leg_lengths:
		total += length
	return total


## Donde queda la locomotora parada en la estación de salida: la cola a STOP_MARGIN de ella o,
## en una vía de estación, el tren centrado en la vía.
func start_position() -> float:
	if not leg.is_empty() and is_station_piece(leg[0]):
		return minf(maxf(leg_lengths[0] * 0.5 - (lead_offset() - trail_offset()) * 0.5, STOP_MARGIN + trail_offset()), leg_lengths[0] - STOP_MARGIN - lead_offset())
	return STOP_MARGIN + trail_offset()


## Donde para en la estación de llegada: la punta a STOP_MARGIN de ella o, en una vía de
## estación, el tren centrado en la vía.
func stop_position() -> float:
	var total: float = get_leg_length()
	if not leg.is_empty() and is_station_piece(leg.back()):
		var piece: float = leg_lengths.back()
		return maxf(minf(total - piece * 0.5 - (lead_offset() - trail_offset()) * 0.5, total - STOP_MARGIN - lead_offset()), total - piece + STOP_MARGIN + trail_offset())
	return total - STOP_MARGIN - lead_offset()


func remaining() -> float:
	return stop_position() - position


## Si ya es hora de salir (horas absolutas).
func is_due(now: float) -> bool:
	return not is_moving() and now >= due


## Sale por el camino `route` (tramos desde la estación de salida, con sus largos). Devuelve
## false si no está en una estación o el camino está vacío.
func depart(route: Array[StringName], lengths: Array[float]) -> bool:
	if is_moving() or route.is_empty() or route.size() != lengths.size():
		return false
	leg = route.duplicate()
	leg_lengths = lengths.duplicate()
	position = start_position()
	waiting = ""
	if dwelling:
		# Sigue el mismo viaje desde la parada del medio.
		dwelling = false
	else:
		state = State.OUTBOUND if state == State.AT_HOME else State.INBOUND
	return true


## Avanza `distance` metros sin pasar de `limit` (otro tren, un tramo cortado). Al llegar a la
## parada, llega. Devuelve true si llegó.
func advance(distance: float, now: float, limit: float = INF) -> bool:
	if not is_moving():
		return false
	var target: float = minf(position + maxf(distance, 0.0), stop_position())
	if target > limit:
		target = maxf(position, limit)
		waiting = "esperando vía libre"
	else:
		waiting = ""
	position = target
	if position >= stop_position() - 0.01:
		finish_hop(now)
		return true
	return false


## Llegó al final del pedazo de viaje: a una parada del medio o a la punta.
func finish_hop(now: float) -> void:
	if hop_to != &"":
		arrive_stop(now)
	else:
		arrive(now)


## Llegó a una parada del medio (tarea 61d.2): espera MIN_DWELL_HOURS y sigue el mismo viaje.
## El viaje queda solo con la vía donde paró, para salir de ahí.
func arrive_stop(now: float) -> void:
	if not is_moving() or hop_to == &"":
		return
	dwelling = true
	hop_from = hop_to
	hop_to = &""
	due = now + MIN_DWELL_HOURS
	if turned_back:
		# Volvió marcha atrás: el próximo intento va otra vez con la locomotora adelante.
		turned_back = false
		loco_leads = not loco_leads
	waiting = ""
	var kept: Array[StringName] = [leg.back()]
	var kept_lengths: Array[float] = [leg_lengths.back()]
	leg = kept
	leg_lengths = kept_lengths
	position = start_position()


## Vuelve a la estación de donde salió el pedazo de viaje actual (tarea 62.4): el viaje se da
## vuelta desde donde está y termina ahí como en una parada del medio (arrive_stop), para probar
## de nuevo. La locomotora queda del otro lado (empuja) hasta llegar. Devuelve false si no viaja.
func turn_back() -> bool:
	if not is_moving() or leg.is_empty():
		return false
	var origin: StringName = leg_from()
	var target: StringName = leg_to()
	var total: float = get_leg_length()
	# Si vuelve a la punta hacia donde va el viaje (dio la vuelta dos veces), llega a la punta.
	hop_to = &"" if origin == (away if is_outbound() else home) else origin
	hop_from = target
	leg.reverse()
	leg_lengths.reverse()
	for index: int in leg.size():
		leg[index] = flip_piece(leg[index])
	position = total - position
	loco_leads = not loco_leads
	turned_back = not turned_back
	waiting = ""
	return true


## La posición que tiene el tren de verdad (cuando está cerca del jugador).
func set_position(value: float) -> void:
	position = value


## Llegó: queda en la estación hasta su próxima salida.
func arrive(now: float) -> void:
	if not is_moving():
		return
	var after: float = now + MIN_DWELL_HOURS
	hop_from = &""
	hop_to = &""
	dwelling = false
	turned_back = false
	arrived_at = now
	if state == State.OUTBOUND:
		state = State.AT_AWAY
		due = next_occurrence(back_hour, after)
	else:
		state = State.AT_HOME
		due = next_occurrence(out_hour, after)
	waiting = ""
	# El viaje siguiente va para el otro lado: la locomotora queda atrás hasta que dé la vuelta.
	loco_leads = not loco_leads
	# Parado, la posición queda donde arranca el próximo viaje (el tramo de vuelta mide igual).
	leg.reverse()
	leg_lengths.reverse()
	# Las vías de estación se recorren al revés.
	for index: int in leg.size():
		leg[index] = flip_piece(leg[index])
	position = start_position()


## En qué tramo del viaje queda la coordenada `at`: [índice, metros desde el principio de ese
## tramo en el sentido del viaje]. [-1, 0] si no hay viaje.
func locate(at: float) -> Array:
	if leg.is_empty():
		return [-1, 0.0]
	var start: float = 0.0
	for index: int in leg.size():
		if at <= start + leg_lengths[index] or index == leg.size() - 1:
			return [index, clampf(at - start, 0.0, leg_lengths[index])]
		start += leg_lengths[index]
	return [-1, 0.0]


## Dónde empieza el tramo `index` del viaje.
func segment_start(index: int) -> float:
	var start: float = 0.0
	for i: int in mini(index, leg_lengths.size()):
		start += leg_lengths[i]
	return start


## La estación de donde sale el tramo `index` del viaje: la de salida para el primero, después
## la del otro extremo del anterior (la da `other_end`, func(segment_id, station) -> station).
## Una vía de estación no cambia de estación.
func segment_entry(index: int, other_end: Callable) -> StringName:
	# Parado, `leg` ya está dado vuelta para el próximo viaje: sale de leg_from() igual.
	var station: StringName = leg_from()
	for i: int in mini(index, leg.size()):
		if not is_station_piece(leg[i]):
			station = other_end.call(leg[i], station)
	return station


## "Tren de troncos de Maderera: viajando a Pueblo · sale 07:00, vuelve 13:00".
func status_text(station_name: Callable) -> String:
	var where: String = STATE_NAMES[state] % station_name.call(leg_to() if is_moving() else (home if state == State.AT_HOME else away))
	if turned_back and is_moving():
		where = "volviendo a %s (vía ocupada adelante)" % station_name.call(leg_to())
	if dwelling:
		where = "parada en %s" % station_name.call(hop_from)
	if not waiting.is_empty():
		where += " (%s)" % waiting
	return "%s: %s · sale %s, vuelve %s" % [display_name, where, hour_text(out_hour), hour_text(back_hour)]


## Para el guardado (tarea 65).
func to_dict() -> Dictionary:
	return {
		"id": id, "home": String(home), "away": String(away), "state": int(state), "due": due,
		"position": position, "out_hour": out_hour, "back_hour": back_hour,
		"leg": leg.map(func(segment_id: StringName) -> String: return String(segment_id)),
		"leg_lengths": leg_lengths.duplicate(),
		"loco_leads": loco_leads, "loco_flipped": loco_flipped, "needs_turn": needs_turn,
		"hop_from": String(hop_from), "hop_to": String(hop_to), "dwelling": dwelling,
		"turned_back": turned_back, "arrived_at": arrived_at, "hidden": hidden,
	}


func load_dict(values: Dictionary) -> void:
	state = int(values.get("state", 0)) as State
	due = float(values.get("due", 0.0))
	position = float(values.get("position", 0.0))
	out_hour = float(values.get("out_hour", out_hour))
	back_hour = float(values.get("back_hour", back_hour))
	loco_leads = bool(values.get("loco_leads", is_outbound()))
	loco_flipped = bool(values.get("loco_flipped", false))
	needs_turn = bool(values.get("needs_turn", false))
	hop_from = StringName(values.get("hop_from", ""))
	hop_to = StringName(values.get("hop_to", ""))
	dwelling = bool(values.get("dwelling", false))
	turned_back = bool(values.get("turned_back", false))
	arrived_at = float(values.get("arrived_at", -1.0))
	hidden = bool(values.get("hidden", false))
	turn_until = -1.0
	leg.clear()
	for segment_id: Variant in values.get("leg", []):
		leg.append(StringName(segment_id))
	leg_lengths.clear()
	for length: Variant in values.get("leg_lengths", []):
		leg_lengths.append(float(length))
