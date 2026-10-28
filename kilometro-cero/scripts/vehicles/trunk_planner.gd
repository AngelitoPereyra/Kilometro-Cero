class_name TrunkPlanner
extends RefCounted
## Cómo se arman las troncales de una línea (D118, tarea 61d). Lógica pura: trabaja con los ids
## de las estaciones de la línea en orden (TrunkLine.get_station_ids) y con los flujos.
## - Un flujo va por la línea si sus dos estaciones están en ella (fits).
## - La troncal recorre solo el pedazo que usan sus flujos (span): de la estación más cercana a
##   una punta de la línea a la más cercana a la otra, estirado hasta la ciudad más cercana de
##   cada lado o la punta de la línea (anchor, 61d.2): termina y descansa donde hay andenes.
## - Vagones por tramo (pack): cada flujo se parte en cargas de hasta `capacity` unidades, cada
##   una ocupa un vagón solo entre sus dos estaciones, y un vagón libre en un pedazo se usa en
##   otro (la plataforma que bajó troncos en el pueblo sube los de la maderera). Las cargas que
##   van en sentidos distintos no se estorban (una va a la ida y otra a la vuelta); la gente que
##   va y vuelve ocupa los dos.
## - Servicios (split_services): los flujos, del más viejo al más nuevo, entran en el primer
##   servicio donde sus vagones caben en lo que arrastra la locomotora; si no, en el siguiente
##   (otro tren del mismo recorrido, a otra hora).
## - Vagones por tipo (tarea 62): con `kind_of` (func(item_id) -> tipo de vagón) cada carga va
##   en su tipo (piedra y troncos en plataforma, cemento en vagón cerrado) y solo comparte vagón
##   con cargas del mismo tipo; `capacities` da los lugares de cada tipo. Sin `kind_of`, todo va
##   en un solo tipo con `capacity` lugares.
## Índices: la posición de cada estación en la línea. "dir" de una carga sobre la línea: 1 hacia
## el final de la línea, -1 hacia el principio, 0 los dos (ida y vuelta).


## Si el flujo va por la línea: sus dos estaciones están en ella.
static func fits(flow: ProductionFlow, line: Array[StringName]) -> bool:
	return flow != null and flow.from_station != flow.to_station and line.has(flow.from_station) and line.has(flow.to_station)


## El pedazo de la línea que usan los flujos: Vector2i(índice menor, índice mayor), o (-1, -1)
## si ninguno va por ella.
static func span(flows: Array[ProductionFlow], line: Array[StringName]) -> Vector2i:
	var low: int = -1
	var high: int = -1
	for flow: ProductionFlow in flows:
		if not fits(flow, line):
			continue
		for index: int in [line.find(flow.from_station), line.find(flow.to_station)]:
			low = index if low < 0 else mini(low, index)
			high = maxi(high, index)
	return Vector2i(low, high)


## Estira el pedazo hasta la ciudad (o puerto) más cercana de cada lado, o hasta la punta de la
## línea si no hay (tarea 61d.2): así una troncal nunca termina ni descansa en un pueblo.
## `hubs`: por cada estación de la línea, si es ciudad o puerto.
static func anchor(reach: Vector2i, hubs: Array[bool]) -> Vector2i:
	if reach.x < 0 or hubs.is_empty():
		return reach
	var low: int = reach.x
	var high: int = reach.y
	while low > 0 and not hubs[low]:
		low -= 1
	while high < hubs.size() - 1 and not hubs[high]:
		high += 1
	return Vector2i(low, high)


## Las estaciones de la línea de `from` a `to` (las dos incluidas), en el orden del viaje.
static func stops(line: Array[StringName], from: StringName, to: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var a: int = line.find(from)
	var b: int = line.find(to)
	if a < 0 or b < 0:
		return result
	var step: int = 1 if b >= a else -1
	var index: int = a
	while true:
		result.append(line[index])
		if index == b:
			break
		index += step
	return result


## Las cargas de los flujos: {"item", "units", "from", "to", "low", "high", "dir", "kind"} de a
## lo sumo los lugares de su tipo de vagón cada una (dir sobre la línea). "kind" es &"" sin
## `kind_of` (tarea 62).
static func chunks(flows: Array[ProductionFlow], line: Array[StringName], capacity: int, kind_of: Callable = Callable(), capacities: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for flow: ProductionFlow in flows:
		if not fits(flow, line):
			continue
		var kind: StringName = kind_of.call(flow.item_id) if kind_of.is_valid() else &""
		var room: int = maxi(int(capacities.get(kind, capacity)), 1)
		var a: int = line.find(flow.from_station)
		var b: int = line.find(flow.to_station)
		var dir: int = 0 if flow.round_trip else (1 if b > a else -1)
		var left: int = maxi(flow.amount, 1)
		while left > 0:
			var units: int = mini(left, room)
			result.append({"item": flow.item_id, "units": units, "from": flow.from_station, "to": flow.to_station, "low": mini(a, b), "high": maxi(a, b), "dir": dir, "kind": kind})
			left -= units
	return result


## Reparte las cargas en vagones: cada vagón es {"loads": [cargas], "kind"} y dos cargas del
## mismo tipo de vagón lo comparten si no se pisan (otro pedazo de la línea u otro sentido). Las que empiezan antes van primero.
static func pack(loads: Array[Dictionary]) -> Array[Dictionary]:
	var sorted: Array[Dictionary] = loads.duplicate()
	sorted.sort_custom(_starts_before)
	var wagons: Array[Dictionary] = []
	for part: Dictionary in sorted:
		var slot: int = -1
		for index: int in wagons.size():
			if _has_room(wagons[index], part):
				slot = index
				break
		if slot < 0:
			wagons.append({"loads": [] as Array[Dictionary], "kind": part.get("kind", &"")})
			slot = wagons.size() - 1
		(wagons[slot]["loads"] as Array[Dictionary]).append(part)
	return wagons


## Los servicios de una troncal: listas de flujos (del más viejo al más nuevo en cada una).
## Un flujo que no entra en ningún servicio abre otro; si no entra ni solo, ese servicio lleva
## lo que arrastre la locomotora.
static func split_services(flows: Array[ProductionFlow], line: Array[StringName], capacity: int, max_wagons: int, kind_of: Callable = Callable(), capacities: Dictionary = {}) -> Array:
	var services: Array = []
	for flow: ProductionFlow in flows:
		if not fits(flow, line):
			continue
		var placed: bool = false
		for service: Array[ProductionFlow] in services:
			var trial: Array[ProductionFlow] = service.duplicate()
			trial.append(flow)
			if pack(chunks(trial, line, capacity, kind_of, capacities)).size() <= max_wagons:
				service.append(flow)
				placed = true
				break
		if not placed:
			var fresh: Array[ProductionFlow] = [flow]
			services.append(fresh)
	return services


## Los vagones de una troncal que va de `home` a `away`, en el formato de
## AutoTrains.plan_wagons ({"kind", "item", "dir", "units"}, dir 1 de `home` hacia `away`, -1 al
## revés, 0 los dos) más "loads": lo que lleva por pedazo ({"item", "units", "from", "to",
## "dir"}, con el mismo dir). "item", "units" y "dir" resumen lo que se ve hasta que la carga
## cambie en cada parada (tarea 61d.3): la primera carga, la mayor y el sentido de sus cargas.
## "kind" es el tipo de cada vagón según `kind_of` (tarea 62) o, sin él, `kind`.
static func plan_wagons(flows: Array[ProductionFlow], line: Array[StringName], home: StringName, away: StringName, kind: StringName, capacity: int, max_wagons: int, kind_of: Callable = Callable(), capacities: Dictionary = {}) -> Array[Dictionary]:
	var forward: int = 1 if line.find(away) >= line.find(home) else -1
	var wagons: Array[Dictionary] = []
	for packed: Dictionary in pack(chunks(flows, line, capacity, kind_of, capacities)):
		if wagons.size() >= max_wagons:
			break
		var loads: Array[Dictionary] = []
		var units: int = 0
		var dirs: Dictionary = {}
		for part: Dictionary in packed["loads"]:
			var dir: int = int(part["dir"]) * forward
			loads.append({"item": part["item"], "units": part["units"], "from": part["from"], "to": part["to"], "dir": dir})
			units = maxi(units, int(part["units"]))
			dirs[dir] = true
		var shown_dir: int = int(dirs.keys()[0]) if dirs.size() == 1 else 0
		var wagon_kind: StringName = packed["kind"] if packed["kind"] != &"" else kind
		wagons.append({"kind": wagon_kind, "item": loads[0]["item"], "dir": shown_dir, "units": units, "loads": loads})
	return wagons


static func _starts_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["low"]) != int(b["low"]):
		return int(a["low"]) < int(b["low"])
	return int(a["high"]) > int(b["high"])


static func _has_room(wagon: Dictionary, part: Dictionary) -> bool:
	if wagon.get("kind", &"") != part.get("kind", &""):
		return false
	for other: Dictionary in wagon["loads"]:
		var same_way: bool = int(other["dir"]) == 0 or int(part["dir"]) == 0 or int(other["dir"]) == int(part["dir"])
		if same_way and int(other["low"]) < int(part["high"]) and int(part["low"]) < int(other["high"]):
			return false
	return true
