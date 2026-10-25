class_name StationData
extends Resource
## Definición de una estación (D31, D79, tarea 56): nombre, tipo, región, producción y consumo
## por nivel y servicios. Es compartida y no guarda estado: el nivel actual vive en Station
## y en el ProductionModel (tarea 57). Lo calcula todo en lógica pura, para que el
## modelo de producción y las misiones lo usen sin escena.
## Datos: data/stations/*.tres. El `id` es el mismo nombre de estación que usan las vías
## (TrackSegment.from_station y to_station).

## Ciudad, pueblo, estación de carga (produce y casi no crece) o puerto.
enum StationType { CITY, TOWN, FREIGHT, PORT }

const TYPE_NAMES: Array[String] = ["ciudad", "pueblo", "estación de carga", "puerto"]

@export var id: StringName
@export var display_name: String
@export var type: StationType = StationType.TOWN
## Región a la que pertenece (D76; la tarea 69 le da datos propios).
@export var region: StringName
## Producción base por día, en cualquier nivel.
@export var production: Array[ItemAmount] = []
## Niveles de crecimiento: el primero es el nivel 1. Sin niveles, la estación tiene un solo
## nivel sin consumo ni servicios.
@export var levels: Array[StationLevelData] = []


static func type_name(value: StationType) -> String:
	return TYPE_NAMES[value]


## El nivel más alto al que puede llegar (al menos 1).
func get_max_level() -> int:
	return maxi(1, levels.size())


## `level` dentro de 1 y el máximo.
func clamp_level(level: int) -> int:
	return clampi(level, 1, get_max_level())


## Los datos del nivel (después de limitarlo), o null si no tiene niveles cargados.
func get_level_data(level: int) -> StationLevelData:
	if levels.is_empty():
		return null
	return levels[clamp_level(level) - 1]


## Si todavía puede crecer desde `level`.
func can_grow(level: int) -> bool:
	return clamp_level(level) < get_max_level()


## Producción por día en `level`: la base más lo extra de los niveles hasta ese. Id -> unidades.
func get_production(level: int) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = ItemAmount.sum_by_id(production)
	for index: int in clamp_level(level):
		var data: StationLevelData = _level_at(index)
		if data != null:
			result = ItemAmount.sum_by_id(data.extra_production, result)
	return result


## Lo que hace falta por día para crecer desde `level` (el consumo nuevo de ese nivel).
## Vacío en el último nivel.
func get_growth_needs(level: int) -> Dictionary[StringName, int]:
	if not can_grow(level):
		return {}
	var data: StationLevelData = get_level_data(level)
	return ItemAmount.sum_by_id(data.needs) if data != null else {}


## Días con todo cubierto que hacen falta para crecer desde `level` (0 si ya no crece).
func get_days_to_grow(level: int) -> int:
	if not can_grow(level):
		return 0
	var data: StationLevelData = get_level_data(level)
	return data.days_to_grow if data != null else 0


## Todo lo que consume por día en `level`: el consumo de los niveles hasta ese, incluido el
## que le falta para crecer (lo que ya se cubrió se sigue consumiendo, D79).
func get_consumption(level: int) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	for index: int in clamp_level(level):
		var data: StationLevelData = _level_at(index)
		if data != null:
			result = ItemAmount.sum_by_id(data.needs, result)
	return result


## Si tiene mercado en `level` (un servicio abierto sigue abierto en los niveles de arriba).
func has_market(level: int) -> bool:
	for index: int in clamp_level(level):
		var data: StationLevelData = _level_at(index)
		if data != null and data.market:
			return true
	return false


## Si el nivel ya permite taller (la misión principal que lo habilita es aparte, D80).
func has_workshop(level: int) -> bool:
	for index: int in clamp_level(level):
		var data: StationLevelData = _level_at(index)
		if data != null and data.workshop:
			return true
	return false


## El ItemData con ese id que aparezca en la producción o en los consumos, o null.
func find_item(item_id: StringName) -> ItemData:
	var lists: Array = [production]
	for data: StationLevelData in levels:
		if data != null:
			lists.append(data.needs)
			lists.append(data.extra_production)
	for list: Array in lists:
		for entry: ItemAmount in list:
			if entry != null and entry.item != null and entry.item.id == item_id:
				return entry.item
	return null


## Problemas de los datos (vacío si está todo bien). Station los avisa al empezar.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	if id == &"":
		problems.append("la estación no tiene id")
	if display_name.is_empty():
		problems.append("'%s' no tiene nombre" % id)
	_validate_amounts(production, "la producción base", problems)
	for index: int in levels.size():
		var data: StationLevelData = levels[index]
		if data == null:
			problems.append("'%s': el nivel %d está vacío" % [id, index + 1])
			continue
		_validate_amounts(data.needs, "el consumo del nivel %d" % (index + 1), problems)
		_validate_amounts(data.extra_production, "la producción del nivel %d" % (index + 1), problems)
	return problems


func _level_at(index: int) -> StationLevelData:
	return levels[index] if index < levels.size() else null


func _validate_amounts(amounts: Array[ItemAmount], where: String, problems: PackedStringArray) -> void:
	var seen: Dictionary[StringName, bool] = {}
	for entry: ItemAmount in amounts:
		if entry == null or entry.item == null:
			problems.append("'%s': %s tiene una cantidad sin objeto" % [id, where])
			continue
		if entry.amount <= 0:
			problems.append("'%s': %s tiene %s con cantidad %d" % [id, where, entry.item.id, entry.amount])
		if seen.has(entry.item.id):
			problems.append("'%s': %s repite %s" % [id, where, entry.item.id])
		seen[entry.item.id] = true
