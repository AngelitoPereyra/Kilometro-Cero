class_name Health
extends Node
## Salud del jugador (tarea 62c.3h, D143): lo único que vuelve de la supervivencia (D75). Va de 0 a
## `max_health`, baja despacio con las horas de juego (`decay_per_hour`) y con las cornadas de los
## jabalíes, y solo se recupera comiendo (Eater). Dormir no cura. En 0 no se muere: avisa `depleted`
## y el Sleeper desmaya al jugador (despierta en la última cama con `faint_health`).
## Hijo directo de Player (nodo "Salud"). Reemite sus cambios por EventBus.health_changed.

signal changed(value: float, max_value: float)
## Llegó a 0 (una vez por caída: vuelve a avisar recién después de subir).
signal depleted

@export_range(1.0, 1000.0, 1.0) var max_health: float = 100.0
## Cuánto baja por hora de juego (1: unos 4 días sin comer hasta 0).
@export_range(0.0, 20.0, 0.1) var decay_per_hour: float = 1.0
## Con cuánto despierta después de desmayarse.
@export_range(1.0, 1000.0, 1.0) var faint_health: float = 30.0
## false: el tiempo no la baja (pruebas, menús).
@export var decays: bool = true

var value: float = 100.0

var _depleted_sent: bool = false


## Cuánto queda después de `hours` horas, sin bajar de 0. Lógica pura.
static func after_hours(current: float, hours: float, decay: float) -> float:
	if hours <= 0.0:
		return current
	return maxf(current - hours * decay, 0.0)


## Lo que suma una comida sin pasar del máximo. Lógica pura.
static func healed(current: float, amount: float, maximum: float) -> float:
	return clampf(current + maxf(amount, 0.0), 0.0, maximum)


## "▮▮▮▮▮▮▮▯▯▯" con `cells` celdas. Lógica pura (HUD).
static func bar_text(current: float, maximum: float, cells: int = 10) -> String:
	var full: int = clampi(ceili(current / maxf(maximum, 1.0) * float(cells) - 0.001), 0, cells)
	return "▮".repeat(full) + "▯".repeat(cells - full)


func _ready() -> void:
	value = max_health
	EventBus.time_advanced.connect(_on_time_advanced)


func get_ratio() -> float:
	return value / maxf(max_health, 1.0)


func is_full() -> bool:
	return value >= max_health - 0.001


func is_depleted() -> bool:
	return value <= 0.0


## Resta salud (una cornada). Devuelve lo que quedó.
func damage(amount: float) -> float:
	if amount > 0.0:
		_apply(maxf(value - amount, 0.0))
	return value


## Suma salud (comer). Devuelve cuánto subió de verdad.
func heal(amount: float) -> float:
	var before: float = value
	_apply(healed(value, amount, max_health))
	return value - before


## Pone un valor (despertar del desmayo, pruebas).
func set_value(new_value: float) -> void:
	_apply(clampf(new_value, 0.0, max_health))


func _on_time_advanced(hours: float) -> void:
	if decays and hours > 0.0:
		_apply(after_hours(value, hours, decay_per_hour))


func _apply(new_value: float) -> void:
	if is_equal_approx(new_value, value) and not (new_value <= 0.0 and not _depleted_sent):
		return
	value = new_value
	changed.emit(value, max_health)
	EventBus.health_changed.emit(value)
	if value > 0.0:
		_depleted_sent = false
	elif not _depleted_sent:
		_depleted_sent = true
		depleted.emit()
