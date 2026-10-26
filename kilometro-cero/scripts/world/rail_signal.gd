class_name RailSignal
extends Node3D
## Semáforo de bosquejo (tarea 61, D110, D111) a la entrada de un tramo de vía simple: rojo
## mientras el tramo está ocupado (un automático tiene el bastón, hay un vehículo o un
## automático quedó parado en una punta), verde si está libre. Solo avisa: el tren del jugador puede entrar igual, y si se cruzan de
## frente los dos frenan y el automático espera a que el otro retroceda.
## Lo crea AutoTrains al lado de la vía; arma sus mallas solo.

const POST_HEIGHT: float = 3.2

var segment_id: StringName
var station_id: StringName
var clear: bool = true

var _lamp: MeshInstance3D
var _red: StandardMaterial3D
var _green: StandardMaterial3D


func _ready() -> void:
	var post := MeshInstance3D.new()
	post.name = "Poste"
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.15, POST_HEIGHT, 0.15)
	post.mesh = post_mesh
	post.position = Vector3(0.0, POST_HEIGHT * 0.5, 0.0)
	add_child(post)
	_red = _lamp_material(Color(0.95, 0.1, 0.05))
	_green = _lamp_material(Color(0.1, 0.9, 0.2))
	_lamp = MeshInstance3D.new()
	_lamp.name = "Luz"
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.22
	lamp_mesh.height = 0.44
	_lamp.mesh = lamp_mesh
	_lamp.position = Vector3(0.0, POST_HEIGHT, 0.0)
	add_child(_lamp)
	_apply()


func set_clear(value: bool) -> void:
	if value == clear:
		return
	clear = value
	_apply()


func _apply() -> void:
	if _lamp != null:
		_lamp.material_override = _green if clear else _red


static func _lamp_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	return material
