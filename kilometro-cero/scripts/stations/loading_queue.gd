class_name LoadingQueue
extends RefCounted
## Lo que un punto de carga (LoadingBay, tarea 62.9a, D125) tiene que cargar en los vagones o
## sacar de ellos. Lógica pura: los vagones se los pasa quien llama en cada `work`.
## Cada vagón tarda HOURS_PER_WAGON horas de juego en llenarse entero, así que una unidad tarda
## HOURS_PER_WAGON / capacidad del vagón (una plataforma de 20: 1,5 minutos por tronco).
## Primero descarga (deja lugar) y después carga, de a una unidad, en el orden en que se pidió.
## Lo que falta cargar espera aunque no haya vagones (ya está pago); lo que falta descargar y ya
## no está en ningún vagón (el tren se fue) se anula.

const HOURS_PER_WAGON: float = 0.5
# Margen para que media hora justa cargue el vagón entero (la suma de flotantes no da exacta).
const EPSILON: float = 0.000001

# id de objeto -> unidades que faltan cargar (en el orden en que se pidieron).
var _loads: Dictionary[StringName, int] = {}
var _items: Dictionary[StringName, ItemData] = {}
# id de objeto -> unidades que faltan descargar.
var _unloads: Dictionary[StringName, int] = {}
# Horas acumuladas que todavía no alcanzaron para mover una unidad.
var _hours: float = 0.0


func add_load(item: ItemData, amount: int) -> void:
	if item == null or amount <= 0:
		return
	_items[item.id] = item
	_loads[item.id] = _loads.get(item.id, 0) + amount


func add_unload(item_id: StringName, amount: int) -> void:
	if amount <= 0:
		return
	_unloads[item_id] = _unloads.get(item_id, 0) + amount


func get_loads() -> Dictionary[StringName, int]:
	return _loads.duplicate()


func get_unloads() -> Dictionary[StringName, int]:
	return _unloads.duplicate()


func get_item(item_id: StringName) -> ItemData:
	return _items.get(item_id)


func pending_load_total() -> int:
	var total: int = 0
	for item_id: StringName in _loads:
		total += _loads[item_id]
	return total


func pending_unload_of(item_id: StringName) -> int:
	return _unloads.get(item_id, 0)


func has_work() -> bool:
	return not _loads.is_empty() or not _unloads.is_empty()


## Horas que tarda una unidad en ese vagón.
static func unit_hours(cargo: StorageContainer) -> float:
	return HOURS_PER_WAGON / float(maxi(1, cargo.capacity))


## Horas que faltan, más o menos, con estos vagones (con el primero como medida; 0 sin trabajo o
## sin vagones).
func hours_left(cargos: Array[StorageContainer]) -> float:
	if cargos.is_empty() or not has_work():
		return 0.0
	var units: int = pending_load_total()
	for item_id: StringName in _unloads:
		units += _unloads[item_id]
	return maxf(0.0, units * unit_hours(cargos[0]) - _hours)


## Avanza `hours` horas de juego con estos vagones. Devuelve {"loaded": {id: unidades},
## "unloaded": {id: unidades}} con lo que se movió.
func work(cargos: Array[StorageContainer], hours: float) -> Dictionary:
	var loaded: Dictionary[StringName, int] = {}
	var unloaded: Dictionary[StringName, int] = {}
	var result: Dictionary = {"loaded": loaded, "unloaded": unloaded}
	if not has_work():
		_hours = 0.0
		return result
	_hours += maxf(0.0, hours)
	while true:
		var step: Array = _next_step(cargos)
		if step.is_empty():
			# Nada se puede mover ahora: el tiempo de espera no se guarda.
			_hours = 0.0
			break
		var unloading: bool = step[0]
		var item_id: StringName = step[1]
		var cargo: StorageContainer = step[2]
		var unit: float = unit_hours(cargo)
		if _hours + EPSILON < unit:
			break
		_hours = maxf(0.0, _hours - unit)
		if unloading:
			if _take_one(cargo, item_id):
				unloaded[item_id] = unloaded.get(item_id, 0) + 1
			_reduce(_unloads, item_id)
		else:
			if cargo.try_store(ItemStack.new(_items[item_id], 1)) == null:
				loaded[item_id] = loaded.get(item_id, 0) + 1
			_reduce(_loads, item_id)
		if not has_work():
			_hours = 0.0
			break
	return result


## Para guardar la partida (todavía no se guarda, tarea 65).
func to_dict() -> Dictionary:
	return {"loads": _loads.duplicate(), "unloads": _unloads.duplicate()}


# [descarga (bool), id de objeto, vagón] de la próxima unidad, o [] si no se puede mover nada.
func _next_step(cargos: Array[StorageContainer]) -> Array:
	for item_id: StringName in _unloads.keys():
		for cargo: StorageContainer in cargos:
			if cargo.count_of(item_id) > 0:
				return [true, item_id, cargo]
		# Ya no está en ningún vagón: esa venta se anula.
		_unloads.erase(item_id)
	for item_id: StringName in _loads:
		var probe := ItemStack.new(_items[item_id], 1)
		for cargo: StorageContainer in cargos:
			if cargo.can_store_amount(probe) > 0:
				return [false, item_id, cargo]
	return []


static func _take_one(cargo: StorageContainer, item_id: StringName) -> bool:
	for index: int in range(cargo.get_stack_count() - 1, -1, -1):
		if cargo.peek(index).item.id == item_id:
			return cargo.take(index, 1) != null
	return false


static func _reduce(amounts: Dictionary[StringName, int], item_id: StringName) -> void:
	var left: int = amounts.get(item_id, 0) - 1
	if left > 0:
		amounts[item_id] = left
	else:
		amounts.erase(item_id)
