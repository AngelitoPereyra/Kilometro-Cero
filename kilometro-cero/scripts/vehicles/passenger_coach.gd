class_name PassengerCoach
extends Wagon
## Coche de pasajeros (D85, D103, tarea 60b): un Wagon cuyo WagonData solo acepta pasajeros
## (ItemData.PASSENGER_TAG; data/vehicles/passenger_coach.tres, 10 lugares). No tiene zona de
## carga: la gente no se sube ni se baja con E y Q. Se usa con las puertas: la tecla de puertas
## en la cabina (Cab.toggle_doors) las abre con el tren detenido en una estación, y al abrirse
## baja y sube gente según PassengerTraffic (misiones, demanda y tarifa). Se cierran solas al
## arrancar.
## Hijos opcionales: "Visual/Puertas" (las hojas de las puertas: se esconden abiertas),
## formas "Puerta*" dentro de "CuerpoFisico" (se apagan abiertas) y "Visual/Pasajeros" (un
## muñequito sentado por lugar: se ven tantos como pasajeros lleva).

signal doors_changed(is_open: bool)
## Se abrieron las puertas en una estación: el plan aplicado (ver PassengerTraffic.plan_exchange).
signal passengers_exchanged(station_id: StringName, result: Dictionary)

const DOORS_PATH: NodePath = ^"Visual/Puertas"
const SEATED_PATH: NodePath = ^"Visual/Pasajeros"
const BODY_PATH: NodePath = ^"CuerpoFisico"
## Por encima de esta velocidad (m/s) del tren, las puertas se cierran solas.
const CLOSE_SPEED: float = 0.5
## Muñequitos que caminan como máximo por cada lado (bajan o suben).
const MAX_WALKERS: int = 6
## Segundos que tarda un muñequito en caminar entre el coche y el andén.
const WALK_TIME: float = 2.0

var doors_open: bool = false

var _seated: Node3D
var _doors: Node3D


func _ready() -> void:
	super._ready()
	_seated = get_node_or_null(SEATED_PATH) as Node3D
	_doors = get_node_or_null(DOORS_PATH) as Node3D
	cargo_changed.connect(func(_total: int, _capacity: int) -> void: _update_seated())
	_apply_doors()
	_update_seated()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if doors_open and absf(get_head().speed) > CLOSE_SPEED:
		set_doors(false)


## La estación donde está detenido el tren de este coche, o null.
func get_station() -> Station:
	if not is_inside_tree():
		return null
	var head: Vehicle = get_head()
	for node: Node in get_tree().get_nodes_in_group(Station.GROUP):
		var station := node as Station
		if station != null and station.get_stopped_trains().has(head):
			return station
	return null


func can_open_doors() -> bool:
	return not automatic and get_station() != null


## Pasajeros a bordo: id -> unidades.
func get_aboard() -> Dictionary[StringName, int]:
	var aboard: Dictionary[StringName, int] = {}
	var cargo: StorageContainer = get_cargo()
	if cargo == null:
		return aboard
	for index: int in cargo.get_stack_count():
		var stack: ItemStack = cargo.peek(index)
		aboard[stack.item.id] = aboard.get(stack.item.id, 0) + stack.quantity
	return aboard


## Abre o cierra las puertas. Abrir solo se puede con el tren detenido en una estación, y hace
## el intercambio de pasajeros. Devuelve false si quedó igual.
func set_doors(value: bool) -> bool:
	if value == doors_open or (value and not can_open_doors()):
		return false
	doors_open = value
	_apply_doors()
	doors_changed.emit(value)
	if value:
		exchange()
	return true


## Baja y sube gente en la estación donde está detenido (lo hace solo al abrir las puertas).
## Devuelve el plan aplicado, o vacío si no está en una estación.
func exchange() -> Dictionary:
	var station: Station = get_station()
	var cargo: StorageContainer = get_cargo()
	if station == null or cargo == null:
		return {}
	var station_id: StringName = station.get_station_id()
	var traffic: PassengerTraffic = GameState.passengers
	var plan: Dictionary = traffic.plan_exchange(station_id, get_aboard(), cargo.capacity)
	var alighted: int = 0
	for key: String in ["mission", "alight"]:
		var leaving: Dictionary = plan[key]
		for item_id: StringName in leaving:
			alighted += _take_item(item_id, int(leaving[item_id]))
	var boarded: int = 0
	for key: String in ["board_free", "board_paid"]:
		var entering: Dictionary = plan[key]
		for item_id: StringName in entering:
			var item: ItemData = GameState.economy.get_item(item_id)
			# La familia de una mudanza no está en ningún mercado (tarea 62b.6).
			if item == null:
				item = GameState.missions.find_item(item_id)
			var leftover: ItemStack = cargo.try_store(ItemStack.new(item, int(entering[item_id])))
			if leftover != null:
				push_warning("PassengerCoach: no entraron %d %s." % [leftover.quantity, item_id])
			boarded += int(entering[item_id]) - (leftover.quantity if leftover != null else 0)
	var fare: int = traffic.apply_exchange(station_id, plan)
	GameState.add_money(fare)
	EventBus.passengers_exchanged.emit(station_id, alighted, boarded, fare)
	passengers_exchanged.emit(station_id, plan)
	_show_walkers(station, alighted, boarded)
	return plan


func _take_item(item_id: StringName, amount: int) -> int:
	var cargo: StorageContainer = get_cargo()
	var taken: int = 0
	for index: int in range(cargo.get_stack_count() - 1, -1, -1):
		if taken >= amount:
			break
		if cargo.peek(index).item.id == item_id:
			var stack: ItemStack = cargo.take(index, amount - taken)
			taken += stack.quantity if stack != null else 0
	return taken


func _update_cargo_visual() -> void:
	super._update_cargo_visual()
	_update_seated()


func _apply_doors() -> void:
	if _doors != null:
		_doors.visible = not doors_open
	var body: Node = get_node_or_null(BODY_PATH)
	if body == null:
		return
	for child: Node in body.get_children():
		var shape := child as CollisionShape3D
		if shape != null and String(shape.name).begins_with("Puerta"):
			shape.disabled = doors_open


func _update_seated() -> void:
	if _seated == null:
		return
	var total: int = get_shown_units()
	var index: int = 0
	for child: Node in _seated.get_children():
		var figure := child as Node3D
		if figure != null:
			figure.visible = index < total
			index += 1


# Muñequitos que caminan entre la puerta del lado del andén y el andén (solo se ven).
func _show_walkers(station: Station, alighted: int, boarded: int) -> void:
	var door: Vector3 = _door_towards(station)
	# El andén de las plantillas queda del lado -X de la estación.
	var side: Vector3 = station.global_basis * Vector3.LEFT
	var platform: Vector3 = door + Vector3(side.x, 0.0, side.z).normalized() * 4.0
	for index: int in mini(alighted, MAX_WALKERS):
		_walk(door, platform, index * 0.3)
	for index: int in mini(boarded, MAX_WALKERS):
		_walk(platform, door, 0.6 + index * 0.3)


# La puerta (hija de Visual/Puertas) más cercana al andén; sin puertas, el centro del coche.
func _door_towards(station: Station) -> Vector3:
	var target: Vector3 = station.global_position + station.global_basis * Vector3.LEFT * 5.0
	var best: Vector3 = global_position + Vector3.UP * 0.8
	var best_distance: float = INF
	if _doors != null:
		for child: Node in _doors.get_children():
			var door := child as Node3D
			if door != null and door.global_position.distance_to(target) < best_distance:
				best_distance = door.global_position.distance_to(target)
				best = door.global_position
	return Vector3(best.x, global_position.y + 0.8, best.z)


func _walk(from: Vector3, to: Vector3, delay: float) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var figure := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.2
	mesh.height = 1.1
	figure.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.from_hsv(randf(), 0.45, 0.85)
	figure.material_override = material
	figure.visible = false
	scene_root.add_child(figure)
	figure.global_position = from + Vector3.UP * 0.55
	var tween: Tween = figure.create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(figure.show)
	tween.tween_property(figure, "global_position", to + Vector3.UP * 0.55, WALK_TIME)
	tween.tween_callback(figure.queue_free)
