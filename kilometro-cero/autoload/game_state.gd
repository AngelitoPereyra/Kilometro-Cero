extends Node
## Estado de la partida. Es dueño del reloj del juego (D34) y del modelo de producción
## (D79, tarea 57): lo avanza un día en cada día nuevo y reemite sus cambios de nivel.
## Los demás datos (dinero) entran cuando un sistema los necesite.

## Minutos reales que dura un día de juego (D34). Vivía en NeedsConfig, que se borró (D75).
const DAY_LENGTH_MINUTES: float = 24.0

var clock: GameClock = GameClock.new()
## Permite pausar el tiempo (por ejemplo, en menús) sin tocar nada más.
var clock_running: bool = true
## Multiplicador de la velocidad del tiempo: 1.0 = normal. Sirve para depurar y, más
## adelante, para comprimir el tiempo en viajes largos.
var time_scale: float = 1.0
## Niveles de las estaciones y flujos permanentes. Cada Station se registra al empezar.
var production: ProductionModel

var _hours_per_second: float = 0.0


func _ready() -> void:
	_hours_per_second = GameClock.hours_per_real_second(DAY_LENGTH_MINUTES)
	# El reloj no conoce al EventBus (es lógica pura): GameState hace de puente.
	clock.day_started.connect(_on_day_started)
	clock.time_advanced.connect(_on_time_advanced)
	reset_production()
	EventBus.station_level_changed.connect(_on_station_level_changed)


func _process(delta: float) -> void:
	if clock_running:
		clock.advance(delta * _hours_per_second * time_scale)


## Empieza un modelo de producción vacío (partida nueva, pruebas). Las estaciones de la escena
## tienen que volver a registrarse (Station lo hace en su _ready).
func reset_production() -> void:
	if production != null and production.level_changed.is_connected(_on_production_level_changed):
		production.level_changed.disconnect(_on_production_level_changed)
	production = ProductionModel.new()
	production.connection_check = _are_connected
	production.level_changed.connect(_on_production_level_changed)


func _on_day_started(day: int) -> void:
	# Primero el modelo, así quien escucha day_started ya ve los niveles del día nuevo.
	production.advance_day()
	EventBus.day_started.emit(day)


# Sin red en la escena, todo cuenta como conectado (pruebas sin vías).
func _are_connected(from: StringName, to: StringName) -> bool:
	var network: RailNetwork = RailNetwork.find_in(get_tree())
	return network == null or network.are_connected(from, to)


func _on_production_level_changed(station_id: StringName, level: int) -> void:
	EventBus.station_level_changed.emit(station_id, level)


# Un nivel cambiado desde la escena (Station.set_level) se copia al modelo sin reavisarlo.
func _on_station_level_changed(station_id: StringName, level: int) -> void:
	production.set_level(station_id, level, false)


func _on_time_advanced(hours: float) -> void:
	EventBus.time_advanced.emit(hours)
