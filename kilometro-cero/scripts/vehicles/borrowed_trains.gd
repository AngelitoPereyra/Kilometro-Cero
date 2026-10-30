class_name BorrowedTrains
extends Node
## Trenes prestados del Ferrocarril (tarea 62b.3, D128). Va un solo nodo "TrenesPrestados" en el
## mundo. Cuando se avisa una principal con viaje inaugural (MissionBoard.inaugural_started), arma
## el tren en una vía libre de la estación productora, ya cargado con la primera entrega (sale de
## la producción, no del stock del mercado), mirando hacia el camino de la estación que la pide.
## Aparece con humo (SmokePuff) y con un cartel arriba: "El maquinista está enfermo: ¿lo llevás
## vos?". Es un tren como el del jugador: se maneja desde su cabina y se entrega como siempre (F en
## el tablero, o las puertas del coche si lleva gente). Cumplida la principal, desaparece con humo
## apenas el jugador se baja, y el tren propio (`player_train` y lo que lleve enganchado) aparece con
## humo en una vía libre de esa estación: el viejo lo trae en la maqueta.
## El tren queda centrado frente al edificio de la estación (sobre el andén), no en la punta de la vía.
## Si en la estación productora no hay una vía libre que alcance, espera y vuelve a probar.
## Todavía no se guarda (tarea 65): una principal guardada en viaje inaugural vuelve a armar el tren.

## El tren prestado apareció en su estación.
signal train_appeared(mission_id: StringName, head: Vehicle)
## El tren prestado desapareció (entregado).
signal train_vanished(mission_id: StringName)
## El tren del jugador apareció en una estación.
signal player_train_moved(station_id: StringName)

const GROUP: StringName = &"borrowed_trains"
## Marca (meta) de los vehículos del tren prestado (tarea 62b.4): sus vagones no cuentan para las
## obras (StationGoods.own_trains_only, D127).
const META: StringName = &"borrowed_train"
const SIGN_TEXT: String = "Tren prestado del Ferrocarril\nEl maquinista está enfermo: ¿lo llevás vos?"
## En qué vías se pone un tren, en orden de preferencia.
const TRACK_ROLES: Array = [StationTrack.Role.MAIN, StationTrack.Role.SIDING, StationTrack.Role.FREIGHT]
## Metros libres entre la punta del tren y el final de la vía.
const END_MARGIN: float = 6.0
## Cada cuánto (s) vuelve a probar si hay vía libre.
const RETRY_TIME: float = 1.0
## Altura del cartel sobre la locomotora.
const SIGN_HEIGHT: float = 6.0
## Más cerca que esto (m) de la estación, el tren del jugador ya está ahí.
const ALREADY_THERE: float = 150.0

## La locomotora del jugador (el tren propio vuelve con ella).
@export var player_train: Vehicle

# mission id -> {"vehicles": Array[Vehicle], "sign": Label3D, "station": StringName,
# "source": StringName, "done": bool}
var _trips: Dictionary = {}
# Misiones esperando una vía libre para su tren.
var _pending: Array[StringName] = []
var _retry_left: float = RETRY_TIME
var _board: MissionBoard


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_board = GameState.missions
	_board.inaugural_started.connect(_on_inaugural_started)
	_board.mission_completed.connect(_on_mission_ended)
	_board.mission_removed.connect(_on_mission_ended)
	# Viajes inaugurales que ya estaban en curso (partida cargada).
	for mission: Mission in _board.get_missions():
		if mission.main and mission.is_active() and mission.inaugural:
			_pending.append(mission.id)


static func find_in(tree: SceneTree) -> BorrowedTrains:
	return tree.get_first_node_in_group(GROUP) as BorrowedTrains


func _process(delta: float) -> void:
	_retry_left -= delta
	if _retry_left <= 0.0:
		_retry_left = RETRY_TIME
		for mission_id: StringName in _pending.duplicate():
			if spawn_for(mission_id):
				_pending.erase(mission_id)
	for mission_id: StringName in _trips.keys():
		var trip: Dictionary = _trips[mission_id]
		var label: Variant = trip["sign"]
		if is_instance_valid(label):
			(label as Label3D).visible = not trip["done"] and not _player_in_cab_of(trip["vehicles"])
		if trip["done"] and not is_player_aboard(trip["vehicles"]):
			_finish(mission_id)


## Los vehículos del tren prestado de una misión (vacío si no hay).
func get_train(mission_id: StringName) -> Array[Vehicle]:
	var train: Array[Vehicle] = []
	if _trips.has(mission_id):
		for node: Variant in _trips[mission_id]["vehicles"]:
			if is_instance_valid(node):
				train.append(node as Vehicle)
	return train


func has_train(mission_id: StringName) -> bool:
	return not get_train(mission_id).is_empty()


func is_waiting(mission_id: StringName) -> bool:
	return _pending.has(mission_id)


## Los avisos de los trenes que esperan vía libre ("El tren prestado espera una vía libre en
## Azul"), para el HUD.
func get_waiting_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for mission_id: StringName in _pending:
		var mission: Mission = _board.get_mission(mission_id)
		if mission != null and mission.is_active() and mission.inaugural:
			lines.append("El tren prestado espera una vía libre en %s" % _board.station_name(_board.find_source(mission)))
	return lines


## Arma el tren prestado de una misión en viaje inaugural. True si ya está (o si ya no hace falta);
## false si todavía no hay red o vía libre.
func spawn_for(mission_id: StringName) -> bool:
	var mission: Mission = _board.get_mission(mission_id)
	if mission == null or not mission.is_active() or not mission.inaugural or has_train(mission_id):
		return true
	var network: RailNetwork = RailNetwork.find_in(get_tree())
	if network == null or not network.is_built():
		return false
	var source: StringName = _board.find_source(mission)
	var plan: Array[Dictionary] = plan_wagons(mission.get_remaining(), _wagon_kind, _wagon_capacity)
	var scenes: Array[PackedScene] = []
	var length: float = _loco_length()
	for entry: Dictionary in plan:
		var scene: PackedScene = load(_wagon_scene(entry["kind"])) as PackedScene
		scenes.append(scene)
		length += Vehicle.COUPLING_GAP + _wagon_length(entry["kind"])
	var spot: Array = find_free_track(network, source, length, mission.station_id)
	if spot.is_empty():
		return false
	var path: Path3D = spot[0]
	var faces_end: bool = spot[1]
	var loco := (load(AutoTrains.LOCOMOTIVE_SCENE) as PackedScene).instantiate() as Vehicle
	loco.name = "TrenPrestado_%s" % mission.item_id
	loco.reversed = not faces_end
	loco.set_meta(META, true)
	path.add_child(loco)
	var at: float = _head_at_station(path, source, loco.data.length, length, faces_end)
	loco.place_on(path, at, not faces_end)
	var vehicles: Array[Vehicle] = [loco]
	var dir: float = 1.0 if faces_end else -1.0
	var distance: float = 0.0
	var previous: float = loco.data.length
	for index: int in plan.size():
		var wagon := scenes[index].instantiate() as Wagon
		wagon.name = "%s_Vagon%d" % [loco.name, index + 1]
		wagon.reversed = loco.reversed
		wagon.set_meta(META, true)
		distance += Vehicle.coupling_distance(previous, wagon.data.length)
		previous = wagon.data.length
		path.add_child(wagon)
		wagon.progress = at - dir * distance
		if not loco.get_tail().couple(wagon):
			push_warning("BorrowedTrains: no se pudo enganchar el vagón %d del tren prestado." % (index + 1))
			wagon.queue_free()
			continue
		vehicles.append(wagon)
		# La primera entrega sale de la producción, no del stock del mercado.
		var item: ItemData = _board.find_item(plan[index]["item"])
		var box: StorageContainer = wagon.get_cargo()
		if item != null and box != null:
			var leftover: ItemStack = box.try_store(ItemStack.new(item, int(plan[index]["amount"])))
			if leftover != null:
				push_warning("BorrowedTrains: no entraron %d %s en el vagón %d." % [leftover.quantity, item.id, index + 1])
	var label := Label3D.new()
	label.name = "Cartel"
	label.text = "%s\n%s" % [SIGN_TEXT, _cargo_line(mission)]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.outline_size = 10
	label.pixel_size = 0.01
	label.position = Vector3(0.0, SIGN_HEIGHT, 0.0)
	loco.add_child(label)
	_trips[mission_id] = {"vehicles": vehicles, "sign": label, "station": mission.station_id, "source": source, "done": false}
	SmokePuff.at_vehicles(vehicles)
	print("BorrowedTrains: tren prestado en %s (%s)." % [source, _cargo_line(mission)])
	train_appeared.emit(mission_id, loco)
	return true


## Los vagones para una carga: [{"kind", "item", "amount"}], uno por cada `capacity_of(kind)`
## unidades de cada objeto. Lógica pura.
static func plan_wagons(cargo: Dictionary, kind_of: Callable, capacity_of: Callable) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	for item_id: StringName in cargo:
		var left: int = int(cargo[item_id])
		var kind: StringName = kind_of.call(item_id)
		var capacity: int = maxi(int(capacity_of.call(kind)), 1)
		while left > 0:
			plan.append({"kind": kind, "item": item_id, "amount": mini(left, capacity)})
			left -= capacity
	return plan


## Una vía libre de la estación donde entra un tren de `length` metros: [curva, mira hacia el
## final]. Mira hacia el camino a `toward` (vacío: hacia el final). Vacío si no hay.
func find_free_track(network: RailNetwork, station_id: StringName, length: float, toward: StringName = &"", ignore: Array = []) -> Array:
	for role: int in TRACK_ROLES:
		for station_track: StationTrack in network.get_station_tracks(station_id):
			if station_track.role != role or not station_track.enabled:
				continue
			var path: Path3D = station_track.get_track_path()
			if path == null or path.curve == null or not path.is_visible_in_tree():
				continue
			if path.curve.get_baked_length() < length + 2.0 * END_MARGIN or _has_vehicles(path, ignore):
				continue
			return [path, _faces_end(network, path, station_id, toward)]
	return []


## Si el jugador va en el tren (en la cabina o parado arriba).
func is_player_aboard(vehicles: Array) -> bool:
	for player: Player in _find_players():
		if vehicles.has(player.get_platform()) or _player_in_cab_of(vehicles, player):
			return true
	return false


## Trae el tren del jugador a una vía libre de la estación, con humo. False si no hace falta (ya
## está ahí, el jugador va arriba) o si no hay lugar.
func bring_player_train(station_id: StringName, toward: StringName = &"", ignore: Array = []) -> bool:
	if player_train == null or not is_instance_valid(player_train) or not player_train.is_inside_tree():
		return false
	var head: Vehicle = player_train.get_head()
	var train: Array[Vehicle] = head.get_train()
	if is_player_aboard(train):
		return false
	var station: Station = Station.find(get_tree(), station_id)
	if station != null and head.global_position.distance_to(station.global_position) < ALREADY_THERE:
		return false
	var network: RailNetwork = RailNetwork.find_in(get_tree())
	if network == null:
		return false
	var length: float = 0.0
	for vehicle: Vehicle in train:
		length += vehicle.data.length + Vehicle.COUPLING_GAP
	var spot: Array = find_free_track(network, station_id, length, toward, ignore)
	if spot.is_empty():
		push_warning("BorrowedTrains: no hay vía libre en %s para el tren del jugador." % station_id)
		return false
	var path: Path3D = spot[0]
	var faces_end: bool = spot[1]
	SmokePuff.at_vehicles(train)
	var cab: Cab = _find_cab(head)
	if cab != null:
		cab.set_notch(0)
	head.throttle = 0.0
	for vehicle: Vehicle in train:
		vehicle.speed = 0.0
	head.place_on(path, _head_at_station(path, station_id, head.data.length, length, faces_end), not faces_end)
	head.forget_route_ahead()
	SmokePuff.at_vehicles(train)
	player_train_moved.emit(station_id)
	return true


# Cumplida (o quitada) la principal: el tren se va apenas el jugador se baja.
func _on_mission_ended(mission: Mission) -> void:
	_pending.erase(mission.id)
	if _trips.has(mission.id):
		_trips[mission.id]["done"] = true


func _on_inaugural_started(mission: Mission) -> void:
	if not _pending.has(mission.id):
		_pending.append(mission.id)
	_retry_left = 0.0


func _finish(mission_id: StringName) -> void:
	var trip: Dictionary = _trips[mission_id]
	_trips.erase(mission_id)
	var gone: Array[Vehicle] = []
	for node: Variant in trip["vehicles"]:
		if is_instance_valid(node):
			gone.append(node as Vehicle)
	SmokePuff.at_vehicles(gone)
	for vehicle: Vehicle in gone:
		vehicle.queue_free()
	train_vanished.emit(mission_id)
	var mission: Mission = _board.get_mission(mission_id)
	if mission != null and mission.is_completed():
		bring_player_train(trip["station"], trip["source"], gone)


# Dónde va la cabeza para que el tren (de `train_length` metros) quede centrado frente a la
# estación, sobre el andén, sin pasarse de las puntas de la vía (END_MARGIN).
func _head_at_station(path: Path3D, station_id: StringName, loco_length: float, train_length: float, faces_end: bool) -> float:
	var length: float = path.curve.get_baked_length()
	var center: float = length * 0.5
	var station: Station = Station.find(get_tree(), station_id)
	if station != null:
		center = path.curve.get_closest_offset(path.to_local(station.global_position))
	var dir: float = 1.0 if faces_end else -1.0
	var head: float = center + dir * (train_length * 0.5 - loco_length * 0.5)
	var low: float = END_MARGIN + loco_length * 0.5
	var high: float = length - END_MARGIN - loco_length * 0.5
	if faces_end:
		low += train_length - loco_length
	else:
		high -= train_length - loco_length
	return clampf(head, low, maxf(low, high))


# Si la locomotora tiene que mirar hacia el final de la curva: el final queda más cerca del primer
# tramo del camino a `toward` (o de esa estación, si no hay camino).
func _faces_end(network: RailNetwork, path: Path3D, station_id: StringName, toward: StringName) -> bool:
	if toward == &"" or toward == station_id:
		return true
	var target: Variant = null
	var route: Array[StringName] = network.find_route(station_id, toward, true)
	if not route.is_empty():
		var tracks: Array[TrackSegment] = network.get_tracks(route[0])
		var line: Path3D = tracks[0].get_track_path() if not tracks.is_empty() else null
		if line != null and line.curve != null:
			target = line.to_global(line.curve.sample_baked(line.curve.get_baked_length() * 0.5))
	if target == null:
		var station: Station = Station.find(get_tree(), toward)
		if station == null:
			return true
		target = station.global_position
	var start: Vector3 = path.to_global(path.curve.sample_baked(0.0))
	var end: Vector3 = path.to_global(path.curve.sample_baked(path.curve.get_baked_length()))
	return end.distance_to(target) <= start.distance_to(target)


static func _has_vehicles(path: Path3D, ignore: Array) -> bool:
	for child: Node in path.get_children():
		var vehicle := child as Vehicle
		if vehicle != null and not vehicle.is_queued_for_deletion() and not ignore.has(vehicle):
			return true
	return false


func _player_in_cab_of(vehicles: Array, only: Player = null) -> bool:
	var players: Array[Player] = _find_players()
	if only != null:
		players = [only]
	for player: Player in players:
		var cab: Cab = player.get_cab()
		if cab != null and vehicles.has(Vehicle.find_owner_of(cab)):
			return true
	return false


func _find_players() -> Array[Player]:
	var players: Array[Player] = []
	var scene: Node = get_tree().current_scene
	if scene == null:
		return players
	for node: Node in scene.find_children("*", "CharacterBody3D", true, false):
		if node is Player:
			players.append(node)
	return players


static func _find_cab(loco: Vehicle) -> Cab:
	for node: Node in loco.find_children("*", "", true, false):
		if node is Cab:
			return node
	return null


func _cargo_line(mission: Mission) -> String:
	var parts: PackedStringArray = []
	var cargo: Dictionary[StringName, int] = mission.get_remaining()
	for item_id: StringName in cargo:
		parts.append("%d %s" % [cargo[item_id], _board.name_of(item_id)])
	return "Lleva %s a %s" % [", ".join(parts), _board.station_name(mission.station_id)]


# --- Vagones ---


func _wagon_kind(item_id: StringName) -> StringName:
	var autos: AutoTrains = AutoTrains.find_in(get_tree())
	if autos != null:
		return autos.kind_for(item_id)
	return AutoTrains.KIND_COACH if _board.is_passenger(item_id) else AutoTrains.KIND_FLATCAR


func _wagon_capacity(kind: StringName) -> int:
	var data: WagonData = _wagon_data(kind)
	return data.capacity if data != null else 10


func _wagon_length(kind: StringName) -> float:
	var data: WagonData = _wagon_data(kind)
	return data.length if data != null else 10.0


static func _wagon_data(kind: StringName) -> WagonData:
	match kind:
		AutoTrains.KIND_COACH:
			return load(AutoTrains.COACH_DATA) as WagonData
		AutoTrains.KIND_BOXCAR:
			return load(AutoTrains.BOXCAR_DATA) as WagonData
	return load(AutoTrains.FLATCAR_DATA) as WagonData


static func _wagon_scene(kind: StringName) -> String:
	match kind:
		AutoTrains.KIND_COACH:
			return AutoTrains.COACH_SCENE
		AutoTrains.KIND_BOXCAR:
			return AutoTrains.BOXCAR_SCENE
	return AutoTrains.FLATCAR_SCENE


static func _loco_length() -> float:
	var data: VehicleData = load(AutoTrains.LOCOMOTIVE_DATA) as VehicleData
	return data.length if data != null else 10.0
