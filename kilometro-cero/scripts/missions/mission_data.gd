class_name MissionData
extends Resource
## Una misión secundaria escrita a mano (D80, tarea 58). Las principales no usan este recurso:
## salen solas de los consumos de cada estación (MissionBoard).
## Las secundarias se consiguen explorando y hablando con los pobladores (MissionGiver), cuentan
## la historia del lugar (`intro` al tomarla, `outro` al cumplirla) y suben la producción local
## (`reward_production`), por ejemplo al reabrir la vía a una cantera abandonada.
## Obra (tarea 62b.4, D127, D130): los materiales de `delivery` no se entregan en el tablero sino
## en su obra (ConstructionSite), y solo los que trae el jugador; al cumplirse la obra cambia la
## escena (las carpas pasan a ser casas).
## Datos: data/missions/*.tres.

## Entregar objetos en la estación, habilitar un tramo, despejar una zona o levantar una obra.
enum Kind { DELIVERY, OPEN_SEGMENT, CLEAR_ZONE, BUILD }

const KIND_NAMES: Array[String] = ["entrega", "habilitar tramo", "despejar zona", "obra"]

## Único en todo el juego (se usa para guardar).
@export var id: StringName
@export var title: String
## Lo que cuenta el poblador al darla.
@export_multiline var intro: String
## Lo que cuenta al cumplirla.
@export_multiline var outro: String
## Estación a la que pertenece: aparece en su tablero, y ahí se entrega.
@export var station_id: StringName
@export var kind: Kind = Kind.DELIVERY
## DELIVERY: lo que hay que entregar (una vez, en total; puede ser en varios viajes).
## BUILD: los materiales de la obra (se llevan a su ConstructionSite).
@export var delivery: Array[ItemAmount] = []
## OPEN_SEGMENT: el tramo que tiene que quedar abierto.
@export var segment_id: StringName
## CLEAR_ZONE: se cumple cuando no queda ningún nodo en este grupo (obstáculos, y más adelante
## animales peligrosos).
@export var zone_group: StringName
## Nivel de la estación desde el que se la puede conseguir.
@export_range(1, 10) var min_level: int = 1
## Misiones (ids) que tienen que estar cumplidas antes.
@export var requires: Array[StringName] = []
## Pesos que se cobran al cumplirla.
@export var reward_money: int = 0
## Producción por día que se suma para siempre (ProductionModel.add_production_bonus).
@export var reward_production: Array[ItemAmount] = []
## Familias con oficio que llegan para siempre al cumplirla (tarea 62b.2, D129): una por
## entrada, de origen extra (ProductionModel.add_family, sin mirar bioma, rasgos ni tope). La
## cantera vieja suma 2 familias de canteros en Sierras Bayas.
@export var reward_families: Array[OccupationData] = []
## Estación que recibe la producción extra y las familias (vacío: station_id).
@export var reward_station: StringName
## Herramientas clave que da el poblador al dar la misión (tarea 62.5): el jefe de estación de
## Olavarría da el hacha con la de la vía tapada.
@export var gives_tools: Array[KeyItemData] = []


static func kind_name(value: Kind) -> String:
	return KIND_NAMES[value]


func get_reward_station() -> StringName:
	return reward_station if reward_station != &"" else station_id


## Problemas de los datos (vacío si está todo bien). MissionGiver los avisa al empezar.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	if id == &"":
		problems.append("la misión no tiene id")
	if title.is_empty():
		problems.append("'%s' no tiene título" % id)
	if station_id == &"":
		problems.append("'%s' no tiene estación" % id)
	match kind:
		Kind.DELIVERY:
			if ItemAmount.sum_by_id(delivery).is_empty():
				problems.append("'%s' es de entrega y no pide nada" % id)
		Kind.BUILD:
			if ItemAmount.sum_by_id(delivery).is_empty():
				problems.append("'%s' es una obra y no pide materiales" % id)
		Kind.OPEN_SEGMENT:
			if segment_id == &"":
				problems.append("'%s' es de habilitar tramo y no tiene segment_id" % id)
		Kind.CLEAR_ZONE:
			if zone_group == &"":
				problems.append("'%s' es de despejar zona y no tiene zone_group" % id)
	for entry: ItemAmount in delivery + reward_production:
		if entry == null or entry.item == null:
			problems.append("'%s' tiene una cantidad sin objeto" % id)
	for occupation: OccupationData in reward_families:
		if occupation == null or occupation.id == &"":
			problems.append("'%s' tiene una familia de premio sin oficio" % id)
	if requires.has(id):
		problems.append("'%s' se pide a sí misma" % id)
	return problems
