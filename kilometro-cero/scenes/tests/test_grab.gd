extends Node3D
## Prueba de Hands + Holdable + Grabber + StorageArea + mochila (tareas 13 y 14).
## Genera objetos y una caja de carga delante del jugador, y muestra en
## pantalla lo que tenés en las manos, en la mochila, las necesidades y lo que pasa.

const WORLD_ITEM_SCENE: PackedScene = preload("res://scenes/items/world_item.tscn")
const HELP: String = "Clic izq: tomar · R/Q: soltar mano der/izq · F: guardar en mochila · G: sacar de mochila"

var _player: Player
var _hud: Label
var _message: String = HELP
var _ratio: float = 0.0
var _box_container: StorageContainer
var _box_label: Label3D


func _ready() -> void:
	_check_pure_logic()
	# Esperamos un cuadro de física: el orden de los _ready depende de dónde quedó
	# este nodo en el árbol, y además así se puede consultar el piso con un rayo.
	await get_tree().physics_frame
	_player = _find_player()
	if _player == null:
		push_error("test_grab: no encontré el Player en la escena.")
		return
	_build_hud()
	_spawn_items()
	_build_storage_box()
	_connect_feedback()
	_refresh_hud()


func _check_pure_logic() -> void:
	var base := Vector3(0.0, 0.3, -0.9)
	var ok: bool = true
	ok = ok and Grabber.hold_offset_for(2, 0, base, 0.35) == base
	ok = ok and is_equal_approx(Grabber.hold_offset_for(1, 0, base, 0.35).x, 0.35)
	ok = ok and is_equal_approx(Grabber.hold_offset_for(1, 1, base, 0.35).x, -0.35)
	print("Manos (lógica pura): ", "OK" if ok else "FALLÓ")

	var chatarra := ItemStack.new(_make_data(&"chatarra", ItemData.HandsRequired.ONE, 2.0, ItemData.SizeClass.SMALL))
	var riel := ItemStack.new(_make_data(&"riel", ItemData.HandsRequired.TWO, 40.0, ItemData.SizeClass.LARGE))
	var motor := ItemStack.new(_make_data(&"motor", ItemData.HandsRequired.CRANE, 500.0, ItemData.SizeClass.LARGE))
	var no_samples: Array[ItemStack] = []
	var empty: Array[ItemStack] = [null, null]
	var mixed: Array[ItemStack] = [null, riel, chatarra]
	var only_rail: Array[ItemStack] = [riel]

	var checks: Array[bool] = [
		Grabber.take_blocker(chatarra, 2, 10.0) == &"",
		Grabber.take_blocker(riel, 1, 100.0) == &"hands_full",
		Grabber.take_blocker(motor, 2, 1000.0) == &"too_big",
		Grabber.take_blocker(chatarra, 2, 1.0) == &"too_heavy",
		Grabber.first_takeable_zone(mixed, 1, 10.0) == 2,   # el riel no entra con una mano libre
		Grabber.first_takeable_zone(mixed, 2, 100.0) == 1,
		Grabber.first_takeable_zone(no_samples, 2, 10.0) == -1,
		Grabber.take_failure_reason(empty, 2, 10.0) == &"container_empty",
		Grabber.take_failure_reason(only_rail, 1, 100.0) == &"hands_full",
		Grabber.first_filled_hand(true, true) == 0,
		Grabber.first_filled_hand(false, true) == 1,
		Grabber.first_filled_hand(true, false) == 0,
		Grabber.first_filled_hand(false, false) == -1,
	]
	var passed: int = checks.count(true)
	print("Contenedores y mochila (lógica pura): %d de %d OK" % [passed, checks.size()])


func _find_player() -> Player:
	var scene_root: Node = get_tree().current_scene
	for node: Node in scene_root.find_children("*", "CharacterBody3D", true, false):
		var player := node as Player
		if player != null:
			return player
	return null


func _make_data(id: StringName, hands: ItemData.HandsRequired, weight: float,
		size: ItemData.SizeClass) -> ItemData:
	var data := ItemData.new()
	data.id = id
	data.hands = hands
	data.unit_weight = weight
	data.size_class = size
	return data


func _build_hud() -> void:
	# Un Label dentro de un CanvasLayer se dibuja encima de la escena 3D.
	var layer := CanvasLayer.new()
	_hud = Label.new()
	_hud.position = Vector2(16.0, 16.0)
	layer.add_child(_hud)
	add_child(layer)


func _spawn_items() -> void:
	# Una fila delante del jugador. El tamaño importa: decide en qué zona entra.
	var defs: Array[Dictionary] = [
		{"id": &"chatarra", "hands": ItemData.HandsRequired.ONE, "weight": 2.0, "size": ItemData.SizeClass.SMALL, "amount": 3},
		{"id": &"yerba", "hands": ItemData.HandsRequired.ONE, "weight": 1.0, "size": ItemData.SizeClass.SMALL, "amount": 1},
		{"id": &"comida", "hands": ItemData.HandsRequired.ONE, "weight": 0.5, "size": ItemData.SizeClass.SMALL, "amount": 1},
		{"id": &"durmiente", "hands": ItemData.HandsRequired.ONE, "weight": 8.0, "size": ItemData.SizeClass.MEDIUM, "amount": 2},
		{"id": &"riel", "hands": ItemData.HandsRequired.TWO, "weight": 40.0, "size": ItemData.SizeClass.LARGE, "amount": 1},
		{"id": &"yunque", "hands": ItemData.HandsRequired.ONE, "weight": 200.0, "size": ItemData.SizeClass.MEDIUM, "amount": 1},
		{"id": &"motor", "hands": ItemData.HandsRequired.CRANE, "weight": 500.0, "size": ItemData.SizeClass.LARGE, "amount": 1},
	]
	for i in defs.size():
		var data: ItemData = _make_data(defs[i]["id"], defs[i]["hands"], defs[i]["weight"], defs[i]["size"])
		var stack := ItemStack.new(data, defs[i]["amount"])
		var world_item := WORLD_ITEM_SCENE.instantiate() as WorldItem
		add_child(world_item)
		world_item.global_position = _player.global_position + Vector3(i * 0.9 - 2.7, 1.0, -3.0)
		world_item.setup(stack)
		world_item.name = String(data.id)
		world_item.add_child(_make_label(stack))
	print("test_grab: %d objetos generados." % defs.size())


# Cartel que siempre mira a la cámara, con nombre, cantidad, peso y manos.
func _make_label(stack: ItemStack) -> Label3D:
	var data: ItemData = stack.item
	var label := Label3D.new()
	label.text = "%s x%d\n%.1f kg · %s" % [data.id, stack.quantity, data.unit_weight, _hands_text(data.hands)]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.004
	label.font_size = 48
	label.position = Vector3(0.0, 0.45, 0.0)
	return label


func _hands_text(hands: ItemData.HandsRequired) -> String:
	match hands:
		ItemData.HandsRequired.ONE:
			return "1 mano"
		ItemData.HandsRequired.TWO:
			return "2 manos"
		_:
			return "solo grúa"


# Caja de carga: una plataforma con un volumen encima (el StorageArea) y un
# StorageContainer de 4 zonas: 2 chicas, 1 mediana y 1 grande.
func _build_storage_box() -> void:
	var origin: Vector3 = _player.global_position + Vector3(5.0, 0.0, -3.0)
	origin.y = _floor_height(origin)

	var box := Node3D.new()
	box.name = "CajaDeCarga"
	add_child(box)
	box.global_position = origin

	# Plataforma: se ve y tiene colisión con el mundo (capa 1), así lo rechazado queda apoyado.
	var pad := StaticBody3D.new()
	pad.position = Vector3(0.0, 0.1, 0.0)
	var pad_size := Vector3(1.8, 0.2, 1.8)
	var pad_shape := CollisionShape3D.new()
	var pad_box := BoxShape3D.new()
	pad_box.size = pad_size
	pad_shape.shape = pad_box
	pad.add_child(pad_shape)
	var pad_mesh := MeshInstance3D.new()
	var pad_mesh_box := BoxMesh.new()
	pad_mesh_box.size = pad_size
	pad_mesh.mesh = pad_mesh_box
	pad.add_child(pad_mesh)
	box.add_child(pad)

	# Contenedor: se arma solo en _ready porque ya tiene layout y config.
	var zones: Array[ZoneSpec] = [
		_zone(ItemData.SizeClass.SMALL, 2),
		_zone(ItemData.SizeClass.MEDIUM, 1),
		_zone(ItemData.SizeClass.LARGE, 1),
	]
	var layout := StorageLayout.new()
	layout.zones = zones
	_box_container = StorageContainer.new()
	_box_container.container_id = &"caja_test"
	_box_container.layout = layout
	# Reutilizamos el StorageConfig que ya usa la mochila del jugador.
	_box_container.config = _player.get_backpack().config
	box.add_child(_box_container)

	# Área: el volumen donde se guarda lo que se suelta. Va después del contenedor
	# y como su hermana (D42).
	var area := StorageArea.new()
	area.position = Vector3(0.0, 0.9, 0.0)
	var area_shape := CollisionShape3D.new()
	var area_box := BoxShape3D.new()
	area_box.size = Vector3(1.8, 1.4, 1.8)
	area_shape.shape = area_box
	area.add_child(area_shape)
	box.add_child(area)
	area.item_rejected.connect(_on_box_rejected)

	_box_label = Label3D.new()
	_box_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_box_label.pixel_size = 0.004
	_box_label.font_size = 40
	_box_label.position = Vector3(0.0, 2.1, 0.0)
	box.add_child(_box_label)
	_refresh_box_label()
	print("test_grab: caja de carga creada.")


func _zone(size: ItemData.SizeClass, count: int) -> ZoneSpec:
	var spec := ZoneSpec.new()
	spec.size_class = size
	spec.count = count
	return spec


# Piso bajo un punto, para apoyar la caja bien sin importar dónde esté el origen del Player.
func _floor_height(near: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
			near + Vector3.UP * 5.0, near + Vector3.DOWN * 20.0, WorldItem.LAYER_WORLD)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return near.y
	var point: Vector3 = hit["position"]
	return point.y


# Una línea por zona de un contenedor: "Zona 0 (SMALL): chatarra x3".
func _zone_lines(container: StorageContainer) -> PackedStringArray:
	var lines: PackedStringArray = []
	for i in container.get_zone_count():
		var stack: ItemStack = container.peek(i)
		var size_name: String = ItemData.SizeClass.keys()[container.get_zone_size(i)]
		var contents: String = "vacía" if stack == null else "%s x%d" % [stack.item.id, stack.quantity]
		lines.append("  Zona %d (%s): %s" % [i, size_name, contents])
	return lines


func _refresh_box_label() -> void:
	var lines: PackedStringArray = ["Caja de prueba"]
	lines.append_array(_zone_lines(_box_container))
	_box_label.text = "\n".join(lines)


func _connect_feedback() -> void:
	var grabber := get_tree().current_scene.find_child("Grabber", true, false) as Grabber
	if grabber == null:
		push_error("test_grab: no encontré un nodo llamado Grabber dentro del Player.")
		return
	grabber.grab_failed.connect(_on_grab_failed)
	EventBus.item_held.connect(_on_item_held)
	EventBus.item_released.connect(_on_item_released)
	EventBus.encumbrance_changed.connect(_on_encumbrance_changed)
	# Necesidades y reloj: se muestran en el HUD y se refrescan cuando cambian.
	EventBus.need_changed.connect(_on_need_changed)
	EventBus.time_advanced.connect(_on_time_advanced)
	_box_container.item_stored.connect(_on_box_stored)
	_box_container.item_taken.connect(_on_box_taken)
	var backpack: StorageContainer = _player.get_backpack()
	backpack.item_stored.connect(_on_backpack_stored)
	backpack.item_taken.connect(_on_backpack_taken)
	_ratio = _player.get_encumbrance().get_ratio()
	print("test_grab: Grabber conectado.")


func _on_item_held(stack: ItemStack) -> void:
	_say("Tomó: %s" % stack.item.id)


func _on_item_released(stack: ItemStack) -> void:
	_say("Soltó: %s" % stack.item.id)


func _on_box_stored(stack: ItemStack) -> void:
	_refresh_box_label()
	_say("La caja guardó: %s x%d" % [stack.item.id, stack.quantity])


func _on_box_taken(stack: ItemStack) -> void:
	_refresh_box_label()
	_say("Sacó de la caja: %s x%d" % [stack.item.id, stack.quantity])


func _on_backpack_stored(stack: ItemStack) -> void:
	_say("La mochila guardó: %s x%d" % [stack.item.id, stack.quantity])


func _on_backpack_taken(stack: ItemStack) -> void:
	_say("Sacó de la mochila: %s x%d" % [stack.item.id, stack.quantity])


func _on_box_rejected(leftover: ItemStack) -> void:
	_say("No entra en la caja: sobran %d de %s." % [leftover.quantity, leftover.item.id])


func _on_encumbrance_changed(ratio: float) -> void:
	_ratio = ratio
	_refresh_hud()


func _on_need_changed(_need: StringName, _value: float) -> void:
	_refresh_hud()


func _on_time_advanced(_hours: float) -> void:
	_refresh_hud()


func _on_grab_failed(reason: StringName) -> void:
	match reason:
		&"nothing_near":
			_say("No hay nada al alcance.")
		&"hands_full":
			_say("Las manos están ocupadas.")
		&"hands_empty":
			_say("No tenés nada en las manos para guardar.")
		&"too_big":
			_say("Es demasiado grande: hace falta una grúa.")
		&"too_heavy":
			_say("Pesa demasiado para cargarlo.")
		&"container_empty":
			_say("El contenedor está vacío.")
		&"no_room":
			_say("No entra en la mochila.")


func _say(text: String) -> void:
	_message = text
	print(text)
	_refresh_hud()


func _refresh_hud() -> void:
	var needs: Needs = _player.get_needs()
	var hands: Hands = _player.get_hands()
	var lines: PackedStringArray = []
	lines.append("Día %d · %s" % [GameState.clock.current_day, GameClock.format_time(GameState.clock.time_of_day)])
	lines.append("Agua %.0f · Comida %.0f · Fatiga %.0f" % [
		needs.get_value(Needs.WATER), needs.get_value(Needs.FOOD), needs.get_value(Needs.FATIGUE)])
	for i in Hands.HAND_COUNT:
		var stack: ItemStack = hands.get_stack(i)
		var hand_name: String = "derecha" if i == 0 else "izquierda"
		var contents: String = "—" if stack == null else "%s x%d" % [stack.item.id, stack.quantity]
		lines.append("Mano %s: %s" % [hand_name, contents])
	lines.append("Mochila:")
	lines.append_array(_zone_lines(_player.get_backpack()))
	lines.append("Carga: %.0f %%" % (_ratio * 100.0))
	lines.append(_message)
	_hud.text = "\n".join(lines)
