class_name FlowNames
extends RefCounted
## Nombres de los flujos y de sus trenes automáticos (D106, tarea 61): "Tren de {carga} de
## {origen}" ("Tren de piedra de Sierras Bayas") o, si lleva gente, "Tren de pasajeros a
## {destino}". Un flujo con nombre especial (ProductionFlow.custom_name, "El Marplatense") usa
## ese. El tren de una conexión con varios flujos se llama como el más viejo. Lógica pura.


## Cómo se nombra la carga: ItemData.cargo_name ("troncos") o, si no tiene, su nombre.
static func cargo_name(item: ItemData, fallback: String = "") -> String:
	if item == null:
		return fallback
	if not item.cargo_name.is_empty():
		return item.cargo_name
	return item.display_name if not item.display_name.is_empty() else String(item.id)


## Nombre de un flujo. `item_lookup`: func(item_id) -> ItemData; `station_name`:
## func(station_id) -> String.
static func flow_name(flow: ProductionFlow, item_lookup: Callable, station_name: Callable) -> String:
	if flow == null:
		return ""
	if not flow.custom_name.is_empty():
		return flow.custom_name
	var item: ItemData = item_lookup.call(flow.item_id) if item_lookup.is_valid() else null
	if ItemData.is_passenger(item):
		return "Tren de pasajeros a %s" % station_name.call(flow.to_station)
	return "Tren de %s de %s" % [cargo_name(item, String(flow.item_id)), station_name.call(flow.from_station)]


## Nombre del tren de una conexión: el del primer flujo con nombre especial, si hay; si no, el
## del más viejo.
static func train_name(flows: Array[ProductionFlow], item_lookup: Callable, station_name: Callable) -> String:
	for flow: ProductionFlow in flows:
		if not flow.custom_name.is_empty():
			return flow.custom_name
	return flow_name(flows[0], item_lookup, station_name) if not flows.is_empty() else ""
