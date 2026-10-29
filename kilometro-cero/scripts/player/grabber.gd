class_name Grabber extends Node
## Componente del jugador: recoge objetos del mundo según su tamaño, los suelta,
## los coloca con precisión (fantasma) y saca unidades de los contenedores cercanos.
## Hijo directo de Player. Es el único que lee las acciones de manos.
## No cachea las referencias del jugador: las pide cuando las usa, porque
## Player termina de armarse DESPUÉS de sus hijos (_ready va de abajo hacia arriba).
##
## Regla de recogida (D69): los pequeños van solos a la mochila; los medianos y
## grandes quedan en la mano; si la mano está ocupada, lo que hay se guarda solo en
## la mochila; si no entra, no se toma nada y avisa.
## La mochila es un Inventory de ranuras (tarea 48, D86): acepta pequeños y medianos;
## un grande en la mano nunca entra, así que no se puede cambiar por otro (no_room).
## Desde la interfaz del inventario (tarea 49) se pasa una unidad de una ranura a la
## mano (take_from_backpack) y lo de la mano a la mochila (stow_held).
## Con `prefer_backpack` (tarea 62.7, el Hito A) los medianos y grandes también van solos a la
## mochila mientras entren; recién cuando no entran quedan en la mano. Con la mano vacía, soltar
## (Q) junto a un contenedor (el vagón) le pasa todo lo de la mochila que acepte (unload_backpack).
## Con los controles del jugador apagados (inventario abierto) no lee las teclas.
## Una herramienta clave suelta (KeyItemData, tarea 55) no va a la mano ni a la mochila: pasa
## a los KeyItems del jugador y el objeto desaparece. Si ya la tenía, también desaparece.

## Se emite cuando no se pudo hacer algo. `reason` es &"nothing_near",
## &"too_big" (solo grúa), &"no_room" (no entra en la mochila),
## &"container_empty" (también: ranura vacía), &"hands_empty", &"place_invalid" (el
## lugar apuntado no es válido) o &"not_placeable" (el objeto no tiene Placeable).
## InventoryUI.failure_text lo traduce para mostrarlo.
signal grab_failed(reason: StringName)
## Se pasaron `amount` unidades de la mochila a un contenedor (unload_backpack, tarea 62.7).
signal backpack_unloaded(amount: int)

## Medianos y grandes van a la mochila si entran, en vez de a la mano (tarea 62.7).
@export var prefer_backpack: bool = false
## Distancia máxima al objeto para poder tomarlo.
@export_range(0.5, 5.0, 0.1, "suffix:m") var grab_range: float = 2.0
## Dónde se sostiene, en el marco del CUERPO del jugador (-Z = adelante, +X = derecha).
## Si ves el objeto muy alto o bajo, ajustá la Y: depende de dónde esté el origen del Player.
@export var hold_offset: Vector3 = Vector3(0.0, 1.0, -1.1)
## Cuánto se corre a la derecha un objeto de una mano (solo estético: de dos manos va al centro).
@export_range(0.0, 1.0, 0.05, "suffix:m") var hand_spread: float = 0.5
## Hasta dónde se busca el piso bajo el objeto para mostrar dónde caería.
@export_range(0.5, 10.0, 0.5, "suffix:m") var preview_ray_length: float = 4.0

@export_group("Colocación")
## Un clic derecho más corto que esto suelta el objeto; más largo, apunta el fantasma.
@export_range(0.1, 0.6, 0.05, "suffix:s") var tap_seconds: float = 0.25
## Distancia horizontal máxima, desde el jugador, a la que se puede colocar.
@export_range(1.0, 8.0, 0.5, "suffix:m") var place_range: float = 3.0
## Cuánto gira el fantasma por cada paso de la rueda.
@export_range(5.0, 90.0, 5.0, "suffix:°") var rotate_step_degrees: float = 15.0
## Largo del rayo que sale de la cámara para apuntar.
@export_range(5.0, 200.0, 5.0, "suffix:m") var aim_ray_length: float = 50.0
## Altura de la mira en la pantalla, de 0 (arriba) a 1 (abajo). En tercera persona el
## personaje queda en el centro, así que se apunta un poco más arriba para no caer a sus pies.
@export_range(0.2, 0.5, 0.01) var aim_screen_y: float = 0.4

var _player: Player
# El objeto físico que está en la mano (null si no hay). Hands guarda su ItemStack.
var _held: WorldItem

# Estado del clic derecho y del modo "apuntar fantasma".
var _place_pressed: bool = false
var _place_press_ms: int = 0
var _place_notified: bool = false
var _placing: bool = false
var _place_valid: bool = false
var _place_ground: Vector3 = Vector3.ZERO
var _place_yaw: float = 0.0
var _yaw_offset: float = 0.0


## Posición del objeto en la mano, en el marco del cuerpo. Lógica pura.
## De dos manos: al centro. De una mano: un poco a la derecha.
static func hold_offset_for(hands_used: int, base: Vector3, spread: float) -> Vector3:
	if hands_used >= 2:
		return base
	return base + Vector3(spread, 0.0, 0.0)


## Qué hacer al recoger un objeto. Lógica pura. Devuelve:
##   &"to_backpack" → va directo a la mochila
##   &"to_hand"     → queda en la mano (que estaba libre)
##   &"swap"        → lo de la mano se guarda en la mochila y el nuevo queda en la mano
## o el motivo de fallo: &"too_big" (solo grúa) o &"no_room" (no entra en la mochila).
## Con `backpack_first`, un mediano o grande que entra en la mochila va a la mochila.
static func plan_pickup(size: ItemData.SizeClass, hands_required: ItemData.HandsRequired,
		hand_busy: bool, fits_in_backpack: bool, hand_item_fits_in_backpack: bool,
		backpack_first: bool = false) -> StringName:
	if Hands.hands_needed(hands_required) == 0:
		return &"too_big"
	if backpack_first and fits_in_backpack:
		return &"to_backpack"
	if size == ItemData.SizeClass.SMALL:
		return &"to_backpack" if fits_in_backpack else &"no_room"
	if not hand_busy:
		return &"to_hand"
	return &"swap" if hand_item_fits_in_backpack else &"no_room"


## ¿Es un plan que se puede ejecutar (y no un motivo de fallo)? Lógica pura.
static func is_ok_plan(plan: StringName) -> bool:
	return plan == &"to_backpack" or plan == &"to_hand" or plan == &"swap"


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
	# En la cabina las manos no hacen nada (tarea 52).
	if not _player.controls_enabled or _player.is_in_cab():
		return
	if event.is_action_pressed(&"grab"):
		try_grab()
	elif event.is_action_pressed(&"drop"):
		if _held == null:
			unload_backpack()
		else:
			drop_held()
	elif event.is_action_pressed(&"place"):
		_place_pressed = true
		_place_notified = false
		_place_press_ms = Time.get_ticks_msec()
	elif event.is_action_released(&"place"):
		_finish_place_input()
	elif _placing and event.is_action_pressed(&"rotate_cw"):
		# Un giro positivo alrededor de Y es antihorario visto desde arriba: horario es negativo.
		_yaw_offset = Placeable.rotate_offset(_yaw_offset, -1, rotate_step_degrees)
		get_viewport().set_input_as_handled()
	elif _placing and event.is_action_pressed(&"rotate_ccw"):
		_yaw_offset = Placeable.rotate_offset(_yaw_offset, 1, rotate_step_degrees)
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	# Si el objeto de la mano desapareció por otro lado, se limpia la mano.
	if _held != null and not is_instance_valid(_held):
		_held = null
		_player.get_hands().release()
		_cancel_place()

	# Con un menú abierto no se apunta: se olvida el clic derecho a medio camino.
	if (not _player.controls_enabled or _player.is_in_cab()) and (_place_pressed or _placing):
		_place_pressed = false
		_cancel_place()

	if _place_pressed and not _placing and _held_long_enough():
		_try_enter_placing()

	if _held == null:
		return
	# La mano se ancla al frente del CUERPO, no al de la cámara: gira cuando gira
	# el personaje y no cuando mirás alrededor (D61).
	var yaw: float = _player.get_facing_yaw()
	var body_basis := Basis(Vector3.UP, yaw)
	var hold_position: Vector3 = _player.global_position + body_basis * _offset_of(_held)
	_held.global_transform = Transform3D(body_basis, hold_position)
	if _placing:
		# El fantasma de apuntado reemplaza al que cae bajo la mano.
		_update_placing()
	else:
		_update_preview(Holdable.of(_held), hold_position, yaw)


## ¿Se está apuntando un fantasma de colocación? (para la interfaz y las pruebas)
func is_placing() -> bool:
	return _placing


## ¿El lugar apuntado es válido? Solo tiene sentido mientras `is_placing()`.
func is_place_valid() -> bool:
	return _placing and _place_valid


## Giro que sumó la rueda al fantasma, en radianes.
func get_yaw_offset() -> float:
	return _yaw_offset


## El objeto físico que está en la mano, o null.
func get_held_item() -> WorldItem:
	return _held


## Entrega lo que hay en la mano (tarea 58: el tablero de una estación lo consume al aprobar
## una entrega). El objeto desaparece. Devuelve su pila, o null si la mano estaba vacía.
func consume_held() -> ItemStack:
	if _held == null:
		return null
	_cancel_place()
	var item: WorldItem = _held
	var stack: ItemStack = item.stack
	_player.get_hands().release()
	_held = null
	item.queue_free()
	return stack


## Recoge el objeto suelto más cercano al alcance; si no hay, saca una unidad del
## contenedor más cercano. Devuelve false (y avisa por `grab_failed`) si no pudo.
func try_grab() -> bool:
	var target: WorldItem = _find_nearest_item()
	if target != null:
		return _grab_world_item(target)
	var area: StorageArea = _find_nearest_storage_area()
	if area != null:
		return _take_from_container(area)
	grab_failed.emit(&"nothing_near")
	return false


## Suelta lo que hay en la mano. Si lo suelta sobre un StorageArea, el área se
## encarga de guardarlo: acá no hace falta saberlo. Devuelve false si no tenía nada.
func drop_held() -> bool:
	if _held == null:
		return false
	var item: WorldItem = _held
	_held = null
	_release_to_world(item)
	return true


## Pasa a la mano UNA unidad de la ranura `slot` de la mochila (tarea 49). Si la mano
## está ocupada, lo que tiene vuelve a la mochila (contando el lugar que deja la
## unidad sacada); si no entra, no cambia nada y avisa &"no_room".
func take_from_backpack(slot: int) -> bool:
	var backpack: Inventory = _player.get_backpack()
	if slot < 0 or slot >= backpack.get_slot_count():
		push_error("Grabber.take_from_backpack: no existe la ranura %d" % slot)
		return false
	var sample: ItemStack = backpack.peek(slot)
	if sample == null:
		grab_failed.emit(&"container_empty")
		return false
	if Hands.hands_needed(sample.item.hands) == 0:
		grab_failed.emit(&"too_big")
		return false
	var hands: Hands = _player.get_hands()
	var hand_busy: bool = not hands.is_empty()
	if hand_busy:
		var held: ItemStack = hands.get_held()
		if backpack.can_store_amount_after_take(held, slot, 1) < held.quantity:
			grab_failed.emit(&"no_room")
			return false

	var taken: ItemStack = backpack.take(slot, 1)
	var item: WorldItem = WorldItem.create(taken)
	if item == null or Holdable.of(item) == null:
		# Mismo caso que al sacar de un contenedor: se devuelve y se avisa.
		push_error("'%s' no tiene un Holdable: no se puede pasar a la mano." % taken.item.id)
		backpack.try_store(taken)
		if item != null:
			item.free()  # todavía no está en el árbol, se libera directo
		grab_failed.emit(&"too_big")
		return false
	# Recién ahora, con la unidad afuera, lo de la mano entra seguro (se comprobó arriba).
	if hand_busy:
		_stow_held_in_backpack()
	get_tree().current_scene.add_child(item)
	# Nace sobre el jugador; desde el próximo paso de física lo ubica la mano.
	item.global_position = _player.global_position + Vector3.UP * hold_offset.y
	_hold(item)
	return true


## Guarda en la mochila lo que hay en la mano (tarea 49). Es todo o nada: si no entra
## entero, no cambia nada y avisa &"no_room" (o &"hands_empty" si no había nada).
func stow_held() -> bool:
	if _held == null:
		grab_failed.emit(&"hands_empty")
		return false
	if not _fits_in_backpack(_held.stack):
		grab_failed.emit(&"no_room")
		return false
	_cancel_place()
	_stow_held_in_backpack()
	return true


## Pasa al contenedor más cercano (el vagón) todo lo de la mochila que acepte y entre (tarea
## 62.7). Devuelve cuántas unidades pasó; si no pasó ninguna, avisa &"nothing_near" o
## &"container_full".
func unload_backpack() -> int:
	var area: StorageArea = _find_nearest_storage_area()
	if area == null:
		grab_failed.emit(&"nothing_near")
		return 0
	var container: StorageContainer = area.get_container()
	var backpack: Inventory = _player.get_backpack()
	var moved: int = 0
	for slot: int in backpack.get_slot_count():
		var sample: ItemStack = backpack.peek(slot)
		if sample == null or not container.accepts(sample.item):
			continue
		var amount: int = mini(sample.quantity, container.can_store_amount(sample))
		if amount <= 0:
			continue
		var taken: ItemStack = backpack.take(slot, amount)
		var leftover: ItemStack = container.try_store(taken)
		moved += taken.quantity - (leftover.quantity if leftover != null else 0)
		if leftover != null:
			backpack.try_store(leftover)
	if moved == 0:
		grab_failed.emit(&"container_full")
	else:
		backpack_unloaded.emit(moved)
	return moved


func _held_long_enough() -> bool:
	return float(Time.get_ticks_msec() - _place_press_ms) / 1000.0 >= tap_seconds


# ¿Entra `stack` entero en las ranuras de la mochila? Es todo o nada: no se guardan
# lotes a medias. Un objeto grande nunca entra (D86).
func _fits_in_backpack(stack: ItemStack) -> bool:
	return _player.get_backpack().can_store_amount(stack) >= stack.quantity


# Plan para recoger `stack` ahora mismo: uno de plan_pickup. Sin tope de peso (D86).
func _plan_for(stack: ItemStack) -> StringName:
	# Los pasajeros solo viajan en coches de pasajeros (tarea 60b): nunca a la mano ni a la mochila.
	if ItemData.is_passenger(stack.item):
		return &"passenger"
	var hands: Hands = _player.get_hands()
	var hand_busy: bool = not hands.is_empty()
	var hand_fits: bool = (not hand_busy) or _fits_in_backpack(hands.get_held())
	return plan_pickup(
			stack.item.size_class, stack.item.hands, hand_busy, _fits_in_backpack(stack), hand_fits, prefer_backpack)


func _grab_world_item(target: WorldItem) -> bool:
	var key_item := target.stack.item as KeyItemData
	if key_item != null:
		var key_items: KeyItems = _player.get_key_items()
		if key_items == null:
			push_error("El jugador no tiene un nodo KeyItems: no puede recoger '%s'." % key_item.id)
			grab_failed.emit(&"too_big")
			return false
		key_items.add(key_item)
		target.queue_free()
		return true
	var plan: StringName = _plan_for(target.stack)
	if not is_ok_plan(plan):
		grab_failed.emit(plan)
		return false

	# Ya se comprobó todo: desde acá, nada puede fallar a medias.
	match plan:
		&"to_backpack":
			_player.get_backpack().try_store(target.stack)
			# El cuerpo físico ya no hace falta: el objeto vive ahora como pila en la mochila.
			target.queue_free()
		&"to_hand":
			_hold(target)
		&"swap":
			_stow_held_in_backpack()
			_hold(target)
	return true


# Saca UNA unidad de la primera pila de la que se pueda y la recoge con las mismas
# reglas que un objeto suelto. Se comprueba con copias (peek) antes de sacar nada.
func _take_from_container(area: StorageArea) -> bool:
	var container: StorageContainer = area.get_container()

	var stack_index: int = -1
	var plan: StringName = &""
	var first_failure: StringName = &"container_empty"
	for index: int in container.get_stack_count():
		var sample: ItemStack = container.peek(index)
		var candidate_plan: StringName = _plan_for(sample.duplicate_stack(1))
		if is_ok_plan(candidate_plan):
			stack_index = index
			plan = candidate_plan
			break
		if first_failure == &"container_empty":
			first_failure = candidate_plan
	if stack_index == -1:
		grab_failed.emit(first_failure)
		return false

	var taken: ItemStack = container.take(stack_index, 1)
	if taken == null:
		grab_failed.emit(&"container_empty")
		return false

	if plan == &"to_backpack":
		_player.get_backpack().try_store(taken)
		return true

	# Va a la mano: hace falta un cuerpo físico con Holdable.
	var item: WorldItem = WorldItem.create(taken)
	if item == null or Holdable.of(item) == null:
		# La escena del objeto no se puede tomar a mano: se devuelve y se avisa.
		push_error("'%s' no tiene un Holdable: no se puede sacar a mano." % taken.item.id)
		container.try_store(taken)
		if item != null:
			item.free()  # todavía no está en el árbol, se libera directo
		grab_failed.emit(&"too_big")
		return false
	if plan == &"swap":
		_stow_held_in_backpack()
	get_tree().current_scene.add_child(item)
	item.global_position = area.global_position
	_hold(item)
	return true


# Pone el objeto en la mano: la lógica (Hands) primero y después el cuerpo, así no
# queda un objeto congelado sin dueño si algo falla antes.
func _hold(item: WorldItem) -> void:
	if not _player.get_hands().hold(item.stack):
		push_error("No se pudo sostener '%s': la mano debería estar libre." % item.stack.item.id)
		return
	Holdable.of(item).begin_hold()
	_held = item
	EventBus.item_held.emit(item.stack)


# Guarda en la mochila lo que hay en la mano. Quien llama ya comprobó que entra.
func _stow_held_in_backpack() -> void:
	var item: WorldItem = _held
	var stack: ItemStack = item.stack
	var leftover: ItemStack = _player.get_backpack().try_store(stack)
	if leftover != null:
		push_error("La mochila guardó solo una parte de un stack que había confirmado: revisar Inventory.")
	_player.get_hands().release()
	_held = null
	EventBus.item_released.emit(stack)
	item.queue_free()


# Al mantener el clic derecho: si hay un objeto que se pueda colocar con precisión,
# empieza el modo apuntar. Si no tiene Placeable, avisa una vez y al soltar el
# botón se trata como un soltar rápido.
func _try_enter_placing() -> void:
	if _held == null or Holdable.of(_held) == null:
		return
	if Placeable.of(_held) == null:
		if not _place_notified:
			_place_notified = true
			grab_failed.emit(&"not_placeable")
		return
	_placing = true
	_yaw_offset = 0.0
	_place_valid = false


# Al soltar el clic derecho: confirma la colocación, la cancela o, si fue un toque, suelta.
func _finish_place_input() -> void:
	if not _place_pressed:
		return
	_place_pressed = false
	if _placing:
		var item: WorldItem = _held
		var valid: bool = _place_valid
		var ground: Vector3 = _place_ground
		var yaw: float = _place_yaw
		_cancel_place()
		if valid and item != null:
			_place_item(item, ground, yaw)
		else:
			grab_failed.emit(&"place_invalid")
		return
	# Toque corto (o mantenido sobre un objeto sin Placeable): soltar sin validar.
	if not drop_held():
		grab_failed.emit(&"hands_empty")


func _cancel_place() -> void:
	if _held != null and is_instance_valid(_held):
		var holdable: Holdable = Holdable.of(_held)
		if holdable != null:
			holdable.hide_preview()
	_placing = false
	_place_valid = false


# Cada cuadro mientras se apunta: rayo desde la cámara, recorte de alcance,
# validación y color del fantasma.
func _update_placing() -> void:
	if _held == null:
		_cancel_place()
		return
	var holdable: Holdable = Holdable.of(_held)
	var placeable: Placeable = Placeable.of(_held)
	var camera: Camera3D = get_viewport().get_camera_3d()
	var tp_camera: ThirdPersonCamera = _player.get_camera()
	_place_valid = false
	if camera == null or tp_camera == null:
		holdable.hide_preview()
		return

	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	# La mira está un poco más arriba que el centro (aim_screen_y): en tercera persona el
	# centro de la pantalla cae sobre el propio personaje.
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	var aim_point := Vector2(screen_size.x * 0.5, screen_size.y * aim_screen_y)
	var from: Vector3 = camera.project_ray_origin(aim_point)
	var to: Vector3 = from + camera.project_ray_normal(aim_point) * aim_ray_length
	var hit: Dictionary = _cast_ray(space, from, to)
	if hit.is_empty():
		holdable.hide_preview()
		return
	var ground: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]

	# Fuera de alcance: se recorta en horizontal y se busca el piso bajo ese punto.
	var limited: Vector3 = Placeable.clamp_to_range(_player.global_position, ground, place_range)
	if not limited.is_equal_approx(ground):
		var top := Vector3(limited.x, _player.global_position.y + 2.0, limited.z)
		var below: Dictionary = _cast_ray(space, top, top + Vector3.DOWN * 8.0)
		if below.is_empty():
			holdable.hide_preview()
			return
		ground = below["position"]
		normal = below["normal"]

	var yaw: float = Placeable.facing_yaw(tp_camera.yaw, _yaw_offset)
	_place_ground = ground
	_place_yaw = yaw
	_place_valid = placeable.is_valid_at(space, holdable.body_transform_at(ground, yaw), normal)
	holdable.show_preview(ground, yaw, _place_valid)


# Deja el objeto en el lugar validado. Nace apenas levantado (el margen de Placeable)
# y la física lo asienta.
func _place_item(item: WorldItem, ground: Vector3, yaw: float) -> void:
	var holdable: Holdable = Holdable.of(item)
	var placeable: Placeable = Placeable.of(item)
	var stack: ItemStack = item.stack
	var spot: Transform3D = holdable.body_transform_at(ground, yaw)
	spot.origin += Vector3.UP * placeable.lift

	_player.get_hands().release()
	_held = null
	# Primero se libera y DESPUÉS se mueve (en la mano el cuerpo es cinemático y un
	# cambio de posición pendiente se pierde al liberarlo). Se mueve de dos maneras:
	# directo, por si el motor lo respeta, y con teleport_to, que es la forma oficial.
	holdable.end_hold(Vector3.ZERO)
	item.global_transform = spot
	item.teleport_to(spot)
	EventBus.item_released.emit(stack)
	EventBus.item_placed.emit(stack, spot.origin)


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


# Libera la mano y devuelve el cuerpo al mundo. Quien llama ya lo sacó de _held.
func _release_to_world(item: WorldItem) -> void:
	_player.get_hands().release()
	# Hereda solo la velocidad horizontal: no queremos que salga volando hacia arriba.
	var velocity: Vector3 = Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	Holdable.of(item).end_hold(velocity)
	EventBus.item_released.emit(item.stack)


func _offset_of(item: WorldItem) -> Vector3:
	var used: int = Hands.hands_needed(item.stack.item.hands)
	return hold_offset_for(used, hold_offset, hand_spread)


# Rayo contra el mundo (capa 1): piso, vehículos, plataformas.
func _cast_ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, WorldItem.LAYER_WORLD)
	return space.intersect_ray(query)


# Busca el piso bajo el objeto: ahí es donde caería al soltarlo (fantasma neutro).
func _update_preview(holdable: Holdable, from: Vector3, yaw: float) -> void:
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var hit: Dictionary = _cast_ray(space, from, from + Vector3.DOWN * preview_ray_length)
	if hit.is_empty():
		holdable.hide_preview()
		return
	var ground: Vector3 = hit["position"]
	holdable.show_drop_hint(ground, yaw)
