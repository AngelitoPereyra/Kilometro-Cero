class_name ToolTarget
extends Node
## Base de Clearable y Harvestable (tarea 55, D83): algo del mundo que se trabaja con una
## herramienta clave a golpes (clic izquierdo, ToolUser). Va como hijo del cuerpo que se ve
## (un Node3D: el obstáculo o el árbol); desde ahí se miden la distancia y el temblor.
## Al llegar a `hits_required` golpes termina: suelta `drop_amount` objetos `drop_item`
## alrededor y cada subclase decide qué pasa con el cuerpo (_on_finished).
## Sin durabilidad ni costo (D83): con la herramienta, siempre se puede.

## Cada golpe que cuenta.
signal hit_landed(hits_done: int, hits_required: int)
## Se terminó (despejado o talado).
signal finished

## Grupo de todo lo que se puede trabajar con una herramienta: de acá busca el ToolUser.
const GROUP: StringName = &"tool_targets"
## Cuánto se achica el cuerpo en cada golpe, para que se note (vuelve solo).
const SHAKE_SCALE: float = 0.93
## Si el cuerpo tiene un hijo con este nombre, tiembla solo él (escalar un cuerpo físico no
## conviene).
const VISUAL_NODE: NodePath = ^"Visual"

## Herramienta necesaria. Vacía: se hace con las manos.
@export var required_tool: KeyItemData
@export_range(1, 30, 1) var hits_required: int = 3
## Distancia horizontal máxima desde el origen del cuerpo para poder golpearlo.
@export_range(0.5, 10.0, 0.1, "suffix:m") var reach: float = 3.0

@export_group("Lo que deja")
@export var drop_item: ItemData
@export_range(0, 20, 1) var drop_amount: int = 0
## Radio del círculo en el que caen los objetos.
@export_range(0.0, 5.0, 0.1, "suffix:m") var drop_radius: float = 1.2
## Altura sobre el origen del cuerpo a la que nacen (la física los apoya).
@export_range(0.0, 3.0, 0.1, "suffix:m") var drop_height: float = 0.6

var hits_done: int = 0

var _shake_tween: Tween


## true si con `hits` golpes ya está terminado. Lógica pura.
static func is_done(hits: int, required: int) -> bool:
	return hits >= maxi(required, 1)


## Dónde caen `count` objetos: repartidos en un círculo alrededor de `center` (uno solo, en
## el centro). Lógica pura.
static func drop_positions(center: Vector3, count: int, radius: float) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	if count == 1:
		positions.append(center)
		return positions
	for i: int in count:
		var angle: float = TAU * float(i) / float(count)
		positions.append(center + Vector3(cos(angle), 0.0, sin(angle)) * radius)
	return positions


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	if get_body() == null:
		push_error("%s debe ser hijo de un Node3D (el obstáculo o el árbol)." % name)


## El cuerpo que se trabaja (el padre).
func get_body() -> Node3D:
	return get_parent() as Node3D


## Id de la herramienta necesaria (&"" si no hace falta).
func get_required_tool_id() -> StringName:
	return required_tool.id if required_tool != null else &""


## Nombre de la herramienta para la interfaz ("hacha"), o "" si no hace falta.
func get_required_tool_name() -> String:
	return required_tool.display_name if required_tool != null else ""


## Verbo para la interfaz ("despejar", "talar"). Lo cambia cada subclase.
func get_action_name() -> String:
	return "trabajar"


## Si todavía se puede trabajar (no terminó, o volvió a crecer).
func is_available() -> bool:
	return is_inside_tree() and not is_done(hits_done, hits_required)


## Distancia horizontal desde `point` hasta el origen del cuerpo.
func horizontal_distance_to(point: Vector3) -> float:
	var body: Node3D = get_body()
	if body == null:
		return INF
	var offset: Vector3 = body.global_position - point
	return Vector2(offset.x, offset.z).length()


func can_reach(point: Vector3) -> bool:
	return horizontal_distance_to(point) <= reach


## Un golpe. Devuelve true si con este golpe terminó. Quien llama ya comprobó la herramienta.
func hit() -> bool:
	if not is_available():
		return false
	hits_done += 1
	hit_landed.emit(hits_done, hits_required)
	if not is_done(hits_done, hits_required):
		_shake()
		return false
	_finish()
	return true


## Lo deja como nuevo (cero golpes).
func reset_hits() -> void:
	hits_done = 0


func _finish() -> void:
	spawn_drops()
	finished.emit()
	_on_finished()


## Suelta lo que deja en el mundo. Devuelve los objetos creados (ya en la escena).
func spawn_drops() -> Array[WorldItem]:
	var spawned: Array[WorldItem] = []
	var body: Node3D = get_body()
	if drop_item == null or drop_amount <= 0 or body == null or not is_inside_tree():
		return spawned
	var center: Vector3 = body.global_position + Vector3.UP * drop_height
	var parent: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	for spot: Vector3 in drop_positions(center, drop_amount, drop_radius):
		var item: WorldItem = WorldItem.create(ItemStack.new(drop_item, 1))
		if item == null:
			continue
		parent.add_child(item)
		item.global_position = spot
		spawned.append(item)
	return spawned


## Lo que hace cada subclase al terminar (borrar el obstáculo, esconder el árbol).
func _on_finished() -> void:
	pass


# Un temblor corto: se achica y vuelve. Solo aspecto.
func _shake() -> void:
	var body: Node3D = get_body()
	if body == null or not is_inside_tree():
		return
	var visual := body.get_node_or_null(VISUAL_NODE) as Node3D
	if visual == null:
		visual = body
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
		visual.scale = Vector3.ONE
	_shake_tween = create_tween()
	_shake_tween.tween_property(visual, "scale", Vector3.ONE * SHAKE_SCALE, 0.05)
	_shake_tween.tween_property(visual, "scale", Vector3.ONE, 0.12)
