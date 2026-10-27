class_name RailSignal
extends Node3D
## Cartel de señal de bosquejo (tareas 61, 61b y 61e, D110, D114, D117): un poste con un cartel de
## dos caras, cada una con su luz. El cartel manda sobre una sola vía y cada cara le habla a los
## trenes que se acercan por ese lado: la de adelante (`front`, la que mira hacia `viewers`) y la
## de atrás. Visto de costado casi no se ve la luz, como en una señal de verdad.
## Hay dos clases (los pone y los prende AutoTrains):
## - De línea (LINE): en cada punta de un tramo, unos metros adentro, antes del cambio de la
##   estación. Adelante, la salida a la línea (`segment_id` desde `station_id`): verde del lado
##   por donde entra el automático que lo reservó y rojo del otro, rojo mientras haya un tren
##   adentro. Atrás, la entrada a la estación: si la vía a la que lleva el cambio está libre. En la
##   vía doble cada vía tiene su cartel y la cara de contramano queda siempre en rojo.
## - De vía de estación (TRACK): en cada vía de la estación, pasando el cambio de cada punta (del
##   otro lado de la división). Adelante, la salida por esa punta: el cambio puesto para esta vía
##   y lo que sigue libre. Atrás, para el que entra: si esta vía está libre.
## - De bloque (BLOCK, tarea 61e.3): en la vía doble larga, carteles intermedios cada
##   AutoTrains.block_length más o menos, que parten cada vía en bloques. Adelante, para el que va
##   en el sentido de la vía: rojo si hay algo en el bloque que sigue. Atrás, siempre rojo
##   (contramano). En el rojo frena cualquier tren, también los automáticos.
## Amarillo (tarea 61e.3): en los de línea y de bloque, "el próximo cartel está en rojo". Deja
## pasar como el verde.
## Si el rojo de una salida de línea es por un automático, para el tren del jugador es un tramo
## cortado en ese sentido (no entra hasta que se ponga verde); si es por otro vehículo, solo
## avisa. En la salida en rojo de una vía de estación el tren del jugador frena (tarea 61e.2); al
## lado de ese cartel está la palanca de la vía (TrackLever) para pedir la salida.

enum Kind { LINE, TRACK, BLOCK }
enum Aspect { RED, YELLOW, GREEN }

const POST_HEIGHT: float = 3.0
const BOARD_SIZE: Vector3 = Vector3(0.6, 1.0, 0.1)
const LAMP_RADIUS: float = 0.17
const LAMP_DEPTH: float = 0.04

var kind: Kind = Kind.LINE
## Cartel de línea: el tramo y la estación de esa punta. De bloque: el tramo y la estación de
## donde sale su vía.
var segment_id: StringName
var station_id: StringName
## Cartel de bloque: cuál es, contando desde la salida de la estación (el cartel de salida es el 0).
var block_index: int = 0
## Cartel de vía de estación: la vía y la punta (true: el final de su curva).
var station_track: StationTrack
var at_end: bool = false
## Cartel de vía de estación o de bloque: el avance de su curva donde está (ahí frena el tren si
## está en rojo, tareas 61e.2 y 61e.3).
var track_offset: float = 0.0
## La cara de adelante.
var front: Aspect = Aspect.GREEN
## La cara de atrás.
var back: Aspect = Aspect.RED
## Si la cara de adelante deja pasar (la salida).
var clear: bool:
	get:
		return front != Aspect.RED
## Si la cara de atrás deja pasar (la entrada).
var back_clear: bool:
	get:
		return back != Aspect.RED

var _front_lamp: MeshInstance3D
var _back_lamp: MeshInstance3D
var _materials: Dictionary = {}


func _ready() -> void:
	var post := MeshInstance3D.new()
	post.name = "Poste"
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.12, POST_HEIGHT, 0.12)
	post.mesh = post_mesh
	post.position = Vector3(0.0, POST_HEIGHT * 0.5, 0.0)
	post.material_override = _plain_material(Color(0.85, 0.85, 0.8))
	add_child(post)
	var board := MeshInstance3D.new()
	board.name = "Cartel"
	var board_mesh := BoxMesh.new()
	board_mesh.size = BOARD_SIZE
	board.mesh = board_mesh
	board.position = Vector3(0.0, POST_HEIGHT + BOARD_SIZE.y * 0.5, 0.0)
	board.material_override = _plain_material(Color(0.08, 0.08, 0.08))
	add_child(board)
	for aspect: Aspect in [Aspect.RED, Aspect.YELLOW, Aspect.GREEN]:
		_materials[aspect] = _lamp_material(aspect_color(aspect))
	_front_lamp = _make_lamp("LuzAdelante", 1.0)
	_back_lamp = _make_lamp("LuzAtras", -1.0)
	_apply()


## Gira el cartel para que la cara de adelante mire hacia `viewers` (global, horizontal): la ven
## los trenes que vienen desde ese lado.
func face_towards(viewers: Vector3) -> void:
	var flat := Vector3(viewers.x, 0.0, viewers.z)
	if flat.length_squared() < 0.0001:
		return
	# Basis.looking_at deja -Z hacia el objetivo: la cara de adelante (+Z) queda hacia `viewers`.
	global_basis = Basis.looking_at(-flat.normalized(), Vector3.UP)


## Hacia dónde mira la cara de adelante (global, horizontal).
func get_front_direction() -> Vector3:
	return global_basis.z.normalized()


func set_aspects(front_aspect: Aspect, back_aspect: Aspect) -> void:
	if front_aspect == front and back_aspect == back:
		return
	front = front_aspect
	back = back_aspect
	_apply()


## La cara de adelante en verde o en rojo (la de atrás no cambia).
func set_clear(value: bool) -> void:
	set_aspects(Aspect.GREEN if value else Aspect.RED, back)


static func aspect_color(aspect: Aspect) -> Color:
	match aspect:
		Aspect.GREEN:
			return Color(0.1, 0.9, 0.2)
		Aspect.YELLOW:
			return Color(1.0, 0.75, 0.05)
	return Color(0.95, 0.1, 0.05)


func _make_lamp(node_name: String, side: float) -> MeshInstance3D:
	var lamp := MeshInstance3D.new()
	lamp.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = LAMP_RADIUS
	mesh.bottom_radius = LAMP_RADIUS
	mesh.height = LAMP_DEPTH
	lamp.mesh = mesh
	# Un disco plano pegado a cada cara: de costado se ve solo el borde.
	lamp.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	lamp.position = Vector3(0.0, POST_HEIGHT + BOARD_SIZE.y * 0.62, side * (BOARD_SIZE.z + LAMP_DEPTH) * 0.5)
	add_child(lamp)
	return lamp


func _apply() -> void:
	if _front_lamp == null:
		return
	_front_lamp.material_override = _materials[front]
	_back_lamp.material_override = _materials[back]


static func _lamp_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	return material


static func _plain_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
