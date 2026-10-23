extends Node3D
## Prueba de la tarea 50: correr, saltar, agacharse y caminar hacia atrás (D91).
## Supone el piso arriba en y = 0 y un techo bajo (abajo en y = 1,3) centrado en x = 10.
## Después de las pruebas se puede jugar: WASD, Shift, Espacio, Ctrl y mouse.

const CONTROLES: String = "WASD: caminar · Shift: correr · Espacio: saltar · Ctrl: agacharse · Mouse: cámara · Esc: soltar el mouse\nEl techo bajo está a la derecha del inicio: pasá agachado y soltá Ctrl abajo."
const INICIO: Vector3 = Vector3(0.0, 0.0, 0.0)
const BAJO_TECHO: Vector3 = Vector3(10.0, 0.0, 0.0)
const MAX_CUADROS: int = 120

@onready var _player: Player = $Player
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0


func _ready() -> void:
	_hud.text = CONTROLES
	_probar_calculos()
	_probar_velocidades()
	await _probar_salto()
	await _probar_agacharse()

	if _fallos == 0:
		print("Movimiento: todas las comprobaciones pasaron.")
	else:
		push_error("Movimiento: fallaron %d comprobaciones." % _fallos)

	# Dejamos todo como al principio para poder jugar.
	_player.set_crouching(false)
	_player.controls_enabled = true
	_player.global_position = INICIO
	_player.velocity = Vector3.ZERO


func _probar_calculos() -> void:
	_comprobar(Player.is_backwards(Vector2(0.0, 1.0)), "S es hacia atrás")
	_comprobar(Player.is_backwards(Vector2(-0.7, 0.7)), "Atrás en diagonal también es hacia atrás")
	_comprobar(not Player.is_backwards(Vector2(0.0, -1.0)), "W no es hacia atrás")
	_comprobar(not Player.is_backwards(Vector2(1.0, 0.0)), "D (de costado) no es hacia atrás")

	var atras: Vector3 = Player.body_direction(Vector2(0.0, 1.0), 0.0)
	_comprobar(atras.is_equal_approx(Vector3(0.0, 0.0, -1.0)), "Caminando hacia atrás el cuerpo sigue mirando adelante (-Z)")
	var atras_izquierda: Vector3 = Player.body_direction(Vector2(-1.0, 1.0), 0.0)
	_comprobar(atras_izquierda.is_equal_approx(Vector3(1.0, 0.0, -1.0)), "Atrás a la izquierda: el cuerpo mira adelante a la derecha")
	var adelante: Vector3 = Player.body_direction(Vector2(0.0, -1.0), 0.0)
	_comprobar(adelante.is_equal_approx(Vector3(0.0, 0.0, -1.0)), "Hacia adelante el cuerpo mira hacia donde camina")
	var girado: Vector3 = Player.body_direction(Vector2(0.0, 1.0), deg_to_rad(90.0))
	_comprobar(girado.is_equal_approx(Vector3(-1.0, 0.0, 0.0)), "Con la cámara girada 90°, hacia atrás mira hacia donde mira la cámara")


func _probar_velocidades() -> void:
	_player.set_crouching(false)
	_comprobar(is_equal_approx(_player.get_move_speed(false, false), _player.walk_speed), "Sin Shift camina a walk_speed")
	_comprobar(is_equal_approx(_player.get_move_speed(true, false), _player.sprint_speed), "Con Shift corre a sprint_speed")
	_comprobar(_player.sprint_speed > _player.walk_speed, "Correr es más rápido que caminar")
	var hacia_atras: float = _player.walk_speed * _player.backwards_speed_factor
	_comprobar(is_equal_approx(_player.get_move_speed(true, true), hacia_atras), "Hacia atrás no se corre aunque se mantenga Shift")
	_player.set_crouching(true)
	_comprobar(is_equal_approx(_player.get_move_speed(true, false), _player.crouch_speed), "Agachado va a crouch_speed aunque se mantenga Shift")
	_player.set_crouching(false)


func _probar_salto() -> void:
	_player.global_position = INICIO
	_player.velocity = Vector3.ZERO
	_comprobar(await _esperar(func() -> bool: return _player.is_on_floor()), "El jugador apoya en el piso")

	_player.controls_enabled = false
	_comprobar(not _player.jump(), "Con los controles apagados no salta")
	_player.controls_enabled = true

	_comprobar(_player.jump(), "En el piso salta")
	_comprobar(_player.velocity.y > 0.0, "Al saltar la velocidad vertical es hacia arriba")
	var altura_max: float = 0.0
	var en_el_aire: bool = false
	var probo_doble_salto: bool = false
	for i: int in MAX_CUADROS:
		await get_tree().physics_frame
		altura_max = maxf(altura_max, _player.global_position.y)
		if not _player.is_on_floor():
			en_el_aire = true
			if not probo_doble_salto:
				probo_doble_salto = true
				_comprobar(not _player.jump(), "En el aire no vuelve a saltar")
		elif en_el_aire:
			break
	_comprobar(altura_max > 0.5, "Sube más de medio metro (subió %.2f m)" % altura_max)
	_comprobar(_player.is_on_floor(), "Vuelve a caer al piso")


func _probar_agacharse() -> void:
	var parado: float = _altura_capsula()
	_comprobar(_player.set_crouching(true), "Se puede agachar")
	_comprobar(_player.crouching, "Queda agachado")
	_comprobar(is_equal_approx(_altura_capsula(), _player.crouch_height), "Agachado, la cápsula mide crouch_height")
	_comprobar(_altura_capsula() < parado, "Agachado es más bajo que parado")
	_comprobar(_player.set_crouching(false), "Sin techo se puede parar")
	_comprobar(is_equal_approx(_altura_capsula(), parado), "Parado vuelve a la altura original")

	# Debajo del techo bajo: agachado entra, parado no.
	_player.set_crouching(true)
	_player.global_position = BAJO_TECHO
	_player.velocity = Vector3.ZERO
	await _esperar(func() -> bool: return _player.is_on_floor())
	_comprobar(not _player.can_stand(), "Debajo del techo no hay lugar para pararse")
	_comprobar(not _player.set_crouching(false), "Debajo del techo no se para")
	_comprobar(not _player.jump(), "Agachado debajo del techo no salta")
	for i: int in 5:
		await get_tree().physics_frame
	_comprobar(_player.crouching, "Sigue agachado mientras tenga el techo encima")

	# Al salir de abajo del techo se para solo, porque ya no se pide agacharse.
	_player.global_position = INICIO
	_comprobar(await _esperar(func() -> bool: return not _player.crouching), "Al salir de abajo del techo se para solo")


# Espera cuadros de física hasta que la condición se cumpla (o MAX_CUADROS).
func _esperar(condicion: Callable) -> bool:
	for i: int in MAX_CUADROS:
		if condicion.call():
			return true
		await get_tree().physics_frame
	return condicion.call()


func _altura_capsula() -> float:
	var forma := _player.get_node("CollisionShape3D").shape as CapsuleShape3D
	return forma.height if forma != null else 0.0


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
