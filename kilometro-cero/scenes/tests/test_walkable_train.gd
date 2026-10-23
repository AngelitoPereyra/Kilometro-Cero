extends Node3D
## Prueba de la tarea 51: caminar dentro del tren en movimiento (D84).
## Supone una vía con una recta de 120 m y después una curva hacia la derecha, la
## locomotora y una plataforma detrás. Todavía no hay acople (tarea 53): esta escena
## coloca la plataforma a una distancia fija detrás de la locomotora en cada paso.
## Las comprobaciones usan cuadros de física reales: durante unos 10 segundos el tren y el
## jugador se mueven solos (y el jugador salta de un lugar a otro); no toques nada.
## Después se puede jugar: ↑ y ↓ cambian el acelerador (provisorio hasta la cabina de la
## tarea 52), y se sube al tren por las rampas.

const CONTROLES: String = "↑ / ↓: acelerador del tren · WASD: caminar · Shift: correr · Espacio: saltar · Ctrl: agacharse · Esc: soltar el mouse\nSubí por las rampas del costado. Probá caminar por la cabina, saltar con el tren andando y pasar a la plataforma de atrás."
## Distancia entre los centros de la locomotora y la plataforma (10 m de largo + 0,6 m de hueco).
const SEPARACION_M: float = 10.6
const INICIO_M: float = 30.0
## Avance donde empieza la curva de la vía de esta escena.
const CURVA_M: float = 118.0
## Sobre el pasillo derecho de la locomotora, entre la caldera y la baranda.
const PASILLO_LOCAL: Vector3 = Vector3(1.0, 0.85, -2.0)
## En el piso, al lado de la rampa derecha de la cabina.
const JUNTO_A_LA_RAMPA_LOCAL: Vector3 = Vector3(4.0, 0.2, 2.5)
const PASO_ACELERADOR: float = 0.25

@onready var _player: Player = $Player
@onready var _loco: Vehicle = $Track/Locomotive
@onready var _flatcar: Vehicle = $Track/Flatcar
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0
## Acelerador que esta escena les pasa a los dos vehículos en cada paso de física.
var _throttle: float = 0.0


func _ready() -> void:
	_hud.text = CONTROLES
	# Acople provisorio: la plataforma no se mueve sola, la ubica esta escena después de que
	# avanza la locomotora (prioridad 0) y antes que el jugador (prioridad 10).
	_flatcar.set_physics_process(false)
	process_physics_priority = 5
	# Durante las comprobaciones el mouse no gira la cámara: si no, moverlo cambia el
	# giro medido en la curva.
	_player.get_camera().set_process_unhandled_input(false)
	_probar_calculos()
	await _probar_parado_en_marcha()
	await _probar_curva()
	await _probar_salto()
	await _probar_pared()
	await _probar_pasar_a_la_plataforma()
	await _probar_bajar()

	if _fallos == 0:
		print("Tren caminable: todas las comprobaciones pasaron.")
	else:
		push_error("Tren caminable: fallaron %d comprobaciones." % _fallos)

	# Dejamos todo detenido al principio, con el jugador al lado de la rampa.
	_poner_tren(INICIO_M, 0.0)
	await _esperar(2)
	_player.global_position = _loco.global_transform * JUNTO_A_LA_RAMPA_LOCAL
	_player.velocity = Vector3.ZERO
	_player.get_camera().set_process_unhandled_input(true)


func _physics_process(_delta: float) -> void:
	_loco.throttle = _throttle
	_flatcar.progress = maxf(_loco.progress - SEPARACION_M, 0.0)
	_flatcar.speed = _loco.speed


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_up"):
		_throttle = clampf(_throttle + PASO_ACELERADOR, -1.0, 1.0)
	elif event.is_action_pressed(&"ui_down"):
		_throttle = clampf(_throttle - PASO_ACELERADOR, -1.0, 1.0)


func _process(_delta: float) -> void:
	var plataforma: Vehicle = _player.get_platform()
	_hud.text = "%s\nAcelerador: %d %% · Velocidad: %.0f km/h · Enganchado a: %s" % [
		CONTROLES,
		roundi(_throttle * 100.0),
		absf(_loco.speed) * 3.6,
		String(plataforma.name) if plataforma != null else "nada",
	]


func _probar_calculos() -> void:
	_comprobar(is_equal_approx(Player.yaw_delta(Basis(), Basis(Vector3.UP, 0.3)), 0.3), "Un giro de 0,3 rad a la izquierda mide 0,3")
	var cruzando_pi: float = Player.yaw_delta(Basis(Vector3.UP, 3.0), Basis(Vector3.UP, -3.0))
	_comprobar(is_equal_approx(cruzando_pi, TAU - 6.0), "Al cruzar ±180° se toma el camino corto (%.3f rad)" % cruzando_pi)
	var cuerpo := _loco.get_node("CuerpoFisico")
	_comprobar(Vehicle.find_owner_of(cuerpo) == _loco, "El cuerpo físico pertenece a la locomotora")
	_comprobar(Vehicle.find_owner_of($Ground) == null, "El piso no es un vehículo")
	_comprobar(Vehicle.find_owner_of(null) == null, "Sin nodo no hay vehículo")


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


# Salta corriendo desde la puerta de atrás de la cabina a la plataforma, con el tren andando.
func _probar_pasar_a_la_plataforma() -> void:
	_poner_tren(INICIO_M, 6.0)
	await _esperar(2)
	_player.global_position = _loco.global_transform * Vector3(0.0, 0.85, 3.6)
	_player.velocity = Vector3.ZERO
	await _esperar(10)
	_mirar_hacia_atras_del_tren()
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	var salto: bool = false
	for _i: int in 180:
		await get_tree().physics_frame
		if not salto and _posicion_local().z > 4.7:
			salto = _player.jump()
		if _player.get_platform() == _flatcar:
			break
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	_comprobar(salto, "Saltó desde el borde de la locomotora")
	_comprobar(_player.get_platform() == _flatcar, "Aterrizó en la plataforma y quedó enganchado a ella")
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


# Coloca los dos vehículos en la vía (la plataforma detrás) a esa velocidad.
func _poner_tren(avance: float, velocidad: float) -> void:
	_loco.progress = avance
	_flatcar.progress = avance - SEPARACION_M
	_poner_velocidad(velocidad)


# Velocidad constante: el acelerador pide justo esa velocidad, así no acelera ni frena.
func _poner_velocidad(velocidad: float) -> void:
	_loco.speed = velocidad
	_flatcar.speed = velocidad
	_throttle = velocidad / _loco.get_max_speed()


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
