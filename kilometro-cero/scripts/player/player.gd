class_name Player
extends CharacterBody3D
## Jugador en 3ª persona. Camina relativo a la cámara y puede subir y bajar de un vehículo.
## La raíz NUNCA rota: solo gira el pivote `Visual`. Así la cámara (hija de la raíz) no
## hereda el giro del cuerpo (D44).
## Sobre un vehículo, el jugador no cambia de padre: copia la posición del asiento en cada
## paso de física, y por eso se procesa DESPUÉS del vehículo (ver _ready).
## Tiene una mochila (el nodo Backpack, un Inventory de ranuras armado con `backpack_data`).
## Sin supervivencia ni peso (D75, D86): no hay desmayo, ni accidente al bajarse, y la
## carga no cambia la velocidad.
## Movimiento (tarea 50, D91): Shift corre (sin costo), Espacio salta y Ctrl agacha
## mientras se mantiene. Al caminar hacia atrás el cuerpo no se da vuelta: retrocede
## mirando hacia adelante.

enum State { WALKING, RIDING }

@export_range(0.5, 10.0, 0.1, "suffix:m/s") var walk_speed: float = 4.0
@export_range(0.5, 15.0, 0.1, "suffix:m/s") var sprint_speed: float = 7.0
@export_range(0.5, 10.0, 0.1, "suffix:m/s") var crouch_speed: float = 2.0
## Hacia atrás se camina más lento y no se corre.
@export_range(0.1, 1.0, 0.05) var backwards_speed_factor: float = 0.7
## Velocidad hacia arriba al saltar (con la gravedad por defecto sube unos 1,0 m).
@export_range(1.0, 15.0, 0.1, "suffix:m/s") var jump_velocity: float = 4.5
## Altura de la cápsula agachado. Parado se usa la de la escena.
@export_range(0.7, 2.0, 0.05, "suffix:m") var crouch_height: float = 1.1
@export_range(1.0, 100.0, 0.5) var acceleration: float = 25.0
## Qué tan rápido gira el cuerpo hacia donde camina.
@export_range(1.0, 30.0, 0.5) var turn_speed: float = 12.0
## Distancia máxima al asiento para poder subir.
@export_range(0.5, 10.0, 0.1, "suffix:m") var interaction_range: float = 3.0

@export_group("Carga")
## Mochila equipada: define las ranuras del nodo Backpack.
@export var backpack_data: BackpackData

var state: State = State.WALKING
## Si es false, el jugador no camina, no maneja ni actúa (por ejemplo, con el
## inventario abierto, D72). La física sigue: si estaba en el aire, cae igual.
## Lo cambia quien abre un menú, con set_controls_enabled.
var controls_enabled: bool = true
## Si está agachado (cápsula baja). Se cambia con set_crouching.
var crouching: bool = false
## Si en el último paso de física estaba corriendo. Solo lectura.
var sprinting: bool = false

var _vehicle: Vehicle
var _camera: ThirdPersonCamera
var _backpack: Inventory
var _hands: Hands
# Lo que pide el jugador. Si quiere pararse y hay un techo encima, sigue agachado
# y se vuelve a intentar en cada paso hasta que haya lugar.
var _wants_crouch: bool = false
var _stand_height: float
var _camera_height: float

@onready var _visual: Node3D = $Visual
@onready var _collision: CollisionShape3D = $CollisionShape3D


## Dirección de caminata en el mundo. `input_vector` es lo que devuelve Input.get_vector
## (y negativo = adelante) y `yaw` el giro horizontal de la cámara.
## Lógica pura: se prueba sin escena.
static func world_direction(input_vector: Vector2, yaw: float) -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3(input_vector.x, 0.0, input_vector.y)


## Giro en Y que hace que el frente (-Z) apunte hacia `direction`.
static func facing_yaw(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


## true si la entrada va hacia atrás respecto de la cámara (y positivo en Input.get_vector).
static func is_backwards(input_vector: Vector2) -> bool:
	return input_vector.y > 0.1


## Hacia dónde tiene que mirar el cuerpo según la entrada. Hacia atrás mira al revés de
## donde camina, así retrocede sin darse vuelta (hacia atrás y a la izquierda mira
## adelante y a la derecha).
static func body_direction(input_vector: Vector2, yaw: float) -> Vector3:
	if is_backwards(input_vector):
		return world_direction(-input_vector, yaw)
	return world_direction(input_vector, yaw)


## Índice de la posición más cercana dentro de `max_distance`, o -1 si ninguna alcanza.
static func nearest_index(origin: Vector3, positions: Array[Vector3], max_distance: float) -> int:
	var best: int = -1
	var best_distance: float = max_distance
	for i: int in positions.size():
		var distance: float = origin.distance_to(positions[i])
		if distance <= best_distance:
			best = i
			best_distance = distance
	return best


func _ready() -> void:
	# Mayor número = se procesa después. Si el jugador copiara la posición del asiento
	# antes de que el vehículo avance, iría un cuadro atrasado y se vería temblar.
	process_physics_priority = 10
	_camera = _find_camera()
	if _camera == null:
		# Mostramos qué hijos hay de verdad: es lo que más ayuda a ubicar el error en la escena.
		var names: String = ""
		for child: Node in get_children():
			names += "%s (%s)  " % [child.name, child.get_class()]
		push_error("Player no encontró ningún ThirdPersonCamera entre sus descendientes. Hijos directos: %s" % names)
		set_physics_process(false)
		return
	# La cámara tiene que colgar de la raíz, que nunca rota (D44). Si cuelga de `Visual`,
	# gira junto con el cuerpo y los controles se desordenan en espiral.
	if _camera.get_parent() != self:
		push_error("La cámara ('%s') debe ser hija directa de Player, no de '%s': si no, gira con el cuerpo y los controles se desordenan." % [_camera.name, _camera.get_parent().name])
		set_physics_process(false)
		return
	_backpack = _find_backpack()
	if _backpack == null:
		push_error("Player necesita como hijo directo un Inventory (la mochila, llamado Backpack).")
		set_physics_process(false)
		return
	_hands = _find_hands()
	if _hands == null:
		push_error("Player necesita un nodo Hands como hijo directo.")
		set_physics_process(false)
		return
	_setup_backpack()
	_setup_crouch()
	_hands.hands_changed.connect(_on_hands_changed)
	_backpack.alert_changed.connect(_on_backpack_alert_changed)


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled or not event.is_action_pressed(&"interact"):
		return
	match state:
		State.WALKING:
			try_mount()
		State.RIDING:
			dismount()


func _physics_process(delta: float) -> void:
	match state:
		State.WALKING:
			_walk(delta)
		State.RIDING:
			_ride()


func get_camera() -> ThirdPersonCamera:
	return _camera

## Hacia dónde mira el cuerpo, en radianes (0 mira hacia -Z). Las manos (Grabber)
## se anclan a esto y no a la cámara: giran con el personaje, no cuando mirás
## alrededor, como dos brazos de verdad (D61).
## La raíz nunca rota (D44), así que el giro local del pivote Visual es el del cuerpo.
func get_facing_yaw() -> float:
	return _visual.rotation.y


func get_backpack() -> Inventory:
	return _backpack


## Activa o desactiva los controles del jugador (ver `controls_enabled`). Al
## desactivarlos se frena: no sigue caminando ni acelerando el vehículo.
func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if enabled:
		return
	velocity.x = 0.0
	velocity.z = 0.0
	if _vehicle != null:
		_vehicle.throttle = 0.0

func get_hands() -> Hands:
	return _hands
	
## Velocidad de caminata normal. La carga no la cambia (D86).
func get_walk_speed() -> float:
	return walk_speed


## Velocidad objetivo según el modo: agachado manda sobre todo; hacia atrás no se corre.
func get_move_speed(sprint: bool, backwards: bool) -> float:
	if crouching:
		return crouch_speed
	if backwards:
		return walk_speed * backwards_speed_factor
	if sprint:
		return sprint_speed
	return walk_speed


## Salta si está caminando, con controles y en el piso. Agachado, primero se para;
## si hay un techo encima no salta. Devuelve si saltó.
func jump() -> bool:
	if state != State.WALKING or not controls_enabled or not is_on_floor():
		return false
	if crouching:
		if not can_stand():
			return false
		_wants_crouch = false
		_apply_crouch(false)
	velocity.y = jump_velocity
	return true


## Pide agacharse o pararse. Pararse falla (devuelve false) si hay un techo encima: queda
## agachado y se para solo en cuanto haya lugar.
func set_crouching(value: bool) -> bool:
	_wants_crouch = value
	if value == crouching:
		return true
	if not value and not can_stand():
		return false
	_apply_crouch(value)
	return true


## true si al pararse la cápsula no chocaría con nada (por ejemplo, un techo bajo).
func can_stand() -> bool:
	if not crouching:
		return true
	return not test_move(global_transform, Vector3.UP * (_stand_height - crouch_height))


## Sube al vehículo más cercano al alcance. Devuelve false si no hay ninguno.
func try_mount() -> bool:
	if state != State.WALKING:
		return false
	var vehicles: Array[Vehicle] = _get_vehicles()
	var positions: Array[Vector3] = []
	for vehicle: Vehicle in vehicles:
		positions.append(vehicle.get_seat_position())
	var index: int = nearest_index(global_position, positions, interaction_range)
	if index == -1:
		return false
	_vehicle = vehicles[index]
	# Sentado no hay techo que choque: se para sin preguntar.
	_wants_crouch = false
	_apply_crouch(false)
	sprinting = false
	state = State.RIDING
	velocity = Vector3.ZERO
	# Sentado no choca con nada. Se hace diferido por si se llama dentro de un paso de física.
	_collision.set_deferred("disabled", true)
	return true


## Baja del vehículo, al costado. Se puede bajar a cualquier velocidad (D75).
func dismount() -> void:
	if state != State.RIDING:
		return
	_leave_vehicle()


# Arma la mochila con los datos de `backpack_data`.
func _setup_backpack() -> void:
	if backpack_data == null:
		push_warning("Player no tiene una BackpackData asignada: no podrá guardar objetos.")
		return
	_backpack.setup(backpack_data)


# Duplica la cápsula (el recurso es compartido por todas las instancias de la escena)
# y guarda las alturas paradas de la cápsula y de la cámara.
func _setup_crouch() -> void:
	_collision.shape = _collision.shape.duplicate()
	var capsule := _collision.shape as CapsuleShape3D
	if capsule == null:
		push_warning("Player: la forma de colisión no es una cápsula; agacharse no cambia la altura.")
		_stand_height = crouch_height
	else:
		_stand_height = capsule.height
	_camera_height = _camera.position.y


# Cambia la cápsula, el cuerpo visible y la cámara. No comprueba el techo.
func _apply_crouch(value: bool) -> void:
	crouching = value
	var height: float = crouch_height if value else _stand_height
	var capsule := _collision.shape as CapsuleShape3D
	if capsule != null:
		capsule.height = height
	# La cápsula se achica desde arriba: los pies quedan en el piso.
	_collision.position.y = height / 2.0
	_visual.scale.y = height / _stand_height
	_camera.position.y = _camera_height - (_stand_height - height)


# Hands no conoce al bus: el jugador es el único que avisa (D52).
func _on_hands_changed() -> void:
	EventBus.hands_changed.emit()


# Lo mismo con las alertas de la mochila (D59, patrón D50).
func _on_backpack_alert_changed(alert: Inventory.Alert) -> void:
	EventBus.backpack_alert_changed.emit(alert)


func _leave_vehicle() -> void:
	var vehicle: Vehicle = _vehicle
	_vehicle = null
	state = State.WALKING
	vehicle.throttle = 0.0
	global_position = vehicle.get_dismount_position()
	velocity = Vector3.ZERO
	_collision.set_deferred("disabled", false)


func _walk(delta: float) -> void:
	var input_vector: Vector2 = Vector2.ZERO
	if controls_enabled:
		input_vector = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if controls_enabled:
		if Input.is_action_just_pressed(&"crouch"):
			_wants_crouch = true
		elif Input.is_action_just_released(&"crouch"):
			_wants_crouch = false
		if Input.is_action_just_pressed(&"jump"):
			jump()
	if crouching != _wants_crouch:
		set_crouching(_wants_crouch)
	var backwards: bool = is_backwards(input_vector)
	var direction: Vector3 = world_direction(input_vector, _camera.yaw)
	sprinting = controls_enabled and Input.is_action_pressed(&"sprint") and not crouching and not backwards and direction.length_squared() > 0.0001
	var target: Vector3 = direction * get_move_speed(sprinting, backwards)
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()
	if direction.length_squared() > 0.0001:
		var body: Vector3 = body_direction(input_vector, _camera.yaw)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, facing_yaw(body), minf(turn_speed * delta, 1.0))


func _ride() -> void:
	# Solo este script lee la entrada; el vehículo recibe un número entre -1 y 1.
	_vehicle.throttle = Input.get_axis(&"move_back", &"move_forward") if controls_enabled else 0.0
	global_position = _vehicle.get_seat_position()
	_visual.rotation.y = _vehicle.global_rotation.y


func _get_vehicles() -> Array[Vehicle]:
	var result: Array[Vehicle] = []
	for node: Node in get_tree().get_nodes_in_group(Vehicle.GROUP):
		var vehicle := node as Vehicle
		if vehicle != null:
			result.append(vehicle)
	return result


# Busca por tipo, no por nombre: da igual cómo se llame el nodo o en qué nivel esté.
func _find_camera() -> ThirdPersonCamera:
	for node: Node in find_children("*", "Node3D", true, false):
		var camera := node as ThirdPersonCamera
		if camera != null:
			return camera
	return null


func _find_hands() -> Hands:
	for child: Node in get_children():
		var hands := child as Hands
		if hands != null:
			return hands
	return null

# Por ahora el único Inventory hijo directo es la mochila. Cuando haya más de uno
# (cinturón de herramientas, por ejemplo), se distinguirán por `container_id`.
func _find_backpack() -> Inventory:
	for child: Node in get_children():
		var inventory := child as Inventory
		if inventory != null:
			return inventory
	return null
