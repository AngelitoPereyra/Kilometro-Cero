class_name FoodSeller
extends Interactable
## Mostrador de la taberna (tarea 62c.3h, D143): con F compra una unidad de `item` (el pan) por
## `price` pesos y va a la mochila.

## &"money" o &"no_room".
signal sale_failed(reason: StringName)
signal sold(item: ItemData)

@export var item: ItemData
@export var price: int = 5


func get_prompt() -> String:
	if item == null:
		return "Mostrador"
	return "Comprar %s ($%d)" % [item.display_name, price]


func _on_interact(player: Player) -> void:
	buy(player)


func buy(player: Player) -> bool:
	if item == null or player == null:
		return false
	if GameState.money < price:
		sale_failed.emit(&"money")
		return false
	var leftover: ItemStack = player.get_backpack().try_store(ItemStack.new(item, 1))
	if leftover != null:
		sale_failed.emit(&"no_room")
		return false
	GameState.add_money(-price)
	sold.emit(item)
	return true
