class_name Vehicle
extends PathFollow3D
## Vehículo que sigue la curva de la vía (D06): sin física de ruedas, solo avanza
## `progress` metros sobre el Path3D padre. Su velocidad máxima sale de `data` y de la
## condición del tramo. No lee teclas: quien lo maneja (el jugador, rutas automáticas)
## escribe `throttle`. Así el mismo vehículo sirve para todos.
## Es caminable (tarea 51, D84): el jugador se engancha a cualquier cuerpo físico que cuelgue
## del vehículo (un AnimatableBody3D, D62) y viaja con él. El vehículo no sabe nada de eso.
## Se acopla (tarea 53): el que encabeza el tren simula y ubica a los de atrás sobre la misma
## curva, a la distancia de acople. Ningún vehículo sale de la vía ni se superpone con otro de
## la misma vía: al tocarlo frena en seco y, si lo tocó con la cola (marcha atrás), se le acopla.

signal coupled(rear_vehicle: Vehicle)
signal uncoupled(rear_vehicle: Vehicle)

## Grupo de todos los vehículos.
const GROUP: StringName = &"vehicles"
## Hueco entre los cuerpos de dos vehículos acoplados, y lo más cerca que pueden quedar dos
## vehículos sueltos.
const COUPLING_GAP: float = 0.6
## Nombre de los nodos de la pasarela trasera (malla y forma de choque): solo están mientras
## haya algo acoplado atrás, para no tener que saltar el hueco.
const GANGWAY_NODE: StringName = &"Pasarela"

@export var data: VehicleData
## Tramo que recorre. Si queda vacío, se usa el TrackSegment que cuelga del mismo Path3D:
## desde el inspector no se puede apuntar a nodos de la escena que contiene al vehículo
## (limitación del editor para escenas instanciadas, D42).
## En la tarea 20, RailNetwork lo reemplaza por una consulta por tramo.
@export var segment: TrackSegment
## Al empezar, se acopla detrás del vehículo más cercano que tenga adelante en la misma vía.
## Así se arma un tren en el editor sin apuntar nodos (D42).
@export var couple_on_start: bool = false

## Acelerador pedido: 1.0 adelante a fondo, -1.0 marcha atrás, 0.0 soltar.
var throttle: float = 0.0
## Freno pedido: 0.0 suelto, 1.0 a fondo. Mientras frena, el acelerador no empuja (tarea 52).
var brake: float = 0.0
## Velocidad actual en m/s sobre la curva; negativa = marcha atrás.
var speed: float = 0.0
## Vehículo acoplado adelante (null si este encabeza el tren) y atrás (null si es la cola).
## Solo se cambian con couple() y uncouple_rear().
var front: Vehicle
var rear: Vehicle


func _ready() -> void:
	add_to_group(GROUP)
	# Al llegar al final de la vía se detiene, en vez de dar la vuelta.
	loop = false
	# En PathFollow3D, `use_model_front = true` orienta el eje +Z hacia adelante. Nuestro
	# frente es -Z (Vector3.FORWARD, la convención de Godot para cámaras y modelos), que es
	# el valor por defecto: lo dejamos explícito para que nadie lo cambie por error (D43).
	use_model_front = false
	if segment == null:
		segment = _find_segment()
	if segment == null:
		# Sin tramo, get_track_condition() devuelve 1.0 y el vehículo no tendría límite:
		# preferimos avisar a que falle en silencio.
		push_warning("Vehicle no encontró un TrackSegment en su Path3D: no habrá límite por condición de vía.")
	if data == null:
		push_error("Vehicle necesita un VehicleData asignado.")
		set_physics_process(false)
		return
	_update_gangway()
	if couple_on_start:
		# Diferido: los demás vehículos de la escena todavía pueden no estar listos.
		_couple_to_vehicle_ahead.call_deferred()


func _physics_process(delta: float) -> void:
	simulate(delta)


## Un paso de simulación. Es público para poder probarlo con pasos fijos y sin esperar cuadros.
## Un vehículo acoplado detrás de otro no simula: lo ubica el que encabeza el tren.
func simulate(delta: float) -> void:
	if front != null:
		return
	var limit: float = get_max_speed()
	if brake > 0.0:
		speed = move_toward(speed, 0.0, data.braking * clampf(brake, 0.0, 1.0) * delta)
	elif absf(speed) > limit:
		# Si la vía obliga a ir más despacio, frena de verdad (no alcanza con dejarlo rodar).
		speed = step_speed(speed, throttle, limit, data.acceleration, data.braking, delta)
	else:
		# Sin freno, bajar el acelerador solo deja rodar: lo frena el rozamiento.
		speed = step_speed(speed, throttle, limit, data.acceleration, data.coast_deceleration, delta)
	_advance(speed * delta)


func get_track_condition() -> float:
	# Sin tramo asignado no hay desgaste que limite al vehículo.
	return segment.condition if segment != null else 1.0


## Velocidad máxima permitida ahora mismo: la del más lento del tren, según la vía que pisa.
func get_max_speed() -> float:
	var limit: float = INF
	for vehicle: Vehicle in get_train():
		limit = minf(limit, vehicle.data.get_max_speed(vehicle.get_track_condition()))
	return limit


## Acopla `vehicle` (con lo que lleve detrás) a la cola de este. Tiene que estar en la misma
## vía y encabezar su propio tren; queda a la distancia de acople. Devuelve false si no se pudo.
func couple(vehicle: Vehicle) -> bool:
	if vehicle == null or vehicle.data == null or rear != null or vehicle.front != null:
		return false
	if vehicle.get_parent() != get_parent() or get_train().has(vehicle):
		return false
	rear = vehicle
	vehicle.front = self
	vehicle.throttle = 0.0
	vehicle.brake = 0.0
	_update_gangway()
	get_head().place_rear_vehicles()
	coupled.emit(vehicle)
	return true


## Desacopla lo que hay detrás (y lo que arrastre) y lo devuelve, o null si no había nada.
## Lo desacoplado sigue rodando solo y frena por rozamiento.
func uncouple_rear() -> Vehicle:
	var old_rear: Vehicle = rear
	if old_rear == null:
		return null
	rear = null
	old_rear.front = null
	_update_gangway()
	uncoupled.emit(old_rear)
	return old_rear


## El vehículo que encabeza el tren de este (él mismo si va adelante).
func get_head() -> Vehicle:
	var vehicle: Vehicle = self
	while vehicle.front != null:
		vehicle = vehicle.front
	return vehicle


## El último vehículo del tren de este (él mismo si no tiene nada atrás).
func get_tail() -> Vehicle:
	var vehicle: Vehicle = self
	while vehicle.rear != null:
		vehicle = vehicle.rear
	return vehicle


## Todos los vehículos del tren de este, de adelante hacia atrás.
func get_train() -> Array[Vehicle]:
	var train: Array[Vehicle] = []
	var vehicle: Vehicle = get_head()
	while vehicle != null:
		train.append(vehicle)
		vehicle = vehicle.rear
	return train


## Ubica a los vehículos acoplados detrás de este, a la distancia de acople y con su
## velocidad. Lo llama el que encabeza el tren cada vez que avanza.
func place_rear_vehicles() -> void:
	var vehicle: Vehicle = self
	while vehicle.rear != null:
		var next: Vehicle = vehicle.rear
		next.progress = vehicle.progress - coupling_distance(vehicle.data.length, next.data.length)
		next.speed = speed
		vehicle = next


## Distancia sobre la curva entre los centros de dos vehículos acoplados. Lógica pura.
static func coupling_distance(front_length: float, rear_length: float) -> float:
	return front_length * 0.5 + COUPLING_GAP + rear_length * 0.5


## El Vehicle al que pertenece `node` (el mismo nodo o uno de sus padres), o null.
## Sirve para saber si un cuerpo físico que se pisó es parte de un vehículo.
static func find_owner_of(node: Node) -> Vehicle:
	while node != null:
		var vehicle := node as Vehicle
		if vehicle != null:
			return vehicle
		node = node.get_parent()
	return null


## Nueva velocidad tras un paso. Lógica pura: no toca ningún nodo.
## Acelera solo si el objetivo está más lejos del cero que la velocidad actual y en el
## mismo sentido. En cualquier otro caso (soltar, límite que baja, invertir) frena.
static func step_speed(current_speed: float, throttle_input: float, speed_limit: float, accel: float, decel: float, delta: float) -> float:
	var target: float = clampf(throttle_input, -1.0, 1.0) * speed_limit
	var speeding_up: bool = absf(target) > absf(current_speed) \
			and (is_zero_approx(current_speed) or signf(target) == signf(current_speed))
	var rate: float = accel if speeding_up else decel
	return move_toward(current_speed, target, rate * delta)


# Avanza el tren entero. Los topes de la vía y los demás vehículos de la misma vía lo
# detienen en seco sin que nada se superponga; lo que toca con la cola se le acopla.
func _advance(distance: float) -> void:
	var path := get_parent() as Path3D
	if path == null or path.curve == null:
		return
	var train: Array[Vehicle] = get_train()
	var tail: Vehicle = train.back()
	# Cuánto ocupa el tren detrás del centro de este (el que lo encabeza).
	var behind: float = tail.data.length * 0.5
	for i: int in range(1, train.size()):
		behind += coupling_distance(train[i - 1].data.length, train[i].data.length)
	var ahead: float = data.length * 0.5

	# Topes de la vía: ninguna punta del tren sale de la curva.
	var lowest: float = behind
	var highest: float = path.curve.get_baked_length() - ahead
	var blocker_behind: Vehicle = null
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		var other := node as Vehicle
		if other == null or other.data == null or other.get_parent() != path or train.has(other):
			continue
		var other_half: float = other.data.length * 0.5
		if other.progress >= progress:
			highest = minf(highest, other.progress - other_half - COUPLING_GAP - ahead)
		else:
			var limit: float = other.progress + other_half + COUPLING_GAP + behind
			if limit > lowest:
				lowest = limit
				blocker_behind = other

	var target: float = progress + distance
	if distance < 0.0 and target <= lowest:
		# Si ya estaba más allá del límite (colocado así en el editor), no se lo mueve
		# de golpe: solo no puede ir más atrás.
		target = minf(lowest, progress)
		speed = 0.0
		if blocker_behind != null and lowest <= progress:
			tail.couple(blocker_behind)
	elif distance > 0.0 and target >= highest:
		target = maxf(highest, progress)
		speed = 0.0
	progress = target
	place_rear_vehicles()


# El vehículo más cercano adelante en la misma vía (mayor avance), si tiene la cola libre.
func _couple_to_vehicle_ahead() -> void:
	var nearest: Vehicle = null
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		var other := node as Vehicle
		if other == null or other == self or other.get_parent() != get_parent():
			continue
		if other.progress > progress and (nearest == null or other.progress < nearest.progress):
			nearest = other
	if nearest == null or not nearest.couple(self):
		push_warning("%s no encontró adelante un vehículo libre al que acoplarse." % name)


# La pasarela trasera aparece solo con algo acoplado atrás. Diferido: el acople puede pasar
# en medio del paso de física, y ahí no conviene tocar formas de choque.
func _update_gangway() -> void:
	var has_rear: bool = rear != null
	for node: Node in find_children(GANGWAY_NODE, "", true, false):
		var shape := node as CollisionShape3D
		if shape != null:
			shape.set_deferred(&"disabled", not has_rear)
		elif node is Node3D:
			(node as Node3D).visible = has_rear


func _find_segment() -> TrackSegment:
	var path: Node = get_parent()
	if path == null:
		return null
	for child: Node in path.get_children():
		var found := child as TrackSegment
		if found != null:
			return found
	return null
