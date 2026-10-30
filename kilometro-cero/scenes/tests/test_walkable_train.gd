extends Node3D
## Prueba de las tareas 51 y 52: caminar dentro del tren en movimiento y manejarlo desde
## la cabina en 1ª persona (D84).
## Supone una vía con una recta de 120 m y después una curva hacia la derecha, la
## locomotora y una plataforma detrás. Desde la tarea 53 la plataforma va acoplada y se
## pasa de una a otra caminando por la pasarela.
## Las comprobaciones usan cuadros de física reales: durante unos 10 segundos el tren y el
## jugador se mueven solos (y el jugador salta de un lugar a otro); no toques nada.
## Después se puede jugar: se sube al tren por las rampas y se maneja desde la cabina (F).

const CONTROLES: String = "WASD: caminar · Shift: correr · Espacio: saltar · Ctrl: agacharse · F: entrar o salir de la cabina · Esc: soltar el mouse\nEn la cabina: W / S palanca · Espacio (mantener) freno · L luces · H bocina · mouse mirar\nSubí por las rampas del costado, caminá hasta el puesto (a la derecha, detrás del mando) y apretá F."
const INICIO_M: float = 30.0
## Avance donde empieza la curva de la vía de esta escena.
const CURVA_M: float = 118.0
## Sobre el pasillo derecho de la locomotora, entre la caldera y la baranda.
const PASILLO_LOCAL: Vector3 = Vector3(1.0, 0.85, -2.0)
## En el piso, al lado de la rampa derecha de la cabina.
const JUNTO_A_LA_RAMPA_LOCAL: Vector3 = Vector3(4.0, 0.2, 2.5)
## Dentro de la cabina, a medio metro del puesto.
const CERCA_DEL_PUESTO_LOCAL: Vector3 = Vector3(0.4, 0.85, 2.1)

@onready var _player: Player = $Player
@onready var _loco: Vehicle = $Track/Locomotive
@onready var _flatcar: Vehicle = $Track/Flatcar
@onready var _cab: Cab = $Track/Locomotive/Cab
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0
var _bocinazos: int = 0


func _ready() -> void:
	_hud.text = CONTROLES
	_comprobar(_loco.couple(_flatcar), "La plataforma se acopla detrás de la locomotora")
	# Durante las comprobaciones el mouse no gira la cámara: si no, moverlo cambia el
	# giro medido en la curva.
	_player.get_camera().set_process_unhandled_input(false)
	_cab.horn_sounded.connect(func() -> void: _bocinazos += 1)
	_probar_calculos()
	_probar_calculos_cabina()
	await _probar_parado_en_marcha()
	await _probar_curva()
	await _probar_salto()
	await _probar_pared()
	await _probar_pasar_a_la_plataforma()
	await _probar_bajar()
	await _probar_cabina()

	if _fallos == 0:
		print("Tren caminable: todas las comprobaciones pasaron.")
	else:
		push_error("Tren caminable: fallaron %d comprobaciones." % _fallos)

	# Dejamos todo detenido al principio, con el jugador al lado de la rampa.
	_cab.set_notch(0)
	_poner_tren(INICIO_M, 0.0)
	await _esperar(2)
	_player.global_position = _loco.global_transform * JUNTO_A_LA_RAMPA_LOCAL
	_player.velocity = Vector3.ZERO
	_player.get_camera().set_process_unhandled_input(true)


func _process(_delta: float) -> void:
	var plataforma: Vehicle = _player.get_platform()
	_hud.text = "%s\nMarcha: %s · Acelerador: %d %% · Freno: %s · Luces: %s · Velocidad: %.0f km/h\nEnganchado a: %s · En la cabina: %s" % [
		CONTROLES,
		Cab.notch_text(_cab.notch, _cab.forward_notches, _cab.reverse_notches),
		roundi(_loco.throttle * 100.0),
		"sí" if _cab.braking else "no",
		"sí" if _cab.lights_on else "no",
		absf(_loco.speed) * 3.6,
		String(plataforma.name) if plataforma != null else "nada",
		"sí" if _player.is_in_cab() else "no",
	]


func _probar_calculos() -> void:
	_comprobar(is_equal_approx(Player.yaw_delta(Basis(), Basis(Vector3.UP, 0.3)), 0.3), "Un giro de 0,3 rad a la izquierda mide 0,3")
	var cruzando_pi: float = Player.yaw_delta(Basis(Vector3.UP, 3.0), Basis(Vector3.UP, -3.0))
	_comprobar(is_equal_approx(cruzando_pi, TAU - 6.0), "Al cruzar ±180° se toma el camino corto (%.3f rad)" % cruzando_pi)
	var cuerpo := _loco.get_node("CuerpoFisico")
	_comprobar(Vehicle.find_owner_of(cuerpo) == _loco, "El cuerpo físico pertenece a la locomotora")
	_comprobar(Vehicle.find_owner_of($Ground) == null, "El piso no es un vehículo")
	_comprobar(Vehicle.find_owner_of(null) == null, "Sin nodo no hay vehículo")


func _probar_calculos_cabina() -> void:
	_comprobar(is_equal_approx(Cab.throttle_for_notch(2, 4, 2), 0.5), "Adelante 2 de 4 es medio acelerador")
	_comprobar(is_equal_approx(Cab.throttle_for_notch(-2, 4, 2), -1.0), "Atrás 2 de 2 es marcha atrás a fondo")
	_comprobar(is_zero_approx(Cab.throttle_for_notch(0, 4, 2)), "Punto muerto no acelera")
	_comprobar(Cab.clamp_notch(7, 4, 2) == 4 and Cab.clamp_notch(-5, 4, 2) == -2, "La palanca no pasa de sus topes")
	_comprobar(Cab.notch_text(-1, 4, 2) == "Atrás 1/2", "Nombre de la muesca")
	var lenta: float = _loco.data.coast_deceleration
	_comprobar(lenta < _loco.data.braking, "En punto muerto frena menos que con el freno (%.1f y %.1f m/s²)" % [lenta, _loco.data.braking])


func _probar_parado_en_marcha() -> void:
	_poner_tren(INICIO_M, 0.0)
	await _esperar(2)
	_player.global_position = _loco.global_transform * PASILLO_LOCAL
	_player.velocity = Vector3.ZERO
	await _esperar(20)
	_comprobar(_player.get_platform() == _loco, "Parado sobre la locomotora queda enganchado a ella")

	var antes: Vector3 = _posicion_local()
	var inicio: Vector3 = _loco.global_position
	_poner_velocidad(8.0)
	await _esperar(60)
	var recorrido: float = _loco.global_position.distance_to(inicio)
	_comprobar(recorrido > 7.0, "La locomotora avanzó (%.1f m)" % recorrido)
	var deslizamiento: float = _posicion_local().distance_to(antes)
	_comprobar(deslizamiento < 0.05, "En la recta a 8 m/s no se desliza (%.3f m)" % deslizamiento)


func _probar_curva() -> void:
	_poner_tren(CURVA_M, 10.0)
	await _esperar(2)
	var antes: Vector3 = _posicion_local()
	var giro_tren_antes: float = _loco.global_rotation.y
	var giro_camara_antes: float = _player.get_camera().yaw
	await _esperar(240)
	var giro_tren: float = angle_difference(giro_tren_antes, _loco.global_rotation.y)
	var giro_camara: float = angle_difference(giro_camara_antes, _player.get_camera().yaw)
	_comprobar(absf(giro_tren) > 0.3, "El tren giró en la curva (%.0f°)" % rad_to_deg(giro_tren))
	var deslizamiento: float = _posicion_local().distance_to(antes)
	_comprobar(deslizamiento < 0.1, "En la curva a 10 m/s no se desliza (%.3f m)" % deslizamiento)
	_comprobar(absf(giro_camara - giro_tren) < 0.03, "La cámara giró lo mismo que el tren (%.0f°)" % rad_to_deg(giro_camara))
	_comprobar(_player.get_platform() == _loco, "Sigue enganchado después de la curva")


# Se hace con el tren todavía andando en la curva.
func _probar_salto() -> void:
	var antes: Vector3 = _posicion_local()
	_comprobar(_player.jump(), "Puede saltar con el tren en marcha")
	var cuadros: int = 0
	while cuadros < 120:
		await get_tree().physics_frame
		cuadros += 1
		if cuadros > 5 and _player.is_on_floor():
			break
	var despues: Vector3 = _posicion_local()
	var corrimiento: float = Vector2(despues.x - antes.x, despues.z - antes.z).length()
	_comprobar(cuadros < 120, "Aterriza (%d cuadros en el aire)" % cuadros)
	_comprobar(corrimiento < 0.15, "Cae en el mismo lugar del vagón (%.3f m)" % corrimiento)
	_comprobar(_player.get_platform() == _loco, "Después del salto sigue enganchado a la locomotora")


# Con el tren en marcha atrás, la pared de atrás de la cabina va adelante: si el choque
# del tren llegara un paso tarde sin compensarlo, empujaría al jugador hacia adentro.
func _probar_pared() -> void:
	_poner_tren(INICIO_M, -10.0)
	await _esperar(2)
	_player.global_position = _loco.global_transform * Vector3(-1.0, 0.85, 3.5)
	_player.velocity = Vector3.ZERO
	await _esperar(10)
	_mirar_hacia_atras_del_tren()
	Input.action_press(&"move_forward")
	await _esperar(60)
	Input.action_release(&"move_forward")
	# La pared está en z = 4,4 (cara interna) y la cápsula tiene 0,35 m de radio.
	var z: float = _posicion_local().z
	_comprobar(z > 3.95 and z < 4.08, "A 10 m/s, contra la pared de la cabina queda apoyado sin atravesarla ni rebotar (z = %.3f)" % z)
	_poner_velocidad(0.0)


# Camina, sin saltar, desde la puerta de atrás de la cabina hasta la plataforma por la
# pasarela, con el tren andando (tarea 53).
func _probar_pasar_a_la_plataforma() -> void:
	_poner_tren(INICIO_M, 6.0)
	await _esperar(2)
	_comprobar(_loco.get_node("Visual/Pasarela").visible and _flatcar.front == _loco, "Acoplada, la locomotora muestra su pasarela")
	_comprobar(not _flatcar.get_node("Visual/Pasarela").visible, "La plataforma, sin nada atrás, no")
	var hueco: float = (_loco.global_position - _flatcar.global_position).length() - Vehicle.coupling_distance(_loco.data.length, _flatcar.data.length)
	_comprobar(absf(hueco) < 0.01, "Quedan a la distancia de acople (error %.3f m)" % hueco)
	_player.global_position = _loco.global_transform * Vector3(0.0, 0.85, 3.6)
	_player.velocity = Vector3.ZERO
	await _esperar(10)
	_mirar_hacia_atras_del_tren()
	Input.action_press(&"move_forward")
	var altura_minima: float = INF
	for _i: int in 180:
		await get_tree().physics_frame
		altura_minima = minf(altura_minima, _posicion_local().y)
		if _player.get_platform() == _flatcar:
			break
	Input.action_release(&"move_forward")
	_comprobar(_player.get_platform() == _flatcar, "Caminando por la pasarela llegó a la plataforma y quedó enganchado a ella")
	_comprobar(altura_minima > 0.7, "No cayó en el hueco (altura mínima %.2f m)" % altura_minima)
	await _esperar(30)
	_comprobar(_player.get_platform() == _flatcar, "Sigue sobre la plataforma con el tren andando")
	_poner_velocidad(0.0)


func _probar_bajar() -> void:
	_poner_velocidad(0.0)
	await _esperar(2)
	# Lo dejamos en el piso al costado de la vía.
	_player.global_position = _loco.global_transform * Vector3(6.0, 0.5, 0.0)
	_player.velocity = Vector3.ZERO
	await _esperar(30)
	_comprobar(_player.get_platform() == null, "En el piso se desengancha del tren")
	var quieto: Vector3 = _player.global_position
	_poner_velocidad(8.0)
	await _esperar(30)
	_comprobar(_player.global_position.distance_to(quieto) < 0.02, "Desenganchado, el tren se va sin llevarlo")
	_poner_velocidad(0.0)


func _probar_cabina() -> void:
	_poner_tren(INICIO_M, 0.0)
	_cab.set_notch(0)
	await _esperar(2)
	# Desde el piso, al lado de la locomotora, no se entra.
	_player.global_position = _loco.global_transform * JUNTO_A_LA_RAMPA_LOCAL
	_player.velocity = Vector3.ZERO
	await _esperar(20)
	_comprobar(not _player.try_enter_cab(), "Desde el piso no se entra a la cabina")
	# En el pasillo de adelante, lejos del puesto, tampoco.
	_player.global_position = _loco.global_transform * PASILLO_LOCAL
	_player.velocity = Vector3.ZERO
	await _esperar(20)
	_comprobar(not _player.try_enter_cab(), "Lejos del puesto no se entra")

	_player.global_position = _loco.global_transform * CERCA_DEL_PUESTO_LOCAL
	_player.velocity = Vector3.ZERO
	await _esperar(20)
	_comprobar(_player.get_platform() == _loco, "Parado en la cabina va enganchado a la locomotora")
	await _tocar(&"interact")
	_comprobar(_player.is_in_cab() and _cab.get_occupant() == _player, "F entra a la cabina")
	_comprobar(get_viewport().get_camera_3d() == _cab.get_camera(), "La cámara pasa a la de la cabina")
	_comprobar(not _player.get_node("Visual").visible, "El cuerpo se esconde")
	var puesto: Vector3 = _loco.global_transform.affine_inverse() * _cab.global_position
	_comprobar(_posicion_local().distance_to(puesto) < 0.01, "Queda parado en el puesto")

	await _enviar_accion(&"move_forward")
	await _enviar_accion(&"move_forward")
	# Desde la 62b.5 cada muesca pide una velocidad (adelante 2: 43 km/h de los 90 de la locomotora).
	_comprobar(_cab.notch == 2 and is_equal_approx(_loco.throttle, Cab.speed_fraction(_cab.forward_speeds_kmh, 2, _loco.data.max_speed)), "W dos veces: adelante 2, 43 km/h")
	await _esperar(120)
	_comprobar(_loco.speed > 1.0, "El tren arranca (%.1f m/s)" % _loco.speed)
	_comprobar(_posicion_local().distance_to(puesto) < 0.05, "Con el tren andando sigue en el puesto (%.3f m)" % _posicion_local().distance_to(puesto))

	await _enviar_accion(&"move_back")
	await _enviar_accion(&"move_back")
	var antes: float = _loco.speed
	await _esperar(60)
	_comprobar(_cab.notch == 0 and _loco.speed < antes and _loco.speed > antes - 0.6, "En punto muerto rueda y frena despacio (%.2f → %.2f m/s)" % [antes, _loco.speed])

	Input.action_press(&"jump")
	var cuadros: int = 0
	while cuadros < 300 and _loco.speed > 0.0:
		await get_tree().physics_frame
		cuadros += 1
	_comprobar(_cab.braking and is_zero_approx(_loco.speed), "Espacio frena hasta detener el tren (%d cuadros)" % cuadros)
	_comprobar(_player.is_in_cab() and _player.velocity.is_zero_approx(), "En la cabina Espacio no hace saltar")
	Input.action_release(&"jump")
	await _esperar(2)
	_comprobar(not _cab.braking and is_zero_approx(_loco.brake), "Al soltar Espacio se suelta el freno")

	await _enviar_accion(&"move_back")
	_comprobar(_cab.notch == -1 and _loco.throttle < 0.0, "S desde punto muerto pone marcha atrás")
	await _enviar_accion(&"move_forward")

	await _enviar_accion(&"lights")
	_comprobar(_cab.lights_on and _loco.get_node("Faro").visible, "L prende el faro")
	await _enviar_accion(&"lights")
	_comprobar(not _loco.get_node("Faro").visible, "L otra vez lo apaga")
	await _enviar_accion(&"horn")
	_comprobar(_bocinazos == 1, "H toca la bocina")

	_player.set_controls_enabled(false)
	await _enviar_accion(&"move_forward")
	_comprobar(_cab.notch == 0, "Con el inventario abierto la palanca no se mueve")
	_player.set_controls_enabled(true)

	await _tocar(&"interact")
	_comprobar(not _player.is_in_cab() and not _cab.is_occupied(), "F otra vez sale de la cabina")
	_comprobar(get_viewport().get_camera_3d() != _cab.get_camera() and _player.get_node("Visual").visible, "Vuelve la 3ª persona y se ve el cuerpo")
	await _esperar(10)
	_comprobar(_player.get_platform() == _loco, "Al salir sigue enganchado a la locomotora")


# Mantiene apretada una acción un paso de física (para lo que se lee con is_action_just_pressed).
func _tocar(accion: StringName) -> void:
	Input.action_press(accion)
	await _esperar(2)
	Input.action_release(accion)
	await _esperar(1)


# Simula apretar y soltar una tecla (para lo que se lee como evento).
func _enviar_accion(accion: StringName) -> void:
	for apretada: bool in [true, false]:
		var evento := InputEventAction.new()
		evento.action = accion
		evento.pressed = apretada
		Input.parse_input_event(evento)
		await get_tree().process_frame
	await _esperar(1)


# Coloca el tren en la vía (la plataforma, acoplada detrás) a esa velocidad.
func _poner_tren(avance: float, velocidad: float) -> void:
	_loco.progress = avance
	_loco.place_rear_vehicles()
	_poner_velocidad(velocidad)


# Velocidad constante: el acelerador pide justo esa velocidad, así no acelera ni frena.
func _poner_velocidad(velocidad: float) -> void:
	_loco.speed = velocidad
	# Con la Cab el acelerador es fracción de la máxima de la locomotora (62b.5), no del límite de la vía.
	_loco.throttle = velocidad / (_loco.data.max_speed if _loco.absolute_throttle else _loco.get_max_speed())


# Gira la cámara para que "adelante" (W) apunte hacia la cola de la locomotora (+Z local).
func _mirar_hacia_atras_del_tren() -> void:
	var camara: ThirdPersonCamera = _player.get_camera()
	camara.add_yaw(angle_difference(camara.yaw, _loco.global_rotation.y + PI))


func _posicion_local() -> Vector3:
	return _loco.global_transform.affine_inverse() * _player.global_position


func _esperar(cuadros: int) -> void:
	for _i: int in cuadros:
		await get_tree().physics_frame


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
