class_name ProductionModel
extends RefCounted
## Modelo de producción y consumo (D79, tarea 57). Lógica pura: no sabe de escenas ni del
## reloj. Guarda el nivel de cada estación y los flujos permanentes, y avanza de a un día
## (advance_day). GameState es dueño de una instancia, la avanza en cada día nuevo y reemite
## sus cambios de nivel por EventBus.station_level_changed.
## Un día:
## 1. Cada estación produce según su nivel (StationData.get_production).
## 2. La producción se reparte entre los flujos que salen de ella, del más viejo al más nuevo;
##    un flujo cuyo camino está cortado no entrega ni ocupa producción ese día.
## 3. Una estación con todo su consumo cubierto (StationData.get_consumption, que incluye lo que
##    le falta para crecer) suma un día; al juntar los días del nivel
##    (StationData.get_days_to_grow) sube de nivel y nace el consumo nuevo.
## 4. Nada decrece: un día sin cubrir no suma ni resta (estancamiento).
## Lo que la producción no manda por flujos queda libre (get_free_production) para el mercado y
## las misiones (tareas 58 y 59).
## Desde la tarea 58 una estación puede tener producción extra permanente (add_production_bonus),
## la recompensa de las misiones secundarias (por ejemplo, reabrir una cantera vieja).

## Una estación subió (o se le cambió) de nivel.
signal level_changed(station_id: StringName, level: int)
signal flow_added(flow: ProductionFlow)
signal flow_removed(flow: ProductionFlow)
## Terminó de simular un día.
signal day_processed()

## Si dos estaciones están conectadas: func(from: StringName, to: StringName) -> bool. Vacío,
## todo está conectado (GameState le pone la consulta a RailNetwork).
var connection_check: Callable = Callable()

# station_id -> StationData. El orden de registro es el orden en que se procesan.
var _data: Dictionary[StringName, StationData] = {}
# station_id -> nivel. Puede tener estaciones sin datos todavía (cargadas de un guardado).
var _levels: Dictionary[StringName, int] = {}
# station_id -> días cubiertos juntados para crecer desde el nivel actual.
var _progress: Dictionary[StringName, int] = {}
var _flows: Array[ProductionFlow] = []
var _next_flow_id: int = 1
# station_id -> (id de objeto -> unidades por día de más). Puede tener estaciones sin datos.
var _bonus: Dictionary[StringName, Dictionary] = {}


## Registra una estación. Si el modelo ya la conocía (otra escena, un guardado) conserva su
## nivel; si no, empieza en `level`. Devuelve el nivel con el que queda.
func add_station(data: StationData, level: int = 1) -> int:
	if data == null or data.id == &"":
		push_warning("ProductionModel: estación sin datos o sin id.")
		return 1
	_data[data.id] = data
	var start: int = _levels.get(data.id, level)
	_levels[data.id] = data.clamp_level(start)
	if not _progress.has(data.id):
		_progress[data.id] = 0
	return _levels[data.id]


func has_station(station_id: StringName) -> bool:
	return _data.has(station_id)


func get_station_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_data.keys())
	return ids


func get_data(station_id: StringName) -> StationData:
	return _data.get(station_id)


## Olvida todo (estaciones, niveles y flujos).
func clear() -> void:
	_data.clear()
	_levels.clear()
	_progress.clear()
	_flows.clear()
	_next_flow_id = 1
	_bonus.clear()


func get_level(station_id: StringName) -> int:
	return _levels.get(station_id, 1)


## Cambia el nivel a mano (limitado a los datos) y vuelve a contar los días desde cero.
## `notify` en false no emite level_changed (para copiar un cambio que ya se avisó).
## Devuelve false si quedó igual o si no conoce la estación.
func set_level(station_id: StringName, level: int, notify: bool = true) -> bool:
	var data: StationData = get_data(station_id)
	if data == null:
		return false
	var clamped: int = data.clamp_level(level)
	if clamped == get_level(station_id):
		return false
	_levels[station_id] = clamped
	_progress[station_id] = 0
	if notify:
		level_changed.emit(station_id, clamped)
	return true


## Días cubiertos que ya juntó para crecer.
func get_growth_progress(station_id: StringName) -> int:
	return _progress.get(station_id, 0)


## Días cubiertos que necesita para crecer desde su nivel (0 si ya no crece).
func get_days_to_grow(station_id: StringName) -> int:
	var data: StationData = get_data(station_id)
	if data == null or not data.can_grow(get_level(station_id)):
		return 0
	return data.get_days_to_grow(get_level(station_id))


## Producción por día en su nivel actual más la extra (id de objeto -> unidades).
func get_production(station_id: StringName) -> Dictionary[StringName, int]:
	var data: StationData = get_data(station_id)
	if data == null:
		return {}
	var result: Dictionary[StringName, int] = data.get_production(get_level(station_id))
	var bonus: Dictionary = _bonus.get(station_id, {})
	for item_id: StringName in bonus:
		result[item_id] = result.get(item_id, 0) + int(bonus[item_id])
	return result


## Suma producción permanente a una estación (tarea 58: recompensa de misiones secundarias).
## Se acumula y se guarda. Devuelve false si la cantidad no sirve.
func add_production_bonus(station_id: StringName, item_id: StringName, amount: int) -> bool:
	if station_id == &"" or item_id == &"" or amount < 1:
		push_warning("ProductionModel: producción extra inválida (%d %s a '%s')." % [amount, item_id, station_id])
		return false
	var bonus: Dictionary = _bonus.get(station_id, {})
	bonus[item_id] = int(bonus.get(item_id, 0)) + amount
	_bonus[station_id] = bonus
	return true


## La producción extra de una estación (id de objeto -> unidades por día).
func get_production_bonus(station_id: StringName) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	var bonus: Dictionary = _bonus.get(station_id, {})
	for item_id: StringName in bonus:
		result[item_id] = int(bonus[item_id])
	return result


## Consumo por día en su nivel actual (lo cubierto más lo que pide para crecer).
func get_consumption(station_id: StringName) -> Dictionary[StringName, int]:
	var data: StationData = get_data(station_id)
	return data.get_consumption(get_level(station_id)) if data != null else {}


# --- Flujos ---


## Crea un flujo permanente de `amount` unidades por día. Devuelve null si los datos no sirven
## (estación desconocida, la misma estación, sin objeto o cantidad menor a 1). No exige que
## alcance la producción: si no alcanza, el flujo nuevo recibe lo que dejan los más viejos.
## `round_trip`: flujo de pasajeros que va y vuelve (tarea 60b).
func add_flow(from: StringName, to: StringName, item_id: StringName, amount: int, round_trip: bool = false) -> ProductionFlow:
	if not has_station(from) or not has_station(to) or from == to or item_id == &"" or amount < 1:
		push_warning("ProductionModel: flujo inválido (%d %s de '%s' a '%s')." % [amount, item_id, from, to])
		return null
	var flow := ProductionFlow.new(from, to, item_id, amount)
	flow.id = _next_flow_id
	flow.round_trip = round_trip
	_next_flow_id += 1
	_flows.append(flow)
	flow_added.emit(flow)
	return flow


func remove_flow(flow: ProductionFlow) -> bool:
	if not _flows.has(flow):
		return false
	_flows.erase(flow)
	flow_removed.emit(flow)
	return true


## Todos los flujos, del más viejo al más nuevo.
func get_flows() -> Array[ProductionFlow]:
	return _flows.duplicate()


func get_flows_from(station_id: StringName) -> Array[ProductionFlow]:
	var result: Array[ProductionFlow] = []
	for flow: ProductionFlow in _flows:
		if flow.from_station == station_id:
			result.append(flow)
	return result


func get_flows_to(station_id: StringName) -> Array[ProductionFlow]:
	var result: Array[ProductionFlow] = []
	for flow: ProductionFlow in _flows:
		if flow.to_station == station_id:
			result.append(flow)
	return result


## La producción que no está comprometida en flujos (cuenta también los flujos cortados, que
## vuelven a pedir lo suyo al repararse). Es lo que puede pedir una misión nueva.
func get_free_production(station_id: StringName) -> Dictionary[StringName, int]:
	var free: Dictionary[StringName, int] = get_production(station_id)
	for flow: ProductionFlow in get_flows_from(station_id):
		if free.has(flow.item_id):
			free[flow.item_id] = maxi(0, free[flow.item_id] - flow.amount)
	return free


## Lo que los flujos le prometen por día a una estación, entreguen o no hoy (cortados o sin
## producción suficiente también cuentan). Lo que el consumo pide por encima de esto es lo que
## piden las misiones principales (tarea 58).
func get_committed_supply(station_id: StringName) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	for flow: ProductionFlow in get_flows_to(station_id):
		result[flow.item_id] = result.get(flow.item_id, 0) + flow.amount
	return result


## El consumo que ningún flujo tiene comprometido (id de objeto -> unidades por día).
func get_uncommitted_needs(station_id: StringName) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	var committed: Dictionary[StringName, int] = get_committed_supply(station_id)
	var consumption: Dictionary[StringName, int] = get_consumption(station_id)
	for item_id: StringName in consumption:
		var lacking: int = consumption[item_id] - committed.get(item_id, 0)
		if lacking > 0:
			result[item_id] = lacking
	return result


## Si dos estaciones están conectadas según connection_check (sin consulta, siempre).
func are_connected(from: StringName, to: StringName) -> bool:
	return not connection_check.is_valid() or bool(connection_check.call(from, to))


## Si el camino del flujo está abierto hoy.
func is_flow_connected(flow: ProductionFlow) -> bool:
	return are_connected(flow.from_station, flow.to_station)


## Lo que entregaría cada flujo si el día se simulara ahora: flow.id -> unidades.
func plan_deliveries() -> Dictionary[int, int]:
	var plan: Dictionary[int, int] = {}
	# station_id -> lo que le queda de producción por objeto.
	var remaining: Dictionary = {}
	for flow: ProductionFlow in _flows:
		if not remaining.has(flow.from_station):
			remaining[flow.from_station] = get_production(flow.from_station)
		var left: Dictionary = remaining[flow.from_station]
		var amount: int = 0
		if is_flow_connected(flow):
			amount = mini(flow.amount, left.get(flow.item_id, 0))
			if amount > 0:
				left[flow.item_id] -= amount
		plan[flow.id] = amount
	return plan


## Lo que le llega por día a la estación con los flujos de hoy (id de objeto -> unidades).
func get_supply(station_id: StringName) -> Dictionary[StringName, int]:
	return _supply_from(plan_deliveries(), station_id)


## Lo que le falta por día para cubrir todo su consumo (vacío si está cubierta).
func get_missing(station_id: StringName) -> Dictionary[StringName, int]:
	return _missing_from(get_supply(station_id), station_id)


func is_covered(station_id: StringName) -> bool:
	return get_missing(station_id).is_empty()


## Si está cubierta y todavía puede crecer (no estancada).
func is_growing(station_id: StringName) -> bool:
	return get_days_to_grow(station_id) > 0 and is_covered(station_id)


# --- Simulación ---


## Simula un día: entrega los flujos, suma días a las estaciones cubiertas y las hace crecer.
## Primero actualiza todo y después avisa, así quien escucha ve el modelo entero ya al día.
func advance_day() -> void:
	var plan: Dictionary[int, int] = plan_deliveries()
	for flow: ProductionFlow in _flows:
		flow.last_delivered = plan.get(flow.id, 0)
	var grown: Array[StringName] = []
	for station_id: StringName in _data:
		var needed: int = get_days_to_grow(station_id)
		if needed <= 0 or not _missing_from(_supply_from(plan, station_id), station_id).is_empty():
			continue
		_progress[station_id] = get_growth_progress(station_id) + 1
		if _progress[station_id] >= needed:
			_levels[station_id] = get_level(station_id) + 1
			_progress[station_id] = 0
			grown.append(station_id)
	for station_id: StringName in grown:
		level_changed.emit(station_id, get_level(station_id))
	day_processed.emit()


## Simula `days` días seguidos.
func advance_days(days: int) -> void:
	for i: int in days:
		advance_day()


# --- Guardado (tarea 65) ---


func to_dict() -> Dictionary:
	var levels: Dictionary = {}
	for station_id: StringName in _levels:
		levels[String(station_id)] = _levels[station_id]
	var progress: Dictionary = {}
	for station_id: StringName in _progress:
		progress[String(station_id)] = _progress[station_id]
	var flows: Array = []
	for flow: ProductionFlow in _flows:
		flows.append(flow.to_dict())
	var bonus: Dictionary = {}
	for station_id: StringName in _bonus:
		var items: Dictionary = {}
		for item_id: StringName in _bonus[station_id]:
			items[String(item_id)] = _bonus[station_id][item_id]
		bonus[String(station_id)] = items
	return {"levels": levels, "progress": progress, "flows": flows, "next_flow_id": _next_flow_id, "bonus": bonus}


## Carga niveles, días, flujos y producción extra. Las estaciones (sus datos) se vuelven a registrar con
## add_station, que respeta el nivel cargado.
func load_dict(values: Dictionary) -> void:
	_levels.clear()
	_progress.clear()
	_flows.clear()
	_bonus.clear()
	for key: String in values.get("levels", {}):
		_levels[StringName(key)] = int(values["levels"][key])
	for key: String in values.get("progress", {}):
		_progress[StringName(key)] = int(values["progress"][key])
	var saved_bonus: Dictionary = values.get("bonus", {})
	for key: String in saved_bonus:
		var items: Dictionary = {}
		for item_key: String in saved_bonus[key]:
			items[StringName(item_key)] = int(saved_bonus[key][item_key])
		_bonus[StringName(key)] = items
	for entry: Dictionary in values.get("flows", []):
		_flows.append(ProductionFlow.from_dict(entry))
	_next_flow_id = int(values.get("next_flow_id", 1))
	for flow: ProductionFlow in _flows:
		_next_flow_id = maxi(_next_flow_id, flow.id + 1)
	for station_id: StringName in _data:
		_levels[station_id] = _data[station_id].clamp_level(_levels.get(station_id, 1))
		if not _progress.has(station_id):
			_progress[station_id] = 0


func _supply_from(plan: Dictionary[int, int], station_id: StringName) -> Dictionary[StringName, int]:
	var supply: Dictionary[StringName, int] = {}
	for flow: ProductionFlow in _flows:
		var amount: int = plan.get(flow.id, 0)
		if flow.to_station == station_id and amount > 0:
			supply[flow.item_id] = supply.get(flow.item_id, 0) + amount
	return supply


func _missing_from(supply: Dictionary[StringName, int], station_id: StringName) -> Dictionary[StringName, int]:
	var missing: Dictionary[StringName, int] = {}
	var consumption: Dictionary[StringName, int] = get_consumption(station_id)
	for item_id: StringName in consumption:
		var lacking: int = consumption[item_id] - supply.get(item_id, 0)
		if lacking > 0:
			missing[item_id] = lacking
	return missing
