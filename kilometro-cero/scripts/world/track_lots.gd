class_name TrackLots
extends Node3D
## Paisaje productivo (D131, tarea 62b.5): cada familia de una estación tiene su parcela en un lote
## junto a la vía (TrackLot, hijos de este nodo o en cualquier parte de la escena). Al llegar una
## familia jugando (ProductionModel.family_added) brota la parcela de su oficio en el lote libre más
## cercano a su estación: los procesados prefieren los lotes de la zona industrial y la comida y la
## materia prima los del campo (TrackLot.ring; el anillo del pueblo queda en segundo lugar para todos). Al empezar, las familias que ya estaban (el cupo del
## nivel inicial, una partida cargada) aparecen quietas. Uno por escena. Sin lugar, la familia
## queda esperando lote (get_pending) y brota cuando se suma uno y se llama a sync_station.

## Brotó la parcela de una familia (animated: jugando; false al empezar o al cargar).
signal parcel_placed(lot: TrackLot, occupation: OccupationData, animated: bool)

## Grupo del nodo (uno por escena).
const GROUP: StringName = &"track_lots_manager"

## El modelo de las familias. Null: GameState.production.
var model: ProductionModel
## Dónde está cada estación: func(station_id) -> Variant (Vector3 global, o null). Vacío: la
## Station de la escena con ese id (Station.find).
var station_position: Callable

# Familias de cada estación que ya tienen parcela, en orden de llegada.
var _placed: Dictionary[StringName, int] = {}
var _connected: ProductionModel


func _ready() -> void:
	add_to_group(GROUP)
	# Diferido: las estaciones se registran en el modelo en su propio _ready.
	sync_all.call_deferred(false)


static func find_in(tree: SceneTree) -> TrackLots:
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP) as TrackLots


## El modelo que usa (el propio o el de GameState).
func get_model() -> ProductionModel:
	return model if model != null else GameState.production


## Pone las parcelas que falten de todas las estaciones del modelo.
func sync_all(animate: bool = false) -> void:
	_connect_model()
	var production: ProductionModel = get_model()
	if production == null:
		return
	for station_id: StringName in production.get_station_ids():
		sync_station(station_id, animate)


## Pone las parcelas de las familias de la estación que todavía no tienen. Devuelve cuántas puso.
func sync_station(station_id: StringName, animate: bool = true) -> int:
	_connect_model()
	var production: ProductionModel = get_model()
	if production == null:
		return 0
	var families: Array[StringName] = production.get_families(station_id)
	var placed: int = _placed.get(station_id, 0)
	var count: int = 0
	while placed < families.size():
		var occupation: OccupationData = production.get_occupation(families[placed])
		var lot: TrackLot = choose_lot(station_id, occupation)
		if lot == null:
			break
		lot.place(occupation, animate)
		placed += 1
		count += 1
		parcel_placed.emit(lot, occupation, animate)
	_placed[station_id] = placed
	return count


## Familias de la estación que esperan lote.
func get_pending(station_id: StringName) -> int:
	var production: ProductionModel = get_model()
	if production == null:
		return 0
	return production.get_family_count(station_id) - _placed.get(station_id, 0)


## Los lotes de la estación en la escena, en orden del árbol.
func get_lots(station_id: StringName) -> Array[TrackLot]:
	var lots: Array[TrackLot] = []
	for node: Node in get_tree().get_nodes_in_group(TrackLot.GROUP):
		var lot := node as TrackLot
		if lot != null and lot.station_id == station_id and not lot.is_queued_for_deletion():
			lots.append(lot)
	return lots


func get_free_lots(station_id: StringName) -> Array[TrackLot]:
	var lots: Array[TrackLot] = []
	for lot: TrackLot in get_lots(station_id):
		if lot.is_free():
			lots.append(lot)
	return lots


## El lote donde brotaría la parcela de ese oficio en la estación, o null si no queda ninguno.
func choose_lot(station_id: StringName, occupation: OccupationData) -> TrackLot:
	var processed: bool = occupation != null and occupation.kind == OccupationData.Kind.PROCESSED
	return pick_lot(get_free_lots(station_id), _station_position(station_id), processed)


## Orden de anillos que prefiere un oficio: procesado zona industrial, pueblo, campo; los demás
## campo, pueblo, zona industrial.
static func ring_order(processed: bool) -> Array[TrackLot.Ring]:
	if processed:
		return [TrackLot.Ring.INDUSTRY, TrackLot.Ring.TOWN, TrackLot.Ring.FIELD]
	return [TrackLot.Ring.FIELD, TrackLot.Ring.TOWN, TrackLot.Ring.INDUSTRY]


## Lógica pura: entre los lotes libres, el más cercano a `at` del anillo que prefiere el oficio
## (ring_order); si no queda de ese, del siguiente. Con `at` null, el primero en orden. Null si
## la lista está vacía.
static func pick_lot(lots: Array[TrackLot], at: Variant, processed: bool) -> TrackLot:
	var order: Array[TrackLot.Ring] = ring_order(processed)
	var best: TrackLot = null
	var best_score: float = INF
	for lot: TrackLot in lots:
		if not lot.is_free():
			continue
		var score: float = order.find(lot.ring) * 1.0e6
		if at is Vector3:
			score += lot.global_position.distance_to(at as Vector3)
		if score < best_score:
			best = lot
			best_score = score
	return best


func _station_position(station_id: StringName) -> Variant:
	if station_position.is_valid():
		return station_position.call(station_id)
	var station: Station = Station.find(get_tree(), station_id)
	if station == null:
		return null
	return station.global_position


# Escucha las familias del modelo que esté usando (GameState puede rehacerlo).
func _connect_model() -> void:
	var production: ProductionModel = get_model()
	if production == _connected:
		return
	if _connected != null and _connected.family_added.is_connected(_on_family_added):
		_connected.family_added.disconnect(_on_family_added)
	_connected = production
	_placed.clear()
	if production != null:
		production.family_added.connect(_on_family_added)


func _on_family_added(station_id: StringName, _occupation: OccupationData, _origin: int) -> void:
	sync_station(station_id, true)
