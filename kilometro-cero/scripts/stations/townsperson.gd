@tool
class_name Townsperson
extends Node3D
## Poblador de adorno (D79, tarea 60): un muñequito que pasea cerca de donde se lo puso, se
## detiene un rato y sigue. No choca ni se le habla (los que cuentan historias son
## MissionGiver). Dentro de "Niveles/NivelN" de una estación aparece desde ese nivel; mientras
## está escondido no camina. Su cuerpo es un BigHeadFigure (tarea 62c.3e, D140) que arma solo
## (también en el editor) con colores que salen de su nombre y su lugar, así cada uno es distinto
## y siempre el mismo; mueve piernas y brazos cuando camina.

## Metros que se aleja de donde se lo puso.
@export_range(0.5, 30.0, 0.1, "suffix:m") var wander_radius: float = 3.0
@export_range(0.1, 5.0, 0.1, "suffix:m/s") var walk_speed: float = 1.1
## Segundos que se queda quieto entre paseo y paseo (al azar entre los dos).
@export_range(0.0, 30.0, 0.1, "suffix:s") var pause_min: float = 1.0
@export_range(0.0, 30.0, 0.1, "suffix:s") var pause_max: float = 4.0
## Color de la ropa (se usa el más parecido de la paleta); transparente elige uno al azar.
@export var color: Color = Color(0, 0, 0, 0)

var _rng := RandomNumberGenerator.new()
var _home: Vector3
var _target: Vector3
var _wait: float = 0.0
var _walking: bool = false
var _body: BigHeadFigure


## Lógica pura: un punto al azar dentro del círculo de radio `radius` alrededor de `home`
## (`a` y `b` entre 0 y 1). Repartido parejo en el círculo, a la misma altura.
static func pick_target(home: Vector3, radius: float, a: float, b: float) -> Vector3:
	var angle: float = a * TAU
	var distance: float = sqrt(b) * radius
	return home + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)


## Lógica pura: el giro en Y para mirar (hacia -Z) en la dirección `direction`.
static func facing_angle(direction: Vector3) -> float:
	return atan2(direction.x, direction.z) + PI


func _ready() -> void:
	_rng.seed = hash(str(name, position))
	_build_body()
	if Engine.is_editor_hint():
		return
	_home = position
	_target = _home
	_wait = _rng.randf_range(0.0, pause_min)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_visible_in_tree():
		return
	if _wait > 0.0:
		_wait -= delta
		_set_walking(false)
		return
	var to_target: Vector3 = _target - position
	to_target.y = 0.0
	var step: float = walk_speed * delta
	if to_target.length() <= step:
		position = Vector3(_target.x, _home.y, _target.z)
		_target = pick_target(_home, wander_radius, _rng.randf(), _rng.randf())
		_wait = _rng.randf_range(pause_min, maxf(pause_min, pause_max))
		_set_walking(false)
		return
	var direction: Vector3 = to_target.normalized()
	position += direction * step
	rotation.y = facing_angle(direction)
	_set_walking(true)


## Dónde se lo puso (el centro de su paseo).
func get_home() -> Vector3:
	return _home


## Si está caminando ahora (no en una pausa).
func is_walking() -> bool:
	return _walking


## El cuerpo cabezón.
func get_figure() -> BigHeadFigure:
	return _body


func _set_walking(value: bool) -> void:
	_walking = value


# El cuerpo es interno (no se guarda en la escena), así se puede cambiar sin tocar las plantillas.
func _build_body() -> void:
	if _body != null:
		return
	_body = BigHeadFigure.new()
	_body.name = "Cuerpo"
	_body.look_seed = _rng.randi_range(1, 1 << 30)
	if color.a > 0.0:
		_body.shirt = Palette.NAMES[Palette.nearest(color)]
	add_child(_body, false, Node.INTERNAL_MODE_FRONT)
