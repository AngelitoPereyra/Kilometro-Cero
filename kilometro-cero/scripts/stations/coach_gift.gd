class_name CoachGift
extends Interactable
## Taller de una ciudad con el coche de pasajeros que regala (D103, tarea 60b): nodo "Taller"
## de city_station.tscn. Cuando nace el primer pedido de pasajeros, el coche aparece en
## reparación en el taller de la ciudad que lo regala (PassengerTraffic.gift_station): no está
## listo desde el principio. F entrega los materiales que pide `repair_cost` (de los vagones de
## los trenes detenidos, la mano y la mochila, como el tablero). Reparado, el coche sale a la vía
## en el punto de la vía más cercano a "Salida" (cuando ese tramo de vía está libre) y se engancha
## como cualquier vagón, tocándolo marcha atrás con la cola del tren. Una sola vez por partida.
## Hijos: "Texto" (Label3D), "CocheEnReparacion" (lo que se ve mientras se arregla) y "Salida"
## (Marker3D sobre la vía).

## El coche salió a la vía.
signal coach_placed(coach: PassengerCoach)
## Se entregaron materiales: id de objeto -> unidades.
signal repaired(amounts: Dictionary[StringName, int])

const TEXT_PATH: NodePath = ^"Texto"
const MODEL_PATH: NodePath = ^"CocheEnReparacion"
const EXIT_PATH: NodePath = ^"Salida"
## Cada cuánto (s) revisa el estado y escribe el texto.
const REFRESH_TIME: float = 0.5
## Metros libres que pide entre el coche y otro vehículo de la misma vía para sacarlo.
const CLEARANCE: float = 1.0

## La escena del coche (scenes/vehicles/passenger_coach.tscn).
@export var coach_scene: PackedScene
## Materiales para dejarlo andando (provisorio: troncos para los asientos; en la 62, rieles y
## cueros, D102).
@export var repair_cost: Array[ItemAmount] = []

var _station: Station
var _label: Label3D
var _model: Node3D
var _exit: Node3D
var _timer: float = 0.0
var _message: String = ""
var _coach: PassengerCoach


func _ready() -> void:
	_station = _find_station()
	_label = get_node_or_null(TEXT_PATH) as Label3D
	_model = get_node_or_null(MODEL_PATH) as Node3D
	_exit = get_node_or_null(EXIT_PATH) as Node3D
	if Engine.is_editor_hint():
		return
	if _station == null:
		push_warning("CoachGift %s: no está dentro de una Station." % name)
	refresh()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH_TIME
		refresh()


func get_station() -> Station:
	return _station


## Si esta ciudad es la que regala el coche.
func is_gift_here() -> bool:
	return _station != null and GameState.passengers.gift_station == _station.get_station_id()


func get_state() -> PassengerTraffic.CoachState:
	return GameState.passengers.coach_state if is_gift_here() else PassengerTraffic.CoachState.NONE


## Lo que cuesta repararlo: id de objeto -> unidades.
func get_cost() -> Dictionary[StringName, int]:
	return ItemAmount.sum_by_id(repair_cost)


func get_remaining() -> Dictionary[StringName, int]:
	return GameState.passengers.get_repair_remaining(get_cost())


## Lo que F entregaría ahora (lo que falta y está al alcance).
func get_repair_plan(player: Player = null) -> Dictionary[StringName, int]:
	var plan: Dictionary[StringName, int] = {}
	if get_state() != PassengerTraffic.CoachState.REPAIRING:
		return plan
	var available: Dictionary[StringName, int] = StationGoods.new(_station, player).get_available()
	var remaining: Dictionary[StringName, int] = get_remaining()
	for item_id: StringName in remaining:
		var amount: int = mini(remaining[item_id], available.get(item_id, 0))
		if amount > 0:
			plan[item_id] = amount
	return plan


func can_interact(player: Player) -> bool:
	return super.can_interact(player) and get_state() == PassengerTraffic.CoachState.REPAIRING


func get_prompt() -> String:
	var plan: Dictionary[StringName, int] = get_repair_plan()
	return "Entregar " + _amounts_text(plan) + " para el coche" if not plan.is_empty() else "Mirar el coche en reparación"


## Entrega materiales para la reparación. Devuelve lo entregado.
func repair(player: Player = null) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	var plan: Dictionary[StringName, int] = get_repair_plan(player)
	if plan.is_empty():
		return result
	var goods := StationGoods.new(_station, player)
	for item_id: StringName in plan:
		var taken: int = goods.take(item_id, plan[item_id])
		var accepted: int = GameState.passengers.add_repair(item_id, taken, get_cost())
		if accepted > 0:
			result[item_id] = accepted
	if not result.is_empty():
		_message = "Entregaste " + _amounts_text(result)
		repaired.emit(result)
	refresh()
	return result


## Revisa el estado: ofrece el coche si hace falta, lo saca a la vía si está listo y escribe
## el texto.
func refresh() -> void:
	if _station == null:
		return
	GameState.passengers.check_offer()
	var state: PassengerTraffic.CoachState = get_state()
	if state == PassengerTraffic.CoachState.READY:
		place_coach()
		state = get_state()
	if _model != null:
		_model.visible = state == PassengerTraffic.CoachState.REPAIRING or state == PassengerTraffic.CoachState.READY
	if _label != null:
		_label.text = build_text()


func build_text() -> String:
	match get_state():
		PassengerTraffic.CoachState.REPAIRING:
			var lines: PackedStringArray = ["Taller: coche de pasajeros (regalo de la ciudad)", "Para dejarlo andando faltan " + _amounts_text(get_remaining())]
			var plan: Dictionary[StringName, int] = get_repair_plan()
			if not plan.is_empty():
				lines.append("F: entregar " + _amounts_text(plan))
			if not _message.is_empty():
				lines.append(_message)
			return "\n".join(lines)
		PassengerTraffic.CoachState.READY:
			return "Taller: coche listo\nEsperando la vía libre para sacarlo"
		PassengerTraffic.CoachState.DELIVERED:
			return "Taller" if _coach == null else "Taller: el coche está en la vía\nEngánchalo tocándolo marcha atrás"
	return "Taller"


## Si el coche está listo y la vía al lado de la salida está libre, lo pone en la vía.
## Devuelve el coche, o null si todavía no se pudo.
func place_coach() -> PassengerCoach:
	if get_state() != PassengerTraffic.CoachState.READY or coach_scene == null or _exit == null:
		return null
	var path: Path3D = find_exit_track()
	if path == null:
		push_warning("CoachGift %s: no hay vía cerca de la salida." % name)
		return null
	var offset: float = path.curve.get_closest_offset(path.to_local(_exit.global_position))
	var coach := coach_scene.instantiate() as PassengerCoach
	if coach == null:
		push_error("CoachGift %s: coach_scene no es un PassengerCoach." % name)
		return null
	if not is_track_free(path, offset, coach.data.length if coach.data != null else 10.0):
		coach.free()
		return null
	path.add_child(coach)
	coach.place_on(path, offset)
	_coach = coach
	GameState.passengers.mark_coach_delivered()
	var visual := coach.get_node_or_null(^"Visual") as Node3D
	if visual != null:
		GrowthCelebration.pop(visual)
	coach_placed.emit(coach)
	return coach


## El coche que sacó a la vía (null si todavía no).
func get_coach() -> PassengerCoach:
	return _coach if is_instance_valid(_coach) else null


## La vía (Path3D con TrackSegment) más cercana a la salida.
func find_exit_track() -> Path3D:
	var best: Path3D = null
	var best_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group(TrackSegment.GROUP):
		var path: Path3D = (node as TrackSegment).get_track_path()
		if path == null or path.curve == null:
			continue
		var local: Vector3 = path.to_local(_exit.global_position)
		var distance: float = path.to_global(path.curve.get_closest_point(local)).distance_to(_exit.global_position)
		if distance < best_distance:
			best = path
			best_distance = distance
	return best


## Si en la vía no hay otro vehículo donde iría el coche (su largo y CLEARANCE de hueco).
func is_track_free(path: Path3D, offset: float, length: float) -> bool:
	for node: Node in get_tree().get_nodes_in_group(Vehicle.GROUP):
		var vehicle := node as Vehicle
		if vehicle == null or vehicle.get_parent() != path or vehicle.data == null:
			continue
		if absf(vehicle.progress - offset) < (vehicle.data.length + length) * 0.5 + CLEARANCE:
			return false
	return true


func _on_interact(player: Player) -> void:
	repair(player)


func _amounts_text(amounts: Dictionary[StringName, int]) -> String:
	var parts: PackedStringArray = []
	for item_id: StringName in amounts:
		parts.append("%d %s" % [amounts[item_id], GameState.missions.name_of(item_id)])
	return ", ".join(parts)


func _find_station() -> Station:
	var node: Node = get_parent()
	while node != null:
		if node is Station:
			return node
		node = node.get_parent()
	return null
