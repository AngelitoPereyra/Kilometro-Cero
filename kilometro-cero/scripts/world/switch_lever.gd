class_name SwitchLever
extends Interactable
## Palanca de un cambio de vía (tarea 61b, D113), de bosquejo: un poste con un brazo que se
## inclina hacia un lado o el otro y un cartel con la vía a la que lleva. Con F pasa a la salida
## que sigue; con un vehículo encima del cambio no se mueve. La crea RailNetwork junto a la aguja
## y arma sus mallas sola. Al principio el jugador se baja a moverla; más adelante lo hace un
## cambista o se maneja desde el tren (tarea 61c).

const POST_HEIGHT: float = 0.9
const ARM_LENGTH: float = 1.0
const ARM_TILT: float = 35.0
const LABEL_RANGE: float = 25.0

var track_switch: TrackSwitch:
	set(value):
		if track_switch != null and track_switch.state_changed.is_connected(_on_state_changed):
			track_switch.state_changed.disconnect(_on_state_changed)
		track_switch = value
		if track_switch != null:
			track_switch.state_changed.connect(_on_state_changed)
		_apply()

var _arm: Node3D
var _label: Label3D
var _main_material: StandardMaterial3D
var _other_material: StandardMaterial3D
var _knob: MeshInstance3D


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
	_main_material = _make_material(Color(0.95, 0.95, 0.9))
	_other_material = _make_material(Color(0.95, 0.75, 0.1))
	_knob = MeshInstance3D.new()
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
	return track_switch != null and super.can_interact(player)


func get_prompt() -> String:
	if track_switch == null:
		return "Usar"
	return "Mover el cambio a la %s" % track_switch.option_label(track_switch.next_state())


func _on_interact(_player: Player) -> void:
	if not track_switch.cycle():
		_label.text = "Hay un vehículo encima del cambio"


func _on_state_changed(_state: int) -> void:
	_apply()


func _apply() -> void:
	if _arm == null or track_switch == null:
		return
	var on_main: bool = track_switch.is_main_option(track_switch.state)
	_arm.rotation_degrees = Vector3(0.0, 0.0, -ARM_TILT if on_main else ARM_TILT)
	_knob.material_override = _main_material if on_main else _other_material
	_label.text = "→ %s" % track_switch.option_label(track_switch.state)


static func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
