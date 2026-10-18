class_name StorageZone
extends RefCounted
## Una zona de un contenedor: guarda una pila de un solo tipo de objeto, o está vacía.
## Es un dato interno de StorageContainer; desde afuera se mira con StorageContainer.peek().

var size_class: ItemData.SizeClass
var capacity: int
## Null si la zona está vacía.
var stack: ItemStack


func _init(zone_size: ItemData.SizeClass, stack_capacity: int) -> void:
	size_class = zone_size
	capacity = stack_capacity


func is_empty() -> bool:
	return stack == null


## Cuántas unidades de `candidate` puede recibir todavía esta zona. Lógica pura.
## Una zona vacía recibe hasta su capacidad, salvo objetos con durabilidad, que van de a uno.
func room_for(candidate: ItemStack) -> int:
	if stack == null:
		return 1 if candidate.has_durability() else capacity
	if not stack.can_merge(candidate):
		return 0
	return maxi(capacity - stack.quantity, 0)
