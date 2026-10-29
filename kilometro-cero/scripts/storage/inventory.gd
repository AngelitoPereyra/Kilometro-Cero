class_name Inventory
extends Node
## Mochila de ranuras (D70, D86), como la de Minecraft: N ranuras y cada una apila un
## solo tipo de objeto. Acepta pequeños, medianos y, si la mochila lo dice
## (BackpackData.large_stack_limit, tarea 62.6), grandes. Sin peso ni reglas
## de compatibilidad (eso queda para vagones y cajas, en StorageContainer).
## Lógica pura: no dibuja nada; la interfaz (InventoryUI, tarea 49) observa sus señales.
## Misma regla de propiedad que StorageContainer: NUNCA modifica el ItemStack que
## recibe; devuelve stacks nuevos (el sobrante en try_store, lo extraído en take).

## Ocupación de la mochila: ranuras ocupadas sobre ranuras totales.
enum Alert { NONE, ALMOST_FULL, FULL }

## Se emiten con lo que realmente entró o salió (no con lo que se pidió).
signal item_stored(stack: ItemStack)
signal item_taken(stack: ItemStack)
## Cambió el contenido de alguna ranura (para la interfaz).
signal slots_changed
## Cambió el nivel de alerta (D59). La interfaz avisa solo cuando sube; al bajar se rearma.
signal alert_changed(alert: Alert)

## Si no está vacío, item_stored e item_taken también se emiten por el EventBus con este id.
@export var container_id: StringName
## Si se asigna desde el inspector, la mochila se arma sola al entrar al árbol.
@export var data: BackpackData

# Una entrada por ranura; null = vacía. Typed arrays de objetos aceptan null.
var _slots: Array[ItemStack] = []
var _alert: Alert = Alert.NONE


## Nivel de alerta para `used` ranuras ocupadas de `total`. Lógica pura.
static func alert_for(used: int, total: int, almost_full_ratio: float) -> Alert:
	if total <= 0:
		return Alert.NONE
	if used >= total:
		return Alert.FULL
	if float(used) / float(total) >= almost_full_ratio:
		return Alert.ALMOST_FULL
	return Alert.NONE


func _ready() -> void:
	if data != null and _slots.is_empty():
		setup(data)


## Arma las ranuras desde `new_data`. Si ya había contenido, se descarta.
func setup(new_data: BackpackData) -> void:
	if new_data == null:
		push_error("Inventory.setup necesita una BackpackData.")
		return
	data = new_data
	_slots.clear()
	_slots.resize(data.slot_count)
	_alert = Alert.NONE
	slots_changed.emit()


## ¿Este tipo de objeto puede ir en la mochila? (pequeño o mediano, D86)
func accepts(item: ItemData) -> bool:
	return data != null and item != null and data.stack_limit(item.size_class) > 0


## Guarda lo que entre. Devuelve el sobrante (un ItemStack nuevo) o null si entró todo.
func try_store(stack: ItemStack) -> ItemStack:
	if not _is_storable(stack):
		return null
	var stored: int = _store(stack, true)
	if stored > 0:
		_notify_stored(stack.duplicate_stack(stored))
	var leftover: int = stack.quantity - stored
	return stack.duplicate_stack(leftover) if leftover > 0 else null


## Cuántas unidades de `stack` entrarían ahora, sin guardar nada.
func can_store_amount(stack: ItemStack) -> int:
	return _store(stack, false) if _is_storable(stack) else 0


## Cuántas unidades de `stack` entrarían si antes se sacaran `amount` unidades de la
## ranura `slot`, sin modificar nada. Lo usa el Grabber para cambiar lo de la mano por
## una unidad de la ranura (tarea 49): si la ranura queda vacía, ese lugar cuenta.
func can_store_amount_after_take(stack: ItemStack, slot: int, amount: int) -> int:
	if not _is_storable(stack) or not _is_valid_slot(slot):
		return 0
	var current: ItemStack = _slots[slot]
	if current == null or amount <= 0:
		return can_store_amount(stack)
	# Se saca de verdad, se simula con el mismo algoritmo y se deja todo como estaba.
	# No se emite ninguna señal: para afuera, nada cambió.
	var removed: int = mini(amount, current.quantity)
	current.quantity -= removed
	var cleared: bool = current.quantity <= 0
	if cleared:
		_slots[slot] = null
	var room: int = _store(stack, false)
	current.quantity += removed
	if cleared:
		_slots[slot] = current
	return room


## Saca hasta `amount` unidades de una ranura. Devuelve lo extraído (nuevo) o null.
func take(slot: int, amount: int) -> ItemStack:
	if not _is_valid_slot(slot):
		push_error("Inventory.take: no existe la ranura %d" % slot)
		return null
	var current: ItemStack = _slots[slot]
	if current == null or amount <= 0:
		return null
	var taken: ItemStack = current.duplicate_stack(mini(amount, current.quantity))
	current.quantity -= taken.quantity
	if current.quantity <= 0:
		_slots[slot] = null
	_notify_taken(taken)
	return taken


## Copia de lo que hay en una ranura, o null si está vacía.
func peek(slot: int) -> ItemStack:
	if not _is_valid_slot(slot):
		push_error("Inventory.peek: no existe la ranura %d" % slot)
		return null
	var current: ItemStack = _slots[slot]
	return null if current == null else current.duplicate_stack()


func get_slot_count() -> int:
	return _slots.size()


func get_used_slot_count() -> int:
	var used: int = 0
	for current: ItemStack in _slots:
		if current != null:
			used += 1
	return used


## Ranuras ocupadas sobre totales, de 0.0 a 1.0.
func get_fill_ratio() -> float:
	return 0.0 if _slots.is_empty() else float(get_used_slot_count()) / float(_slots.size())


func get_alert() -> Alert:
	return _alert


## Tope de la pila de `item` en una ranura (0 si no entra).
func stack_limit_of(item: ItemData) -> int:
	return 0 if data == null or item == null else data.stack_limit(item.size_class)


func count_of(item_id: StringName) -> int:
	var total: int = 0
	for current: ItemStack in _slots:
		if current != null and current.item.id == item_id:
			total += current.quantity
	return total


# Un solo algoritmo para simular (commit = false) y para guardar (commit = true): así
# la simulación nunca puede contradecir al guardado real. Devuelve cuántas unidades entran.
func _store(stack: ItemStack, commit: bool) -> int:
	var limit: int = stack_limit_of(stack.item)
	if limit <= 0:
		return 0
	var remaining: int = stack.quantity

	# 1) Completar las pilas del mismo tipo que ya existen, antes de abrir una ranura nueva.
	for current: ItemStack in _slots:
		if remaining <= 0:
			break
		if current == null or not current.can_merge(stack):
			continue
		var room: int = mini(limit - current.quantity, remaining)
		if room <= 0:
			continue
		if commit:
			current.quantity += room
		remaining -= room

	# 2) Ranuras vacías, en orden. Un objeto con durabilidad nunca se apila: va de a uno.
	var per_slot: int = 1 if stack.has_durability() else limit
	for i: int in _slots.size():
		if remaining <= 0:
			break
		if _slots[i] != null:
			continue
		var amount: int = mini(per_slot, remaining)
		if commit:
			_slots[i] = stack.duplicate_stack(amount)
		remaining -= amount

	return stack.quantity - remaining


func _is_storable(stack: ItemStack) -> bool:
	return stack != null and stack.item != null and stack.quantity > 0


func _is_valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < _slots.size()


func _notify_stored(stored_stack: ItemStack) -> void:
	item_stored.emit(stored_stack)
	if container_id != &"":
		EventBus.item_stored.emit(container_id, stored_stack)
	_after_change()


func _notify_taken(taken_stack: ItemStack) -> void:
	item_taken.emit(taken_stack)
	if container_id != &"":
		EventBus.item_taken.emit(container_id, taken_stack)
	_after_change()


func _after_change() -> void:
	slots_changed.emit()
	var new_alert: Alert = alert_for(get_used_slot_count(), _slots.size(), data.almost_full_ratio)
	if new_alert != _alert:
		_alert = new_alert
		alert_changed.emit(_alert)
