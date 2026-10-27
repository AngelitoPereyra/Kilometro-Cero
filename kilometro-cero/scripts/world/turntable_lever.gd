class_name TurntableLever
extends Interactable
## Palanca de una mesa giratoria (tarea 61e, pedido de Batmi): con F gira 180° el vehículo que
## está parado entero sobre la mesa, para que el jugador pueda dar vuelta su locomotora (los
## automáticos giran solos, AutoTrains). La mesa gira uno solo: un vehículo acoplado no gira (se
## desacopla con F en el enganche), tampoco uno automático ni uno en movimiento. Al terminar el
## vehículo queda mirando para el otro lado de la cola y sale de frente. La crea StationTracks
## junto a cada mesa y arma sus mallas sola.

const POST_HEIGHT: float = 0.9
const ARM_LENGTH: float = 1.0
const ARM_TILT: float = 35.0
## Segundos que tarda la mesa en dar media vuelta (como la de los automáticos).
const TURN_SECONDS: float = 4.0
## Por debajo de esta velocidad (m/s) el vehículo cuenta como quieto.
const STILL_SPEED: float = 0.1
const LABEL_RANGE: float = 25.0

## La malla de la mesa (gira mientras gira el vehículo).
var table: Node3D
## La cola de maniobras donde está la mesa.
var headshunt: Path3D
## Avance del centro de la mesa sobre la cola.
var spot: float = 0.0
var radius: float = 7.0

var _turning: Vehicle
var _brake_before: float = 0.0
var _time: float = 0.0
var _arm: Node3D
var _label: Label3D


func _ready() -> void:
	var post := MeshInstance3D.new()
	post.name = "Poste"
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.3, POST_HEIGHT, 0.3)
	post.mesh = post_mesh
	post.position = Vector3(0.0, POST_HEIGHT * 0.5, 0.0)
	add_child(post)
	_arm = Node3D.new()
	_arm.name = "Brazo"
	_arm.position = Vector3(0.0, POST_HEIGHT, 0.0)
	_arm.rotation_degrees = Vector3(0.0, 0.0, -ARM_TILT)
	add_child(_arm)
	var rod := MeshInstance3D.new()
	var rod_mesh := BoxMesh.new()
	rod_mesh.size = Vector3(0.08, ARM_LENGTH, 0.08)
	rod.mesh = rod_mesh
	rod.position = Vector3(0.0, ARM_LENGTH * 0.5, 0.0)
	_arm.add_child(rod)
	_label = Label3D.new()
	_label.name = "Cartel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.006
	_label.font_size = 32
	_label.outline_size = 8
	_label.position = Vector3(0.0, POST_HEIGHT + ARM_LENGTH + 0.5, 0.0)
	_label.visibility_range_end = LABEL_RANGE
	_label.text = "Mesa giratoria"
	add_child(_label)
	set_process(false)


func can_interact(player: Player) -> bool:
	return table != null and headshunt != null and _turning == null and super.can_interact(player)


func get_prompt() -> String:
	return "Girar la mesa"


func is_turning() -> bool:
	return _turning != null


## El vehículo que está entero sobre la mesa, o null.
func find_vehicle() -> Vehicle:
	if headshunt == null:
		return null
	for child: Node in headshunt.get_children():
		var vehicle := child as Vehicle
		if vehicle == null or vehicle.data == null or vehicle.is_queued_for_deletion():
			continue
		if absf(vehicle.progress - spot) + vehicle.data.length * 0.5 <= radius + 0.5:
			return vehicle
	return null


## Por qué no se puede girar ahora, o "" si se puede.
func why_not() -> String:
	if headshunt == null:
		return "Sin mesa"
	for child: Node in headshunt.get_children():
		var other := child as Vehicle
		if other != null and other.automatic:
			return "La mesa la está usando otro tren"
	var vehicle: Vehicle = find_vehicle()
	if vehicle == null:
		return "No hay ningún vehículo entero sobre la mesa"
	if vehicle.front != null or vehicle.rear != null:
		return "Desacoplá el vehículo: la mesa gira uno solo"
	if absf(vehicle.speed) > STILL_SPEED:
		return "Esperá a que se detenga"
	return ""


func _on_interact(_player: Player) -> void:
	var problem: String = why_not()
	if problem != "":
		_label.text = problem
		return
	_turning = find_vehicle()
	_brake_before = _turning.brake
	_turning.throttle = 0.0
	_turning.brake = 1.0
	_time = 0.0
	_arm.rotation_degrees = Vector3(0.0, 0.0, ARM_TILT)
	_label.text = "Girando..."
	set_process(true)


func _process(delta: float) -> void:
	if not is_instance_valid(_turning) or _turning.get_parent() != headshunt:
		_stop()
		return
	_time += delta
	var turned: float = minf(_time / TURN_SECONDS, 1.0)
	table.rotation.y = PI * turned
	_turning.model_yaw = PI * turned
	if turned >= 1.0:
		var vehicle: Vehicle = _turning
		var at: float = vehicle.progress
		_stop()
		# El giro pasa del modelo al vehículo: ahora mira para el otro lado de la cola.
		vehicle.place_on(headshunt, at, not vehicle.reversed)
		_label.text = "Listo: salí de frente"


func _stop() -> void:
	if is_instance_valid(_turning):
		_turning.model_yaw = 0.0
		_turning.brake = _brake_before
	_turning = null
	set_process(false)
	if table != null:
		table.rotation.y = 0.0
	_arm.rotation_degrees = Vector3(0.0, 0.0, -ARM_TILT)
	_label.text = "Mesa giratoria"
