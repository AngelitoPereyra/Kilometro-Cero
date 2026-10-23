extends Node3D
## Prueba de la tarea 9: estructura y cálculos del jugador.
## Desde la tarea 51 no se sube ni se baja del vehículo con F: el tren se camina
## (eso se prueba en test_walkable_train).
## Después de las pruebas se puede jugar: WASD y mouse.

const CONTROLES: String = "WASD: caminar · Mouse: cámara · Esc: soltar el mouse"

@onready var _player: Player = $Player
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0


func _ready() -> void:
		# Margen desde el borde superior izquierdo, hecho por código para no depender del inspector.
	_hud.position = Vector2(16.0, 16.0)
	_hud.text = CONTROLES
	_probar_estructura()
	_probar_calculos()

	if _fallos == 0:
		print("Jugador: todas las comprobaciones pasaron.")
	else:
		push_error("Jugador: fallaron %d comprobaciones." % _fallos)


func _probar_calculos() -> void:
	var adelante: Vector3 = Player.world_direction(Vector2(0.0, -1.0), 0.0)
	_comprobar(adelante.is_equal_approx(Vector3(0.0, 0.0, -1.0)), "Sin giro de cámara, 'adelante' es -Z")
	var derecha: Vector3 = Player.world_direction(Vector2(1.0, 0.0), 0.0)
	_comprobar(derecha.is_equal_approx(Vector3(1.0, 0.0, 0.0)), "Sin giro, la derecha es +X")
	var girado: Vector3 = Player.world_direction(Vector2(0.0, -1.0), deg_to_rad(90.0))
	_comprobar(girado.is_equal_approx(Vector3(-1.0, 0.0, 0.0)), "Con la cámara girada 90° a la izquierda, 'adelante' es -X")

	_comprobar(is_zero_approx(Player.facing_yaw(Vector3(0.0, 0.0, -1.0))), "Mirar hacia -Z es ángulo 0")
	_comprobar(is_equal_approx(Player.facing_yaw(Vector3(1.0, 0.0, 0.0)), -PI / 2.0), "Mirar hacia +X es -90°")

	var posiciones: Array[Vector3] = [Vector3(10.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0)]
	_comprobar(Player.nearest_index(Vector3.ZERO, posiciones, 3.0) == 1, "Elige la posición más cercana dentro del alcance")
	_comprobar(Player.nearest_index(Vector3.ZERO, posiciones, 1.0) == -1, "Ninguna dentro del alcance: -1")
	var vacio: Array[Vector3] = []
	_comprobar(Player.nearest_index(Vector3.ZERO, vacio, 3.0) == -1, "Sin posiciones: -1")


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)

func _probar_estructura() -> void:
	var camara: ThirdPersonCamera = _player.get_camera()
	_comprobar(camara != null, "El jugador tiene una cámara en 3ª persona")
	if camara != null:
		_comprobar(camara.get_parent() == _player, "La cámara cuelga de la raíz del jugador (no gira con el cuerpo)")
