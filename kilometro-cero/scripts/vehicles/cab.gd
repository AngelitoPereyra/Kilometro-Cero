class_name Cab
extends Node3D
## Puesto de manejo en 1ª persona (tarea 52, D84). Va dentro de la escena de una locomotora,
## como descendiente de su Vehicle. Su origen marca el piso donde se para el maquinista y su
## -Z mira hacia donde maneja. Hijos: `Camera3D` (obligatoria, a la altura de los ojos) y
## `Palanca` (opcional, se inclina con la marcha).
## La entrada y la salida las hace el jugador con F (Player.try_enter_cab y exit_cab), que
## llama a `occupy` y `release`. Mientras está ocupada, la cabina lee las teclas (D91):
## W y S mueven la palanca de marcha una muesca, Espacio frena mientras se mantiene, L prende
## y apaga las luces y H toca la bocina; el mouse mira alrededor con límites.
## Escribe en el vehículo solo cuando algo cambia (`throttle` y `brake`): al bajarse, el tren
## sigue con la marcha que quedó puesta, y las pruebas pueden manejarlo directamente.

signal controls_changed                  # cambió la marcha, el freno o las luces
signal horn_sounded

## Grupo de todas las cabinas (el jugador busca acá la más cercana).
const GROUP: StringName = &"cabs"

## Muescas de la palanca hacia adelante y hacia atrás; la última de cada lado es a fondo.
@export_range(1, 10) var forward_notches: int = 4
@export_range(1, 10) var reverse_notches: int = 2
## Distancia horizontal máxima desde el puesto para entrar con F.
@export_range(0.5, 5.0, 0.1, "suffix:m") var enter_radius: float = 1.5
## Cuánto se inclina la palanca visible por muesca.
@export_range(0.0, 45.0, 1.0, "suffix:°") var lever_degrees_per_notch: float = 12.0
@export_range(0.0005, 0.01, 0.0005) var mouse_sensitivity: float = 0.0025
## Hasta dónde se puede girar la cabeza hacia cada costado.
@export_range(0.0, 180.0, 1.0, "suffix:°") var max_look_yaw_degrees: float = 110.0
@export_range(-89.0, 0.0, 1.0, "suffix:°") var min_look_pitch_degrees: float = -60.0
@export_range(0.0, 89.0, 1.0, "suffix:°") var max_look_pitch_degrees: float = 45.0
## Luces que prende y apaga L (faros).
@export var lights: Array[Light3D] = []
## Sonido de la bocina. Sin sonido, H solo emite `horn_sounded`.
@export var horn_sound: AudioStream

## Muesca actual: 0 punto muerto, positiva adelante, negativa atrás.
var notch: int = 0
var braking: bool = false
var lights_on: bool = false
## Hacia dónde mira la cabeza, relativo a la cabina (radianes).
var look_yaw: float = 0.0
var look_pitch: float = 0.0

var _vehicle: Vehicle
var _occupant: Player
var _horn: AudioStreamPlayer3D

@onready var _camera: Camera3D = get_node_or_null(^"Camera3D") as Camera3D
@onready var _lever: Node3D = get_node_or_null(^"Palanca") as Node3D


## Acelerador (-1.0 a 1.0) que corresponde a una muesca. Lógica pura.
static func throttle_for_notch(value: int, forward_count: int, reverse_count: int) -> float:
	if value > 0:
		return minf(float(value) / float(forward_count), 1.0)
	if value < 0:
		return -minf(float(-value) / float(reverse_count), 1.0)
	return 0.0


## Mantiene una muesca dentro de la palanca. Lógica pura.
static func clamp_notch(value: int, forward_count: int, reverse_count: int) -> int:
	return clampi(value, -reverse_count, forward_count)


## Nombre de la muesca para la interfaz: "Punto muerto", "Adelante 2/4", "Atrás 1/2".
static func notch_text(value: int, forward_count: int, reverse_count: int) -> String:
	if value > 0:
		return "Adelante %d/%d" % [value, forward_count]
	if value < 0:
		return "Atrás %d/%d" % [-value, reverse_count]
	return "Punto muerto"


func _ready() -> void:
	add_to_group(GROUP)
	_vehicle = Vehicle.find_owner_of(self)
	if _vehicle == null:
		push_error("Cab ('%s') tiene que estar dentro de un Vehicle." % name)
	if _camera == null:
		push_error("Cab ('%s') necesita un hijo Camera3D (la vista en 1ª persona)." % name)
	else:
		_camera.current = false
	_horn = AudioStreamPlayer3D.new()
	_horn.name = "Bocina"
	_horn.stream = horn_sound
	add_child(_horn)
	_apply_lights()
	_apply_lever()


func _unhandled_input(event: InputEvent) -> void:
	if not _can_drive():
		return
	if event.is_action_pressed(&"move_forward"):
		set_notch(notch + 1)
	elif event.is_action_pressed(&"move_back"):
		set_notch(notch - 1)
	elif event.is_action_pressed(&"lights"):
		set_lights(not lights_on)
	elif event.is_action_pressed(&"horn"):
		sound_horn()
	var motion := event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(-motion.relative.x * mouse_sensitivity, -motion.relative.y * mouse_sensitivity)


func _physics_process(_delta: float) -> void:
	var want_brake: bool = _can_drive() and Input.is_action_pressed(&"jump")
	if want_brake != braking:
		set_braking(want_brake)


func get_vehicle() -> Vehicle:
	return _vehicle


func get_occupant() -> Player:
	return _occupant


func is_occupied() -> bool:
	return _occupant != null


func get_camera() -> Camera3D:
	return _camera


## Si el jugador puede entrar: la cabina está libre, el jugador va enganchado a este vehículo
## y está a `enter_radius` o menos del puesto (sin contar la altura).
func can_enter(player: Player) -> bool:
	if player == null or is_occupied() or _vehicle == null or _camera == null:
		return false
	if player.get_platform() != _vehicle:
		return false
	return horizontal_distance_to(player.global_position) <= enter_radius


## Distancia en el plano de la cabina (sin la altura) desde el puesto hasta un punto.
func horizontal_distance_to(point: Vector3) -> float:
	var local: Vector3 = global_transform.affine_inverse() * point
	return Vector2(local.x, local.z).length()


## La ocupa un jugador: pasa a su cámara, mirando hacia adelante. La llama Player.
func occupy(player: Player) -> void:
	_occupant = player
	look_yaw = 0.0
	look_pitch = 0.0
	_apply_look()
	_camera.make_current()


## Queda libre. El freno se suelta; la marcha queda puesta. La llama Player.
func release() -> void:
	_occupant = null
	_camera.current = false
	if braking:
		set_braking(false)


## Mueve la palanca a esa muesca (se limita a las que hay) y ajusta el acelerador.
func set_notch(value: int) -> void:
	var clamped: int = clamp_notch(value, forward_notches, reverse_notches)
	if clamped == notch:
		return
	notch = clamped
	if _vehicle != null:
		_vehicle.throttle = get_throttle()
	_apply_lever()
	controls_changed.emit()


func get_throttle() -> float:
	return throttle_for_notch(notch, forward_notches, reverse_notches)


func set_braking(value: bool) -> void:
	braking = value
	if _vehicle != null:
		_vehicle.brake = 1.0 if value else 0.0
	controls_changed.emit()


func set_lights(value: bool) -> void:
	lights_on = value
	_apply_lights()
	controls_changed.emit()


func sound_horn() -> void:
	if _horn.stream != null:
		_horn.play()
	horn_sounded.emit()


## Gira la cabeza (radianes), dentro de los límites.
func look(yaw_amount: float, pitch_amount: float) -> void:
	var max_yaw: float = deg_to_rad(max_look_yaw_degrees)
	look_yaw = clampf(look_yaw + yaw_amount, -max_yaw, max_yaw)
	look_pitch = clampf(look_pitch + pitch_amount, deg_to_rad(min_look_pitch_degrees), deg_to_rad(max_look_pitch_degrees))
	_apply_look()


## Hacia dónde mira la cabeza en el mundo (0 mira hacia -Z), para que la 3ª persona
## salga mirando lo mismo.
func get_view_yaw() -> float:
	return Player.facing_yaw(-global_basis.z) + look_yaw


# Con el inventario abierto (controles apagados) no se maneja.
func _can_drive() -> bool:
	return _occupant != null and _occupant.controls_enabled


func _apply_look() -> void:
	if _camera != null:
		_camera.rotation = Vector3(look_pitch, look_yaw, 0.0)


func _apply_lights() -> void:
	for light: Light3D in lights:
		if light != null:
			light.visible = lights_on


func _apply_lever() -> void:
	if _lever != null:
		# Adelante inclina la palanca hacia el frente (-Z).
		_lever.rotation.x = -deg_to_rad(lever_degrees_per_notch) * notch
