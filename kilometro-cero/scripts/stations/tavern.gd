class_name Tavern
extends Node3D
## Taberna de una estación (tarea 62c.3h, D143), provisoria hasta los pueblos armados (62c.4 y 62c.5):
## un local chico de tres paredes y techo, un cartel, una cama que se paga (hijo Bed "Cama") y un
## mostrador que vende pan (hijo FoodSeller "Mostrador"). El local se arma por código al empezar;
## la cama, el mostrador y el cartel están en la escena para moverlos en el editor.

## "Azul": la cama se llama "la taberna de Azul" y el cartel dice "TABERNA".
@export var town_name: String = ""
@export var bed_price: int = 20
## Ancho (x) y fondo (z) del local, en metros.
@export var size: Vector2 = Vector2(7.0, 5.0)

const WALL_HEIGHT: float = 3.0
const WALL_THICKNESS: float = 0.2


func _ready() -> void:
	var bed := get_node_or_null(^"Cama") as Bed
	if bed != null:
		bed.price = bed_price
		if town_name != "":
			bed.place_name = "la taberna de %s" % town_name
	if get_node_or_null(^"Local") == null:
		_build_room()


func get_bed() -> Bed:
	return get_node_or_null(^"Cama") as Bed


func get_counter() -> FoodSeller:
	return get_node_or_null(^"Mostrador") as FoodSeller


# Tres paredes (abierto hacia +z, el frente), techo de chapa y piso de tablas, con choque.
func _build_room() -> void:
	var room := StaticBody3D.new()
	room.name = "Local"
	add_child(room)
	var wall := _material(Color(0.88, 0.82, 0.68))
	var roof := _material(Color(0.46, 0.13, 0.15))
	var floor_material := _material(Color(0.5, 0.36, 0.22))
	var half := size / 2.0
	_part(room, Vector3(size.x, 0.1, size.y), Vector3(0.0, 0.05, 0.0), floor_material, false)
	_part(room, Vector3(size.x, WALL_HEIGHT, WALL_THICKNESS), Vector3(0.0, WALL_HEIGHT / 2.0, -half.y), wall, true)
	_part(room, Vector3(WALL_THICKNESS, WALL_HEIGHT, size.y), Vector3(-half.x, WALL_HEIGHT / 2.0, 0.0), wall, true)
	_part(room, Vector3(WALL_THICKNESS, WALL_HEIGHT, size.y), Vector3(half.x, WALL_HEIGHT / 2.0, 0.0), wall, true)
	_part(room, Vector3(size.x + 0.6, 0.12, size.y + 0.8), Vector3(0.0, WALL_HEIGHT + 0.06, 0.2), roof, false)


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material


static func _part(body: StaticBody3D, part_size: Vector3, at: Vector3, material: Material, solid: bool) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = part_size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	body.add_child(mesh)
	if not solid:
		return
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = part_size
	shape.shape = box_shape
	shape.position = at
	body.add_child(shape)
