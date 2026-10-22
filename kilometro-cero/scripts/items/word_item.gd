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

# Escena genérica para stacks cuyo ItemData no trae una propia. Se carga con
# load() y no con preload(): esta escena referencia este script, y un preload
# en el sentido contrario formaría un ciclo.
const DEFAULT_SCENE_PATH: String = "res://scenes/items/world_item.tscn"

var stack: ItemStack

# Teletransporte pendiente: se aplica en _integrate_forces (ver teleport_to).
var _pending_teleport: Transform3D = Transform3D.IDENTITY
var _has_pending_teleport: bool = false


## Crea el objeto físico de un stack (todavía fuera del árbol: quien lo llama
## decide dónde agregarlo). Usa la escena del ItemData o la genérica.
## Devuelve null si la escena no tiene un WorldItem como raíz.
static func create(new_stack: ItemStack) -> WorldItem:
	var scene: PackedScene = new_stack.item.scene
	if scene == null:
		scene = load(DEFAULT_SCENE_PATH) as PackedScene
	var item := scene.instantiate() as WorldItem
	if item == null:
		push_error("La escena de '%s' no tiene un WorldItem como raíz." % new_stack.item.id)
		return null
	item.setup(new_stack)
	return item


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


## Teletransporta el cuerpo a `target` (sin velocidad). Se aplica en el próximo paso
## de física, dentro de _integrate_forces: es el camino que Godot documenta para
## mover un RigidBody3D de forma segura. Cambiarle el transform a mano justo después
## de liberarlo puede perderse según cómo trate el motor ese cambio de modo.
func teleport_to(target: Transform3D) -> void:
	_pending_teleport = target
	_has_pending_teleport = true
	# Un cuerpo dormido no ejecutaría _integrate_forces.
	sleeping = false


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not _has_pending_teleport:
		return
	_has_pending_teleport = false
	state.transform = _pending_teleport
	state.linear_velocity = Vector3.ZERO
	state.angular_velocity = Vector3.ZERO
