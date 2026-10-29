class_name LoadingBay
extends Node3D
## Punto de carga de una estación (tarea 62.9a, D125): va junto a su bahía de carga (una vía de
## estación con rol BAY, lejos de la principal; los automáticos no la usan). Lo que se compra en
## el mercado de la estación se carga de a poco en los vagones del jugador estacionados en la
## bahía, y lo que se vende se descarga de ellos (LoadingQueue: media hora de juego por vagón
## lleno). Lo comprado que todavía no entró espera acá aunque el tren se vaya.
## La bahía va en las ciudades o pueblos de la línea principal con talleres (Batmi, 2026-10-29),
## generada por StationTracks (bay_offsets). En una estación de carga va al final de un ramal que
## sale de la principal y se abre en dos bahías, una para el jugador y otra para los automáticos;
## esas vías se ponen a mano en la escena (Path3D hijos de la Station con su StationTrack "Via").
## Hijo directo de la Station. Su Label3D "Texto" dice qué vagones hay y cómo va la carga.

## Se cargaron (o descargaron) `amount` unidades en los vagones de la bahía.
signal loaded(item_id: StringName, amount: int)
signal unloaded(item_id: StringName, amount: int)

const TEXT_PATH: NodePath = ^"Texto"
const REFRESH_TIME: float = 0.5
## Unidades que se piden de más para medir el lugar libre.
const ROOM_PROBE: int = 9999

## El nombre de la curva de la bahía (Path3D) dentro de la Station: la generada por Vias o una
## puesta a mano. Vacío: la primera bahía de Vias.
@export var track_name: StringName = &"Bahia1"

var queue := LoadingQueue.new()

var _station: Station
var _label: Label3D
var _timer: float = 0.0
# La curva de la bahía, una vez encontrada (StationTracks la arma en su _ready).
var _found_path: Path3D


func _ready() -> void:
	_station = get_parent() as Station
	_label = get_node_or_null(TEXT_PATH) as Label3D
	if _station == null:
		push_warning("LoadingBay %s: no es hijo de una Station." % name)
	EventBus.time_advanced.connect(_on_time_advanced)
	update_text()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH_TIME
		update_text()


func get_station() -> Station:
	return _station


## La vía de la bahía, o null (la estación no tiene).
func get_track() -> StationTrack:
	if _station == null:
		return null
	if track_name != &"":
		if not is_instance_valid(_found_path) or not _found_path.is_inside_tree():
			_found_path = _station.find_child(String(track_name), true, false) as Path3D
		if _found_path == null:
			return null
		return (RailNetwork.track_of(_found_path) as StationTrack)
	var vias := _station.get_node_or_null(^"Vias") as StationTracks
	if vias == null:
		return null
	for station_track: StationTrack in vias.get_tracks():
		if station_track.role == StationTrack.Role.BAY:
			return station_track
	return null


## Si la bahía existe y está habilitada (si no, el mercado trabaja como antes, con el tren
## detenido en el andén).
func is_usable() -> bool:
	var station_track: StationTrack = get_track()
	return station_track != null and station_track.enabled


## Los vagones del jugador detenidos sobre la bahía (con carga).
func get_wagons() -> Array[Wagon]:
	var wagons: Array[Wagon] = []
	var station_track: StationTrack = get_track()
	if station_track == null or not station_track.enabled:
		return wagons
	for child: Node in station_track.get_track_path().get_children():
		var wagon := child as Wagon
		if wagon == null or wagon.automatic or wagon.get_cargo() == null:
			continue
		var head: Vehicle = wagon.get_head()
		if head != null and absf(head.speed) >= Station.STOP_SPEED:
			continue
		wagons.append(wagon)
	return wagons


func get_cargos() -> Array[StorageContainer]:
	var cargos: Array[StorageContainer] = []
	for wagon: Wagon in get_wagons():
		cargos.append(wagon.get_cargo())
	return cargos


func has_wagons() -> bool:
	return not get_wagons().is_empty()


## Cuántas unidades de `item` se pueden pedir todavía (lugar libre menos lo que ya espera).
func room_for(item: ItemData) -> int:
	if item == null:
		return 0
	var probe := ItemStack.new(item, ROOM_PROBE)
	var room: int = 0
	for cargo: StorageContainer in get_cargos():
		room += cargo.can_store_amount(probe)
	return maxi(0, room - queue.pending_load_total())


## Pide cargar `amount` unidades (ya pagas). Se cargan con el tiempo.
func order_load(item: ItemData, amount: int) -> void:
	queue.add_load(item, amount)
	update_text()


## Lo que hay en los vagones de la bahía y todavía no se pidió descargar: id -> unidades.
func get_available() -> Dictionary[StringName, int]:
	var available: Dictionary[StringName, int] = {}
	for cargo: StorageContainer in get_cargos():
		for index: int in cargo.get_stack_count():
			var stack: ItemStack = cargo.peek(index)
			available[stack.item.id] = available.get(stack.item.id, 0) + stack.quantity
	for item_id: StringName in available.keys():
		available[item_id] -= queue.pending_unload_of(item_id)
		if available[item_id] <= 0:
			available.erase(item_id)
	return available


func count_of(item_id: StringName) -> int:
	return get_available().get(item_id, 0)


## El ItemData de algo que hay en los vagones de la bahía (null si no hay).
func find_item(item_id: StringName) -> ItemData:
	for cargo: StorageContainer in get_cargos():
		for index: int in cargo.get_stack_count():
			var stack: ItemStack = cargo.peek(index)
			if stack.item.id == item_id:
				return stack.item
	return null


## Pide descargar hasta `amount` unidades. Devuelve cuántas se van a descargar.
func order_unload(item_id: StringName, amount: int) -> int:
	var accepted: int = mini(amount, count_of(item_id))
	queue.add_unload(item_id, accepted)
	update_text()
	return accepted


## Avanza la carga `hours` horas de juego (lo llama el reloj; también sirve para pruebas).
func advance(hours: float) -> void:
	if not queue.has_work() or not is_usable():
		return
	var done: Dictionary = queue.work(get_cargos(), hours)
	var done_unloaded: Dictionary = done["unloaded"]
	var done_loaded: Dictionary = done["loaded"]
	for item_id: StringName in done_unloaded:
		unloaded.emit(item_id, done_unloaded[item_id])
	for item_id: StringName in done_loaded:
		loaded.emit(item_id, done_loaded[item_id])
	if not done_unloaded.is_empty() or not done_loaded.is_empty():
		update_text()


## Escribe el cartel en el Label3D "Texto" (también lo devuelve, para pruebas).
func update_text() -> String:
	var text: String = build_text()
	if _label != null:
		_label.text = text
	return text


func build_text() -> String:
	if not is_usable():
		return "Punto de carga (sin bahía)"
	var lines: PackedStringArray = ["Punto de carga"]
	var cargos: Array[StorageContainer] = get_cargos()
	if cargos.is_empty():
		lines.append("Estacioná tus vagones en la bahía")
	else:
		var total: int = 0
		var capacity: int = 0
		for cargo: StorageContainer in cargos:
			total += cargo.get_total()
			capacity += cargo.capacity
		lines.append("%d %s en la bahía · %d de %d" % [cargos.size(), "vagón" if cargos.size() == 1 else "vagones", total, capacity])
	var unloads: Dictionary[StringName, int] = queue.get_unloads()
	for item_id: StringName in unloads:
		lines.append("Descargando %d %s" % [unloads[item_id], _name_of(item_id)])
	var loads: Dictionary[StringName, int] = queue.get_loads()
	for item_id: StringName in loads:
		lines.append("%s %d %s" % ["Cargando" if not cargos.is_empty() else "Espera", loads[item_id], _name_of(item_id)])
	if queue.has_work() and not cargos.is_empty():
		lines.append("Faltan unos %d min" % ceili(queue.hours_left(cargos) * 60.0))
	return "\n".join(lines)


func _name_of(item_id: StringName) -> String:
	var item: ItemData = queue.get_item(item_id)
	if item == null:
		item = find_item(item_id)
	if item != null and item.display_name != "":
		return item.display_name
	return GameState.economy.name_of(item_id) if GameState.economy != null else String(item_id)


func _on_time_advanced(hours: float) -> void:
	advance(hours)
