class_name WorldItem extends RigidBody3D
## Objeto físico del mundo (D22). Referencia un ItemStack: puede ser una
## unidad suelta o un lote (una caja de bulones x50).
## Esta clase solo guarda datos y configura la física. Tomarlo y soltarlo
## es responsabilidad del componente Holdable (parte 2).

const GROUP: StringName = &"world_items"

# Capas de colisión (setup_project.gd): 1 mundo, 2 jugador, 3 objetos sueltos.
# Los valores son máscaras de bits: la capa N vale 1 << (N - 1).
const LAYER_WORLD: int = 1 << 0
const LAYER_ITEMS: int = 1 << 2

# Piso de masa para que un objeto liviano no se comporte de forma rara.
const MIN_MASS: float = 0.05

var stack: ItemStack


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = LAYER_ITEMS
	# Choca con el mundo y con otros objetos; no con el jugador, así
	# no lo empuja ni lo hace trabarse.
	collision_mask = LAYER_WORLD | LAYER_ITEMS


## Asigna lo que representa este objeto. Se puede llamar antes o después
## de agregarlo al árbol.
func setup(new_stack: ItemStack) -> void:
	stack = new_stack
	# La masa real sale del peso: una caja de 50 bulones pesa más que uno.
	mass = maxf(stack.get_weight(), MIN_MASS)
