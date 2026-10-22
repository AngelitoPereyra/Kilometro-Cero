class_name Placeable extends Node
## Capacidad de "se puede colocar con precisión" (tarea 15). Va como hijo directo
## de un WorldItem, junto a Holdable. Solo decide si un lugar es VÁLIDO para dejar
## el objeto: que la superficie no sea muy empinada y que su forma no se meta
## dentro de nada. El fantasma lo dibuja Holdable; el apuntado y los botones los
## maneja el Grabber.

## Pendiente máxima de la superficie donde se puede apoyar.
@export_range(0.0, 60.0, 1.0, "suffix:°") var max_slope_degrees: float = 30.0
## Cuánto se levanta la forma al consultar. Un objeto apoyado en el piso lo toca,
## y sin este margen ese contacto contaría como un choque.
@export_range(0.0, 0.2, 0.005, "suffix:m") var lift: float = 0.03

var _body: WorldItem
var _warned_no_shape: bool = false


## El Placeable de un objeto, o null si no tiene (entonces no se puede colocar con precisión).
static func of(item: WorldItem) -> Placeable:
	for child: Node in item.get_children():
		var placeable := child as Placeable
		if placeable != null:
			return placeable
	return null


## ¿Es una superficie lo bastante plana para apoyar algo? Lógica pura.
static func slope_ok(surface_normal: Vector3, max_slope: float) -> bool:
	return surface_normal.normalized().dot(Vector3.UP) >= cos(deg_to_rad(max_slope))


## Recorta `target` para que no quede a más de `max_distance` de `origin` en el
## plano horizontal; conserva la altura de `target`. Lógica pura.
static func clamp_to_range(origin: Vector3, target: Vector3, max_distance: float) -> Vector3:
	var flat := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	if flat.length() <= max_distance:
		return target
	flat = flat.normalized() * max_distance
	return Vector3(origin.x + flat.x, target.y, origin.z + flat.z)


## Giro del objeto: mira a la cámara (su frente, -Z, apunta hacia ella) más un
## desvío que se ajusta con la rueda. Lógica pura.
static func facing_yaw(camera_yaw: float, offset: float) -> float:
	return wrapf(camera_yaw + PI + offset, -PI, PI)


## Suma `steps` pasos de `step_degrees` al desvío de giro y lo mantiene entre -PI y PI.
## Lógica pura.
static func rotate_offset(offset: float, steps: int, step_degrees: float) -> float:
	return wrapf(offset + deg_to_rad(step_degrees) * steps, -PI, PI)


func _ready() -> void:
	_body = get_parent() as WorldItem
	if _body == null:
		push_error("Placeable debe ser hijo directo de un WorldItem.")


## ¿Se puede dejar el objeto con `body_transform` sobre una superficie con esa normal?
## `space` es el espacio físico (get_world_3d().direct_space_state).
func is_valid_at(space: PhysicsDirectSpaceState3D, body_transform: Transform3D, surface_normal: Vector3) -> bool:
	if not slope_ok(surface_normal, max_slope_degrees):
		return false
	var collider: CollisionShape3D = _find_collision_shape()
	if collider == null:
		# Sin forma no se puede comprobar el espacio libre: se acepta y se avisa una vez.
		if not _warned_no_shape:
			_warned_no_shape = true
			push_warning("%s no tiene un CollisionShape3D con forma: no se valida el espacio libre." % _body.name)
		return true

	var lifted := Transform3D(body_transform.basis, body_transform.origin + Vector3.UP * lift)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	# La forma está colgada del cuerpo: su transform es local a él.
	query.transform = lifted * collider.transform
	# Choca contra el mundo y contra otros objetos sueltos (no contra el jugador).
	query.collision_mask = WorldItem.LAYER_WORLD | WorldItem.LAYER_ITEMS
	query.exclude = [_body.get_rid()]
	return space.intersect_shape(query, 1).is_empty()


func _find_collision_shape() -> CollisionShape3D:
	for child: Node in _body.get_children():
		var collider := child as CollisionShape3D
		if collider != null and collider.shape != null and not collider.disabled:
			return collider
	return null
