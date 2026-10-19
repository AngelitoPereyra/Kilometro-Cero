class_name Grabber extends Node
## Componente del jugador: toma y suelta objetos del mundo con las manos, saca
## unidades de los contenedores (StorageArea) cercanos y maneja la mochila.
## Hijo directo de Player. Es el único que lee las acciones de manos y mochila.
## No cachea las referencias del jugador: las pide cuando las usa, porque
## Player termina de armarse DESPUÉS de sus hijos (_ready va de abajo hacia arriba).

## Se emite cuando no se pudo hacer algo. `reason` es &"nothing_near",
## &"hands_full", &"hands_empty", &"too_big" (solo grúa), &"too_heavy",
## &"container_empty" o &"no_room" (no entra en la mochila). La UI lo usará después.
signal grab_failed(reason: StringName)

## Distancia máxima al objeto para poder tomarlo.
@export_range(0.5, 5.0, 0.1, "suffix:m") var grab_range: float = 2.0
## Dónde se sostiene, en el marco del CUERPO del jugador (-Z = adelante, +X = derecha).
## Si ves los objetos muy altos o bajos, ajustá la Y: depende de dónde esté el
## origen de tu Player.
@export var hold_offset: Vector3 = Vector3(0.0, 1.0, -1.1)
## Separación lateral de cada mano cuando son objetos de una mano.
@export_range(0.0, 1.0, 0.05, "suffix:m") var hand_spread: float = 0.5
## Hasta dónde se busca el piso bajo el objeto para mostrar dónde caería.
@export_range(0.5, 10.0, 0.5, "suffix:m") var preview_ray_length: float = 4.0

var _player: Player
# En el orden en que se tomaron.
var _held: Array[WorldItem] = []


## Posición de un objeto sostenido, en el marco del cuerpo. Lógica pura.
## Dos manos: al centro. Una mano: la 0 es la derecha y la 1 la izquierda.
static func hold_offset_for(hands_used: int, hand_index: int, base: Vector3, spread: float) -> Vector3:
	if hands_used >= 2:
		return base
	var side: float = 1.0 if hand_index == 0 else -1.0
	return base + Vector3(side * spread, 0.0, 0.0)


## Por qué no se puede sacar UNA unidad de `sample`: &"" si se puede, o
## &"too_big" (solo grúa), &"hands_full" o &"too_heavy". Lógica pura.
static func take_blocker(sample: ItemStack, free_hands: int, room_kg: float) -> StringName:
	var needed: int = Hands.hands_needed(sample.item.hands)
	if needed == 0:
		return &"too_big"
	if free_hands < needed:
		return &"hands_full"
	if sample.item.unit_weight > room_kg:
		return &"too_heavy"
	return &""


## Índice de la primera zona de la que se puede sacar una unidad, o -1.
## `samples` tiene una entrada por zona (null si está vacía). Lógica pura.
static func first_takeable_zone(samples: Array[ItemStack], free_hands: int, room_kg: float) -> int:
	for i: int in samples.size():
		if samples[i] != null and take_blocker(samples[i], free_hands, room_kg) == &"":
			return i
	return -1


## Motivo del fallo cuando no hay ninguna zona de la que sacar: &"container_empty"
## si están todas vacías; si no, el bloqueo de la primera zona con algo. Lógica pura.
static func take_failure_reason(samples: Array[ItemStack], free_hands: int, room_kg: float) -> StringName:
	for sample: ItemStack in samples:
		if sample != null:
			return take_blocker(sample, free_hands, room_kg)
	return &"container_empty"


## Qué mano se guarda en la mochila: la derecha (0) primero y, si está vacía, la
## izquierda (1). Devuelve -1 si no hay nada en las manos. Lógica pura.
static func first_filled_hand(hand0_filled: bool, hand1_filled: bool) -> int:
	if hand0_filled:
		return 0
	if hand1_filled:
		return 1
	return -1


func _ready() -> void:
	_player = get_parent() as Player
	if _player == null:
		push_error("Grabber debe ser hijo directo de un Player.")
		set_physics_process(false)
		set_process_unhandled_input(false)
		return
	# Se procesa después del jugador (que tiene 10) para no ir un cuadro atrasado (D44).
	process_physics_priority = 20


func _unhandled_input(event: InputEvent) -> void:
	# Desmayado no se hace nada; caminando o sentado sí (sentado también se
	# puede tomar, soltar y usar la mochila).
	if _player.state == Player.State.FAINTED:
		return
	if event.is_action_pressed(&"grab"):
		try_grab()
	elif event.is_action_pressed(&"drop_right"):
		drop_hand(0)
	elif event.is_action_pressed(&"drop_left"):
		drop_hand(1)
	elif event.is_action_pressed(&"backpack_store"):
		store_in_backpack()
	elif event.is_action_pressed(&"backpack_take"):
		take_from_backpack()


func _physics_process(_delta: float) -> void:
	if _held.is_empty():
		return
	# Las manos se anclan al frente del CUERPO, no al de la cámara: giran cuando
	# gira el personaje y no cuando mirás alrededor (D61).
	var yaw: float = _player.get_facing_yaw()
	var body_basis := Basis(Vector3.UP, yaw)
	for item: WorldItem in _held:
		var offset: Vector3 = _offset_of(item)
		var hold_position: Vector3 = _player.global_position + body_basis * offset
		item.global_transform = Transform3D(body_basis, hold_position)
		_update_preview(Holdable.of(item), hold_position, yaw)


## Toma el objeto suelto más cercano al alcance; si no hay, saca una unidad del
## contenedor más cercano. Devuelve false (y avisa por `grab_failed`) si no pudo.
func try_grab() -> bool:
	var target: WorldItem = _find_nearest_item()
	if target != null:
		return _grab_world_item(target)
	var area: StorageArea = _find_nearest_storage_area()
	if area != null:
		return _take_from_container(
				area.get_container(), area.global_position, _player.get_encumbrance().get_pickup_room())
	grab_failed.emit(&"nothing_near")
	return false


## Suelta lo que hay en una mano (0 = derecha, 1 = izquierda). Un objeto de dos
## manos se suelta desde cualquiera de las dos. Si lo suelta sobre un StorageArea,
## el área se encarga de guardarlo: acá no hace falta saberlo.
func drop_hand(hand_index: int) -> bool:
	var stack: ItemStack = _player.get_hands().get_stack(hand_index)
	if stack == null:
		return false
	var item: WorldItem = _held_item_of(stack)
	if item == null:
		return false
	_held.erase(item)
	_release_to_world(item)
	return true


## Suelta el último objeto tomado (sin tecla propia; queda para uso interno,
## por ejemplo soltar todo al desmayarse). Devuelve false si no tenía nada.
func drop_last() -> bool:
	if _held.is_empty():
		return false
	var item: WorldItem = _held.pop_back()
	_release_to_world(item)
	return true


## Guarda en la mochila lo que hay en la mano (la derecha primero). Es todo o nada:
## si el lote entero no entra, queda en la mano y avisa &"no_room".
func store_in_backpack() -> bool:
	var hands: Hands = _player.get_hands()
	var hand_index: int = first_filled_hand(hands.get_stack(0) != null, hands.get_stack(1) != null)
	if hand_index == -1:
		grab_failed.emit(&"hands_empty")
		return false

	var stack: ItemStack = hands.get_stack(hand_index)
	var backpack: StorageContainer = _player.get_backpack()
	# La simulación y el guardado usan el mismo algoritmo (D48): si dice que entra, entra.
	if backpack.can_store_amount(stack) < stack.quantity:
		grab_failed.emit(&"no_room")
		return false
	var item: WorldItem = _held_item_of(stack)
	if item == null:
		push_error("Hay un objeto en la mano sin su WorldItem: no se puede guardar.")
		return false

	var leftover: ItemStack = backpack.try_store(stack)
	if leftover != null:
		push_error("La mochila guardó solo una parte de un stack que había confirmado: revisar StorageContainer.")
	hands.release(hand_index)
	_held.erase(item)
	EventBus.item_released.emit(stack)
	# El cuerpo físico ya no hace falta: el objeto vive ahora como pila en la mochila.
	item.queue_free()
	return true


## Saca una unidad de la mochila (de la primera zona que se pueda) y la pone en la mano.
func take_from_backpack() -> bool:
	# Pasa de la mochila a la mano: el peso total no cambia, por eso no hay tope (INF).
	return _take_from_container(_player.get_backpack(), _player.global_position, INF)


func _find_nearest_item() -> WorldItem:
	var candidates: Array[WorldItem] = []
	var positions: Array[Vector3] = []
	for node: Node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var candidate := node as WorldItem
		if candidate == null or candidate.stack == null:
			continue
		var holdable: Holdable = Holdable.of(candidate)
		if holdable == null or holdable.is_held:
			continue
		candidates.append(candidate)
		positions.append(candidate.global_position)
	var index: int = Player.nearest_index(_player.global_position, positions, grab_range)
	if index == -1:
		return null
	return candidates[index]


# Cada área tiene su propio alcance, por eso no se usa nearest_index.
func _find_nearest_storage_area() -> StorageArea:
	var best: StorageArea = null
	var best_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group(StorageArea.GROUP):
		var area := node as StorageArea
		if area == null or area.get_container() == null:
			continue
		var distance: float = _player.global_position.distance_to(area.global_position)
		if distance <= area.reach and distance < best_distance:
			best = area
			best_distance = distance
	return best


func _grab_world_item(target: WorldItem) -> bool:
	var hands: Hands = _player.get_hands()
	if Hands.hands_needed(target.stack.item.hands) == 0:
		grab_failed.emit(&"too_big")
		return false
	if not hands.can_hold(target.stack):
		grab_failed.emit(&"hands_full")
		return false
	if not _player.get_encumbrance().can_pick_up(target.stack.get_weight()):
		grab_failed.emit(&"too_heavy")
		return false

	# Primero la lógica (Hands) y después el cuerpo: si algo falla antes,
	# no queda un objeto congelado sin dueño.
	hands.hold(target.stack)
	Holdable.of(target).begin_hold()
	_register_held(target)
	return true


# Saca UNA unidad de la primera zona de la que se pueda. Se hace en este orden:
# 1) comprobar con copias (peek), 2) sacar, 3) crear el cuerpo, 4) tomarlo. Si algo
# falla después de sacar, se devuelve al contenedor y no se pierde nada.
# `spawn_position` es dónde aparece el objeto (de ahí pasa a la mano en el próximo
# cuadro) y `room_kg` el peso que todavía se puede sumar.
func _take_from_container(container: StorageContainer, spawn_position: Vector3, room_kg: float) -> bool:
	var hands: Hands = _player.get_hands()

	var samples: Array[ItemStack] = []
	for zone: int in container.get_zone_count():
		samples.append(container.peek(zone))

	var zone_index: int = first_takeable_zone(samples, hands.free_hands(), room_kg)
	if zone_index == -1:
		grab_failed.emit(take_failure_reason(samples, hands.free_hands(), room_kg))
		return false

	var taken: ItemStack = container.take(zone_index, 1)
	if taken == null:
		grab_failed.emit(&"container_empty")
		return false

	var item: WorldItem = WorldItem.create(taken)
	if item == null or Holdable.of(item) == null:
		# La escena del objeto no se puede tomar a mano: se devuelve y se avisa.
		push_error("'%s' no tiene un Holdable: no se puede sacar a mano." % taken.item.id)
		container.try_store(taken)
		if item != null:
			item.free()  # todavía no está en el árbol, se libera directo
		grab_failed.emit(&"too_big")
		return false
	if not hands.hold(taken):
		container.try_store(taken)
		item.free()
		grab_failed.emit(&"hands_full")
		return false

	get_tree().current_scene.add_child(item)
	item.global_position = spawn_position
	Holdable.of(item).begin_hold()
	_register_held(item)
	return true


func _register_held(item: WorldItem) -> void:
	_held.append(item)
	EventBus.item_held.emit(item.stack)


# El WorldItem que está en la mano con ese stack, o null.
func _held_item_of(stack: ItemStack) -> WorldItem:
	for item: WorldItem in _held:
		if item.stack == stack:
			return item
	return null


# Libera las manos y devuelve el cuerpo al mundo. Quien llama ya lo sacó de _held.
func _release_to_world(item: WorldItem) -> void:
	var hands: Hands = _player.get_hands()
	for i in Hands.HAND_COUNT:
		if hands.get_stack(i) == item.stack:
			hands.release(i)
			break
	# Hereda solo la velocidad horizontal: no queremos que salga volando hacia arriba.
	var velocity: Vector3 = Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	Holdable.of(item).end_hold(velocity)
	EventBus.item_released.emit(item.stack)


func _offset_of(item: WorldItem) -> Vector3:
	var hands: Hands = _player.get_hands()
	var used: int = Hands.hands_needed(item.stack.item.hands)
	var hand_index: int = 0
	for i in Hands.HAND_COUNT:
		if hands.get_stack(i) == item.stack:
			hand_index = i
			break
	return hold_offset_for(used, hand_index, hold_offset, hand_spread)


# Busca el piso bajo el objeto: ahí es donde caería al soltarlo.
func _update_preview(holdable: Holdable, from: Vector3, yaw: float) -> void:
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
			from, from + Vector3.DOWN * preview_ray_length, WorldItem.LAYER_WORLD)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		holdable.hide_preview()
		return
	var ground: Vector3 = hit["position"]
	holdable.show_preview(ground, yaw)
