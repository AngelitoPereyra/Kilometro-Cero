extends Node3D
## Prueba de la Vehiculo: VehicleData, aceleración y vehículo sobre la vía.
## Las comprobaciones corren con simulate() en pasos fijos, sin esperar cuadros reales.
## Supone la vía de 200 m de las tareas 6 y 7, y un VehicleData con
## min_track_condition > 0 y max_speed mayor que la velocidad en la condición mínima.
## Después de las pruebas se puede manejar el vehículo: Espacio empuja, S marcha atrás.
## Para ver cómo cambia la velocidad, mové la condición del TrackSegment desde la
## pestaña Remote del panel Scene mientras el juego corre.

const PASO_S: float = 1.0 / 60.0

@onready var _track: ManualTrack = $Track
@onready var _segment: TrackSegment = $Track/TrackSegment
@onready var _vehicle: Vehicle = $Track/Vehicle
@onready var _hud: Label = get_node_or_null("Hud") as Label

var _fallos: int = 0
var _manual: bool = false


func _ready() -> void:
	# Pausamos la simulación propia del vehículo: las pruebas la manejan paso a paso.
	_vehicle.set_physics_process(false)
	var condicion_inicial: float = _segment.condition

	_probar_datos_de_vehiculo()
	_probar_aceleracion()
	_probar_vehiculo()
	_probar_orientacion()

	if _fallos == 0:
		print("Vehiculo: todas las comprobaciones pasaron.")
	else:
		push_error("Tarea 8: fallaron %d comprobaciones." % _fallos)

	# Dejamos todo como estaba y habilitamos el manejo manual.
	_reiniciar(condicion_inicial)
	_vehicle.set_physics_process(true)
	_manual = true


func _physics_process(_delta: float) -> void:
	if _manual:
		# Solo la escena de prueba lee la entrada; el vehículo recibe un número (-1 a 1).
		_vehicle.throttle = Input.get_axis(&"move_back", &"push")


func _process(_delta: float) -> void:
	if _hud == null or not _manual:
		return
	_hud.text = "Condición de vía: %d %%\nVelocidad: %.1f m/s (%.0f km/h) · máxima en este tramo: %.1f m/s\nEspacio: empujar · S: marcha atrás" % [
		roundi(_segment.condition * 100.0),
		_vehicle.speed,
		absf(_vehicle.speed) * 3.6,
		_vehicle.get_max_speed(),
	]


func _probar_datos_de_vehiculo() -> void:
	var datos := VehicleData.new()
	datos.min_track_condition = 0.4
	datos.max_speed = 10.0
	datos.min_speed_fraction = 0.5
	_comprobar(not datos.can_enter(0.39), "No entra a una vía bajo la condición mínima")
	_comprobar(datos.can_enter(0.4), "Entra justo en la condición mínima")
	_comprobar(is_zero_approx(datos.get_max_speed(0.39)), "Bajo el mínimo la velocidad máxima es 0")
	_comprobar(is_equal_approx(datos.get_max_speed(0.4), 5.0), "En la condición mínima: la fracción mínima (5.0 m/s)")
	_comprobar(is_equal_approx(datos.get_max_speed(1.0), 10.0), "Con la vía perfecta: velocidad máxima (10.0 m/s)")
	_comprobar(is_equal_approx(datos.get_max_speed(0.7), 7.5), "A mitad de camino se interpola (7.5 m/s)")
	datos.min_track_condition = 1.0
	_comprobar(is_equal_approx(datos.get_max_speed(1.0), 10.0), "Un vehículo que exige vía perfecta no produce NaN")


func _probar_aceleracion() -> void:
	# Argumentos: velocidad actual, acelerador, límite, aceleración 1.0, frenado 2.5, un segundo.
	_comprobar(is_equal_approx(Vehicle.step_speed(0.0, 1.0, 6.0, 1.0, 2.5, 1.0), 1.0), "Acelera desde cero a 1 m/s por segundo")
	_comprobar(is_equal_approx(Vehicle.step_speed(5.5, 1.0, 6.0, 1.0, 2.5, 1.0), 6.0), "No supera el límite")
	_comprobar(is_equal_approx(Vehicle.step_speed(6.0, 0.0, 6.0, 1.0, 2.5, 1.0), 3.5), "Al soltar el acelerador frena")
	_comprobar(is_equal_approx(Vehicle.step_speed(6.0, 1.0, 2.0, 1.0, 2.5, 1.0), 3.5), "Si el límite baja, frena hacia el nuevo límite")
	_comprobar(is_equal_approx(Vehicle.step_speed(0.0, -1.0, 6.0, 1.0, 2.5, 1.0), -1.0), "Acelera en marcha atrás")
	_comprobar(is_equal_approx(Vehicle.step_speed(2.0, -1.0, 6.0, 1.0, 2.5, 1.0), -0.5), "Invertir el sentido frena primero")
	_comprobar(is_zero_approx(Vehicle.step_speed(0.0, 1.0, 0.0, 1.0, 2.5, 1.0)), "Con límite 0 no arranca")


func _probar_vehiculo() -> void:
	var listo: bool = _vehicle.data != null and _vehicle.segment != null
	_comprobar(listo, "El vehículo tiene VehicleData y tramo asignados")
	if not listo:
		return
	var minima: float = _vehicle.data.min_track_condition
	var largo: float = _track.curve.get_baked_length()

	# Justo en la condición mínima el vehículo puede andar.
	_reiniciar(minima, 0.0, 0.0, 1.0)
	_simular(1.0)
	_comprobar(_vehicle.speed > 0.0 and _vehicle.progress > 0.0, "El vehículo arranca y avanza")
	_simular(10.0)
	var limite_bajo: float = _vehicle.get_max_speed()
	_comprobar(is_equal_approx(_vehicle.speed, limite_bajo), "Llega a la velocidad máxima del tramo (%.1f m/s)" % limite_bajo)

	# Con mejor vía el límite sube y el vehículo acelera hasta él.
	_segment.condition = 1.0
	var limite_alto: float = _vehicle.get_max_speed()
	_comprobar(limite_alto > limite_bajo, "Con mejor vía el límite sube (%.1f m/s)" % limite_alto)
	_simular(10.0)
	_comprobar(is_equal_approx(_vehicle.speed, limite_alto), "Acelera hasta el nuevo límite")

	# Bajo el mínimo no puede andar: frena hasta detenerse y no vuelve a arrancar.
	_segment.condition = maxf(minima - 0.1, 0.0)
	_simular(10.0)
	_comprobar(is_zero_approx(_vehicle.speed), "Bajo la condición mínima el vehículo se detiene")
	var avance: float = _vehicle.progress
	_simular(1.0)
	_comprobar(is_equal_approx(_vehicle.progress, avance), "Y no avanza aunque se acelere")

	# Topes: al llegar a un extremo de la vía se detiene en seco.
	_reiniciar(1.0, largo - 1.0, 6.0, 1.0)
	_simular(2.0)
	_comprobar(is_equal_approx(_vehicle.progress, largo) and is_zero_approx(_vehicle.speed), "Se detiene en el tope del final de la vía")
	_reiniciar(1.0, 1.0, -6.0, -1.0)
	_simular(2.0)
	_comprobar(is_zero_approx(_vehicle.progress) and is_zero_approx(_vehicle.speed), "Se detiene en el tope del inicio de la vía")


func _reiniciar(condicion: float, avance: float = 0.0, velocidad: float = 0.0, acelerador: float = 0.0) -> void:
	_segment.condition = condicion
	_vehicle.progress = avance
	_vehicle.speed = velocidad
	_vehicle.throttle = acelerador


func _simular(segundos: float) -> void:
	for _i: int in roundi(segundos / PASO_S):
		_vehicle.simulate(PASO_S)


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)


func _probar_orientacion() -> void:
	_reiniciar(1.0, 50.0)
	var curva: Curve3D = _track.curve
	# Sentido de la vía en ese punto, medido con dos muestras cercanas.
	var sentido: Vector3 = (curva.sample_baked(51.0) - curva.sample_baked(50.0)).normalized()
	# El frente del vehículo es -Z; el basis del PathFollow3D ya viene orientado.
	var frente: Vector3 = -_vehicle.basis.z
	_comprobar(frente.dot(sentido) > 0.99, "El frente del vehículo (-Z) apunta en el sentido de la vía")
