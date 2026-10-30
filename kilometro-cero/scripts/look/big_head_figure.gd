@tool
class_name BigHeadFigure
extends Node3D
## Personaje cabezón estilo Alba (tarea 62c.3e, D140): piernas, cuerpo, brazos y una cabeza grande
## con pelo, nariz y dos puntitos de ojos, sin cara detallada; con boina, sombrero o gorra. Pinta
## con la paleta (Palette.figure_material: siempre con todo su color). Mide 1,7 m con los pies en
## y 0 y mira hacia -Z. Arma sus piezas solo (también en el editor) como hijos internos, así no se
## guardan en la escena. Lo que se deja vacío sale al azar según `look_seed` (0: según el nombre
## de quien lo tiene), así cada uno es distinto y siempre el mismo.
## Camina solo (`auto_walk`): mueve piernas y brazos según cuánto avanza, o según la velocidad del
## CharacterBody3D que lo lleva (el jugador: así no camina cuando viaja parado en el tren).

enum Hat { NONE, BERET, BRIMMED, CAP }

const SKINS: Array[StringName] = [&"piel_clara", &"piel_media", &"piel_morena"]
const HAIRS: Array[StringName] = [&"pelo", &"barro", &"durmiente", &"gris_claro", &"tierra"]
const SHIRTS: Array[StringName] = [&"ropa_azul", &"ropa_roja", &"ropa_verde", &"crema", &"ocre", &"celeste_pared", &"rosa_pared", &"blanco", &"mostaza", &"bordo"]
const PANTS: Array[StringName] = [&"ropa_gris", &"hierro", &"durmiente", &"ropa_azul", &"tierra", &"carbon"]
const HAT_COLORS: Array[StringName] = [&"carbon", &"ropa_azul", &"bordo", &"madera_clara", &"crema", &"verde_oscuro"]
## Altura de la cabeza (centro) y su radio: casi un tercio del cuerpo.
const HEAD_Y: float = 1.4
const HEAD_RADIUS: float = 0.29
## Cuánto se mueven al caminar: giro de piernas y brazos (radianes) y salto (metros).
const SWING: float = 0.6
const BOB: float = 0.05

@export var look_seed: int = 0:
	set(value):
		look_seed = value
		_rebuild_if_ready()
## Vacío: al azar.
@export var skin: StringName = &"":
	set(value):
		skin = value
		_rebuild_if_ready()
@export var hair: StringName = &"":
	set(value):
		hair = value
		_rebuild_if_ready()
@export var shirt: StringName = &"":
	set(value):
		shirt = value
		_rebuild_if_ready()
@export var pants: StringName = &"":
	set(value):
		pants = value
		_rebuild_if_ready()
@export var hat: Hat = Hat.NONE:
	set(value):
		hat = value
		_rebuild_if_ready()
## Si el sombrero sale al azar (entonces `hat` no cuenta).
@export var random_hat: bool = true:
	set(value):
		random_hat = value
		_rebuild_if_ready()
@export var hat_color: StringName = &"":
	set(value):
		hat_color = value
		_rebuild_if_ready()
@export var auto_walk: bool = true

var _root: Node3D
var _hips: Array[Node3D] = []
var _shoulders: Array[Node3D] = []
var _phase: float = 0.0
var _amount: float = 0.0
var _last_position: Vector3
var _body: CharacterBody3D
# Lo que eligió al armarse (para pruebas).
var _chosen: Dictionary[StringName, Variant] = {}


func _ready() -> void:
	rebuild()
	_last_position = global_position
	_body = _find_body()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not auto_walk or delta <= 0.0:
		return
	var speed: float
	if _body != null:
		speed = Vector2(_body.velocity.x, _body.velocity.z).length()
	else:
		var moved: Vector3 = global_position - _last_position
		speed = minf(Vector2(moved.x, moved.z).length() / delta, 6.0)
	_last_position = global_position
	animate(speed, delta)


## Mueve piernas y brazos para esa velocidad (m/s); quieto vuelve de a poco a pararse derecho.
func animate(speed: float, delta: float) -> void:
	_amount = move_toward(_amount, clampf(speed / 1.4, 0.0, 1.0), delta * 4.0)
	_phase = fmod(_phase + delta * (4.0 + speed * 3.0), TAU)
	var swing: float = sin(_phase) * SWING * _amount
	if _hips.size() == 2:
		_hips[0].rotation.x = swing
		_hips[1].rotation.x = -swing
		_shoulders[0].rotation.x = -swing * 0.8
		_shoulders[1].rotation.x = swing * 0.8
	if _root != null:
		_root.position.y = absf(sin(_phase)) * BOB * _amount


## Cuánto camina ahora (0 quieto, 1 a paso normal).
func get_walk_amount() -> float:
	return _amount


## Lo que eligió: skin, hair, shirt, pants, hat y hat_color.
func get_look() -> Dictionary[StringName, Variant]:
	return _chosen


## Lógica pura: lo que se pidió o, si está vacío, uno de la lista según el sorteo.
static func pick(wanted: StringName, options: Array[StringName], rng: RandomNumberGenerator) -> StringName:
	var drawn: StringName = options[rng.randi_range(0, options.size() - 1)]
	return wanted if wanted != &"" else drawn


## Vuelve a armar el cuerpo.
func rebuild() -> void:
	if _root != null:
		_root.free()
	_hips.clear()
	_shoulders.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = look_seed if look_seed != 0 else hash(String(_seed_node().name))
	_chosen = {}
	_chosen[&"skin"] = pick(skin, SKINS, rng)
	_chosen[&"hair"] = pick(hair, HAIRS, rng)
	_chosen[&"shirt"] = pick(shirt, SHIRTS, rng)
	_chosen[&"pants"] = pick(pants, PANTS, rng)
	var drawn_hat: int = rng.randi_range(0, Hat.size() - 1)
	_chosen[&"hat"] = drawn_hat if random_hat else int(hat)
	_chosen[&"hat_color"] = pick(hat_color, HAT_COLORS, rng)
	_root = Node3D.new()
	_root.name = "Figura"
	add_child(_root, false, Node.INTERNAL_MODE_FRONT)
	_build_body()
	_build_head()


func _build_body() -> void:
	var skin_name: StringName = _chosen[&"skin"]
	for side: float in [-1.0, 1.0]:
		var hip: Node3D = _pivot(Vector3(side * 0.1, 0.55, 0.0))
		_hips.append(hip)
		_add(hip, _capsule(0.085, 0.6), _chosen[&"pants"], Vector3(0.0, -0.27, 0.0))
		_add(hip, _box(Vector3(0.14, 0.08, 0.22)), &"carbon", Vector3(0.0, -0.52, -0.03))
		var shoulder: Node3D = _pivot(Vector3(side * 0.27, 1.05, 0.0))
		_shoulders.append(shoulder)
		_add(shoulder, _capsule(0.065, 0.46), _chosen[&"shirt"], Vector3(0.0, -0.2, 0.0))
		_add(shoulder, _sphere(0.07, 0.14), skin_name, Vector3(0.0, -0.43, 0.0))
	_add(_root, _capsule(0.21, 0.62), _chosen[&"shirt"], Vector3(0.0, 0.83, 0.0))


func _build_head() -> void:
	var skin_name: StringName = _chosen[&"skin"]
	_add(_root, _sphere(HEAD_RADIUS, HEAD_RADIUS * 1.94), skin_name, Vector3(0.0, HEAD_Y, 0.0))
	_add(_root, _sphere(0.3, 0.42), _chosen[&"hair"], Vector3(0.0, HEAD_Y + 0.12, 0.04))
	_add(_root, _sphere(0.05, 0.1), skin_name, Vector3(0.0, HEAD_Y - 0.02, -HEAD_RADIUS + 0.01))
	for side: float in [-1.0, 1.0]:
		_add(_root, _sphere(0.028, 0.056), &"carbon", Vector3(side * 0.09, HEAD_Y + 0.05, -HEAD_RADIUS + 0.015))
	var color: StringName = _chosen[&"hat_color"]
	match _chosen[&"hat"]:
		Hat.BERET:
			var beret: MeshInstance3D = _add(_root, _cylinder(0.27, 0.3, 0.08), color, Vector3(0.03, HEAD_Y + 0.26, 0.02))
			beret.rotation.z = -0.15
		Hat.BRIMMED:
			_add(_root, _cylinder(0.42, 0.42, 0.03), color, Vector3(0.0, HEAD_Y + 0.22, 0.0))
			_add(_root, _cylinder(0.24, 0.26, 0.2), color, Vector3(0.0, HEAD_Y + 0.33, 0.0))
		Hat.CAP:
			_add(_root, _cylinder(0.27, 0.27, 0.14), color, Vector3(0.0, HEAD_Y + 0.26, 0.0))
			_add(_root, _box(Vector3(0.3, 0.02, 0.16)), &"carbon", Vector3(0.0, HEAD_Y + 0.2, -0.3))


func _pivot(at: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	_root.add_child(pivot)
	return pivot


func _add(parent: Node3D, mesh: Mesh, swatch: StringName, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = Palette.figure_material(swatch)
	instance.position = at
	parent.add_child(instance)
	return instance


func _seed_node() -> Node:
	if owner != null:
		return owner
	return get_parent() if get_parent() != null else self


func _find_body() -> CharacterBody3D:
	var node: Node = get_parent()
	while node != null:
		if node is CharacterBody3D:
			return node as CharacterBody3D
		node = node.get_parent()
	return null


func _rebuild_if_ready() -> void:
	if is_node_ready():
		rebuild()


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 4
	return mesh


static func _sphere(radius: float, height: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 6
	return mesh


static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	return mesh


static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh
