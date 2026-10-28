class_name TrunkLine
extends Node
## Línea troncal (D118, tarea 61d): una línea marcada a mano en el mapa, con su nombre y sus
## estaciones en orden (por ejemplo Buenos Aires, ..., Bahía Blanca). Los flujos que tienen sus
## dos estaciones en la línea no van en el tren chico de su conexión sino en las troncales de
## la línea (AutoTrains): una de carga, con todo lo que no es gente, y otra de pasajeros. Cada
## troncal recorre solo el pedazo que usan sus flujos. Puede haber varias en el mundo; un flujo
## que entra en dos líneas va por la primera.

const GROUP: StringName = &"trunk_lines"

## El nombre de la línea ("Ferrocarril Sud"); solo para mostrar.
@export var line_name: String = ""
## Las estaciones de la línea, en orden de una punta a la otra.
@export var stations: Array[Station] = []


func _enter_tree() -> void:
	add_to_group(GROUP)


## Todas las líneas del mundo, en el orden del árbol.
static func find_all(tree: SceneTree) -> Array[TrunkLine]:
	var found: Array[TrunkLine] = []
	if tree == null:
		return found
	for node: Node in tree.get_nodes_in_group(GROUP):
		if node is TrunkLine:
			found.append(node)
	return found


## Los ids de las estaciones en orden (sin repetidos ni estaciones sin datos).
func get_station_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for station: Station in stations:
		if station != null and station.data != null and not ids.has(station.data.id):
			ids.append(station.data.id)
	return ids
