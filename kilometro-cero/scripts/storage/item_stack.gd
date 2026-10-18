class_name ItemStack
extends RefCounted
## Estado de un objeto en runtime: qué objeto es, cuántos hay y cuánta durabilidad tiene.
## ItemData nunca se modifica (D33): si guardáramos la cantidad ahí, todas las pilas
## del mismo objeto compartirían el mismo número.

var item: ItemData
var quantity: int = 0
## -1.0 si el objeto no tiene durabilidad; si no, el valor actual.
var durability: float = -1.0


func _init(item_data: ItemData = null, amount: int = 1, start_durability: float = -1.0) -> void:
	item = item_data
	quantity = amount
	durability = start_durability


func get_weight() -> float:
	return 0.0 if item == null else item.unit_weight * quantity


func has_durability() -> bool:
	return durability >= 0.0


## Dos pilas se fusionan si son del mismo objeto. Los que tienen durabilidad nunca:
## cada herramienta tiene su propio desgaste. Se compara por `id` y no por la
## referencia al recurso, así dos copias cargadas por separado cuentan como el mismo.
func can_merge(other: ItemStack) -> bool:
	if item == null or other == null or other.item == null:
		return false
	return item.id == other.item.id and not has_durability() and not other.has_durability()


## Copia independiente. Con `new_quantity` negativo conserva la cantidad.
func duplicate_stack(new_quantity: int = -1) -> ItemStack:
	return ItemStack.new(item, quantity if new_quantity < 0 else new_quantity, durability)
