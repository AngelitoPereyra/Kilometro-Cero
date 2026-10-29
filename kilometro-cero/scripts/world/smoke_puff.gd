class_name SmokePuff
extends Node3D
## Nube de humo con un "puf" (tarea 62b.3, D128): los trenes y vagones que aparecen o desaparecen
## de la nada lo hacen con humo, porque en el fondo es el viejo poniendo y sacando trenes de la
## maqueta. La usan el tren prestado (BorrowedTrains), los automáticos que se guardan y vuelven
## (AutoTrains.park_hidden) y los vagones de regalo (WagonGift).
## Escena scenes/world/smoke_puff.tscn: las partículas y el sonido se arman por código (el sonido
## es ruido filtrado que se apaga rápido; provisorio hasta los sonidos de la tarea 66). Se borra
## sola a los LIFETIME segundos.

const SCENE_PATH: String = "res://scenes/world/smoke_puff.tscn"
## Cuánto vive (s) antes de borrarse.
const LIFETIME: float = 2.5
const SOUND_RATE: int = 22050
const SOUND_SECONDS: float = 0.35

## Tamaño de la nube (1: un vehículo).
@export var size: float = 1.0
@export var sound: bool = true

static var _sound_stream: AudioStreamWAV

var _left: float = LIFETIME


## Una nube en `at` (global), colgada de `parent`. Null si `parent` no está en el árbol.
static func spawn(parent: Node, at: Vector3, puff_size: float = 1.0, with_sound: bool = true) -> SmokePuff:
	if parent == null or not parent.is_inside_tree():
		return null
	var puff := (load(SCENE_PATH) as PackedScene).instantiate() as SmokePuff
	puff.size = puff_size
	puff.sound = with_sound
	parent.add_child(puff)
	puff.global_position = at
	return puff


## Una nube sobre cada vehículo (un solo "puf", en el primero). Cuelgan de la escena actual, así
## siguen aunque el vehículo se borre. Devuelve cuántas puso.
static func at_vehicles(vehicles: Array) -> int:
	var count: int = 0
	for node: Variant in vehicles:
		if not is_instance_valid(node):
			continue
		var vehicle := node as Vehicle
		if vehicle == null or not vehicle.is_inside_tree():
			continue
		var tree: SceneTree = vehicle.get_tree()
		var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
		var length: float = vehicle.data.length if vehicle.data != null else 10.0
		if spawn(parent, vehicle.global_position + Vector3(0.0, 1.5, 0.0), clampf(length / 10.0, 0.6, 2.0), count == 0) != null:
			count += 1
	return count


## El "puf": ruido que pasa por un filtro bajo y se apaga rápido. Lógica pura (se arma una vez).
static func make_sound() -> AudioStreamWAV:
	if _sound_stream != null:
		return _sound_stream
	var samples: int = int(SOUND_RATE * SOUND_SECONDS)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 62
	var low: float = 0.0
	for index: int in samples:
		var t: float = float(index) / SOUND_RATE
		var envelope: float = exp(-t * 12.0) * minf(1.0, t * 200.0)
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.12)
		bytes.encode_s16(index * 2, int(clampf(low * envelope * 3.0, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SOUND_RATE
	stream.stereo = false
	stream.data = bytes
	_sound_stream = stream
	return stream


func _ready() -> void:
	add_child(_make_particles())
	if sound:
		var player := AudioStreamPlayer3D.new()
		player.name = "Puf"
		player.stream = make_sound()
		player.unit_size = 12.0
		player.pitch_scale = randf_range(0.85, 1.15)
		add_child(player)
		player.play()


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		queue_free()


func _make_particles() -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = "Humo"
	particles.one_shot = true
	particles.amount = 24
	particles.lifetime = 1.6
	particles.explosiveness = 0.9
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 1.5 * size
	particles.direction = Vector3.UP
	particles.spread = 70.0
	particles.initial_velocity_min = 1.0 * size
	particles.initial_velocity_max = 3.0 * size
	particles.gravity = Vector3(0.0, 0.8, 0.0)
	particles.damping_min = 1.5
	particles.damping_max = 2.5
	particles.scale_amount_min = 0.8 * size
	particles.scale_amount_max = 1.6 * size
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.5))
	particles.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.92, 0.92, 0.9, 0.9))
	fade.set_color(1, Color(0.8, 0.8, 0.8, 0.0))
	particles.color_ramp = fade
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	var mesh := SphereMesh.new()
	mesh.radius = 0.6
	mesh.height = 1.2
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = material
	particles.mesh = mesh
	particles.emitting = true
	return particles
