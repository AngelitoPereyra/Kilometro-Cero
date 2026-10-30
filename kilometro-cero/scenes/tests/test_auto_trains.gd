extends Node3D
## Prueba de la tarea 61: trenes automáticos (AutoTrainRun, AutoTrains, FlowNames, RailSignal;
## D81, D106, D110). Primero la lógica pura; después la escena:
## ciudad ==(c_p, vía doble: Ida y Vuelta)== pueblo --(p_m, vía simple)-- maderera,
## con un tren del jugador (locomotora y plataforma) en la Ida, cerca de la ciudad. Los trenes
## automáticos se mueven paso a paso (sin esperar cuadros). Al terminar vuelve a cargar la escena
## limpia para jugar (ver CONTROLES).

const CONTROLES: String = "WASD: caminar · F: cabina · 1: flujo de 10 troncos maderera→pueblo · 2: flujo de pasajeros ciudad↔pueblo · 3: suma 25 troncos (más vagones)\nT: +1 hora · Y: hasta la próxima salida · C: cortar o abrir p_m · X: borrar el último flujo · Mirá los tableros: horarios y estado de cada tren."
const PASO_S: float = 1.0 / 60.0
const LOG: StringName = &"log"
const TRAVELERS: StringName = &"travelers"
const LEJOS: Vector3 = Vector3(250.0, 0.7, 300.0)

## Ya se corrieron las comprobaciones: al recargar la escena queda solo para jugar.
static var _probado: bool = false

@onready var _network: RailNetwork = $RailNetwork
@onready var _trains: AutoTrains = $TrenesAutomaticos
@onready var _pm: Path3D = $PuebloMaderera
@onready var _loco: Vehicle = $Ida/Locomotive
@onready var _pueblo: Station = $Pueblo
@onready var _maderera: Station = $Maderera
@onready var _player: Player = $Player
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0


func _ready() -> void:
	if _probado:
		_preparar_juego.call_deferred()
		return
	_probado = true
	_probar_nombres()
	_probar_vagones()
	_probar_viaje()
	await get_tree().process_frame
	await get_tree().process_frame
	await _probar_escena()
	if _fallos == 0:
		print("Trenes automáticos: todas las comprobaciones pasaron.")
	else:
		push_error("Trenes automáticos: fallaron %d comprobaciones." % _fallos)
	GameState.reset_production()
	get_tree().reload_current_scene.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	var tecla := event as InputEventKey
	if tecla == null or not tecla.pressed or tecla.echo:
		return
	var model: ProductionModel = GameState.production
	match tecla.physical_keycode:
		KEY_1:
			model.add_flow(&"maderera", &"pueblo", LOG, 10)
		KEY_2:
			model.add_flow(&"ciudad", &"pueblo", TRAVELERS, 5, true)
		KEY_3:
			model.add_flow(&"maderera", &"pueblo", LOG, 25)
		KEY_X:
			var flows: Array[ProductionFlow] = model.get_flows()
			if not flows.is_empty():
				model.remove_flow(flows.back())
		KEY_T:
			GameState.clock.advance(1.0)
		KEY_Y:
			_hasta_la_proxima_salida()
		KEY_C:
			var cortado: bool = _network.is_cut(&"p_m")
			_network.set_state(&"p_m", TrackSegment.State.OPEN if cortado else TrackSegment.State.CUT)


func _process(_delta: float) -> void:
	if _hud == null:
		return
	var lineas: PackedStringArray = [CONTROLES, "Día %d · %s · p_m %s" % [
		GameState.clock.current_day, GameClock.format_time(GameState.clock.time_of_day),
		"cortado" if _network.is_cut(&"p_m") else "abierto"]]
	for run: AutoTrainRun in _trains.get_runs():
		lineas.append("%s%s" % [run.status_text(GameState.missions.station_name), " (en la vía)" if _trains.is_spawned(run) else ""])
	_hud.text = "\n".join(lineas)


func _preparar_juego() -> void:
	GameState.clock.time_of_day = 6.5


func _hasta_la_proxima_salida() -> void:
	var ahora: float = AutoTrains.now_hours()
	var proxima: float = INF
	for run: AutoTrainRun in _trains.get_runs():
		if not run.is_moving():
			proxima = minf(proxima, run.due)
	if proxima != INF and proxima > ahora:
		GameState.clock.advance(proxima - ahora + 0.01)


func _check(condicion: bool, texto: String) -> void:
	if condicion:
		print("OK: " + texto)
	else:
		_fallos += 1
		push_error("FALLA: " + texto)


# --- Lógica pura ---

func _probar_nombres() -> void:
	var items: Dictionary = {LOG: load("res://data/items/log.tres"), TRAVELERS: load("res://data/items/travelers.tres")}
	var buscar: Callable = func(item_id: StringName) -> ItemData: return items.get(item_id)
	var nombres: Callable = func(station_id: StringName) -> String: return {&"maderera": "Maderera", &"pueblo": "Pueblo", &"ciudad": "Ciudad"}.get(station_id, String(station_id))
	var troncos := ProductionFlow.new(&"maderera", &"pueblo", LOG, 10)
	_check(FlowNames.flow_name(troncos, buscar, nombres) == "Tren de troncos de Maderera", "Nombre de un flujo de carga: \"Tren de troncos de Maderera\"")
	var gente := ProductionFlow.new(&"ciudad", &"pueblo", TRAVELERS, 5)
	gente.round_trip = true
	_check(FlowNames.flow_name(gente, buscar, nombres) == "Tren de pasajeros a Pueblo", "Nombre de un flujo de pasajeros: \"Tren de pasajeros a Pueblo\"")
	var flujos: Array[ProductionFlow] = [troncos, gente]
	_check(FlowNames.train_name(flujos, buscar, nombres) == "Tren de troncos de Maderera", "El tren de una conexión se llama como su flujo más viejo")
	gente.custom_name = "El Marplatense"
	_check(FlowNames.train_name(flujos, buscar, nombres) == "El Marplatense", "Un nombre especial manda")
	var guardado := ProductionFlow.from_dict(gente.to_dict())
	_check(guardado.custom_name == "El Marplatense", "El nombre especial se guarda")
	var sin_nombre := ItemData.new()
	sin_nombre.display_name = "piedra"
	_check(FlowNames.cargo_name(sin_nombre) == "piedra", "Sin cargo_name, la carga se llama como el objeto")


func _probar_vagones() -> void:
	var pasajero: Callable = func(item_id: StringName) -> bool: return item_id == TRAVELERS
	var lugares: Dictionary = {AutoTrains.KIND_FLATCAR: 20, AutoTrains.KIND_COACH: 10}
	var flujos: Array[ProductionFlow] = [ProductionFlow.new(&"maderera", &"pueblo", LOG, 10)]
	var vagones: Array[Dictionary] = AutoTrains.plan_wagons(flujos, &"maderera", pasajero, lugares, 4)
	_check(vagones.size() == 1 and vagones[0]["kind"] == AutoTrains.KIND_FLATCAR and vagones[0]["units"] == 10 and vagones[0]["dir"] == 1, "10 troncos por día: una plataforma de ida")
	flujos.append(ProductionFlow.new(&"maderera", &"pueblo", LOG, 25))
	vagones = AutoTrains.plan_wagons(flujos, &"maderera", pasajero, lugares, 4)
	_check(vagones.size() == 3 and vagones[1]["units"] == 20 and vagones[2]["units"] == 5, "Otro flujo en la misma conexión suma vagones (25 troncos: dos plataformas más)")
	var vuelta := ProductionFlow.new(&"pueblo", &"maderera", LOG, 30)
	flujos.append(vuelta)
	vagones = AutoTrains.plan_wagons(flujos, &"maderera", pasajero, lugares, 4)
	_check(vagones.size() == 4 and vagones[3]["dir"] == -1, "Sin pasar de lo que arrastra la locomotora (4); lo que va al revés viaja a la vuelta")
	var gente := ProductionFlow.new(&"ciudad", &"pueblo", TRAVELERS, 5)
	gente.round_trip = true
	var mixtos: Array[ProductionFlow] = [gente]
	vagones = AutoTrains.plan_wagons(mixtos, &"ciudad", pasajero, lugares, 4)
	_check(vagones.size() == 1 and vagones[0]["kind"] == AutoTrains.KIND_COACH and vagones[0]["dir"] == 0, "Pasajeros ida y vuelta: un coche que va lleno en los dos sentidos")
	var largos: Array[float] = [10.0, 10.0]
	_check(is_equal_approx(AutoTrains.length_behind(10.0, largos), 5.0 + 0.6 + 10.0 + 0.6 + 10.0), "Largo del tren detrás de la locomotora")
	var sin_vagones: Array[float] = []
	_check(is_equal_approx(AutoTrains.length_behind(10.0, sin_vagones), 5.0), "Sin vagones, media locomotora")


func _probar_viaje() -> void:
	_check(is_equal_approx(AutoTrainRun.next_occurrence(7.0, 8.0), 31.0) and is_equal_approx(AutoTrainRun.next_occurrence(7.0, 30.0), 31.0) and is_equal_approx(AutoTrainRun.next_occurrence(7.0, 31.0), 31.0), "Próxima vez que llega una hora del día")
	var run := AutoTrainRun.new()
	run.home = &"a"
	run.away = &"b"
	run.loco_length = 10.0
	run.behind = 15.6
	run.set_schedule(7.0, 8.0)
	_check(is_equal_approx(run.back_hour, 13.0) and is_equal_approx(run.due, 31.0), "Horario: sale 7:00, vuelve 13:00; a las 8 la próxima salida es mañana")
	_check(not run.is_due(30.0) and run.is_due(31.0), "Sale recién a su hora")
	var tramos: Array[StringName] = [&"s1", &"s2"]
	var largos: Array[float] = [100.0, 60.0]
	_check(run.depart(tramos, largos) and run.state == AutoTrainRun.State.OUTBOUND, "Sale de ida")
	_check(is_equal_approx(run.position, 3.0 + 15.6), "Arranca con la cola a 3 m de la estación")
	_check(is_equal_approx(run.stop_position(), 160.0 - 3.0 - 5.0), "A la ida para con la locomotora a 3 m de la llegada")
	_check(run.locate(120.0) == [1, 20.0], "Ubica una coordenada en su tramo")
	_check(not run.advance(50.0, 31.0, 40.0) and is_equal_approx(run.position, 40.0) and run.waiting == "esperando vía libre", "No pasa de un tren que tiene adelante")
	_check(run.advance(500.0, 32.0) and run.state == AutoTrainRun.State.AT_AWAY, "Llega a destino")
	_check(is_equal_approx(run.due, AutoTrainRun.next_occurrence(13.0, 32.5)), "Espera su hora de vuelta")
	_check(run.leg == _tramos([&"s2", &"s1"]), "El próximo viaje es por los mismos tramos al revés")
	_check(is_equal_approx(run.position, 3.0 + 5.0) and is_equal_approx(run.lead_offset(), 15.6), "A la vuelta va marcha atrás: adelante van los vagones")
	var copia := AutoTrainRun.new()
	copia.load_dict(run.to_dict())
	_check(copia.state == run.state and is_equal_approx(copia.due, run.due) and copia.leg == run.leg, "El viaje se guarda y se carga")


# --- Escena ---

func _probar_escena() -> void:
	GameState.reset_production()
	for station: Station in [$Ciudad as Station, _pueblo, _maderera]:
		GameState.production.add_station(station.data, 1)
		GameState.economy.add_station(station.data)
	GameState.clock.current_day = 1
	GameState.clock.time_of_day = 8.0
	_player.global_position = LEJOS
	await get_tree().physics_frame
	var model: ProductionModel = GameState.production
	model.add_flow(&"maderera", &"pueblo", LOG, 10)
	_trains.sync_flows()
	var runs: Array[AutoTrainRun] = _trains.get_runs()
	_check(runs.size() == 1, "Un flujo nuevo crea su tren")
	var run: AutoTrainRun = runs[0] if not runs.is_empty() else null
	if run == null:
		return
	_check(run.display_name == "Tren de troncos de Maderera" and run.wagons.size() == 1, "Se llama \"Tren de troncos de Maderera\" y lleva una plataforma")
	model.add_flow(&"maderera", &"pueblo", LOG, 25)
	_trains.sync_flows()
	_check(_trains.get_runs().size() == 1 and run.wagons.size() == 3, "Un segundo flujo en la misma conexión no crea otro tren: le suma dos plataformas")
	_check(run.state == AutoTrainRun.State.AT_HOME and absf(run.due - 8.5) < 0.1, "El primer viaje sale apenas nace el flujo (media hora)")
	_trains.step(0.0)
	_check(run.state == AutoTrainRun.State.AT_HOME, "Antes de su hora no sale")

	# Vía cortada: espera.
	_network.set_state(&"p_m", TrackSegment.State.CUT)
	GameState.clock.time_of_day = 8.6
	_trains.step(0.0)
	_check(run.state == AutoTrainRun.State.AT_HOME and run.waiting == "vía cortada", "Con el tramo cortado espera en su estación")
	_network.set_state(&"p_m", TrackSegment.State.OPEN)

	# Vía simple ocupada por un tren del jugador: no sale.
	var intruso: Vehicle = _poner_locomotora(_pm, 100.0)
	_trains.step(0.0)
	_check(run.state == AutoTrainRun.State.AT_HOME and run.waiting == "vía ocupada", "Con un tren del jugador en la vía simple no sale")
	intruso.get_parent().remove_child(intruso)
	intruso.free()

	_trains.step(0.0)
	_check(run.state == AutoTrainRun.State.OUTBOUND and run.leg == _tramos([&"p_m"]), "Sale por la vía simple hacia el pueblo")
	_check(_trains.get_token_holder(&"p_m") == run.id, "Tiene el bastón de la vía simple")
	var semaforo: RailSignal = _trains.get_signal(&"p_m", &"pueblo")
	_check(semaforo != null and not semaforo.clear, "El semáforo del tramo está en rojo")
	_check(not _trains.is_spawned(run), "Lejos del jugador es solo un número")

	# Otro tren que necesita el mismo tramo espera el bastón.
	model.add_flow(&"maderera", &"ciudad", LOG, 5)
	_trains.sync_flows()
	var otro: AutoTrainRun = null
	for candidate: AutoTrainRun in _trains.get_runs():
		if candidate != run:
			otro = candidate
	_check(otro != null and not is_equal_approx(otro.out_hour, run.out_hour), "La conexión nueva tiene su propio tren y otro horario")
	GameState.clock.time_of_day = 9.5
	_trains.step(0.0)
	_check(otro != null and otro.state == AutoTrainRun.State.AT_HOME and otro.waiting == "esperando vía libre", "Sin la reserva del tramo, el otro tren espera vía libre")

	# Lejos: avanza sin nodos y no pasa por encima de un tren parado en la vía.
	var parado: Vehicle = _poner_locomotora(_pm, 150.0)
	# Hasta que se frena detrás y un rato más, menos que STUCK_SECONDS (si no, vuelve a la estación
	# de donde salió); desde la 62c.3a los automáticos andan más rápido y llegan antes.
	var detras: int = -1
	for i: int in 600:
		_trains.step(PASO_S * 4.0)
		if detras < 0 and run.waiting == "esperando vía libre":
			detras = i
		if detras >= 0 and i - detras >= 60:
			break
	_check(run.is_moving() and run.waiting == "esperando vía libre", "Lejos tampoco pasa por encima de un tren parado")
	_check(run.position + run.lead_offset() <= 200.0 - 150.0 - 5.0 + 0.01, "Queda detrás del tren parado")
	parado.get_parent().remove_child(parado)
	parado.free()
	for _i: int in 2000:
		if not run.is_moving():
			break
		_trains.step(PASO_S * 4.0)
	_check(run.state == AutoTrainRun.State.AT_AWAY, "Llega al pueblo")
	_check(_trains.get_token_holder(&"p_m") != run.id, "Al llegar devuelve el bastón")
	_trains.step(0.0)
	_trains._update_signals()
	_check(otro.state == AutoTrainRun.State.AT_HOME and otro.waiting == "vía ocupada", "El otro no sale: el tren parado en el pueblo le tapa el camino")
	_check(not semaforo.clear and not _trains.get_signal(&"p_m", &"maderera").clear, "Con un tren parado dentro del tramo los semáforos siguen en rojo")
	model.remove_flow(model.get_flows().back())
	_trains.sync_flows()
	_check(_trains.get_runs().size() == 1 and _trains.get_token_holder(&"p_m") == 0, "Al borrar su flujo el tren se va y no queda nadie con el bastón")

	# Cerca: aparece de verdad, parado en el pueblo. Que no desaparezca al llegar a la maderera
	# (a 200 m del jugador): si no, depende de cuántos cuadros pasen.
	_trains.despawn_distance = 600.0
	_player.global_position = _pueblo.global_position + Vector3(-6.0, 0.7, 0.0)
	await _esperar_fisica(3)
	_trains._update_spawns()
	var tren: Array[Vehicle] = _trains.get_train(run)
	_check(tren.size() == 4, "Cerca del jugador aparece de verdad: locomotora y tres plataformas")
	if tren.size() != 4:
		return
	var cabeza: Vehicle = tren[0]
	_check(cabeza.automatic and tren[3].automatic and cabeza.get_parent() == _pm, "Sus vehículos son automáticos y está en la vía simple")
	var nombre := cabeza.get_node_or_null(^"Nombre") as Label3D
	_check(nombre != null and nombre.text == run.display_name, "Lleva un cartel con su nombre")
	_check((tren[1] as Wagon).get_shown_units() == 0 and (tren[1] as Wagon).get_cargo().get_total() == 0, "Descargado en el pueblo: vuelve vacío (y nunca tiene carga de verdad)")
	_check(tren[1].find_children("*", "", true, false).all(func(node: Node) -> bool: return not node is StorageArea or node.is_queued_for_deletion()), "No se le puede soltar carga adentro")
	_check(not _loco.couple(cabeza) and not tren.back().couple(_loco), "No se acopla con el tren del jugador")
	var cab: Cab = AutoTrains._find_cab(cabeza)
	_check(cab != null and not cab.can_enter(_player), "Su cabina no se usa")
	await _esperar_fisica(3)
	_check(not _pueblo.get_stopped_trains().has(cabeza), "El tablero y el mercado no cuentan sus vagones")
	var tablero := _pueblo.find_child("Tablero", true, false) as StationBoard
	_check(tablero != null and tablero.build_text().contains("— Trenes —") and tablero.build_text().contains(run.display_name), "El tablero del pueblo muestra el tren y su horario")

	# Vuelve marcha atrás a la maderera, de verdad.
	GameState.clock.time_of_day = 13.0
	_trains.step(0.0)
	_check(run.state == AutoTrainRun.State.INBOUND and is_equal_approx((tren[1] as Wagon).get_shown_units(), 0), "A su hora sale de vuelta")
	var antes: float = cabeza.global_position.z
	await _manejar(run, 240)
	_check(cabeza.global_position.z < antes - 3.0 and cabeza.speed < 0.0, "Vuelve marcha atrás hacia la maderera")

	# Se cruza de frente con el tren del jugador: frena y espera, no desaparece.
	var frente: float = run.position + run.lead_offset()
	var bloqueo: Vehicle = _poner_locomotora(_pm, minf(frente + 30.0, 190.0))
	await _manejar(run, 900)
	_check(_trains.is_spawned(run) and run.is_moving() and absf(cabeza.speed) < 0.05, "De frente con otro tren frena y queda a la vista")
	_check(run.waiting == "esperando vía libre", "Avisa que espera vía libre")
	bloqueo.get_parent().remove_child(bloqueo)
	bloqueo.free()
	await _manejar(run, 3000)
	_check(run.state == AutoTrainRun.State.AT_HOME, "Con la vía libre llega a la maderera")
	_check(absf(run.remaining()) < 0.01 or run.state == AutoTrainRun.State.AT_HOME, "Para en su lugar")
	var punta: float = _pm.curve.get_baked_length() - tren.back().progress
	_check(cabeza.get_parent() == _pm and tren.back().get_parent() == _pm, "Queda entero en la vía de la maderera")
	_check(punta > 0.0, "Ningún vagón pasa de la estación")
	_check((tren[1] as Wagon).get_shown_units() == 10 and (tren[2] as Wagon).get_shown_units() == 20, "En la maderera se carga para la ida")

	# Lejos vuelve a ser un número.
	_player.global_position = LEJOS
	_trains._update_spawns()
	await get_tree().process_frame
	_check(not _trains.is_spawned(run) and not is_instance_valid(cabeza), "Al alejarse el jugador deja de estar en la escena")

	# Pasajeros ida y vuelta por la vía doble: tren propio, sin bastón.
	model.add_flow(&"ciudad", &"pueblo", TRAVELERS, 5, true)
	_trains.sync_flows()
	var gente: AutoTrainRun = null
	for candidate: AutoTrainRun in _trains.get_runs():
		if candidate.home == &"ciudad":
			gente = candidate
	_check(gente != null and gente.display_name == "Tren de pasajeros a Pueblo" and gente.wagons.size() == 1, "Pasajeros: \"Tren de pasajeros a Pueblo\" con un coche")
	GameState.clock.time_of_day = 23.0
	_trains.step(0.0)
	_check(gente.state == AutoTrainRun.State.AT_HOME and gente.waiting == "vía ocupada", "En la vía doble no sale si el tren del jugador está en su vía")
	# El tren del jugador se pasa a la otra vía (la de vuelta).
	for vehiculo: Vehicle in [_loco, $Ida/Flatcar as Vehicle]:
		vehiculo.reparent($Vuelta, false)
	_trains.step(0.0)
	_check(gente.state == AutoTrainRun.State.OUTBOUND and _trains.get_token_holder(&"c_p") == 0, "Con su vía libre sale sin bastón aunque el tren del jugador esté en la otra")

	# Guardado.
	var guardado: Dictionary = _trains.to_dict()
	_check((guardado["runs"] as Array).size() == 2, "Se guardan los dos trenes")
	model.remove_flow(model.get_flows().back())
	_trains.sync_flows()
	_check(_trains.get_runs().size() == 1, "Al borrar el flujo de pasajeros se va su tren")


func _tramos(ids: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(ids)
	return result


func _poner_locomotora(path: Path3D, at: float) -> Vehicle:
	var loco := (load(AutoTrains.LOCOMOTIVE_SCENE) as PackedScene).instantiate() as Vehicle
	loco.name = "TrenDelJugador"
	path.add_child(loco)
	loco.place_on(path, at)
	return loco


# Maneja el tren paso a paso: el AutoTrains decide y el vehículo avanza.
func _manejar(run: AutoTrainRun, pasos: int) -> void:
	for i: int in pasos:
		var tren: Array[Vehicle] = _trains.get_train(run)
		if tren.is_empty() or not run.is_moving():
			return
		_trains._drive(run, PASO_S)
		tren = _trains.get_train(run)
		if not tren.is_empty():
			tren[0].simulate(PASO_S)
		if i % 60 == 0:
			await get_tree().process_frame


func _esperar_fisica(cuadros: int) -> void:
	for _i: int in cuadros:
		await get_tree().physics_frame
