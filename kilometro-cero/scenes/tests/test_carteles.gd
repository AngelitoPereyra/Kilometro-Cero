extends Node3D
## Prueba de las tareas 61e.1 y 61e.2 (D117): carteles de señal de dos caras y palancas de vía.
## ciudad (3 vías) --(c_p)-- pueblo (principal y cruce) --(p_m)-- maderera (principal, cruce y
## carga). Comprueba que cada tramo tiene un cartel de línea en cada punta y cada vía de estación
## uno en cada punta, del otro lado de la división y a la derecha del tren que sale; que la cara
## de adelante mira hacia quien la lee; que la salida de una vía se pone en verde solo si se pidió
## con su palanca (la principal, sola); que la entrada avisa si la vía está ocupada o reservada; y que un automático que
## sale tiene su salida en verde y las otras vías no. Palancas (61e.2): solo las vías que no son la
## principal; pedir paso traba el cambio y pone la principal en rojo, tu tren frena en el cartel en
## rojo y pasa con el paso pedido, el cambio se suelta solo al pasar y vuelve a la principal, la
## palanca madre junto a la aguja reserva la vía para entrar (bloqueada en sus dos puntas), la
## principal manda solo en su punta, la
## principal sale sola, una vía con cambio de resorte sale sin pedir y un automático que mueve el
## cambio suelta la traba.
## Al terminar vuelve a cargar la escena limpia para recorrerla con los dos trenes automáticos y el
## tuyo (una locomotora en la tercera vía de la ciudad, mirando al pueblo), desde las 6:30.

const CONTROLES: String = "WASD: caminar · F: cabina o palanca · T: +1 hora · Y: hasta la próxima salida\nTu tren está en la tercera vía de la ciudad. Cada vía tiene su cartel pasando el cambio: la cara que mirás de frente es la tuya.\nPara salir de una vía de cruce (o entrar a una), tirá la palanca junto a su cartel (F): pone el cambio, lo traba y el cartel se pone en verde. La principal no tiene palanca: sale sola."
const LOG: StringName = &"log"
const LEJOS: Vector3 = Vector3(140.0, 0.7, 0.0)
const VERDE: RailSignal.Aspect = RailSignal.Aspect.GREEN
const ROJO: RailSignal.Aspect = RailSignal.Aspect.RED
const PASO_S: float = 1.0 / 60.0

@onready var _network: RailNetwork = $RailNetwork
@onready var _trains: AutoTrains = $TrenesAutomaticos
@onready var _pm: Path3D = $PuebloMaderera
@onready var _player: Player = $Player
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0

## Ya se corrieron las comprobaciones: al recargar la escena queda solo para jugar.
static var _probado: bool = false


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	if _probado:
		_preparar_juego()
		return
	_probado = true
	_probar_cartel()
	_probar_palancas()
	_probar_escena()
	_probar_mesa()
	if _fallos == 0:
		print("Carteles: todas las comprobaciones pasaron.")
	else:
		push_error("Carteles: fallaron %d comprobaciones." % _fallos)
	GameState.reset_production()
	get_tree().reload_current_scene.call_deferred()


func _preparar_juego() -> void:
	GameState.reset_production()
	for station: Station in [$Ciudad as Station, $Pueblo as Station, $Maderera as Station]:
		GameState.production.add_station(station.data, 1)
		GameState.economy.add_station(station.data)
	GameState.clock.current_day = 1
	GameState.clock.time_of_day = 6.5
	GameState.production.add_flow(&"maderera", &"pueblo", LOG, 10)
	GameState.production.add_flow(&"maderera", &"ciudad", LOG, 30)
	_trains.sync_flows()
	for run: AutoTrainRun in _trains.get_runs():
		run.due = AutoTrainRun.next_occurrence(run.out_hour, AutoTrains.now_hours())
	# Tu tren, en la tercera vía de la ciudad (los automáticos usan las otras), mirando al pueblo.
	var tercera: Path3D = _via(&"ciudad", "Cruce2")
	if tercera != null:
		var tuyo: Vehicle = _poner_locomotora(tercera, tercera.curve.get_baked_length() * 0.5, true)
		tuyo.name = "TuTren"
		_player.global_position = tuyo.global_position + Vector3(-4.0, 0.7, 0.0)
	else:
		_player.global_position = $Pueblo.global_position + Vector3(-6.0, 0.7, -40.0)


func _unhandled_input(event: InputEvent) -> void:
	var tecla := event as InputEventKey
	if tecla == null or not tecla.pressed or tecla.echo:
		return
	match tecla.physical_keycode:
		KEY_T:
			GameState.clock.advance(1.0)
		KEY_Y:
			var ahora: float = AutoTrains.now_hours()
			var proxima: float = INF
			for run: AutoTrainRun in _trains.get_runs():
				if not run.is_moving():
					proxima = minf(proxima, run.due)
			if proxima != INF and proxima > ahora:
				GameState.clock.advance(proxima - ahora + 0.01)


func _process(_delta: float) -> void:
	if _hud == null:
		return
	var lineas: PackedStringArray = [CONTROLES, "Día %d · %s" % [GameState.clock.current_day, GameClock.format_time(GameState.clock.time_of_day)]]
	for run: AutoTrainRun in _trains.get_runs():
		lineas.append(run.status_text(GameState.missions.station_name))
	_hud.text = "\n".join(lineas)


# --- El cartel solo ---

func _probar_cartel() -> void:
	var cartel := RailSignal.new()
	add_child(cartel)
	_comprobar(cartel.front == VERDE and cartel.back == ROJO and cartel.clear and not cartel.back_clear, "Un cartel nuevo: adelante verde, atrás rojo")
	_comprobar(cartel.get_node_or_null("LuzAdelante") != null and cartel.get_node_or_null("LuzAtras") != null, "Tiene una luz en cada cara")
	cartel.face_towards(Vector3(1.0, 0.0, 0.0))
	_comprobar(cartel.get_front_direction().dot(Vector3(1.0, 0.0, 0.0)) > 0.99, "La cara de adelante mira hacia donde se le pide")
	var luz: Node3D = cartel.get_node("LuzAdelante") as Node3D
	_comprobar((luz.global_position - cartel.global_position).dot(Vector3(1.0, 0.0, 0.0)) > 0.0, "La luz de adelante está del lado de la cara de adelante")
	cartel.set_clear(false)
	_comprobar(cartel.front == ROJO and cartel.back == ROJO and not cartel.clear, "set_clear cambia solo la cara de adelante")
	cartel.set_aspects(VERDE, RailSignal.Aspect.YELLOW)
	_comprobar(cartel.clear and cartel.back_clear, "El amarillo deja pasar")
	cartel.queue_free()


# --- Escena ---

func _probar_escena() -> void:
	GameState.reset_production()
	for station: Station in [$Ciudad as Station, $Pueblo as Station, $Maderera as Station]:
		GameState.production.add_station(station.data, 1)
		GameState.economy.add_station(station.data)
	GameState.clock.current_day = 1
	GameState.clock.time_of_day = 8.0
	_player.global_position = LEJOS
	_trains._update_signals()

	# Carteles de línea: uno en cada punta de cada tramo, con la cara de adelante hacia la estación.
	for punta: Array in [[&"p_m", &"pueblo"], [&"p_m", &"maderera"], [&"c_p", &"ciudad"], [&"c_p", &"pueblo"]]:
		var linea: RailSignal = _trains.get_signal(punta[0], punta[1])
		_comprobar(linea != null and linea.kind == RailSignal.Kind.LINE, "Hay cartel de línea en %s, punta de %s" % punta)
	var del_pueblo: RailSignal = _trains.get_signal(&"p_m", &"pueblo")
	var punta_pueblo: Vector3 = _pm.global_transform * _pm.curve.sample_baked(0.0)
	_comprobar(del_pueblo != null and (punta_pueblo - del_pueblo.global_position).dot(del_pueblo.get_front_direction()) > 0.0, "La cara de adelante del cartel de línea mira hacia la estación (la salida)")
	_comprobar(del_pueblo != null and del_pueblo.clear, "Sin trenes, la salida a la línea está en verde")

	# Carteles de vía de estación: cada vía, cada punta, pasando la división y a la derecha.
	var principal: Path3D = _via(&"pueblo", "Principal")
	var cruce: Path3D = _via(&"pueblo", "Cruce1")
	var cartel_principal: RailSignal = _cartel(principal, false)
	var cartel_cruce: RailSignal = _cartel(cruce, false)
	_comprobar(cartel_principal != null and cartel_cruce != null and _cartel(principal, true) != null and _cartel(cruce, true) != null, "Cada vía del pueblo tiene un cartel en cada punta")
	if cartel_principal == null or cartel_cruce == null:
		return
	_comprobar(cartel_principal.kind == RailSignal.Kind.TRACK and cartel_principal.station_id == &"pueblo", "Son carteles de vía de estación")
	var punta_a: Vector3 = principal.global_transform * principal.curve.sample_baked(0.0)
	var afuera: Vector3 = Vector3(0.0, 0.0, -1.0)
	# Del otro lado de la división: donde la vía de cruce ya se apartó de la principal.
	var adentro: float = (cartel_cruce.global_position - punta_a).dot(-afuera)
	var lado_cruce: Vector3 = cruce.global_transform * cruce.curve.sample_baked(cruce.curve.get_closest_offset(cruce.to_local(cartel_cruce.global_position)))
	_comprobar(adentro > 10.0 and lado_cruce.x - punta_a.x >= AutoTrains.TRACK_FOULING_LATERAL, "El cartel está pasando la división (%.1f m adentro, la vía de cruce ya a %.1f m)" % [adentro, lado_cruce.x - punta_a.x])
	_comprobar(absf((cartel_principal.global_position - punta_a).dot(-afuera) - adentro) < 2.0, "Los carteles de las dos vías quedan a la misma altura")
	# A la derecha del tren que sale por la punta A (hacia -Z): +X.
	_comprobar((cartel_principal.global_position - punta_a).x > 1.0 and (cartel_cruce.global_position - lado_cruce).x > 1.0, "Van a la derecha del tren que sale")
	_comprobar(cartel_principal.get_front_direction().dot(-afuera) > 0.9, "La cara de adelante mira hacia adentro: la lee el tren de esa vía que va a salir")

	# La salida: la principal sale sola; la de cruce, cuando pide el paso con su palanca.
	_trains._update_signals()
	_comprobar(cartel_principal.front == VERDE and cartel_cruce.front == ROJO, "Sin pedir paso: la principal en verde (sale sola) y la de cruce en rojo")
	var cambio: TrackSwitch = _network.find_switch(_pm, false)
	_comprobar(cambio != null, "Hay un cambio en la punta del pueblo")
	if cambio == null:
		return
	_network.request_route(cruce, false)
	_trains._update_signals()
	_comprobar(cartel_principal.front == ROJO and cartel_cruce.front == VERDE, "Pedido el paso por la vía de cruce, se invierte")

	# La entrada: si la vía está libre (el paso pedido también sirve para entrar).
	_comprobar(cartel_cruce.back == VERDE and del_pueblo.back == VERDE, "La vía de cruce está libre: entrada en verde, también en el cartel de línea (el cambio lleva ahí)")
	var suelto: Vehicle = _poner_locomotora(cruce, 60.0)
	_trains._update_signals()
	_comprobar(cartel_cruce.back == ROJO and _cartel(cruce, true).back == ROJO, "Con un vehículo en la vía de cruce, su entrada está en rojo en las dos puntas")
	_comprobar(del_pueblo.back == ROJO, "El cartel de línea avisa que la vía a la que lleva el cambio está ocupada")
	_network.cancel_route(cruce, false)
	_trains._update_signals()
	_comprobar(cambio.is_main_option(cambio.state) and del_pueblo.back == VERDE and cartel_principal.back == VERDE, "Cancelado el paso, el cambio vuelve a la principal (libre) y la entrada vuelve a verde")
	_quitar(suelto)

	# Un automático que reservó su salida: verde en su vía, rojo en las otras.
	GameState.production.add_flow(&"maderera", &"pueblo", LOG, 10)
	_trains.sync_flows()
	var run: AutoTrainRun = _trains.get_runs()[0]
	_trains.step(0.0)
	GameState.clock.time_of_day = 8.3
	_trains.step(0.0)
	_trains._update_signals()
	_comprobar(_trains.get_token_holder(&"p_m") == run.id, "El automático reservó el tramo")
	var carga: Path3D = _via(&"maderera", "Carga1")
	var principal_maderera: Path3D = _via(&"maderera", "Principal")
	var salida_carga: RailSignal = _cartel(carga, true)
	var salida_principal: RailSignal = _cartel(principal_maderera, true)
	_comprobar(salida_carga != null and salida_carga.front == VERDE, "Sale de la vía de carga: su salida está en verde aunque el cambio todavía no se movió")
	_comprobar(salida_principal != null and salida_principal.front == ROJO, "La principal de la maderera tiene la salida en rojo: el tramo es del automático")
	var llegada: RailSignal = _cartel(cruce, false)
	_comprobar(llegada.back == ROJO, "La vía de cruce del pueblo, reservada para él, avisa ocupada mientras no viaja")
	GameState.clock.time_of_day = 8.5
	_trains.step(0.0)
	_trains._update_signals()
	_comprobar(run.is_moving() and llegada.back == VERDE and del_pueblo.back == VERDE, "Ya viajando, la entrada al pueblo y a su vía están en verde para él")
	_comprobar(not del_pueblo.clear, "La salida del pueblo al tramo, en rojo")


# --- Palancas de vía (61e.2) ---

func _probar_palancas() -> void:
	_trains._update_signals()
	var principal: Path3D = _via(&"pueblo", "Principal")
	var cruce: Path3D = _via(&"pueblo", "Cruce1")
	var cambio: TrackSwitch = _network.find_switch(_pm, false)
	var cartel_cruce: RailSignal = _cartel(cruce, false)
	var cartel_principal: RailSignal = _cartel(principal, false)
	var del_pueblo: RailSignal = _trains.get_signal(&"p_m", &"pueblo")
	_comprobar(cambio != null and cartel_cruce != null and cartel_principal != null and del_pueblo != null, "Pueblo, punta A: cambio, carteles de las dos vías y cartel de línea")
	if cambio == null or cartel_cruce == null or cartel_principal == null or del_pueblo == null:
		return
	var palanca := cartel_cruce.get_node_or_null("Palanca") as TrackLever
	_comprobar(palanca != null and cartel_principal.get_node_or_null("Palanca") == null, "La vía de cruce tiene su palanca junto al cartel; la principal no (sale sola)")
	if palanca == null:
		return
	_comprobar(palanca.global_position.distance_to(cartel_cruce.global_position) < 3.0 and palanca.get_prompt() == "Pedir paso por la vía de cruce", "La palanca dice qué hace: \"%s\"" % palanca.get_prompt())
	_comprobar(cambio.is_main_option(cambio.state) and not cambio.is_locked(), "Al empezar, el cambio está en la principal y suelto")
	_comprobar(cartel_principal.front == VERDE and cartel_cruce.front == ROJO, "Sin pedidos, la principal tiene la salida en verde y la vía de cruce en rojo")

	# Tu tren en la vía de cruce, mirando hacia la punta A: frena en el cartel en rojo.
	var tuyo: Vehicle = _poner_locomotora(cruce, cruce.curve.get_baked_length() * 0.5, true)
	_trains._update_signals()
	_comprobar(cartel_cruce.front == ROJO and _network.get_exit_stop(cruce, false) >= 0.0, "Sin pedir paso, el cartel está en rojo y marca dónde frenar")
	tuyo.throttle = 1.0
	for _i: int in 1500:
		tuyo.simulate(PASO_S)
	var parada: float = cartel_cruce.track_offset + Vehicle.SIGNAL_STOP_MARGIN + tuyo.data.length * 0.5
	_comprobar(tuyo.get_parent() == cruce and absf(tuyo.speed) < 0.01 and absf(tuyo.progress - parada) < 0.5, "Tu tren frena antes del cartel en rojo (en %.1f, el cartel en %.1f)" % [tuyo.progress, cartel_cruce.track_offset])

	# Pedir paso: el cambio va a la vía de cruce, queda trabado y la principal pasa a rojo.
	_comprobar(palanca.interact(_player) and palanca.is_requested() and cambio.get_option_path(cambio.state) == cruce and cambio.is_locked(), "Con F la palanca pide paso: pone el cambio para la vía de cruce y lo traba")
	_comprobar(palanca.get_prompt() == "Cancelar el paso", "Con el paso pedido, la palanca ofrece cancelarlo")
	_comprobar(not cambio.set_state(_opcion(cambio, principal)) and cambio.get_option_path(cambio.state) == cruce, "Trabado, el cambio no se mueve")
	_trains._update_signals()
	_comprobar(cartel_cruce.front == VERDE and cartel_principal.front == ROJO and _network.get_exit_stop(cruce, false) < 0.0, "Paso pedido y línea libre: verde en la vía de cruce y rojo en la principal (otra vía pidió el cambio)")

	# Sale y, al terminar de pasar el cambio, se suelta solo y vuelve a la principal.
	var paso: int = 0
	while paso < 2400 and not (tuyo.get_parent() == _pm and tuyo.global_position.distance_to(cambio.point) > 20.0):
		tuyo.simulate(PASO_S)
		_network.update_locks()
		paso += 1
	_comprobar(tuyo.get_parent() == _pm, "Con la salida en verde, tu tren pasa el cambio y sale al tramo")
	_comprobar(not cambio.is_locked() and not palanca.is_requested() and cambio.is_main_option(cambio.state), "Al terminar de pasar, el cambio se soltó solo y volvió a la principal")
	_quitar(tuyo)
	_trains._update_signals()
	_comprobar(cartel_cruce.front == ROJO and cartel_principal.front == VERDE, "La vía de cruce vuelve a rojo y la principal a verde")

	# Llegando al pueblo: la palanca madre, junto a la aguja, reserva la vía de cruce.
	var madre := _network.get_node_or_null("PalancaMadre%d" % cambio.id) as MotherLever
	_comprobar(madre != null and madre.global_position.distance_to(cambio.point) < 6.0, "El cambio tiene su palanca madre junto a la aguja")
	if madre == null:
		return
	_comprobar(madre.get_prompt() == "Reservar la vía de cruce", "La palanca madre dice qué hace: \"%s\"" % madre.get_prompt())
	_comprobar(madre.interact(_player) and cambio.get_option_path(cambio.state) == cruce and cambio.is_locked() and _network.is_track_reserved(cruce), "Con F reserva la vía de cruce: pone el cambio y lo traba")
	_trains._update_signals()
	_comprobar(cartel_cruce.back == VERDE and _cartel(cruce, true).back == ROJO, "La vía de cruce reservada: entrada en verde por la punta donde se reservó y en rojo en la otra (62.4)")
	_comprobar(cartel_principal.back == ROJO, "La entrada a la principal queda en rojo: el cambio lleva a la vía de cruce (62.4)")
	_comprobar(cartel_principal.front == ROJO, "La principal queda en rojo: el cambio es de la vía de cruce")
	_comprobar(_network.request_route(cruce, true) == "Vía reservada desde la otra punta", "Desde la otra punta no se puede pedir paso por la vía reservada")
	_comprobar(madre.get_prompt() == "Volver el cambio a la principal", "Con una sola vía de cruce, la próxima vez vuelve a la principal")
	madre.interact(_player)
	_comprobar(cambio.is_main_option(cambio.state) and not cambio.is_locked() and not _network.is_track_reserved(cruce), "Con F otra vez se suelta y el cambio vuelve a la principal")
	madre.interact(_player)
	var llega: Vehicle = _poner_locomotora(_pm, 40.0, true)
	llega.throttle = 1.0
	var pisadas: Dictionary = {}
	paso = 0
	while paso < 2400 and not (llega.get_parent() == cruce and llega.global_position.distance_to(cambio.point) > 20.0):
		llega.simulate(PASO_S)
		_network.update_locks()
		pisadas[String(llega.get_parent().name)] = true
		paso += 1
	_comprobar(llega.get_parent() == cruce and not pisadas.has("Principal"), "El tren que llega entra a la vía de cruce")
	_comprobar(not cambio.is_locked() and cambio.is_main_option(cambio.state) and not _network.is_track_reserved(cruce), "Al terminar de entrar, la reserva se soltó y el cambio volvió a la principal")
	_quitar(llega)

	# La principal manda, pero cada punta se maneja sola.
	_comprobar(_network.request_route(cruce, false) == "", "Se vuelve a pedir paso por la vía de cruce")
	var en_principal: Vehicle = _poner_locomotora(principal, 60.0, true)
	en_principal.speed = 3.0
	_trains._update_signals()
	_comprobar(cartel_cruce.front == ROJO, "Con un tren andando por la principal hacia esta punta, la vía de cruce sigue en rojo aunque pidió paso")
	en_principal.speed = -3.0
	_trains._update_signals()
	_comprobar(cartel_cruce.front == VERDE, "Si va hacia la otra punta, no la necesita: se pone en verde")
	_quitar(en_principal)

	# Cancelar con la palanca.
	_comprobar(palanca.interact(_player) and not cambio.is_locked() and cambio.is_main_option(cambio.state), "Con F otra vez, la palanca cancela el paso y el cambio vuelve a la principal")

	# Un automático que necesita el cambio lo mueve igual y el paso pedido se pierde.
	_network.request_route(cruce, false)
	_comprobar(cambio.set_state(_opcion(cambio, principal), true) and not cambio.is_locked(), "Un automático que mueve el cambio para su camino suelta la traba")

	# La principal sale sola: talona el cambio si ninguna vía lo trabó.
	cambio.set_state(_opcion(cambio, cruce))
	var de_principal: Vehicle = _poner_locomotora(principal, 30.0, true)
	_comprobar(not _network.next_piece(principal, false, de_principal).is_empty() and cambio.is_main_option(cambio.state), "Desde la principal se sale sin palanca: talona el cambio, que vuelve a ella")
	_quitar(de_principal)

	# Cambio de resorte en una vía: sale sin pedir, talonando el cambio.
	var sin_resorte: Vehicle = _poner_locomotora(cruce, 30.0, true)
	_comprobar(_network.next_piece(cruce, false, sin_resorte).is_empty(), "Sin resorte, tu tren no talona el cambio puesto para la principal")
	var via_cruce := RailNetwork.track_of(cruce) as StationTrack
	via_cruce.spring_exit = true
	_trains._update_signals()
	_comprobar(cartel_cruce.front == VERDE, "Con spring_exit, la vía de cruce tiene la salida en verde sin pedirla")
	_comprobar(not _network.next_piece(cruce, false, sin_resorte).is_empty() and cambio.get_option_path(cambio.state) == cruce, "Y tu tren talona el cambio, que queda puesto hacia ella")
	via_cruce.spring_exit = false
	_quitar(sin_resorte)
	cambio.set_state(_opcion(cambio, principal))
	_trains._update_signals()


# La palanca de la mesa giratoria de la ciudad: gira una locomotora suelta parada encima.
func _probar_mesa() -> void:
	var palanca := get_node_or_null("Ciudad/Vias/PalancaMesaB") as TurntableLever
	var cola := get_node_or_null("Ciudad/Vias/ColaB") as Path3D
	_comprobar(palanca != null and cola != null, "La ciudad tiene mesa giratoria con su palanca en la cola B")
	if palanca == null or cola == null:
		return
	_comprobar(palanca.why_not() == "No hay ningún vehículo entero sobre la mesa", "Sin nada encima, avisa que no hay qué girar")
	var loco: Vehicle = _poner_locomotora(cola, palanca.spot)
	var antes: bool = loco.reversed
	loco.speed = 0.0
	_comprobar(palanca.why_not() == "" and palanca.interact(_player), "Con la locomotora quieta sobre la mesa, F la empieza a girar")
	_comprobar(palanca.is_turning() and loco.brake >= 1.0, "Mientras gira la mesa, la locomotora queda frenada")
	palanca._process(TurntableLever.TURN_SECONDS * 0.5)
	_comprobar(is_equal_approx(loco.model_yaw, PI * 0.5), "A mitad de camino va por el cuarto de vuelta")
	palanca._process(TurntableLever.TURN_SECONDS)
	_comprobar(not palanca.is_turning() and loco.reversed != antes and is_zero_approx(loco.model_yaw) and is_zero_approx(palanca.table.rotation.y), "Al terminar quedó mirando para el otro lado de la cola")
	_comprobar(loco.get_parent() == cola and absf(loco.progress - palanca.spot) < 0.01 and loco.brake < 1.0, "Sigue en el mismo lugar y suelta el freno")
	_quitar(loco)


func _cartel(path: Path3D, at_end: bool) -> RailSignal:
	return _trains.get_track_signal(RailNetwork.track_of(path) as StationTrack, at_end) if path != null else null


func _opcion(cambio: TrackSwitch, path: Path3D) -> int:
	for index: int in cambio.option_count():
		if cambio.get_option_path(index) == path:
			return index
	return -1


func _via(station: StringName, nombre: String) -> Path3D:
	for via: StationTrack in _network.get_station_tracks(station):
		if via.get_track_path().name == nombre:
			return via.get_track_path()
	return null


func _poner_locomotora(path: Path3D, at: float, mirando_atras: bool = false) -> Vehicle:
	var loco := (load(AutoTrains.LOCOMOTIVE_SCENE) as PackedScene).instantiate() as Vehicle
	loco.name = "Suelta"
	path.add_child(loco)
	loco.place_on(path, at, mirando_atras)
	return loco


func _quitar(vehiculo: Vehicle) -> void:
	vehiculo.get_parent().remove_child(vehiculo)
	vehiculo.free()


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
