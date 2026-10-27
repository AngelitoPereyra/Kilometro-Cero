extends Node3D
## Prueba de la tarea 61e.3: bloques en la vía doble. ciudad ==(c_p: Ida y Vuelta, unos 560 m)==
## pueblo, con bloques de 150 m (TrenesAutomaticos.block_length): cada vía tiene tres carteles de
## bloque además del de salida. Comprueba los colores (rojo con algo en el bloque, amarillo si el
## que sigue está en rojo o si la entrada a la estación de llegada está en rojo), que el tren del
## jugador frena ante un cartel de bloque en rojo, que un automático sale apenas se libera el primer
## bloque y que frena ante el rojo, lejos (como un número) y cerca (de verdad). El tren del jugador
## también frena ante la entrada en rojo a la estación (cartel de línea de llegada).
## Al terminar vuelve a cargar la escena limpia para jugar: tu tren en la tercera vía de la ciudad y
## un automático de la ciudad al pueblo, desde las 6:30.

const CONTROLES: String = "WASD: caminar · F: cabina o palanca · T: +1 hora · Y: hasta la próxima salida\nVía doble con bloques: seguí al automático por la Ida (o salí antes que él) y mirá los carteles."
const PASO_S: float = 1.0 / 60.0
## Cada cuántos pasos se prenden los carteles (en el juego, cada AutoTrains.REFRESH_TIME).
const PASOS_CARTELES: int = 15
const LARGO_BLOQUE: float = 150.0
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
	_probar_carteles()
	_probar_jugador()
	_probar_lejos()
	await _probar_cerca()
	if _fallos == 0:
		print("Bloques: todas las comprobaciones pasaron.")
	else:
		push_error("Bloques: fallaron %d comprobaciones." % _fallos)
	GameState.reset_production()
	get_tree().reload_current_scene.call_deferred()


# Un tren de la ciudad al pueblo y tu tren en la tercera vía de la ciudad, mirando al pueblo.
func _preparar_juego() -> void:
	_agregar_estaciones()
	GameState.clock.time_of_day = 6.5
	GameState.production.add_flow(&"ciudad", &"pueblo", LOG, 10)
	_trains.sync_flows()
	for run: AutoTrainRun in _trains.get_runs():
		run.due = AutoTrainRun.next_occurrence(run.out_hour, AutoTrains.now_hours())
	var tercera: Path3D = _via(&"ciudad", "Cruce2")
	if tercera != null:
		var tuyo: Vehicle = _poner_locomotora(tercera, tercera.curve.get_baked_length() * 0.5, true)
		tuyo.name = "TuTren"
		_player.global_position = tuyo.global_position + Vector3(-4.0, 0.7, 0.0)


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


# Los carteles de bloque y sus colores, con un vehículo quieto en distintos lugares de la Ida.
func _probar_carteles() -> void:
	_comprobar(_network.is_double(&"c_p") and is_equal_approx(_trains.block_length, LARGO_BLOQUE), "c_p es vía doble con bloques de %d m" % LARGO_BLOQUE)
	_trains._update_signals()
	var inicios: PackedFloat64Array = AutoTrains.block_starts(_ida.curve.get_baked_length(), LARGO_BLOQUE)
	_comprobar(inicios.size() == 4, "La Ida tiene cuatro bloques: %s" % [inicios])
	for estacion: StringName in [&"ciudad", &"pueblo"]:
		for numero: int in range(1, 4):
			var cartel: RailSignal = _trains.get_block_signal(&"c_p", estacion, numero)
			_comprobar(cartel != null and cartel.kind == RailSignal.Kind.BLOCK, "Hay cartel de bloque %d en la vía que sale de %s" % [numero, estacion])
			_comprobar(cartel != null and cartel.front == RailSignal.Aspect.GREEN and cartel.back == RailSignal.Aspect.RED, "Con la vía vacía está en verde (y de contramano en rojo)")
		_comprobar(_trains.get_block_signal(&"c_p", estacion, 4) == null, "No hay un cuarto cartel de bloque en la vía que sale de %s" % estacion)
	if inicios.size() != 4:
		return
	var b1: RailSignal = _trains.get_block_signal(&"c_p", &"ciudad", 1)
	var b2: RailSignal = _trains.get_block_signal(&"c_p", &"ciudad", 2)
	var b3: RailSignal = _trains.get_block_signal(&"c_p", &"ciudad", 3)
	var salida: RailSignal = _trains.get_signal(&"c_p", &"ciudad")
	_comprobar(b1 != null and absf(b1.track_offset - inicios[1]) < 0.01 and b1.global_position.distance_to(_ida.global_transform * _ida.curve.sample_baked(inicios[1])) < 4.0, "El cartel de bloque está al lado de la Ida, donde empieza su bloque")
	_comprobar(b1 != null and b1.get_front_direction().dot(_tangente(_ida, inicios[1])) < -0.9, "Su cara de adelante mira a los trenes que vienen por la Ida")
	_comprobar(salida != null and salida.front == RailSignal.Aspect.GREEN, "La salida de la ciudad está en verde")
	if b1 == null or b2 == null or b3 == null or salida == null:
		return

	var quieto: Vehicle = _poner_locomotora(_ida, (inicios[2] + inicios[3]) * 0.5, false)
	_trains._update_signals()
	_comprobar(b2.front == RailSignal.Aspect.RED and b1.front == RailSignal.Aspect.YELLOW and salida.front == RailSignal.Aspect.GREEN and b3.front == RailSignal.Aspect.GREEN,
			"Un tren en el bloque 2: el 2 en rojo, el 1 en amarillo, la salida y el 3 en verde (%s %s %s %s)" % [salida.front, b1.front, b2.front, b3.front])
	_comprobar(_network.get_block_stops(_ida, true) == PackedFloat64Array([inicios[2]]), "La red anota que se frena en el cartel 2: %s" % [_network.get_block_stops(_ida, true)])
	_comprobar(_network.get_block_stops(_vuelta, true).is_empty() and _trains.get_block_signal(&"c_p", &"pueblo", 2).front == RailSignal.Aspect.GREEN, "La Vuelta no se entera")
	quieto.place_on(_ida, (inicios[1] + inicios[2]) * 0.5, false)
	_trains._update_signals()
	_comprobar(b1.front == RailSignal.Aspect.RED and salida.front == RailSignal.Aspect.YELLOW and b2.front == RailSignal.Aspect.GREEN, "En el bloque 1: el 1 en rojo y la salida en amarillo")
	_comprobar(not _network.is_entry_closed(&"c_p", &"ciudad"), "La entrada a la línea no se cierra: se frena en los carteles")
	quieto.place_on(_ida, inicios[0] + 20.0, false)
	_trains._update_signals()
	_comprobar(not salida.clear and _network.get_block_stops(_ida, true) == PackedFloat64Array([inicios[0]]), "En el primer bloque: la salida en rojo y ahí se frena")
	_sacar(quieto)

	# La entrada al pueblo en rojo (un vehículo en la vía a la que lleva el cambio): el último en amarillo.
	var destino: Path3D = _trains._entry_target(_network, &"c_p", &"pueblo")
	_comprobar(destino != null, "La Ida lleva a una vía del pueblo")
	if destino == null:
		return
	var tapon: Vehicle = _poner_locomotora(destino, destino.curve.get_baked_length() * 0.5, false)
	_trains._update_signals()
	_comprobar(b3.front == RailSignal.Aspect.YELLOW and b2.front == RailSignal.Aspect.GREEN, "Con la entrada al pueblo en rojo, el último cartel de bloque está en amarillo")
	var largo: float = _ida.curve.get_baked_length()
	var entrada: RailSignal = _trains._signals.get("c_p|pueblo" + AutoTrains.ARRIVING_SUFFIX) as RailSignal
	_comprobar(entrada != null and entrada.back == RailSignal.Aspect.RED and is_equal_approx(_network.get_exit_stop(_ida, true), largo - AutoTrains.SIGNAL_OFFSET),
			"La entrada al pueblo está en rojo y el tren del jugador frena en su cartel")
	var tuyo: Vehicle = _poner_locomotora(_ida, inicios[3] + 30.0, false)
	tuyo.throttle = 1.0
	for i: int in 3000:
		tuyo.simulate(PASO_S)
	var punta: float = tuyo.progress + tuyo.data.length * 0.5
	_comprobar(tuyo.get_parent() == _ida and punta <= largo - AutoTrains.SIGNAL_OFFSET - Vehicle.SIGNAL_STOP_MARGIN + 0.1,
			"Tu tren frena antes de la entrada en rojo (punta en %.1f de %.1f)" % [punta, largo])
	_sacar(tuyo)
	_sacar(tapon)
	_trains._update_signals()
	_comprobar(b3.front == RailSignal.Aspect.GREEN and _network.get_exit_stop(_ida, true) < 0.0, "Al irse, vuelve al verde y no frena")


# El tren del jugador va por la Ida y frena ante el cartel de bloque en rojo.
func _probar_jugador() -> void:
	var inicios: PackedFloat64Array = AutoTrains.block_starts(_ida.curve.get_baked_length(), LARGO_BLOQUE)
	var adelante: Vehicle = _poner_locomotora(_ida, (inicios[2] + inicios[3]) * 0.5, false)
	var tuyo: Vehicle = _poner_locomotora(_ida, 30.0, false)
	tuyo.throttle = 1.0
	_trains._update_signals()
	for i: int in 9000:
		tuyo.simulate(PASO_S)
		if i % PASOS_CARTELES == 0:
			_trains._update_signals()
	var punta: float = tuyo.progress + tuyo.data.length * 0.5
	_comprobar(tuyo.get_parent() == _ida and punta <= inicios[2] - Vehicle.SIGNAL_STOP_MARGIN + 0.05 and punta > inicios[2] - 5.0,
			"Tu tren frena antes del cartel 2 en rojo (punta en %.1f, cartel en %.1f)" % [punta, inicios[2]])
	_comprobar(_trains.get_block_signal(&"c_p", &"ciudad", 1).front == RailSignal.Aspect.RED, "Detrás de él, el cartel 1 queda en rojo")
	_sacar(adelante)
	_trains._update_signals()
	for i: int in 300:
		tuyo.simulate(PASO_S)
	_comprobar(tuyo.progress + tuyo.data.length * 0.5 > inicios[2] + 1.0, "Con el bloque libre sigue")
	_sacar(tuyo)
	_trains._update_signals()


# Un automático lejos del jugador (solo un número): sale apenas el primer bloque está libre y no
# pasa un cartel de bloque en rojo.
func _probar_lejos() -> void:
	var inicios: PackedFloat64Array = AutoTrains.block_starts(_ida.curve.get_baked_length(), LARGO_BLOQUE)
	_agregar_estaciones()
	GameState.clock.time_of_day = 8.0
	_player.global_position = $Pueblo.global_position + Vector3(120.0, 0.7, -200.0)
	var adelante: Vehicle = _poner_locomotora(_ida, (inicios[1] + inicios[2]) * 0.5, false)
	_trains._update_signals()
	GameState.production.add_flow(&"ciudad", &"pueblo", LOG, 10)
	_trains.sync_flows()
	var run: AutoTrainRun = _trains.get_runs()[0]
	run.due = AutoTrains.now_hours()
	_trains.step(0.0)
	_comprobar(run.state == AutoTrainRun.State.OUTBOUND, "Con un tren en el bloque 1 el automático sale igual (su primer bloque está libre): %s" % run.waiting)
	for i: int in 3000:
		_trains.step(0.05)
		_trains._update_signals()
	var punta: float = run.position + run.lead_offset() - run.segment_start(1)
	_comprobar(run.is_moving() and not _trains.is_spawned(run) and punta <= inicios[1] - Vehicle.SIGNAL_STOP_MARGIN + 0.05 and punta > inicios[1] - 5.0,
			"Lejos frena antes del cartel 1 en rojo (punta en %.1f, cartel en %.1f)" % [punta, inicios[1]])
	_comprobar(_trains.get_signal(&"c_p", &"ciudad").front == RailSignal.Aspect.RED, "Él mismo ocupa el primer bloque: la salida en rojo")
	_sacar(adelante)
	for i: int in 3000:
		_trains.step(0.05)
		_trains._update_signals()
		if not run.is_moving():
			break
	_comprobar(run.state == AutoTrainRun.State.AT_AWAY, "Con la vía libre llega al pueblo")
	GameState.reset_production()
	_trains.sync_flows()
	_comprobar(_trains.get_runs().is_empty(), "Sin el flujo se va el tren")


# Un automático de verdad (cerca del jugador) frena ante el cartel de bloque en rojo y sigue
# cuando se pone en verde.
func _probar_cerca() -> void:
	var inicios: PackedFloat64Array = AutoTrains.block_starts(_ida.curve.get_baked_length(), LARGO_BLOQUE)
	_agregar_estaciones()
	GameState.clock.time_of_day = 8.0
	_trains.despawn_distance = 5000.0
	_player.global_position = $Ciudad.global_position + Vector3(20.0, 0.7, -60.0)
	var adelante: Vehicle = _poner_locomotora(_ida, (inicios[2] + inicios[3]) * 0.5, false)
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
		_sacar(adelante)
		return
	var cabeza: Vehicle = tren[0]
	var quieto: int = 0
	for i: int in 20000:
		if i % PASOS_CARTELES == 0:
			_trains._update_signals()
		_trains._drive(run, PASO_S)
		cabeza.simulate(PASO_S)
		quieto = quieto + 1 if run.waiting == AutoTrains.SIGNAL_WAIT and absf(cabeza.speed) < 0.01 else 0
		if quieto > 120:
			break
		if i % 120 == 0:
			await get_tree().process_frame
	var punta: float = cabeza.progress + cabeza.data.length * 0.5
	_comprobar(cabeza.get_parent() == _ida and punta <= inicios[2] - Vehicle.SIGNAL_STOP_MARGIN + 0.05 and punta > inicios[2] - 8.0,
			"Cerca frena antes del cartel 2 en rojo (punta en %.1f, cartel en %.1f): %s" % [punta, inicios[2], run.waiting])
	_comprobar(_trains.get_block_signal(&"c_p", &"ciudad", 1).front == RailSignal.Aspect.RED and _trains.get_signal(&"c_p", &"ciudad").front == RailSignal.Aspect.YELLOW,
			"Detrás de él: el cartel 1 en rojo y la salida en amarillo")
	_sacar(adelante)
	for i: int in 20000:
		if not run.is_moving():
			break
		if i % PASOS_CARTELES == 0:
			_trains._update_signals()
		_trains._drive(run, PASO_S)
		if is_instance_valid(cabeza):
			cabeza.simulate(PASO_S)
		if i % 120 == 0:
			await get_tree().process_frame
	_comprobar(run.state == AutoTrainRun.State.AT_AWAY, "Con el bloque libre sigue y llega al pueblo")
	_trains.step(0.0)
	_trains._update_signals()
	_comprobar(_trains._maneuvers.has(run.id) and _network.get_exit_stop(_ida, true) >= 0.0,
			"Mientras da la vuelta en el pueblo, el que viene atrás frena en la entrada (no se mete en su maniobra)")


func _agregar_estaciones() -> void:
	GameState.reset_production()
	for station: Station in [$Ciudad as Station, $Pueblo as Station]:
		GameState.production.add_station(station.data, 1)
		GameState.economy.add_station(station.data)
	GameState.clock.current_day = 1


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


func _sacar(vehiculo: Vehicle) -> void:
	vehiculo.get_parent().remove_child(vehiculo)
	vehiculo.free()


static func _tangente(path: Path3D, at: float) -> Vector3:
	var adelante: Vector3 = path.global_transform * path.curve.sample_baked(at + 1.0)
	var atras: Vector3 = path.global_transform * path.curve.sample_baked(at - 1.0)
	return (adelante - atras).normalized()


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
