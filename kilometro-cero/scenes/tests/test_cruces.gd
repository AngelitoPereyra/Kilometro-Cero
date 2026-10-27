extends Node3D
## Prueba de la tarea 61b.2 (D112, D114): los trenes automáticos usan las vías de estación.
## ciudad (3 vías) --(c_p)-- pueblo (principal y cruce) --(p_m)-- maderera (principal, cruce y
## carga). Dos trenes de troncos salen de la maderera: uno al pueblo (10 troncos) y otro a la
## ciudad (30). Comprueba que paran en las vías de cruce o de carga, que el que pasa por el pueblo
## usa la principal mientras el otro espera en la de cruce, que reservan 15 minutos antes, que
## gana el que lleva más carga y que el rojo le corta el paso al tren del jugador. Al final maneja
## uno de verdad, de la maderera a la vía de cruce del pueblo, moviendo los cambios solo, y le
## hace dar la vuelta (tarea 61b.3): en el pueblo rodeando el tren por la principal y en la
## maderera con la mesa giratoria.
## Al terminar vuelve a cargar la escena limpia para jugar con los dos trenes, desde las 6:30.

const CONTROLES: String = "WASD: caminar · F: cabina o palanca · T: +1 hora · Y: hasta la próxima salida\nLos automáticos paran en las vías de cruce y de carga; con el semáforo en rojo, tu tren no entra al tramo."
const PASO_S: float = 1.0 / 60.0
const LOG: StringName = &"log"
const LEJOS: Vector3 = Vector3(140.0, 0.7, 0.0)

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
	_probar_pedazos()
	_probar_prioridad()
	await _probar_escena()
	if _fallos == 0:
		print("Cruces: todas las comprobaciones pasaron.")
	else:
		push_error("Cruces: fallaron %d comprobaciones." % _fallos)
	# Las comprobaciones dejan los trenes con horarios cambiados: se juega desde cero.
	GameState.reset_production()
	get_tree().reload_current_scene.call_deferred()


# Los dos trenes de la maderera, desde temprano, con el jugador en el pueblo.
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
	# Para jugar, cada uno sale a su horario (el de 7 al pueblo, el de 9 a la ciudad) y no apenas
	# nace su flujo: si no, los dos quieren salir a las 7 y gana el que lleva más carga.
	for run: AutoTrainRun in _trains.get_runs():
		run.due = AutoTrainRun.next_occurrence(run.out_hour, AutoTrains.now_hours())
	_player.global_position = $Pueblo.global_position + Vector3(-6.0, 0.7, 0.0)


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


# --- Lógica pura ---

func _probar_pedazos() -> void:
	var pedazo: StringName = AutoTrainRun.station_piece(&"pueblo", "Cruce1", true)
	_comprobar(pedazo == &"@pueblo/Cruce1/f" and AutoTrainRun.is_station_piece(pedazo) and not AutoTrainRun.is_station_piece(&"p_m"), "Un pedazo de viaje en una vía de estación: \"@pueblo/Cruce1/f\"")
	_comprobar(AutoTrainRun.piece_station(pedazo) == &"pueblo" and AutoTrainRun.piece_track_name(pedazo) == "Cruce1" and AutoTrainRun.piece_forward(pedazo), "Se lee la estación, la vía y el sentido")
	_comprobar(AutoTrainRun.piece_section(pedazo) == &"@pueblo/Cruce1" and AutoTrainRun.flip_piece(pedazo) == &"@pueblo/Cruce1/r" and AutoTrainRun.flip_piece(&"p_m") == &"p_m", "Se reserva la vía sin el sentido; al revés cambia el sentido")
	var run := AutoTrainRun.new()
	run.home = &"a"
	run.away = &"b"
	run.loco_length = 10.0
	run.behind = 15.6
	var pedazos: Array[StringName] = [&"@a/Cruce1/r", &"s1", &"@b/Principal/f"]
	var largos: Array[float] = [120.0, 100.0, 120.0]
	_comprobar(run.depart(pedazos, largos), "Sale con vías de estación en el viaje")
	# Centrado: el centro del tren (locomotora + (adelante - atrás) / 2) en la mitad de la vía.
	_comprobar(is_equal_approx(run.position + (run.lead_offset() - run.trail_offset()) * 0.5, 60.0), "Arranca con el tren centrado en su vía")
	_comprobar(is_equal_approx(run.stop_position() + (run.lead_offset() - run.trail_offset()) * 0.5, 340.0 - 60.0), "Para con el tren centrado en la vía de llegada")
	run.advance(1000.0, 1.0)
	_comprobar(run.state == AutoTrainRun.State.AT_AWAY and run.leg[0] == &"@b/Principal/r" and run.leg[2] == &"@a/Cruce1/f", "Al llegar, el viaje de vuelta recorre las vías al revés")
	_comprobar(is_equal_approx(run.position + (run.lead_offset() - run.trail_offset()) * 0.5, 60.0), "Parado, el tren sigue en el mismo lugar (centrado)")


func _probar_prioridad() -> void:
	var mucha := AutoTrainRun.new()
	mucha.id = 901
	mucha.wagons = [{"kind": AutoTrains.KIND_FLATCAR, "item": LOG, "dir": 1, "units": 20}, {"kind": AutoTrains.KIND_FLATCAR, "item": LOG, "dir": 1, "units": 10}]
	var poca := AutoTrainRun.new()
	poca.id = 902
	poca.wagons = [{"kind": AutoTrains.KIND_FLATCAR, "item": LOG, "dir": 1, "units": 10}]
	_trains._requested[901] = 5.0
	_trains._requested[902] = 4.0
	_comprobar(_trains._goes_first(mucha, poca) and not _trains._goes_first(poca, mucha), "Gana el que lleva más carga aunque haya pedido después")
	poca.wagons = mucha.wagons.duplicate(true)
	_comprobar(_trains._goes_first(poca, mucha), "Con la misma carga, el que pidió primero")
	_trains._requested.clear()


# --- Escena ---

func _probar_escena() -> void:
	GameState.reset_production()
	for station: Station in [$Ciudad as Station, $Pueblo as Station, $Maderera as Station]:
		GameState.production.add_station(station.data, 1)
		GameState.economy.add_station(station.data)
	GameState.clock.current_day = 1
	GameState.clock.time_of_day = 8.0
	_player.global_position = LEJOS
	_trains.despawn_distance = 5000.0
	var model: ProductionModel = GameState.production

	# Tren al pueblo: parado en la vía de carga de la maderera.
	model.add_flow(&"maderera", &"pueblo", LOG, 10)
	_trains.sync_flows()
	var al_pueblo: AutoTrainRun = _trains.get_runs()[0]
	_trains.step(0.0)
	_comprobar(al_pueblo.leg == _pedazos([&"@maderera/Carga1/f", &"p_m", &"@pueblo/Cruce1/f"]), "Sale de la vía de carga de la maderera y va a la de cruce del pueblo: %s" % [al_pueblo.leg])
	_comprobar(_trains.get_token_holder(&"@maderera/Carga1") == al_pueblo.id and _trains.get_token_holder(&"p_m") == 0, "Parado se queda con su vía; el tramo todavía no lo reservó")

	# 15 minutos antes reserva: semáforo en rojo y el tren del jugador no entra.
	GameState.clock.time_of_day = 8.3
	_trains.step(0.0)
	_comprobar(al_pueblo.state == AutoTrainRun.State.AT_HOME and _trains.get_token_holder(&"p_m") == al_pueblo.id and _trains.get_token_holder(&"@pueblo/Cruce1") == al_pueblo.id, "A las 8:18 (sale 8:30) ya reservó el tramo y la vía de llegada")
	var semaforo: RailSignal = _trains.get_signal(&"p_m", &"pueblo")
	_comprobar(semaforo != null and not semaforo.clear and _network.is_entry_closed(&"p_m", &"pueblo"), "El semáforo del pueblo está en rojo y cierra la entrada")
	var semaforo_salida: RailSignal = _trains.get_signal(&"p_m", &"maderera")
	_comprobar(semaforo_salida != null and semaforo_salida.clear, "Del lado de la maderera, por donde va a entrar, está en verde: los semáforos van por sentido")
	var principal: Path3D = _via(&"pueblo", "Principal")
	var jugador: Vehicle = _poner_locomotora(principal, 30.0, true)
	_comprobar(not _network.may_enter(jugador, RailNetwork.track_of(_pm), &"pueblo") and _network.next_piece(principal, false, jugador).is_empty(), "Para el tren del jugador es un tramo cortado")
	jugador.throttle = 1.0
	for _i: int in 1200:
		jugador.simulate(PASO_S)
	_comprobar(jugador.get_parent() == principal and absf(jugador.speed) < 0.01, "Manejando hacia el tramo, frena en la punta y no entra")
	jugador.throttle = 0.0
	_quitar(jugador)

	# Sale a su hora y llega a la vía de cruce del pueblo.
	GameState.clock.time_of_day = 8.5
	_trains.step(0.0)
	_comprobar(al_pueblo.state == AutoTrainRun.State.OUTBOUND, "A las 8:30 sale")
	for _i: int in 200:
		_trains.step(PASO_S * 4.0)
	_trains._update_signals()
	_comprobar(not semaforo_salida.clear and not semaforo.clear, "Ya adentro del tramo, rojo en las dos puntas (lo detecta aunque esté lejos, como un número)")
	_avanzar(al_pueblo, 3000)
	_comprobar(al_pueblo.state == AutoTrainRun.State.AT_AWAY and al_pueblo.leg[0] == &"@pueblo/Cruce1/r", "Llega al pueblo y para en la vía de cruce")
	_comprobar(_trains.get_token_holder(&"p_m") == 0 and _trains.get_token_holder(&"@maderera/Carga1") == 0 and _trains.get_token_holder(&"@pueblo/Cruce1") == al_pueblo.id, "Devuelve el tramo y la vía de la maderera; se queda con la de cruce")
	_comprobar(semaforo.clear and not _network.is_entry_closed(&"p_m", &"pueblo"), "Parado en la vía de cruce no tapa el tramo: semáforo en verde")

	# Tren a la ciudad: pasa por la principal del pueblo con el otro parado en la de cruce.
	GameState.clock.time_of_day = 9.0
	model.add_flow(&"maderera", &"ciudad", LOG, 30)
	_trains.sync_flows()
	var a_la_ciudad: AutoTrainRun = null
	for run: AutoTrainRun in _trains.get_runs():
		if run != al_pueblo:
			a_la_ciudad = run
	_trains.step(0.0)
	_comprobar(a_la_ciudad != null and a_la_ciudad.leg == _pedazos([&"@maderera/Carga1/f", &"p_m", &"@pueblo/Principal/f", &"c_p", &"@ciudad/Cruce1/f"]), "El de la ciudad pasa por la principal del pueblo y va a una vía de cruce de la ciudad: %s" % [a_la_ciudad.leg if a_la_ciudad != null else []])
	GameState.clock.time_of_day = 9.5
	_trains.step(0.0)
	_comprobar(a_la_ciudad.state == AutoTrainRun.State.OUTBOUND, "Sale aunque haya otro automático parado en el pueblo (se cruzan)")
	_trains.step(10.0)
	GameState.clock.time_of_day = 12.8
	_trains.step(0.0)
	_comprobar(al_pueblo.state == AutoTrainRun.State.AT_AWAY and al_pueblo.waiting == "esperando vía libre", "El del pueblo quiere volver, pero el tramo lo tiene el otro: espera vía libre")
	_avanzar(a_la_ciudad, 4000)
	_comprobar(a_la_ciudad.state == AutoTrainRun.State.AT_AWAY and a_la_ciudad.leg[0] == &"@ciudad/Cruce1/r", "El de la ciudad llega a su vía de cruce")
	GameState.clock.time_of_day = 13.0
	_trains.step(0.0)
	_comprobar(al_pueblo.state == AutoTrainRun.State.INBOUND and al_pueblo.leg.back() == &"@maderera/Carga1/r", "Con el tramo libre, el del pueblo vuelve a la vía de carga")
	_avanzar(al_pueblo, 3000)
	_comprobar(al_pueblo.state == AutoTrainRun.State.AT_HOME, "Llega a la maderera")

	# Los dos quieren p_m a la vez: gana el de 30 troncos, que para en la vía de cruce.
	var ahora: float = AutoTrains.now_hours()
	al_pueblo.due = ahora + 0.1
	a_la_ciudad.due = ahora + 0.1
	_trains.step(0.0)
	_comprobar(_trains.get_token_holder(&"p_m") == a_la_ciudad.id and al_pueblo.waiting == "esperando vía libre", "Piden el tramo a la vez: lo reserva el que lleva más carga")
	_comprobar(a_la_ciudad.leg.back() == &"@maderera/Cruce1/r", "La vía de carga está ocupada: va a la de cruce de la maderera")
	GameState.clock.advance(0.2)
	_trains.step(0.0)
	# El otro sale más tarde (así no se mueve mientras se mira cómo devuelve el tramo).
	al_pueblo.due = AutoTrains.now_hours() + 48.0
	var devuelto: Dictionary = {"antes_de_llegar": false}
	for _i: int in 4000:
		if not a_la_ciudad.is_moving():
			break
		_trains.step(PASO_S * 4.0)
		if a_la_ciudad.is_moving() and _trains.get_token_holder(&"p_m") == 0:
			devuelto.antes_de_llegar = true
	_comprobar(devuelto.antes_de_llegar, "Devuelve el tramo apenas lo dejó atrás, antes de terminar de llegar")
	_comprobar(a_la_ciudad.state == AutoTrainRun.State.AT_HOME and a_la_ciudad.leg[0] == &"@maderera/Cruce1/f", "El de la ciudad llega a la vía de cruce de la maderera")
	al_pueblo.due = AutoTrains.now_hours()
	_trains.step(0.0)
	_comprobar(al_pueblo.state == AutoTrainRun.State.OUTBOUND and _trains.get_token_holder(&"p_m") == al_pueblo.id and is_equal_approx(al_pueblo.position, al_pueblo.start_position()), "Con el tramo libre, el otro reserva y sale (todavía en la vía de carga)")

	# Lejos, el de la ciudad da la vuelta esperando un rato.
	_trains.step(0.0)
	_comprobar(a_la_ciudad.needs_turn and a_la_ciudad.waiting == "dando la vuelta", "Lejos del jugador, dar la vuelta es una espera")
	GameState.clock.advance(AutoTrains.TURN_HOURS + 0.05)
	_trains.step(0.0)
	_comprobar(not a_la_ciudad.needs_turn and a_la_ciudad.loco_leads and a_la_ciudad.waiting == "", "Pasado el rato, ya tiene la locomotora adelante")

	# De verdad: el del pueblo sale de la vía de carga y entra solo a la de cruce del pueblo.
	_player.global_position = $Maderera.global_position + Vector3(20.0, 0.7, 60.0)
	_trains._update_spawns()
	var tren: Array[Vehicle] = _trains.get_train(al_pueblo)
	_comprobar(tren.size() == 2 and tren[0].get_parent().name == "Carga1" and tren[1].get_parent().name == "Carga1", "Cerca del jugador aparece entero en la vía de carga")
	if tren.size() != 2:
		return
	var pisadas: Dictionary = await _manejar(al_pueblo, 12000)
	var cabeza: Vehicle = tren[0]
	_comprobar(al_pueblo.state == AutoTrainRun.State.AT_AWAY and cabeza.get_parent() == _via(&"pueblo", "Cruce1") and tren[1].get_parent() == _via(&"pueblo", "Cruce1"), "Llega entero a la vía de cruce del pueblo")
	_comprobar(pisadas.has("PuebloMaderera") and not pisadas.has("Principal"), "Pasó por p_m y no pisó ninguna principal")
	var cambio: TrackSwitch = _network.find_switch(_pm, false)
	_comprobar(cambio != null and cambio.option_label(cambio.state) == "vía de cruce", "Movió solo el cambio del pueblo hacia la vía de cruce")

	# La vuelta en el pueblo (sin mesa): la locomotora rodea el tren por la principal.
	a_la_ciudad.due = AutoTrains.now_hours() + 48.0
	_comprobar(al_pueblo.needs_turn and not al_pueblo.loco_leads, "Al llegar, la locomotora quedó del lado lejano: tiene que dar la vuelta")
	_trains.step(0.0)
	_comprobar(_trains._maneuvers.has(al_pueblo.id) and cabeza.rear == null and al_pueblo.waiting == "dando la vuelta", "Se desengancha y empieza a rodear el tren")
	_comprobar(_trains.get_token_holder(&"c_p") == al_pueblo.id and _trains.get_token_holder(&"@pueblo/Principal") == al_pueblo.id, "Reserva la principal y el tramo c_p (pasa la otra punta)")
	pisadas = await _maniobrar(al_pueblo, 20000)
	tren = _trains.get_train(al_pueblo)
	var cruce_pueblo: Path3D = _via(&"pueblo", "Cruce1")
	_comprobar(not _trains._maneuvers.has(al_pueblo.id) and not al_pueblo.needs_turn and al_pueblo.loco_leads, "Terminó la vuelta: el próximo viaje va con la locomotora adelante")
	_comprobar(pisadas.has("CiudadPueblo") and pisadas.has("Principal") and pisadas.has("PuebloMaderera"), "Salió por una punta, volvió por la principal y pasó la otra punta")
	_comprobar(tren.size() == 2 and cabeza.rear == tren[1] and tren[1].get_parent() == cruce_pueblo and cabeza.get_parent() == cruce_pueblo, "Se volvió a enganchar del otro lado, en la vía de cruce")
	_comprobar(cabeza.global_position.z < tren[1].global_position.z, "La locomotora quedó del lado de la maderera")
	_comprobar(al_pueblo.loco_flipped and is_equal_approx(cabeza.model_yaw, PI), "Sin mesa giratoria vuelve de culata")
	_comprobar(_trains.get_token_holder(&"c_p") == 0 and _trains.get_token_holder(&"@pueblo/Principal") == 0, "Devolvió lo que usó para maniobrar")

	# Vuelve con la locomotora adelante. Para probar la mesa, la prueba la pone de frente.
	al_pueblo.loco_flipped = false
	cabeza.model_yaw = 0.0
	al_pueblo.due = AutoTrains.now_hours()
	_trains.step(0.0)
	_comprobar(al_pueblo.state == AutoTrainRun.State.INBOUND, "Sale de vuelta a la maderera")
	pisadas = await _manejar(al_pueblo, 12000)
	var carga: Path3D = _via(&"maderera", "Carga1")
	_comprobar(al_pueblo.state == AutoTrainRun.State.AT_HOME and cabeza.get_parent() == carga and tren[1].get_parent() == carga, "Llega con la locomotora adelante a la vía de carga")
	_comprobar(not pisadas.has("Principal"), "Volvió por las vías de cruce y de carga, sin pisar ninguna principal")

	# En la maderera hay mesa giratoria al final de la cola.
	_trains.step(0.0)
	_comprobar(_trains._maneuvers.has(al_pueblo.id), "Empieza la vuelta en la maderera")
	var visto: Dictionary = {"mesa": false}
	var mesa: Node3D = ($Maderera.get_node(^"Vias") as StationTracks).get_turntable(_via(&"maderera", "ColaA"))
	pisadas = await _maniobrar(al_pueblo, 20000, func() -> void:
		if mesa != null and absf(mesa.rotation.y) > 0.5:
			visto.mesa = true)
	tren = _trains.get_train(al_pueblo)
	_comprobar(visto.mesa and pisadas.has("ColaA") and pisadas.has("Principal"), "Fue a la mesa de la cola, giró y volvió por la principal")
	_comprobar(tren.size() == 2 and cabeza.rear == tren[1] and cabeza.get_parent() == carga, "Enganchó el tren del otro lado")
	_comprobar(not al_pueblo.loco_flipped and is_equal_approx(cabeza.model_yaw, 0.0) and is_equal_approx(mesa.rotation.y, 0.0), "Con la mesa vuelve de frente")
	_comprobar(cabeza.global_position.z > tren[1].global_position.z, "La locomotora quedó del lado del pueblo")
	_player.global_position = LEJOS


func _pedazos(ids: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(ids)
	return result


func _via(station: StringName, nombre: String) -> Path3D:
	for via: StationTrack in _network.get_station_tracks(station):
		if via.get_track_path().name == nombre:
			return via.get_track_path()
	return null


func _poner_locomotora(path: Path3D, at: float, mirando_atras: bool = false) -> Vehicle:
	var loco := (load(AutoTrains.LOCOMOTIVE_SCENE) as PackedScene).instantiate() as Vehicle
	loco.name = "TrenDelJugador"
	path.add_child(loco)
	loco.place_on(path, at, mirando_atras)
	return loco


func _quitar(vehiculo: Vehicle) -> void:
	vehiculo.get_parent().remove_child(vehiculo)
	vehiculo.free()


# Lejos del jugador: avanza paso a paso hasta llegar.
func _avanzar(run: AutoTrainRun, pasos: int) -> void:
	for _i: int in pasos:
		if not run.is_moving():
			return
		_trains.step(PASO_S * 4.0)


# Maneja la maniobra de vuelta paso a paso (cada paso llama a `cada_paso`, si hay). Devuelve los
# nombres de las curvas que pisó la locomotora.
func _maniobrar(run: AutoTrainRun, pasos: int, cada_paso: Callable = Callable()) -> Dictionary:
	var pisadas: Dictionary = {}
	for i: int in pasos:
		if not _trains._maneuvers.has(run.id):
			break
		var loco: Vehicle = _trains.get_train(run)[0]
		_trains._drive(run, PASO_S)
		loco.simulate(PASO_S)
		pisadas[String(loco.get_parent().name)] = true
		if cada_paso.is_valid():
			cada_paso.call()
		if i % 120 == 0:
			await get_tree().process_frame
	return pisadas


# Maneja el tren de verdad paso a paso. Devuelve los nombres de las curvas que pisó.
func _manejar(run: AutoTrainRun, pasos: int) -> Dictionary:
	var pisadas: Dictionary = {}
	for i: int in pasos:
		var tren: Array[Vehicle] = _trains.get_train(run)
		if tren.is_empty() or not run.is_moving():
			break
		_trains._drive(run, PASO_S)
		tren = _trains.get_train(run)
		if not tren.is_empty():
			tren[0].simulate(PASO_S)
			for vehiculo: Vehicle in tren:
				pisadas[String(vehiculo.get_parent().name)] = true
		if i % 120 == 0:
			await get_tree().process_frame
	return pisadas


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
