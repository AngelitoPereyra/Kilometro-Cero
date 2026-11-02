class_name Eater
extends Node
## Comer (tarea 62c.3h, D143). Con R (acción `eat`) come una unidad de comida (FoodData): primero lo
## que hay en la mano; con la mano vacía (o sin comida en ella), lo que más cura de la mochila. Suma
## su `heal` a la Salud. No come con la salud llena ni en la cabina.
## Hijo directo de Player, junto a Health ("Salud"), Hands, Grabber y la mochila.

signal eaten(item: FoodData, healed: float)
## &"no_food", &"full" o &"no_health".
signal eat_failed(reason: StringName)

var _player: Player


## Texto para la interfaz. Lógica pura.
static func failure_text(reason: StringName) -> String:
	match reason:
		&"no_food":
			return "No tenés nada para comer."
		&"full":
			return "No tenés hambre: la salud está llena."
	return ""


## La ranura de la comida que más cura entre `stacks` (null = ranura vacía), o -1. Lógica pura.
static func best_food_slot(stacks: Array[ItemStack]) -> int:
	var best: int = -1
	var best_heal: float = -1.0
	for i: int in stacks.size():
		var stack: ItemStack = stacks[i]
		if stack == null or stack.quantity <= 0:
			continue
		var food := stack.item as FoodData
		if food != null and food.heal > best_heal:
			best = i
			best_heal = food.heal
	return best


func _ready() -> void:
	_player = get_parent() as Player
	if _player == null:
		push_error("Eater debe ser hijo directo de un Player.")
		set_process_unhandled_input(false)


func _unhandled_input(event: InputEvent) -> void:
	if not InputMap.has_action(&"eat") or not event.is_action_pressed(&"eat"):
		return
	if not _player.controls_enabled or _player.is_in_cab():
		return
	try_eat()


## Come una unidad. Devuelve false (y avisa por `eat_failed`) si no pudo.
func try_eat() -> bool:
	var health: Health = _player.get_health()
	if health == null:
		eat_failed.emit(&"no_health")
		return false
	if health.is_full():
		eat_failed.emit(&"full")
		return false
	var food: FoodData = _take_from_hand()
	if food == null:
		food = _take_from_backpack()
	if food == null:
		eat_failed.emit(&"no_food")
		return false
	var gained: float = health.heal(food.heal)
	eaten.emit(food, gained)
	return true


# Una unidad de comida de la mano; lo que sobre de la pila vuelve a la mochila.
func _take_from_hand() -> FoodData:
	var hands: Hands = _player.get_hands()
	var held: ItemStack = hands.get_held() if hands != null else null
	if held == null or not FoodData.is_food(held.item):
		return null
	var grabber: Grabber = _find_grabber()
	var stack: ItemStack = grabber.consume_held() if grabber != null else hands.release()
	if stack == null:
		return null
	if stack.quantity > 1:
		var leftover: ItemStack = _player.get_backpack().try_store(stack.duplicate_stack(stack.quantity - 1))
		if leftover != null:
			push_warning("Eater: no entró en la mochila lo que sobraba de la mano (%d)." % leftover.quantity)
	return stack.item as FoodData


func _take_from_backpack() -> FoodData:
	var backpack: Inventory = _player.get_backpack()
	if backpack == null:
		return null
	var stacks: Array[ItemStack] = []
	for slot: int in backpack.get_slot_count():
		stacks.append(backpack.peek(slot))
	var slot: int = best_food_slot(stacks)
	if slot < 0:
		return null
	var taken: ItemStack = backpack.take(slot, 1)
	return taken.item as FoodData if taken != null else null


func _find_grabber() -> Grabber:
	for child: Node in _player.get_children():
		if child is Grabber:
			return child as Grabber
	return null
