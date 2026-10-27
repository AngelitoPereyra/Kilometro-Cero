extends Node3D
## Prueba de la tarea 61b.1 (D112, D113): vías de estación (StationTracks, StationTrack), cambios
## (TrackSwitch), palancas de vía (TrackLever, tarea 61e.2) y desacople con F (Coupler).
## ciudad (3 vías de 6, crece con los flujos) --(c_p)-- pueblo (principal y cruce, andén isla)
## --(p_m)-- maderera (principal, cruce y carga). Corre el tren paso a paso (sin esperar cuadros):
## pasa el pueblo por la principal (sale sola, sin palanca), vuelve marcha atrás por la de cruce
## pidiendo el paso en cada punta (para entrar y para salir; el cambio vuelve solo a la principal) y
## cambia de vía con la palanca mientras se acerca.
## Al terminar se puede jugar: la locomotora con una plataforma, antes del pueblo, mirando hacia él.

const CONTROLES: String = "WASD: caminar · F: cabina, palanca de vía o enganche (desacoplar con el tren quieto)\nJunto a cada aguja, la palanca madre elige a qué vía entrás (la reserva). Para salir de una vía de cruce, la palanca junto a su cartel. La principal sale sola si nadie pidió paso.\nPara acoplar, tocá la plataforma con la cola (marcha atrás)."
const PASO_S: float = 1.0 / 60.0

@onready var _network: RailNetwork = $RailNetwork
@onready var _trains: AutoTrains = $TrenesAutomaticos
@onready var _cp: Path3D = $CiudadPueblo
@onready var _pm: Path3D = $PuebloMaderera
@onready var _loco: Vehicle = $CiudadPueblo/Locomotive
@onready var _flatcar: Vehicle = $CiudadPueblo/Flatcar
@onready var _ciudad: Station = $Ciudad
@onready var _player: Player = $Player
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0


func _ready() -> void:
	# couple_on_start y el armado de la red son diferidos: al terminar el primer cuadro ya están.
	await get_tree().process_frame
	await get_tree().physics_frame
	_probar_cuentas()
	_probar_vias()
	_probar_palanca()
	_probar_tren()
	_probar_desacople()
	_probar_crecimiento()
	if _fallos == 0:
		print("Vías de estación: todas las comprobaciones pasaron.")
	else:
		push_error("Vías de estación: fallaron %d comprobaciones." % _fallos)
	_preparar_para_jugar()


func _process(_delta: float) -> void:
	var lugar: String = _loco.get_parent().name
	var vias := _loco.get_parent().get_parent() as StationTracks
	if vias != null:
		lugar = "%s de %s" % [lugar, (vias.get_parent() as Station).get_display_name()]
	var cerca: Interactable = Interactable.find_nearest(get_tree(), _player.global_position, _player)
	_hud.text = "%s\nLocomotora en: %s · %.0f km/h\n%s" % [
		CONTROLES, lugar, absf(_loco.speed) * 3.6, ("F: " + cerca.get_prompt()) if cerca != null else "",
	]


func _probar_cuentas() -> void:
	_comprobar(StationTracks.tracks_for_flows(0, 3, 2, 6) == 3 and StationTracks.tracks_for_flows(4, 3, 2, 6) == 3, "Ciudad: 3 vías hasta 4 flujos (2 por vía que no es la principal)")
	_comprobar(StationTracks.tracks_for_flows(5, 3, 2, 6) == 4 and StationTracks.tracks_for_flows(6, 3, 2, 6) == 4, "Con 5 y 6 flujos, 4 vías")
	_comprobar(StationTracks.tracks_for_flows(7, 3, 2, 6) == 5 and StationTracks.tracks_for_flows(20, 3, 2, 6) == 6, "Con 7 flujos 5 vías; nunca más de las de la plantilla")


func _probar_vias() -> void:
	var pueblo: Array[StationTrack] = _network.get_station_tracks(&"pueblo")
	_comprobar(pueblo.size() == 2 and pueblo[0].is_main() and pueblo[1].role == StationTrack.Role.SIDING, "El pueblo tiene vía principal y vía de cruce")
	_comprobar(pueblo[0].get_label() == "vía principal" and pueblo[1].get_label() == "vía de cruce", "Nombres de las vías del pueblo")
	var ciudad: Array[StationTrack] = _network.get_station_tracks(&"ciudad")
	_comprobar(ciudad.size() == 7 and _contar_habilitadas(ciudad) == 3, "La ciudad trae 6 vías y arranca con 3 habilitadas (más su cola de maniobras)")
	var maderera: Array[StationTrack] = _network.get_station_tracks(&"maderera")
	var roles: Array = maderera.map(func(via: StationTrack) -> int: return via.role)
	_comprobar(maderera.size() == 4 and _contar_habilitadas(maderera) == 3 and roles.has(StationTrack.Role.FREIGHT), "La maderera tiene principal, cruce y carga")
	_comprobar(not pueblo.any(func(via: StationTrack) -> bool: return via.role == StationTrack.Role.HEADSHUNT), "El pueblo no tiene cola de maniobras: le llegan tramos por las dos puntas")
	var cola_ciudad: StationTrack = ciudad.back()
	var cola_maderera: StationTrack = maderera.back()
	_comprobar(cola_ciudad.role == StationTrack.Role.HEADSHUNT and cola_ciudad.get_track_path().name == "ColaB" and cola_ciudad.get_label() == "cola de maniobras", "La ciudad tiene una cola de maniobras en la punta B, donde no llega ningún tramo")
	_comprobar(cola_maderera.get_track_path().name == "ColaA", "La maderera, en su punta A")
	var vias_ciudad := _ciudad.get_node(^"Vias") as StationTracks
	_comprobar(vias_ciudad.get_turntable(cola_ciudad.get_track_path()) != null and ($Pueblo.get_node(^"Vias") as StationTracks).turntable == false, "Al final de la cola de la ciudad hay mesa giratoria (en el pueblo no)")
	_comprobar(not ciudad[5].get_track_path().visible, "Una vía todavía no habilitada no se ve")

	_comprobar(_network.get_switches_at(&"pueblo").size() == 2 and _network.get_switches_at(&"ciudad").size() == 2 \
			and _network.get_switches_at(&"maderera").size() == 2, "Un cambio en cada punta: donde llega un tramo y donde está la cola de maniobras")
	var en_cola: TrackSwitch = _network.find_switch(cola_ciudad.get_track_path(), false)
	_comprobar(en_cola != null and en_cola.option_count() == 3, "De la cola de la ciudad se pasa a cualquiera de sus 3 vías")
	var en_pueblo: TrackSwitch = _network.find_switch(_cp, true)
	_comprobar(en_pueblo != null and en_pueblo.option_count() == 2 and en_pueblo.station_id == &"pueblo", "La punta del tramo c_p en el pueblo es la aguja de un cambio de dos salidas")
	var en_ciudad: TrackSwitch = _network.find_switch(_cp, false)
	_comprobar(en_ciudad != null and en_ciudad.option_count() == 3, "En la ciudad el cambio lleva a sus 3 vías habilitadas")
	var en_maderera: TrackSwitch = _network.find_switch(_pm, true)
	_comprobar(en_maderera != null and en_maderera.option_count() == 3, "En la maderera: principal, cruce y carga (la de carga con su propia entrada)")
	var todos_en_principal: bool = true
	for cambio: TrackSwitch in _network.get_switches():
		todos_en_principal = todos_en_principal and cambio.is_main_option(cambio.state)
	_comprobar(todos_en_principal, "Al empezar, todos los cambios están en la principal")
	_comprobar(_network.get_links(pueblo[0].get_track_path(), true).size() == 1, "Del lado de las vías de la estación, cada punta sigue por una sola vía")
	var avisos: PackedStringArray = _network.validate()
	_comprobar(avisos.is_empty(), "La red no tiene avisos (los tramos llegan a las puntas) %s" % str(avisos))
	_trains._update_signals()
	var cruce: Path3D = pueblo[1].get_track_path()
	_comprobar(_palanca(cruce, false) != null and _palanca(cruce, true) != null, "La vía de cruce tiene una palanca en cada punta, junto a su cartel")
	_comprobar(_trains.get_track_signal(pueblo[0], true) != null and _palanca(pueblo[0].get_track_path(), true) == null, "La principal tiene cartel pero no palanca")
	var madre := _network.get_node_or_null("PalancaMadre%d" % en_pueblo.id) as MotherLever
	_comprobar(madre != null and madre.global_position.distance_to(en_pueblo.point) < 6.0, "Cada cambio tiene su palanca madre junto a la aguja")


func _probar_palanca() -> void:
	var cambio: TrackSwitch = _network.find_switch(_cp, true)
	var palanca: TrackLever = _palanca(_cruce(&"pueblo").get_track_path(), true)
	if palanca == null:
		return
	_comprobar(palanca.get_prompt() == "Pedir paso por la vía de cruce", "La palanca dice qué hace: \"%s\"" % palanca.get_prompt())
	_comprobar(palanca.interact(_player) and (cambio.get_option_track(cambio.state) as StationTrack).role == StationTrack.Role.SIDING \
			and cambio.is_locked(), "Con F el cambio pasa a la vía de cruce y queda trabado")
	palanca.interact(_player)
	_comprobar(cambio.is_main_option(cambio.state) and not cambio.is_locked(), "Con F otra vez se cancela y el cambio vuelve a la principal")
	var madre := _network.get_node_or_null("PalancaMadre%d" % cambio.id) as MotherLever
	if madre == null:
		return
	_comprobar(madre.interact(_player) and (cambio.get_option_track(cambio.state) as StationTrack).role == StationTrack.Role.SIDING \
			and _network.is_track_reserved(_cruce(&"pueblo").get_track_path()), "La palanca madre reserva la vía de cruce para entrar")
	madre.interact(_player)
	_comprobar(cambio.is_main_option(cambio.state) and not cambio.is_locked(), "Con F otra vez vuelve a la principal")


func _probar_tren() -> void:
	var cambio_b: TrackSwitch = _network.find_switch(_cp, true)
	var cambio_a: TrackSwitch = _network.find_switch(_pm, false)
	# 1. Pasa el pueblo por la principal y sigue a p_m.
	var pisadas: Dictionary = _manejar(1.0, func() -> bool: return _loco.get_parent() == _pm and _flatcar.get_parent() == _pm, 40.0)
	_comprobar(pisadas.has("Principal") and not pisadas.has("Cruce1"), "Con los cambios en la principal, el tren cruza el pueblo por la principal")
	_comprobar(_loco.get_parent() == _pm and _flatcar.get_parent() == _pm, "Del otro lado sigue por el tramo p_m (cambio tomado de talón)")
	_frenar()
	# 2. Vuelve marcha atrás por la vía de cruce: pide el paso en la punta A para entrar y en la B
	# para salir (tarea 61e.2). Cada vez que el tren termina de pasar, el cambio vuelve a la principal.
	var cruce: Path3D = _cruce(&"pueblo").get_track_path()
	_comprobar(_network.request_route(cruce, false) == "" and cambio_a.get_option_path(cambio_a.state) == cruce, "Con el tren lejos, pide el paso por la vía de cruce en la punta A (para entrar)")
	_trains._update_signals()
	pisadas = _manejar(-1.0, func() -> bool: return _flatcar.get_parent() == cruce and _flatcar.global_position.distance_to(cambio_b.point) < 60.0, 40.0)
	_frenar()
	_comprobar(pisadas.has("Cruce1") and not pisadas.has("Principal"), "Marcha atrás entra por la vía de cruce, como marca el cambio")
	_comprobar(not cambio_a.is_locked() and cambio_a.is_main_option(cambio_a.state), "Al terminar de entrar, el cambio de la punta A se soltó y volvió a la principal")
	_comprobar(_network.next_piece(cruce, true, _flatcar).is_empty(), "Sin pedir el paso en la punta B, el tren no talona el cambio puesto para la principal")
	_comprobar(_network.request_route(cruce, true) == "" and cambio_b.get_option_path(cambio_b.state) == cruce and cambio_b.is_locked(), "Pide el paso en la punta B (para salir): el cambio queda puesto hacia ella y trabado")
	_trains._update_signals()
	pisadas = _manejar(-1.0, func() -> bool: return _loco.get_parent() == _cp and _loco.global_position.distance_to(cambio_b.point) > 20.0, 40.0)
	_comprobar(_loco.get_parent() == _cp, "Y sale al tramo c_p por la otra punta")
	_frenar()
	_comprobar(not cambio_b.is_locked() and cambio_b.is_main_option(cambio_b.state), "Al terminar de pasar se suelta solo y el cambio vuelve a la principal")
	# 3. Se aleja y se acerca: a 25 m le piden el paso por la vía de cruce y vuelve a preguntar.
	_manejar(-1.0, func() -> bool: return _loco.global_position.distance_to(cambio_b.point) > 60.0, 30.0)
	_frenar()
	_manejar(1.0, func() -> bool: return _loco.global_position.distance_to(cambio_b.point) < 25.0, 30.0)
	_comprobar(_loco.get_route().has_path(_principal(&"pueblo").get_track_path()), "A menos de 30 m ya sumó la principal a su camino")
	_comprobar(_palanca(cruce, true).interact(_player) and cambio_b.get_option_path(cambio_b.state) == cruce, "Con el tren a 25 m, la palanca de la vía de cruce mueve el cambio")
	_comprobar(not _loco.get_route().has_path(_principal(&"pueblo").get_track_path()), "Al moverse el cambio, el tren olvida la principal")
	# Las lambdas copian las variables locales: el diccionario se comparte.
	var visto: Dictionary = {"encima": false}
	pisadas = _manejar(1.0, func() -> bool:
		if _loco.global_position.distance_to(cambio_b.point) < 3.0 and not visto.encima:
			visto.encima = true
			_comprobar(not cambio_b.set_state(1 - cambio_b.state) and cambio_b.is_fouled(), "Con la locomotora encima, el cambio no se mueve")
		return _loco.get_parent().name == "Cruce1" and _flatcar.get_parent().name == "Cruce1", 30.0)
	_comprobar(visto.encima and pisadas.has("Cruce1") and _loco.get_parent().name == "Cruce1", "Entra a la vía de cruce")
	_frenar()


func _probar_desacople() -> void:
	var enganche := _loco.get_node(^"Enganche") as Coupler
	_comprobar(enganche != null and enganche.can_interact(_player) and enganche.get_prompt() == "Desacoplar", "Con el tren quieto, el enganche de la locomotora se puede usar")
	_comprobar(not (_flatcar.get_node(^"Enganche") as Coupler).can_interact(_player), "El de la plataforma no (no tiene nada atrás)")
	_comprobar(enganche.interact(_player) and _loco.rear == null and _flatcar.front == null, "Con F se desacopla la plataforma")
	_comprobar(_loco.couple(_flatcar), "Se vuelve a acoplar")
	_loco.automatic = true
	_comprobar(not enganche.can_interact(_player), "En un tren automático el enganche no se usa")
	_loco.automatic = false
	_loco.speed = 3.0
	_comprobar(not enganche.can_interact(_player), "Con el tren andando tampoco")
	_loco.speed = 0.0


func _probar_crecimiento() -> void:
	var vias := _ciudad.get_node(^"Vias") as StationTracks
	for i: int in 5:
		GameState.production.add_flow(&"ciudad", &"pueblo", &"log", 1)
	vias.refresh_enabled()
	_comprobar(vias.get_enabled_count() == 4 and _contar_habilitadas(_network.get_station_tracks(&"ciudad")) == 4, "Con 5 flujos la ciudad habilita su cuarta vía")
	_comprobar(_network.find_switch(_cp, false).option_count() == 4, "Y el cambio de la punta ya lleva a ella")
	for flujo: ProductionFlow in GameState.production.get_flows():
		GameState.production.remove_flow(flujo)
	vias.refresh_enabled()
	_comprobar(vias.get_enabled_count() == 4, "Si se van flujos, la vía queda (no se achica)")


func _preparar_para_jugar() -> void:
	for cambio: TrackSwitch in _network.get_switches():
		for i: int in cambio.option_count():
			if cambio.is_main_option(i):
				cambio.set_state(i, true)
				break
	_loco.place_on(_cp, 60.0)
	_loco.speed = 0.0
	_loco.throttle = 0.0
	_loco.brake = 0.0
	_player.global_position = _loco.global_position + Vector3(-4.0, 0.0, -5.0)


# Maneja el tren (W o S) paso a paso hasta que se cumpla `listo` o pasen `maximo` segundos.
# Devuelve los nombres de las curvas que pisó la locomotora o la plataforma.
func _manejar(acelerador: float, listo: Callable, maximo: float) -> Dictionary:
	var pisadas: Dictionary = {}
	_loco.brake = 0.0
	_loco.throttle = acelerador
	var tiempo: float = 0.0
	while tiempo < maximo and not listo.call():
		_loco.simulate(PASO_S)
		_network.update_locks()
		tiempo += PASO_S
		pisadas[String(_loco.get_parent().name)] = true
		pisadas[String(_flatcar.get_parent().name)] = true
	return pisadas


func _frenar() -> void:
	_loco.throttle = 0.0
	_loco.brake = 1.0
	for _i: int in 600:
		if is_zero_approx(_loco.speed):
			break
		_loco.simulate(PASO_S)
	_loco.brake = 0.0


func _principal(station: StringName) -> StationTrack:
	for via: StationTrack in _network.get_station_tracks(station):
		if via.is_main():
			return via
	return null


func _palanca(path: Path3D, at_end: bool) -> TrackLever:
	var cartel: RailSignal = _trains.get_track_signal(RailNetwork.track_of(path) as StationTrack, at_end)
	return cartel.get_node_or_null(^"Palanca") as TrackLever if cartel != null else null


func _cruce(station: StringName) -> StationTrack:
	for via: StationTrack in _network.get_station_tracks(station):
		if via.role == StationTrack.Role.SIDING:
			return via
	return null


func _contar_habilitadas(vias: Array[StationTrack]) -> int:
	var total: int = 0
	for via: StationTrack in vias:
		if via.enabled and via.role != StationTrack.Role.HEADSHUNT:
			total += 1
	return total


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
