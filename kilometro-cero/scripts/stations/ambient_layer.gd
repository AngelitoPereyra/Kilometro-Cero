class_name AmbientLayer
extends AudioStreamPlayer3D
## Capa de sonido de ambiente (D79, tarea 60): dentro de "Niveles/NivelN" de una estación suena
## desde ese nivel, así el pueblo suma capas al crecer (pájaros, gente, martillos, música).
## Entra y sale con un fundido, suena en loop y se oye cerca del pueblo (max_distance).
## Los sonidos de data/audio/ambient_*.wav son provisorios hasta definir la dirección sonora.

## Segundos del fundido de entrada y de salida.
@export_range(0.0, 10.0, 0.1, "suffix:s") var fade_time: float = 2.0
## Volumen al que llega (lineal, 0 a 1).
@export_range(0.0, 1.0, 0.01) var loudness: float = 1.0

var _fade: float = 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	volume_linear = 0.0
	finished.connect(_on_finished)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var target: float = loudness if is_visible_in_tree() else 0.0
	var speed: float = loudness / fade_time if fade_time > 0.0 else INF
	_fade = move_toward(_fade, target, speed * delta)
	volume_linear = _fade
	if _fade > 0.0 and not playing and stream != null:
		play()
	elif _fade <= 0.0 and playing:
		stop()


## Si se está oyendo (sonando con volumen).
func is_audible() -> bool:
	return playing and _fade > 0.0


## Cuánto del volumen tiene ahora (0 a `loudness`).
func get_fade() -> float:
	return _fade


# Loop: al terminar vuelve a empezar mientras siga sonando.
func _on_finished() -> void:
	if _fade > 0.0:
		play()
