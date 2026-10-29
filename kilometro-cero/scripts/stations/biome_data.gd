class_name BiomeData
extends Resource
## Un bioma (D132, tarea 62b.1): el perfil de zona de una región (sierras, pampa húmeda,
## cuenca del Salado...). Dice qué oficios toman solas las familias que llegan (los propios),
## cuáles son raros pero permitidos (los posibles, solo los trae el jugador) y qué pide siempre
## porque no lo tiene (las demandas naturales, de donde salen los flujos entre biomas; tareas 69
## y 70, en el Hito A no se usan). Los rasgos de cada estación (StationData.traits) habilitan
## oficios de afuera del bioma. Es una definición: no guarda estado. Datos: data/biomes/*.tres.

@export var id: StringName
@export var display_name: String
## Los oficios que más se asignan solos.
@export var own: Array[OccupationData] = []
## Raros pero permitidos (corderos en la pampa): no se asignan solos, los puede traer el jugador.
@export var possible: Array[OccupationData] = []
## Lo que el bioma no tiene y siempre pide.
@export var natural_demands: Array[ItemData] = []


func is_own(occupation_id: StringName) -> bool:
	return _index_of(own, occupation_id) >= 0


func is_possible(occupation_id: StringName) -> bool:
	return _index_of(possible, occupation_id) >= 0


## Si el jugador puede traer una familia de ese oficio (propio o posible, D132).
func allows(occupation_id: StringName) -> bool:
	return is_own(occupation_id) or is_possible(occupation_id)


## Los oficios propios y posibles, sin repetir.
func get_occupations() -> Array[OccupationData]:
	var result: Array[OccupationData] = []
	for list: Array in [own, possible]:
		for occupation: OccupationData in list:
			if occupation != null and _index_of(result, occupation.id) < 0:
				result.append(occupation)
	return result


## Problemas de los datos (vacío si está todo bien).
func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	if id == &"":
		problems.append("un bioma no tiene id")
	if display_name.is_empty():
		problems.append("el bioma '%s' no tiene nombre" % id)
	for occupation: OccupationData in own:
		if occupation == null:
			problems.append("el bioma '%s' tiene un oficio propio vacío" % id)
		elif is_possible(occupation.id):
			problems.append("el bioma '%s' tiene '%s' como propio y como posible" % [id, occupation.id])
	return problems


static func _index_of(list: Array[OccupationData], occupation_id: StringName) -> int:
	for index: int in list.size():
		if list[index] != null and list[index].id == occupation_id:
			return index
	return -1
