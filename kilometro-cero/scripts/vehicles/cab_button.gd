@tool
class_name CabButton
extends Area3D
## Botón de la botonera de la cabina (tarea 60c): en 1ª persona se aprieta con el clic
## izquierdo apuntando con la mira del centro (Cab.press_aimed). Hace lo mismo que su tecla
## (Cab.press_control). Arma solo su forma, su botón y su cartel, así en la escena alcanza con
## poner el nodo y elegir `control`. Va dentro de una Cab (por ejemplo, en "Botonera").

signal pressed

## Qué hace: una de las claves de LABELS (las mismas que Cab.press_control).
@export var control: StringName = &"forward":
	set(value):
		control = value
		_rebuild()
## Texto del cartel; vacío usa el de LABELS.
@export var label_text: String = "":
	set(value):
		label_text = value
		_rebuild()
@export var color: Color = Color(0.8, 0.15, 0.1):
	set(value):
		color = value
		_rebuild()
@export_range(0.02, 0.2, 0.005, "suffix:m") var radius: float = 0.05

## Controles que entiende la cabina y su cartel por defecto.
const LABELS: Dictionary[StringName, String] = {
	&"forward": "Adelante",
	&"back": "Atrás",
	&"brake": "Freno",
	&"lights": "Luces",
	&"horn": "Bocina",
	&"doors": "Puertas",
}
## Capa de los botones: "interactuables" (capa 4, 02-arquitectura sección 9).
const LAYER: int = 1 << 3
const PRESS_DEPTH: float = 0.015

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _label: Label3D
var _hovered: bool = false


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	_rebuild()


## El texto que muestra (y que la cabina usa para la mira).
func get_label() -> String:
	return label_text if not label_text.is_empty() else LABELS.get(control, String(control))


func is_hovered() -> bool:
	return _hovered


## Lo ilumina mientras la mira lo apunta.
func set_hovered(value: bool) -> void:
	_hovered = value
	if _material != null:
		_material.emission_enabled = value
		_material.emission = color
		_material.emission_energy_multiplier = 0.8


## Lo aprieta: la cabina hace lo que corresponde. Devuelve si hizo algo.
func press() -> bool:
	var cab: Cab = get_cab()
	if cab == null:
		return false
	var done: bool = cab.press_control(control)
	pressed.emit()
	if _mesh != null and is_inside_tree():
		var tween: Tween = create_tween()
		tween.tween_property(_mesh, "position:y", -PRESS_DEPTH, 0.06)
		tween.tween_property(_mesh, "position:y", 0.0, 0.12)
	return done


func get_cab() -> Cab:
	var node: Node = get_parent()
	while node != null:
		if node is Cab:
			return node
		node = node.get_parent()
	return null


# Arma la forma, el botón y el cartel (cada vez que cambia un dato).
func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child: Node in get_children():
		if child.has_meta(&"cab_button_part"):
			child.free()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(radius * 2.6, 0.08, radius * 2.6)
	shape.shape = box
	_add_part(shape)
	_mesh = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 0.03
	_mesh.mesh = cylinder
	_material = StandardMaterial3D.new()
	_material.albedo_color = color
	_mesh.material_override = _material
	_add_part(_mesh)
	_label = Label3D.new()
	_label.text = get_label()
	_label.font_size = 28
	_label.pixel_size = 0.0012
	_label.outline_size = 6
	_label.position = Vector3(0.0, 0.02, radius + 0.035)
	_label.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	_add_part(_label)
	set_hovered(_hovered)


func _add_part(part: Node3D) -> void:
	part.set_meta(&"cab_button_part", true)
	add_child(part)
