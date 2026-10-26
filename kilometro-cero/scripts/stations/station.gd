@tool
class_name Station
extends Node3D
## Una estación en el mundo (D31, tarea 56): raíz de las plantillas scenes/stations/
## (town_station.tscn, city_station.tscn y freight_station.tscn), configurada por un
## StationData. Su id es el nombre de estación que usan las vías (TrackSegment.from_station
## y to_station), así se ubica en el RailNetwork.
## Hijos que usa (todos opcionales):
## - "Cartel" (Label3D): muestra el nombre.
## - "Niveles": sus hijos "Nivel1", "Nivel2"... se ven desde ese nivel (D79; la tarea 60
##   suma gente, luces y sonido).
## - "Zona" (Area3D): avisa qué trenes y si el jugador están en la estación, y cuándo un tren
##   se detiene en ella (para entregas, misiones y trenes automáticos).
## Es @tool para ver el nombre y los niveles en el editor al cambiar `data` o `level`.

## Cambió el nivel.
signal level_changed(level: int)
## Entró o salió de la zona un vehículo (cualquiera del tren).
signal vehicle_entered(vehicle: Vehicle)
signal vehicle_exited(vehicle: Vehicle)
## El jugador entró o salió de la zona.
signal player_entered
signal player_exited
## Un tren se detuvo con algún vehículo en la zona (una vez por parada). Se pasa la cabeza.
signal train_stopped(head: Vehicle)

const GROUP: StringName = &"stations"
const SIGN_PATH: NodePath = ^"Cartel"
const LEVELS_PATH: NodePath = ^"Niveles"
const ZONE_PATH: NodePath = ^"Zona"
## Por debajo de esta velocidad (m/s) un tren cuenta como detenido.
const STOP_SPEED: float = 0.1

@export var data: StationData:
	set(value):
		data = value
		if is_node_ready():
			_refresh()
## Nivel de crecimiento (1 a data.get_max_level()). En el juego lo maneja el modelo de
## producción (GameState.production, tarea 57) con EventBus.station_level_changed; acá sirve
## para el nivel inicial de una partida nueva y para ver los niveles en el editor.
@export_range(1, 10) var level: int = 1:
	get:
		return _level
	set(value):
		if is_node_ready():
			set_level(value)
		else:
			_level = value

var _level: int = 1
var _vehicles: Array[Vehicle] = []
var _player_inside: bool = false
var _player: Player
## Cabezas de los trenes que ya avisaron que se detuvieron (hasta que vuelvan a moverse).
var _stopped_heads: Array[Vehicle] = []


## La estación con ese id en la escena, o null.
static func find(tree: SceneTree, station_id: StringName) -> Station:
	for node: Node in tree.get_nodes_in_group(GROUP):
		var station := node as Station
		if station != null and station.get_station_id() == station_id:
			return station
	return null


## Lógica pura: el nivel que indica el nombre de un nodo de "Niveles" ("Nivel2" -> 2; sin
## número, 1).
static func level_of_node(node_name: String) -> int:
	var digits: String = ""
	for character: String in node_name:
		if character >= "0" and character <= "9":
			digits += character
	return maxi(1, digits.to_int()) if not digits.is_empty() else 1


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_refresh()
	if Engine.is_editor_hint():
		return
	EventBus.station_level_changed.connect(_on_station_level_changed)
	var zone: Area3D = get_zone()
	if zone != null:
		zone.body_entered.connect(_on_body_entered)
		zone.body_exited.connect(_on_body_exited)
	if data == null:
		push_warning("Station %s: no tiene StationData." % name)
	else:
		for problem: String in data.validate():
			push_warning("Station %s: %s." % [name, problem])
		# Si el modelo ya la conocía (escena recargada, partida guardada) manda su nivel.
		_apply_level(GameState.production.add_station(data, _level))
		# Su mercado: los objetos que conoce y, si es nueva, el stock lleno (tarea 59).
		GameState.economy.add_station(data)
		# Nace la principal de lo que pide (tarea 58).
		GameState.missions.refresh()
	# Diferido: la red arma el grafo en su primer cuadro.
	_check_network.call_deferred()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_check_stops()


## El id del StationData (&"" sin datos).
func get_station_id() -> StringName:
	return data.id if data != null else &""


func get_display_name() -> String:
	return data.display_name if data != null else String(name)


## Cambia el nivel (limitado a lo que permiten los datos), muestra sus nodos y lo avisa
## también por EventBus. Devuelve false si quedó igual.
func set_level(value: int) -> bool:
	if not _apply_level(value):
		return false
	if not Engine.is_editor_hint():
		EventBus.station_level_changed.emit(get_station_id(), level)
	return true


func get_max_level() -> int:
	return data.get_max_level() if data != null else 1


func can_grow() -> bool:
	return data != null and data.can_grow(level)


## Producción por día en el nivel actual (id -> unidades).
func get_production() -> Dictionary[StringName, int]:
	return data.get_production(level) if data != null else {}


## Todo lo que consume por día en el nivel actual.
func get_consumption() -> Dictionary[StringName, int]:
	return data.get_consumption(level) if data != null else {}


## Lo que le falta cubrir por día para crecer al nivel siguiente.
func get_growth_needs() -> Dictionary[StringName, int]:
	return data.get_growth_needs(level) if data != null else {}


## Lo que le llega por día con los flujos de hoy (del modelo de producción).
func get_supply() -> Dictionary[StringName, int]:
	return GameState.production.get_supply(get_station_id())


## Lo que le falta por día para cubrir todo su consumo (vacío si está cubierta).
func get_missing() -> Dictionary[StringName, int]:
	return GameState.production.get_missing(get_station_id())


## Días cubiertos juntados para crecer, y cuántos hacen falta (0 si ya no crece).
func get_growth_progress() -> int:
	return GameState.production.get_growth_progress(get_station_id())


func get_days_to_grow() -> int:
	return GameState.production.get_days_to_grow(get_station_id())


func has_market() -> bool:
	return data != null and data.has_market(level)


func has_workshop() -> bool:
	return data != null and data.has_workshop(level)


func get_zone() -> Area3D:
	return get_node_or_null(ZONE_PATH) as Area3D


func get_network() -> RailNetwork:
	return RailNetwork.find_in(get_tree()) if is_inside_tree() else null


## Si alguna vía de la red llega a esta estación.
func is_on_network() -> bool:
	var network: RailNetwork = get_network()
	return network != null and network.has_station(get_station_id())


## Los tramos que salen de la estación (vacío sin red).
func get_segments() -> Array[StringName]:
	var network: RailNetwork = get_network()
	if network == null or not network.has_station(get_station_id()):
		return []
	return network.get_segments_at(get_station_id())


## Los vehículos que están ahora en la zona.
func get_vehicles_present() -> Array[Vehicle]:
	_forget_freed()
	return _vehicles.duplicate()


## Las cabezas de los trenes con algún vehículo en la zona (una por tren).
func get_trains_present() -> Array[Vehicle]:
	var heads: Array[Vehicle] = []
	for vehicle: Vehicle in get_vehicles_present():
		var head: Vehicle = vehicle.get_head()
		if not heads.has(head):
			heads.append(head)
	return heads


## Si hay un tren detenido en la estación.
func has_stopped_train() -> bool:
	return not get_stopped_trains().is_empty()


## Las cabezas de los trenes detenidos en la estación (tarea 58: el tablero entrega su carga).
func get_stopped_trains() -> Array[Vehicle]:
	var heads: Array[Vehicle] = []
	for head: Vehicle in get_trains_present():
		if absf(head.speed) < STOP_SPEED:
			heads.append(head)
	return heads


func is_player_present() -> bool:
	return _player_inside


## El jugador si está en la zona, o null (tarea 58: el tablero entrega de su mochila).
func get_present_player() -> Player:
	return _player if _player_inside and is_instance_valid(_player) else null


## "Pueblo (pueblo, nivel 1 de 3)".
func describe() -> String:
	if data == null:
		return "%s (sin datos)" % name
	return "%s (%s, nivel %d de %d)" % [data.display_name, StationData.type_name(data.type), level, get_max_level()]


# Lee solo propiedades de los datos, sin llamar a sus métodos: al abrir el editor, los .tres
# pueden cargarse antes que su script y mientras tanto son "placeholder" sin métodos.
func _clamped(value: int) -> int:
	if data == null:
		return maxi(1, value)
	return clampi(value, 1, maxi(1, data.levels.size()))


# Pone el nivel y sus nodos, sin avisar por EventBus. True si cambió.
func _apply_level(value: int) -> bool:
	var clamped: int = _clamped(value)
	if clamped == _level:
		return false
	_level = clamped
	_update_level_nodes()
	level_changed.emit(level)
	return true


func _refresh() -> void:
	_level = _clamped(_level)
	var sign_label := get_node_or_null(SIGN_PATH) as Label3D
	if sign_label != null:
		sign_label.text = get_display_name()
	_update_level_nodes()


func _update_level_nodes() -> void:
	var levels_node: Node = get_node_or_null(LEVELS_PATH)
	if levels_node == null:
		return
	for child: Node in levels_node.get_children():
		var visual := child as Node3D
		if visual != null:
			visual.visible = level_of_node(child.name) <= _level


func _check_network() -> void:
	if data != null and get_network() != null and not is_on_network():
		push_warning("Station %s: ninguna vía llega a '%s' (revisar from_station y to_station)." % [name, get_station_id()])


func _on_station_level_changed(station_id: StringName, new_level: int) -> void:
	if station_id == get_station_id():
		_apply_level(new_level)


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player = body
		if not _player_inside:
			_player_inside = true
			player_entered.emit()
			EventBus.player_station_changed.emit(get_station_id())
		return
	var vehicle: Vehicle = Vehicle.find_owner_of(body)
	if vehicle != null and not _vehicles.has(vehicle):
		_vehicles.append(vehicle)
		vehicle_entered.emit(vehicle)


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		if _player_inside:
			_player_inside = false
			player_exited.emit()
			EventBus.player_station_changed.emit(&"")
		return
	var vehicle: Vehicle = Vehicle.find_owner_of(body)
	if vehicle != null and _vehicles.has(vehicle):
		_vehicles.erase(vehicle)
		vehicle_exited.emit(vehicle)


func _forget_freed() -> void:
	for index: int in range(_vehicles.size() - 1, -1, -1):
		if not is_instance_valid(_vehicles[index]):
			_vehicles.remove_at(index)


# Avisa una vez por parada; un tren que vuelve a moverse puede avisar de nuevo.
func _check_stops() -> void:
	for index: int in range(_stopped_heads.size() - 1, -1, -1):
		var old: Vehicle = _stopped_heads[index]
		if not is_instance_valid(old) or absf(old.speed) >= STOP_SPEED or not get_trains_present().has(old):
			_stopped_heads.remove_at(index)
	for head: Vehicle in get_trains_present():
		if absf(head.speed) < STOP_SPEED and not _stopped_heads.has(head):
			_stopped_heads.append(head)
			train_stopped.emit(head)
			EventBus.train_stopped_at_station.emit(get_station_id(), head)
