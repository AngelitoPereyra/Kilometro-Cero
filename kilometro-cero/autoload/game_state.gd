extends Node
## Estado de la partida. Es dueño del reloj del juego (D34).
## Los demás datos (dinero, IRR, niveles de estación) entran cuando un sistema los necesite.

## Minutos reales que dura un día de juego (D34). Vivía en NeedsConfig, que se borró (D75).
const DAY_LENGTH_MINUTES: float = 24.0

var clock: GameClock = GameClock.new()
## Permite pausar el tiempo (por ejemplo, en menús) sin tocar nada más.
var clock_running: bool = true
## Multiplicador de la velocidad del tiempo: 1.0 = normal. Sirve para depurar y, más
## adelante, para comprimir el tiempo en viajes largos.
var time_scale: float = 1.0

var _hours_per_second: float = 0.0


func _ready() -> void:
	_hours_per_second = GameClock.hours_per_real_second(DAY_LENGTH_MINUTES)
	# El reloj no conoce al EventBus (es lógica pura): GameState hace de puente.
	clock.day_started.connect(_on_day_started)
	clock.time_advanced.connect(_on_time_advanced)


func _process(delta: float) -> void:
	if clock_running:
		clock.advance(delta * _hours_per_second * time_scale)


func _on_day_started(day: int) -> void:
	EventBus.day_started.emit(day)


func _on_time_advanced(hours: float) -> void:
	EventBus.time_advanced.emit(hours)
