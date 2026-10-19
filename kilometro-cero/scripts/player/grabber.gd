class_name Grabber extends Node
## Componente del jugador: toma y suelta objetos del mundo con las manos.
## Hijo directo de Player. Es el único que lee las acciones `grab` y `drop`.
## No cachea las referencias del jugador: las pide cuando las usa, porque
## Player termina de armarse DESPUÉS de sus hijos (_ready va de abajo hacia arriba).

## Se emite cuando no se pudo tomar algo. `reason` es &"nothing_near",
## &"hands_full", &"too_big" (solo con grúa) o &"too_heavy". La UI lo usará después.
signal grab_failed(reason: StringName)

## Distancia máxima al objeto para poder tomarlo.
@export_range(0.5, 5.0, 0.1, "suffix:m") var grab_range: float = 2.0
## Dónde se sostiene, en el marco de la cámara (-Z = adelante, +X = derecha).
## Si ves los objetos muy altos o bajos, ajustá la Y: depende de dónde esté el
## origen de tu Player.
@export var hold_offset: Vector3 = Vector3(0.0, 1.0, -1.1)
## Separación lateral de cada mano cuando son objetos de una mano.
@export_range(0.0, 1.0, 0.05, "suffix:m") var hand_spread: float = 0.5
## Hasta dónde se busca el piso bajo el objeto para mostrar dónde caería.
@export_range(0.5, 10.0, 0.5, "suffix:m") var preview_ray_length: float = 4.0

var _player: Player
# En el orden en que se tomaron: soltar saca el último.
var _held: Array[WorldItem] = []


## Posición de un objeto sostenido, en el marco de la cámara. Lógica pura.
## Dos manos: al centro. Una mano: la 0 es la derecha y la 1 la izquierda.
static func hold_offset_for(hands_used: int, hand_index: int, base: Vector3, spread: float) -> Vector3:
	if hands_used >= 2:
		return base
	var side: float = 1.0 if hand_index == 0 else -1.0
	return base + Vector3(side * spread, 0.0, 0.0)


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
	# Solo se toma y se suelta caminando.
	if _player.state != Player.State.WALKING:
		return
	if event.is_action_pressed(&"grab"):
		try_grab()
	elif event.is_action_pressed(&"drop"):
		drop_last()


func _physics_process(_delta: float) -> void:
	var camera: ThirdPersonCamera = _player.get_camera()
	if camera == null or _held.is_empty():
		return
	var yaw: float = camera.yaw
	var camera_basis := Basis(Vector3.UP, yaw)
	for item: WorldItem in _held:
		var offset: Vector3 = _offset_of(item)
		var hold_position: Vector3 = _player.global_position + camera_basis * offset
		item.global_transform = Transform3D(camera_basis, hold_position)
		_update_preview(Holdable.of(item), hold_position, yaw)


## Toma el objeto más cercano al alcance. Devuelve false (y avisa por
## `grab_failed`) si no pudo.
func try_grab() -> bool:
	var hands: Hands = _player.get_hands()
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
		grab_failed.emit(&"nothing_near")
		return false

	var target: WorldItem = candidates[index]
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
	_held.append(target)
	EventBus.item_held.emit(target.stack)
	return true


## Suelta el último objeto tomado. Devuelve false si no tenía nada.
func drop_last() -> bool:
	if _held.is_empty():
		return false
	var item: WorldItem = _held.pop_back()
	var hands: Hands = _player.get_hands()
	for i in Hands.HAND_COUNT:
		if hands.get_stack(i) == item.stack:
			hands.release(i)
			break
	# Hereda solo la velocidad horizontal: no queremos que salga volando hacia arriba.
	var velocity: Vector3 = Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	Holdable.of(item).end_hold(velocity)
	EventBus.item_released.emit(item.stack)
	return true


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
