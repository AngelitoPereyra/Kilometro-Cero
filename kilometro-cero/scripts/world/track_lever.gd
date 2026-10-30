class_name TrackLever
extends Interactable
## Palanca de una vía de estación en una punta (tarea 61e.2, D117), de bosquejo: un poste con un
## brazo, junto al cartel de esa vía. La tienen las vías que no son la principal (la principal sale
## sola). Con F pide el paso por esa vía en esa punta (RailNetwork.request_route), para salir o para
## que entre un tren que llega: pone el cambio para ella y lo traba. La salida se pone en verde
## cuando lo que sigue está libre y la principal no la necesita; la entrada (el cartel de línea),
## cuando la vía está libre. Cuando un tren termina de pasar el cambio se suelta sola y el cambio
## vuelve a la principal. Tirada otra vez antes, cancela. Si no se puede (el cambio trabado por otra
## vía, un vehículo encima), el cartel de la palanca dice por qué. La crea AutoTrains con cada
## cartel de vía de estación y arma sus mallas sola.

const POST_HEIGHT: float = 0.9
const ARM_LENGTH: float = 1.0
const ARM_TILT: float = 35.0
const LABEL_RANGE: float = 25.0
## Cada cuánto mira el estado de la salida (segundos).
const REFRESH_TIME: float = 0.25
## Cuánto queda a la vista el motivo de un rechazo (segundos).
const MESSAGE_TIME: float = 3.0

var network: RailNetwork
var station_track: StationTrack
## La punta (true: el final de la curva).
var at_end: bool = false
## El cartel de esa salida (para mostrar si está en verde).
var signal_node: RailSignal

var _arm: Node3D
var _knob: MeshInstance3D
var _label: Label3D
var _idle_material: StandardMaterial3D
var _pulled_material: StandardMaterial3D
var _refresh_left: float = 0.0
var _message_left: float = 0.0


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
	add_child(_arm)
	var rod := MeshInstance3D.new()
	var rod_mesh := BoxMesh.new()
	rod_mesh.size = Vector3(0.08, ARM_LENGTH, 0.08)
	rod.mesh = rod_mesh
	rod.position = Vector3(0.0, ARM_LENGTH * 0.5, 0.0)
	_arm.add_child(rod)
	_idle_material = _make_material(Color(0.85, 0.15, 0.1))
	_pulled_material = _make_material(Color(0.15, 0.85, 0.25))
	_knob = MeshInstance3D.new()
	# Cambia de color al moverla: LookPainter no la repinta.
	_knob.set_meta(LookPainter.KEEP_META, true)
	var knob_mesh := SphereMesh.new()
	knob_mesh.radius = 0.12
	knob_mesh.height = 0.24
	_knob.mesh = knob_mesh
	_knob.position = Vector3(0.0, ARM_LENGTH, 0.0)
	_arm.add_child(_knob)
	_label = Label3D.new()
	_label.name = "Cartel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.006
	_label.font_size = 32
	_label.outline_size = 8
	_label.position = Vector3(0.0, POST_HEIGHT + ARM_LENGTH + 0.5, 0.0)
	_label.visibility_range_end = LABEL_RANGE
	add_child(_label)
	_apply()


func can_interact(player: Player) -> bool:
	return network != null and is_instance_valid(station_track) and super.can_interact(player)


func get_prompt() -> String:
	if is_requested():
		return "Cancelar el paso"
	return "Pedir paso por la %s" % station_track.get_label() if is_instance_valid(station_track) else "Pedir paso"


## Si el paso por esta vía en esta punta está pedido (el cambio trabado para ella).
func is_requested() -> bool:
	var path: Path3D = _path()
	return network != null and path != null and network.is_route_requested(path, at_end)


func _on_interact(_player: Player) -> void:
	var path: Path3D = _path()
	if path == null:
		return
	if network.is_route_requested(path, at_end):
		network.cancel_route(path, at_end)
		_show_message("Paso cancelado")
		return
	var problem: String = network.request_route(path, at_end)
	if problem != "":
		_show_message(problem)
		return
	_message_left = 0.0
	_apply()


func _process(delta: float) -> void:
	_message_left = maxf(0.0, _message_left - delta)
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH_TIME
	_apply()


func _show_message(text: String) -> void:
	_message_left = MESSAGE_TIME
	_apply()
	_label.text = text


func _apply() -> void:
	if _arm == null:
		return
	var requested: bool = is_requested()
	var green: bool = is_instance_valid(signal_node) and signal_node.clear
	# Tirada (hacia adelante) mientras la salida está pedida o en verde (un automático que sale).
	var pulled: bool = requested or green
	_arm.rotation_degrees = Vector3(ARM_TILT if pulled else -ARM_TILT, 0.0, 0.0)
	_knob.material_override = _pulled_material if pulled else _idle_material
	if _message_left > 0.0:
		return
	if green:
		_label.text = "Salida en verde"
	elif requested:
		_label.text = "Paso pedido: cambio puesto para esta vía"
	else:
		_label.text = "Salida cerrada"


func _path() -> Path3D:
	return station_track.get_track_path() if is_instance_valid(station_track) else null


static func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
