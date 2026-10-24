class_name StorageContainer
extends Node
## Almacenamiento de vagones y cajas (D85, tarea 53): una lista de pilas, una por tipo de
## objeto, con un tope de unidades en total. Sin zonas por tamaño ni reglas de
## compatibilidad: qué carga entra lo dice `accepted_tags` (el vagón lo copia de su WagonData).
## Es lógica pura: no dibuja nada; la UI y el StorageArea solo observan sus señales y llaman
## a sus funciones.
## Regla de propiedad: el container NUNCA modifica el ItemStack que recibe. Devuelve stacks
## nuevos (el sobrante en try_store, lo extraído en take), así nadie comparte un objeto mutable.

## Se emiten con lo que realmente entró o salió (no con lo que se pidió).
signal item_stored(stack: ItemStack)
signal item_taken(stack: ItemStack)

## Si no está vacío, además se emite por el EventBus con este id (02-arquitectura, sección 5).
@export var container_id: StringName
## Unidades que entran en total, sumando todas las pilas.
@export_range(1, 9999) var capacity: int = 50
## Si no está vacío, solo entra lo que tenga al menos una de estas etiquetas (ItemData.tags).
@export var accepted_tags: Array[StringName] = []

# Una pila por tipo de objeto, en el orden en que llegaron. Lo que tiene durabilidad no se
# fusiona: cada unidad ocupa su propia pila.
var _stacks: Array[ItemStack] = []


## Cambia la capacidad y la carga aceptada. No toca lo que ya hay guardado.
func configure(new_capacity: int, new_accepted_tags: Array[StringName]) -> void:
	capacity = maxi(new_capacity, 0)
	accepted_tags = new_accepted_tags.duplicate()


## ¿Este tipo de objeto es carga de este contenedor?
func accepts(item: ItemData) -> bool:
	if item == null:
		return false
	if accepted_tags.is_empty():
		return true
	for tag: StringName in item.tags:
		if accepted_tags.has(tag):
			return true
	return false


## Guarda lo que entre. Devuelve el sobrante (un ItemStack nuevo) o null si entró todo.
## El stack recibido no se modifica.
func try_store(stack: ItemStack) -> ItemStack:
	if not _is_storable(stack):
		return null
	var stored: int = can_store_amount(stack)
	if stored > 0:
		_store(stack, stored)
		_notify_stored(stack.duplicate_stack(stored))
	var leftover: int = stack.quantity - stored
	return stack.duplicate_stack(leftover) if leftover > 0 else null


## Cuántas unidades de `stack` entrarían ahora, sin guardar nada.
func can_store_amount(stack: ItemStack) -> int:
	if not _is_storable(stack) or not accepts(stack.item):
		return 0
	return mini(stack.quantity, get_free_space())


## Saca hasta `amount` unidades de una pila. Devuelve lo extraído (un ItemStack nuevo) o null
## si la cantidad no es positiva. Si la pila se vacía, desaparece y las de atrás se corren.
func take(stack_index: int, amount: int) -> ItemStack:
	if not _is_valid_index(stack_index):
		push_error("StorageContainer.take: no existe la pila %d" % stack_index)
		return null
	if amount <= 0:
		return null
	var stack: ItemStack = _stacks[stack_index]
	var taken: ItemStack = stack.duplicate_stack(mini(amount, stack.quantity))
	stack.quantity -= taken.quantity
	if stack.quantity <= 0:
		_stacks.remove_at(stack_index)
	_notify_taken(taken)
	return taken


## Copia de una pila. No permite modificar el contenido.
func peek(stack_index: int) -> ItemStack:
	if not _is_valid_index(stack_index):
		push_error("StorageContainer.peek: no existe la pila %d" % stack_index)
		return null
	return _stacks[stack_index].duplicate_stack()


## Cuántas pilas hay (una por tipo de objeto). Las pilas vacías no existen.
func get_stack_count() -> int:
	return _stacks.size()


func count_of(item_id: StringName) -> int:
	var total: int = 0
	for stack: ItemStack in _stacks:
		if stack.item.id == item_id:
			total += stack.quantity
	return total


## Unidades guardadas en total.
func get_total() -> int:
	var total: int = 0
	for stack: ItemStack in _stacks:
		total += stack.quantity
	return total


func get_free_space() -> int:
	return maxi(capacity - get_total(), 0)


func is_empty() -> bool:
	return _stacks.is_empty()


# Quien llama ya comprobó que entran `amount` unidades.
func _store(stack: ItemStack, amount: int) -> void:
	if stack.has_durability():
		# Cada unidad con desgaste propio va en su pila.
		for _i: int in amount:
			_stacks.append(stack.duplicate_stack(1))
		return
	for existing: ItemStack in _stacks:
		if existing.can_merge(stack):
			existing.quantity += amount
			return
	_stacks.append(stack.duplicate_stack(amount))


func _is_storable(stack: ItemStack) -> bool:
	return stack != null and stack.item != null and stack.quantity > 0


func _is_valid_index(stack_index: int) -> bool:
	return stack_index >= 0 and stack_index < _stacks.size()


func _notify_stored(stored_stack: ItemStack) -> void:
	item_stored.emit(stored_stack)
	if container_id != &"":
		EventBus.item_stored.emit(container_id, stored_stack)


func _notify_taken(taken_stack: ItemStack) -> void:
	item_taken.emit(taken_stack)
	if container_id != &"":
		EventBus.item_taken.emit(container_id, taken_stack)
