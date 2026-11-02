class_name BoarHerd
extends Node3D
## Grupo de jabalíes (tarea 62c.3h, D143): al empezar suelta entre `min_count` y `max_count` jabalíes
## (Boar) alrededor de su lugar (la querencia), apoyados en el Terrain. Cuando cazan a todos, a las
## `respawn_hours` de juego vuelve a soltar el grupo entero, si el jugador no está mirando de cerca.
## Se ponen en el monte y la sierra, lejos de las vías y los pueblos.

const GROUP: StringName = &"boar_herds"
## Si el jugador está más cerca que esto, la vuelta del grupo espera.
const RESPAWN_CLEARANCE: float = 90.0

@export_range(1, 6, 1) var min_count: int = 2
@export_range(1, 6, 1) var max_count: int = 3
## Radio en el que nacen.
@export_range(1.0, 30.0, 0.5, "suffix:m") var spread: float = 6.0
@export_range(1.0, 240.0, 1.0, "suffix:h") var respawn_hours: float = 48.0
## Semilla del tamaño del grupo (0: según el nombre del nodo).
@export var seed_value: int = 0

var _boars: Array[Boar] = []
var _hours_empty: float = 0.0


## Cuántos jabalíes tiene un grupo con esta semilla. Lógica pura.
static func herd_size(seed_number: int, minimum: int, maximum: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_number
	return rng.randi_range(mini(minimum, maximum), maxi(minimum, maximum))


## Jabalíes vivos a menos de `radius` metros (en el plano) de `point`.
static func count_near(tree: SceneTree, point: Vector3, radius: float) -> int:
	var count: int = 0
	for node: Node in tree.get_nodes_in_group(Boar.GROUP):
		var boar := node as Boar
		if boar == null or boar.is_queued_for_deletion():
			continue
		if Vector2(boar.global_position.x - point.x, boar.global_position.z - point.z).length() < radius:
			count += 1
	return count


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	EventBus.time_advanced.connect(_on_time_advanced)
	# El terreno arma su forma en su _ready: se espera un cuadro de física.
	await get_tree().physics_frame
	spawn()


func get_boars() -> Array[Boar]:
	var alive: Array[Boar] = []
	for boar: Variant in _boars:
		if is_instance_valid(boar) and not (boar as Node).is_queued_for_deletion():
			alive.append(boar)
	_boars = alive
	return _boars


func get_alive_count() -> int:
	return get_boars().size()


## Suelta el grupo entero. Devuelve cuántos nacieron.
func spawn() -> int:
	if not is_inside_tree():
		return 0
	var count: int = herd_size(seed_value if seed_value != 0 else hash(String(name)), min_count, max_count)
	var terrain := get_tree().get_first_node_in_group(Terrain.GROUP) as Terrain
	var parent: Node = get_parent() if get_parent() != null else self
	for i: int in count:
		var angle: float = TAU * float(i) / float(count) + 0.7
		var spot: Vector3 = global_position + Vector3(cos(angle), 0.0, sin(angle)) * spread * (0.5 + 0.5 * float(i % 2))
		var ground: float = terrain.height_at(spot) if terrain != null else NAN
		if not is_nan(ground):
			spot.y = ground
		var boar := Boar.new()
		boar.name = "%sJabali%d" % [name, i + 1]
		boar.home = global_position
		parent.add_child(boar)
		boar.global_position = spot + Vector3.UP * 0.3
		boar.died.connect(_on_boar_died)
		_boars.append(boar)
	_hours_empty = 0.0
	return count


func _on_boar_died(_boar: Boar) -> void:
	_hours_empty = 0.0


func _on_time_advanced(hours: float) -> void:
	if get_alive_count() > 0:
		return
	_hours_empty += hours
	if _hours_empty < respawn_hours:
		return
	var player := get_tree().get_first_node_in_group(Player.GROUP) as Node3D
	if player != null and player.global_position.distance_to(global_position) < RESPAWN_CLEARANCE:
		return
	spawn()
