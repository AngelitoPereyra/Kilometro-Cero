class_name StorageArea extends Area3D
## Zona física de un StorageContainer (arquitectura, sección 9): si un objeto
## suelto entra en el volumen, se guarda en el contenedor y el cuerpo desaparece.
## Va como hermana del StorageContainer (mismo padre), con un CollisionShape3D
## hijo que marca el volumen. Sirve para la zorra, el carrito, los vagones
## y los depósitos de estación.

## Se emite cuando algo no entró (o entró solo una parte). `leftover` es lo
## que quedó afuera.
signal item_rejected(leftover: ItemStack)

const GROUP: StringName = &"storage_areas"
# Capa 6: zonas de almacenamiento (setup_project.gd).
const LAYER_ZONES: int = 1 << 5

## Distancia máxima, desde el centro del área, a la que el jugador puede
## sacar cosas del contenedor.
@export_range(0.5, 6.0, 0.1, "suffix:m") var reach: float = 2.5

var _container: StorageContainer
# Stacks que ya se intentaron guardar sin éxito (clave: id de instancia del
# ItemStack). Se olvidan cuando el jugador levanta el objeto de nuevo, así un
# objeto rechazado no se reintenta solo en cada soltada.
var _rejected: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = LAYER_ZONES
	# Solo detecta objetos sueltos (capa 3).
	collision_mask = WorldItem.LAYER_ITEMS
	_container = _find_container()
	if _container == null:
		push_error("StorageArea necesita un StorageContainer hermano (hijo del mismo padre).")
		return
	body_entered.connect(_on_body_entered)
	EventBus.item_released.connect(_on_item_released)
	EventBus.item_held.connect(_on_item_held)


func get_container() -> StorageContainer:
	return _container


# D42: se busca entre los hermanos, no se asigna con @export.
func _find_container() -> StorageContainer:
	var parent: Node = get_parent()
	if parent == null:
		return null
	for child: Node in parent.get_children():
		var container := child as StorageContainer
		if container != null:
			return container
	return null


func _on_body_entered(body: Node3D) -> void:
	var item := body as WorldItem
	if item == null:
		return
	# Diferido: el motor avisa esto en medio del paso de física y ahí no
	# conviene tocar masas ni liberar cuerpos.
	_try_absorb.call_deferred(item)


# Soltar un objeto que ya estaba dentro del volumen puede no disparar
# body_entered (su cuerpo no se movió, solo cambió de capa). Por eso, después
# de cada soltada se revisa lo que hay adentro.
func _on_item_released(_stack: ItemStack) -> void:
	# Al soltar, el cuerpo recién recupera su capa: dos cuadros de física
	# alcanzan para que el área lo vea.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	for body: Node3D in get_overlapping_bodies():
		var item := body as WorldItem
		if item != null:
			_try_absorb(item)


# Si el jugador levanta un objeto rechazado, se le da otra oportunidad cuando lo suelte.
func _on_item_held(stack: ItemStack) -> void:
	_rejected.erase(stack.get_instance_id())


# Es seguro llamarla dos veces para el mismo objeto (por body_entered y por la
# revisión posterior): el segundo intento lo encuentra ya liberado o rechazado.
func _try_absorb(item: WorldItem) -> void:
	if not is_instance_valid(item) or item.is_queued_for_deletion() or not item.is_inside_tree():
		return
	if item.stack == null:
		return
	# En la mano no se guarda: lo sostiene el jugador.
	var holdable: Holdable = Holdable.of(item)
	if holdable != null and holdable.is_held:
		return
	if _rejected.has(item.stack.get_instance_id()):
		return

	var leftover: ItemStack = _container.try_store(item.stack)
	if leftover == null:
		item.queue_free()
		return
	# Algo no entró. Si entró una parte, el objeto pasa a representar solo el sobrante.
	if leftover.quantity < item.stack.quantity:
		item.setup(leftover)
	_rejected[item.stack.get_instance_id()] = true
	item_rejected.emit(leftover)
