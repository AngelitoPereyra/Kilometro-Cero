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
## Pasa de un tramo a otro (tarea 54): al llegar al final de su curva, si hay un RailNetwork en la
## escena, le pregunta por dónde sigue y se cambia de Path3D. El tren se ubica sobre una
## TrainRoute (las curvas que ocupa), así puede quedar repartido entre dos tramos. A un tramo
## cortado no entra: se frena con la punta en el final de su curva, como en un tope.

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
## Cuánto antes de llegar al final de su curva el tren ya mira el tramo que sigue (y lo que hay
## en él), para frenar a tiempo ante un vehículo parado del otro lado de la estación.
const LOOKAHEAD: float = 30.0

@export var data: VehicleData
## Tramo que recorre. Si queda vacío, se usa el TrackSegment que cuelga del mismo Path3D:
## desde el inspector no se puede apuntar a nodos de la escena que contiene al vehículo
## (limitación del editor para escenas instanciadas, D42).
## Al pasar a otra curva se cambia solo por el TrackSegment de esa curva (tarea 54).
@export var segment: TrackSegment
## Al empezar, se acopla detrás del vehículo más cercano que tenga adelante en la misma vía.
## Así se arma un tren en el editor sin apuntar nodos (D42).
@export var couple_on_start: bool = false
## Mira hacia el principio de su curva (avance 0) en vez de hacia el final. Lo cambia solo al
## pasar a un tramo dibujado al revés.
@export var reversed: bool = false

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
## Estación a la que va. Solo decide en los cruces (estaciones con más de un tramo para seguir);
## vacío: en un cruce se frena. Lo escribe quien maneja; vale el de la cabeza del tren.
var destination: StringName

# Las curvas que ocupa el tren, si este vehículo lo encabeza.
var _route: TrainRoute


func _ready() -> void:
	add_to_group(GROUP)
	# Al llegar al final de la vía se detiene, en vez de dar la vuelta.
	loop = false
	# En PathFollow3D, `use_model_front = true` orienta el eje +Z hacia adelante. Nuestro
	# frente es -Z (Vector3.FORWARD, la convención de Godot para cámaras y modelos), que es
	# el valor por defecto (D43).
	# Un vehículo dado vuelta sobre su curva (`reversed`) usa +Z como frente: es el mismo giro
	# de 180° sin tocar la escena.
	use_model_front = reversed
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
	return segment.get_effective_condition() if segment != null else 1.0


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
	if get_train().has(vehicle):
		return false
	var head: Vehicle = get_head()
	head._sync_route()
	if not head._route.has_path(vehicle.get_parent() as Path3D):
		return false
	rear = vehicle
	vehicle.front = self
	vehicle.throttle = 0.0
	vehicle.brake = 0.0
	_update_gangway()
	head.place_rear_vehicles()
	coupled.emit(vehicle)
	return true


## Desacopla lo que hay detrás (y lo que arrastre) y lo devuelve, o null si no había nada.
## Lo desacoplado sigue rodando solo y frena por rozamiento.
func uncouple_rear() -> Vehicle:
	var old_rear: Vehicle = rear
	if old_rear == null:
		return null
	var head: Vehicle = get_head()
	head._sync_route()
	rear = null
	old_rear.front = null
	# Lo de atrás sigue sobre las mismas curvas: arranca con una copia de la ruta.
	old_rear._route = head._route.duplicate_route()
	old_rear._route.head = old_rear._route.coordinate_of(old_rear.get_parent() as Path3D, old_rear.progress)
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
## velocidad. Lo llama el que encabeza el tren cada vez que avanza. Si alguien movió `progress`
## a mano, toma esa posición como la nueva.
func place_rear_vehicles() -> void:
	_sync_route()
	var train: Array[Vehicle] = get_train()
	var network: RailNetwork = RailNetwork.find_in(get_tree()) if is_inside_tree() else null
	if network != null:
		_extend_back(network, _route.head - _length_behind(train), train)
	_place_train(train)


## Pone este vehículo (y lo que lleve atrás) en el avance `at` de `path`, mirando hacia el
## final de la curva o, con `facing_back`, hacia el principio. Sirve para armar o restaurar un
## tren por código (estaciones, guardado, pruebas). Si va acoplado detrás de otro, no hace nada.
func place_on(path: Path3D, at: float, facing_back: bool = false) -> void:
	if front != null or path == null:
		return
	_move_to(path, at, -1 if facing_back else 1)
	_route = TrainRoute.new()
	_route.reset(path, get_curve_direction(), progress)
	place_rear_vehicles()


## Hacia dónde de su curva mira: 1 hacia el final, -1 hacia el principio (`reversed`).
func get_curve_direction() -> int:
	return -1 if reversed else 1


## Las curvas que ocupa el tren de este vehículo (las de su cabeza). Solo lectura.
func get_route() -> TrainRoute:
	var head: Vehicle = get_head()
	head._sync_route()
	return head._route


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


# Avanza el tren entero sobre su ruta. Los topes (final de la vía o tramo cortado) y los demás
# vehículos de las curvas que ocupa lo detienen en seco sin que nada se superponga; lo que toca
# con la cola se le acopla.
func _advance(distance: float) -> void:
	var path := get_parent() as Path3D
	if path == null or path.curve == null:
		return
	_sync_route()
	var train: Array[Vehicle] = get_train()
	# Cuánto ocupa el tren detrás del centro de este (el que lo encabeza).
	var behind: float = _length_behind(train)
	var ahead: float = data.length * 0.5

	# Si hay red, se suma el tramo que sigue antes de llegar a él.
	var network: RailNetwork = RailNetwork.find_in(get_tree())
	if network != null:
		if distance > 0.0:
			_extend_front(network, _route.head + ahead + distance + LOOKAHEAD)
		elif distance < 0.0:
			_extend_back(network, _route.head - behind + distance - LOOKAHEAD, train)

	# Topes de la ruta: ninguna punta del tren sale de las curvas que ocupa.
	var lowest: float = behind
	var highest: float = _route.get_length() - ahead
	var blocker_behind: Vehicle = null
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		var other := node as Vehicle
		if other == null or other.data == null or train.has(other):
			continue
		var other_path := other.get_parent() as Path3D
		if not _route.has_path(other_path):
			continue
		var at: float = _route.coordinate_of(other_path, other.progress)
		var other_half: float = other.data.length * 0.5
		if at >= _route.head:
			highest = minf(highest, at - other_half - COUPLING_GAP - ahead)
		else:
			var limit: float = at + other_half + COUPLING_GAP + behind
			if limit > lowest:
				lowest = limit
				blocker_behind = other

	var current: float = _route.head
	var target: float = current + distance
	if distance < 0.0 and target <= lowest:
		# Si ya estaba más allá del límite (colocado así en el editor), no se lo mueve
		# de golpe: solo no puede ir más atrás.
		target = minf(lowest, current)
		speed = 0.0
		if blocker_behind != null and lowest <= current:
			train.back().couple(blocker_behind)
			train = get_train()
	elif distance > 0.0 and target >= highest:
		target = maxf(highest, current)
		speed = 0.0
	_route.head = target
	_place_train(train)
	var tail_at: float = _route.head - _length_behind(train)
	_route.trim(tail_at, _route.head + ahead)
	_drop_cut_spares(tail_at, _route.head + ahead)
	if network != null:
		_use_own_way_on_spares(network, _length_behind(train), ahead)


# Los pedazos de ruta que se guardan por si el tren vuelve (adelante o atrás de él) se olvidan
# si su tramo está cortado: a un tramo cortado no se entra, tampoco marcha atrás.
func _drop_cut_spares(tail_at: float, front_at: float) -> void:
	var from: float = tail_at
	var to: float = front_at
	while _route.get_piece_count() > 1 and _route.piece_start(1) <= from and _is_cut(_route.get_path(0)):
		# Al sacar un pedazo de atrás, todas las coordenadas corren lo que medía.
		var shift: float = _route.piece_length(0)
		_route.drop_back()
		from -= shift
		to -= shift
	while _route.get_piece_count() > 1:
		var last: int = _route.get_piece_count() - 1
		if _route.piece_start(last) < to or not _is_cut(_route.get_path(last)):
			break
		_route.drop_front()


# Los pedazos guardados por si el tren vuelve recuerdan por qué tramo vino, pero en un tramo de
# vía doble el tren vuelve por la vía de su sentido (D81): la que sale de la estación hacia
# donde va. Así, marcha atrás desde el pueblo, entra a la Vuelta y no a la Ida.
func _use_own_way_on_spares(network: RailNetwork, behind: float, ahead: float) -> void:
	var count: int = _route.get_piece_count()
	if count < 2:
		return
	# Atrás: el pedazo 0, si el tren ya salió entero de él.
	if _route.piece_start(1) <= _route.head - behind:
		var next_track: TrackSegment = RailNetwork.track_of(_route.get_path(1))
		var spare: TrackSegment = RailNetwork.track_of(_route.get_path(0))
		if next_track != null and spare != null:
			var station: StringName = next_track.from_station if _route.get_dir(1) > 0 else next_track.to_station
			var own: TrackSegment = network.track_leaving(spare.segment_id, station)
			if own != null and own != spare and own.get_track_path() != null:
				_route.replace_piece(0, own.get_track_path(), -1 if own.from_station == station else 1)
	# Adelante: el último pedazo, si el tren todavía no entró a él.
	var last: int = _route.get_piece_count() - 1
	if _route.piece_start(last) >= _route.head + ahead:
		var prev_track: TrackSegment = RailNetwork.track_of(_route.get_path(last - 1))
		var spare: TrackSegment = RailNetwork.track_of(_route.get_path(last))
		if prev_track != null and spare != null:
			var station: StringName = prev_track.to_station if _route.get_dir(last - 1) > 0 else prev_track.from_station
			var own: TrackSegment = network.track_leaving(spare.segment_id, station)
			if own != null and own != spare and own.get_track_path() != null:
				_route.replace_piece(last, own.get_track_path(), 1 if own.from_station == station else -1)


static func _is_cut(path: Path3D) -> bool:
	var track: TrackSegment = RailNetwork.track_of(path)
	return track != null and track.is_cut()


# Lo que ocupa el tren detrás del centro de su cabeza (hasta la punta de la cola).
func _length_behind(train: Array[Vehicle]) -> float:
	var behind: float = train.back().data.length * 0.5
	for i: int in range(1, train.size()):
		behind += coupling_distance(train[i - 1].data.length, train[i].data.length)
	return behind


# Ubica a todo el tren sobre la ruta: cada vehículo a su distancia de la cabeza, en la curva
# que le toque y mirando para el lado del tren.
func _place_train(train: Array[Vehicle]) -> void:
	var at: float = _route.head
	for i: int in train.size():
		var vehicle: Vehicle = train[i]
		if i > 0:
			at -= coupling_distance(train[i - 1].data.length, vehicle.data.length)
			vehicle.speed = speed
		var spot: Array = _route.locate(at)
		vehicle._move_to(_route.get_path(spot[0]), spot[1], _route.get_dir(spot[0]))


# Lleva el vehículo a `progress` de `path`, mirando según `dir`. Si cambia de curva, se cambia
# de padre (sin tocar a quien vaya arriba: el jugador sigue al cuerpo físico).
func _move_to(path: Path3D, at: float, dir: int) -> void:
	if path == null:
		return
	if get_parent() != path:
		reparent(path, false)
		segment = _find_segment()
	reversed = dir < 0
	if use_model_front != reversed:
		use_model_front = reversed
	progress = at


# La cabeza se ubica en la ruta: si nadie la armó o el vehículo está en otra curva (lo movieron
# a mano), arranca una ruta nueva donde está; si no, toma su avance actual.
func _sync_route() -> void:
	var path := get_parent() as Path3D
	if _route == null or not _route.has_path(path):
		_route = TrainRoute.new()
		_route.reset(path, get_curve_direction(), progress)
		return
	var at: float = _route.coordinate_of(path, progress)
	if not is_nan(at):
		_route.head = at


# Suma tramos adelante hasta que la ruta llegue a la coordenada `needed` o no haya por dónde.
func _extend_front(network: RailNetwork, needed: float) -> void:
	for _i: int in 8:
		if _route.get_length() >= needed:
			return
		var last: int = _route.get_piece_count() - 1
		var track: TrackSegment = RailNetwork.track_of(_route.get_path(last))
		if track == null:
			return
		var station: StringName = track.to_station if _route.get_dir(last) > 0 else track.from_station
		var next: TrackSegment = network.next_track(track, station, get_head().destination)
		if next == null or next.get_track_path() == null or _route.has_path(next.get_track_path()):
			return
		# Si sale de la estación por el principio de la curva, el frente mira hacia su final.
		_route.push_front(next.get_track_path(), 1 if next.from_station == station else -1)


# Suma tramos atrás hasta que la ruta empiece antes de la coordenada `needed` (que puede ser
# negativa) o no haya por dónde.
func _extend_back(network: RailNetwork, needed: float, train: Array[Vehicle]) -> void:
	var missing: float = -needed
	for _i: int in 8:
		if missing <= 0.0:
			return
		var track: TrackSegment = RailNetwork.track_of(_route.get_path(0))
		if track == null:
			return
		var station: StringName = track.from_station if _route.get_dir(0) > 0 else track.to_station
		var next: TrackSegment = _track_behind(network, track, station, train)
		if next == null or next.get_track_path() == null or _route.has_path(next.get_track_path()):
			return
		var before: float = _route.get_length()
		# La cola sale de la estación: si entra por el principio de la curva, el frente mira
		# hacia la estación, o sea hacia el principio.
		_route.push_back(next.get_track_path(), -1 if next.from_station == station else 1)
		missing -= _route.get_length() - before


# Por dónde sigue la ruta hacia atrás: primero, la curva donde ya está algún vehículo del tren
# (al acoplar uno que quedó del otro lado de la estación); si no, lo que diga la red.
func _track_behind(network: RailNetwork, current: TrackSegment, station: StringName, train: Array[Vehicle]) -> TrackSegment:
	for vehicle: Vehicle in train:
		var track: TrackSegment = RailNetwork.track_of(vehicle.get_parent() as Path3D)
		if track != null and track != current and not _route.has_path(track.get_track_path()) \
				and (track.from_station == station or track.to_station == station):
			return track
	return network.next_track(current, station)


# El vehículo más cercano adelante en la misma vía (mayor avance), si tiene la cola libre.
func _couple_to_vehicle_ahead() -> void:
	var nearest: Vehicle = null
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		var other := node as Vehicle
		if other == null or other == self or other.get_parent() != get_parent():
			continue
		var dir: int = get_curve_direction()
		if other.progress * dir > progress * dir and (nearest == null or other.progress * dir < nearest.progress * dir):
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
