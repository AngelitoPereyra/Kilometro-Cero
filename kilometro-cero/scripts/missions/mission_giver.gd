class_name MissionGiver
extends Interactable
## Un poblador (o un objeto que cuenta algo, como un cartel viejo) que da misiones secundarias
## (D80, tarea 58). Se pone en cualquier lugar del pueblo, la ciudad o la estación de carga.
## Registra sus misiones en GameState.missions al empezar. Con F:
## - si tiene una disponible, la da y cuenta su presentación (`intro`); si la misión trae
##   herramientas (`MissionData.gives_tools`, tarea 62.5), se las da al jugador;
## - si se cumplió una y todavía no contó el cierre, cuenta el cierre (`outro`);
## - si hay una en curso, recuerda lo que falta.
## Quien da las principales de una estación (`main_station`, tarea 62b.3, D128: el jefe de
## estación, la comisión de fomento, el capataz) pide que le avisen cuando el camino está
## habilitado: al hablarle con el camino abierto recibe el aviso (MissionBoard.report) y cuenta si
## el Ferrocarril manda el tren solo o si el maquinista está enfermo y el jugador puede llevar el
## prestado (se pide en el tablero del productor).
## Lo que dice se ve en su Label3D "Globo" durante SPEECH_TIME; el resto del tiempo el globo
## muestra "!" si tiene algo para dar o contar. La interfaz definitiva llega con la tarea 67.

## Dijo algo (para la interfaz).
signal said(text: String)

const BUBBLE_PATH: NodePath = ^"Globo"
## Cuánto (s) queda a la vista lo que dijo.
const SPEECH_TIME: float = 10.0

## Nombre del que habla ("Don Aurelio, el jefe de estación").
@export var speaker: String = ""
## Sus misiones, en el orden en que las da.
@export var missions: Array[MissionData] = []
## La estación cuyas principales da (tarea 62b.3). Vacío: ninguna.
@export var main_station: StringName = &""

var _bubble: Label3D
var _speech_left: float = 0.0


func _ready() -> void:
	_bubble = get_node_or_null(BUBBLE_PATH) as Label3D
	for mission_data: MissionData in missions:
		if mission_data == null:
			push_warning("MissionGiver %s: tiene una misión vacía." % name)
			continue
		for problem: String in mission_data.validate():
			push_warning("MissionGiver %s: %s." % [name, problem])
		GameState.missions.register_side(mission_data)
		GameState.missions.set_side_giver(mission_data.id, get_short_name())
	if main_station != &"":
		GameState.missions.register_main_giver(main_station, get_short_name())
	_update_bubble()


func _process(delta: float) -> void:
	if _speech_left > 0.0:
		_speech_left -= delta
		if _speech_left <= 0.0:
			_update_bubble()
	elif _bubble != null:
		_update_bubble()


func get_prompt() -> String:
	return "Hablar con " + (speaker if not speaker.is_empty() else String(name))


## Su nombre corto para los pasos de las misiones: "Doña Clara" de "Doña Clara, de la comisión".
func get_short_name() -> String:
	return speaker.get_slice(",", 0).strip_edges() if not speaker.is_empty() else String(name)


## Si tiene algo nuevo: una misión para dar, un cierre para contar o un aviso para recibir.
func has_news() -> bool:
	return _find(Mission.State.AVAILABLE) != null or _find_untold() != null or _find_main_to_report() != null


## Lo que dice al hablarle (también lo hace: da la misión o marca el cierre como contado).
## `player`: a quien le da las herramientas de la misión (null: no da ninguna).
func talk(player: Player = null) -> String:
	var board: MissionBoard = GameState.missions
	var text: String = ""
	var untold: Mission = _find_untold()
	var to_report: Mission = _find_main_to_report()
	var available: Mission = _find(Mission.State.AVAILABLE)
	var active: Mission = _find(Mission.State.ACTIVE)
	var main_active: Mission = _find_main_with_steps()
	if untold != null:
		untold.outro_told = true
		text = untold.data.outro if not untold.data.outro.is_empty() else "¡Gracias!"
	elif to_report != null:
		board.report(to_report.id)
		text = report_text(to_report)
	elif available != null:
		board.start(available.id)
		text = "%s\n[%s]" % [available.data.intro, board.get_title(available)]
		var given: PackedStringArray = _give_tools(available.data, player)
		if not given.is_empty():
			text += "\nTe da: %s" % ", ".join(given)
	elif active != null:
		var steps: PackedStringArray = board.get_pending_steps(active)
		text = "[%s] %s" % [board.get_title(active), "; ".join(steps) if not steps.is_empty() else "listo"]
	elif main_active != null:
		text = "[%s] %s" % [board.get_title(main_active), "; ".join(board.get_pending_steps(main_active))]
	else:
		text = "No tengo nada más para contarte."
	if not speaker.is_empty():
		text = "%s: %s" % [speaker, text]
	_show(text)
	said.emit(text)
	return text


func _on_interact(player: Player) -> void:
	talk(player)


# Le da al jugador las herramientas de la misión que no tenga. Devuelve sus nombres.
func _give_tools(mission_data: MissionData, player: Player) -> PackedStringArray:
	var names: PackedStringArray = []
	var keys: KeyItems = player.get_key_items() if player != null else null
	if keys == null:
		return names
	for tool: KeyItemData in mission_data.gives_tools:
		if tool != null and keys.add(tool):
			names.append(tool.display_name)
	return names


## Lo que cuenta al recibir el aviso de una principal (tarea 62b.3).
static func report_text(mission: Mission) -> String:
	var board: MissionBoard = GameState.missions
	var source: String = board.station_name(mission.source_id)
	var item: String = board.name_of(mission.item_id)
	if mission.offered:
		return "¡Gracias por avisar! El Ferrocarril arma en %s el tren con %d %s, pero el maquinista está enfermo. Si querés traerlo vos, pedilo en el tablero de %s; si no, mañana lo trae uno de reemplazo." % [source, mission.required.get(mission.item_id, 0), item, source]
	var when: String = "desde mañana" if board.flows_start_next_day else "desde hoy"
	return "¡Gracias por avisar! El maquinista ya se curó: %s el Ferrocarril trae %d %s por día desde %s." % [when, mission.flow_amount, item, source]


# La primera principal de su estación a la que ya se le puede avisar, o null.
func _find_main_to_report() -> Mission:
	if main_station == &"":
		return null
	for mission: Mission in GameState.missions.get_main_missions(main_station):
		if GameState.missions.can_report(mission):
			return mission
	return null


# La primera principal en curso de su estación con algo por hacer, o null.
func _find_main_with_steps() -> Mission:
	if main_station == &"":
		return null
	for mission: Mission in GameState.missions.get_main_missions(main_station):
		if not GameState.missions.get_pending_steps(mission).is_empty():
			return mission
	return null


func _find(state: Mission.State) -> Mission:
	for mission_data: MissionData in missions:
		var mission: Mission = GameState.missions.get_mission(mission_data.id) if mission_data != null else null
		if mission != null and mission.state == state:
			return mission
	return null


func _find_untold() -> Mission:
	for mission_data: MissionData in missions:
		var mission: Mission = GameState.missions.get_mission(mission_data.id) if mission_data != null else null
		if mission != null and mission.is_completed() and not mission.outro_told:
			return mission
	return null


func _show(text: String) -> void:
	_speech_left = SPEECH_TIME
	if _bubble != null:
		_bubble.text = text


func _update_bubble() -> void:
	if _bubble != null:
		_bubble.text = "!" if has_news() else ""
