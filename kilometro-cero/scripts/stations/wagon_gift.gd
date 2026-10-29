class_name WagonGift
extends Node3D
## Regalo de un vagón (tarea 62.4, D120, idea de Batmi): una estación le da al jugador el vagón
## (cargado o vacío) que necesita para la tarea que sigue. En el Hito A (tarea 62.5, D121) los
## vagones salen vacíos y los carga el jugador: al despejar o_a, una plataforma en Azul para los
## troncos del monte; cumplida la de los troncos, otra en Sierras Bayas para la piedra; cumplida
## la de la piedra, un vagón cerrado en Olavarría para el cemento.
## Cuándo: al abrirse `open_segment` (despejado el último obstáculo, después de haberlo visto
## cortado) o al cumplirse la principal de `mission_station` que pide `mission_item`; con las dos,
## cuando pasan las dos. Con `next_day`, recién al empezar el día siguiente ("al descargar y pasar
## la noche"). Una sola vez por partida (el guardado llega con la tarea 65).
## El vagón sale ya cargado en la vía más cercana a este nodo, cuando ahí hay lugar, y se engancha
## como cualquier vagón suelto, tocándolo marcha atrás con la cola del tren. Hijo opcional "Texto"
## (Label3D) que avisa mientras el vagón espera que lo enganchen.

## El vagón salió a la vía.
signal given(wagon: Wagon)

const GROUP: StringName = &"wagon_gifts"
const TEXT_PATH: NodePath = ^"Texto"
## Cada cuánto (s) revisa si ya toca el regalo; la primera vez espera un poco más, a que los
## obstáculos corten sus tramos.
const REFRESH_TIME: float = 0.5
const FIRST_WAIT: float = 1.0
## Metros libres que pide entre el vagón y otro vehículo de la misma vía.
const CLEARANCE: float = 1.0

## La escena del vagón (scenes/vehicles/flatcar.tscn).
@export var wagon_scene: PackedScene
## Lo que lleva cargado.
@export var cargo: Array[ItemAmount] = []
## Se regala cuando este tramo queda abierto (vacío: no mira tramos).
@export var open_segment: StringName
## Se regala cuando se cumple la principal de esta estación que pide `mission_item` (vacío: no
## mira misiones; `mission_item` vacío: cualquier principal de la estación).
@export var mission_station: StringName
@export var mission_item: StringName
## Espera al día siguiente de cumplida la condición.
@export var next_day: bool = false
## Qué decir del vagón vacío ("una plataforma"), si no lleva carga.
@export var wagon_name: String = "un vagón"
## Lo que dice el aviso debajo del regalo ("Cargala con troncos del monte").
@export var hint: String = ""
## Quién regala, para los textos ("Azul").
@export var giver_name: String = ""

var _label: Label3D
var _timer: float = FIRST_WAIT
var _seen_cut: bool = false
# Día en que se cumplió la condición, o -1.
var _ready_day: int = -1
var _given: bool = false
var _wagon: Wagon


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_label = get_node_or_null(TEXT_PATH) as Label3D
	if _label != null:
		_label.visible = false


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH_TIME
	refresh()


## Si ya se regaló.
func is_given() -> bool:
	return _given


## El vagón regalado (null si todavía no, o si ya no existe).
func get_wagon() -> Wagon:
	return _wagon if is_instance_valid(_wagon) else null


## Revisa la condición, saca el vagón si ya toca y escribe el aviso.
func refresh() -> void:
	if not _given:
		if _ready_day < 0 and is_triggered():
			_ready_day = GameState.clock.current_day
		if _ready_day >= 0 and (not next_day or GameState.clock.current_day > _ready_day):
			place_wagon()
	_update_label()


## Si ya se cumplió lo que pide (sin contar la espera al día siguiente).
func is_triggered() -> bool:
	if open_segment == &"" and mission_station == &"":
		return false
	if open_segment != &"":
		var network: RailNetwork = RailNetwork.find_in(get_tree()) if is_inside_tree() else null
		if network == null or not network.has_segment(open_segment):
			return false
		if network.is_cut(open_segment):
			_seen_cut = true
			return false
		if not _seen_cut:
			return false
	if mission_station != &"" and not _mission_done():
		return false
	return true


## Lo que dice el aviso: "Regalo de Azul: 20 troncos", o "Regalo de Azul: una plataforma" vacío.
func describe() -> String:
	var parts: PackedStringArray = []
	for entry: ItemAmount in cargo:
		if entry != null and entry.item != null:
			parts.append("%d %s" % [entry.amount, entry.item.cargo_name if entry.item.cargo_name != "" else entry.item.display_name])
	return "Regalo de %s: %s" % [giver_name if giver_name != "" else "la estación", ", ".join(parts) if not parts.is_empty() else wagon_name]


## Pone el vagón cargado en la vía más cercana si hay lugar. Devuelve el vagón, o null si todavía no.
func place_wagon() -> Wagon:
	if _given:
		return get_wagon()
	if wagon_scene == null:
		push_warning("WagonGift %s: no tiene wagon_scene." % name)
		_given = true
		return null
	var path: Path3D = _find_track()
	if path == null:
		push_warning("WagonGift %s: no hay vía cerca." % name)
		return null
	var wagon := wagon_scene.instantiate() as Wagon
	if wagon == null:
		push_error("WagonGift %s: wagon_scene no es un Wagon." % name)
		_given = true
		return null
	var offset: float = path.curve.get_closest_offset(path.to_local(global_position))
	if not _is_track_free(path, offset, wagon.data.length if wagon.data != null else 10.0):
		wagon.free()
		return null
	wagon.name = "Regalo%s" % name
	path.add_child(wagon)
	wagon.place_on(path, offset)
	var box: StorageContainer = wagon.get_cargo()
	for entry: ItemAmount in cargo:
		if box != null and entry != null and entry.item != null and entry.amount > 0:
			box.try_store(ItemStack.new(entry.item, entry.amount))
	_wagon = wagon
	_given = true
	var visual := wagon.get_node_or_null(^"Visual") as Node3D
	if visual != null:
		GrowthCelebration.pop(visual)
	# Lo pone el viejo en la maqueta (tarea 62b.3): con humo.
	SmokePuff.at_vehicles([wagon])
	print("WagonGift: %s (en %s)." % [describe(), path.name])
	given.emit(wagon)
	return wagon


func _mission_done() -> bool:
	for mission: Mission in GameState.missions.get_missions():
		if mission.main and mission.station_id == mission_station and (mission_item == &"" or mission.item_id == mission_item) and mission.is_completed():
			return true
	return false


# La vía (Path3D con TrackSegment) más cercana a este nodo.
func _find_track() -> Path3D:
	var best: Path3D = null
	var best_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group(TrackSegment.GROUP):
		var track := node as TrackSegment
		var path: Path3D = track.get_track_path() if track != null else null
		if path == null or path.curve == null or not path.is_visible_in_tree():
			continue
		var distance: float = path.to_global(path.curve.get_closest_point(path.to_local(global_position))).distance_to(global_position)
		if distance < best_distance:
			best = path
			best_distance = distance
	return best


func _is_track_free(path: Path3D, offset: float, length: float) -> bool:
	for node: Node in get_tree().get_nodes_in_group(Vehicle.GROUP):
		var vehicle := node as Vehicle
		if vehicle == null or vehicle.get_parent() != path or vehicle.data == null:
			continue
		if absf(vehicle.progress - offset) < (vehicle.data.length + length) * 0.5 + CLEARANCE:
			return false
	return true


func _update_label() -> void:
	if _label == null:
		return
	var wagon: Wagon = get_wagon()
	_label.visible = wagon != null and wagon.front == null and wagon.rear == null
	if _label.visible:
		_label.global_position = wagon.global_position + Vector3(0.0, 4.0, 0.0)
		_label.text = describe() + ("\n" + hint if hint != "" else "") + "\nEngánchalo tocándolo marcha atrás"
