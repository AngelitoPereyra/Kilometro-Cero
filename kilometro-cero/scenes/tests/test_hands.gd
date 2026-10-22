extends Node
## Prueba de Hands (una sola mano, D68) y WorldItem.
## Se corre con F6 con esta escena abierta; el resultado sale en "Salida".

var _passed: int = 0
var _failed: int = 0
# Se cuenta en una variable de la clase porque una lambda de GDScript
# captura las variables locales por valor y no podría modificarlas.
var _signal_count: int = 0


func _ready() -> void:
	_test_hands()
	_test_world_item()
	print("--- Manos: %d OK, %d con error ---" % [_passed, _failed])


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

	_check(Hands.hands_needed(ItemData.HandsRequired.ONE) == 1, "Una mano: se ve con 1")
	_check(Hands.hands_needed(ItemData.HandsRequired.TWO) == 2, "Dos manos: se ve con 2")
	_check(Hands.hands_needed(ItemData.HandsRequired.CRANE) == 0, "Grúa: no se toma a mano")

	_check(hands.is_empty(), "Empieza con la mano libre")
	_check(hands.get_held() == null, "Empieza sin nada")
	_check(is_zero_approx(hands.get_total_weight()), "Sin nada, el peso es 0")
	_check(not hands.is_two_handed_occupied(), "Empieza sin objeto de dos manos")

	var chatarra := _make_stack(&"chatarra", ItemData.HandsRequired.ONE, 2.0)
	var yerba := _make_stack(&"yerba", ItemData.HandsRequired.ONE, 1.0)
	var riel := _make_stack(&"riel", ItemData.HandsRequired.TWO, 40.0)
	var motor := _make_stack(&"motor", ItemData.HandsRequired.CRANE, 500.0)

	# Un objeto de una mano
	_check(hands.hold(chatarra), "Toma un objeto de una mano")
	_check(not hands.is_empty(), "Ya no está libre")
	_check(hands.get_held() == chatarra, "Guarda la referencia real, no una copia")
	_check(is_equal_approx(hands.get_total_weight(), 2.0), "Peso = 2 kg")
	_check(not hands.is_two_handed_occupied(), "Una mano no impide empujar la zorra")
	_check(_signal_count == 1, "Una señal por tomar")

	# Una sola mano: no hay lugar para otro
	_check(not hands.can_hold(yerba), "Con la mano ocupada no se puede tomar otro")
	_check(not hands.hold(yerba), "hold falla con la mano ocupada")
	_check(not hands.can_hold(chatarra), "Tampoco el mismo objeto de nuevo")
	_check(_signal_count == 1, "Un intento fallido no emite señal")

	# Soltar
	_check(hands.release() == chatarra, "release devuelve lo que había")
	_check(hands.is_empty(), "Después de soltar queda libre")
	_check(hands.release() == null, "Soltar con la mano vacía devuelve null")
	_check(_signal_count == 2, "Soltar vacío no emite señal")

	# Dos manos: ocupa el mismo único lugar
	_check(hands.hold(riel), "Toma un objeto de dos manos")
	_check(hands.is_two_handed_occupied(), "Detecta el objeto de dos manos")
	_check(is_equal_approx(hands.get_total_weight(), 40.0), "El peso se cuenta una sola vez")
	_check(hands.release() == riel, "Suelta el objeto de dos manos")
	_check(not hands.is_two_handed_occupied(), "Ya no hay objeto de dos manos")

	# Casos inválidos
	_check(not hands.can_hold(motor), "Grúa no se puede tomar a mano")
	_check(not hands.hold(null), "null no se puede tomar")
	hands.free()


func _test_world_item() -> void:
	var item := WorldItem.new()
	add_child(item)  # _ready configura grupo y capas al entrar al árbol
	var stack := _make_stack(&"bulones", ItemData.HandsRequired.ONE, 10.0, 3)
	item.setup(stack)
	_check(item.stack == stack, "WorldItem guarda su stack")
	_check(is_equal_approx(item.mass, 30.0), "Masa = peso del lote (10 kg x3)")
	_check(item.collision_layer == WorldItem.LAYER_ITEMS, "Está en la capa 3 (objetos sueltos)")
	_check(item.is_in_group(WorldItem.GROUP), "Pertenece al grupo world_items")
	item.queue_free()
