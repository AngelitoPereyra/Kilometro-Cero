class_name TrainCamera
extends Camera3D
## Cámara exterior del tren (tarea 60c): mira el tren entero desde afuera y gira a su
## alrededor con el mouse; la rueda la acerca y la aleja. La crea la `Cab` (hija "CamaraExterior")
## y la tecla V alterna entre esta y la vista de la cabina; los controles del tren son los mismos.
## Sigue el centro del tren y gira con la locomotora en las curvas: `yaw` es relativo al frente
## del vehículo de la cabina (0 = detrás del tren, mirando hacia adelante).

@export_range(0.0005, 0.01, 0.0005) var mouse_sensitivity: float = 0.0025
@export_range(2.0, 100.0, 0.5, "suffix:m") var min_distance: float = 8.0
@export_range(2.0, 100.0, 0.5, "suffix:m") var max_distance: float = 45.0
@export_range(2.0, 100.0, 0.5, "suffix:m") var initial_distance: float = 18.0
## Cuánto cambia la distancia por cada paso de la rueda.
@export_range(0.5, 10.0, 0.5, "suffix:m") var zoom_step: float = 2.0
## Mirando hacia abajo es negativo (la cámara sube).
@export_range(-89.0, 0.0, 1.0, "suffix:°") var min_pitch_degrees: float = -75.0
@export_range(-89.0, 0.0, 1.0, "suffix:°") var max_pitch_degrees: float = -5.0
@export_range(-89.0, 0.0, 1.0, "suffix:°") var initial_pitch_degrees: float = -20.0
## Altura sobre los rieles del punto que mira.
@export_range(0.0, 10.0, 0.1, "suffix:m") var target_height: float = 2.0

## Giro alrededor del tren (radianes), relativo al frente del vehículo.
var yaw: float = 0.0
var pitch: float = 0.0
var distance: float = 18.0

var _vehicle: Vehicle


func _ready() -> void:
	top_level = true
	reset_view()


## El vehículo que sigue (el de la cabina). Lo pone la Cab.
func set_vehicle(vehicle: Vehicle) -> void:
	_vehicle = vehicle
	update_transform()


func get_vehicle() -> Vehicle:
	return _vehicle


## Vuelve a la vista inicial: detrás del tren, un poco desde arriba.
func reset_view() -> void:
	yaw = 0.0
	pitch = deg_to_rad(initial_pitch_degrees)
	distance = clampf(initial_distance, min_distance, max_distance)
	update_transform()


## Gira alrededor del tren (radianes).
func orbit(yaw_amount: float, pitch_amount: float) -> void:
	yaw = wrapf(yaw + yaw_amount, -PI, PI)
	pitch = clampf(pitch + pitch_amount, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))
	update_transform()


## Acerca (pasos negativos) o aleja (positivos) la cámara.
func zoom(steps: float) -> void:
	distance = clampf(distance + steps * zoom_step, min_distance, max_distance)
	update_transform()


## El punto que mira: el centro del tren, a `target_height`.
func get_target() -> Vector3:
	if _vehicle == null or not is_instance_valid(_vehicle) or not _vehicle.is_inside_tree():
		return global_position
	var train: Array[Vehicle] = _vehicle.get_train()
	var center: Vector3 = Vector3.ZERO
	for vehicle: Vehicle in train:
		center += vehicle.global_position
	center /= maxf(float(train.size()), 1.0)
	return center + Vector3.UP * target_height


## Hacia dónde mira en el mundo (0 mira hacia -Z), como Cab.get_view_yaw.
func get_view_yaw() -> float:
	return Player.facing_yaw(-global_basis.z)


func _process(_delta: float) -> void:
	if current:
		update_transform()


func update_transform() -> void:
	if not is_inside_tree() or _vehicle == null or not is_instance_valid(_vehicle) or not _vehicle.is_inside_tree():
		return
	var forward: Vector3 = -_vehicle.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	var base_yaw: float = Player.facing_yaw(forward.normalized())
	var view: Basis = Basis.from_euler(Vector3(pitch, base_yaw + yaw, 0.0))
	var target: Vector3 = get_target()
	global_transform = Transform3D(view, target + view * Vector3(0.0, 0.0, distance))
