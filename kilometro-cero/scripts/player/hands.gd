class_name Hands extends Node
## La mano del jugador (D68). En la lógica hay UN solo lugar donde se sostiene algo.
## Las "dos manos" son solo animación: `ItemData.hands` dice cuántas manos se ven
## agarrando el objeto, pero no ocupa más lugar ni cambia las reglas de arriba.
## Lógica pura: guarda un ItemStack, no un nodo. El cuerpo físico del objeto lo
## maneja Holdable, y el Grabber es quien decide cuándo tomar, guardar y soltar.

## Se emite solo cuando algo cambia de verdad (no en intentos fallidos).
signal hands_changed

# Se guarda la referencia real, sin copiar: la durabilidad de una herramienta en
# mano se gasta sobre este mismo objeto.
var _held: ItemStack


## Cuántas manos se ven agarrando un objeto: 1, 2, o 0 si no se puede tomar a mano
## (CRANE: solo con vagón grúa). Estático: no depende del estado de la mano.
static func hands_needed(hands_required: ItemData.HandsRequired) -> int:
	match hands_required:
		ItemData.HandsRequired.ONE:
			return 1
		ItemData.HandsRequired.TWO:
			return 2
		_:
			return 0


func is_empty() -> bool:
	return _held == null


## Lo que hay en la mano (la referencia real, no una copia), o null.
func get_held() -> ItemStack:
	return _held


## ¿Se puede sostener `stack`? Solo con la mano libre y si el objeto se puede tomar a mano.
func can_hold(stack: ItemStack) -> bool:
	if _held != null:
		return false
	if stack == null or stack.item == null:
		return false
	return hands_needed(stack.item.hands) > 0


func hold(stack: ItemStack) -> bool:
	if not can_hold(stack):
		return false
	_held = stack
	hands_changed.emit()
	return true


## Suelta lo que haya en la mano y lo devuelve (null si ya estaba vacía).
func release() -> ItemStack:
	if _held == null:
		return null
	var stack: ItemStack = _held
	_held = null
	hands_changed.emit()
	return stack


## Con un objeto de dos manos no se puede empujar la zorra (GDD 5.2).
func is_two_handed_occupied() -> bool:
	return _held != null and hands_needed(_held.item.hands) == 2


func get_total_weight() -> float:
	if _held == null:
		return 0.0
	return _held.get_weight()
