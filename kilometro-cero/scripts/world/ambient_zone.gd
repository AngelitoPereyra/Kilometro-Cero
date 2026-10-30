class_name AmbientZone
extends Node3D
## Sonido por zona (tarea 62c.3c, adelanta D131): viento en el pasto, pájaros en el monte, agua en
## el arroyo. Suena entero a menos de `radius` de la cámara y se apaga del todo `fade` metros más
## allá; con `along` mide la distancia a esa curva (el arroyo) en vez de al nodo. Si no tiene
## `stream`, arma el sonido sola con ruido (provisorio, hasta que haya sonidos de verdad).
## ECHO todavía no suena: queda para la trinchera de la sierra (62c.7).

enum Kind { WIND, BIRDS, WATER, ECHO }

const MIX_RATE: float = 11025.0
const BUFFER_SECONDS: float = 0.3
const SILENT_WEIGHT: float = 0.01

@export var kind: Kind = Kind.WIND
@export_range(0.0, 100000.0, 1.0, "suffix:m") var radius: float = 60.0
@export_range(1.0, 1000.0, 1.0, "suffix:m") var fade: float = 40.0
@export_range(-60.0, 12.0, 0.5, "suffix:dB") var volume_db: float = -14.0
@export var stream: AudioStream
@export var along: NodePath

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _path: Path3D
var _weight: float = 0.0
# Estado del ruido.
var _rng := RandomNumberGenerator.new()
var _brown: float = 0.0
var _low: float = 0.0
var _time: float = 0.0
var _chirp_left: float = 0.0
var _next_chirp: float = 1.0
var _chirp_phase: float = 0.0


func _ready() -> void:
	_rng.seed = hash(name)
	_path = get_node_or_null(along) as Path3D if not along.is_empty() else null
	_player = AudioStreamPlayer.new()
	_player.name = "Sonido"
	if stream != null:
		_player.stream = stream
	else:
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = MIX_RATE
		generator.buffer_length = BUFFER_SECONDS
		_player.stream = generator
	add_child(_player)


## Lógica pura: cuánto suena (0 a 1) a esa distancia.
static func zone_weight(distance: float, zone_radius: float, zone_fade: float) -> float:
	return 1.0 - smoothstep(zone_radius, zone_radius + zone_fade, distance)


## Distancia desde un punto global a la zona (al nodo, o a la curva de `along`).
func distance_to_point(point: Vector3) -> float:
	if _path != null and _path.curve != null and _path.curve.point_count >= 2:
		var local: Vector3 = _path.to_local(point)
		return _path.to_global(_path.curve.get_closest_point(local)).distance_to(point)
	return global_position.distance_to(point)


func get_weight() -> float:
	return _weight


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	_weight = zone_weight(distance_to_point(camera.global_position), radius, fade)
	if _weight < SILENT_WEIGHT or (kind == Kind.ECHO and stream == null):
		if _player.playing:
			_player.stop()
			_playback = null
		return
	_player.volume_db = volume_db + linear_to_db(_weight)
	if not _player.playing:
		_player.play()
		_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _playback != null:
		_fill(_playback.get_frames_available())


func _fill(frames: int) -> void:
	for _i: int in frames:
		var sample: float = _next_sample()
		_playback.push_frame(Vector2(sample, sample))


func _next_sample() -> float:
	var step: float = 1.0 / MIX_RATE
	_time += step
	var white: float = _rng.randf_range(-1.0, 1.0)
	match kind:
		Kind.WIND:
			_brown = clampf(_brown + white * 0.02, -1.0, 1.0) * 0.998
			var gust: float = 0.55 + 0.3 * sin(_time * 0.35) + 0.15 * sin(_time * 1.3)
			return _brown * gust * 2.2
		Kind.WATER:
			_low += (white - _low) * 0.35
			var babble: float = 0.6 + 0.4 * sin(_time * 9.0 + sin(_time * 2.3) * 3.0)
			return _low * babble * 0.5
		Kind.BIRDS:
			_next_chirp -= step
			if _next_chirp <= 0.0:
				_chirp_left = 0.12
				_next_chirp = _rng.randf_range(0.6, 2.8)
			if _chirp_left <= 0.0:
				return 0.0
			_chirp_left -= step
			var pitch: float = lerpf(4200.0, 2400.0, _chirp_left / 0.12)
			_chirp_phase = fmod(_chirp_phase + TAU * pitch * step, TAU)
			return sin(_chirp_phase) * 0.25 * sin(PI * _chirp_left / 0.12)
	return 0.0
