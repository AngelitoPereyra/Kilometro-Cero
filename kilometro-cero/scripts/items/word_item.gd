class_name WorldItem extends RigidBody3D
## Objeto físico del mundo (D22). Referencia un ItemStack: puede ser una
## unidad suelta o un lote (una caja de bulones x50).
## Solo guarda datos y configura su propia física. Qué pasa al tomarlo o
## soltarlo lo decide el componente Holdable (D52).

const GROUP: StringName = &"world_items"

# Capas de colisión (setup_project.gd): 1 mundo, 2 jugador, 3 objetos sueltos.
# Son máscaras de bits: la capa N vale 1 << (N - 1).
const LAYER_WORLD: int = 1 << 0
const LAYER_ITEMS: int = 1 << 2

# Piso de masa para que un objeto liviano no se comporte de forma rara.
const MIN_MASS: float = 0.05

var stack: ItemStack


func _ready() -> void:
	add_to_group(GROUP)
	set_held(false)


## Asigna lo que representa este objeto. Se puede llamar antes o después
## de agregarlo al árbol.
func setup(new_stack: ItemStack) -> void:
	stack = new_stack
	# La masa real sale del peso: una caja de 50 bulones pesa más que uno.
	mass = maxf(stack.get_weight(), MIN_MASS)


## En la mano el cuerpo se congela y no colisiona con nada: lo mueve quien
## lo sostiene, y así no empuja al jugador ni a otros objetos.
## Al soltarlo vuelve a ser un cuerpo físico normal.
func set_held(held: bool) -> void:
	# KINEMATIC: congelado pero movible por script (no queda clavado en el aire).
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = held
	if held:
		collision_layer = 0
		collision_mask = 0
	else:
		collision_layer = LAYER_ITEMS
		# Choca con el mundo y con otros objetos; no con el jugador.
		collision_mask = LAYER_WORLD | LAYER_ITEMS
