extends Node3D
## Prueba de la tarea 55: herramientas clave (KeyItems, D83), obstáculos que cortan un tramo
## (Obstacle con Clearable, D78) y árboles para talar (Harvestable).
## ciudad --(a_b)-- pueblo --(b_c, con un árbol caído y una piedra)-- maderera.
## Primero corre las comprobaciones (sin tocar nada, tarda un par de segundos) y después vuelve
## a cargar la escena limpia para jugar: el hacha está en el piso al lado tuyo, la barreta en
## el pueblo, y hay árboles para talar junto a la ciudad.

const CONTROLES: String = "WASD: caminar · E: recoger · clic izquierdo: usar la herramienta · F: cabina · T: pasar 24 h\nJuntá el hacha, talá un árbol y cargá los troncos; con el hacha y la barreta despejá b_c y andá con el tren hasta la maderera."
const PASO_S: float = 1.0 / 60.0

## Ya se corrieron las comprobaciones: al recargar la escena queda solo para jugar.
static var _probado: bool = false

@onready var _network: RailNetwork = $RailNetwork
@onready var _ida: Path3D = $Ida
@onready var _ramal: Path3D = $Ramal
@onready var _loco: Vehicle = $Ida/Locomotive
@onready var _flatcar: Wagon = $Ida/Flatcar
@onready var _arbol_caido: Obstacle = $ArbolCaido
@onready var _piedra: Obstacle = $Piedra
@onready var _arbol: StaticBody3D = $Arboles/Arbol1
@onready var _hacha: WorldItem = $Hacha
@onready var _barreta: WorldItem = $Barreta
@onready var _player: Player = $Player
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0
var _avisos: Array = []
var _mensaje: String = ""


func _ready() -> void:
	_conectar_mensajes()
	if _probado:
		return
	_probado = true
	EventBus.segment_state_changed.connect(_on_segment_state_changed)
	_probar_logica()
	_probar_bloqueos()
	# Los obstáculos se anotan en la red de forma diferida: al terminar el cuadro ya están.
	await get_tree().process_frame
	await get_tree().physics_frame
	await _probar_escena()

	if _fallos == 0:
		print("Herramientas y obstáculos: todas las comprobaciones pasaron.")
	else:
		push_error("Herramientas y obstáculos: fallaron %d comprobaciones." % _fallos)
	# La escena quedó despejada: se vuelve a cargar entera para jugar.
	get_tree().reload_current_scene.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	var tecla := event as InputEventKey
	if tecla == null or not tecla.pressed or tecla.echo:
		return
	if tecla.physical_keycode == KEY_T:
		GameState.clock.advance(24.0)
		_mensaje = "Pasaron 24 horas: los árboles talados volvieron a crecer."


func _process(_delta: float) -> void:
	var tramos: PackedStringArray = []
	for id: StringName in [&"a_b", &"b_c"]:
		tramos.append("%s %s (%d obstáculos)" % [id, TrackSegment.state_name(_network.get_state(id)), _network.get_blockers(id).size()])
	var llaves: KeyItems = _player.get_key_items()
	_hud.text = "%s\nHerramientas: %s\nTramos: %s · tren %.0f km/h\n%s" % [
		CONTROLES, llaves.describe() if llaves != null else "-", " · ".join(tramos), absf(_loco.speed) * 3.6, _mensaje,
	]


func _probar_logica() -> void:
	_comprobar(not ToolTarget.is_done(2, 3) and ToolTarget.is_done(3, 3) and ToolTarget.is_done(1, 0), "is_done cuenta los golpes (con 0 pedidos, alcanza uno)")
	var lugares: Array[Vector3] = ToolTarget.drop_positions(Vector3(0, 1, 0), 4, 2.0)
	_comprobar(lugares.size() == 4 and is_equal_approx(lugares[0].distance_to(Vector3(0, 1, 0)), 2.0) and is_equal_approx(lugares[0].y, 1.0), "Los objetos caen en un círculo alrededor")
	_comprobar(ToolTarget.drop_positions(Vector3.ONE, 1, 2.0) == ([Vector3.ONE] as Array[Vector3]), "Uno solo cae en el centro")
	_comprobar(ToolUser.failure_text(&"missing_tool", "hacha") == "Hace falta: hacha.", "Texto de herramienta faltante")

	var hacha: KeyItemData = load("res://data/items/axe.tres")
	var llaves := KeyItems.new()
	var agregadas: Array = []
	llaves.item_added.connect(func(item: KeyItemData) -> void: agregadas.append(item.id))
	_comprobar(llaves.has(&"") and not llaves.has(&"axe") and llaves.describe() == "ninguna", "Sin herramientas: solo lo que se hace con las manos")
	_comprobar(llaves.add(hacha) and not llaves.add(hacha) and llaves.get_count() == 1, "El hacha se suma una sola vez")
	_comprobar(llaves.has(&"axe") and agregadas == [&"axe"] and llaves.describe() == "hacha", "Tiene el hacha y se avisó una vez")
	_comprobar(llaves.remove(&"axe") and not llaves.has(&"axe") and not llaves.remove(&"axe"), "Se puede quitar")
	llaves.free()


# Red por código: X --(xy)-- Y. Los bloqueos cortan el tramo y, al irse, lo dejan como estaba.
func _probar_bloqueos() -> void:
	var red := RailNetwork.new()
	var curva := Path3D.new()
	curva.curve = Curve3D.new()
	curva.curve.add_point(Vector3.ZERO)
	curva.curve.add_point(Vector3(0, 0, -50))
	var via := TrackSegment.new()
	via.segment_id = &"xy"
	via.from_station = &"X"
	via.to_station = &"Y"
	curva.add_child(via)
	red.add_track(via)
	var uno := RefCounted.new()
	var otro := RefCounted.new()

	_avisos.clear()
	_comprobar(red.add_blocker(&"xy", uno) and red.is_cut(&"xy") and red.is_blocked(&"xy"), "Un bloqueo corta el tramo")
	_comprobar(_avisos == [[&"xy", TrackSegment.State.CUT]], "Y se avisa por EventBus")
	_comprobar(not red.add_blocker(&"nada", uno), "No se bloquea un tramo que no existe")
	_comprobar(not red.set_state(&"xy", TrackSegment.State.OPEN) and red.is_cut(&"xy"), "Con un bloqueo no se lo puede abrir")
	red.add_blocker(&"xy", otro)
	_comprobar(red.remove_blocker(&"xy", uno) and red.is_cut(&"xy"), "Sacar uno de dos lo deja cortado")
	_comprobar(red.remove_blocker(&"xy", otro) and red.get_state(&"xy") == TrackSegment.State.OPEN, "Sin bloqueos vuelve a abierto")
	_comprobar(not red.remove_blocker(&"xy", otro), "Un bloqueo que no estaba no se saca")
	red.set_state(&"xy", TrackSegment.State.IMPROVED)
	red.add_blocker(&"xy", uno)
	red.remove_blocker(&"xy", uno)
	_comprobar(red.get_state(&"xy") == TrackSegment.State.IMPROVED, "Si estaba mejorado, vuelve a mejorado")
	red.set_state(&"xy", TrackSegment.State.CUT)
	red.add_blocker(&"xy", uno)
	red.remove_blocker(&"xy", uno)
	_comprobar(red.get_state(&"xy") == TrackSegment.State.OPEN, "Si ya estaba cortado, al despejarlo se abre")
	red.add_blocker(&"xy", uno)
	red.clear()
	red.add_track(via)
	_comprobar(red.is_cut(&"xy"), "Los bloqueos siguen al rearmar la red")
	red.remove_blocker(&"xy", uno)

	red.free()
	curva.free()


func _probar_escena() -> void:
	var llaves: KeyItems = _player.get_key_items()
	var usuario: ToolUser = _player.get_node("ToolUser")
	var grabber: Grabber = _player.get_node("Grabber")
	var clearable: Clearable = _arbol_caido.get_clearable()
	var cosecha: Harvestable = _arbol.get_node("Harvestable")

	_comprobar(llaves != null and llaves.get_count() == 0, "El jugador tiene KeyItems y arranca sin herramientas")
	_comprobar(_arbol_caido.segment_id == &"b_c" and _arbol_caido.is_blocking(), "El árbol caído encontró solo su tramo (b_c)")
	_comprobar(_network.get_blockers(&"b_c").size() == 2 and _network.is_cut(&"b_c"), "b_c arranca cortado por dos obstáculos")
	_comprobar(not _network.is_cut(&"a_b"), "a_b está abierto")

	# El tren no pasa del pueblo mientras b_c esté cortado.
	_loco.set_physics_process(false)
	_flatcar.set_physics_process(false)
	_poner_tren(130.0, 8.0)
	_simular(20.0)
	_comprobar(_loco.get_parent() == _ida and is_equal_approx(_loco.progress, _ida.curve.get_baked_length() - 5.0), "Con b_c cortado el tren frena en el pueblo")

	# Sin herramientas no se puede.
	_ir_a(_arbol_caido.global_position + Vector3(-2.0, 0.0, 0.0))
	var fallos: Array = []
	usuario.use_failed.connect(func(reason: StringName, tool_name: String) -> void: fallos.append([reason, tool_name]))
	_comprobar(not usuario.try_use() and fallos.back() == [&"missing_tool", "hacha"], "Sin el hacha avisa que hace falta")
	_ir_a(Vector3(30.0, 0.0, -100.0))
	_comprobar(not usuario.try_use() and fallos.back() == [&"nothing_near", ""], "Lejos de todo: nada cerca")

	# El hacha del piso pasa a las herramientas, no a la mano ni a la mochila.
	var obtenidas: Array = []
	EventBus.key_item_obtained.connect(func(id: StringName) -> void: obtenidas.append(id))
	_ir_a(_hacha.global_position + Vector3(0.8, 0.0, 0.0))
	_comprobar(grabber.try_grab() and llaves.has(&"axe"), "E recoge el hacha como herramienta clave")
	_comprobar(_player.get_hands().is_empty() and _player.get_backpack().count_of(&"axe") == 0 and obtenidas == [&"axe"], "No ocupa la mano ni la mochila, y se avisa por EventBus")
	await get_tree().process_frame
	_comprobar(not is_instance_valid(_hacha), "El hacha del piso desapareció")

	# Talar un árbol: tres golpes, tres troncos, y el árbol se esconde hasta volver a crecer.
	var troncos_antes: int = _contar_troncos()
	_ir_a(_arbol.global_position + Vector3(1.5, 0.0, 0.0))
	_comprobar(usuario.find_target() == cosecha, "Cerca del árbol, apunta al árbol")
	usuario.try_use()
	usuario.try_use()
	_comprobar(cosecha.hits_done == 2 and _arbol.visible, "Dos golpes: sigue en pie")
	usuario.try_use()
	_comprobar(cosecha.is_depleted() and not _arbol.visible and _arbol.collision_layer == 0, "Al tercero cae: se esconde y deja de chocar")
	_comprobar(_contar_troncos() == troncos_antes + 3, "Dejó tres troncos (%d)" % (_contar_troncos() - troncos_antes))
	_comprobar(usuario.find_target() == null, "Talado no se puede volver a golpear")
	GameState.clock.advance(10.0)
	_comprobar(cosecha.is_depleted() and is_equal_approx(cosecha.get_hours_to_regrow(), 14.0), "A las 10 horas le faltan 14 para volver")
	GameState.clock.advance(14.0)
	_comprobar(not cosecha.is_depleted() and _arbol.visible and _arbol.collision_layer == 1, "A las 24 horas volvió a crecer")

	# El árbol caído: cuatro golpes con el hacha; deja dos troncos y b_c sigue cortado por la piedra.
	_ir_a(_arbol_caido.global_position + Vector3(-2.0, 0.0, 1.0))
	troncos_antes = _contar_troncos()
	var despejados: Array = []
	EventBus.obstacle_cleared.connect(func(id: StringName) -> void: despejados.append(id))
	for _i: int in 3:
		usuario.try_use()
	_comprobar(clearable.hits_done == 3 and _network.is_cut(&"b_c"), "Tres golpes: el árbol sigue ahí")
	usuario.try_use()
	_comprobar(despejados == [&"b_c"] and _contar_troncos() == troncos_antes + 2, "Al cuarto se despeja y deja dos troncos")
	_comprobar(_network.is_cut(&"b_c") and _network.get_blockers(&"b_c").size() == 1, "b_c sigue cortado: falta la piedra")
	await get_tree().process_frame
	_comprobar(not is_instance_valid(_arbol_caido), "El árbol caído se borró")

	# La piedra pide la barreta.
	_ir_a(_piedra.global_position + Vector3(-2.0, 0.0, 0.0))
	_comprobar(not usuario.try_use() and fallos.back() == [&"missing_tool", "barreta"], "La piedra pide la barreta")
	llaves.add(_barreta.stack.item as KeyItemData)
	_avisos.clear()
	for _i: int in 5:
		usuario.try_use()
	_comprobar(not _network.is_cut(&"b_c") and _avisos == [[&"b_c", TrackSegment.State.OPEN]], "Con la piedra despejada, b_c se abre (y se avisa una vez)")

	# Ahora el tren sigue hasta la maderera.
	_poner_tren(_loco.progress, 8.0)
	_simular(30.0)
	_comprobar(_loco.get_parent() == _ramal, "Con b_c abierto el tren pasa a b_c")
	_loco.set_physics_process(true)
	_flatcar.set_physics_process(true)

	# Un obstáculo nuevo sobre un tramo abierto lo corta en cuanto entra a la escena.
	var piedra_nueva: Obstacle = (load("res://scenes/obstacles/rock.tscn") as PackedScene).instantiate()
	add_child(piedra_nueva)
	piedra_nueva.global_position = Vector3(0.0, 0.0, -100.0)
	await get_tree().process_frame
	_comprobar(piedra_nueva.segment_id == &"a_b" and _network.is_cut(&"a_b"), "Una piedra nueva sobre a_b lo corta")
	piedra_nueva.clear()
	_comprobar(not _network.is_cut(&"a_b"), "Y despejarla por código lo vuelve a abrir")


func _conectar_mensajes() -> void:
	var usuario: ToolUser = _player.get_node("ToolUser")
	usuario.used.connect(_on_tool_used)
	usuario.use_failed.connect(func(reason: StringName, tool_name: String) -> void: _mensaje = ToolUser.failure_text(reason, tool_name))
	var grabber: Grabber = _player.get_node("Grabber")
	grabber.grab_failed.connect(func(reason: StringName) -> void: _mensaje = InventoryUI.failure_text(reason))
	_player.get_key_items().item_added.connect(func(item: KeyItemData) -> void: _mensaje = "Conseguiste: %s. %s" % [item.display_name, item.action_text])
	EventBus.obstacle_cleared.connect(_on_obstacle_cleared)


func _on_tool_used(target: ToolTarget, done: bool) -> void:
	if done:
		_mensaje = "Listo: %s." % ("despejado" if target is Clearable else "talado")
	else:
		_mensaje = "%s: %d/%d" % [target.get_action_name().capitalize(), target.hits_done, target.hits_required]


func _on_obstacle_cleared(segment_id: StringName) -> void:
	if not _network.is_cut(segment_id):
		_mensaje = "¡El tramo %s quedó libre!" % segment_id


func _on_segment_state_changed(segment_id: StringName, state: int) -> void:
	_avisos.append([segment_id, state])


func _contar_troncos() -> int:
	var total: int = 0
	for node: Node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var item := node as WorldItem
		if item != null and not item.is_queued_for_deletion() and item.stack != null and item.stack.item.id == &"log":
			total += 1
	return total


func _ir_a(punto: Vector3) -> void:
	_player.global_position = punto
	_player.velocity = Vector3.ZERO


func _poner_tren(avance: float, velocidad: float) -> void:
	_loco.progress = avance
	_loco.speed = velocidad
	_loco.throttle = 1.0
	_loco.place_rear_vehicles()


func _simular(segundos: float) -> void:
	for _i: int in roundi(segundos / PASO_S):
		_loco.simulate(PASO_S)


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
