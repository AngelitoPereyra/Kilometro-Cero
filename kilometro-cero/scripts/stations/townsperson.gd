@tool
class_name Townsperson
extends Node3D
## Poblador de adorno (D79, tarea 60): un muñequito que pasea cerca de donde se lo puso, se
## detiene un rato y sigue. No choca ni se le habla (los que cuentan historias son
## MissionGiver). Dentro de "Niveles/NivelN" de una estación aparece desde ese nivel; mientras
## está escondido no camina. Arma su cuerpo solo (también en el editor) con un color que sale
## de su nombre y su lugar, así cada uno es distinto y siempre el mismo.

## Metros que se aleja de donde se lo puso.
@export_range(0.5, 30.0, 0.1, "suffix:m") var wander_radius: float = 3.0
@export_range(0.1, 5.0, 0.1, "suffix:m/s") var walk_speed: float = 1.1
## Segundos que se queda quieto entre paseo y paseo (al azar entre los dos).
@export_range(0.0, 30.0, 0.1, "suffix:s") var pause_min: float = 1.0
@export_range(0.0, 30.0, 0.1, "suffix:s") var pause_max: float = 4.0
## Color de la ropa; transparente elige uno al azar según el nombre.
@export var color: Color = Color(0, 0, 0, 0)

const CLOTHES: PackedColorArray = [
	Color(0.75, 0.25, 0.2), Color(0.25, 0.4, 0.7), Color(0.3, 0.55, 0.3), Color(0.85, 0.7, 0.3),
	Color(0.55, 0.35, 0.6), Color(0.9, 0.9, 0.85), Color(0.35, 0.3, 0.25),
]
const SKIN: PackedColorArray = [Color(0.95, 0.8, 0.65), Color(0.8, 0.6, 0.45), Color(0.6, 0.42, 0.3)]
## Altura (m) del rebote al caminar.
const BOB_HEIGHT: float = 0.06

var _rng := RandomNumberGenerator.new()
var _home: Vector3
var _target: Vector3
var _wait: float = 0.0
var _walking: bool = false
var _step_phase: float = 0.0
var _body: Node3D


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
	_step_phase += delta * walk_speed * 6.0
	if _body != null:
		_body.position.y = absf(sin(_step_phase)) * BOB_HEIGHT


## Dónde se lo puso (el centro de su paseo).
func get_home() -> Vector3:
	return _home


## Si está caminando ahora (no en una pausa).
func is_walking() -> bool:
	return _walking


func _set_walking(value: bool) -> void:
	_walking = value
	if not value and _body != null:
		_body.position.y = 0.0


# Cuerpo de bosquejo: cápsula con la ropa y una esfera de cabeza. Es interno (no se guarda en
# la escena), así el muñeco se puede reemplazar después sin tocar las plantillas.
func _build_body() -> void:
	if _body != null:
		return
	var clothes: Color = color if color.a > 0.0 else CLOTHES[_rng.randi_range(0, CLOTHES.size() - 1)]
	var skin: Color = SKIN[_rng.randi_range(0, SKIN.size() - 1)]
	_body = Node3D.new()
	_body.name = "Cuerpo"
	add_child(_body, false, Node.INTERNAL_MODE_FRONT)
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.25
	torso_mesh.height = 1.2
	_body.add_child(_mesh_at(torso_mesh, clothes, Vector3(0, 0.6, 0)))
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.2
	head_mesh.height = 0.4
	_body.add_child(_mesh_at(head_mesh, skin, Vector3(0, 1.42, 0)))
	# Una nariz para ver hacia dónde mira.
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.06, 0.06, 0.1)
	_body.add_child(_mesh_at(nose_mesh, skin, Vector3(0, 1.42, -0.22)))


func _mesh_at(mesh: Mesh, albedo: Color, at: Vector3) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	return instance
