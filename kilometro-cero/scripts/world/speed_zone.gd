@tool
class_name SpeedZone
extends Node3D
## Zona de precaución (D131, tarea 62b.5): desde el cartel hasta el andén, el tren del jugador (y
## el prestado) no pasa de `max_speed`; Vehicle.get_max_speed la mira. Los automáticos no (siguen
## su horario). La zona es una caja: el origen va sobre la vía a la altura del cartel, se extiende
## `length` metros hacia -Z (hacia la estación) y `width` de ancho. El cartel de bosquejo (poste,
## tablero amarillo y texto, mirando a +Z, hacia el tren que llega) se arma por código como nodos
## internos, también en el editor.

## Alto de la caja (m), para no depender de la altura exacta de la vía.
const HEIGHT: float = 20.0

## Velocidad máxima dentro de la zona (m/s; 4,2 m/s son 15 km/h).
@export_range(0.5, 30.0, 0.1, "suffix:m/s") var max_speed: float = 4.2:
	set(value):
		max_speed = value
		_build_sign()
## Largo de la zona hacia -Z (m).
@export_range(5.0, 500.0, 1.0, "suffix:m") var length: float = 130.0
## Ancho de la zona (m), centrado en el origen.
@export_range(2.0, 200.0, 1.0, "suffix:m") var width: float = 60.0
## Dónde está el cartel respecto del origen (al costado de la vía).
@export var sign_offset: Vector3 = Vector3(3.5, 0.0, 0.0):
	set(value):
		sign_offset = value
		_build_sign()

static var _zones: Array[SpeedZone] = []

var _sign: Node3D


func _ready() -> void:
	_build_sign()


func _enter_tree() -> void:
	if not Engine.is_editor_hint() and not _zones.has(self):
		_zones.append(self)


func _exit_tree() -> void:
	_zones.erase(self)


## Las zonas que hay en el juego (no las del editor).
static func get_zones() -> Array[SpeedZone]:
	return _zones


static func has_zones() -> bool:
	return not _zones.is_empty()


## Si un punto global está dentro de la zona.
func contains(point: Vector3) -> bool:
	if not is_inside_tree():
		return false
	return contains_local(to_local(point), length, width)


## Lógica pura: un punto local dentro de la caja de largo `zone_length` (hacia -Z) y ancho `zone_width`.
static func contains_local(local: Vector3, zone_length: float, zone_width: float) -> bool:
	return local.z <= 0.0 and local.z >= -zone_length \
			and absf(local.x) <= zone_width * 0.5 and absf(local.y) <= HEIGHT * 0.5


## La zona más lenta que pisa alguno de esos vehículos, o null.
static func find_for(vehicles: Array[Vehicle]) -> SpeedZone:
	var found: SpeedZone = null
	for zone: SpeedZone in _zones:
		if found != null and zone.max_speed >= found.max_speed:
			continue
		for vehicle: Vehicle in vehicles:
			if vehicle != null and vehicle.is_inside_tree() and zone.contains(vehicle.global_position):
				found = zone
				break
	return found


## Tope de velocidad para un tren (todos sus vehículos): el de la zona más lenta que pisa, o INF.
static func limit_for(vehicles: Array[Vehicle]) -> float:
	var zone: SpeedZone = find_for(vehicles)
	return zone.max_speed if zone != null else INF


## El tope en km/h, redondeado (lo que dice el cartel).
func get_kmh() -> int:
	return roundi(max_speed * 3.6)


func sign_text() -> String:
	return "PRECAUCIÓN\n%d km/h" % get_kmh()


func _build_sign() -> void:
	if not is_inside_tree():
		return
	if _sign != null:
		_sign.queue_free()
	_sign = Node3D.new()
	_sign.name = "Cartel"
	_sign.position = sign_offset
	add_child(_sign, false, Node.INTERNAL_MODE_FRONT)
	var post := MeshInstance3D.new()
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.15, 2.6, 0.15)
	post.mesh = post_mesh
	post.position = Vector3(0.0, 1.3, 0.0)
	post.material_override = _material(Color(0.35, 0.3, 0.25))
	_sign.add_child(post)
	var board := MeshInstance3D.new()
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(1.6, 1.0, 0.08)
	board.mesh = board_mesh
	board.position = Vector3(0.0, 2.6, 0.05)
	board.material_override = _material(Color(1.0, 0.8, 0.1))
	_sign.add_child(board)
	var label := Label3D.new()
	label.name = "Texto"
	label.text = sign_text()
	label.font_size = 40
	label.outline_size = 0
	label.modulate = Color(0.1, 0.1, 0.1)
	label.position = Vector3(0.0, 2.6, 0.1)
	_sign.add_child(label)


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
