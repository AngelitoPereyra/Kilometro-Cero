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
## Un flujo recién nacido puede empezar el día siguiente (ProductionFlow.pending, tarea 62.4):
## se activa al principio del próximo advance_day, antes de repartir, y ese día ya entrega.
## Lo que la producción no manda por flujos queda libre (get_free_production) para el mercado y
## las misiones (tareas 58 y 59).
## Desde la tarea 58 una estación puede tener producción extra permanente (add_production_bonus),
## la recompensa de las misiones secundarias (por ejemplo, reabrir una cantera vieja).
## Población (tarea 62b.1, D129 y D132): cada estación tiene familias y cada familia un oficio
## (OccupationData). Las familias del cupo de cada nivel (StationLevelData.families) llegan solas
## al registrar la estación o al subir de nivel y toman oficio según el bioma y los rasgos
## (assign_occupation); el jugador agrega pocas (add_player_family, con tope por tipo). La
## producción de la estación suma la de sus familias y su consumo suma los insumos de todas.
## Una familia sin todos sus insumos no produce. Los insumos se toman primero de lo que llega
## por flujos y después de la producción propia que no se llevan los flujos; antes que las
## familias come el consumo del nivel. Como un oficio que trabaja puede alimentar a otro (en la
## misma estación o en otra por un flujo), el día se resuelve en rondas hasta que ninguna familia
## cambia (_solve).

## Una estación subió (o se le cambió) de nivel.
signal level_changed(station_id: StringName, level: int)
signal flow_added(flow: ProductionFlow)
signal flow_removed(flow: ProductionFlow)
## Terminó de simular un día.
signal day_processed()
## Llegó una familia con oficio a una estación (tarea 62b.1). `origin` es un FamilyOrigin.
signal family_added(station_id: StringName, occupation: OccupationData, origin: int)

## De dónde salió una familia: el cupo de un nivel, otra cosa del juego (la recompensa de una
## misión) o el jugador (mudanza, cuenta para el tope de D129).
enum FamilyOrigin { LEVEL, EXTRA, PLAYER }

## Lo que resuelve un día (_solve): producción con las familias que trabajan, reparto entre
## flujos, lo que llega, lo propio que se usa y qué familias trabajan.
class DaySolution:
	var plan: Dictionary[int, int] = {}
	## station_id -> Dictionary[StringName, int]
	var production: Dictionary = {}
	## station_id -> Dictionary[StringName, int]
	var supply: Dictionary = {}
	## station_id -> Dictionary[StringName, int]: producción propia que se come la estación.
	var local_use: Dictionary = {}
	## station_id -> Array de bool, uno por familia en orden: si trabaja.
	var active: Dictionary = {}

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
# occupation_id -> OccupationData: los oficios conocidos (los del bioma de cada estación se suman
# solos; los que habilita un rasgo hay que registrarlos con add_occupation).
var _occupations: Dictionary[StringName, OccupationData] = {}
# station_id -> familias en orden de llegada: {"occupation": StringName, "origin": FamilyOrigin}.
# Puede tener estaciones sin datos todavía (cargadas de un guardado).
var _families: Dictionary[StringName, Array] = {}


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
	if data.biome != null:
		for occupation: OccupationData in data.biome.get_occupations():
			add_occupation(occupation)
	_fill_families(data.id)
	return _levels[data.id]


func has_station(station_id: StringName) -> bool:
	return _data.has(station_id)


func get_station_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_data.keys())
	return ids


func get_data(station_id: StringName) -> StationData:
	return _data.get(station_id)


## Olvida todo (estaciones, niveles, flujos y familias). Los oficios registrados quedan: son
## definiciones, no estado.
func clear() -> void:
	_data.clear()
	_levels.clear()
	_progress.clear()
	_flows.clear()
	_next_flow_id = 1
	_bonus.clear()
	_families.clear()


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
	var added: Array[OccupationData] = _fill_families(station_id)
	if notify:
		level_changed.emit(station_id, clamped)
		_emit_families(station_id, added, FamilyOrigin.LEVEL)
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


## Producción por día en su nivel actual, más la extra y la de las familias que trabajan hoy
## (id de objeto -> unidades).
func get_production(station_id: StringName) -> Dictionary[StringName, int]:
	return _dict_at(_solve().production, station_id)


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


## Consumo por día en su nivel actual (lo cubierto más lo que pide para crecer) más los insumos
## de todas sus familias (también las que hoy no trabajan).
func get_consumption(station_id: StringName) -> Dictionary[StringName, int]:
	var data: StationData = get_data(station_id)
	if data == null:
		return {}
	var result: Dictionary[StringName, int] = data.get_consumption(get_level(station_id))
	for family: Dictionary in _families.get(station_id, []):
		var occupation: OccupationData = get_occupation(family["occupation"])
		if occupation != null:
			result = ItemAmount.sum_by_id(occupation.needs, result)
	return result


# --- Población: oficios y familias (tarea 62b.1) ---


## Registra un oficio. Los del bioma de cada estación se registran solos al sumar la estación;
## los que solo habilita un rasgo (hacheros con monte en las sierras) hay que registrarlos acá.
## Devuelve false si no sirve.
func add_occupation(occupation: OccupationData) -> bool:
	if occupation == null or occupation.id == &"":
		push_warning("ProductionModel: oficio sin datos o sin id.")
		return false
	_occupations[occupation.id] = occupation
	return true


func get_occupation(occupation_id: StringName) -> OccupationData:
	return _occupations.get(occupation_id)


## Los oficios registrados, en orden de registro.
func get_occupations() -> Array[OccupationData]:
	var result: Array[OccupationData] = []
	result.assign(_occupations.values())
	return result


## Los oficios de sus familias, en orden de llegada (ids, repetidos si hay varias).
func get_families(station_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for family: Dictionary in _families.get(station_id, []):
		result.append(family["occupation"])
	return result


func get_family_count(station_id: StringName) -> int:
	return _families.get(station_id, []).size()


## Cuántas familias de ese oficio tiene.
func count_families(station_id: StringName, occupation_id: StringName) -> int:
	return get_families(station_id).count(occupation_id)


## Los oficios de las familias que trajo el jugador.
func get_player_families(station_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for family: Dictionary in _families.get(station_id, []):
		if int(family["origin"]) == FamilyOrigin.PLAYER:
			result.append(family["occupation"])
	return result


## Los oficios de las familias que hoy no trabajan porque les faltan insumos (o porque su oficio
## no está registrado).
func get_idle_families(station_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var families: Array = _families.get(station_id, [])
	var flags: Array = _solve().active.get(station_id, [])
	for index: int in families.size():
		if index >= flags.size() or not flags[index]:
			result.append(families[index]["occupation"])
	return result


## Los oficios que puede tomar sola una familia nueva (D129, D132): los propios del bioma cuyo
## rasgo tiene la estación y los registrados que pide un rasgo que tiene, salvo los posibles del
## bioma (esos los trae solo el jugador).
func get_allowed_occupations(station_id: StringName) -> Array[OccupationData]:
	var result: Array[OccupationData] = []
	var data: StationData = get_data(station_id)
	if data == null:
		return result
	if data.biome != null:
		for occupation: OccupationData in data.biome.own:
			if occupation != null and _trait_ok(data, occupation) and not _has_occupation(result, occupation.id):
				result.append(occupation)
	for occupation: OccupationData in _occupations.values():
		if occupation.requires_trait == &"" or not data.has_trait(occupation.requires_trait):
			continue
		if data.biome != null and data.biome.is_possible(occupation.id):
			continue
		if not _has_occupation(result, occupation.id):
			result.append(occupation)
	return result


## El oficio que tomaría sola una familia nueva, o null si no hay ninguno permitido. Orden de
## D129: comida si todavía no tiene ninguna familia de comida, después materia prima del lugar y
## por último procesado. Entre los del mismo grupo gana el que da algo que a la estación le
## falta, después el que tiene menos familias y después el primero de la lista.
func choose_occupation(station_id: StringName) -> OccupationData:
	var allowed: Array[OccupationData] = get_allowed_occupations(station_id)
	if allowed.is_empty():
		return null
	var pool: Array[OccupationData] = []
	if not _has_family_of_kind(station_id, OccupationData.Kind.FOOD):
		pool = _of_kind(allowed, OccupationData.Kind.FOOD)
	if pool.is_empty():
		pool = _of_kind(allowed, OccupationData.Kind.RAW)
	if pool.is_empty():
		pool = _of_kind(allowed, OccupationData.Kind.PROCESSED)
	if pool.is_empty():
		pool = allowed
	var missing: Dictionary[StringName, int] = get_missing(station_id)
	var best: OccupationData = null
	var best_score: int = 0
	for occupation: OccupationData in pool:
		var score: int = count_families(station_id, occupation.id)
		var fills: bool = false
		for item_id: StringName in occupation.get_production():
			fills = fills or missing.has(item_id)
		if not fills:
			score += 1000
		if best == null or score < best_score:
			best = occupation
			best_score = score
	return best


## Llega una familia que toma oficio sola (choose_occupation). Devuelve su oficio, o null si la
## estación no permite ninguno. `origin`: EXTRA para lo que no es el cupo de un nivel (la
## recompensa de una misión).
func assign_occupation(station_id: StringName, origin: FamilyOrigin = FamilyOrigin.EXTRA) -> OccupationData:
	var occupation: OccupationData = choose_occupation(station_id)
	if occupation == null:
		push_warning("ProductionModel: '%s' no tiene ningún oficio permitido para una familia nueva (bioma y rasgos)." % station_id)
		return null
	_push_family(station_id, occupation, origin)
	family_added.emit(station_id, occupation, origin)
	return occupation


## Suma una familia de un oficio elegido, sin mirar bioma, rasgos ni tope (la recompensa de una
## misión: "Sierras Bayas suma 2 familias de canteros"). Devuelve false si no conoce la estación
## o el oficio.
func add_family(station_id: StringName, occupation_id: StringName, origin: FamilyOrigin = FamilyOrigin.EXTRA) -> bool:
	var occupation: OccupationData = get_occupation(occupation_id)
	if not has_station(station_id) or occupation == null:
		push_warning("ProductionModel: no se puede sumar una familia de '%s' a '%s'." % [occupation_id, station_id])
		return false
	_push_family(station_id, occupation, origin)
	family_added.emit(station_id, occupation, origin)
	return true


## Cuántas familias más puede traer el jugador (D129: 1 en un pueblo, 3 en una ciudad).
func get_player_slots(station_id: StringName) -> int:
	var data: StationData = get_data(station_id)
	if data == null:
		return 0
	return maxi(0, data.get_max_player_occupations() - get_player_families(station_id).size())


## Si el jugador puede traer una familia de ese oficio: propio o posible del bioma (nunca de
## otro, D132), con el rasgo que pida y con lugar en el tope.
func can_add_player_family(station_id: StringName, occupation_id: StringName) -> bool:
	var data: StationData = get_data(station_id)
	var occupation: OccupationData = get_occupation(occupation_id)
	if data == null or occupation == null or data.biome == null:
		return false
	return data.biome.allows(occupation_id) and _trait_ok(data, occupation) and get_player_slots(station_id) > 0


## Suma una familia traída por el jugador (mudanza). Devuelve false si no se puede
## (can_add_player_family).
func add_player_family(station_id: StringName, occupation_id: StringName) -> bool:
	if not can_add_player_family(station_id, occupation_id):
		return false
	var occupation: OccupationData = get_occupation(occupation_id)
	_push_family(station_id, occupation, FamilyOrigin.PLAYER)
	family_added.emit(station_id, occupation, FamilyOrigin.PLAYER)
	return true


# --- Flujos ---


## Crea un flujo permanente de `amount` unidades por día. Devuelve null si los datos no sirven
## (estación desconocida, la misma estación, sin objeto o cantidad menor a 1). No exige que
## alcance la producción: si no alcanza, el flujo nuevo recibe lo que dejan los más viejos.
## `round_trip`: flujo de pasajeros que va y vuelve (tarea 60b). `pending`: empieza el día
## siguiente (tarea 62.4).
func add_flow(from: StringName, to: StringName, item_id: StringName, amount: int, round_trip: bool = false, pending: bool = false) -> ProductionFlow:
	if not has_station(from) or not has_station(to) or from == to or item_id == &"" or amount < 1:
		push_warning("ProductionModel: flujo inválido (%d %s de '%s' a '%s')." % [amount, item_id, from, to])
		return null
	var flow := ProductionFlow.new(from, to, item_id, amount)
	flow.id = _next_flow_id
	flow.round_trip = round_trip
	flow.pending = pending
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


## Todos los flujos, del más viejo al más nuevo (también los que empiezan mañana).
func get_flows() -> Array[ProductionFlow]:
	return _flows.duplicate()


## Los flujos que ya empezaron (sin los que empiezan mañana): los que llevan tren.
func get_running_flows() -> Array[ProductionFlow]:
	var result: Array[ProductionFlow] = []
	for flow: ProductionFlow in _flows:
		if not flow.pending:
			result.append(flow)
	return result


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
## vuelven a pedir lo suyo al repararse) ni la usa la propia estación (sus familias o el consumo
## del nivel, tarea 62b.1). Es lo que puede pedir una misión nueva.
func get_free_production(station_id: StringName) -> Dictionary[StringName, int]:
	var solution: DaySolution = _solve()
	var free: Dictionary[StringName, int] = _uncommitted(_dict_at(solution.production, station_id), station_id)
	var used: Dictionary[StringName, int] = _dict_at(solution.local_use, station_id)
	for item_id: StringName in used:
		if free.has(item_id):
			free[item_id] = maxi(0, free[item_id] - used[item_id])
	return free


## Lo que los flujos le prometen por día a una estación, entreguen o no hoy (cortados o sin
## producción suficiente también cuentan). Lo que el consumo pide por encima de esto es lo que
## piden las misiones principales (tarea 58).
func get_committed_supply(station_id: StringName) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	for flow: ProductionFlow in get_flows_to(station_id):
		result[flow.item_id] = result.get(flow.item_id, 0) + flow.amount
	return result


## El consumo que ningún flujo tiene comprometido ni cubre la producción propia (id de objeto ->
## unidades por día).
func get_uncommitted_needs(station_id: StringName) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	var committed: Dictionary[StringName, int] = get_committed_supply(station_id)
	var own: Dictionary[StringName, int] = _uncommitted(get_production(station_id), station_id)
	var consumption: Dictionary[StringName, int] = get_consumption(station_id)
	for item_id: StringName in consumption:
		var lacking: int = consumption[item_id] - committed.get(item_id, 0) - own.get(item_id, 0)
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
	return _solve().plan


## Lo que le llega por día a la estación con los flujos de hoy (id de objeto -> unidades).
func get_supply(station_id: StringName) -> Dictionary[StringName, int]:
	return _dict_at(_solve().supply, station_id)


## Lo que le falta por día para cubrir todo su consumo con lo que llega y lo propio (vacío si
## está cubierta).
func get_missing(station_id: StringName) -> Dictionary[StringName, int]:
	return _missing_in(_solve(), station_id)


func is_covered(station_id: StringName) -> bool:
	return get_missing(station_id).is_empty()


## Si está cubierta y todavía puede crecer (no estancada).
func is_growing(station_id: StringName) -> bool:
	return get_days_to_grow(station_id) > 0 and is_covered(station_id)


# --- Simulación ---


## Simula un día: entrega los flujos, suma días a las estaciones cubiertas y las hace crecer.
## Primero actualiza todo y después avisa, así quien escucha ve el modelo entero ya al día.
func advance_day() -> void:
	# Los flujos que nacieron ayer empiezan hoy (tarea 62.4).
	for flow: ProductionFlow in _flows:
		flow.pending = false
	var solution: DaySolution = _solve()
	for flow: ProductionFlow in _flows:
		flow.last_delivered = solution.plan.get(flow.id, 0)
	var grown: Array[StringName] = []
	for station_id: StringName in _data:
		var needed: int = get_days_to_grow(station_id)
		if needed <= 0 or not _missing_in(solution, station_id).is_empty():
			continue
		_progress[station_id] = get_growth_progress(station_id) + 1
		if _progress[station_id] >= needed:
			_levels[station_id] = get_level(station_id) + 1
			_progress[station_id] = 0
			grown.append(station_id)
	# Las familias del nivel nuevo llegan con todo el modelo ya al día (tarea 62b.1).
	var arrived: Dictionary[StringName, Array] = {}
	for station_id: StringName in grown:
		arrived[station_id] = _fill_families(station_id)
	for station_id: StringName in grown:
		level_changed.emit(station_id, get_level(station_id))
		var added: Array[OccupationData] = []
		added.assign(arrived[station_id])
		_emit_families(station_id, added, FamilyOrigin.LEVEL)
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
	var families: Dictionary = {}
	for station_id: StringName in _families:
		var entries: Array = []
		for family: Dictionary in _families[station_id]:
			entries.append({"occupation": String(family["occupation"]), "origin": int(family["origin"])})
		families[String(station_id)] = entries
	return {"levels": levels, "progress": progress, "flows": flows, "next_flow_id": _next_flow_id, "bonus": bonus, "families": families}


## Carga niveles, días, flujos, producción extra y familias. Las estaciones (sus datos) se vuelven
## a registrar con add_station, que respeta el nivel y las familias cargadas (solo completa el
## cupo si falta alguna, sin avisar).
func load_dict(values: Dictionary) -> void:
	_levels.clear()
	_progress.clear()
	_flows.clear()
	_bonus.clear()
	_families.clear()
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
	var saved_families: Dictionary = values.get("families", {})
	for key: String in saved_families:
		var entries: Array = []
		for family: Dictionary in saved_families[key]:
			entries.append({"occupation": StringName(str(family.get("occupation", ""))), "origin": int(family.get("origin", FamilyOrigin.LEVEL))})
		_families[StringName(key)] = entries
	for entry: Dictionary in values.get("flows", []):
		_flows.append(ProductionFlow.from_dict(entry))
	_next_flow_id = int(values.get("next_flow_id", 1))
	for flow: ProductionFlow in _flows:
		_next_flow_id = maxi(_next_flow_id, flow.id + 1)
	for station_id: StringName in _data:
		_levels[station_id] = _data[station_id].clamp_level(_levels.get(station_id, 1))
		if not _progress.has(station_id):
			_progress[station_id] = 0
	for station_id: StringName in _data:
		_fill_families(station_id)


# --- Privados ---


# Completa el cupo de familias de los niveles hasta el actual, sin avisar. Devuelve los oficios
# que llegaron (para avisar después con _emit_families).
func _fill_families(station_id: StringName) -> Array[OccupationData]:
	var added: Array[OccupationData] = []
	var data: StationData = get_data(station_id)
	if data == null:
		return added
	var quota: int = data.get_family_quota(get_level(station_id))
	var from_levels: int = 0
	for family: Dictionary in _families.get(station_id, []):
		if int(family["origin"]) == FamilyOrigin.LEVEL:
			from_levels += 1
	while from_levels < quota:
		var occupation: OccupationData = choose_occupation(station_id)
		if occupation == null:
			push_warning("ProductionModel: '%s' no tiene ningún oficio permitido para sus familias (bioma y rasgos)." % station_id)
			break
		_push_family(station_id, occupation, FamilyOrigin.LEVEL)
		added.append(occupation)
		from_levels += 1
	return added


func _emit_families(station_id: StringName, added: Array[OccupationData], origin: FamilyOrigin) -> void:
	for occupation: OccupationData in added:
		family_added.emit(station_id, occupation, origin)


func _push_family(station_id: StringName, occupation: OccupationData, origin: FamilyOrigin) -> void:
	var families: Array = _families.get(station_id, [])
	families.append({"occupation": occupation.id, "origin": origin})
	_families[station_id] = families


static func _trait_ok(data: StationData, occupation: OccupationData) -> bool:
	return occupation.requires_trait == &"" or data.has_trait(occupation.requires_trait)


static func _has_occupation(list: Array[OccupationData], occupation_id: StringName) -> bool:
	for occupation: OccupationData in list:
		if occupation.id == occupation_id:
			return true
	return false


static func _of_kind(list: Array[OccupationData], kind: OccupationData.Kind) -> Array[OccupationData]:
	var result: Array[OccupationData] = []
	for occupation: OccupationData in list:
		if occupation.kind == kind:
			result.append(occupation)
	return result


func _has_family_of_kind(station_id: StringName, kind: OccupationData.Kind) -> bool:
	for occupation_id: StringName in get_families(station_id):
		var occupation: OccupationData = get_occupation(occupation_id)
		if occupation != null and occupation.kind == kind:
			return true
	return false


# Resuelve el día: empieza con trabajando solo las familias sin insumos y repite (producción,
# reparto, insumos) hasta que ninguna familia cambia. Cada ronda puede encender familias que
# dependen de otras (troncos de Azul -> canteros de Sierras Bayas -> caleros de Olavarría), así
# que alcanza con una ronda por estación y dos más.
func _solve() -> DaySolution:
	var active: Dictionary = {}
	for station_id: StringName in _data:
		var flags: Array = []
		for family: Dictionary in _families.get(station_id, []):
			var occupation: OccupationData = get_occupation(family["occupation"])
			flags.append(occupation != null and occupation.needs.is_empty())
		active[station_id] = flags
	var solution: DaySolution = null
	for _round: int in _data.size() + 2:
		solution = _solve_with(active)
		if not _flags_changed(active, solution.active):
			break
		active = solution.active
	return solution


func _solve_with(active: Dictionary) -> DaySolution:
	var solution := DaySolution.new()
	# 1. Producción: la de los datos, la extra y la de las familias que trabajan.
	for station_id: StringName in _data:
		var data: StationData = _data[station_id]
		var production: Dictionary[StringName, int] = data.get_production(get_level(station_id))
		var bonus: Dictionary = _bonus.get(station_id, {})
		for item_id: StringName in bonus:
			production[item_id] = production.get(item_id, 0) + int(bonus[item_id])
		var families: Array = _families.get(station_id, [])
		var flags: Array = active.get(station_id, [])
		for index: int in families.size():
			var occupation: OccupationData = get_occupation(families[index]["occupation"])
			if occupation != null and index < flags.size() and flags[index]:
				production = ItemAmount.sum_by_id(occupation.produces, production)
		solution.production[station_id] = production
	# 2. Reparto entre flujos, del más viejo al más nuevo.
	var remaining: Dictionary = {}
	for flow: ProductionFlow in _flows:
		if not remaining.has(flow.from_station):
			remaining[flow.from_station] = _dict_at(solution.production, flow.from_station)
		var left: Dictionary = remaining[flow.from_station]
		var amount: int = 0
		if not flow.pending and is_flow_connected(flow):
			amount = mini(flow.amount, left.get(flow.item_id, 0))
			if amount > 0:
				left[flow.item_id] -= amount
		solution.plan[flow.id] = amount
	# 3. Lo que le llega a cada estación.
	for station_id: StringName in _data:
		var supply: Dictionary[StringName, int] = {}
		for flow: ProductionFlow in _flows:
			var delivered: int = solution.plan.get(flow.id, 0)
			if flow.to_station == station_id and delivered > 0:
				supply[flow.item_id] = supply.get(flow.item_id, 0) + delivered
		solution.supply[station_id] = supply
	# 4. Insumos: primero el consumo del nivel, después las familias en orden de llegada; cada uno
	# toma de lo que llega y después de lo propio que no se llevan los flujos.
	for station_id: StringName in _data:
		var from_supply: Dictionary[StringName, int] = _dict_at(solution.supply, station_id)
		var from_own: Dictionary[StringName, int] = _uncommitted(_dict_at(solution.production, station_id), station_id)
		var used_own: Dictionary[StringName, int] = {}
		_take(_data[station_id].get_consumption(get_level(station_id)), from_supply, from_own, used_own)
		var flags: Array = []
		for family: Dictionary in _families.get(station_id, []):
			var occupation: OccupationData = get_occupation(family["occupation"])
			var works: bool = occupation != null and _has_all(occupation.get_needs(), from_supply, from_own)
			if works:
				_take(occupation.get_needs(), from_supply, from_own, used_own)
			flags.append(works)
		solution.active[station_id] = flags
		solution.local_use[station_id] = used_own
	return solution


static func _flags_changed(before: Dictionary, after: Dictionary) -> bool:
	for station_id: StringName in after:
		var old_flags: Array = before.get(station_id, [])
		var new_flags: Array = after[station_id]
		if old_flags.size() != new_flags.size():
			return true
		for index: int in new_flags.size():
			if bool(old_flags[index]) != bool(new_flags[index]):
				return true
	return false


# Saca `needs` de lo que llega y, si no alcanza, de lo propio (anotado en `used_own`). Toma lo
# que haya aunque no alcance.
static func _take(needs: Dictionary[StringName, int], from_supply: Dictionary[StringName, int], from_own: Dictionary[StringName, int], used_own: Dictionary[StringName, int]) -> void:
	for item_id: StringName in needs:
		var wanted: int = needs[item_id]
		var supplied: int = mini(wanted, from_supply.get(item_id, 0))
		if supplied > 0:
			from_supply[item_id] -= supplied
			wanted -= supplied
		var own: int = mini(wanted, from_own.get(item_id, 0))
		if own > 0:
			from_own[item_id] -= own
			used_own[item_id] = used_own.get(item_id, 0) + own


static func _has_all(needs: Dictionary[StringName, int], from_supply: Dictionary[StringName, int], from_own: Dictionary[StringName, int]) -> bool:
	for item_id: StringName in needs:
		if from_supply.get(item_id, 0) + from_own.get(item_id, 0) < needs[item_id]:
			return false
	return true


# La producción menos lo que prometen los flujos que salen (también los cortados).
func _uncommitted(production: Dictionary[StringName, int], station_id: StringName) -> Dictionary[StringName, int]:
	var free: Dictionary[StringName, int] = production.duplicate()
	for flow: ProductionFlow in get_flows_from(station_id):
		if free.has(flow.item_id):
			free[flow.item_id] = maxi(0, free[flow.item_id] - flow.amount)
	return free


# Lo que le falta para cubrir todo su consumo con lo que le llega y su producción libre.
func _missing_in(solution: DaySolution, station_id: StringName) -> Dictionary[StringName, int]:
	var missing: Dictionary[StringName, int] = {}
	var supply: Dictionary[StringName, int] = _dict_at(solution.supply, station_id)
	var own: Dictionary[StringName, int] = _uncommitted(_dict_at(solution.production, station_id), station_id)
	var consumption: Dictionary[StringName, int] = get_consumption(station_id)
	for item_id: StringName in consumption:
		var lacking: int = consumption[item_id] - supply.get(item_id, 0) - own.get(item_id, 0)
		if lacking > 0:
			missing[item_id] = lacking
	return missing


# Copia tipada de un diccionario id de objeto -> unidades guardado en `source` (vacía si no está).
static func _dict_at(source: Dictionary, key: StringName) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	var found: Dictionary = source.get(key, {})
	for item_id: StringName in found:
		result[item_id] = int(found[item_id])
	return result
