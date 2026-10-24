extends Node3D
## Prueba de la tarea 54: RailNetwork (D78), vía doble (D81) y trenes que pasan de un tramo a otro.
## Primero prueba el grafo con una red armada por código (con un cruce) y la TrainRoute; después,
## en la escena, corre los trenes paso a paso (sin esperar cuadros):
## ciudad ==(a_b, vía doble: Ida y Vuelta)== pueblo --(b_c)-- maderera --(c_d, cortado)-- depósito.
## Al final, con cuadros de física reales, el jugador va parado en la plataforma mientras cruza
## el pueblo (cambia de curva): no toques nada durante unos 5 segundos.
## Al terminar se puede jugar: en la ciudad, la locomotora sola y detrás dos plataformas sueltas.

const CONTROLES: String = "WASD: caminar · F: cabina · K: cortar o abrir c_d · J: cortar o abrir b_c · U: desacoplar el último vagón\nLa locomotora mira al pueblo; atrás, hacia la ciudad, hay dos plataformas sueltas: acoplalas marcha atrás (S en la cabina)."
const PASO_S: float = 1.0 / 60.0
## Sobre el piso de la plataforma, hacia la cola.
const SOBRE_LA_PLATAFORMA_LOCAL: Vector3 = Vector3(0.0, 0.85, 3.0)
## En el piso, al lado de la rampa derecha de la cabina.
const JUNTO_A_LA_RAMPA_LOCAL: Vector3 = Vector3(4.0, 0.2, 2.5)
## Dentro de la cabina, a medio metro del puesto.
const CERCA_DEL_PUESTO_LOCAL: Vector3 = Vector3(0.4, 0.85, 2.1)

@onready var _network: RailNetwork = $RailNetwork
@onready var _ida: Path3D = $Ida
@onready var _vuelta: Path3D = $Vuelta
@onready var _bc: Path3D = $PuebloMaderera
@onready var _cd: Path3D = $Cortado
@onready var _loco: Vehicle = $Ida/Locomotive
@onready var _flatcar: Wagon = $Ida/Flatcar
@onready var _loco2: Vehicle = $PuebloMaderera/Locomotive2
@onready var _suelta: Wagon = $PuebloMaderera/PlataformaSuelta
@onready var _player: Player = $Player
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0
var _avisos: Array = []


func _ready() -> void:
	EventBus.segment_state_changed.connect(_on_segment_state_changed)
	_probar_grafo()
	_probar_ruta()
	# couple_on_start y el armado de la red son diferidos: al terminar el primer cuadro ya están.
	await get_tree().process_frame
	await get_tree().physics_frame
	_probar_red_de_la_escena()
	_probar_trenes()
	await _probar_jugador_cruzando()

	if _fallos == 0:
		print("Red ferroviaria: todas las comprobaciones pasaron.")
	else:
		push_error("Red ferroviaria: fallaron %d comprobaciones." % _fallos)
	await _preparar_para_jugar()


func _unhandled_input(event: InputEvent) -> void:
	var tecla := event as InputEventKey
	if tecla == null or not tecla.pressed or tecla.echo:
		return
	match tecla.physical_keycode:
		KEY_K:
			_alternar(&"c_d")
		KEY_J:
			_alternar(&"b_c")
		KEY_U:
			var ultimo: Vehicle = _loco.get_tail()
			if ultimo != _loco:
				ultimo.front.uncouple_rear()


func _process(_delta: float) -> void:
	var tramos: PackedStringArray = []
	for id: StringName in [&"a_b", &"b_c", &"c_d"]:
		tramos.append("%s %s" % [id, TrackSegment.state_name(_network.get_state(id))])
	var tren: PackedStringArray = []
	for vehiculo: Vehicle in _loco.get_train():
		tren.append("%s (%s)" % [vehiculo.name, vehiculo.get_parent().name])
	_hud.text = "%s\nTramos: %s\nTren: %s · %.0f km/h" % [
		CONTROLES, " · ".join(tramos), " + ".join(tren), absf(_loco.speed) * 3.6,
	]


# Red de prueba sin escena: X ==(xy, doble)== Y, y en Y un cruce hacia Z (yz) y hacia W (yw,
# dibujada de W a Y); Z --(zw, cortado)-- W.
func _probar_grafo() -> void:
	var red := RailNetwork.new()
	var xy1: TrackSegment = _via(&"xy", &"X", &"Y", 100.0)
	var xy2: TrackSegment = _via(&"xy", &"Y", &"X", 100.0)
	var yz: TrackSegment = _via(&"yz", &"Y", &"Z", 50.0)
	var yw: TrackSegment = _via(&"yw", &"W", &"Y", 80.0)
	var zw: TrackSegment = _via(&"zw", &"Z", &"W", 10.0)
	zw.state = TrackSegment.State.CUT
	var sin_datos: TrackSegment = _via(&"", &"X", &"Z", 5.0)
	for via: TrackSegment in [xy1, xy2, yz, yw, zw, sin_datos]:
		red.add_track(via)

	_comprobar(red.get_station_ids().size() == 4 and red.get_segment_ids().size() == 4, "4 estaciones y 4 tramos (la vía sin tramo queda afuera)")
	_comprobar(red.is_double(&"xy") and not red.is_double(&"yz"), "xy tiene vía doble y yz simple")
	var en_y: Array[StringName] = red.get_segments_at(&"Y")
	_comprobar(en_y.size() == 3 and en_y.has(&"xy") and en_y.has(&"yz") and en_y.has(&"yw"), "A Y llegan tres tramos")
	_comprobar(red.other_end(&"yw", &"Y") == &"W" and red.other_end(&"yw", &"X") == &"", "El otro extremo de yw desde Y es W")
	_comprobar(is_equal_approx(red.get_segment_length(&"yz"), 50.0), "El largo del tramo sale de su curva")

	# Caminos: nunca por un tramo cortado.
	_comprobar(red.find_route(&"X", &"W") == ([&"xy", &"yw"] as Array[StringName]), "De X a W: xy y yw")
	_comprobar(red.find_route(&"Z", &"W") == ([&"yz", &"yw"] as Array[StringName]), "De Z a W da la vuelta porque zw está cortado")
	red.set_state(&"zw", TrackSegment.State.OPEN)
	_comprobar(red.find_route(&"Z", &"W") == ([&"zw"] as Array[StringName]), "Con zw abierto, va directo (es más corto)")
	red.set_state(&"yw", TrackSegment.State.CUT)
	red.set_state(&"zw", TrackSegment.State.CUT)
	_comprobar(not red.are_connected(&"X", &"W") and red.are_connected(&"X", &"Z"), "Con yw y zw cortados, W queda aislada")
	_comprobar(red.find_route(&"X", &"X").is_empty() and red.are_connected(&"X", &"X"), "Una estación está conectada consigo misma")
	red.set_state(&"yw", TrackSegment.State.OPEN)

	# Por dónde sigue un tren al llegar a una estación.
	_comprobar(red.next_track(xy1, &"Y") == null, "En el cruce de Y sin destino, se frena")
	_comprobar(red.next_track(xy1, &"Y", &"Z") == yz and red.next_track(xy1, &"Y", &"W") == yw, "Con destino, toma el tramo del camino")
	_comprobar(red.next_track(yz, &"Y", &"X") == xy2, "Hacia X por la vía doble, usa la que sale de Y")
	_comprobar(red.next_track(yw, &"Y", &"X") == xy2 and red.track_leaving(&"xy", &"X") == xy1, "Cada sentido tiene su vía")
	_comprobar(red.next_track(yz, &"Z") == null, "En Z sigue zw, que está cortado: se frena")
	red.set_state(&"zw", TrackSegment.State.OPEN)
	_comprobar(red.next_track(yz, &"Z") == zw and red.next_track(yw, &"W") == zw, "Con zw abierto, sigue por él")
	_comprobar(red.next_track(xy2, &"X") == null, "X es punta de línea")

	# El estado es uno por tramo, aunque tenga dos vías.
	_avisos.clear()
	red.set_state(&"xy", TrackSegment.State.CUT)
	_comprobar(xy1.is_cut() and xy2.is_cut(), "Cortar un tramo corta sus dos vías")
	_comprobar(_avisos == [[&"xy", TrackSegment.State.CUT]], "Y se avisa una vez por EventBus.segment_state_changed")
	xy2.state = TrackSegment.State.IMPROVED
	_comprobar(xy1.state == TrackSegment.State.IMPROVED and red.get_state(&"xy") == TrackSegment.State.IMPROVED, "Cambiar una vía a mano copia el estado a la otra")
	xy1.condition = 0.3
	_comprobar(is_equal_approx(xy1.get_effective_condition(), 1.0), "Mejorado anda como vía perfecta")
	_comprobar(red.get_state(&"nada") == TrackSegment.State.CUT and not red.set_state(&"nada", TrackSegment.State.OPEN), "Un tramo que no existe cuenta como cortado")
	_comprobar(TrackSegment.state_name(TrackSegment.State.CUT) == "cortado", "Nombre del estado")

	red.clear()
	red.free()
	for via: TrackSegment in [xy1, xy2, yz, yw, zw, sin_datos]:
		via.get_parent().free()


func _probar_ruta() -> void:
	var p1: Path3D = _curva_recta(100.0)
	var p2: Path3D = _curva_recta(50.0)
	var p0: Path3D = _curva_recta(40.0)
	var ruta := TrainRoute.new()
	ruta.reset(p1, 1, 80.0)
	_comprobar(is_equal_approx(ruta.head, 80.0) and is_equal_approx(ruta.get_length(), 100.0), "Ruta de una curva: la cabeza en su avance")
	ruta.push_front(p2, -1)
	var lugar: Array = ruta.locate(120.0)
	_comprobar(lugar[0] == 1 and is_equal_approx(lugar[1], 30.0), "20 m dentro de una curva dada vuelta es su avance 30")
	_comprobar(is_equal_approx(ruta.coordinate_of(p2, 30.0), 120.0) and is_nan(ruta.coordinate_of(p0, 0.0)), "coordinate_of es la inversa de locate")
	ruta.push_back(p0, 1)
	_comprobar(is_equal_approx(ruta.head, 120.0) and is_equal_approx(ruta.coordinate_of(p1, 80.0), 120.0), "Sumar atrás corre las coordenadas")
	ruta.reset(p1, -1, 80.0)
	_comprobar(is_equal_approx(ruta.head, 20.0), "Mirando al principio de la curva, la coordenada crece hacia el avance 0")
	for curva: Path3D in [p0, p1, p2]:
		curva.free()


func _probar_red_de_la_escena() -> void:
	_comprobar(RailNetwork.find_in(get_tree()) == _network, "La escena tiene su RailNetwork")
	_comprobar(_network.get_station_ids().size() == 4 and _network.is_double(&"a_b"), "Armó 4 estaciones y a_b tiene vía doble")
	_comprobar(_network.is_cut(&"c_d") and _network.validate().is_empty(), "c_d arranca cortado y la red no tiene problemas")
	_comprobar(_flatcar.front == _loco, "La plataforma está acoplada a la locomotora")


# Con la simulación de los vehículos apagada: cada paso se da a mano con simulate().
func _probar_trenes() -> void:
	for vehiculo: Vehicle in [_loco, _flatcar, _loco2, _suelta]:
		vehiculo.set_physics_process(false)
	var largo_vuelta: float = _vuelta.curve.get_baked_length()
	var largo_bc: float = _bc.curve.get_baked_length()
	var largo_cd: float = _cd.curve.get_baked_length()

	# Vía doble: la locomotora 2, en b_c mirando al pueblo, vuelve a la ciudad por la Vuelta.
	_poner(_loco2, 60.0, 5.0)
	_simular([_loco2], 4.0)
	_comprobar(_loco2.get_parent() == _bc and _loco2.reversed, "Va por b_c dada vuelta (la curva está dibujada del pueblo a la maderera)")
	_simular([_loco2], 60.0)
	_comprobar(_loco2.get_parent() == _vuelta and not _loco2.reversed, "En el pueblo pasó a la Vuelta (la vía de a_b que sale del pueblo)")
	_comprobar(is_equal_approx(_loco2.progress, largo_vuelta - 5.0) and is_zero_approx(_loco2.speed), "Se frenó con la punta al final, en la ciudad")
	var frente: Vector3 = -_loco2.global_basis.z
	_comprobar(frente.dot(Vector3.BACK) > 0.99, "Y mira hacia la ciudad")
	_loco2.get_parent().remove_child(_loco2)
	_loco2.queue_free()

	# Un vehículo parado del otro lado de la estación frena al tren a 0,6 m, aunque estén en
	# curvas distintas; el tren queda repartido entre las dos.
	_suelta.progress = 15.0
	_poner(_loco, 60.0, 6.0)
	_simular([_loco, _suelta], 40.0)
	_comprobar(_loco.get_parent() == _bc and _flatcar.get_parent() == _ida, "El tren cruzó el pueblo: la locomotora en b_c y la plataforma todavía en la Ida")
	var hueco: float = (_suelta.progress - 5.0) - (_loco.progress + 5.0)
	_comprobar(is_equal_approx(hueco, Vehicle.COUPLING_GAP) and is_zero_approx(_loco.speed), "Frenó con 0,6 m de hueco contra la plataforma suelta (%.2f m)" % hueco)
	_comprobar(is_equal_approx(_flatcar.progress, 150.0 - 6.2), "La plataforma quedó a 10,6 m, del otro lado de la estación (%.2f)" % _flatcar.progress)
	_comprobar(_suelta.front == null, "De frente no se acopla")

	# Marcha atrás hacia la ciudad: la cola entra a la Vuelta (la del sentido de la marcha) y se
	# acopla a la suelta que está ahí.
	_loco.place_on(_bc, 40.0)
	_comprobar(_flatcar.get_parent() == _bc and is_equal_approx(_flatcar.progress, 29.4), "place_on lleva el tren entero a b_c")
	_suelta.place_on(_vuelta, 20.0, true)
	_poner(_loco, 40.0, -6.0)
	_simular([_loco, _suelta], 30.0)
	_comprobar(_flatcar.rear == _suelta and _loco.get_train().size() == 3, "Marcha atrás pasó a la Vuelta y se acopló a la suelta")
	var ruta: TrainRoute = _loco.get_route()
	var entre: float = ruta.coordinate_of(_flatcar.get_parent() as Path3D, _flatcar.progress) - ruta.coordinate_of(_suelta.get_parent() as Path3D, _suelta.progress)
	_comprobar(is_equal_approx(entre, 10.6), "Acoplada a 10,6 m sobre la ruta (%.2f)" % entre)

	# Hacia la maderera: c_d está cortado, así que se frena al final de b_c.
	_poner(_loco, _loco.progress, 6.0)
	_simular([_loco], 80.0)
	_comprobar(_loco.get_parent() == _bc and is_equal_approx(_loco.progress, largo_bc - 5.0) and is_zero_approx(_loco.speed), "No entra a c_d (cortado): frena con la punta en la maderera")
	_comprobar(_suelta.get_parent() == _bc and not _suelta.reversed, "La suelta salió de la Vuelta detrás del tren y ya no va dada vuelta")

	# Se abre c_d: avisa y el tren sigue hasta el depósito (punta de línea).
	_avisos.clear()
	_network.set_state(&"c_d", TrackSegment.State.OPEN)
	_comprobar(_avisos == [[&"c_d", TrackSegment.State.OPEN]], "Abrir c_d se avisa por EventBus")
	_poner(_loco, _loco.progress, 6.0)
	_simular([_loco], 40.0)
	_comprobar(_loco.get_parent() == _cd and is_equal_approx(_loco.progress, largo_cd - 5.0), "Con c_d abierto llega al depósito")
	_comprobar(_loco.get_route().get_piece_count() <= 2, "La ruta se olvida de lo que quedó lejos (%d curvas)" % _loco.get_route().get_piece_count())

	# Marcha atrás hasta la ciudad: en el pueblo la cola toma la Vuelta.
	_poner(_loco, _loco.progress, -6.0)
	_simular([_loco], 120.0)
	_comprobar(_suelta.get_parent() == _vuelta and _suelta.reversed and is_equal_approx(_suelta.progress, largo_vuelta - 5.0), "Marcha atrás llegó a la ciudad por la Vuelta, con la cola en el tope")

	# Con b_c cortado no se sale del pueblo, tampoco con el tren entero sobre a_b.
	_network.set_state(&"b_c", TrackSegment.State.CUT)
	_poner(_loco, _loco.progress, 6.0)
	_simular([_loco], 60.0)
	_comprobar(_loco.get_parent() == _vuelta and is_equal_approx(_loco.progress, 5.0), "Con b_c cortado frena en el pueblo, al final de la Vuelta")
	_network.set_state(&"b_c", TrackSegment.State.OPEN)

	# Mejorado: la velocidad sale de la vía perfecta aunque la condición sea baja.
	var via: TrackSegment = RailNetwork.track_of(_vuelta)
	via.condition = 0.5
	var abierto: float = _loco.get_max_speed()
	_network.set_state(&"a_b", TrackSegment.State.IMPROVED)
	_comprobar(_loco.get_max_speed() > abierto and is_equal_approx(_loco.get_track_condition(), 1.0), "Un tramo mejorado deja ir más rápido (%.1f > %.1f m/s)" % [_loco.get_max_speed(), abierto])
	_network.set_state(&"a_b", TrackSegment.State.OPEN)
	via.condition = 1.0

	# Ida y vuelta: va al pueblo por la Ida y, marcha atrás, vuelve por la Vuelta (su sentido),
	# aunque recuerde que vino por la Ida.
	_loco.place_on(_ida, 100.0)
	_poner(_loco, 100.0, 0.0)
	_loco.throttle = 1.0
	_simular([_loco], 15.0)
	_comprobar(_suelta.get_parent() == _bc, "El tren entero pasó a b_c")
	_poner(_loco, _loco.progress, -6.0)
	_simular([_loco], 60.0)
	_comprobar(_suelta.get_parent() == _vuelta and _loco.get_parent() == _vuelta, "Marcha atrás desde b_c vuelve a la ciudad por la Vuelta, no por la Ida")

	for vehiculo: Vehicle in [_loco, _flatcar, _suelta]:
		vehiculo.set_physics_process(true)


# El jugador parado en la plataforma sigue con ella cuando cambia de curva en el pueblo.
func _probar_jugador_cruzando() -> void:
	_flatcar.uncouple_rear()
	_suelta.place_on(_bc, 140.0)
	_loco.place_on(_ida, 125.0)
	_loco.speed = 8.0
	_loco.throttle = 8.0 / _loco.get_max_speed()
	_player.global_position = _flatcar.global_transform * SOBRE_LA_PLATAFORMA_LOCAL
	_player.velocity = Vector3.ZERO
	await _esperar(20)
	var antes: Vector3 = _flatcar.global_transform.affine_inverse() * _player.global_position
	_comprobar(_player.get_platform() == _flatcar, "El jugador va enganchado a la plataforma")
	for _i: int in 400:
		if _flatcar.get_parent() == _bc:
			break
		await get_tree().physics_frame
	await _esperar(60)
	var despues: Vector3 = _flatcar.global_transform.affine_inverse() * _player.global_position
	_comprobar(_flatcar.get_parent() == _bc and _player.get_platform() == _flatcar, "La plataforma pasó a b_c y el jugador sigue enganchado")
	_comprobar(antes.distance_to(despues) < 0.3, "Y sigue en el mismo lugar de la plataforma (se movió %.2f m)" % antes.distance_to(despues))

	# Manejando desde la cabina: la cámara sigue siendo la de la cabina al cambiar de curva.
	_loco.place_on(_ida, 125.0)
	_loco.speed = 0.0
	_loco.throttle = 0.0
	# El tren saltó de lugar: se espera un cuadro para que el jugador se suelte de la plataforma.
	await _esperar(2)
	_player.global_position = _loco.global_transform * CERCA_DEL_PUESTO_LOCAL
	_player.velocity = Vector3.ZERO
	await _esperar(20)
	var cabina: Cab = _loco.get_node("Cab")
	_comprobar(_player.try_enter_cab(), "Entra a la cabina")
	cabina.set_notch(4)
	for _i: int in 400:
		if _loco.get_parent() == _bc:
			break
		await get_tree().physics_frame
	await _esperar(10)
	_comprobar(_loco.get_parent() == _bc and get_viewport().get_camera_3d() == cabina.get_camera() and _player.is_in_cab(), "La locomotora pasó a b_c y se sigue viendo desde la cabina")
	cabina.set_notch(0)
	_player.exit_cab()
	_loco.brake = 1.0
	await _esperar(5)
	_loco.brake = 0.0


# Al terminar: en la ciudad, la locomotora sola mirando al pueblo y las dos plataformas sueltas
# detrás (hacia la ciudad), para acoplarlas marcha atrás. El jugador, al lado de la cabina.
func _preparar_para_jugar() -> void:
	_flatcar.uncouple_rear()
	_loco.uncouple_rear()
	for vehiculo: Vehicle in [_loco, _flatcar, _suelta]:
		vehiculo.speed = 0.0
		vehiculo.throttle = 0.0
		vehiculo.brake = 0.0
	_loco.place_on(_ida, 50.0)
	_flatcar.place_on(_ida, 30.0)
	_suelta.place_on(_ida, 12.0)
	_network.set_state(&"c_d", TrackSegment.State.CUT)
	_network.set_state(&"b_c", TrackSegment.State.OPEN)
	# El jugador puede haber quedado enganchado a un vagón que acaba de saltar de lugar: primero
	# se lo baja a un lugar vacío, y recién cuando se soltó se lo pone al lado de la cabina.
	_player.global_position = Vector3(-20.0, 0.2, -40.0)
	_player.velocity = Vector3.ZERO
	await _esperar(3)
	_player.global_position = _loco.global_transform * JUNTO_A_LA_RAMPA_LOCAL
	_player.velocity = Vector3.ZERO


func _alternar(segmento: StringName) -> void:
	var cortado: bool = _network.is_cut(segmento)
	_network.set_state(segmento, TrackSegment.State.OPEN if cortado else TrackSegment.State.CUT)


func _on_segment_state_changed(segment_id: StringName, state: int) -> void:
	_avisos.append([segment_id, state])


# Una vía suelta (con su curva recta) para armar redes por código.
func _via(id: StringName, desde: StringName, hasta: StringName, largo: float) -> TrackSegment:
	var curva: Path3D = _curva_recta(largo)
	var via := TrackSegment.new()
	via.segment_id = id
	via.from_station = desde
	via.to_station = hasta
	curva.add_child(via)
	return via


func _curva_recta(largo: float) -> Path3D:
	var curva := Path3D.new()
	curva.curve = Curve3D.new()
	curva.curve.add_point(Vector3.ZERO)
	curva.curve.add_point(Vector3(0.0, 0.0, -largo))
	return curva


func _poner(vehiculo: Vehicle, avance: float, velocidad: float) -> void:
	vehiculo.progress = avance
	vehiculo.speed = velocidad
	vehiculo.throttle = signf(velocidad) if not is_zero_approx(velocidad) else 0.0
	vehiculo.place_rear_vehicles()


# Los vehículos de `cabezas` simulan en orden; los acoplados detrás los ubica su cabeza.
func _simular(cabezas: Array, segundos: float) -> void:
	for _i: int in roundi(segundos / PASO_S):
		for vehiculo: Vehicle in cabezas:
			if is_instance_valid(vehiculo) and vehiculo.front == null:
				vehiculo.simulate(PASO_S)


func _esperar(cuadros: int) -> void:
	for _i: int in cuadros:
		await get_tree().physics_frame


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
