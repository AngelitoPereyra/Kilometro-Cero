class_name OccupationData
extends Resource
## Un oficio (D129, tarea 62b.1): lo que hace una familia de una estación ("hacheros",
## "canteros"). Cada familia necesita y produce por día lo de su oficio; sin todos sus insumos
## no produce (los canteros sin troncos no pican). Es una definición: no guarda estado (las
## familias viven en el ProductionModel). Datos: data/occupations/*.tres (tarea 62b.2).

## Para el orden de asignación de D129: primero la comida que falta, después la materia prima
## del lugar y por último el procesado.
enum Kind { FOOD, RAW, PROCESSED }

const KIND_NAMES: Array[String] = ["comida", "materia prima", "procesado"]

@export var id: StringName
## Cómo se nombran las familias de este oficio ("hacheros").
@export var display_name: String
@export var kind: Kind = Kind.RAW
## Insumos por familia y por día.
@export var needs: Array[ItemAmount] = []
## Producción por familia y por día (solo con los insumos cubiertos).
@export var produces: Array[ItemAmount] = []
## Rasgo de estación que pide (monte, campo, cantera, horno). Vacío: ninguno. El rasgo también
## habilita el oficio fuera de su bioma (D132: monte da hacheros en cualquier bioma).
@export var requires_trait: StringName
## Su parcela de paisaje junto a la vía (tarea 62b.5).
@export var landscape_scene: PackedScene
@export_multiline var description: String = ""


static func kind_name(value: Kind) -> String:
	return KIND_NAMES[value]


## Insumos de una familia por día (id de objeto -> unidades).
func get_needs() -> Dictionary[StringName, int]:
	return ItemAmount.sum_by_id(needs)


## Producción de una familia por día (id de objeto -> unidades).
func get_production() -> Dictionary[StringName, int]:
	return ItemAmount.sum_by_id(produces)


func produces_item(item_id: StringName) -> bool:
	return get_production().has(item_id)


## El ItemData con ese id entre sus insumos o su producción, o null.
func find_item(item_id: StringName) -> ItemData:
	for list: Array in [needs, produces]:
		for entry: ItemAmount in list:
			if entry != null and entry.item != null and entry.item.id == item_id:
				return entry.item
	return null


## Problemas de los datos (vacío si está todo bien).
func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	if id == &"":
		problems.append("un oficio no tiene id")
	if display_name.is_empty():
		problems.append("el oficio '%s' no tiene nombre" % id)
	if produces.is_empty():
		problems.append("el oficio '%s' no produce nada" % id)
	for list: Array in [needs, produces]:
		for entry: ItemAmount in list:
			if entry == null or entry.item == null:
				problems.append("el oficio '%s' tiene una cantidad sin objeto" % id)
	return problems
