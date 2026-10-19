extends Node
## Prueba de Hands y WorldItem (tarea 13, parte 1).
## Se corre con F6 con esta escena abierta; el resultado sale en "Salida".

var _passed: int = 0
var _failed: int = 0
# Se cuenta en una variable de la clase porque una lambda de GDScript
# captura las variables locales por valor y no podría modificarlas.
var _signal_count: int = 0


func _ready() -> void:
	_test_hands()
	_test_world_item()
	print("--- Hands/WorldItem: %d OK, %d con error ---" % [_passed, _failed])


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FALLÓ: " + message)


func _make_stack(id: StringName, hands: ItemData.HandsRequired,
		weight: float, amount: int = 1) -> ItemStack:
	var data := ItemData.new()
	data.id = id
	data.hands = hands
	data.unit_weight = weight
	return ItemStack.new(data, amount)


func _on_hands_changed() -> void:
	_signal_count += 1


func _test_hands() -> void:
	var hands := Hands.new()
	hands.hands_changed.connect(_on_hands_changed)

	_check(hands.free_hands() == 2, "empieza con 2 manos libres")
	_check(not hands.is_two_handed_occupied(), "empieza sin objeto de dos manos")

	var chatarra := _make_stack(&"chatarra", ItemData.HandsRequired.ONE, 2.0)
	var yerba := _make_stack(&"yerba", ItemData.HandsRequired.ONE, 1.0)
	var comida := _make_stack(&"comida", ItemData.HandsRequired.ONE, 0.5)
	var riel := _make_stack(&"riel", ItemData.HandsRequired.TWO, 40.0)
	var motor := _make_stack(&"motor", ItemData.HandsRequired.CRANE, 500.0)

	# Objetos de una mano
	_check(hands.hold(chatarra), "toma un objeto de una mano")
	_check(hands.free_hands() == 1, "queda 1 mano libre")
	_check(hands.hold(yerba), "toma un segundo objeto de una mano")
	_check(hands.free_hands() == 0, "no quedan manos libres")
	_check(not hands.hold(comida), "no toma un tercer objeto")
	_check(not hands.can_hold(chatarra), "no repite el mismo stack")
	_check(is_equal_approx(hands.get_total_weight(), 3.0), "peso = 2 + 1 kg")
	_check(_signal_count == 2, "2 señales por 2 tomas exitosas")

	# Soltar
	_check(hands.release(0) == chatarra, "release(0) devuelve el stack de la mano 0")
	_check(hands.free_hands() == 1, "después de soltar hay 1 mano libre")
	_check(hands.release(0) == null, "soltar una mano vacía devuelve null")
	_check(hands.release(-1) == null and hands.release(2) == null,
			"índices fuera de rango devuelven null")
	_check(_signal_count == 3, "soltar vacío o fuera de rango no emite señal")
	hands.release(1)

	# Dos manos
	_check(hands.hold(chatarra), "vuelve a tomar una de una mano")
	_check(not hands.can_hold(riel), "dos manos no entra con una mano ocupada")
	hands.release(0)
	_check(hands.hold(riel), "toma un objeto de dos manos con las manos vacías")
	_check(hands.free_hands() == 0, "dos manos ocupa ambas")
	_check(hands.is_two_handed_occupied(), "detecta objeto de dos manos")
	_check(is_equal_approx(hands.get_total_weight(), 40.0),
			"el peso de dos manos se cuenta una sola vez")
	_check(hands.get_stack(0) == hands.get_stack(1), "ambas manos apuntan al mismo stack")
	_check(hands.release(1) == riel, "soltar por la mano 1 devuelve el objeto de dos manos")
	_check(hands.free_hands() == 2, "soltar dos manos libera las dos")
	_check(not hands.is_two_handed_occupied(), "ya no hay objeto de dos manos")

	# Casos inválidos
	_check(not hands.can_hold(motor), "CRANE no se puede tomar a mano")
	_check(not hands.hold(null), "null no se puede tomar")
	hands.free()


func _test_world_item() -> void:
	var item := WorldItem.new()
	add_child(item)  # _ready configura grupo y capas al entrar al árbol
	var stack := _make_stack(&"bulones", ItemData.HandsRequired.ONE, 10.0, 3)
	item.setup(stack)
	_check(item.stack == stack, "WorldItem guarda su stack")
	_check(is_equal_approx(item.mass, 30.0), "masa = peso del lote (10 kg x3)")
	_check(item.collision_layer == WorldItem.LAYER_ITEMS, "está en la capa 3 (objetos sueltos)")
	_check(item.is_in_group(WorldItem.GROUP), "pertenece al grupo world_items")
	item.queue_free()
