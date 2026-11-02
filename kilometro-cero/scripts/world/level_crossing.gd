class_name LevelCrossing
extends Node3D
## Paso a nivel con barreras (tarea 62c.3f): baja los brazos cuando un tren (cualquier vehículo a la
## vista, del jugador o automático) está a menos de `warning_distance` del cruce, y los sube cuando
## ya no queda ninguno. El nodo va en el centro del cruce, con la vía a lo largo de su Z y el camino
## a lo largo de su X. Cada barrera es un hijo cuyo nombre empieza con "Barrera" y que tiene un
## MeshInstance3D "Brazo" parado sobre su poste: al empezar, el brazo pasa a una bisagra a
## `hinge_height` y al bajar gira hasta quedar acostado sobre el camino, apuntando al centro.

const BARRIER_PREFIX: String = "Barrera"
const ARM_NAME: String = "Brazo"
const HINGE_NAME: String = "Bisagra"
const CHECK_TIME: float = 0.2

@export_range(10.0, 400.0, 1.0, "suffix:m") var warning_distance: float = 90.0
## Altura de la bisagra (la punta del poste).
@export_range(0.2, 3.0, 0.05, "suffix:m") var hinge_height: float = 1.1
## Segundos que tarda en bajar o subir.
@export_range(0.2, 10.0, 0.1, "suffix:s") var swing_time: float = 2.5

## Las bisagras de las barreras y hacia qué lado bajan (+1 o -1, giro en X).
var _hinges: Array[Node3D] = []
var _sides: Array[float] = []
var _closed: bool = false
# 0 arriba, 1 abajo.
var _amount: float = 0.0
var _check_left: float = 0.0


## Lógica pura: si algún punto (global) está a menos de `distance` del cruce en el plano.
static func any_near(center: Vector3, points: Array[Vector3], distance: float) -> bool:
	for point: Vector3 in points:
		if Vector2(point.x - center.x, point.z - center.z).length() <= distance:
			return true
	return false


func _ready() -> void:
	for child: Node in get_children():
		var barrier := child as Node3D
		if barrier == null or not String(barrier.name).begins_with(BARRIER_PREFIX):
			continue
		var arm := barrier.get_node_or_null(NodePath(ARM_NAME)) as Node3D
		if arm == null:
			continue
		var hinge := Node3D.new()
		hinge.name = HINGE_NAME
		hinge.position = Vector3(0.0, hinge_height, 0.0)
		barrier.add_child(hinge)
		var arm_height: float = arm.position.y
		arm.reparent(hinge, false)
		arm.position = Vector3(0.0, arm_height - hinge_height, 0.0)
		_hinges.append(hinge)
		# Baja hacia el centro del cruce: si la barrera está del lado +Z del camino, el brazo
		# apunta a -Z (giro negativo en X).
		_sides.append(-1.0 if barrier.position.z > 0.0 else 1.0)


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = CHECK_TIME
		_closed = any_near(global_position, _train_points(), warning_distance)
	var target: float = 1.0 if _closed else 0.0
	if not is_equal_approx(_amount, target):
		_amount = move_toward(_amount, target, delta / swing_time)
		_apply()


## Si las barreras están bajando o abajo (hay un tren cerca).
func is_closed() -> bool:
	return _closed


## Cuánto bajaron (0 arriba, 1 acostadas).
func get_lowered_amount() -> float:
	return _amount


func get_barrier_count() -> int:
	return _hinges.size()


## Vuelve a mirar los trenes ahora (para pruebas; en juego lo hace solo cada CHECK_TIME).
func check_now() -> bool:
	_closed = any_near(global_position, _train_points(), warning_distance)
	return _closed


## Pone las barreras de golpe (para pruebas).
func set_lowered_amount(value: float) -> void:
	_amount = clampf(value, 0.0, 1.0)
	_apply()


func _apply() -> void:
	var angle: float = smoothstep(0.0, 1.0, _amount) * PI * 0.5
	for index: int in _hinges.size():
		_hinges[index].rotation.x = angle * _sides[index]


func _train_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for node: Node in get_tree().get_nodes_in_group(Vehicle.GROUP):
		var vehicle := node as Vehicle
		if vehicle != null and vehicle.is_visible_in_tree():
			points.append(vehicle.global_position)
	return points
