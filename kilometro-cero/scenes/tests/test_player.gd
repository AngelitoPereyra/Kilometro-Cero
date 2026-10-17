extends Node3D
## Prueba de la tarea 9: cálculos del jugador, umbral de accidente, y subir y bajar del vehículo.
## Después de las pruebas se puede jugar: WASD, mouse, E, Espacio y S.
## Supone el jugador a 2 m del vehículo y el vehículo detenido al inicio de la vía.

const CONTROLES: String = "WASD: caminar · Mouse: cámara · E: subir/bajar · Espacio: empujar · S: marcha atrás · Esc: soltar el mouse"
const TOLERANCIA_M: float = 0.01

@onready var _player: Player = $Player
@onready var _vehicle: Vehicle = $Track/Vehicle
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0
var _accidentes: int = 0


func _ready() -> void:
		# Margen desde el borde superior izquierdo, hecho por código para no depender del inspector.
	_hud.position = Vector2(16.0, 16.0)
	_hud.text = CONTROLES
	EventBus.player_fainted.connect(_al_desmayar)
	_probar_estructura()
	_probar_calculos()
	_probar_umbral_de_accidente()
	await _probar_subir_y_bajar()

	if _fallos == 0:
		print("Tarea 9: todas las comprobaciones pasaron.")
	else:
		push_error("Tarea 9: fallaron %d comprobaciones." % _fallos)

	# Dejamos todo como al principio para poder jugar.
	_vehicle.speed = 0.0
	_vehicle.throttle = 0.0
	_vehicle.progress = 0.0
	_player.global_position = Vector3(2.0, 0.0, 0.0)
	_hud.text = CONTROLES


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
	_comprobar(Player.nearest_index(Vector3.ZERO, posiciones, 3.0) == 1, "Elige el vehículo más cercano dentro del alcance")
	_comprobar(Player.nearest_index(Vector3.ZERO, posiciones, 1.0) == -1, "Ninguno dentro del alcance: -1")
	var vacio: Array[Vector3] = []
	_comprobar(Player.nearest_index(Vector3.ZERO, vacio, 3.0) == -1, "Sin vehículos: -1")


func _probar_umbral_de_accidente() -> void:
	var datos := VehicleData.new()
	datos.max_safe_dismount_speed = 3.0
	_comprobar(datos.is_dismount_safe(0.0), "Detenido, bajarse es seguro")
	_comprobar(datos.is_dismount_safe(3.0), "Justo en el umbral, bajarse es seguro")
	_comprobar(not datos.is_dismount_safe(3.1), "Sobre el umbral, bajarse es un accidente")
	_comprobar(not datos.is_dismount_safe(-3.1), "También en marcha atrás")


func _probar_subir_y_bajar() -> void:
	# Lejos del vehículo no se puede subir.
	_player.global_position = Vector3(50.0, 0.0, 0.0)
	_comprobar(not _player.try_mount(), "Lejos del vehículo no se puede subir")
	_comprobar(_player.state == Player.State.WALKING, "Y sigue caminando")

	# Cerca sí, y queda sentado en el asiento.
	_player.global_position = Vector3(2.0, 0.0, 0.0)
	_comprobar(_player.try_mount(), "Cerca del vehículo se puede subir")
	_comprobar(_player.state == Player.State.RIDING, "Pasa al estado 'en el vehículo'")
		# physics_frame se emite ANTES de que corran los _physics_process de ese cuadro:
	# con uno solo, el jugador todavía no copió la posición del asiento. Esperamos dos.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_comprobar(_player.global_position.distance_to(_vehicle.get_seat_position()) < TOLERANCIA_M, "Sentado, sigue al asiento del vehículo")
	# Bajar detenido: sin accidente, al costado del vehículo.
	_vehicle.speed = 0.0
	_player.dismount()
	_comprobar(_accidentes == 0, "Bajar detenido no causa accidente")
	_comprobar(_player.state == Player.State.WALKING, "Después de bajar vuelve a caminar")
	_comprobar(_player.global_position.distance_to(_vehicle.get_dismount_position()) < TOLERANCIA_M, "Aparece al costado del vehículo")
	_comprobar(_player.global_position.distance_to(_vehicle.global_position) > 1.0, "Fuera del cuerpo del vehículo")
	_comprobar(is_zero_approx(_vehicle.throttle), "Al bajar, el acelerador vuelve a 0")

	# Bajar rápido: accidente.
	_player.global_position = Vector3(2.0, 0.0, 0.0)
	_player.try_mount()
	_vehicle.speed = 5.0
	_player.dismount()
	_comprobar(_accidentes == 1, "Bajar a 5 m/s emite player_fainted (accidente)")
	_comprobar(_player.state == Player.State.WALKING, "Tras el accidente el jugador queda caminando")


func _al_desmayar(cause: StringName) -> void:
	_accidentes += 1
	_hud.text = "¡Accidente (%s)! Sin efecto por ahora: el desmayo llega con Needs (tarea 10).\n%s" % [cause, CONTROLES]


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
