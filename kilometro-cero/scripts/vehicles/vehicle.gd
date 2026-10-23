class_name Vehicle
extends PathFollow3D
## Vehículo que sigue la curva de la vía (D06): sin física de ruedas, solo avanza
## `progress` metros sobre el Path3D padre. Su velocidad máxima sale de `data` y de la
## condición del tramo. No lee teclas: quien lo maneja (el jugador, rutas automáticas)
## escribe `throttle`. Así el mismo vehículo sirve para todos.
## Es caminable (tarea 51, D84): el jugador se engancha a cualquier cuerpo físico que cuelgue
## del vehículo (un AnimatableBody3D, D62) y viaja con él. El vehículo no sabe nada de eso.

## Grupo de todos los vehículos.
const GROUP: StringName = &"vehicles"

@export var data: VehicleData
## Tramo que recorre. Si queda vacío, se usa el TrackSegment que cuelga del mismo Path3D:
## desde el inspector no se puede apuntar a nodos de la escena que contiene al vehículo
## (limitación del editor para escenas instanciadas, D42).
## En la tarea 20, RailNetwork lo reemplaza por una consulta por tramo.
@export var segment: TrackSegment

## Acelerador pedido: 1.0 adelante a fondo, -1.0 marcha atrás, 0.0 soltar.
var throttle: float = 0.0
## Freno pedido: 0.0 suelto, 1.0 a fondo. Mientras frena, el acelerador no empuja (tarea 52).
var brake: float = 0.0
## Velocidad actual en m/s sobre la curva; negativa = marcha atrás.
var speed: float = 0.0


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


func _physics_process(delta: float) -> void:
	simulate(delta)


## Un paso de simulación. Es público para poder probarlo con pasos fijos y sin esperar cuadros.
func simulate(delta: float) -> void:
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


## Velocidad máxima permitida ahora mismo, según el vehículo y la vía que pisa.
func get_max_speed() -> float:
	return data.get_max_speed(get_track_condition())


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
static func step_speed(current_speed: float, throttle_input: float, speed_limit: float, accel: float, brake: float, delta: float) -> float:
	var target: float = clampf(throttle_input, -1.0, 1.0) * speed_limit
	var speeding_up: bool = absf(target) > absf(current_speed) \
			and (is_zero_approx(current_speed) or signf(target) == signf(current_speed))
	var rate: float = accel if speeding_up else brake
	return move_toward(current_speed, target, rate * delta)


func _advance(distance: float) -> void:
	var path := get_parent() as Path3D
	if path == null or path.curve == null:
		return
	var length: float = path.curve.get_baked_length()
	var target: float = progress + distance
	if target <= 0.0 or target >= length:
		# Tope en cualquiera de los dos extremos: el vehículo se detiene en seco.
		target = clampf(target, 0.0, length)
		speed = 0.0
	progress = target


func _find_segment() -> TrackSegment:
	var path: Node = get_parent()
	if path == null:
		return null
	for child: Node in path.get_children():
		var found := child as TrackSegment
		if found != null:
			return found
	return null
