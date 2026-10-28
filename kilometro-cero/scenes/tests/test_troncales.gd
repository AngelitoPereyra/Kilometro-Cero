extends Node3D
## Prueba de las tareas 61d.1 a 61d.3 (y vagones por tipo de la 62.2): trenes troncales (TrunkLine, TrunkPlanner, FlowNames.trunk_name y
## las troncales de AutoTrains; D118). Primero la lógica pura; después la escena (la de
## test_cruces, con vías de estación): ciudad --(c_p)-- pueblo --(p_m)-- maderera, con la
## LineaTroncal Ciudad, Pueblo, Maderera. Los trenes automáticos se mueven paso a paso, lejos del jugador.
## Al terminar vuelve a cargar la escena limpia para jugar (ver CONTROLES).

const CONTROLES: String = "WASD: caminar · 1: 10 troncos maderera→pueblo · 2: pasajeros ciudad↔pueblo · 3: 25 troncos ciudad→maderera (estira la troncal) · 4: 80 troncos pueblo→maderera (segundo servicio)\nT: +1 hora · Y: hasta la próxima salida · X: borrar el último flujo · Mirá los tableros: horarios y estado de cada tren."
const PASO_S: float = 0.25
const LOG: StringName = &"log"
const TRAVELERS: StringName = &"travelers"
const CEMENT: StringName = &"cement"
const LEJOS: Vector3 = Vector3(140.0, 0.7, 0.0)

## Ya se corrieron las comprobaciones: al recargar la escena queda solo para jugar.
static var _probado: bool = false

@onready var _trains: AutoTrains = $TrenesAutomaticos
@onready var _linea: TrunkLine = $LineaTroncal
@onready var _player: Player = $Player
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0


func _ready() -> void:
	if _probado:
		_preparar_juego.call_deferred()
		return
	_probado = true
	_probar_linea()
	_probar_vagones()
	_probar_vagones_por_tipo()
	_probar_servicios()
	_probar_nombres()
	_probar_paradas()
	_probar_carga_visible()
	await get_tree().process_frame
	await get_tree().process_frame
	await _probar_escena()
	if _fallos == 0:
		print("Trenes troncales: todas las comprobaciones pasaron.")
	else:
		push_error("Trenes troncales: fallaron %d comprobaciones." % _fallos)
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
			model.add_flow(&"ciudad", &"maderera", LOG, 25)
		KEY_4:
			model.add_flow(&"pueblo", &"maderera", LOG, 80)
		KEY_X:
			var flows: Array[ProductionFlow] = model.get_flows()
			if not flows.is_empty():
				model.remove_flow(flows.back())
		KEY_T:
			GameState.clock.advance(1.0)
		KEY_Y:
			_hasta_la_proxima_salida()


func _process(_delta: float) -> void:
	if _hud == null:
		return
	var lineas: PackedStringArray = [CONTROLES, "Día %d · %s" % [GameState.clock.current_day, GameClock.format_time(GameState.clock.time_of_day)]]
	for run: AutoTrainRun in _trains.get_runs():
		var vagones: PackedStringArray = []
		for wagon: Dictionary in run.wagons:
			var cargas: PackedStringArray = []
			for carga: Dictionary in wagon.get("loads", []):
				cargas.append("%d %s %s→%s" % [carga["units"], carga["item"], carga["from"], carga["to"]])
			vagones.append("[%s]" % (", ".join(cargas) if not cargas.is_empty() else "%d %s" % [wagon["units"], wagon["item"]]))
		# Por qué vías de estación va el viaje (para ver si el plan y los cambios coinciden).
		var vias: PackedStringArray = []
		for piece: StringName in run.leg:
			if AutoTrainRun.is_station_piece(piece):
				vias.append("%s/%s" % [AutoTrainRun.piece_station(piece), AutoTrainRun.piece_track_name(piece)])
		var cabeza: String = ""
		var tren: Array[Vehicle] = _trains.get_train(run)
		if not tren.is_empty():
			cabeza = " · cabeza en %s, cola en %s" % [tren[0].get_parent().name, tren.back().get_parent().name]
		lineas.append("%s%s · %s · vías: %s%s" % [run.status_text(GameState.missions.station_name), " (en la vía)" if _trains.is_spawned(run) else "", " ".join(vagones), ", ".join(vias), cabeza])
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


func _estaciones() -> Array[Station]:
	var result: Array[Station] = [$Ciudad as Station, $Pueblo as Station, $Maderera as Station]
	return result


func _ids(ids: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(ids)
	return result


func _flujo(from: StringName, to: StringName, amount: int, item: StringName = LOG) -> ProductionFlow:
	return ProductionFlow.new(from, to, item, amount)


# --- Lógica pura ---

func _probar_linea() -> void:
	var linea: Array[StringName] = _ids([&"c", &"p", &"m"])
	_check(TrunkPlanner.fits(_flujo(&"m", &"p", 10), linea), "Un flujo con sus dos estaciones en la línea va por ella")
	_check(not TrunkPlanner.fits(_flujo(&"x", &"p", 10), linea), "Si una punta está fuera de la línea (un ramal), no")
	var flujos: Array[ProductionFlow] = [_flujo(&"m", &"p", 10)]
	_check(TrunkPlanner.span(flujos, linea) == Vector2i(1, 2), "El recorrido es solo el pedazo que usan sus flujos (pueblo a maderera)")
	flujos.append(_flujo(&"c", &"p", 5))
	_check(TrunkPlanner.span(flujos, linea) == Vector2i(0, 2), "Se estira con un flujo que llega más lejos")
	_check(TrunkPlanner.stops(linea, &"m", &"c") == _ids([&"m", &"p", &"c"]), "Las estaciones del recorrido, en el orden del viaje")
	_check(_linea.get_station_ids() == _ids([&"ciudad", &"pueblo", &"maderera"]), "La LineaTroncal de la escena da sus estaciones en orden")
	var ciudades: Array[bool] = [true, false, false, true, false]
	_check(TrunkPlanner.anchor(Vector2i(1, 2), ciudades) == Vector2i(0, 3), "Las puntas se estiran hasta la ciudad más cercana de cada lado")
	_check(TrunkPlanner.anchor(Vector2i(3, 4), ciudades) == Vector2i(3, 4), "Sin ciudad más allá, hasta la punta de la línea")
	_check(TrunkPlanner.anchor(Vector2i(0, 3), ciudades) == Vector2i(0, 3), "Si ya termina en ciudades, queda igual")


func _probar_vagones() -> void:
	var linea: Array[StringName] = _ids([&"c", &"p", &"m"])
	var flujos: Array[ProductionFlow] = [_flujo(&"m", &"p", 20), _flujo(&"p", &"c", 20)]
	_check(TrunkPlanner.pack(TrunkPlanner.chunks(flujos, linea, 20)).size() == 1, "La plataforma que baja troncos en el pueblo sube los que siguen a la ciudad: un vagón")
	flujos.append(_flujo(&"c", &"m", 20))
	_check(TrunkPlanner.pack(TrunkPlanner.chunks(flujos, linea, 20)).size() == 1, "Lo que va para el otro lado viaja a la ida en el mismo vagón")
	flujos.append(_flujo(&"m", &"c", 20))
	_check(TrunkPlanner.pack(TrunkPlanner.chunks(flujos, linea, 20)).size() == 2, "Dos cargas en el mismo tramo y sentido necesitan dos vagones")
	flujos.append(_flujo(&"p", &"m", 30))
	_check(TrunkPlanner.chunks(flujos, linea, 20).size() == 6, "Un flujo más grande que un vagón se parte (30: 20 y 10)")
	var gente := _flujo(&"c", &"p", 5, TRAVELERS)
	gente.round_trip = true
	var con_gente: Array[ProductionFlow] = [gente, _flujo(&"p", &"m", 5, TRAVELERS)]
	_check(TrunkPlanner.pack(TrunkPlanner.chunks(con_gente, linea, 10)).size() == 1, "Pasajeros de ida y vuelta y otros más allá comparten coche")
	var vagones: Array[Dictionary] = TrunkPlanner.plan_wagons(_lista([_flujo(&"m", &"p", 10), _flujo(&"c", &"m", 5)]), linea, &"c", &"m", AutoTrains.KIND_FLATCAR, 20, 4)
	_check(vagones.size() == 1 and (vagones[0]["loads"] as Array).size() == 2, "Un vagón con dos cargas: una a la ida y otra a la vuelta")
	_check(vagones.size() == 1 and vagones[0]["dir"] == 0 and vagones[0]["kind"] == AutoTrains.KIND_FLATCAR, "Se ve cargado en los dos sentidos")
	var al_reves: Array[Dictionary] = TrunkPlanner.plan_wagons(_lista([_flujo(&"m", &"p", 10)]), linea, &"m", &"c", AutoTrains.KIND_FLATCAR, 20, 4)
	_check(al_reves.size() == 1 and al_reves[0]["dir"] == 1, "El sentido se cuenta desde la punta de donde sale (de maderera hacia ciudad: ida)")
	var muchos: Array[Dictionary] = TrunkPlanner.plan_wagons(_lista([_flujo(&"c", &"m", 200)]), linea, &"c", &"m", AutoTrains.KIND_FLATCAR, 20, 4)
	_check(muchos.size() == 4, "Sin pasar de lo que arrastra la locomotora")



# Tarea 62: cada carga en su tipo de vagón (el cemento en el cerrado).
func _probar_vagones_por_tipo() -> void:
	var linea: Array[StringName] = _ids([&"c", &"p", &"m"])
	var tipo: Callable = func(item_id: StringName) -> StringName:
		if item_id == TRAVELERS:
			return AutoTrains.KIND_COACH
		return AutoTrains.KIND_BOXCAR if item_id == CEMENT else AutoTrains.KIND_FLATCAR
	var lugares: Dictionary = {AutoTrains.KIND_FLATCAR: 20, AutoTrains.KIND_BOXCAR: 40, AutoTrains.KIND_COACH: 10}
	var flujos: Array[ProductionFlow] = [_flujo(&"m", &"p", 20), _flujo(&"c", &"p", 30, CEMENT)]
	var vagones: Array[Dictionary] = TrunkPlanner.plan_wagons(flujos, linea, &"c", &"m", AutoTrains.KIND_FLATCAR, 20, 4, tipo, lugares)
	var tipos: Array[StringName] = []
	for vagon: Dictionary in vagones:
		tipos.append(vagon["kind"])
	_check(vagones.size() == 2 and tipos.has(AutoTrains.KIND_FLATCAR) and tipos.has(AutoTrains.KIND_BOXCAR), "Troncos en plataforma y cemento en vagón cerrado: %s" % [tipos])
	var cerrado: int = tipos.find(AutoTrains.KIND_BOXCAR)
	_check(cerrado >= 0 and int(vagones[cerrado]["units"]) == 30, "Las 30 bolsas entran en un solo vagón cerrado (40 lugares)")
	flujos.append(_flujo(&"p", &"m", 20, CEMENT))
	vagones = TrunkPlanner.plan_wagons(flujos, linea, &"c", &"m", AutoTrains.KIND_FLATCAR, 20, 4, tipo, lugares)
	_check(vagones.size() == 2, "El cemento que sigue del pueblo a la maderera usa el mismo vagón cerrado (otro tramo)")
	flujos.append(_flujo(&"m", &"c", 10))
	vagones = TrunkPlanner.plan_wagons(flujos, linea, &"c", &"m", AutoTrains.KIND_FLATCAR, 20, 4, tipo, lugares)
	_check(vagones.size() == 3, "Troncos de vuelta no van en el vagón cerrado aunque vaya vacío para ese lado (%d vagones)" % vagones.size())
	var servicios: Array = TrunkPlanner.split_services(flujos, linea, 20, 2, tipo, lugares)
	_check(servicios.size() == 2, "Con 2 vagones por tren, lo que no entra va a un segundo servicio")
	var nadie: Callable = func(_item_id: StringName) -> bool: return false
	var chicos: Array[Dictionary] = AutoTrains.plan_wagons(_lista([_flujo(&"c", &"p", 10, CEMENT)]), &"c", nadie, lugares, 4, tipo)
	_check(chicos.size() == 1 and chicos[0]["kind"] == AutoTrains.KIND_BOXCAR, "Un tren chico también lleva el cemento en vagón cerrado")
	_check(load(AutoTrains.BOXCAR_SCENE) is PackedScene and load(AutoTrains.BOXCAR_DATA) is WagonData, "La escena y los datos del vagón cerrado cargan")

func _probar_servicios() -> void:
	var linea: Array[StringName] = _ids([&"c", &"p", &"m"])
	var flujos: Array[ProductionFlow] = [_flujo(&"c", &"m", 60), _flujo(&"p", &"m", 40), _flujo(&"c", &"p", 20)]
	var servicios: Array = TrunkPlanner.split_services(flujos, linea, 20, 4)
	_check(servicios.size() == 2, "Lo que no entra en 4 vagones va en un segundo servicio")
	_check(servicios.size() == 2 and (servicios[0] as Array).size() == 2 and (servicios[0] as Array)[1] == flujos[2], "Un flujo más nuevo entra en el primero si cabe (de ciudad a pueblo usa el vagón que va vacío hasta ahí)")
	_check(servicios.size() == 2 and (servicios[1] as Array)[0] == flujos[1], "El que no cabe va al segundo")


func _probar_nombres() -> void:
	var nombres: Callable = func(station_id: StringName) -> String: return {&"maderera": "Maderera", &"pueblo": "Pueblo", &"ciudad": "Ciudad"}.get(station_id, String(station_id))
	var flujos: Array[ProductionFlow] = [_flujo(&"maderera", &"pueblo", 10)]
	_check(FlowNames.trunk_name(flujos, false, &"ciudad", &"maderera", nombres) == "Tren de carga de Ciudad a Maderera", "Troncal de carga: \"Tren de carga de Ciudad a Maderera\"")
	_check(FlowNames.trunk_name(flujos, true, &"ciudad", &"pueblo", nombres) == "Tren de pasajeros de Ciudad a Pueblo", "Troncal de pasajeros: \"Tren de pasajeros de Ciudad a Pueblo\"")
	_check(FlowNames.trunk_name(flujos, false, &"ciudad", &"maderera", nombres, 2) == "Tren de carga de Ciudad a Maderera (2)", "El segundo servicio suma (2)")
	flujos[0].custom_name = "El Maderero"
	_check(FlowNames.trunk_name(flujos, false, &"ciudad", &"maderera", nombres) == "El Maderero", "Un nombre especial manda")


func _probar_paradas() -> void:
	var run := AutoTrainRun.new()
	run.home = &"a"
	run.away = &"c"
	run.loco_length = 10.0
	run.behind = 15.6
	run.set_schedule(7.0, 8.0)
	run.hop_to = &"b"
	var primero: Array[StringName] = [&"s1"]
	var largo_1: Array[float] = [100.0]
	_check(run.depart(primero, largo_1) and run.leg_to() == &"b", "Una troncal sale hasta su próxima parada")
	_check(run.advance(500.0, 31.0) and run.dwelling and run.state == AutoTrainRun.State.OUTBOUND and not run.is_moving(), "Llega a la parada sin terminar el viaje de ida")
	_check(run.leg_from() == &"b" and run.leg_to() == &"c" and is_equal_approx(run.due, 31.0 + AutoTrainRun.MIN_DWELL_HOURS), "Desde ahí sigue a la punta después de media hora")
	var copia := AutoTrainRun.new()
	copia.load_dict(run.to_dict())
	_check(copia.dwelling and copia.hop_from == &"b", "La parada se guarda y se carga")
	var segundo: Array[StringName] = [&"s2"]
	var largo_2: Array[float] = [60.0]
	_check(run.depart(segundo, largo_2) and run.state == AutoTrainRun.State.OUTBOUND and not run.dwelling and run.is_moving(), "Sigue el mismo viaje")
	_check(run.advance(500.0, 32.0) and run.state == AutoTrainRun.State.AT_AWAY and run.hop_from == &"", "Llega a la punta")
	var troncal := AutoTrainRun.new()
	troncal.trunk_key = "troncal|x"
	var poco: Array[Dictionary] = [{"kind": AutoTrains.KIND_FLATCAR, "item": LOG, "dir": 1, "units": 1}]
	troncal.wagons = poco
	var chico := AutoTrainRun.new()
	var mucho: Array[Dictionary] = [{"kind": AutoTrains.KIND_FLATCAR, "item": LOG, "dir": 1, "units": 20}]
	chico.wagons = mucho
	_check(_trains._goes_first(troncal, chico) and not _trains._goes_first(chico, troncal), "Si piden vía a la vez, la troncal va primero aunque lleve menos")


func _probar_carga_visible() -> void:
	var run := AutoTrainRun.new()
	run.trunk_key = "troncal|prueba"
	run.home = &"c"
	run.away = &"m"
	run.stops = _ids([&"c", &"p", &"m"])
	var cargas: Array[Dictionary] = [
		{"item": LOG, "units": 10, "from": &"m", "to": &"p", "dir": -1},
		{"item": LOG, "units": 5, "from": &"c", "to": &"m", "dir": 1},
		{"item": LOG, "units": 7, "from": &"p", "to": &"c", "dir": -1},
	]
	var vagon: Dictionary = {"kind": AutoTrains.KIND_FLATCAR, "item": LOG, "dir": 0, "units": 10, "loads": cargas}
	_check(_trains._shown_units(run, vagon, run.cargo_dir()) == 5, "En la ciudad, a la ida, se ve lo que va a la maderera")
	run.state = AutoTrainRun.State.AT_AWAY
	_check(_trains._shown_units(run, vagon, run.cargo_dir()) == 10, "En la maderera, a la vuelta, se ven los troncos para el pueblo")
	run.state = AutoTrainRun.State.INBOUND
	run.dwelling = true
	run.hop_from = &"p"
	_check(_trains._shown_units(run, vagon, run.cargo_dir()) == 7, "Parada en el pueblo: bajan los de la maderera y suben los que van a la ciudad")


func _lista(flujos: Array) -> Array[ProductionFlow]:
	var result: Array[ProductionFlow] = []
	result.assign(flujos)
	return result


# --- Escena ---

func _probar_escena() -> void:
	GameState.reset_production()
	for station: Station in _estaciones():
		GameState.production.add_station(station.data, 1)
		GameState.economy.add_station(station.data)
	GameState.clock.current_day = 1
	GameState.clock.time_of_day = 8.0
	_player.global_position = LEJOS
	await get_tree().physics_frame
	var model: ProductionModel = GameState.production

	# Una carga de la línea: troncal de carga, estirada hasta la ciudad (61d.2).
	model.add_flow(&"maderera", &"pueblo", LOG, 10)
	_trains.sync_flows()
	var runs: Array[AutoTrainRun] = _trains.get_runs()
	_check(runs.size() == 1 and runs[0].is_trunk(), "Un flujo de la línea crea una troncal, no el tren de su conexión")
	if runs.size() != 1:
		return
	var carga: AutoTrainRun = runs[0]
	_check(carga.home == &"ciudad" and carga.away == &"maderera", "No termina en el pueblo: va de la ciudad a la punta de la línea")
	_check(carga.stops == _ids([&"ciudad", &"pueblo", &"maderera"]), "Su recorrido pasa por el pueblo")
	_check(carga.display_name == "Tren de carga de Ciudad a Maderera" and carga.wagons.size() == 1, "Se llama \"Tren de carga de Ciudad a Maderera\" y lleva una plataforma")

	# Pasajeros: otra troncal, aparte de la carga.
	model.add_flow(&"ciudad", &"pueblo", TRAVELERS, 5, true)
	_trains.sync_flows()
	var gente: AutoTrainRun = null
	for run: AutoTrainRun in _trains.get_runs():
		if run != carga:
			gente = run
	_check(gente != null and gente.is_trunk() and _trains.get_runs().size() == 2, "Los pasajeros van en su propia troncal")
	_check(gente != null and gente.wagons.size() == 1 and gente.wagons[0]["kind"] == AutoTrains.KIND_COACH and gente.display_name.begins_with("Tren de pasajeros de Ciudad"), "\"Tren de pasajeros de Ciudad a ...\" con un coche")
	_check(carga.wagons.size() == 1 and carga.wagons[0]["kind"] == AutoTrains.KIND_FLATCAR, "La troncal de carga no suma coches")
	_check(gente != null and not is_equal_approx(gente.out_hour, carga.out_hour), "Cada troncal tiene su horario")
	model.remove_flow(model.get_flows().back())
	_trains.sync_flows()
	_check(_trains.get_runs().size() == 1 and _trains.get_run(gente.id) == null, "Sin flujos de pasajeros su troncal se va")

	# Otra carga de la línea, de la ciudad a la maderera: misma troncal, mismo vagón.
	model.add_flow(&"ciudad", &"maderera", LOG, 5)
	_trains.sync_flows()
	_check(_trains.get_runs().size() == 1, "Otra carga de la línea va en la misma troncal")
	_check(carga.wagons.size() == 1 and (carga.wagons[0]["loads"] as Array).size() == 2, "Un solo vagón: los troncos al pueblo a la vuelta y los de la ciudad a la ida")
	_check(_trains.get_runs_at(&"pueblo").has(carga), "El tablero del pueblo la muestra aunque solo pase")
	var tablero: String = "\n".join(_trains.describe_at(&"pueblo"))
	_check(tablero.contains("para acá a la ida") and tablero.contains("a la vuelta"), "El tablero del pueblo dice a qué hora para a la ida y a la vuelta")
	_check(not "\n".join(_trains.describe_at(&"ciudad")).contains("para acá"), "En las puntas sigue con la hora de salida y de vuelta")

	# Para en todas las estaciones de su recorrido, también a la ida.
	_avanzar_hasta(carga.due)
	_trains.step(0.0)
	_check(carga.state == AutoTrainRun.State.OUTBOUND and carga.hop_to == &"pueblo" and carga.leg.has(&"c_p") and not carga.leg.has(&"p_m"), "A la ida también para en el pueblo")
	_llegar(carga)
	_check(carga.dwelling and carga.hop_from == &"pueblo", "Parada en el pueblo")
	_avanzar_hasta(carga.due)
	_trains.step(0.0)
	_check(carga.state == AutoTrainRun.State.OUTBOUND and carga.leg.has(&"p_m"), "Sigue a la maderera")
	_llegar(carga)
	_check(carga.state == AutoTrainRun.State.AT_AWAY, "Llega a la maderera")
	_trains.step(0.0)
	_check(not carga.needs_turn and not carga.loco_leads, "No da la vuelta: a la vuelta va adelante la locomotora de la cola")

	# Vuelve a la ciudad: para en el pueblo, donde bajan los troncos de la maderera.
	_avanzar_hasta(carga.due)
	_trains.step(0.0)
	_check(carga.state == AutoTrainRun.State.INBOUND and carga.hop_to == &"pueblo" and carga.leg.has(&"p_m") and not carga.leg.has(&"c_p"), "Sale de vuelta solo hasta el pueblo: ahí bajan los troncos")
	_check(_trains.get_token_holder(&"c_p") != carga.id, "Reserva de parada en parada: el tramo a la ciudad todavía no es suyo")
	_llegar(carga)
	var principal: Path3D = ($Pueblo/Vias as StationTracks).get_main_track().get_track_path()
	_check(carga.dwelling and carga.state == AutoTrainRun.State.INBOUND and carga.hop_from == &"pueblo", "Para en el pueblo sin terminar el viaje")
	# Desde la 61d.3 la troncal de carga para en la de carga o la de cruce; la principal queda para los pasajeros.
	_check(AutoTrainRun.piece_station(carga.leg[0]) == &"pueblo" and AutoTrainRun.piece_track_name(carga.leg[0]) != String(principal.name), "La de carga para fuera de la vía principal (en la de cruce)")
	_check(absf(carga.due - AutoTrains.now_hours() - AutoTrainRun.MIN_DWELL_HOURS) < 0.05, "Espera media hora")
	_check(carga.status_text(GameState.missions.station_name).contains("parada en"), "El tablero dice que está parada")
	_avanzar_hasta(carga.due)
	_trains.step(0.0)
	_check(carga.state == AutoTrainRun.State.INBOUND and not carga.dwelling and carga.hop_to == &"" and carga.leg.has(&"c_p"), "Pasada la media hora sigue hasta la ciudad")
	_llegar(carga)
	_check(carga.state == AutoTrainRun.State.AT_HOME and carga.hop_from == &"", "Llega a la ciudad y termina el viaje")

	# Cerca: una locomotora en cada punta.
	_trains.despawn_distance = 600.0
	_player.global_position = ($Ciudad as Node3D).global_position + Vector3(-12.0, 0.7, 0.0)
	await _esperar_fisica(3)
	_trains._update_spawns()
	var tren: Array[Vehicle] = _trains.get_train(carga)
	_check(tren.size() == carga.wagons.size() + 2, "Cerca del jugador aparece con una locomotora en cada punta")
	if tren.size() >= 2:
		_check(tren.back().data == tren[0].data and is_equal_approx(tren.back().model_yaw, PI), "La de la cola mira para el otro lado")
	_player.global_position = LEJOS
	_trains.despawn_distance = 160.0
	_trains._update_spawns()
	await get_tree().process_frame
	_check(not _trains.is_spawned(carga), "Lejos vuelve a ser un número")

	# Con un tren parado en la principal del pueblo, pasa por otra vía.
	var parado: Vehicle = _poner_locomotora(principal, principal.curve.get_baked_length() * 0.5)
	_avanzar_hasta(carga.due)
	_trains.step(0.0)
	var por_el_pueblo: StringName = &""
	for piece: StringName in carga.leg:
		if AutoTrainRun.is_station_piece(piece) and AutoTrainRun.piece_station(piece) == &"pueblo":
			por_el_pueblo = piece
	_check(carga.state == AutoTrainRun.State.OUTBOUND and por_el_pueblo != &"" and AutoTrainRun.piece_track_name(por_el_pueblo) != String(principal.name), "Con la principal ocupada para en otra vía del pueblo")
	_llegar(carga)
	_avanzar_hasta(carga.due)
	_trains.step(0.0)
	_llegar(carga)
	_check(carga.state == AutoTrainRun.State.AT_AWAY, "Llega a la maderera")
	parado.get_parent().remove_child(parado)
	parado.free()

	# Lo que no entra en lo que arrastra la locomotora: segundo servicio.
	model.add_flow(&"pueblo", &"maderera", LOG, 80)
	_trains.sync_flows()
	var segundo: AutoTrainRun = null
	for run: AutoTrainRun in _trains.get_runs():
		if run != carga:
			segundo = run
	_check(segundo != null and segundo.is_trunk() and segundo.display_name == "Tren de carga de Ciudad a Maderera (2)", "80 troncos más no entran: segundo servicio de la troncal")
	_check(segundo != null and segundo.home == &"ciudad" and segundo.away == &"maderera" and segundo.wagons.size() == 4, "También sale de la ciudad, con cuatro plataformas")

	# Guardado.
	var guardado: Dictionary = _trains.to_dict()
	var claves: Array = (guardado["runs"] as Array).map(func(values: Dictionary) -> String: return String(values["key"]))
	_check(claves.size() == 2 and claves.all(func(key: String) -> bool: return key.begins_with("troncal|")), "Se guardan las troncales con su clave")
	_trains.load_dict(guardado)
	_check(carga.home == &"ciudad" and carga.away == &"maderera" and carga.state == AutoTrainRun.State.AT_AWAY, "Al cargar, la troncal retoma sus puntas")

	# Si la maderera no está en la línea, sus flujos vuelven a los trenes de conexión.
	var sin_maderera: Array[Station] = [$Ciudad as Station, $Pueblo as Station]
	_linea.stations = sin_maderera
	_trains.sync_flows()
	var troncales: int = 0
	for run: AutoTrainRun in _trains.get_runs():
		if run.is_trunk():
			troncales += 1
	_check(troncales == 0 and _trains.get_runs().size() == 2, "Lo que no va por una línea sigue con el tren de su conexión")
	_linea.stations = _estaciones()


func _poner_locomotora(path: Path3D, at: float) -> Vehicle:
	var loco := (load(AutoTrains.LOCOMOTIVE_SCENE) as PackedScene).instantiate() as Vehicle
	loco.name = "TrenDelJugador"
	path.add_child(loco)
	loco.place_on(path, at)
	return loco


func _avanzar_hasta(hora: float) -> void:
	var ahora: float = AutoTrains.now_hours()
	if hora > ahora:
		GameState.clock.advance(hora - ahora + 0.01)


func _esperar_fisica(cuadros: int) -> void:
	for _i: int in cuadros:
		await get_tree().physics_frame


func _llegar(run: AutoTrainRun) -> void:
	for _i: int in 4000:
		if not run.is_moving():
			return
		_trains.step(PASO_S)
