class_name AgendaText
extends RefCounted
## Los textos de las pestañas "Agenda" y "Tren" del TAB (tarea 62.8, D124). Lógica pura: arma
## BBCode para un RichTextLabel con lo que recibe; InventoryUI le pasa el tablero, el modelo,
## los automáticos y el tren del jugador.

## Para el fondo crema de la ventana (tarea 62.8).
const COLOR_TITLE: String = "#7a4a12"
const COLOR_DIM: String = "#77705f"
const COLOR_OK: String = "#2f7d1f"


## La agenda: por estación, el nivel y las misiones en curso con sus pasos; después los flujos
## y los trenes automáticos con su horario. `extra`: renglones que agrega la escena (el coche de
## regalo, los vagones regalados).
static func agenda(board: MissionBoard, model: ProductionModel, autos: AutoTrains, extra: PackedStringArray = PackedStringArray()) -> String:
	var lines: PackedStringArray = []
	if model != null and board != null:
		lines.append(title("Estaciones"))
		for station_id: StringName in model.get_station_ids():
			lines.append(station_line(board, model, station_id))
			for mission: Mission in board.get_active_missions(station_id):
				lines.append(mission_line(board, mission))
		var flows: Array[ProductionFlow] = model.get_flows()
		lines.append("")
		lines.append(title("Flujos"))
		if flows.is_empty():
			lines.append(dim("Todavía ninguno: cumplí una misión principal para que nazca el primero."))
		for flow: ProductionFlow in flows:
			lines.append("• %s · entregó %d" % [flow.describe(), flow.last_delivered])
	lines.append("")
	lines.append(title("Trenes automáticos"))
	var runs: Array[AutoTrainRun] = autos.get_runs() if autos != null else ([] as Array[AutoTrainRun])
	if runs.is_empty():
		lines.append(dim("No hay ninguno andando."))
	for run: AutoTrainRun in runs:
		lines.append(run_line(board, run, AutoTrains.now_hours()))
	if not extra.is_empty():
		lines.append("")
		lines.append(title("Además"))
		for line: String in extra:
			lines.append("• " + line)
	return "\n".join(lines)


## "Olavarría · nivel 2 de 4 · creciendo (1 de 2 días)".
static func station_line(board: MissionBoard, model: ProductionModel, station_id: StringName) -> String:
	var text: String = "[b]%s[/b] · nivel %d de %d" % [board.station_name(station_id), model.get_level(station_id), model.get_data(station_id).get_max_level()]
	if model.get_days_to_grow(station_id) > 0 and model.get_missing(station_id).is_empty():
		text += " · [color=%s]creciendo (%d de %d días)[/color]" % [COLOR_OK, model.get_growth_progress(station_id), model.get_days_to_grow(station_id)]
	return text


## "   ▸ Troncos para Sierras Bayas: faltan 12 troncos".
static func mission_line(board: MissionBoard, mission: Mission) -> String:
	var steps: PackedStringArray = board.get_pending_steps(mission)
	var name: String = board.get_title(mission) if mission.main else mission.data.title
	return "    ▸ %s%s" % [name, (": " + ", ".join(steps)) if not steps.is_empty() else ""]


## Un automático: dónde está y su horario; parado, cuándo sale.
static func run_line(board: MissionBoard, run: AutoTrainRun, now: float) -> String:
	var station_name: Callable = func(station_id: StringName) -> String:
		return board.station_name(station_id) if board != null else String(station_id)
	var text: String = "• " + run.status_text(station_name)
	if not run.is_moving() and run.due > now:
		text += " · [color=%s]próxima salida %s%s[/color]" % [COLOR_TITLE, AutoTrainRun.hour_text(run.due), " (mañana)" if floori(run.due / GameClock.HOURS_PER_DAY) > floori(now / GameClock.HOURS_PER_DAY) else ""]
	return text


## El tren del jugador vagón por vagón, de adelante para atrás, con lo que lleva cada uno.
static func train(vehicles: Array[Vehicle], board: MissionBoard) -> String:
	if vehicles.is_empty():
		return dim("No encontré tu tren. Subite a la cabina (F) o acercate a la locomotora.")
	var lines: PackedStringArray = [title("Tu tren · %d %s" % [vehicles.size(), "vehículo" if vehicles.size() == 1 else "vehículos"])]
	var number: int = 0
	for vehicle: Vehicle in vehicles:
		number += 1
		lines.append(vehicle_line(number, vehicle, board))
	return "\n".join(lines)


## "2. plataforma · 18 / 20 · 18 troncos".
static func vehicle_line(number: int, vehicle: Vehicle, board: MissionBoard) -> String:
	var name: String = vehicle.data.display_name if vehicle.data != null and vehicle.data.display_name != "" else String(vehicle.name)
	var wagon := vehicle as Wagon
	var cargo: StorageContainer = wagon.get_cargo() if wagon != null else null
	if cargo == null:
		return "%d. [b]%s[/b]" % [number, name]
	var used: int = cargo.get_total()
	var text: String = "%d. [b]%s[/b] · %d / %d" % [number, name, used, used + cargo.get_free_space()]
	text += " · " + (cargo_text(cargo, board) if used > 0 else dim("vacío"))
	return text


## "18 troncos, 2 piedra".
static func cargo_text(cargo: StorageContainer, board: MissionBoard) -> String:
	var amounts: Dictionary[StringName, int] = {}
	for index: int in cargo.get_stack_count():
		var stack: ItemStack = cargo.peek(index)
		if stack != null and stack.item != null:
			amounts[stack.item.id] = amounts.get(stack.item.id, 0) + stack.quantity
	var parts: PackedStringArray = []
	for item_id: StringName in amounts:
		parts.append("%d %s" % [amounts[item_id], board.name_of(item_id) if board != null else String(item_id)])
	return ", ".join(parts)


static func title(text: String) -> String:
	return "[color=%s][b]%s[/b][/color]" % [COLOR_TITLE, text]


static func dim(text: String) -> String:
	return "[color=%s]%s[/color]" % [COLOR_DIM, text]
