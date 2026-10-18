class_name StorageContainer
extends Node
## Almacenamiento abstracto por zonas (D22, D23) para mochila, zorra, carrito, vagones y
## depósitos de estación. Es lógica pura: no dibuja nada ni depende de nodos de interfaz;
## la UI y las zonas físicas (Area3D) solo observan sus señales y llaman a sus funciones.
## Regla de propiedad: el container NUNCA modifica el ItemStack que recibe. Devuelve stacks
## nuevos (el sobrante en try_store, lo extraído en take), así nadie comparte un objeto mutable.

## Se emiten con lo que realmente entró o salió (no con lo que se pidió).
signal item_stored(stack: ItemStack)
signal item_taken(stack: ItemStack)

## Si no está vacío, además se emite por el EventBus con este id (02-arquitectura, sección 5).
@export var container_id: StringName
## Si se asignan los dos desde el inspector, el contenedor se arma solo al entrar al árbol.
@export var layout: StorageLayout
@export var config: StorageConfig

var _zones: Array[StorageZone] = []


func _ready() -> void:
	if layout != null and config != null and _zones.is_empty():
		setup(layout, config)


## Arma las zonas desde el layout. Si ya había contenido, se descarta.
func setup(new_layout: StorageLayout, new_config: StorageConfig) -> void:
	if new_layout == null or new_config == null:
		push_error("StorageContainer.setup necesita un StorageLayout y un StorageConfig.")
		return
	layout = new_layout
	config = new_config
	_zones.clear()
	for spec: ZoneSpec in layout.zones:
		if spec == null:
			continue
		for _i: int in spec.count:
			_zones.append(StorageZone.new(spec.size_class, config.stack_capacity(spec.size_class)))


## Guarda lo que entre. Devuelve el sobrante (un ItemStack nuevo) o null si entró todo.
## El stack recibido no se modifica.
func try_store(stack: ItemStack) -> ItemStack:
	if not _is_storable(stack):
		return null
	var stored: int = _store(stack, true)
	if stored > 0:
		_notify_stored(stack.duplicate_stack(stored))
	var leftover: int = stack.quantity - stored
	return stack.duplicate_stack(leftover) if leftover > 0 else null


## Cuántas unidades de `stack` entrarían ahora, sin guardar nada. Sirve para que la UI y el
## fantasma de colocación sepan de antemano si algo cabe.
func can_store_amount(stack: ItemStack) -> int:
	return _store(stack, false) if _is_storable(stack) else 0


## Saca hasta `amount` unidades de una zona. Devuelve lo extraído (un ItemStack nuevo) o null
## si la zona está vacía o la cantidad no es positiva.
func take(zone_index: int, amount: int) -> ItemStack:
	if not _is_valid_index(zone_index):
		push_error("StorageContainer.take: no existe la zona %d" % zone_index)
		return null
	var zone: StorageZone = _zones[zone_index]
	if zone.is_empty() or amount <= 0:
		return null
	var taken: ItemStack = zone.stack.duplicate_stack(mini(amount, zone.stack.quantity))
	zone.stack.quantity -= taken.quantity
	if zone.stack.quantity <= 0:
		zone.stack = null
	_notify_taken(taken)
	return taken


## Copia de lo que hay en una zona, o null si está vacía. No permite modificar el contenido.
func peek(zone_index: int) -> ItemStack:
	if not _is_valid_index(zone_index):
		push_error("StorageContainer.peek: no existe la zona %d" % zone_index)
		return null
	var zone: StorageZone = _zones[zone_index]
	return null if zone.is_empty() else zone.stack.duplicate_stack()


func get_zone_count() -> int:
	return _zones.size()


func get_zone_size(zone_index: int) -> ItemData.SizeClass:
	if not _is_valid_index(zone_index):
		push_error("StorageContainer.get_zone_size: no existe la zona %d" % zone_index)
		return ItemData.SizeClass.SMALL
	return _zones[zone_index].size_class


func count_of(item_id: StringName) -> int:
	var total: int = 0
	for zone: StorageZone in _zones:
		if not zone.is_empty() and zone.stack.item.id == item_id:
			total += zone.stack.quantity
	return total


func get_total_weight() -> float:
	var total: float = 0.0
	for zone: StorageZone in _zones:
		if not zone.is_empty():
			total += zone.stack.get_weight()
	return total


# Un solo algoritmo para simular (commit = false) y para guardar (commit = true): así
# la simulación nunca puede contradecir al guardado real. Devuelve cuántas unidades entran.
func _store(stack: ItemStack, commit: bool) -> int:
	if config == null or _conflicts_with_contents(stack.item):
		return 0
	var remaining: int = stack.quantity

	# 1) Completar las pilas que ya existen, antes de abrir una zona nueva.
	for zone: StorageZone in _zones:
		if remaining <= 0:
			break
		if zone.is_empty():
			continue
		var room: int = mini(zone.room_for(stack), remaining)
		if room <= 0:
			continue
		if commit:
			zone.stack.quantity += room
		remaining -= room

	# 2) Usar zonas vacías de la más chica a la más grande, para no gastar una grande en
	# algo que entra en una chica (el orden del enum va de menor a mayor).
	for zone_size: int in ItemData.SizeClass.values():
		for zone: StorageZone in _zones:
			if remaining <= 0:
				break
			if zone.size_class != zone_size or not zone.is_empty():
				continue
			if not config.zone_accepts(zone.size_class, stack.item.size_class):
				continue
			var amount: int = mini(zone.room_for(stack), remaining)
			if amount <= 0:
				continue
			if commit:
				zone.stack = stack.duplicate_stack(amount)
			remaining -= amount

	return stack.quantity - remaining


# Un objeto no entra si alguna de sus etiquetas choca con las de otro objeto ya guardado
# (por ejemplo, un químico junto a comida).
func _conflicts_with_contents(item: ItemData) -> bool:
	for zone: StorageZone in _zones:
		if zone.is_empty() or zone.stack.item.id == item.id:
			continue
		if config.tags_conflict(item.tags, zone.stack.item.tags):
			return true
	return false


func _is_storable(stack: ItemStack) -> bool:
	return stack != null and stack.item != null and stack.quantity > 0


func _is_valid_index(zone_index: int) -> bool:
	return zone_index >= 0 and zone_index < _zones.size()


func _notify_stored(stored_stack: ItemStack) -> void:
	item_stored.emit(stored_stack)
	if container_id != &"":
		EventBus.item_stored.emit(container_id, stored_stack)


func _notify_taken(taken_stack: ItemStack) -> void:
	item_taken.emit(taken_stack)
	if container_id != &"":
		EventBus.item_taken.emit(container_id, taken_stack)
