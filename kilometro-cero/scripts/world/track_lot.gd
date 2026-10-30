@tool
class_name TrackLot
extends Marker3D
## Lote junto a la vía (D131, tarea 62b.5): un lugar vacío al costado de un tramo, cerca de una
## estación, donde brota la parcela del oficio de una familia que llega (TrackLots elige el lote).
## El marcador va en el centro del lote, con su +Z mirando a la vía: la parcela se pone con ese
## mismo giro (las escenas de scenes/parcels/ tienen el frente hacia +Z). Vacío se ven cuatro
## estacas en las esquinas, también en el editor; con parcela las estacas se esconden.
## Anillos (ajuste de Batmi, 2026-10-30): el campo son hectáreas (100 × 100 m: chacras, montes,
## corrales, canteras), la zona industrial de las ciudades lotes de un cuarto a media hectárea
## (50 × 50 m: galpones de ladrillo de la industria y de chapa del ferrocarril) y el anillo del
## pueblo lotes chicos (16 × 12 m). Un lote con `fixed_scene` ya está ocupado desde el principio
## (el galpón ferroviario) y nunca recibe familias.

## Grupo de todos los lotes.
const GROUP: StringName = &"track_lots"
## Segundos que flota el cartel "¡Llegaron los hacheros!".
const MESSAGE_TIME: float = 4.0
const MESSAGE_RISE: float = 2.0
const STAKE_HEIGHT: float = 0.8

## Anillo del lote: campo (hectáreas), zona industrial o pueblo.
enum Ring { FIELD, INDUSTRY, TOWN }

const RING_NAMES: Array[String] = ["campo", "zona industrial", "pueblo"]
## Medidas de cada anillo (a lo largo de la vía × fondo) cuando `size` queda en cero.
const RING_SIZES: Array[Vector2] = [Vector2(100.0, 100.0), Vector2(50.0, 50.0), Vector2(16.0, 12.0)]

## Estación a la que pertenece (su id, como en las vías).
@export var station_id: StringName
## Campo: los prefieren la comida y la materia prima; zona industrial: los procesados; pueblo: el
## anillo de adentro (D131). Si no queda del que prefiere, otro (TrackLots).
@export var ring: Ring = Ring.FIELD:
	set(value):
		ring = value
		_build_stakes()
## Ancho a lo largo de la vía (X) y fondo (Z, de la vía hacia afuera), en metros. Cero: el del anillo.
@export var size: Vector2 = Vector2.ZERO:
	set(value):
		size = value
		_build_stakes()
## Algo que ya está en el lote desde el principio (el galpón ferroviario). El lote no recibe familias.
@export var fixed_scene: PackedScene

var _parcel: Node3D
var _occupation: OccupationData
var _stakes: Node3D
var _message: Label3D


func _ready() -> void:
	add_to_group(GROUP)
	_build_stakes()
	if fixed_scene != null and _parcel == null:
		_parcel = fixed_scene.instantiate() as Node3D
		if _parcel != null:
			_parcel.name = "Fijo"
			# Interno: en el editor se ve pero no se guarda en la escena.
			add_child(_parcel, false, Node.INTERNAL_MODE_FRONT)
			_stakes.visible = false


func is_free() -> bool:
	return _parcel == null


## Las medidas del lote: `size`, o las de su anillo si quedó en cero.
func get_size() -> Vector2:
	return size if size != Vector2.ZERO else RING_SIZES[ring]


static func ring_name(value: Ring) -> String:
	return RING_NAMES[value]


## La parcela que brotó en el lote, o null.
func get_parcel() -> Node3D:
	return _parcel


func get_occupation() -> OccupationData:
	return _occupation


func get_occupation_id() -> StringName:
	return _occupation.id if _occupation != null else &""


## El cartel que está flotando, o null.
func get_message() -> Label3D:
	return _message if is_instance_valid(_message) else null


## Pone la parcela del oficio (su landscape_scene; sin escena, un galpón de bosquejo con el nombre).
## Con `animate` sus piezas brotan una tras otra (GrowthCelebration.pop) y flota un cartel; sin
## animar (al cargar) aparece quieta. Devuelve la parcela, o null si el lote ya estaba ocupado.
func place(occupation: OccupationData, animate: bool = true) -> Node3D:
	if not is_free() or occupation == null:
		return null
	_occupation = occupation
	if occupation.landscape_scene != null:
		_parcel = occupation.landscape_scene.instantiate() as Node3D
	if _parcel == null:
		_parcel = _make_placeholder(occupation)
	_parcel.name = "Parcela"
	add_child(_parcel)
	if _stakes != null:
		_stakes.visible = false
	if animate:
		var delay: float = 0.0
		var pieces: Array[Node3D] = GrowthCelebration.get_pieces(_parcel)
		if pieces.is_empty():
			pieces.append(_parcel)
		for piece: Node3D in pieces:
			GrowthCelebration.pop(piece, delay)
			delay += GrowthCelebration.POP_STAGGER
		_show_message("¡Llegaron los %s!" % occupation.display_name)
	return _parcel


## "Lote de azul (campo, libre)" o "Lote de azul (campo): hacheros".
func describe() -> String:
	if _occupation == null:
		return "Lote de %s (%s, %s)" % [station_id, ring_name(ring), "ocupado" if _parcel != null else "libre"]
	return "Lote de %s (%s): %s" % [station_id, ring_name(ring), _occupation.display_name]


func _build_stakes() -> void:
	if not is_inside_tree():
		return
	if _stakes != null:
		_stakes.queue_free()
	_stakes = Node3D.new()
	_stakes.name = "Estacas"
	_stakes.visible = _parcel == null
	add_child(_stakes, false, Node.INTERNAL_MODE_FRONT)
	var lot_size: Vector2 = get_size()
	# En las hectáreas las estacas son postes más gruesos, para verlas de lejos.
	var thick: float = clampf(lot_size.x / 200.0, 0.06, 0.3)
	var mesh := CylinderMesh.new()
	mesh.top_radius = thick * 0.7
	mesh.bottom_radius = thick
	mesh.height = STAKE_HEIGHT * (2.0 if lot_size.x > 40.0 else 1.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.75, 0.55)
	mesh.material = material
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var stake := MeshInstance3D.new()
		stake.mesh = mesh
		stake.position = Vector3(corner.x * lot_size.x * 0.5, mesh.height * 0.5, corner.y * lot_size.y * 0.5)
		_stakes.add_child(stake)


func _make_placeholder(occupation: OccupationData) -> Node3D:
	var root := Node3D.new()
	var shed := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(5.0, 2.5, 4.0)
	shed.mesh = box
	shed.position = Vector3(0.0, 1.25, 0.0)
	root.add_child(shed)
	var label := Label3D.new()
	label.text = occupation.display_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.outline_size = 10
	label.position = Vector3(0.0, 3.5, 0.0)
	root.add_child(label)
	return root


func _show_message(text: String) -> void:
	if is_instance_valid(_message):
		_message.queue_free()
	_message = Label3D.new()
	_message.text = text
	_message.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_message.font_size = 96
	_message.outline_size = 18
	_message.modulate = Color(1.0, 0.85, 0.3)
	_message.no_depth_test = true
	_message.position = Vector3(0.0, 5.0, 0.0)
	add_child(_message, false, Node.INTERNAL_MODE_FRONT)
	var tween: Tween = _message.create_tween().set_parallel()
	tween.tween_property(_message, "position:y", 5.0 + MESSAGE_RISE, MESSAGE_TIME)
	tween.tween_property(_message, "modulate:a", 0.0, MESSAGE_TIME * 0.4).set_delay(MESSAGE_TIME * 0.6)
	tween.chain().tween_callback(_message.queue_free)
