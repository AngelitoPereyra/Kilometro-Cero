class_name ConstructionSite
extends Interactable
## Obra (tarea 62b.4, D127, D130): un edificio a medio hacer con un cartel de lo que falta. La
## lleva una secundaria de tipo obra (`mission`, MissionData.Kind.BUILD): sus materiales no se
## entregan en el tablero sino acá. F acepta la obra si está disponible y, en curso, entrega desde
## los vagones de los trenes del jugador detenidos en la estación, la mano (entero) y la mochila
## (StationGoods). Regla de D127: lo que traen los automáticos nunca entra (no son trenes
## detenidos del jugador) y tampoco lo del tren prestado (`StationGoods.own_trains_only`).
## Se arma de a partes a la vista: cada parte de "Partes" aparece (brota) cuando llega su parte de
## los materiales. Al terminar, lo de "Antes" (las carpas) se va con humo, brota lo de "Despues"
## (las casas terminadas) y la secundaria se cumple (MissionBoard.deliver_build).
## Al cargar una partida aparece quieta en su estado. En el editor se ve todo, para acomodarlo.
## Va dentro de una Station (si no, busca la de `mission.station_id`). Hijos: "Cartel" (Label3D),
## "Antes", "Andamios" (se ven mientras está en curso), "Partes" y "Despues" (Node3D con piezas).
## Escena de bosquejo: scenes/stations/construction_site.tscn (dos casitas).

## Se entregaron materiales: id de objeto -> unidades.
signal materials_delivered(amounts: Dictionary[StringName, int])
## Apareció una parte más (cuántas se ven ahora).
signal part_built(count: int)
## La obra quedó terminada (jugando, no al cargar).
signal finished

const SIGN_PATH: NodePath = ^"Cartel"
const BEFORE_PATH: NodePath = ^"Antes"
const SCAFFOLD_PATH: NodePath = ^"Andamios"
const PARTS_PATH: NodePath = ^"Partes"
const AFTER_PATH: NodePath = ^"Despues"
## Cada cuánto (s) revisa la misión y escribe el cartel.
const REFRESH_TIME: float = 0.5
## Cuánto (s) queda a la vista el aviso de la última entrega.
const MESSAGE_TIME: float = 4.0
## Cuánto (s) queda a la vista la presentación de la obra aceptada acá.
const INTRO_TIME: float = 12.0
## Hasta qué distancia (m) el cartel cuenta lo que trae el jugador fuera de la zona de la estación.
const PLAYER_RANGE: float = 15.0
## Segundos entre una pieza que brota y la siguiente.
const POP_STAGGER: float = 0.2

## La secundaria de la obra (tipo BUILD).
@export var mission: MissionData

## El tablero de misiones (null: GameState.missions; las pruebas ponen uno propio).
var board: MissionBoard

var _station: Station
var _label: Label3D
var _before: Node3D
var _scaffold: Node3D
var _parts: Node3D
var _after: Node3D
var _timer: float = 0.0
var _message: String = ""
var _message_left: float = 0.0
var _shown_parts: int = -1
var _finished: bool = false
var _player: Player


func _ready() -> void:
	_label = get_node_or_null(SIGN_PATH) as Label3D
	_before = get_node_or_null(BEFORE_PATH) as Node3D
	_scaffold = get_node_or_null(SCAFFOLD_PATH) as Node3D
	_parts = get_node_or_null(PARTS_PATH) as Node3D
	_after = get_node_or_null(AFTER_PATH) as Node3D
	if Engine.is_editor_hint():
		return
	_station = _find_station()
	if mission == null:
		push_warning("ConstructionSite %s: no tiene misión." % name)
		return
	for problem: String in mission.validate():
		push_warning("ConstructionSite %s: %s." % [name, problem])
	if mission.kind != MissionData.Kind.BUILD:
		push_warning("ConstructionSite %s: '%s' no es una obra." % [name, mission.id])
	get_board().register_side(mission)
	refresh(false)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or mission == null:
		return
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			_message = ""
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH_TIME
		refresh()


func get_board() -> MissionBoard:
	return board if board != null else GameState.missions


## La estación de la obra (la que la contiene o la de su misión), o null.
func get_station() -> Station:
	if _station == null and mission != null and is_inside_tree():
		_station = Station.find(get_tree(), mission.station_id)
	return _station


## La misión en juego, o null.
func get_mission() -> Mission:
	return get_board().get_mission(mission.id) if mission != null else null


func get_state() -> Mission.State:
	var current: Mission = get_mission()
	return current.state if current != null else Mission.State.LOCKED


## Qué parte de los materiales ya llegó (0 a 1).
func get_progress() -> float:
	return get_board().get_build_progress(get_mission())


func is_finished() -> bool:
	return _finished


## Las piezas que se arman de a una ("Partes"), en orden.
func get_parts() -> Array[Node3D]:
	if _parts == null:
		return []
	return GrowthCelebration.get_pieces(_parts)


## Cuántas partes se ven ahora.
func get_built_count() -> int:
	return maxi(_shown_parts, 0)


## Lógica pura: cuántas de `count` partes se ven con `progress` (0 a 1) de los materiales.
static func parts_for(progress: float, count: int) -> int:
	if progress >= 1.0:
		return count
	return clampi(floori(progress * count), 0, count)


## Lo que el jugador tiene al alcance para la obra: vagones de su tren detenido en la estación,
## mano y mochila. Nunca lo de un automático ni del tren prestado (D127).
func get_goods(player: Player = null) -> StationGoods:
	var goods := StationGoods.new(get_station(), player if player != null else _find_player())
	goods.own_trains_only = true
	return goods


## Lo que hay al alcance (sin pasajeros): id de objeto -> unidades.
func get_available(player: Player = null) -> Dictionary[StringName, int]:
	var available: Dictionary[StringName, int] = {}
	var all: Dictionary[StringName, int] = get_goods(player).get_available()
	for item_id: StringName in all:
		if not get_board().is_passenger(item_id):
			available[item_id] = all[item_id]
	return available


## Lo que F entregaría ahora (lo que falta y está al alcance).
func get_delivery_plan(player: Player = null) -> Dictionary[StringName, int]:
	if mission == null:
		return {}
	return get_board().plan_build(mission.id, get_available(player))


func can_interact(player: Player) -> bool:
	if not super.can_interact(player):
		return false
	var state: Mission.State = get_state()
	return state == Mission.State.AVAILABLE or state == Mission.State.ACTIVE


func get_prompt() -> String:
	match get_state():
		Mission.State.AVAILABLE:
			return "Aceptar la obra: " + mission.title
		Mission.State.ACTIVE:
			var plan: Dictionary[StringName, int] = get_delivery_plan()
			if not plan.is_empty():
				return "Entregar %s para la obra" % _amounts_text(plan)
	return "Mirar la obra"


## Acepta la obra disponible y cuenta su presentación en el cartel. True si estaba disponible.
func accept() -> bool:
	if mission == null or get_state() != Mission.State.AVAILABLE or not get_board().start(mission.id):
		return false
	_say("%s\n[%s]" % [mission.intro, mission.title], INTRO_TIME)
	refresh()
	return true


## Entrega materiales para la obra (vagones del jugador, mano y mochila, en ese orden). Devuelve
## lo entregado.
func deliver(player: Player = null) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	if mission == null:
		return result
	var goods: StationGoods = get_goods(player)
	var plan: Dictionary[StringName, int] = get_delivery_plan(player)
	for item_id: StringName in plan:
		var taken: int = goods.take(item_id, plan[item_id])
		if taken <= 0:
			continue
		var accepted: int = get_board().deliver_build(mission.id, item_id, taken)
		if accepted < taken:
			# No debería pasar (el plan es de recién), pero nada se pierde.
			_give_back(goods, item_id, taken - accepted)
		if accepted > 0:
			result[item_id] = accepted
	if not result.is_empty():
		_say("Entregaste " + _amounts_text(result), MESSAGE_TIME)
		materials_delivered.emit(result)
	refresh()
	return result


## Muestra el estado de la misión: partes, carpas, andamios y casas; `animate` (jugando) hace
## brotar lo nuevo y al terminar echa humo; sin animar (al cargar) queda todo quieto.
func refresh(animate: bool = true) -> void:
	if mission == null:
		return
	var state: Mission.State = get_state()
	if state == Mission.State.COMPLETED:
		if not _finished:
			_finish(animate)
	else:
		_show_parts(parts_for(get_progress(), get_parts().size()) if state == Mission.State.ACTIVE else 0, animate)
		_set_visible(_before, true)
		_set_visible(_scaffold, state == Mission.State.ACTIVE)
		_set_visible(_after, false)
	if _label != null:
		_label.text = build_text()


func build_text() -> String:
	if mission == null:
		return ""
	var lines: PackedStringArray = []
	match get_state():
		Mission.State.AVAILABLE:
			lines.append("Obra: " + mission.title)
			var giver: String = get_board().get_side_giver(mission.id)
			lines.append(("Hablá con %s o F para aceptarla" % giver) if giver != "" else "F para aceptarla")
		Mission.State.ACTIVE:
			lines.append("Obra: " + mission.title)
			var current: Mission = get_mission()
			var remaining: Dictionary[StringName, int] = current.get_remaining()
			var parts: PackedStringArray = []
			for item_id: StringName in current.required:
				parts.append("%d de %d %s" % [current.delivered.get(item_id, 0), current.required[item_id], get_board().name_of(item_id)])
			lines.append("Faltan %s (van %s)" % [_amounts_text(remaining), ", ".join(parts)])
			var plan: Dictionary[StringName, int] = get_delivery_plan()
			if not plan.is_empty():
				lines.append("F: entregar " + _amounts_text(plan))
		Mission.State.COMPLETED:
			if _message.is_empty():
				return ""
	if not _message.is_empty():
		lines.append(_message)
	return "\n".join(lines)


func _on_interact(player: Player) -> void:
	_player = player
	if get_state() == Mission.State.AVAILABLE:
		accept()
	else:
		deliver(player)


# Muestra las primeras `count` partes; jugando, las nuevas brotan.
func _show_parts(count: int, animate: bool) -> void:
	var pieces: Array[Node3D] = get_parts()
	var delay: float = 0.0
	var grew: bool = false
	for index: int in pieces.size():
		var piece: Node3D = pieces[index]
		var wanted: bool = index < count
		if wanted and not piece.visible:
			piece.visible = true
			grew = true
			if animate and _shown_parts >= 0:
				GrowthCelebration.pop(piece, delay)
				delay += POP_STAGGER
		elif not wanted and piece.visible:
			piece.visible = false
	var before: int = _shown_parts
	_shown_parts = count
	if grew and before >= 0 and animate:
		part_built.emit(count)


# La obra terminada: carpas y andamios afuera (con humo), todas las partes y lo de "Despues".
func _finish(animate: bool) -> void:
	_finished = true
	var playing: bool = animate and _shown_parts >= 0
	_show_parts(get_parts().size(), playing)
	if playing and _before != null and _before.visible:
		var with_sound: bool = true
		for piece: Node3D in GrowthCelebration.get_pieces(_before):
			if piece.visible:
				SmokePuff.spawn(self, piece.global_position + Vector3(0.0, 1.0, 0.0), 0.8, with_sound)
				with_sound = false
	_set_visible(_before, false)
	_set_visible(_scaffold, false)
	_set_visible(_after, true)
	if playing and _after != null:
		var delay: float = POP_STAGGER
		for piece: Node3D in GrowthCelebration.get_pieces(_after):
			GrowthCelebration.pop(piece, delay)
			delay += POP_STAGGER
		_say("¡Obra terminada! %s" % mission.title, MESSAGE_TIME)
		finished.emit()


func _say(text: String, seconds: float) -> void:
	_message = text
	_message_left = seconds
	if _label != null:
		_label.text = build_text()


static func _set_visible(node: Node3D, value: bool) -> void:
	if node != null:
		node.visible = value


# El jugador para los textos: el de la zona de la estación, el último que la usó o el de la escena,
# si está cerca.
func _find_player() -> Player:
	var station: Station = get_station()
	if station != null and station.get_present_player() != null:
		return station.get_present_player()
	var candidates: Array[Player] = []
	if is_instance_valid(_player):
		candidates.append(_player)
	var scene: Node = get_tree().current_scene if is_inside_tree() else null
	if scene != null:
		for child: Node in scene.get_children():
			if child is Player:
				candidates.append(child)
	for candidate: Player in candidates:
		if candidate.is_inside_tree() and candidate.global_position.distance_to(global_position) <= PLAYER_RANGE:
			return candidate
	return null


func _amounts_text(amounts: Dictionary[StringName, int]) -> String:
	var parts: PackedStringArray = []
	for item_id: StringName in amounts:
		parts.append("%d %s" % [amounts[item_id], get_board().name_of(item_id)])
	return ", ".join(parts)


func _find_station() -> Station:
	var node: Node = get_parent()
	while node != null:
		if node is Station:
			return node
		node = node.get_parent()
	return null


func _give_back(goods: StationGoods, item_id: StringName, amount: int) -> void:
	var item: ItemData = goods.find_item(item_id)
	if item == null:
		item = get_board().find_item(item_id)
	var stored: int = goods.store(item, amount)
	if stored < amount:
		push_warning("ConstructionSite: no se pudieron devolver %d %s." % [amount - stored, item_id])
