class_name Boar
extends CharacterBody3D
## Jabalí (tarea 62c.3h, D143). Anda en grupos (BoarHerd) por el monte y la sierra. Pasea despacio
## cerca de su querencia; huye si el jugador se le acerca corriendo (o demasiado, aunque camine). Si
## le pegan y no cae, embiste: corre hacia el jugador y, si lo alcanza, le saca `charge_damage` de
## salud una sola vez y después huye. Cae con 3 golpes de machete (hijo Huntable) y suelta 2 carnes.
## Se arma solo (cuerpo, cabeza, patas y colmillos, sin modelo) y lejos del jugador no se procesa.

enum State { WANDER, FLEE, CHARGE }

signal died(boar: Boar)

const GROUP: StringName = &"boars"
## Más lejos del jugador que esto, queda quieto y sin procesar.
const ACTIVE_DISTANCE: float = 160.0
## Cuánto dura una embestida como máximo (s) antes de darse por vencido.
const CHARGE_SECONDS: float = 5.0
## A esta distancia (m, en el plano) la embestida pega.
const HIT_DISTANCE: float = 1.5

@export_range(0.2, 5.0, 0.1, "suffix:m/s") var walk_speed: float = 1.2
@export_range(1.0, 15.0, 0.1, "suffix:m/s") var run_speed: float = 6.5
## Si el jugador corre a menos de esto, huye.
@export_range(1.0, 40.0, 0.5, "suffix:m") var flee_run_distance: float = 12.0
## Si el jugador camina a menos de esto, huye igual.
@export_range(0.5, 20.0, 0.5, "suffix:m") var flee_walk_distance: float = 3.5
## Huye hasta quedar a esta distancia.
@export_range(5.0, 80.0, 1.0, "suffix:m") var safe_distance: float = 25.0
@export_range(0.0, 100.0, 1.0) var charge_damage: float = 15.0
## Radio del paseo alrededor de `home`.
@export_range(1.0, 100.0, 1.0, "suffix:m") var wander_radius: float = 18.0

## A quién mira (el jugador). Lo pone el BoarHerd; si falta, se busca en el grupo de Player.
var target: Node3D
## Centro del paseo (la querencia del grupo).
var home: Vector3
var state: State = State.WANDER

var _wander_to: Vector3
var _wander_wait: float = 0.0
var _charge_left: float = 0.0
var _rng := RandomNumberGenerator.new()
var _visual: Node3D


## Qué hace según la distancia al jugador. `provoked`: le acaban de pegar. Lógica pura.
static func decide(current: State, distance: float, player_running: bool, provoked: bool, flee_run: float, flee_walk: float, safe: float) -> State:
	if provoked:
		return State.CHARGE
	if current == State.CHARGE:
		return State.CHARGE
	if current == State.FLEE:
		return State.FLEE if distance < safe else State.WANDER
	if distance < flee_walk or (player_running and distance < flee_run):
		return State.FLEE
	return State.WANDER


## Hacia dónde huye: lejos del jugador, en el plano. Lógica pura.
static func flee_direction(from: Vector3, threat: Vector3) -> Vector3:
	var away := Vector3(from.x - threat.x, 0.0, from.z - threat.z)
	if away.length_squared() < 0.0001:
		return Vector3.FORWARD
	return away.normalized()


## true si la embestida alcanza. Lógica pura.
static func charge_hits(from: Vector3, threat: Vector3) -> bool:
	return Vector2(from.x - threat.x, from.z - threat.z).length() <= HIT_DISTANCE


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	floor_max_angle = deg_to_rad(50.0)
	if home == Vector3.ZERO:
		home = global_position
	_rng.seed = hash(name) ^ int(home.x * 13.0) ^ int(home.z * 7.0)
	_wander_to = home
	if get_node_or_null(^"Forma") == null:
		var shape := CollisionShape3D.new()
		shape.name = "Forma"
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.35
		capsule.height = 0.9
		shape.shape = capsule
		shape.position = Vector3(0.0, 0.45, 0.0)
		add_child(shape)
	if get_node_or_null(^"Visual") == null:
		_build_visual()
	_visual = get_node_or_null(^"Visual") as Node3D
	if get_node_or_null(^"Huntable") == null:
		var huntable := Huntable.new()
		huntable.name = "Huntable"
		huntable.required_tool = load("res://data/items/machete.tres") as KeyItemData
		huntable.hits_required = 3
		huntable.reach = 2.5
		huntable.drop_item = load("res://data/items/raw_meat.tres") as ItemData
		huntable.drop_amount = 2
		huntable.drop_radius = 0.6
		huntable.drop_height = 0.5
		add_child(huntable)


## Le pegaron y no cayó: embiste.
func provoke() -> void:
	state = State.CHARGE
	_charge_left = CHARGE_SECONDS


## Se cae: avisa al grupo y desaparece (la carne ya la soltó el Huntable).
func die() -> void:
	died.emit(self)
	queue_free()


func get_target() -> Node3D:
	if target != null and is_instance_valid(target):
		return target
	target = get_tree().get_first_node_in_group(Player.GROUP) as Node3D
	return target


func _physics_process(delta: float) -> void:
	var threat: Node3D = get_target()
	var distance: float = INF
	var running: bool = false
	if threat != null:
		distance = Vector2(threat.global_position.x - global_position.x, threat.global_position.z - global_position.z).length()
		var player := threat as Player
		running = player != null and player.sprinting
	if distance > ACTIVE_DISTANCE and state != State.CHARGE:
		velocity = Vector3.ZERO
		return
	state = decide(state, distance, running, false, flee_run_distance, flee_walk_distance, safe_distance)
	var move := Vector3.ZERO
	match state:
		State.WANDER:
			move = _wander(delta) * walk_speed
		State.FLEE:
			move = flee_direction(global_position, threat.global_position) * run_speed
		State.CHARGE:
			_charge_left -= delta
			if threat == null or _charge_left <= 0.0:
				state = State.FLEE
			elif charge_hits(global_position, threat.global_position):
				_hit(threat)
				state = State.FLEE
			else:
				move = -flee_direction(global_position, threat.global_position) * run_speed
	velocity.x = move.x
	velocity.z = move.z
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	if move.length_squared() > 0.01 and _visual != null:
		_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(-move.x, -move.z), minf(10.0 * delta, 1.0))


# Pasea: elige un punto cerca de la querencia, va caminando y espera un rato.
func _wander(delta: float) -> Vector3:
	if _wander_wait > 0.0:
		_wander_wait -= delta
		return Vector3.ZERO
	var to := Vector3(_wander_to.x - global_position.x, 0.0, _wander_to.z - global_position.z)
	if to.length() < 0.8:
		_wander_wait = _rng.randf_range(2.0, 7.0)
		var angle: float = _rng.randf() * TAU
		_wander_to = home + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(2.0, wander_radius)
		return Vector3.ZERO
	return to.normalized()


func _hit(threat: Node3D) -> void:
	var player := threat as Player
	var health: Health = player.get_health() if player != null else null
	if health != null:
		health.damage(charge_damage)
	EventBus.player_hurt.emit(charge_damage, &"boar")


# Cuerpo de cajas: lomo marrón oscuro, hocico, colmillos claros y cuatro patas.
func _build_visual() -> void:
	var visual := Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	var pelo := _material(Color(0.29, 0.22, 0.17))
	var hocico := _material(Color(0.42, 0.31, 0.25))
	var colmillo := _material(Color(0.93, 0.89, 0.78))
	_box(visual, Vector3(0.55, 0.5, 1.1), Vector3(0.0, 0.6, 0.05), pelo)
	_box(visual, Vector3(0.45, 0.42, 0.4), Vector3(0.0, 0.62, -0.68), pelo)
	_box(visual, Vector3(0.22, 0.2, 0.22), Vector3(0.0, 0.55, -0.95), hocico)
	_box(visual, Vector3(0.04, 0.12, 0.04), Vector3(0.1, 0.48, -1.02), colmillo)
	_box(visual, Vector3(0.04, 0.12, 0.04), Vector3(-0.1, 0.48, -1.02), colmillo)
	_box(visual, Vector3(0.5, 0.14, 0.8), Vector3(0.0, 0.88, 0.0), pelo)
	for x: float in [-0.18, 0.18]:
		for z: float in [-0.35, 0.4]:
			_box(visual, Vector3(0.12, 0.35, 0.12), Vector3(x, 0.18, z), pelo)


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material


static func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
