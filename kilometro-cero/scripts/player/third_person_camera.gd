class_name ThirdPersonCamera
extends Node3D
## Cámara orbital en 3ª persona: el mouse gira alrededor del jugador (yaw = horizontal,
## pitch = vertical). El nodo gira en Y; el SpringArm3D hijo lleva el pitch y acerca la
## cámara si hay una pared o el piso en el medio (no atraviesa el mundo).
## El movimiento del jugador se calcula relativo a `yaw`.
## El manejo del mouse acá es provisorio: cuando exista la interfaz (tarea 28),
## la captura y liberación del mouse se mueven a un solo lugar.

@export_range(0.0005, 0.01, 0.0005) var mouse_sensitivity: float = 0.0025
## Mirando hacia abajo es negativo (la cámara sube); hacia arriba es positivo.
@export_range(-89.0, 0.0, 1.0, "suffix:°") var min_pitch_degrees: float = -70.0
@export_range(0.0, 89.0, 1.0, "suffix:°") var max_pitch_degrees: float = 10.0
@export_range(-89.0, 89.0, 1.0, "suffix:°") var initial_pitch_degrees: float = -15.0

## Giro horizontal en radianes. 0 = la cámara mira hacia -Z.
var yaw: float = 0.0
var pitch: float = 0.0

@onready var _spring_arm: SpringArm3D = $SpringArm3D


func _ready() -> void:
	pitch = deg_to_rad(initial_pitch_degrees)
	_apply()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	var motion := event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= motion.relative.x * mouse_sensitivity
		# Mouse hacia arriba (relative.y negativo) = mirar hacia arriba = pitch positivo.
		pitch = clampf(pitch - motion.relative.y * mouse_sensitivity, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))
		_apply()


## Suma un giro horizontal sin pasar por el mouse. Lo usa el jugador para que la cámara
## gire junto con el tren en las curvas (tarea 51).
func add_yaw(amount: float) -> void:
	yaw = wrapf(yaw + amount, -PI, PI)
	_apply()


func _apply() -> void:
	rotation.y = yaw
	_spring_arm.rotation.x = pitch
