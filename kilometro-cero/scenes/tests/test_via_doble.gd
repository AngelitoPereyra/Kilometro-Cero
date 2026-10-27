extends Node3D
## Prueba de la tarea 61b.4: la vía doble llega a las puntas de las estaciones sin salto.
## ciudad --(c_p: Ida y Vuelta)-- pueblo. Las dos vías del tramo se juntan en cada punta y cada
## tren toma la de su sentido solo, sin cambio con palanca: Ida de la ciudad al pueblo y Vuelta
## del pueblo a la ciudad. Comprueba las uniones, que el tren del jugador sale del pueblo por la
## Vuelta y que un automático va por la Ida, da la vuelta en el pueblo y vuelve por la Vuelta.
## Al terminar vuelve a cargar la escena limpia para jugar con ese tren, desde las 6:30.

const CONTROLES: String = "WASD: caminar · F: cabina o palanca · T: +1 hora · Y: hasta la próxima salida\nVía doble: cada tren toma la vía de su sentido al salir de la estación."
const PASO_S: float = 1.0 / 60.0
const LOG: StringName = &"log"

@onready var _network: RailNetwork = $RailNetwork
@onready var _trains: AutoTrains = $TrenesAutomaticos
@onready var _ida: Path3D = $Ida
@onready var _vuelta: Path3D = $Vuelta
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
	_probar_uniones()
	_probar_jugador()
	await _probar_automatico()
	if _fallos == 0:
		print("Vía doble: todas las comprobaciones pasaron.")
	else:
		push_error("Vía doble: fallaron %d comprobaciones." % _fallos)
	GameState.reset_production()
	get_tree().reload_current_scene.call_deferred()


# Un tren de la ciudad al pueblo, con el jugador en el pueblo.
func _preparar_juego() -> void:
	_agregar_estaciones()
	GameState.clock.time_of_day = 6.5
	GameState.production.add_flow(&"ciudad", &"pueblo", LOG, 10)
	_trains.sync_flows()
	for run: AutoTrainRun in _trains.get_runs():
		run.due = AutoTrainRun.next_occurrence(run.out_hour, AutoTrains.now_hours())
	_player.global_position = $Pueblo.global_position + Vector3(-6.0, 0.7, 40.0)


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


func _probar_uniones() -> void:
	_comprobar(_network.is_double(&"c_p"), "c_p es vía doble")
	for station: StringName in [&"pueblo", &"ciudad"]:
		var punta: Array = _punta_hacia_vias(station)
		_comprobar(not punta.is_empty(), "En %s una vía de estación llega a las dos vías del tramo" % station)
		if punta.is_empty():
			continue
		_comprobar(_network.find_switch(punta[0], punta[1]) == null, "En %s esa punta no es un cambio con palanca" % station)
	# Las puntas de las vías del tramo siguen hacia las vías de estación (ahí sí hay cambio, si
	# la estación tiene más de una vía en esa punta).
	for punta: Array in [[_ida, false], [_ida, true], [_vuelta, false], [_vuelta, true]]:
		var links: Array = _network.get_links(punta[0], punta[1])
		var a_estacion: bool = not links.is_empty()
		for link: Array in links:
			a_estacion = a_estacion and RailNetwork.track_of(link[0]) is StationTrack
		_comprobar(a_estacion, "%s %s sigue hacia una vía de estación" % [(punta[0] as Path3D).name, "final" if punta[1] else "principio"])


func _probar_jugador() -> void:
	var punta: Array = _punta_hacia_vias(&"pueblo")
	if punta.is_empty():
		return
	var via: Path3D = punta[0]
	var largo: float = via.curve.get_baked_length()
	var loco: Vehicle = _poner_locomotora(via, largo - 15.0 if punta[1] else 15.0, not punta[1])
	loco.throttle = 1.0
	var pisadas: Dictionary = {}
	for _i: int in 900:
		loco.simulate(PASO_S)
		pisadas[String(loco.get_parent().name)] = true
	_comprobar(pisadas.has("Vuelta") and not pisadas.has("Ida"), "El tren del jugador sale del pueblo por la Vuelta, la de su sentido: %s" % [pisadas.keys()])
	loco.throttle = 0.0
	loco.get_parent().remove_child(loco)
	loco.free()


func _probar_automatico() -> void:
	_agregar_estaciones()
	GameState.clock.time_of_day = 8.0
	_trains.despawn_distance = 5000.0
	_player.global_position = $Ciudad.global_position + Vector3(20.0, 0.7, -60.0)
	GameState.production.add_flow(&"ciudad", &"pueblo", LOG, 10)
	_trains.sync_flows()
	var run: AutoTrainRun = _trains.get_runs()[0]
	run.due = AutoTrains.now_hours()
	_trains.step(0.0)
	_comprobar(run.state == AutoTrainRun.State.OUTBOUND, "Sale de la ciudad")
	_trains._update_spawns()
	var tren: Array[Vehicle] = _trains.get_train(run)
	_comprobar(not tren.is_empty(), "Cerca del jugador aparece de verdad")
	if tren.is_empty():
		return
	var cabeza: Vehicle = tren[0]
	var pisadas: Dictionary = await _manejar(run, 20000)
	_comprobar(run.state == AutoTrainRun.State.AT_AWAY and cabeza.get_parent() == _via(&"pueblo", "Cruce1"), "Llega a la vía de cruce del pueblo: %s" % [cabeza.get_parent().name])
	_comprobar(pisadas.has("Ida") and not pisadas.has("Vuelta"), "Fue por la Ida: %s" % [pisadas.keys()])

	_trains.step(0.0)
	_comprobar(_trains._maneuvers.has(run.id), "Empieza a dar la vuelta en el pueblo")
	await _maniobrar(run, 20000)
	_comprobar(not _trains._maneuvers.has(run.id) and run.loco_leads and cabeza.rear != null, "Terminó la vuelta y se volvió a enganchar")

	run.due = AutoTrains.now_hours()
	_trains.step(0.0)
	_comprobar(run.state == AutoTrainRun.State.INBOUND, "Sale de vuelta a la ciudad")
	pisadas = await _manejar(run, 20000)
	_comprobar(run.state == AutoTrainRun.State.AT_HOME, "Llega a la ciudad")
	_comprobar(pisadas.has("Vuelta") and not pisadas.has("Ida"), "Volvió por la Vuelta: %s" % [pisadas.keys()])


func _agregar_estaciones() -> void:
	GameState.reset_production()
	for station: Station in [$Ciudad as Station, $Pueblo as Station]:
		GameState.production.add_station(station.data, 1)
		GameState.economy.add_station(station.data)
	GameState.clock.current_day = 1


# La punta de vía de estación que sigue hacia las dos vías del tramo: [Path3D, bool final].
func _punta_hacia_vias(station: StringName) -> Array:
	for via: StationTrack in _network.get_station_tracks(station):
		var path: Path3D = via.get_track_path()
		for at_end: bool in [false, true]:
			var destinos: Array = []
			for link: Array in _network.get_links(path, at_end):
				destinos.append(link[0])
			if destinos.has(_ida) and destinos.has(_vuelta):
				return [path, at_end]
	return []


func _via(station: StringName, nombre: String) -> Path3D:
	for via: StationTrack in _network.get_station_tracks(station):
		if via.get_track_path().name == nombre:
			return via.get_track_path()
	return null


func _poner_locomotora(path: Path3D, at: float, mirando_atras: bool) -> Vehicle:
	var loco := (load(AutoTrains.LOCOMOTIVE_SCENE) as PackedScene).instantiate() as Vehicle
	loco.name = "TrenDelJugador"
	path.add_child(loco)
	loco.place_on(path, at, mirando_atras)
	return loco


# Maneja la maniobra de vuelta paso a paso. Devuelve los nombres de las curvas que pisó.
func _maniobrar(run: AutoTrainRun, pasos: int) -> Dictionary:
	var pisadas: Dictionary = {}
	for i: int in pasos:
		if not _trains._maneuvers.has(run.id):
			break
		var loco: Vehicle = _trains.get_train(run)[0]
		_trains._drive(run, PASO_S)
		loco.simulate(PASO_S)
		pisadas[String(loco.get_parent().name)] = true
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
