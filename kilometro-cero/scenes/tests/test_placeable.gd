extends Node3D
## Prueba de Placeable (tarea 15, parte 1): lógica pura y validación contra la física.
## No necesita jugador: arma un piso, un bloque y un objeto de obstáculo por código.

const WORLD_ITEM_SCENE: PackedScene = preload("res://scenes/items/world_item.tscn")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_check_pure_logic()
	var candidate: WorldItem = _build_world()
	# La física necesita un par de cuadros para registrar los cuerpos nuevos.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if candidate != null:
		_check_against_physics(candidate)
	print("Colocación: %d OK, %d con error" % [_passed, _failed])


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FALLÓ: " + message)


func _check_pure_logic() -> void:
	_check(Placeable.slope_ok(Vector3.UP, 30.0), "Piso plano: pendiente aceptable")
	_check(not Placeable.slope_ok(Vector3(1.0, 1.0, 0.0).normalized(), 30.0), "45°: demasiado empinado")
	_check(Placeable.slope_ok(Vector3(sin(deg_to_rad(20.0)), cos(deg_to_rad(20.0)), 0.0), 30.0), "20°: aceptable")

	var far: Vector3 = Placeable.clamp_to_range(Vector3.ZERO, Vector3(10.0, 2.0, 0.0), 3.0)
	_check(is_equal_approx(far.x, 3.0), "Lejos: se recorta al alcance")
	_check(is_equal_approx(far.y, 2.0), "Al recortar se conserva la altura")
	_check(Placeable.clamp_to_range(Vector3.ZERO, Vector3(1.0, 0.0, 1.0), 3.0) == Vector3(1.0, 0.0, 1.0),
			"Cerca: no se toca")

	_check(absf(angle_difference(Placeable.facing_yaw(0.0, 0.0), PI)) < 0.001, "El objeto mira a la cámara")
	_check(absf(angle_difference(Placeable.facing_yaw(1.0, 0.5), 1.0 + PI + 0.5)) < 0.001,
			"El giro de la cámara y el de la rueda se suman")

	_check(is_equal_approx(Placeable.rotate_offset(0.0, 1, 15.0), deg_to_rad(15.0)), "Un paso a la derecha")
	_check(is_equal_approx(Placeable.rotate_offset(0.0, -1, 15.0), -deg_to_rad(15.0)), "Un paso a la izquierda")
	_check(absf(angle_difference(Placeable.rotate_offset(deg_to_rad(175.0), 1, 15.0), deg_to_rad(-170.0))) < 0.001,
			"Da la vuelta completa sin saltos")


# Piso (su tope está en y = 0), un bloque de 1 m en x = 3, un objeto obstáculo
# en x = -3 y el objeto candidato, lejos y congelado, que es el que se consulta.
func _build_world() -> WorldItem:
	_add_static_box(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
	_add_static_box(Vector3(3.0, 0.5, 0.0), Vector3(1.0, 1.0, 1.0))

	var candidate: WorldItem = _spawn_item(&"candidato", Vector3(20.0, 5.0, 20.0))
	candidate.freeze = true
	if Holdable.of(candidate) == null or Placeable.of(candidate) == null:
		push_error("test_placeable: el WorldItem necesita hijos Holdable y Placeable. ¿Agregaste Placeable a world_item.tscn?")
		return null

	var obstacle: WorldItem = _spawn_item(&"obstaculo", Vector3(-3.0, 5.0, 0.0))
	# Se apoya en el piso igual que lo haría el candidato, sea cual sea su tamaño.
	obstacle.global_transform = Holdable.of(obstacle).body_transform_at(Vector3(-3.0, 0.0, 0.0), 0.0)
	obstacle.freeze = true
	return candidate


func _add_static_box(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = center


func _spawn_item(id: StringName, at: Vector3) -> WorldItem:
	var data := ItemData.new()
	data.id = id
	data.hands = ItemData.HandsRequired.ONE
	data.unit_weight = 1.0
	data.size_class = ItemData.SizeClass.SMALL
	var item := WORLD_ITEM_SCENE.instantiate() as WorldItem
	add_child(item)
	item.global_position = at
	item.setup(ItemStack.new(data, 1))
	return item


func _check_against_physics(candidate: WorldItem) -> void:
	var holdable: Holdable = Holdable.of(candidate)
	var placeable: Placeable = Placeable.of(candidate)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var up: Vector3 = Vector3.UP

	_check(placeable.is_valid_at(space, holdable.body_transform_at(Vector3(0.0, 0.0, 0.0), 0.0), up),
			"Piso libre: se puede colocar")
	_check(not placeable.is_valid_at(space, holdable.body_transform_at(Vector3(3.0, 0.5, 0.0), 0.0), up),
			"Dentro de un bloque: no se puede")
	_check(placeable.is_valid_at(space, holdable.body_transform_at(Vector3(3.0, 1.0, 0.0), 0.0), up),
			"Encima del bloque: se puede")
	_check(not placeable.is_valid_at(space, holdable.body_transform_at(Vector3(-3.0, 0.0, 0.0), 0.0), up),
			"Encima de otro objeto: no se puede")
	_check(not placeable.is_valid_at(space, holdable.body_transform_at(Vector3(0.0, 0.0, 0.0), 0.0), Vector3.RIGHT),
			"Superficie vertical: no se puede")
	_check(placeable.is_valid_at(space, holdable.body_transform_at(Vector3(0.0, 0.0, 0.0), 1.2), up),
			"Girado sobre el piso libre: se puede")
