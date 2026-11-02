class_name Oven
extends Interactable
## Horno del vagón cocina (tarea 62c.3h, D143). Con F mete a asar toda la comida cruda que se puede
## cocinar (FoodData.cooked) de la mano y la mochila; a las `cook_hours` de juego está lista y con F
## se saca a la mochila (lo que no entra cae al lado). Mientras asa no acepta más.

signal cooking_started(amount: int)
signal cooking_done(amount: int)
signal collected(amount: int)

@export_range(0.05, 12.0, 0.05, "suffix:h") var cook_hours: float = 0.5

# Lo que está adentro: ya convertido en lo cocido (se ve al terminar).
var _inside: Array[ItemStack] = []
var _hours_left: float = 0.0


## "Asar 3 carnes de jabalí", "Asándose: faltan 20 min", "Sacar 3 carnes asadas". Lógica pura.
static func prompt_for(raw_count: int, inside_count: int, hours_left: float) -> String:
	if inside_count > 0 and hours_left > 0.0:
		return "Horno: asándose, faltan %d min" % ceili(hours_left * 60.0)
	if inside_count > 0:
		return "Horno: sacar %d %s" % [inside_count, "asado" if inside_count == 1 else "asados"]
	if raw_count > 0:
		return "Horno: asar %d %s" % [raw_count, "carne" if raw_count == 1 else "carnes"]
	return "Horno: nada para asar"


func _ready() -> void:
	EventBus.time_advanced.connect(_on_time_advanced)


func is_cooking() -> bool:
	return not _inside.is_empty() and _hours_left > 0.0


func is_ready() -> bool:
	return not _inside.is_empty() and _hours_left <= 0.0


func get_inside_count() -> int:
	var total: int = 0
	for stack: ItemStack in _inside:
		total += stack.quantity
	return total


func get_hours_left() -> float:
	return _hours_left if not _inside.is_empty() else 0.0


func get_prompt() -> String:
	var player := get_tree().get_first_node_in_group(Player.GROUP) as Player
	return prompt_for(count_raw(player), get_inside_count(), get_hours_left())


## Cuánta comida para asar tiene el jugador (mano y mochila).
func count_raw(player: Player) -> int:
	if player == null:
		return 0
	var total: int = 0
	var held: ItemStack = player.get_hands().get_held() if player.get_hands() != null else null
	if held != null and FoodData.is_cookable(held.item):
		total += held.quantity
	var backpack: Inventory = player.get_backpack()
	if backpack != null:
		for slot: int in backpack.get_slot_count():
			var stack: ItemStack = backpack.peek(slot)
			if stack != null and FoodData.is_cookable(stack.item):
				total += stack.quantity
	return total


func _on_interact(player: Player) -> void:
	if is_ready():
		collect(player)
	elif not is_cooking():
		load_from(player)


## Mete a asar lo crudo del jugador. Devuelve cuántas unidades entraron.
func load_from(player: Player) -> int:
	if player == null or is_cooking() or is_ready():
		return 0
	var amount: int = 0
	var held: ItemStack = player.get_hands().get_held()
	if held != null and FoodData.is_cookable(held.item):
		var grabber: Grabber = _grabber_of(player)
		var stack: ItemStack = grabber.consume_held() if grabber != null else player.get_hands().release()
		if stack != null:
			amount += _put(stack)
	var backpack: Inventory = player.get_backpack()
	for slot: int in backpack.get_slot_count():
		var stack: ItemStack = backpack.peek(slot)
		if stack == null or not FoodData.is_cookable(stack.item):
			continue
		var taken: ItemStack = backpack.take(slot, stack.quantity)
		if taken != null:
			amount += _put(taken)
	if amount > 0:
		_hours_left = cook_hours
		cooking_started.emit(amount)
	return amount


## Saca lo asado a la mochila; lo que no entra cae al lado del horno. Devuelve cuánto salió.
func collect(player: Player) -> int:
	if not is_ready():
		return 0
	var amount: int = 0
	for stack: ItemStack in _inside:
		amount += stack.quantity
		var leftover: ItemStack = player.get_backpack().try_store(stack) if player != null else stack
		if leftover != null:
			_drop(leftover)
	_inside.clear()
	_hours_left = 0.0
	collected.emit(amount)
	return amount


func _put(stack: ItemStack) -> int:
	var food := stack.item as FoodData
	_inside.append(ItemStack.new(food.cooked, stack.quantity))
	return stack.quantity


func _drop(stack: ItemStack) -> void:
	for i: int in stack.quantity:
		var item: WorldItem = WorldItem.create(ItemStack.new(stack.item, 1))
		if item == null:
			return
		get_tree().current_scene.add_child(item)
		item.global_position = global_position + Vector3(0.4 * float(i % 3), 0.5, 0.6)


func _on_time_advanced(hours: float) -> void:
	if not is_cooking():
		return
	_hours_left = maxf(_hours_left - hours, 0.0)
	if _hours_left <= 0.0:
		cooking_done.emit(get_inside_count())


static func _grabber_of(player: Player) -> Grabber:
	for child: Node in player.get_children():
		if child is Grabber:
			return child as Grabber
	return null
