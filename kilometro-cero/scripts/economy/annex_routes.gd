class_name AnnexRoutes
extends RefCounted
## Anexos de producción (tarea 62c.2, D139). Lógica pura. Las vías troncales unen pueblos y ciudades;
## una estación de carga que no está en ninguna línea troncal (cantera, maderera, obraje) es un
## anexo de su cabecera: la estación de una línea más cercana por vía. Un flujo que sale de un
## anexo o llega a uno se ve como dos trenes: el de ramal, entre el anexo y su cabecera, y la
## troncal (o el tren de su conexión) desde la cabecera. La economía no cambia: el modelo sigue
## entregando de punta a punta y la cabecera no guarda stock (acopio invisible, Batmi 2026-10-30).


## Anexo -> cabecera. `types`: id de estación -> StationData.StationType; `lines`: los ids de cada
## línea troncal; `distance`: func(from, to) -> float, el largo del camino por vía (INF sin camino).
## Un anexo sin camino a ninguna línea no tiene cabecera (sus flujos van enteros).
static func find_hubs(types: Dictionary, lines: Array[Array], distance: Callable) -> Dictionary[StringName, StringName]:
	var hubs: Dictionary[StringName, StringName] = {}
	var on_lines: Array[StringName] = []
	for line: Array in lines:
		for station_id: StringName in line:
			if not on_lines.has(station_id):
				on_lines.append(station_id)
	if on_lines.is_empty():
		return hubs
	for station_id: StringName in types:
		if int(types[station_id]) != StationData.StationType.FREIGHT or on_lines.has(station_id):
			continue
		var best: StringName = &""
		var best_distance: float = INF
		for candidate: StringName in on_lines:
			var length: float = float(distance.call(station_id, candidate))
			if length < best_distance:
				best = candidate
				best_distance = length
		if best != &"":
			hubs[station_id] = best
	return hubs


## Los flujos como los ven los trenes: cada uno que toca un anexo se parte en pedazos por su
## cabecera (anexo a cabecera, cabecera a la otra punta; o anexo, cabecera, otra cabecera, anexo).
## Los pedazos son copias con el mismo id, carga y cantidad; los que no tocan anexos quedan iguales.
static func split(flows: Array[ProductionFlow], hubs: Dictionary[StringName, StringName]) -> Array[ProductionFlow]:
	var legs: Array[ProductionFlow] = []
	for flow: ProductionFlow in flows:
		var stops: Array[StringName] = route_stops(flow.from_station, flow.to_station, hubs)
		if stops.size() == 2:
			legs.append(flow)
			continue
		for index: int in stops.size() - 1:
			legs.append(_leg(flow, stops[index], stops[index + 1]))
	return legs


## Lógica pura: por dónde pasa lo que va de `from` a `to`, las dos puntas incluidas.
static func route_stops(from: StringName, to: StringName, hubs: Dictionary[StringName, StringName]) -> Array[StringName]:
	var stops: Array[StringName] = [from]
	var from_hub: StringName = hubs.get(from, &"")
	var to_hub: StringName = hubs.get(to, &"")
	if from_hub != &"" and from_hub != to:
		stops.append(from_hub)
	if to_hub != &"" and to_hub != from and to_hub != stops[stops.size() - 1]:
		stops.append(to_hub)
	stops.append(to)
	return stops


## Los anexos de una cabecera, en el orden en que aparecen.
static func annexes_of(hub: StringName, hubs: Dictionary[StringName, StringName]) -> Array[StringName]:
	var found: Array[StringName] = []
	for annex: StringName in hubs:
		if hubs[annex] == hub:
			found.append(annex)
	return found


static func _leg(flow: ProductionFlow, from: StringName, to: StringName) -> ProductionFlow:
	var leg := ProductionFlow.new(from, to, flow.item_id, flow.amount)
	leg.id = flow.id
	leg.round_trip = flow.round_trip
	leg.custom_name = flow.custom_name
	leg.last_delivered = flow.last_delivered
	leg.pending = flow.pending
	return leg
