class_name Holdable extends Node
## Capacidad de "se puede tomar con las manos". Va como hijo directo de un
## WorldItem. Maneja el estado de "en la mano" y el fantasma que muestra dónde
## quedaría el objeto. No sabe quién lo sostiene: eso lo decide el Grabber.
## La validación de si un lugar sirve la hace Placeable; acá solo se dibuja.

# Colores del fantasma. Blanco azulado = dónde caería si lo soltás (sin validar).
# Verde = se puede colocar ahí, rojo = no se puede (modo apuntar, tarea 15).
const GHOST_DROP: Color = Color(0.85, 0.9, 1.0, 0.25)
const GHOST_VALID: Color = Color(0.3, 1.0, 0.3, 0.4)
const GHOST_INVALID: Color = Color(1.0, 0.3, 0.3, 0.4)

var is_held: bool = false

var _body: WorldItem
var _preview: MeshInstance3D
var _preview_material: StandardMaterial3D
var _preview_failed: bool = false
# Posición del mesh respecto del cuerpo, para ubicar el fantasma igual.
var _preview_local: Transform3D = Transform3D.IDENTITY
# Distancia del origen del cuerpo a lo más bajo del mesh: sirve para que el
# fantasma apoye sobre el piso en vez de quedar enterrado.
var _foot_offset: float = 0.0


## El Holdable de un objeto, o null si no tiene (entonces no se puede tomar).
static func of(item: WorldItem) -> Holdable:
	for child: Node in item.get_children():
		var holdable := child as Holdable
		if holdable != null:
			return holdable
	return null


func _ready() -> void:
	_body = get_parent() as WorldItem
	if _body == null:
		push_error("Holdable debe ser hijo directo de un WorldItem.")


func begin_hold() -> void:
	if is_held or _body == null:
		return
	is_held = true
	_body.linear_velocity = Vector3.ZERO
	_body.angular_velocity = Vector3.ZERO
	_body.set_held(true)


## Lo suelta. `inherited_velocity` es la velocidad del jugador, para que el
## objeto no se frene en seco si lo suelta caminando.
func end_hold(inherited_velocity: Vector3 = Vector3.ZERO) -> void:
	if not is_held or _body == null:
		return
	is_held = false
	hide_preview()
	_body.set_held(false)
	_body.linear_velocity = inherited_velocity
	_body.angular_velocity = Vector3.ZERO


## Transform que tendría el cuerpo con su base apoyada en `ground_point` y
## girado `yaw`. Lo usa Placeable para consultar si ese lugar está libre.
func body_transform_at(ground_point: Vector3, yaw: float) -> Transform3D:
	if _preview == null and not _preview_failed:
		_build_preview()
	return Transform3D(Basis(Vector3.UP, yaw), ground_point + Vector3.UP * _foot_offset)


## Fantasma del modo apuntar: verde si se puede dejar ahí, rojo si no.
func show_preview(ground_point: Vector3, yaw: float, valid: bool = true) -> void:
	_show(ground_point, yaw, GHOST_VALID if valid else GHOST_INVALID)


## Fantasma neutro que muestra dónde caería el objeto si lo soltás (sin validar).
func show_drop_hint(ground_point: Vector3, yaw: float) -> void:
	_show(ground_point, yaw, GHOST_DROP)


func hide_preview() -> void:
	if _preview != null:
		_preview.visible = false


func _show(ground_point: Vector3, yaw: float, color: Color) -> void:
	var body_transform: Transform3D = body_transform_at(ground_point, yaw)
	if _preview == null:
		return
	_preview_material.albedo_color = color
	_preview.global_transform = body_transform * _preview_local
	_preview.visible = true


# El fantasma se arma recién cuando hace falta, copiando el primer mesh del objeto.
func _build_preview() -> void:
	var source: MeshInstance3D = null
	for node: Node in _body.find_children("*", "MeshInstance3D", true, false):
		source = node as MeshInstance3D
		break
	if source == null or source.mesh == null:
		_preview_failed = true
		push_warning("%s no tiene un MeshInstance3D con mesh: no habrá previsualización." % _body.name)
		return
	_preview_local = _body.global_transform.affine_inverse() * source.global_transform
	# Transform3D * AABB devuelve el AABB transformado; su position.y es lo más bajo.
	_foot_offset = -(_preview_local * source.mesh.get_aabb()).position.y
	_preview_material = _make_ghost_material()
	_preview = MeshInstance3D.new()
	_preview.mesh = source.mesh
	_preview.material_override = _preview_material
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview.visible = false
	# top_level: no hereda el movimiento del cuerpo; queda donde lo ponemos en el mundo.
	_preview.top_level = true
	_body.add_child(_preview)


func _make_ghost_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = GHOST_DROP
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
