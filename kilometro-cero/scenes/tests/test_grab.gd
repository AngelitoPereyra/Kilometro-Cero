extends Node3D
## Prueba de Hands + Holdable + Grabber (tarea 13).
## Genera objetos delante del jugador, les pone un cartel y muestra en
## pantalla lo que tenés en las manos y lo que pasa al tomar o soltar.

const WORLD_ITEM_SCENE: PackedScene = preload("res://scenes/items/world_item.tscn")

var _player: Player
var _hud: Label
var _message: String = "Acercate a un cubo (menos de 2 m) y apretá grab."
var _ratio: float = 0.0


func _ready() -> void:
	_check_pure_logic()
	_player = _find_player()
	if _player == null:
		push_error("test_grab: no encontré el Player en la escena.")
		return
	_build_hud()
	_spawn_items()
	_connect_feedback()
	_refresh_hud()


func _check_pure_logic() -> void:
	var base := Vector3(0.0, 0.3, -0.9)
	var ok: bool = true
	ok = ok and Grabber.hold_offset_for(2, 0, base, 0.35) == base
	ok = ok and is_equal_approx(Grabber.hold_offset_for(1, 0, base, 0.35).x, 0.35)
	ok = ok and is_equal_approx(Grabber.hold_offset_for(1, 1, base, 0.35).x, -0.35)
	print("Lógica pura del Grabber: ", "OK" if ok else "FALLÓ")


func _find_player() -> Player:
	var scene_root: Node = get_tree().current_scene
	for node: Node in scene_root.find_children("*", "CharacterBody3D", true, false):
		var player := node as Player
		if player != null:
			return player
	return null


func _build_hud() -> void:
	# Un Label dentro de un CanvasLayer se dibuja encima de la escena 3D.
	var layer := CanvasLayer.new()
	_hud = Label.new()
	_hud.position = Vector2(16.0, 16.0)
	layer.add_child(_hud)
	add_child(layer)


func _spawn_items() -> void:
	# Una fila delante del jugador, bien juntos para que ninguno caiga del piso.
	var defs: Array[Dictionary] = [
		{"id": &"chatarra", "hands": ItemData.HandsRequired.ONE, "weight": 2.0},
		{"id": &"yerba", "hands": ItemData.HandsRequired.ONE, "weight": 1.0},
		{"id": &"comida", "hands": ItemData.HandsRequired.ONE, "weight": 0.5},
		{"id": &"riel", "hands": ItemData.HandsRequired.TWO, "weight": 40.0},
		{"id": &"yunque", "hands": ItemData.HandsRequired.ONE, "weight": 200.0},
		{"id": &"motor", "hands": ItemData.HandsRequired.CRANE, "weight": 500.0},
	]
	for i in defs.size():
		var data := ItemData.new()
		data.id = defs[i]["id"]
		data.hands = defs[i]["hands"]
		data.unit_weight = defs[i]["weight"]
		var world_item := WORLD_ITEM_SCENE.instantiate() as WorldItem
		add_child(world_item)
		world_item.global_position = _player.global_position + Vector3(i * 0.9 - 2.25, 1.0, -3.0)
		world_item.setup(ItemStack.new(data, 1))
		world_item.name = String(data.id)
		world_item.add_child(_make_label(data))
	print("test_grab: %d objetos generados." % defs.size())


# Cartel que siempre mira a la cámara, con nombre, peso y manos.
func _make_label(data: ItemData) -> Label3D:
	var label := Label3D.new()
	label.text = "%s\n%.1f kg · %s" % [data.id, data.unit_weight, _hands_text(data.hands)]
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


func _connect_feedback() -> void:
	var grabber := get_tree().current_scene.find_child("Grabber", true, false) as Grabber
	if grabber == null:
		push_error("test_grab: no encontré un nodo llamado Grabber dentro del Player.")
		return
	grabber.grab_failed.connect(_on_grab_failed)
	EventBus.item_held.connect(_on_item_held)
	EventBus.item_released.connect(_on_item_released)
	EventBus.encumbrance_changed.connect(_on_encumbrance_changed)
	_ratio = _player.get_encumbrance().get_ratio()
	print("test_grab: Grabber conectado.")


func _on_item_held(stack: ItemStack) -> void:
	_say("Tomó: %s" % stack.item.id)


func _on_item_released(stack: ItemStack) -> void:
	_say("Soltó: %s" % stack.item.id)


func _on_encumbrance_changed(ratio: float) -> void:
	_ratio = ratio
	_refresh_hud()


func _on_grab_failed(reason: StringName) -> void:
	match reason:
		&"nothing_near":
			_say("No hay nada al alcance.")
		&"hands_full":
			_say("Las manos están ocupadas.")
		&"too_big":
			_say("Es demasiado grande: hace falta una grúa.")
		&"too_heavy":
			_say("Pesa demasiado para cargarlo.")


func _say(text: String) -> void:
	_message = text
	print(text)
	_refresh_hud()


func _refresh_hud() -> void:
	var hands: Hands = _player.get_hands()
	var lines: PackedStringArray = []
	for i in Hands.HAND_COUNT:
		var stack: ItemStack = hands.get_stack(i)
		lines.append("Mano %d: %s" % [i, String(stack.item.id) if stack != null else "—"])
	lines.append("Carga: %.0f %%" % (_ratio * 100.0))
	lines.append(_message)
	_hud.text = "\n".join(lines)
