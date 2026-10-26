extends Node3D
## Prueba de la tarea 58: misiones (MissionData, Mission, MissionBoard, StationBoard,
## MissionGiver, D80).
## Primero la lógica pura con tableros propios; después la escena: ciudad --(c_p)-- pueblo
## --(p_m, con un árbol caído)-- maderera --(m_a, cortado)-- aserradero viejo, el tren con la
## plataforma cargada, dos pobladores y escombros detrás del pueblo. Al terminar vuelve a cargar
## la escena limpia para jugar (ver CONTROLES).

const CONTROLES: String = "WASD: caminar · E: agarrar (hacha y barreta en el andén) · clic: golpear · F: cabina, tablero o hablar\nT: pasa un día · R: llena la plataforma de troncos (provisorio, hasta el mercado) · M: abre o corta la vía al aserradero viejo (m_a)\nTroncos sin tren: talá los árboles detrás del pueblo (hacha), llevá un tronco en la mano y F en el tablero."
const LOG_PATH: String = "res://data/items/log.tres"
const MISSION_FILES: Array[String] = ["aserradero_viejo", "lena_escuela", "galpones_pueblo"]
## Troncos con que arranca la plataforma (llena).
const START_LOGS: int = 20

## Ya se corrieron las comprobaciones: al recargar la escena queda solo para jugar.
static var _probado: bool = false

@onready var _ida: Path3D = $Ida
@onready var _loco: Vehicle = $Ida/Locomotive
@onready var _flatcar: Wagon = $Ida/Flatcar
@onready var _red: RailNetwork = $RailNetwork
@onready var _pueblo: Station = $Pueblo
@onready var _maestra: MissionGiver = $Maestra
@onready var _hachero: MissionGiver = $Hachero
@onready var _player: Player = $Player
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0
var _entregas: Array = []
var _cumplidas: Array[StringName] = []


func _ready() -> void:
	EventBus.contribution_delivered.connect(func(station_id: StringName, item_id: StringName, amount: int) -> void: _entregas.append([station_id, item_id, amount]))
	EventBus.mission_completed.connect(func(mission_id: StringName) -> void: _cumplidas.append(mission_id))
	_cargar_plataforma.call_deferred()
	if _probado:
		return
	_probado = true
	_probar_principales()
	_probar_produccion_insuficiente()
	_probar_conexion()
	_probar_secundarias()
	_probar_quitar_principal()
	_probar_guardado()
	_probar_archivos()
	await _esperar_fisica(4)
	await _probar_escena()

	if _fallos == 0:
		print("Misiones: todas las comprobaciones pasaron.")
	else:
		push_error("Misiones: fallaron %d comprobaciones." % _fallos)
	# Partida limpia para jugar.
	GameState.money = 0
	GameState.reset_production()
	get_tree().reload_current_scene.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	var tecla := event as InputEventKey
	if tecla == null or not tecla.pressed or tecla.echo:
		return
	match tecla.physical_keycode:
		KEY_T:
			GameState.clock.advance(GameClock.HOURS_PER_DAY)
		KEY_R:
			_cargar_plataforma()
		KEY_M:
			_red.set_state(&"m_a", TrackSegment.State.OPEN if _red.is_cut(&"m_a") else TrackSegment.State.CUT)


func _process(_delta: float) -> void:
	var modelo: ProductionModel = GameState.production
	var lineas: PackedStringArray = [CONTROLES, "Día %d · $%d · plataforma: %d troncos · mochila: %d troncos" % [
		GameState.clock.current_day, GameState.money, _flatcar.get_cargo().get_total() if _flatcar.get_cargo() != null else 0,
		_player.get_backpack().count_of(&"log") if _player.get_backpack() != null else 0]]
	for flujo: ProductionFlow in modelo.get_flows():
		lineas.append("Flujo: %s · entregó %d" % [flujo.describe(), flujo.last_delivered])
	var cerca: Interactable = Interactable.find_nearest(get_tree(), _player.global_position, _player)
	if cerca != null:
		lineas.append("F: " + cerca.get_prompt())
	_hud.text = "\n".join(lineas)


# --- Lógica pura ---


func _probar_principales() -> void:
	var tablero: MissionBoard = _tablero_hito()
	var principales: Array[Mission] = tablero.get_main_missions(&"pueblo")
	_comprobar(principales.size() == 1, "Nace sola una principal en el pueblo")
	var mision: Mission = principales[0] if not principales.is_empty() else Mission.new()
	_comprobar(mision.id == &"main:pueblo:log:1" and mision.flow_amount == 10 and mision.required == _dic({&"log": 20}), "Abastecer con 10 troncos por día: pide una primera carga de 20 (%s)" % mision.id)
	_comprobar(tablero.get_title(mision) == "Abastecer con 10 tronco por día", "Título con el nombre del objeto: %s" % tablero.get_title(mision))
	_comprobar(tablero.get_main_missions(&"maderera").is_empty(), "La maderera no consume: sin principales")
	_comprobar(tablero.find_source(mision) == &"maderera", "El productor es la maderera")
	_comprobar(tablero.get_pending_steps(mision) == PackedStringArray(["Entregar 20 tronco"]), "Paso pendiente: %s" % [tablero.get_pending_steps(mision)])

	_comprobar(tablero.plan_delivery(&"pueblo", _dic({&"log": 30, &"rail": 4})) == _dic({&"log": 20}), "De 30 troncos y 4 rieles, el pueblo acepta 20 troncos")
	_comprobar(tablero.plan_delivery(&"maderera", _dic({&"log": 30})).is_empty(), "La maderera no acepta nada")
	_comprobar(tablero.deliver(&"pueblo", &"log", 12) == 12 and mision.delivered == _dic({&"log": 12}) and mision.is_active(), "Se entregan 12: sigue en curso con 12/20")
	_comprobar(tablero.deliver(&"pueblo", &"log", 15) == 8, "De otros 15 acepta solo los 8 que faltan")
	_comprobar(mision.is_completed() and mision.flow != null and mision.flow.describe() == "10 log de maderera a pueblo", "Cumplida: nace el flujo de 10 troncos de la maderera")
	_comprobar(tablero.get_main_missions(&"pueblo").is_empty() and tablero.production.get_uncommitted_needs(&"pueblo").is_empty(), "El pueblo ya no tiene principales: su consumo está comprometido")

	tablero.production.advance_days(3)
	var segunda: Array[Mission] = tablero.get_main_missions(&"pueblo")
	_comprobar(tablero.production.get_level(&"pueblo") == 2 and segunda.size() == 1 and segunda[0].flow_amount == 15 and segunda[0].id == &"main:pueblo:log:2", "Al crecer pide 15 más: nace la segunda principal")


func _probar_produccion_insuficiente() -> void:
	var tablero: MissionBoard = _tablero_hito()
	var ciudad: Mission = tablero.get_main_missions(&"ciudad")[0]
	_comprobar(ciudad.flow_amount == 20 and tablero.find_source(ciudad) == &"", "La ciudad pide 20 y la maderera solo da 15: no hay productor")
	_comprobar(tablero.get_pending_steps(ciudad)[0] == "Producción insuficiente: nadie tiene 20 tronco por día libres", "El tablero dice que falta producción")
	tablero.deliver(&"ciudad", &"log", 40)
	_comprobar(ciudad.is_delivery_done() and ciudad.is_active(), "Con la carga entregada sigue esperando un productor")
	tablero.production.add_production_bonus(&"maderera", &"log", 5)
	tablero.refresh()
	_comprobar(tablero.production.get_production(&"maderera") == _dic({&"log": 20}), "Con 5 de producción extra la maderera da 20")
	_comprobar(ciudad.is_completed() and tablero.production.get_flows_to(&"ciudad").size() == 1, "Ahora alcanza: se cumple y nace el flujo a la ciudad")
	_comprobar(tablero.get_main_missions(&"pueblo")[0].get_remaining() == _dic({&"log": 20}) and tablero.find_source(tablero.get_main_missions(&"pueblo")[0]) == &"", "El pueblo queda sin productor (la ciudad se llevó todo)")


func _probar_conexion() -> void:
	var tablero: MissionBoard = _tablero_hito()
	var abierto: Array[bool] = [false]
	tablero.production.connection_check = func(_desde: StringName, _hasta: StringName) -> bool: return abierto[0]
	tablero.route_finder = func(desde: StringName, hasta: StringName) -> Variant:
		if desde == &"maderera" and hasta == &"pueblo":
			return [&"m_p"] as Array[StringName]
		if desde == &"maderera" and hasta == &"ciudad":
			return [&"m_p", &"p_c"] as Array[StringName]
		return null
	tablero.segment_check = func(tramo: StringName) -> bool: return abierto[0] or tramo != &"m_p"
	var mision: Mission = tablero.get_main_missions(&"pueblo")[0]
	_comprobar(tablero.get_cut_segments(mision) == ([&"m_p"] as Array[StringName]), "El camino desde la maderera tiene cortado m_p")
	_comprobar(tablero.get_pending_steps(mision) == PackedStringArray(["Habilitar el tramo m_p (hacia Maderera)", "Entregar 20 tronco"]), "Pasos: habilitar el tramo y entregar (%s)" % [tablero.get_pending_steps(mision)])
	tablero.deliver(&"pueblo", &"log", 20)
	_comprobar(mision.is_active() and tablero.production.get_flows().is_empty(), "Entregado pero cortado: no se cumple todavía")
	abierto[0] = true
	tablero.refresh()
	_comprobar(mision.is_completed() and tablero.production.get_flows().size() == 1, "Al habilitar el tramo se cumple")


func _probar_secundarias() -> void:
	var tablero: MissionBoard = _tablero_hito()
	var abierto: Array[bool] = [false]
	var quedan: Array[int] = [2]
	tablero.segment_check = func(tramo: StringName) -> bool: return abierto[0] or tramo != &"m_a"
	tablero.zone_count = func(_grupo: StringName) -> int: return quedan[0]
	var avisos: Array[StringName] = []
	tablero.mission_available.connect(func(m: Mission) -> void: avisos.append(m.id))
	var aserradero: Mission = tablero.register_side(load("res://data/missions/aserradero_viejo.tres"))
	var lena: Mission = tablero.register_side(load("res://data/missions/lena_escuela.tres"))
	var galpones: Mission = tablero.register_side(load("res://data/missions/galpones_pueblo.tres"))
	_comprobar(aserradero.state == Mission.State.AVAILABLE and lena.state == Mission.State.AVAILABLE, "Aserradero y leña se pueden conseguir desde el nivel 1")
	_comprobar(galpones.state == Mission.State.LOCKED, "Los galpones esperan el nivel 2 y la leña")
	_comprobar(avisos == ([&"aserradero_viejo", &"lena_escuela"] as Array[StringName]), "Se avisó cuáles aparecieron (%s)" % [avisos])
	_comprobar(tablero.register_side(load("res://data/missions/lena_escuela.tres")) == lena, "Registrarla de nuevo devuelve la misma")
	_comprobar(tablero.plan_delivery(&"pueblo", _dic({&"log": 50})) == _dic({&"log": 20}), "Sin tomarla, la leña no acepta entregas (solo la principal)")

	_comprobar(tablero.start(&"lena_escuela") and not tablero.start(&"lena_escuela") and lena.is_active(), "Se toma una sola vez")
	_comprobar(tablero.plan_delivery(&"pueblo", _dic({&"log": 50})) == _dic({&"log": 25}), "Tomada, el pueblo acepta 25 (20 de la principal y 5 de la leña)")
	_comprobar(tablero.deliver(&"pueblo", &"log", 22) == 22 and lena.delivered == _dic({&"log": 2}), "La principal cobra primero: la leña recibe 2 de 22")
	tablero.deliver(&"pueblo", &"log", 3)
	_comprobar(lena.is_completed(), "Con 5 troncos la leña se cumple")

	tablero.production.set_level(&"pueblo", 2)
	_comprobar(galpones.state == Mission.State.AVAILABLE, "En el nivel 2 y con la leña cumplida aparecen los galpones")
	tablero.start(&"galpones_pueblo")
	_comprobar(galpones.is_active() and tablero.get_pending_steps(galpones) == PackedStringArray(["Despejar la zona (quedan 2)"]), "Falta despejar la zona: %s" % [tablero.get_pending_steps(galpones)])
	quedan[0] = 0
	tablero.refresh()
	_comprobar(galpones.is_completed(), "Despejada la zona, se cumple")

	tablero.start(&"aserradero_viejo")
	_comprobar(aserradero.is_active() and tablero.get_pending_steps(aserradero) == PackedStringArray(["Habilitar el tramo m_a"]), "Falta habilitar m_a")
	abierto[0] = true
	tablero.refresh()
	_comprobar(aserradero.is_completed() and tablero.production.get_production(&"maderera") == _dic({&"log": 30}), "Reabierto el aserradero, la maderera produce 15 más para siempre")
	_comprobar(tablero.get_side_missions(&"pueblo").size() == 2 and tablero.get_side_missions(&"maderera").size() == 1, "Secundarias por estación")


func _probar_quitar_principal() -> void:
	var tablero: MissionBoard = _tablero_hito()
	var quitadas: Array[StringName] = []
	tablero.mission_removed.connect(func(m: Mission) -> void: quitadas.append(m.id))
	tablero.deliver(&"pueblo", &"log", 6)
	tablero.production.add_flow(&"maderera", &"pueblo", &"log", 4)
	var mision: Mission = tablero.get_main_missions(&"pueblo")[0]
	_comprobar(mision.flow_amount == 6 and mision.required == _dic({&"log": 12}) and mision.delivered == _dic({&"log": 6}), "Un flujo de 4 a mano baja la principal a 6 por día (12 de carga) y conserva lo entregado")
	tablero.production.add_flow(&"maderera", &"pueblo", &"log", 6)
	_comprobar(tablero.get_main_missions(&"pueblo").is_empty() and quitadas == ([&"main:pueblo:log:1"] as Array[StringName]), "Cubierto por otros flujos, la principal se quita")


func _probar_guardado() -> void:
	var tablero: MissionBoard = _tablero_hito()
	tablero.register_side(load("res://data/missions/lena_escuela.tres"))
	tablero.start(&"lena_escuela")
	tablero.deliver(&"pueblo", &"log", 15)
	tablero.get_mission(&"lena_escuela").outro_told = true
	var guardado: Dictionary = JSON.parse_string(JSON.stringify({"production": tablero.production.to_dict(), "missions": tablero.to_dict()}))

	var modelo := ProductionModel.new()
	modelo.load_dict(guardado["production"])
	var copia := MissionBoard.new(modelo)
	copia.load_dict(guardado["missions"])
	for archivo: String in ["maderera", "pueblo", "ciudad"]:
		modelo.add_station(load("res://data/stations/%s.tres" % archivo))
	copia.refresh()
	var principal: Mission = copia.get_mission(&"main:pueblo:log:1")
	_comprobar(principal != null and principal.is_active() and principal.delivered == _dic({&"log": 15}), "La principal vuelve con lo entregado")
	var lena: Mission = copia.register_side(load("res://data/missions/lena_escuela.tres"))
	_comprobar(lena.is_active() and lena.delivered.is_empty() and lena.outro_told, "La secundaria se une a sus datos al registrarse, con su estado")
	_comprobar(copia.get_main_missions(&"ciudad").size() == 1 and copia.get_main_missions(&"ciudad")[0].id == &"main:ciudad:log:1", "No se duplican principales al cargar")
	var segundo := MissionBoard.new(ProductionModel.new())
	segundo.load_dict(copia.to_dict())
	_comprobar(segundo.to_dict()["missions"].size() == copia.to_dict()["missions"].size(), "Lo no registrado se conserva al volver a guardar")


func _probar_archivos() -> void:
	for archivo: String in MISSION_FILES:
		var datos: MissionData = load("res://data/missions/%s.tres" % archivo)
		_comprobar(datos != null and datos.validate().is_empty(), "data/missions/%s.tres sin problemas %s" % [archivo, datos.validate() if datos != null else PackedStringArray()])
	var mala := MissionData.new()
	mala.kind = MissionData.Kind.OPEN_SEGMENT
	_comprobar(mala.validate().size() == 4, "Una misión vacía avisa id, título, estación y tramo (%s)" % [mala.validate()])


# --- Escena ---


func _probar_escena() -> void:
	var tablero: MissionBoard = GameState.missions
	var pizarra: StationBoard = _pueblo.get_node("Tablero")
	_comprobar(($Hacha as WorldItem).stack != null and ($Barreta as WorldItem).stack != null, "El hacha y la barreta del andén se pueden agarrar")
	var principal: Mission = tablero.get_main_missions(&"pueblo")[0] if not tablero.get_main_missions(&"pueblo").is_empty() else null
	_comprobar(principal != null and tablero.get_pending_steps(principal) == PackedStringArray(["Habilitar el tramo p_m (hacia Maderera)", "Entregar 20 tronco"]), "Pueblo: habilitar p_m (el árbol caído) y entregar 20 troncos")
	_comprobar(pizarra.build_text().contains("Abastecer con 10 tronco por día"), "El tablero del pueblo muestra la principal:\n%s" % pizarra.build_text())

	# El tren llega al pueblo: nada se descarga solo.
	_loco.place_on(_ida, 140.0)
	await _esperar_fisica(6)
	_comprobar(_pueblo.get_stopped_trains() == ([_loco] as Array[Vehicle]), "El tren está detenido en el pueblo")
	_comprobar(_flatcar.get_cargo().get_total() == START_LOGS and principal.delivered.is_empty(), "Al llegar no se descargó nada")
	_comprobar(pizarra.get_delivery_plan() == _dic({&"log": 20}) and pizarra.get_prompt() == "Entregar 20 tronco", "El tablero ofrece entregar 20 troncos")

	# F en el tablero aprueba la entrega.
	_player.global_position = pizarra.global_position + Vector3(1.5, 0.2, 0)
	await _esperar_fisica(2)
	_comprobar(Interactable.find_nearest(get_tree(), _player.global_position, _player) == pizarra, "Lo más cercano para la F es el tablero")
	_comprobar(_player.try_interact() and _flatcar.get_cargo().get_total() == 0, "F: se descargan los 20 troncos de la plataforma")
	_comprobar(_entregas == [[&"pueblo", &"log", 20]] and principal.is_delivery_done() and principal.is_active(), "Se avisó la entrega; falta habilitar el tramo")

	# Despejar el árbol caído abre p_m: se cumple y nace el flujo.
	($ArbolCaido as Obstacle).clear()
	await _esperar_fisica(3)
	_comprobar(principal.is_completed() and GameState.production.get_flows().size() == 1, "Despejado el árbol, la principal se cumple y nace el flujo")
	_comprobar(_cumplidas.has(principal.id), "Se avisó por EventBus.mission_completed")

	# La maestra da la leña; se entrega con el tablero.
	_player.global_position = _maestra.global_position + Vector3(1.2, 0.2, 0)
	await _esperar_fisica(2)
	_comprobar(_maestra.has_news() and _maestra.get_prompt() == "Hablar con Doña Elena, la maestra", "La maestra tiene algo para contar")
	_player.try_interact()
	var lena: Mission = tablero.get_mission(&"lena_escuela")
	_comprobar(lena.is_active() and (_maestra.get_node("Globo") as Label3D).text.contains("estufa"), "Hablando, la leña queda en curso y cuenta su historia")
	_cargar_plataforma()
	_comprobar(pizarra.deliver() == _dic({&"log": 5}) and _flatcar.get_cargo().get_total() == 15, "Con la plataforma otra vez llena, el tablero entrega solo los 5 de la leña")
	_comprobar(lena.is_completed() and GameState.money == 150, "Leña entregada: se cobran $150")
	_comprobar(_maestra.has_news() and _maestra.talk().contains("calorcito") and lena.outro_told and not _maestra.has_news(), "Al volver a hablarle cuenta el cierre una vez")

	# Al crecer aparecen los galpones; se despejan los escombros.
	_pueblo.set_level(2)
	var galpones: Mission = tablero.get_mission(&"galpones_pueblo")
	_comprobar(galpones.state == Mission.State.AVAILABLE and _maestra.has_news(), "Nivel 2: la maestra ofrece los galpones")
	_maestra.talk()
	for nombre: String in ["EscombrosA", "EscombrosB", "EscombrosC"]:
		get_node(nombre).queue_free()
	EventBus.tool_used.emit(&"crowbar")
	await _esperar_fisica(2)
	_comprobar(galpones.is_completed() and GameState.money == 550, "Sin escombros, los galpones se cumplen ($550)")

	# Mochila: la segunda principal del pueblo (15 por día) espera producción.
	var segunda: Mission = tablero.get_main_missions(&"pueblo")[0]
	_comprobar(segunda.flow_amount == 15 and tablero.find_source(segunda) == &"", "Segunda principal: 15 troncos, y la maderera no tiene libres")
	_comprobar(pizarra.deliver() == _dic({&"log": 15}) and segunda.delivered == _dic({&"log": 15}), "La segunda principal recibe los 15 troncos que quedaban")

	# Mano: un tronco talado a mano se entrega desde la mano.
	var tronco: WorldItem = WorldItem.create(ItemStack.new(load(LOG_PATH), 1))
	add_child(tronco)
	tronco.global_position = _player.global_position + Vector3(0, 0.5, -1)
	await _esperar_fisica(3)
	var grabber: Grabber = _player.get_node("Grabber")
	_comprobar(grabber.try_grab() and pizarra.get_delivery_plan(_player) == _dic({&"log": 1}), "Con un tronco en la mano, el tablero ofrece entregarlo")
	_comprobar(pizarra.deliver(_player) == _dic({&"log": 1}) and grabber.get_held_item() == null and _player.get_hands().is_empty() and segunda.delivered == _dic({&"log": 16}), "F entrega el tronco de la mano")

	# Mochila: una secundaria de pieles (objeto chico) se entrega desde la mochila.
	var piel := ItemData.new()
	piel.id = &"fur"
	piel.display_name = "piel"
	var pieles := MissionData.new()
	pieles.id = &"pieles_prueba"
	pieles.title = "Pieles para el curtidor"
	pieles.station_id = &"pueblo"
	pieles.delivery = [_cantidad(piel, 3)] as Array[ItemAmount]
	tablero.register_side(pieles)
	tablero.start(&"pieles_prueba")
	var mochila: Inventory = _player.get_backpack()
	mochila.try_store(ItemStack.new(piel, 4))
	_comprobar(pizarra.get_delivery_plan(_player) == _dic({&"fur": 3}), "El tablero ofrece 3 de las 4 pieles de la mochila")
	_comprobar(pizarra.deliver(_player) == _dic({&"fur": 3}) and mochila.count_of(&"fur") == 1 and tablero.is_completed(&"pieles_prueba"), "Se entregan 3 pieles y queda 1 en la mochila")

	# El hachero: reabrir la vía al aserradero sube la producción y alcanza para el pueblo.
	_hachero.talk()
	var aserradero: Mission = tablero.get_mission(&"aserradero_viejo")
	_comprobar(aserradero.is_active(), "El hachero da la vía al aserradero")
	_red.set_state(&"m_a", TrackSegment.State.OPEN)
	await _esperar_fisica(2)
	_comprobar(aserradero.is_completed() and GameState.production.get_production(&"maderera") == _dic({&"log": 30}) and GameState.money == 850, "Reabierta la vía: la maderera produce 30 y se cobran $300")
	_comprobar(tablero.find_source(segunda) == &"maderera", "Ahora la maderera tiene libres los 15 del pueblo")
	_comprobar(pizarra.build_text().contains("Entregar 14 tronco"), "Al pueblo le faltan 14 troncos de carga")


# --- Ayudas ---


func _cargar_plataforma() -> void:
	if _flatcar.get_cargo() != null:
		_flatcar.get_cargo().try_store(ItemStack.new(load(LOG_PATH), START_LOGS))


func _cantidad(item: ItemData, cantidad: int) -> ItemAmount:
	var resultado := ItemAmount.new()
	resultado.item = item
	resultado.amount = cantidad
	return resultado


func _tablero_hito() -> MissionBoard:
	var modelo := ProductionModel.new()
	for archivo: String in ["maderera", "pueblo", "ciudad"]:
		modelo.add_station(load("res://data/stations/%s.tres" % archivo))
	var tablero := MissionBoard.new(modelo)
	tablero.refresh()
	return tablero


func _dic(valores: Dictionary) -> Dictionary[StringName, int]:
	var resultado: Dictionary[StringName, int] = {}
	for clave: StringName in valores:
		resultado[clave] = valores[clave]
	return resultado


func _esperar_fisica(pasos: int) -> void:
	for i: int in pasos:
		await get_tree().physics_frame


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
