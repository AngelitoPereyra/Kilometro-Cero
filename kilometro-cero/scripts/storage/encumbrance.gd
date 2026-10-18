class_name Encumbrance
extends Node
## Peso total contra capacidad de quien carga (el jugador, un vehículo). Es lógica pura:
## no dibuja nada ni conoce a Needs ni al movimiento. Avisa con `ratio_changed` y quien
## se ve afectado (Player) aplica los multiplicadores (D20).
## El peso llega por "fuentes" con nombre (manos, mochila, vehículo...): cada una informa su
## peso con set_load(), o se engancha a un StorageContainer con track_container().
## Sumar una fuente nueva no obliga a tocar esta clase.
## Hay que agregarlo al árbol antes de usarlo: carga su configuración en _ready().

## Se emite solo cuando el cociente peso / capacidad cambia.
signal ratio_changed(ratio: float)

@export var config: CarryConfig

var _loads: Dictionary[StringName, float] = {}
var _capacity_bonuses: Dictionary[StringName, float] = {}
var _ratio: float = 0.0


## Peso sobre capacidad. Con capacidad 0, cualquier peso es "infinito" y sin peso es 0.
static func compute_ratio(total_weight: float, capacity: float) -> float:
	if capacity <= 0.0:
		return INF if total_weight > 0.0 else 0.0
	return total_weight / capacity


func _ready() -> void:
	if config == null:
		push_warning("Encumbrance no tiene un CarryConfig asignado: se usan los valores por defecto.")
		config = CarryConfig.new()


## Informa el peso actual de una fuente. Volver a informarla reemplaza su peso, no lo suma.
func set_load(source_id: StringName, kilograms: float) -> void:
	_loads[source_id] = maxf(kilograms, 0.0)
	_refresh()


func clear_load(source_id: StringName) -> void:
	_loads.erase(source_id)
	_refresh()


## Capacidad extra que aporta una fuente (por ejemplo, una mochila). Con 0 se quita.
func set_capacity_bonus(source_id: StringName, kilograms: float) -> void:
	if kilograms > 0.0:
		_capacity_bonuses[source_id] = kilograms
	else:
		_capacity_bonuses.erase(source_id)
	_refresh()


## Engancha un contenedor como fuente de peso: toma su peso actual y lo actualiza solo
## cada vez que algo entra o sale.
func track_container(source_id: StringName, container: StorageContainer) -> void:
	if container == null:
		push_error("Encumbrance.track_container necesita un StorageContainer.")
		return
	# bind agrega los argumentos al final de los que trae la señal (el ItemStack).
	container.item_stored.connect(_on_container_changed.bind(source_id, container))
	container.item_taken.connect(_on_container_changed.bind(source_id, container))
	set_load(source_id, container.get_total_weight())


func get_total_weight() -> float:
	var total: float = 0.0
	for kilograms: float in _loads.values():
		total += kilograms
	return total


## Capacidad total: la base más el aporte de cada mochila.
func get_capacity() -> float:
	var total: float = config.base_capacity
	for kilograms: float in _capacity_bonuses.values():
		total += kilograms
	return total


## Peso total / capacidad (1.0 = justo al límite sin penalización).
func get_ratio() -> float:
	return _ratio


func get_speed_multiplier() -> float:
	return config.speed_multiplier(_ratio)


func get_fatigue_multiplier() -> float:
	return config.fatigue_multiplier(_ratio)


## Si se puede sumar `extra_weight` sin pasar el tope de la configuración (150 %).
## Levantar nada, o soltar (peso negativo), siempre se puede.
func can_pick_up(extra_weight: float) -> bool:
	if extra_weight <= 0.0:
		return true
	return config.can_carry(compute_ratio(get_total_weight() + extra_weight, get_capacity()))


## Cuántos kilos más se pueden levantar hasta el tope. Nunca es negativo.
## Sirve para recoger una parte de una pila cuando no entra entera.
func get_pickup_room() -> float:
	return maxf(get_capacity() * config.max_ratio - get_total_weight(), 0.0)


func _on_container_changed(_stack: ItemStack, source_id: StringName, container: StorageContainer) -> void:
	set_load(source_id, container.get_total_weight())


func _refresh() -> void:
	var new_ratio: float = compute_ratio(get_total_weight(), get_capacity())
	if is_equal_approx(new_ratio, _ratio):
		return
	_ratio = new_ratio
	ratio_changed.emit(_ratio)
