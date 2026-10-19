class_name Hands 
extends Node
## Las dos manos del jugador (GDD 5.2, arquitectura sección 9).
## Lógica pura: guarda ItemStack, no nodos. El cuerpo físico del objeto
## lo maneja Holdable. Así esta clase se puede probar sin escenas.

## Se emite solo cuando algo cambia de verdad (no en intentos fallidos).
signal hands_changed

const HAND_COUNT: int = 2

# Una referencia por mano. Un objeto de dos manos aparece en AMBAS
# ranuras con la misma referencia (como dos variables apuntando al
# mismo objeto en Java). Se guarda el stack original, sin copiar, porque
# la durabilidad de una herramienta en mano se gasta sobre ese objeto.
var _slots: Array[ItemStack] = []


func _init() -> void:
	# resize() rellena con null; evita el problema de asignar un literal
	# sin tipo a un Array tipado.
	_slots.resize(HAND_COUNT)


## Cuántas manos ocupa un objeto. 0 significa "no se puede tomar a mano"
## (CRANE: solo con vagón grúa). Estático: no depende del estado de las manos.
static func hands_needed(hands_required: ItemData.HandsRequired) -> int:
	match hands_required:
		ItemData.HandsRequired.ONE:
			return 1
		ItemData.HandsRequired.TWO:
			return 2
		_:
			return 0


func can_hold(stack: ItemStack) -> bool:
	if stack == null or stack.item == null:
		return false
	# El mismo stack en dos manos duplicaría su peso y rompería release().
	if _slots.has(stack):
		return false
	var needed: int = hands_needed(stack.item.hands)
	if needed == 0:
		return false
	return free_hands() >= needed


func hold(stack: ItemStack) -> bool:
	if not can_hold(stack):
		return false
	if hands_needed(stack.item.hands) == 2:
		_slots[0] = stack
		_slots[1] = stack
	else:
		# can_hold garantiza que hay al menos una mano libre.
		_slots[_slots.find(null)] = stack
	hands_changed.emit()
	return true


## Suelta lo que haya en esa mano y lo devuelve (null si estaba vacía o el
## índice no existe). Si era de dos manos, se liberan las dos.
func release(hand_index: int) -> ItemStack:
	if hand_index < 0 or hand_index >= HAND_COUNT:
		return null
	var stack: ItemStack = _slots[hand_index]
	if stack == null:
		return null
	for i in HAND_COUNT:
		if _slots[i] == stack:
			_slots[i] = null
	hands_changed.emit()
	return stack


func free_hands() -> int:
	var free: int = 0
	for slot in _slots:
		if slot == null:
			free += 1
	return free


## Con un objeto de dos manos no se puede empujar la zorra (GDD 5.2).
func is_two_handed_occupied() -> bool:
	for slot in _slots:
		if slot != null and hands_needed(slot.item.hands) == 2:
			return true
	return false


## Lo que hay en esa mano (la referencia real, no una copia), o null.
func get_stack(hand_index: int) -> ItemStack:
	if hand_index < 0 or hand_index >= HAND_COUNT:
		return null
	return _slots[hand_index]


## Peso total en manos. Un objeto de dos manos cuenta una sola vez.
func get_total_weight() -> float:
	var total: float = 0.0
	for i in HAND_COUNT:
		var slot: ItemStack = _slots[i]
		if slot == null:
			continue
		# Si la mano 1 repite la referencia de la mano 0, ya se sumó.
		if i == 1 and slot == _slots[0]:
			continue
		total += slot.get_weight()
	return total
