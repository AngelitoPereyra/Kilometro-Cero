class_name Player
extends CharacterBody3D
## Jugador en 3ª persona. Camina relativo a la cámara y puede subir y bajar de un vehículo.
## La raíz NUNCA rota: solo gira el pivote `Visual`. Así la cámara (hija de la raíz) no
## hereda el giro del cuerpo (D44).
## Sobre un vehículo, el jugador no cambia de padre: copia la posición del asiento en cada
## paso de física, y por eso se procesa DESPUÉS del vehículo (ver _ready).
## Tiene una mochila (el nodo Backpack, un StorageContainer armado con `backpack_data`).
## Sin supervivencia ni peso (D75, D86): no hay desmayo, ni accidente al bajarse, y la
## carga no cambia la velocidad.

enum State { WALKING, RIDING }

@export_range(0.5, 10.0, 0.1, "suffix:m/s") var walk_speed: float = 4.0
@export_range(1.0, 100.0, 0.5) var acceleration: float = 25.0
## Qué tan rápido gira el cuerpo hacia donde camina.
@export_range(1.0, 30.0, 0.5) var turn_speed: float = 12.0
## Distancia máxima al asiento para poder subir.
@export_range(0.5, 10.0, 0.1, "suffix:m") var interaction_range: float = 3.0

@export_group("Carga")
## Mochila equipada: define las zonas del nodo Backpack.
@export var backpack_data: BackpackData

var state: State = State.WALKING

var _vehicle: Vehicle
var _camera: ThirdPersonCamera
var _backpack: StorageContainer
var _hands: Hands

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
		push_error("Player necesita como hijo directo un StorageContainer (la mochila, llamado Backpack).")
		set_physics_process(false)
		return
	_hands = _find_hands()
	if _hands == null:
		push_error("Player necesita un nodo Hands como hijo directo.")
		set_physics_process(false)
		return
	_setup_backpack()
	_hands.hands_changed.connect(_on_hands_changed)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"interact"):
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


func get_backpack() -> StorageContainer:
	return _backpack

func get_hands() -> Hands:
	return _hands
	
## Velocidad de caminata actual. La carga no la cambia (D86); correr llega en la tarea 50.
func get_walk_speed() -> float:
	return walk_speed


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
	if backpack_data == null or backpack_data.layout == null:
		push_warning("Player no tiene una BackpackData con layout asignada: no podrá guardar objetos.")
		return
	if _backpack.config == null:
		push_error("El nodo Backpack del jugador necesita un StorageConfig asignado.")
		return
	_backpack.setup(backpack_data.layout, _backpack.config)


# Hands no conoce al bus: el jugador es el único que avisa (D52).
func _on_hands_changed() -> void:
	EventBus.hands_changed.emit()


func _leave_vehicle() -> void:
	var vehicle: Vehicle = _vehicle
	_vehicle = null
	state = State.WALKING
	vehicle.throttle = 0.0
	global_position = vehicle.get_dismount_position()
	velocity = Vector3.ZERO
	_collision.set_deferred("disabled", false)


func _walk(delta: float) -> void:
	var input_vector: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var direction: Vector3 = world_direction(input_vector, _camera.yaw)
	var target: Vector3 = direction * get_walk_speed()
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()
	if direction.length_squared() > 0.0001:
		_visual.rotation.y = lerp_angle(_visual.rotation.y, facing_yaw(direction), minf(turn_speed * delta, 1.0))


func _ride() -> void:
	# Solo este script lee la entrada; el vehículo recibe un número entre -1 y 1.
	_vehicle.throttle = Input.get_axis(&"move_back", &"move_forward")
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

# Por ahora el único StorageContainer hijo directo es la mochila. Cuando haya más de uno
# (cinturón de herramientas, por ejemplo), se distinguirán por `container_id`.
func _find_backpack() -> StorageContainer:
	for child: Node in get_children():
		var container := child as StorageContainer
		if container != null:
			return container
	return null
