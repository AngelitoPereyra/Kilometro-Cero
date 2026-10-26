class_name GrowthCelebration
extends Node3D
## Festejo del crecimiento (D79, tarea 60): va como hijo "Festejo" de una Station, a la altura
## donde tiene que aparecer el cartel. Cuando la estación crece jugando (Station.grew), lo
## nuevo de cada nivel "brota" de a una pieza (escala de casi 0 a la suya, con rebote y un
## poco de polvo), suena una campana, salen papelitos y flota un cartel "¡Pueblo creció!".
## Al cargar la escena no festeja: lo que ya estaba aparece quieto.

## Terminó de armar el festejo de ese nivel (las piezas siguen brotando un rato).
signal celebrated(level: int)

## Segundos que tarda en brotar cada pieza.
const POP_TIME: float = 0.6
## Segundos entre una pieza y la siguiente.
const POP_STAGGER: float = 0.15
## Escala con la que arranca una pieza que brota.
const POP_START_SCALE: float = 0.01
## Segundos que flota el cartel antes de borrarse.
const MESSAGE_TIME: float = 4.0
## Metros que sube el cartel mientras se desvanece.
const MESSAGE_RISE: float = 2.0
# Guarda en cada pieza su escala real, por si vuelve a brotar antes de terminar.
const _SCALE_META: StringName = &"growth_scale"

## Campana del festejo (data/audio/growth_chime.wav, provisoria).
@export var sound: AudioStream
## Si saltan papelitos.
@export var confetti: bool = true

var _station: Station
var _audio: AudioStreamPlayer3D
var _confetti: CPUParticles3D
var _message: Label3D


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_station = get_parent() as Station
	if _station == null:
		push_warning("GrowthCelebration %s: tiene que ser hijo de una Station." % name)
		return
	_station.grew.connect(celebrate)
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = sound
	_audio.unit_size = 20.0
	add_child(_audio, false, Node.INTERNAL_MODE_FRONT)
	if confetti:
		_confetti = _make_particles(80, 2.5, 6.0, 0.15)
		_confetti.color_initial_ramp = _confetti_colors()
		add_child(_confetti, false, Node.INTERNAL_MODE_FRONT)


## Festeja haber crecido de `previous` a `level` (lo llama Station.grew; sirve también para
## probarlo a mano).
func celebrate(level: int, previous: int) -> void:
	var delay: float = 0.0
	for level_number: int in range(previous + 1, level + 1):
		var level_node: Node3D = _station.get_level_node(level_number)
		if level_node == null:
			continue
		for piece: Node3D in get_pieces(level_node):
			pop(piece, delay)
			delay += POP_STAGGER
	if _audio.stream != null:
		_audio.play()
	if _confetti != null:
		_confetti.restart()
	_show_message(level)
	celebrated.emit(level)


## El cartel que está flotando, o null.
func get_message() -> Label3D:
	return _message if is_instance_valid(_message) else null


## Lógica pura: las piezas que brotan de un nodo de nivel (sus hijos 3D que se ven: no el
## sonido ni las luces sueltas).
static func get_pieces(level_node: Node) -> Array[Node3D]:
	var pieces: Array[Node3D] = []
	for child: Node in level_node.get_children():
		if child is Node3D and not child is AudioStreamPlayer3D and not child is Light3D:
			pieces.append(child)
	return pieces


## Hace brotar una pieza: de casi nada a su escala, con rebote, después de `delay` segundos.
static func pop(piece: Node3D, delay: float = 0.0) -> void:
	var target: Vector3 = piece.get_meta(_SCALE_META, piece.scale)
	piece.set_meta(_SCALE_META, target)
	piece.scale = target * POP_START_SCALE
	var tween: Tween = piece.create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(_puff.bind(piece))
	tween.tween_property(piece, "scale", target, POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# Una nubecita de polvo al pie de la pieza que brota.
static func _puff(piece: Node3D) -> void:
	if not piece.is_inside_tree():
		return
	var dust: CPUParticles3D = _make_particles(16, 1.0, 1.5, 0.3)
	dust.color = Color(0.75, 0.68, 0.55, 0.8)
	dust.gravity = Vector3(0, 0.5, 0)
	piece.get_parent().add_child(dust)
	dust.global_position = Vector3(piece.global_position.x, piece.get_parent_node_3d().global_position.y, piece.global_position.z)
	dust.emitting = true
	dust.finished.connect(dust.queue_free)


static func _make_particles(amount: int, lifetime: float, velocity: float, size: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.emitting = false
	particles.direction = Vector3.UP
	particles.spread = 60.0
	particles.initial_velocity_min = velocity * 0.5
	particles.initial_velocity_max = velocity
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size, size, size * 0.2)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	particles.mesh = mesh
	return particles


static func _confetti_colors() -> Gradient:
	# Los colores salen al azar de este degradé (rojo, amarillo, verde, celeste).
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	gradient.colors = PackedColorArray([Color(0.9, 0.2, 0.2), Color(1.0, 0.85, 0.2), Color(0.3, 0.8, 0.3), Color(0.3, 0.7, 1.0)])
	return gradient


func _show_message(level: int) -> void:
	if is_instance_valid(_message):
		_message.queue_free()
	_message = Label3D.new()
	_message.text = "¡%s creció!\nNivel %d" % [_station.get_display_name(), level]
	_message.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_message.font_size = 128
	_message.outline_size = 24
	_message.modulate = Color(1.0, 0.85, 0.3)
	_message.no_depth_test = true
	add_child(_message, false, Node.INTERNAL_MODE_FRONT)
	var tween: Tween = _message.create_tween().set_parallel()
	tween.tween_property(_message, "position:y", MESSAGE_RISE, MESSAGE_TIME)
	tween.tween_property(_message, "modulate:a", 0.0, MESSAGE_TIME * 0.4).set_delay(MESSAGE_TIME * 0.6)
	tween.chain().tween_callback(_message.queue_free)
