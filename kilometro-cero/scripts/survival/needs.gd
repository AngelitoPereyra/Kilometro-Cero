class_name Needs
extends Node
## Necesidades del jugador: agua, comida y fatiga, de 0 a 100.
## Agua y comida bajan con el tiempo de juego; la fatiga sube (0 = descansado, 100 = agotado).
## Escucha `time_advanced` del EventBus: el mate, el sueño o un desmayo gastan necesidades
## por el mismo camino que el paso normal del tiempo.
## NO decide qué pasa al desmayarse: avisa con `fainted` y quien tiene cuerpo (Player) reacciona.

## Se emite una sola vez cuando una necesidad llega al límite. Puede volver a emitirse
## recién después de `recover_from_faint()`.
signal fainted(cause: StringName)

const WATER: StringName = &"water"
const FOOD: StringName = &"food"
const FATIGUE: StringName = &"fatigue"
const MAX_VALUE: float = 100.0

@export var config: NeedsConfig
## En pausa, el paso del tiempo no gasta necesidades (por ejemplo, mientras está desmayado).
var paused: bool = false

## Multiplica la fatiga que se acumula con el paso del tiempo. Lo escribe quien conoce la
## carga (Player, a partir de Encumbrance): 1.0 = normal, 2.0 = se cansa el doble.
## No afecta a `change()`: el esfuerzo puntual (empujar la zorra) lo calcula quien lo causa.
var fatigue_multiplier: float = 1.0:
	set(value):
		fatigue_multiplier = maxf(value, 0.0)

var _values: Dictionary[StringName, float] = {}
# Sin este "cerrojo" emitiríamos `fainted` en cada cambio mientras la necesidad siga en el límite.
var _faint_latched: bool = false


## Causa del desmayo para esos valores, o &"" si no hay ninguna. Lógica pura.
## Con varias causas a la vez, el orden de prioridad es agua, comida, fatiga.
static func faint_cause(water: float, food: float, fatigue: float) -> StringName:
	if water <= 0.0:
		return WATER
	if food <= 0.0:
		return FOOD
	if fatigue >= MAX_VALUE:
		return FATIGUE
	return &""


func _ready() -> void:
	if config == null:
		push_warning("Needs no tiene un NeedsConfig asignado: se usan los valores por defecto.")
		config = NeedsConfig.new()
	_values[WATER] = config.start_water
	_values[FOOD] = config.start_food
	_values[FATIGUE] = config.start_fatigue
	EventBus.time_advanced.connect(_on_time_advanced)


func get_value(need: StringName) -> float:
	if not _values.has(need):
		push_error("Necesidad desconocida: %s" % need)
		return 0.0
	return _values[need]


## Suma `delta` (puede ser negativo) a una necesidad, limitada a 0–100.
## También es el punto de entrada del esfuerzo: empujar la zorra o cargar de más
## llamarán a esta función para subir la fatiga.
func change(need: StringName, delta: float) -> void:
	if not _values.has(need):
		push_error("Necesidad desconocida: %s" % need)
		return
	var old_value: float = _values[need]
	var new_value: float = clampf(old_value + delta, 0.0, MAX_VALUE)
	if is_equal_approx(new_value, old_value):
		return
	_values[need] = new_value
	EventBus.need_changed.emit(need, new_value)
	_check_faint()


## Paso del tiempo: gasta agua y comida y suma fatiga según las tasas de NeedsConfig.
func tick(hours: float) -> void:
	if paused or hours <= 0.0:
		return
	change(WATER, -config.water_loss_per_hour * hours)
	change(FOOD, -config.food_loss_per_hour * hours)
	change(FATIGUE, config.fatigue_gain_per_hour * fatigue_multiplier * hours)


## Al dormir en un refugio.
func restore_fatigue() -> void:
	change(FATIGUE, -MAX_VALUE)


## Al despertar de un desmayo: alguien nos dio de comer y beber y descansamos un poco.
## Sube agua y comida hasta el piso y baja la fatiga hasta el techo de NeedsConfig. Así no
## despertamos en el límite y desmayándonos otra vez en el mismo instante.
func recover_from_faint() -> void:
	change(WATER, maxf(0.0, config.faint_recovery_value - get_value(WATER)))
	change(FOOD, maxf(0.0, config.faint_recovery_value - get_value(FOOD)))
	change(FATIGUE, minf(0.0, config.faint_recovery_fatigue - get_value(FATIGUE)))
	_faint_latched = false


func _on_time_advanced(hours: float) -> void:
	tick(hours)


func _check_faint() -> void:
	if _faint_latched:
		return
	var cause: StringName = faint_cause(_values[WATER], _values[FOOD], _values[FATIGUE])
	if cause == &"":
		return
	_faint_latched = true
	fainted.emit(cause)
