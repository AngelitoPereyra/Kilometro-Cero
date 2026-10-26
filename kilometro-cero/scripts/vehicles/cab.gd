class_name Cab
extends Node3D
## Puesto de manejo en 1ª persona (tarea 52, D84). Va dentro de la escena de una locomotora,
## como descendiente de su Vehicle. Su origen marca el piso donde se para el maquinista y su
## -Z mira hacia donde maneja. Hijos: `Camera3D` (obligatoria, a la altura de los ojos) y
## `Palanca` (opcional, se inclina con la marcha).
## La entrada y la salida las hace el jugador con F (Player.try_enter_cab y exit_cab), que
## llama a `occupy` y `release`. Mientras está ocupada, la cabina lee las teclas (D91):
## W y S mueven la palanca de marcha una muesca, Espacio frena mientras se mantiene, L prende
## y apaga las luces, H toca la bocina y O abre y cierra las puertas de los coches de pasajeros
## del tren (tarea 60b, acción `doors`); el mouse mira alrededor con límites.
## Tarea 60c: V (acción `camera_view`) alterna entre la vista de la cabina y una cámara
## exterior (`TrainCamera`, hija "CamaraExterior") que gira alrededor del tren con el mouse y se
## acerca con la rueda; las teclas de manejo andan igual en las dos. En la vista de la cabina
## la botonera (`CabButton`) se aprieta con el clic izquierdo apuntando con la mira del centro.
## Mientras está ocupada muestra un `CabHud` con la marcha, la velocidad y las teclas.
## Escribe en el vehículo solo cuando algo cambia (`throttle` y `brake`): al bajarse, el tren
## sigue con la marcha que quedó puesta, y las pruebas pueden manejarlo directamente.

signal controls_changed                  # cambió la marcha, el freno o las luces
signal horn_sounded
## Se pidieron las puertas: abiertas o cerradas, y si algún coche cambió (tarea 60b).
signal doors_toggled(is_open: bool, changed: bool)
## Cambió la vista (tarea 60c).
signal view_changed(view: View)

## Vista de la cabina en 1ª persona o cámara exterior del tren (tarea 60c).
enum View { CAB, EXTERIOR }

## Grupo de todas las cabinas (el jugador busca acá la más cercana).
const GROUP: StringName = &"cabs"
## Hasta dónde llega la mira para apretar un botón.
const AIM_DISTANCE: float = 1.6

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
## Vista elegida; se recuerda al volver a entrar.
var view: View = View.CAB
## Freno puesto con el botón: queda puesto hasta volver a apretarlo o mover la palanca.
var brake_latched: bool = false

var _vehicle: Vehicle
var _occupant: Player
var _horn: AudioStreamPlayer3D
var _exterior: TrainCamera
var _hud: CabHud
var _aimed: CabButton

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
	_exterior = TrainCamera.new()
	_exterior.name = "CamaraExterior"
	add_child(_exterior)
	_exterior.set_vehicle(_vehicle)
	_apply_lights()
	_apply_lever()


func _unhandled_input(event: InputEvent) -> void:
	if not _can_drive():
		return
	if event.is_action_pressed(&"move_forward"):
		press_control(&"forward")
	elif event.is_action_pressed(&"move_back"):
		press_control(&"back")
	elif event.is_action_pressed(&"lights"):
		press_control(&"lights")
	elif event.is_action_pressed(&"horn"):
		press_control(&"horn")
	elif InputMap.has_action(&"doors") and event.is_action_pressed(&"doors"):
		press_control(&"doors")
	elif InputMap.has_action(&"camera_view") and event.is_action_pressed(&"camera_view"):
		toggle_view()
	elif view == View.CAB and event.is_action_pressed(&"use_tool"):
		press_aimed()
	elif view == View.EXTERIOR and event.is_action_pressed(&"rotate_cw"):
		_exterior.zoom(-1.0)
	elif view == View.EXTERIOR and event.is_action_pressed(&"rotate_ccw"):
		_exterior.zoom(1.0)
	var motion := event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if view == View.CAB:
			look(-motion.relative.x * mouse_sensitivity, -motion.relative.y * mouse_sensitivity)
		else:
			_exterior.orbit(-motion.relative.x * mouse_sensitivity, -motion.relative.y * mouse_sensitivity)


func _physics_process(_delta: float) -> void:
	var want_brake: bool = is_occupied() and (brake_latched or (_can_drive() and Input.is_action_pressed(&"jump")))
	if want_brake != braking:
		set_braking(want_brake)


func _process(_delta: float) -> void:
	if not is_occupied():
		return
	_set_aimed(get_aimed_button() if view == View.CAB and _can_drive() else null)
	if _hud != null:
		_hud.refresh(self)


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
	if player.get_platform() != _vehicle or _vehicle.automatic:
		return false
	return horizontal_distance_to(player.global_position) <= enter_radius


## Distancia en el plano de la cabina (sin la altura) desde el puesto hasta un punto.
func horizontal_distance_to(point: Vector3) -> float:
	var local: Vector3 = global_transform.affine_inverse() * point
	return Vector2(local.x, local.z).length()


## La ocupa un jugador: pasa a la vista elegida (la cabina mirando hacia adelante, o la
## exterior detrás del tren) y muestra el CabHud. La llama Player.
func occupy(player: Player) -> void:
	_occupant = player
	look_yaw = 0.0
	look_pitch = 0.0
	_apply_look()
	_exterior.set_vehicle(_vehicle)
	_exterior.reset_view()
	_apply_view()
	if _hud == null:
		_hud = CabHud.new()
		_hud.name = "CabHud"
		add_child(_hud)
	_hud.refresh(self)


## Queda libre. El freno se suelta; la marcha queda puesta. La llama Player.
func release() -> void:
	_occupant = null
	_camera.current = false
	_exterior.current = false
	_set_aimed(null)
	brake_latched = false
	if braking:
		set_braking(false)
	if _hud != null:
		_hud.queue_free()
		_hud = null


func get_exterior_camera() -> TrainCamera:
	return _exterior


func get_hud() -> CabHud:
	return _hud


## Cambia de vista (tarea 60c). Ocupada, pasa a la cámara que corresponde.
func set_view(value: View) -> void:
	if value == view:
		return
	view = value
	if is_occupied():
		_apply_view()
	view_changed.emit(view)


func toggle_view() -> void:
	set_view(View.EXTERIOR if view == View.CAB else View.CAB)


## Hace lo mismo que su tecla (la usan las teclas y la botonera, tarea 60c): &"forward" y
## &"back" mueven la palanca, &"brake" pone o saca el freno, &"lights", &"horn" y &"doors".
## Devuelve si cambió algo.
func press_control(control: StringName) -> bool:
	match control:
		&"forward", &"back":
			var previous: int = notch
			set_notch(notch + (1 if control == &"forward" else -1))
			return notch != previous
		&"brake":
			set_brake_latched(not brake_latched)
			return true
		&"lights":
			set_lights(not lights_on)
			return true
		&"horn":
			sound_horn()
			return true
		&"doors":
			return toggle_doors()
	push_warning("Cab: control desconocido %s." % control)
	return false


## Pone o saca el freno de botón. Mover la palanca lo saca.
func set_brake_latched(value: bool) -> void:
	brake_latched = value
	controls_changed.emit()


## El botón de esta cabina que apunta la mira (el centro de la vista de la cabina), o null.
func get_aimed_button() -> CabButton:
	if _camera == null or not _camera.is_inside_tree():
		return null
	var from: Vector3 = _camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - _camera.global_basis.z * AIM_DISTANCE, CabButton.LAYER)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var button := hit.get("collider") as CabButton
	return button if button != null and button.get_cab() == self else null


## Aprieta el botón apuntado. Devuelve si había uno.
func press_aimed() -> bool:
	var button: CabButton = get_aimed_button()
	if button == null:
		return false
	button.press()
	return true


func get_aimed() -> CabButton:
	return _aimed if is_instance_valid(_aimed) else null


## Los botones de esta cabina.
func get_buttons() -> Array[CabButton]:
	var buttons: Array[CabButton] = []
	for node: Node in find_children("*", "CabButton", true, false):
		buttons.append(node as CabButton)
	return buttons


## Mueve la palanca a esa muesca (se limita a las que hay) y ajusta el acelerador.
func set_notch(value: int) -> void:
	var clamped: int = clamp_notch(value, forward_notches, reverse_notches)
	if clamped == notch:
		return
	notch = clamped
	brake_latched = false
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


## Los coches de pasajeros del tren de esta locomotora (tarea 60b).
func get_coaches() -> Array[PassengerCoach]:
	var coaches: Array[PassengerCoach] = []
	if _vehicle == null:
		return coaches
	for vehicle: Vehicle in _vehicle.get_train():
		var coach := vehicle as PassengerCoach
		if coach != null:
			coaches.append(coach)
	return coaches


## Abre las puertas de los coches del tren si estaban todas cerradas; si no, las cierra.
## Abrir solo funciona detenido en una estación. Devuelve si alguna cambió.
func toggle_doors() -> bool:
	var coaches: Array[PassengerCoach] = get_coaches()
	var open: bool = true
	for coach: PassengerCoach in coaches:
		if coach.doors_open:
			open = false
	var changed: bool = false
	for coach: PassengerCoach in coaches:
		changed = coach.set_doors(open) or changed
	doors_toggled.emit(open, changed)
	return changed


## Gira la cabeza (radianes), dentro de los límites.
func look(yaw_amount: float, pitch_amount: float) -> void:
	var max_yaw: float = deg_to_rad(max_look_yaw_degrees)
	look_yaw = clampf(look_yaw + yaw_amount, -max_yaw, max_yaw)
	look_pitch = clampf(look_pitch + pitch_amount, deg_to_rad(min_look_pitch_degrees), deg_to_rad(max_look_pitch_degrees))
	_apply_look()


## Hacia dónde mira la cabeza en el mundo (0 mira hacia -Z), para que la 3ª persona
## salga mirando lo mismo.
func get_view_yaw() -> float:
	if view == View.EXTERIOR and _exterior != null:
		return _exterior.get_view_yaw()
	return Player.facing_yaw(-global_basis.z) + look_yaw


# Con el inventario abierto (controles apagados) no se maneja.
func _can_drive() -> bool:
	return _occupant != null and _occupant.controls_enabled


func _apply_view() -> void:
	if view == View.CAB:
		_camera.make_current()
	else:
		_exterior.update_transform()
		_exterior.make_current()
		_set_aimed(null)


func _set_aimed(button: CabButton) -> void:
	if button == _aimed:
		return
	if is_instance_valid(_aimed):
		_aimed.set_hovered(false)
	_aimed = button
	if _aimed != null:
		_aimed.set_hovered(true)


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
