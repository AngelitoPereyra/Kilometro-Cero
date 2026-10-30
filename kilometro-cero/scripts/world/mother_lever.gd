class_name MotherLever
extends Interactable
## Palanca madre de un cambio (tarea 61e.2, D117), de bosquejo: un poste con un brazo junto a la
## aguja, del lado de la principal. Con F elige a qué vía se entra por esa punta: pasa a la vía que
## sigue y la reserva (RailNetwork.reserve_track): pone el cambio para ella, lo traba y la vía queda
## bloqueada en sus dos puntas (sus carteles de entrada en rojo) hasta que un tren termina de pasar
## el cambio; ahí el cambio vuelve solo a la principal. Después de la última vía vuelve a la
## principal. Para salir de una vía se usa la palanca de esa vía (TrackLever) y la principal da el
## paso o no. La crea RailNetwork junto a cada cambio y arma sus mallas sola.

const POST_HEIGHT: float = 0.9
const ARM_LENGTH: float = 1.0
const ARM_TILT: float = 35.0
const LABEL_RANGE: float = 25.0
## Cada cuánto mira el estado del cambio (segundos).
const REFRESH_TIME: float = 0.25
## Cuánto queda a la vista el motivo de un rechazo (segundos).
const MESSAGE_TIME: float = 3.0

var network: RailNetwork
var track_switch: TrackSwitch

var _arm: Node3D
var _knob: MeshInstance3D
var _label: Label3D
var _main_material: StandardMaterial3D
var _other_material: StandardMaterial3D
var _refresh_left: float = 0.0
var _message_left: float = 0.0


func _ready() -> void:
	var post := MeshInstance3D.new()
	post.name = "Poste"
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.35, POST_HEIGHT, 0.35)
	post.mesh = post_mesh
	post.position = Vector3(0.0, POST_HEIGHT * 0.5, 0.0)
	add_child(post)
	_arm = Node3D.new()
	_arm.name = "Brazo"
	_arm.position = Vector3(0.0, POST_HEIGHT, 0.0)
	add_child(_arm)
	var rod := MeshInstance3D.new()
	var rod_mesh := BoxMesh.new()
	rod_mesh.size = Vector3(0.1, ARM_LENGTH, 0.1)
	rod.mesh = rod_mesh
	rod.position = Vector3(0.0, ARM_LENGTH * 0.5, 0.0)
	_arm.add_child(rod)
	_main_material = _make_material(Color(0.95, 0.95, 0.9))
	_other_material = _make_material(Color(0.95, 0.75, 0.1))
	_knob = MeshInstance3D.new()
	# Cambia de color al moverla: LookPainter no la repinta.
	_knob.set_meta(LookPainter.KEEP_META, true)
	var knob_mesh := SphereMesh.new()
	knob_mesh.radius = 0.14
	knob_mesh.height = 0.28
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
	return network != null and track_switch != null and super.can_interact(player)


func get_prompt() -> String:
	if track_switch == null:
		return "Usar"
	var next: int = _next_option()
	if next < 0:
		return "Volver el cambio a la principal"
	return "Reservar la %s" % track_switch.option_label(next)


## La vía que reservó esta palanca (el índice de su salida en el cambio), o -1.
func get_reserved_option() -> int:
	if track_switch == null or not track_switch.is_locked():
		return -1
	var index: int = track_switch.option_index(track_switch.locked_path)
	if index < 0 or not network.is_reserved(track_switch.locked_path, track_switch.locked_at_end):
		return -1
	return index


func _on_interact(_player: Player) -> void:
	if track_switch.is_locked() and get_reserved_option() < 0:
		_show_message("Trabado: paso pedido desde la %s" % track_switch.option_label(track_switch.option_index(track_switch.locked_path)))
		return
	var current: int = get_reserved_option()
	var next: int = _next_option()
	if current >= 0:
		network.cancel_route(track_switch.get_option_path(current), bool(track_switch.options[current][1]))
	if next < 0:
		if current < 0:
			# Sin reserva: el cambio vuelve a la principal (si un automático lo dejó en otra vía).
			for index: int in track_switch.option_count():
				if track_switch.is_main_option(index):
					track_switch.set_state(index)
					break
		_apply()
		return
	var problem: String = network.reserve_track(track_switch.get_option_path(next), bool(track_switch.options[next][1]))
	if problem != "":
		_show_message(problem)
		return
	_message_left = 0.0
	_apply()


# La próxima vía a reservar (no la principal), o -1 para volver a la principal.
func _next_option() -> int:
	var count: int = track_switch.option_count()
	var current: int = get_reserved_option()
	var start: int = current if current >= 0 else -1
	for step: int in range(1, count + 1):
		var index: int = start + step
		if index >= count:
			return -1
		if not track_switch.is_main_option(index):
			return index
	return -1


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
	if _arm == null or track_switch == null:
		return
	var on_main: bool = track_switch.is_main_option(track_switch.state)
	_arm.rotation_degrees = Vector3(0.0, 0.0, -ARM_TILT if on_main else ARM_TILT)
	_knob.material_override = _main_material if on_main else _other_material
	if _message_left > 0.0:
		return
	var reserved: int = get_reserved_option()
	if reserved >= 0:
		_label.text = "→ %s (reservada)" % track_switch.option_label(reserved)
	elif track_switch.is_locked():
		_label.text = "→ %s (paso pedido)" % track_switch.option_label(track_switch.state)
	else:
		_label.text = "→ %s" % track_switch.option_label(track_switch.state)


static func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
