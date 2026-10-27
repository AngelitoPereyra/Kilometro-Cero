extends Node3D
## Prueba de la tarea 61e.1 (D117): carteles de señal de dos caras.
## ciudad (3 vías) --(c_p)-- pueblo (principal y cruce) --(p_m)-- maderera (principal, cruce y
## carga). Comprueba que cada tramo tiene un cartel de línea en cada punta y cada vía de estación
## uno en cada punta, del otro lado de la división y a la derecha del tren que sale; que la cara
## de adelante mira hacia quien la lee; que la salida de una vía se pone en verde solo si el
## cambio está puesto para ella; que la entrada avisa si la vía está ocupada o reservada; y que un
## automático que sale tiene su salida en verde y las otras vías no.
## Al terminar vuelve a cargar la escena limpia para recorrerla con los dos trenes automáticos y el
## tuyo (una locomotora en la tercera vía de la ciudad, mirando al pueblo), desde las 6:30.

const CONTROLES: String = "WASD: caminar · F: cabina o palanca · T: +1 hora · Y: hasta la próxima salida\nTu tren está en la tercera vía de la ciudad. Cada vía tiene su cartel pasando el cambio: la cara que mirás de frente es la tuya."
const LOG: StringName = &"log"
const LEJOS: Vector3 = Vector3(140.0, 0.7, 0.0)
const VERDE: RailSignal.Aspect = RailSignal.Aspect.GREEN
const ROJO: RailSignal.Aspect = RailSignal.Aspect.RED

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

	# La salida: solo la vía para la que está puesto el cambio.
	_trains._update_signals()
	_comprobar(cartel_principal.front == VERDE and cartel_cruce.front == ROJO, "Con el cambio a la principal: salida verde en la principal y roja en la de cruce")
	var cambio: TrackSwitch = _network.find_switch(_pm, false)
	_comprobar(cambio != null, "Hay un cambio en la punta del pueblo")
	if cambio == null:
		return
	cambio.set_state(_opcion(cambio, cruce))
	_trains._update_signals()
	_comprobar(cartel_principal.front == ROJO and cartel_cruce.front == VERDE, "Con el cambio a la de cruce, se invierte")

	# La entrada: si la vía está libre.
	_comprobar(cartel_cruce.back == VERDE and del_pueblo.back == VERDE, "La vía de cruce está libre: entrada en verde, también en el cartel de línea (el cambio lleva ahí)")
	var suelto: Vehicle = _poner_locomotora(cruce, 60.0)
	_trains._update_signals()
	_comprobar(cartel_cruce.back == ROJO and _cartel(cruce, true).back == ROJO, "Con un vehículo en la vía de cruce, su entrada está en rojo en las dos puntas")
	_comprobar(del_pueblo.back == ROJO, "El cartel de línea avisa que la vía a la que lleva el cambio está ocupada")
	cambio.set_state(_opcion(cambio, principal))
	_trains._update_signals()
	_comprobar(del_pueblo.back == VERDE and cartel_principal.back == VERDE, "Con el cambio a la principal (libre), la entrada vuelve a verde")
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
