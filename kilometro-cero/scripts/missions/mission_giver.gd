class_name MissionGiver
extends Interactable
## Un poblador (o un objeto que cuenta algo, como un cartel viejo) que da misiones secundarias
## (D80, tarea 58). Se pone en cualquier lugar del pueblo, la ciudad o la estación de carga.
## Registra sus misiones en GameState.missions al empezar. Con F:
## - si tiene una disponible, la da y cuenta su presentación (`intro`);
## - si se cumplió una y todavía no contó el cierre, cuenta el cierre (`outro`);
## - si hay una en curso, recuerda lo que falta.
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


## Si tiene algo nuevo: una misión para dar o un cierre para contar.
func has_news() -> bool:
	return _find(Mission.State.AVAILABLE) != null or _find_untold() != null


## Lo que dice al hablarle (también lo hace: da la misión o marca el cierre como contado).
func talk() -> String:
	var board: MissionBoard = GameState.missions
	var text: String = ""
	var untold: Mission = _find_untold()
	var available: Mission = _find(Mission.State.AVAILABLE)
	var active: Mission = _find(Mission.State.ACTIVE)
	if untold != null:
		untold.outro_told = true
		text = untold.data.outro if not untold.data.outro.is_empty() else "¡Gracias!"
	elif available != null:
		board.start(available.id)
		text = "%s\n[%s]" % [available.data.intro, board.get_title(available)]
	elif active != null:
		var steps: PackedStringArray = board.get_pending_steps(active)
		text = "[%s] %s" % [board.get_title(active), "; ".join(steps) if not steps.is_empty() else "listo"]
	else:
		text = "No tengo nada más para contarte."
	if not speaker.is_empty():
		text = "%s: %s" % [speaker, text]
	_show(text)
	said.emit(text)
	return text


func _on_interact(_player: Player) -> void:
	talk()


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
