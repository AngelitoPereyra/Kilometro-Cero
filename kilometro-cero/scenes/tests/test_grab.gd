extends Node3D
## Prueba de la mano, el Grabber, la recogida por tamaño, StorageArea, la mochila
## de ranuras y la colocación (tareas 13 a 15b y 48). Genera objetos y una caja de carga delante
## del jugador, y muestra en pantalla lo que tenés en la mano, en la mochila
## y lo que pasa. Sin peso ni necesidades desde la tarea 47 (D75, D86).

const WORLD_ITEM_SCENE: PackedScene = preload("res://scenes/items/world_item.tscn")
const BOX_CONFIG: StorageConfig = preload("res://data/config/storage_config.tres")
## Ranuras de la mochila de prueba: con 4, el quinto tipo de objeto pequeño ya no entra.
const TEST_BACKPACK_SLOTS: int = 4
const ALERT_NAMES: Array[String] = ["normal", "casi llena", "llena"]
const HELP: String = "E: recolectar · Q: soltar · Clic der: soltar (mantener: apuntar, rueda: girar)"

var _player: Player
var _grabber: Grabber
var _hud: Label
var _crosshair: Label
var _message: String = HELP
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
	_use_test_backpack()
	_build_hud()
	_spawn_items()
	_build_storage_box()
	_connect_feedback()
	_refresh_hud()


# El HUD se refresca siempre: así la línea de diagnóstico muestra los giros en vivo.
func _process(_delta: float) -> void:
	if _player == null or _hud == null:
		return
	_place_crosshair()
	_refresh_hud()


func _check_pure_logic() -> void:
	var base := Vector3(0.0, 0.3, -0.9)
	var offsets_ok: bool = true
	offsets_ok = offsets_ok and Grabber.hold_offset_for(2, base, 0.35) == base
	offsets_ok = offsets_ok and is_equal_approx(Grabber.hold_offset_for(1, base, 0.35).x, 0.35)
	print("Mano (posición): ", "OK" if offsets_ok else "FALLÓ")

	var small := ItemData.SizeClass.SMALL
	var medium := ItemData.SizeClass.MEDIUM
	var large := ItemData.SizeClass.LARGE
	var one := ItemData.HandsRequired.ONE
	var two := ItemData.HandsRequired.TWO
	var crane := ItemData.HandsRequired.CRANE
	# plan_pickup(tamaño, manos, mano ocupada, el nuevo entra en la mochila, lo de la mano entra)
	var checks: Array[bool] = [
		Grabber.plan_pickup(small, one, false, true, true) == &"to_backpack",
		Grabber.plan_pickup(small, one, false, false, true) == &"no_room",
		Grabber.plan_pickup(small, one, true, true, false) == &"to_backpack",   # un pequeño no usa la mano
		Grabber.plan_pickup(medium, one, false, true, true) == &"to_hand",
		Grabber.plan_pickup(medium, one, true, true, true) == &"swap",
		Grabber.plan_pickup(medium, one, true, true, false) == &"no_room",
		Grabber.plan_pickup(large, two, false, false, true) == &"to_hand",
		Grabber.plan_pickup(large, two, true, false, true) == &"swap",
		Grabber.plan_pickup(large, two, true, false, false) == &"no_room",
		Grabber.plan_pickup(large, crane, false, true, true) == &"too_big",
		Grabber.plan_pickup(small, crane, false, true, true) == &"too_big",
		Grabber.is_ok_plan(&"swap"),
		not Grabber.is_ok_plan(&"no_room"),
	]
	var passed: int = checks.count(true)
	print("Recogida por tamaño (lógica pura): %d de %d OK" % [passed, checks.size()])


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
	# Mira: el fantasma de colocación apunta hacia acá (la altura la fija el Grabber).
	_crosshair = Label.new()
	_crosshair.text = "+"
	layer.add_child(_crosshair)
	add_child(layer)


func _place_crosshair() -> void:
	if _crosshair == null:
		return
	var aim_y: float = _grabber.aim_screen_y if _grabber != null else 0.4
	var size: Vector2 = get_viewport().get_visible_rect().size
	_crosshair.position = Vector2(size.x * 0.5, size.y * aim_y) - _crosshair.size * 0.5


func _spawn_items() -> void:
	# Dos filas delante del jugador. El tamaño decide a dónde va cada uno:
	# los 5 pequeños a la mochila (que acá tiene 4 ranuras: el quinto no entra),
	# los medianos y grandes a la mano.
	var defs: Array[Dictionary] = [
		{"id": &"chatarra", "hands": ItemData.HandsRequired.ONE, "weight": 2.0, "size": ItemData.SizeClass.SMALL, "amount": 3},
		{"id": &"yerba", "hands": ItemData.HandsRequired.ONE, "weight": 1.0, "size": ItemData.SizeClass.SMALL, "amount": 1},
		{"id": &"comida", "hands": ItemData.HandsRequired.ONE, "weight": 0.5, "size": ItemData.SizeClass.SMALL, "amount": 1},
		{"id": &"bulones", "hands": ItemData.HandsRequired.ONE, "weight": 0.2, "size": ItemData.SizeClass.SMALL, "amount": 20},
		{"id": &"ramitas", "hands": ItemData.HandsRequired.ONE, "weight": 0.1, "size": ItemData.SizeClass.SMALL, "amount": 10},
		{"id": &"durmiente", "hands": ItemData.HandsRequired.ONE, "weight": 8.0, "size": ItemData.SizeClass.MEDIUM, "amount": 2},
		{"id": &"tabla", "hands": ItemData.HandsRequired.ONE, "weight": 3.0, "size": ItemData.SizeClass.MEDIUM, "amount": 1},
		{"id": &"riel", "hands": ItemData.HandsRequired.TWO, "weight": 40.0, "size": ItemData.SizeClass.LARGE, "amount": 1},
		{"id": &"yunque", "hands": ItemData.HandsRequired.ONE, "weight": 200.0, "size": ItemData.SizeClass.MEDIUM, "amount": 1},
		{"id": &"motor", "hands": ItemData.HandsRequired.CRANE, "weight": 500.0, "size": ItemData.SizeClass.LARGE, "amount": 1},
	]
	for i in defs.size():
		var data: ItemData = _make_data(defs[i]["id"], defs[i]["hands"], defs[i]["weight"], defs[i]["size"])
		var stack := ItemStack.new(data, defs[i]["amount"])
		var world_item := WORLD_ITEM_SCENE.instantiate() as WorldItem
		add_child(world_item)
		var column: float = float(i % 5) * 1.0 - 2.0
		var row: float = floorf(float(i) / 5.0)
		world_item.global_position = _player.global_position + Vector3(column, 1.0, -3.0 - 1.5 * row)
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
	# La mochila ya no usa StorageConfig (tarea 48): la caja carga el de siempre.
	_box_container.config = BOX_CONFIG
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


# Una línea por ranura de la mochila: "Ranura 0: chatarra x3".
func _slot_lines(inventory: Inventory) -> PackedStringArray:
	var lines: PackedStringArray = []
	for i in inventory.get_slot_count():
		var stack: ItemStack = inventory.peek(i)
		var contents: String = "vacía" if stack == null else "%s x%d" % [stack.item.id, stack.quantity]
		lines.append("  Ranura %d: %s" % [i, contents])
	return lines


# Mochila chica para ver en vivo el "no entra" y las alertas (D59) sin juntar 20 tipos.
func _use_test_backpack() -> void:
	var data := BackpackData.new()
	data.slot_count = TEST_BACKPACK_SLOTS
	if _player.backpack_data != null:
		data.small_stack_limit = _player.backpack_data.small_stack_limit
		data.medium_stack_limit = _player.backpack_data.medium_stack_limit
	_player.get_backpack().setup(data)


func _refresh_box_label() -> void:
	var lines: PackedStringArray = ["Caja de prueba"]
	lines.append_array(_zone_lines(_box_container))
	_box_label.text = "\n".join(lines)


func _connect_feedback() -> void:
	_grabber = get_tree().current_scene.find_child("Grabber", true, false) as Grabber
	if _grabber == null:
		push_error("test_grab: no encontré un nodo llamado Grabber dentro del Player.")
		return
	_grabber.grab_failed.connect(_on_grab_failed)
	EventBus.item_held.connect(_on_item_held)
	EventBus.item_released.connect(_on_item_released)
	EventBus.item_placed.connect(_on_item_placed)
	_box_container.item_stored.connect(_on_box_stored)
	_box_container.item_taken.connect(_on_box_taken)
	var backpack: Inventory = _player.get_backpack()
	backpack.item_stored.connect(_on_backpack_stored)
	backpack.item_taken.connect(_on_backpack_taken)
	EventBus.backpack_alert_changed.connect(_on_backpack_alert_changed)
	print("test_grab: Grabber conectado.")


func _on_item_held(stack: ItemStack) -> void:
	_say("En la mano: %s" % stack.item.id)


func _on_item_released(stack: ItemStack) -> void:
	_say("Salió de la mano: %s" % stack.item.id)


func _on_item_placed(stack: ItemStack, where: Vector3) -> void:
	var me: Vector3 = _player.global_position
	_say("Colocó: %s en (%.1f, %.1f, %.1f) · jugador en (%.1f, %.1f, %.1f)" % [
		stack.item.id, where.x, where.y, where.z, me.x, me.y, me.z])
	# Diagnóstico: medio segundo después, ¿dónde quedó realmente el objeto?
	await get_tree().create_timer(0.5).timeout
	for node: Node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var placed := node as WorldItem
		if placed != null and placed.stack == stack:
			var final_position: Vector3 = placed.global_position
			_say("Quedó en (%.1f, %.1f, %.1f): a %.1f m de lo pedido" % [
				final_position.x, final_position.y, final_position.z, final_position.distance_to(where)])
			return


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


func _on_backpack_alert_changed(alert: int) -> void:
	_say("Alerta de la mochila: %s" % ALERT_NAMES[alert])


func _on_box_rejected(leftover: ItemStack) -> void:
	_say("No entra en la caja: sobran %d de %s." % [leftover.quantity, leftover.item.id])


func _on_grab_failed(reason: StringName) -> void:
	match reason:
		&"nothing_near":
			_say("No hay nada al alcance.")
		&"hands_empty":
			_say("No tenés nada en la mano.")
		&"too_big":
			_say("Es demasiado grande: hace falta una grúa.")
		&"container_empty":
			_say("El contenedor está vacío.")
		&"no_room":
			_say("No entra en la mochila.")
		&"place_invalid":
			_say("No se puede colocar ahí.")
		&"not_placeable":
			_say("Este objeto no tiene un nodo Placeable: agregalo a world_item.tscn.")


func _say(text: String) -> void:
	_message = text
	print(text)


func _refresh_hud() -> void:
	var hands: Hands = _player.get_hands()
	var lines: PackedStringArray = []
	lines.append("Día %d · %s" % [GameState.clock.current_day, GameClock.format_time(GameState.clock.time_of_day)])
	var held: ItemStack = hands.get_held()
	var held_text: String = "—"
	if held != null:
		held_text = "%s x%d (%s)" % [held.item.id, held.quantity, _hands_text(held.item.hands)]
	lines.append("Mano: %s" % held_text)
	var backpack: Inventory = _player.get_backpack()
	lines.append("Mochila (%d/%d ranuras, %s):" % [backpack.get_used_slot_count(), backpack.get_slot_count(), ALERT_NAMES[backpack.get_alert()]])
	lines.append_array(_slot_lines(backpack))
	lines.append(_message)
	lines.append(_diagnostic_line())
	_hud.text = "\n".join(lines)


# Diagnóstico: sirve para ver si la mano sigue al cuerpo o a la cámara, y en qué
# estado está el modo apuntar.
func _diagnostic_line() -> String:
	var camera: ThirdPersonCamera = _player.get_camera()
	var camera_deg: float = rad_to_deg(camera.yaw) if camera != null else 0.0
	var line: String = "[diag] Cuerpo %.0f° · Cámara %.0f°" % [rad_to_deg(_player.get_facing_yaw()), camera_deg]
	if _grabber != null:
		line += " · Apuntando: %s · Válido: %s · Giro: %.0f°" % [
			"sí" if _grabber.is_placing() else "no",
			"sí" if _grabber.is_place_valid() else "no",
			rad_to_deg(_grabber.get_yaw_offset())]
	return line
