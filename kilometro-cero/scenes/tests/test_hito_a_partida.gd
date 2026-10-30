extends Node
## Tarea 62b.7: la partida de cierre del Hito A jugada sola, sobre el mapa de verdad (hito_a.tscn
## con GameState), para no tener que jugarla entera (unas 2 horas). Hace lo que haría el jugador
## con los pobladores, los tableros, los obstáculos, la obra, el coche y el tren prestado, y pasa
## los días como la T. Lo único que no hace es manejar: los trenes se ponen en la estación de
## llegada como los pone BorrowedTrains (place_on), y los viajes en el coche propio se hacen con el
## intercambio de pasajeros (PassengerTraffic), sin coche en la vía.
## Orden: la vía tapada (hacha) -> colonos para Azul en el tren prestado -> troncos para Sierras
## Bayas (nadie toma el prestado: lo trae el Ferrocarril) -> piedra para Olavarría (sin viaje
## inaugural) -> cemento para Azul, las primeras casas, los Etchegaray, la maestra, Doña Rosa y los
## cueros, la miel -> la cantera vieja y los troncos que piden sus canteros -> piedra para Azul y
## Olavarría -> los dos en el nivel 3.
## Al final imprime un resumen de la partida (días, plata, niveles, familias, parcelas y flujos) y
## lo que haya quedado colgado, y deja el mapa abierto para mirar.

const HITO_A: String = "res://scenes/hito_a/hito_a.tscn"
const STATIONS: Array[StringName] = [&"olavarria", &"azul", &"sierras_bayas"]
## Cuántos días más se esperan, como mucho, para que Azul y Olavarría lleguen al nivel 3.
const MAX_DAYS_TO_LEVEL_3: int = 6
## Los de hito_a.gd (no tiene class_name): plata al empezar y la hora a la que lleva la T.
const START_MONEY: int = 150
const SKIP_MORNING_HOUR: float = 7.0

var _fallos: int = 0
var _mapa: Node3D
var _jugador: Player
var _red: RailNetwork
var _prestados: BorrowedTrains
var _lotes: TrackLots
var _tablero: MissionBoard
var _modelo: ProductionModel
var _dias_al_empezar: int = 0


func _ready() -> void:
	GameState.reset_production()
	GameState.money = 0
	_mapa = (load(HITO_A) as PackedScene).instantiate() as Node3D
	add_child(_mapa)
	await _cuadros(12)
	_jugador = _mapa.get_node_or_null(^"Player") as Player
	_red = RailNetwork.find_in(get_tree())
	_prestados = BorrowedTrains.find_in(get_tree())
	_lotes = TrackLots.find_in(get_tree())
	_tablero = GameState.missions
	_modelo = GameState.production
	_dias_al_empezar = GameState.clock.current_day
	_comprobar(_jugador != null and _red != null and _prestados != null and _lotes != null, "El Hito A tiene jugador, red, trenes prestados y lotes")
	if _jugador == null or _red == null or _prestados == null or _lotes == null:
		push_error("Partida del Hito A: no se pudo armar el mapa.")
		return
	_probar_arranque()
	await _jugar_la_via_tapada()
	await _jugar_colonos()
	await _jugar_troncos()
	await _jugar_piedra_olavarria()
	await _jugar_secundarias_de_azul()
	await _jugar_secundarias_de_olavarria()
	await _jugar_cantera_vieja()
	await _jugar_nivel_3()
	_probar_final()
	_imprimir_resumen()
	if _fallos == 0:
		print("Partida del Hito A: todas las comprobaciones pasaron.")
	else:
		push_error("Partida del Hito A: fallaron %d comprobaciones." % _fallos)


func _probar_arranque() -> void:
	_paso("Arranque")
	_comprobar(GameState.money == START_MONEY, "Se arranca con $%d (hay $%d)" % [START_MONEY, GameState.money])
	for station_id: StringName in STATIONS:
		_comprobar(_modelo.get_level(station_id) == 1, "%s en el nivel 1" % station_id)
	_comprobar(_red.is_cut(&"o_a") and _red.is_cut(&"o_s") and _red.is_cut(&"s_c"), "o_a, o_s y s_c arrancan cortados")
	var loco: Vehicle = _prestados.player_train
	var olavarria := Station.find(get_tree(), &"olavarria")
	_comprobar(loco != null and olavarria != null and loco.global_position.distance_to(olavarria.global_position) < 60.0, "El tren del jugador arranca en Olavarría")


# 1. Don Ernesto da la vía tapada y el hacha; con los dos árboles despejados se abren o_a y o_s.
func _jugar_la_via_tapada() -> void:
	_paso("La vía tapada")
	var jefe: MissionGiver = _poblador(^"JefeDeEstacion")
	_hablar(jefe)
	_comprobar(_tablero.get_mission(&"la_via_tapada").is_active(), "Don Ernesto da la vía tapada")
	_comprobar(_jugador.get_key_items().has(&"axe"), "Y el hacha")
	_despejar(_mapa.get_node(^"ArbolCaido"))
	_despejar(_mapa.get_node(^"ArbolCaidoSur"))
	await _cuadros(4)
	_comprobar(_tablero.is_completed(&"la_via_tapada"), "Despejados los dos árboles: la vía tapada se cumple")
	_comprobar(not _red.is_cut(&"o_a") and not _red.is_cut(&"o_s") and _red.was_opened(&"o_a") and _red.was_opened(&"o_s"), "o_a y o_s quedan abiertos por el jugador")
	_hablar(jefe)
	_hablar(jefe)
	_comprobar(_tablero.get_mission(&"miel_don_ernesto").is_active(), "Después Don Ernesto pide la miel")
	# El regalo se revisa cada medio segundo.
	var regalo: WagonGift = _regalo_de(&"o_a")
	for _i: int in 30:
		if regalo == null or regalo.get_wagon() != null:
			break
		await get_tree().create_timer(0.1).timeout
	_comprobar(regalo != null and regalo.get_wagon() != null, "Con o_a abierto aparece la plataforma de regalo de Azul")


# 2. Colonos para Azul: se le avisa a Doña Clara, se toma el tren prestado en Olavarría y se lleva.
func _jugar_colonos() -> void:
	_paso("Colonos para Azul (tren prestado)")
	var colonos: Mission = _principal(&"azul", &"settlers")
	_comprobar(colonos != null and _tablero.get_stage(colonos) == MissionBoard.Stage.REPORT, "Azul pide colonos y hay que avisarle a Doña Clara")
	if colonos == null:
		return
	_avisar(_poblador(^"DonaClara"), colonos)
	_comprobar(colonos.reported and colonos.offered and colonos.source_id == &"olavarria", "Avisada: o_a está sin estrenar, el tren prestado se ofrece en Olavarría")
	var tablero_olav := _mapa.get_node_or_null(^"Olavarria/Tablero") as StationBoard
	_comprobar(tablero_olav != null and tablero_olav.get_offer() == colonos and tablero_olav.take_offer(), "F en el tablero de Olavarría: se toma el tren prestado")
	var tren: Array[Vehicle] = await _esperar_tren(colonos.id)
	_comprobar(not tren.is_empty(), "El tren prestado aparece")
	if tren.is_empty():
		_entregar_en_coche(&"azul", {&"settlers": 10})
		return
	var olavarria := Station.find(get_tree(), &"olavarria")
	_comprobar(tren[0].global_position.distance_to(olavarria.global_position) < 80.0 and StationGoods.is_borrowed(tren[0]), "Está en Olavarría, marcado como prestado")
	var coche: PassengerCoach = _coche_de(tren)
	_comprobar(coche != null and coche.get_aboard().get(&"settlers", 0) == 10, "Lleva un coche con los 10 colonos")
	await _llevar(tren[0], &"azul", &"olavarria", tren)
	_comprobar(coche != null and coche.can_open_doors() and coche.set_doors(true), "Detenido en Azul: se abren las puertas")
	await _cuadros(3)
	if not colonos.is_completed():
		_entregar_en_coche(&"azul", {&"settlers": 10})
	_comprobar(colonos.is_completed() and colonos.flow != null and _tablero.is_christened(&"o_a"), "Bajan los colonos: principal cumplida, nace el flujo y o_a queda estrenado")
	for _i: int in 20:
		if not _prestados.has_train(colonos.id):
			break
		await get_tree().create_timer(0.1).timeout
	_comprobar(not _prestados.has_train(colonos.id), "El tren prestado se va con humo")
	var azul := Station.find(get_tree(), &"azul")
	var propio: Vehicle = _prestados.player_train.get_head()
	_comprobar(propio.global_position.distance_to(azul.global_position) < BorrowedTrains.ALREADY_THERE, "Y el tren propio aparece en Azul")
	await _pasar_dia()
	_comprobar(_modelo.get_level(&"azul") == 2, "Al otro día Azul sube al nivel 2")
	var familias: Array[StringName] = _modelo.get_families(&"azul")
	_comprobar(familias.has(&"hacheros") and familias.has(&"puesteros"), "Llegan hacheros y puesteros a Azul (%s)" % [familias])
	_comprobar(_ocupados(&"azul").size() == familias.size(), "Cada familia de Azul tiene su parcela (%d)" % _ocupados(&"azul").size())


# 3. Troncos para Sierras Bayas: avisado Ramírez, Azul ofrece el prestado y nadie lo toma.
func _jugar_troncos() -> void:
	_paso("Troncos para Sierras Bayas (lo trae el Ferrocarril)")
	var troncos: Mission = _principal(&"sierras_bayas", &"log")
	_comprobar(troncos != null and _tablero.can_report(troncos), "Sierras Bayas pide troncos de Azul y hay que avisarle a Ramírez")
	if troncos == null:
		return
	_avisar(_poblador(^"Ramirez"), troncos)
	_comprobar(troncos.offered and _tablero.get_offers_at(&"azul").has(troncos), "o_s sin estrenar: el tablero de Azul ofrece el tren prestado")
	await _pasar_dia()
	_comprobar(troncos.is_completed() and _tablero.is_christened(&"o_s") and not _prestados.has_train(troncos.id), "Nadie lo tomó: al terminar el día lo trajo el Ferrocarril y o_s queda estrenado")
	await _pasar_dia()
	_comprobar(_modelo.get_production(&"sierras_bayas").get(&"limestone", 0) == 20, "Con los troncos los canteros pican 20 piedras por día")
	_comprobar(_modelo.get_level(&"sierras_bayas") == 2, "Sierras Bayas sube al nivel 2")


# 4. Piedra para Olavarría: el camino ya está estrenado y el Ferrocarril la manda solo.
func _jugar_piedra_olavarria() -> void:
	_paso("Piedra para Olavarría (sin viaje inaugural)")
	var piedra: Mission = _principal(&"olavarria", &"limestone")
	_comprobar(piedra != null and _tablero.can_report(piedra), "Hay que avisarle a Don Ernesto de la piedra")
	if piedra == null:
		return
	_avisar(_poblador(^"JefeDeEstacion"), piedra)
	_comprobar(piedra.is_completed() and not piedra.offered and piedra.flow != null and piedra.flow.from_station == &"sierras_bayas", "Avisado: sin tren prestado, nace el flujo de piedra de Sierras Bayas")
	await _pasar_dia()
	_comprobar(_modelo.get_level(&"olavarria") == 2, "Olavarría sube al nivel 2")
	_comprobar(_modelo.count_families(&"olavarria", &"caleros") == 3, "Llega la tercera familia de caleros")
	var produce: Dictionary[StringName, int] = _modelo.get_production(&"olavarria")
	_comprobar(produce.get(&"cement", 0) == 10 and produce.get(&"teacher", 0) == 1, "Olavarría da 10 cemento y 1 maestra por día")


# 5. Azul: el cemento, la obra de las primeras casas, los Etchegaray y la maestra.
func _jugar_secundarias_de_azul() -> void:
	_paso("Azul: cemento, primeras casas, los Etchegaray y la maestra")
	var clara: MissionGiver = _poblador(^"DonaClara")
	var cemento: Mission = _principal(&"azul", &"cement")
	_comprobar(cemento != null and _tablero.can_report(cemento), "Azul pide cemento de Olavarría")
	if cemento != null:
		_avisar(clara, cemento)
		_comprobar(cemento.is_completed(), "Avisada Doña Clara, el Ferrocarril trae el cemento")
	# La obra: la da Doña Clara y se entrega en su cartel.
	_hablar(clara)
	var casas: Mission = _tablero.get_mission(&"primeras_casas")
	_comprobar(casas != null and casas.is_active(), "Doña Clara da la obra de las primeras casas")
	var obra := _mapa.get_node_or_null(^"Azul/ObraCasas") as ConstructionSite
	_comprobar(obra != null and obra.get_mission() == casas, "La obra está junto a la vía de Azul")
	_comprobar(_tablero.deliver_build(&"primeras_casas", &"log", 20) == 20 and casas.is_completed(), "Con 20 troncos se terminan las casas")
	if obra != null:
		obra.refresh(false)
		_comprobar(obra.is_finished() and obra.get_built_count() == obra.get_parts().size(), "La obra queda terminada, con todas sus partes")
	# Los Etchegaray: esperan en Olavarría y viajan en el coche a Azul.
	var etche: Mission = _tablero.get_mission(&"los_etchegaray")
	_comprobar(etche != null and etche.state == Mission.State.AVAILABLE, "Con las casas hechas, los Etchegaray piden venir")
	var etchegaray: MissionGiver = _poblador(^"Etchegaray")
	_hablar(etchegaray)
	_comprobar(etche != null and etche.is_active(), "Los Etchegaray aceptan la mudanza")
	var subieron: Dictionary = _viaje_en_coche(&"olavarria", &"azul")
	_comprobar(int((subieron["board_free"] as Dictionary).get(&"family", 0)) == 1, "En Olavarría la familia sube gratis al coche")
	_comprobar(etche != null and etche.is_completed(), "Bajan en Azul: mudanza cumplida")
	var vecinos: Array[Dictionary] = _modelo.get_player_family_list(&"azul")
	_comprobar(vecinos.size() == 1 and vecinos[0]["name"] == "los Etchegaray" and vecinos[0]["occupation"] == &"tamberos", "Los Etchegaray quedan como tamberos del jugador en Azul")
	await _cuadros(3)
	var llegada := _mapa.get_node(^"LlegadaEtchegaray") as Node3D
	_comprobar(etchegaray.has_moved() and etchegaray.global_position.distance_to(llegada.global_position) < 1.0, "Los Etchegaray se mudan con humo a Azul")
	_comprobar(_parcela_de(&"azul", &"tamberos") != null, "Brota el tambo en un lote de Azul")
	# La maestra: Doña Elvira la pide y viaja en el coche desde Olavarría.
	_hablar(_poblador(^"Vecina"))
	var maestra: Mission = _tablero.get_mission(&"maestra_azul")
	_comprobar(maestra != null and maestra.is_active(), "Doña Elvira pide la maestra")
	var con_maestra: Dictionary = _viaje_en_coche(&"olavarria", &"azul")
	_comprobar(int((con_maestra["board_free"] as Dictionary).get(&"teacher", 0)) == 1, "La maestra sube gratis en Olavarría")
	_comprobar(maestra != null and maestra.is_completed() and _tablero.has_delivered(&"azul", &"teacher"), "Llega la maestra: abre la escuela de Azul")


# 6. Olavarría: Doña Rosa y sus cueros (se queda como curtidora) y la miel de Don Ernesto.
func _jugar_secundarias_de_olavarria() -> void:
	_paso("Olavarría: Doña Rosa y la miel")
	_hablar(_poblador(^"DonaRosa"))
	var cueros: Mission = _tablero.get_mission(&"cueros_dona_rosa")
	_comprobar(cueros != null and cueros.is_active(), "Doña Rosa pide 6 cueros")
	var plata: int = GameState.money
	_tablero.deliver(&"olavarria", &"hides", 6)
	_comprobar(cueros != null and cueros.is_completed() and GameState.money - plata == cueros.paid and cueros.paid >= 300, "Con los cueros se cumple y paga $%d" % (cueros.paid if cueros != null else 0))
	var rosa: Array[Dictionary] = _modelo.get_player_family_list(&"olavarria")
	_comprobar(rosa.size() == 1 and rosa[0]["name"] == "Doña Rosa" and rosa[0]["occupation"] == &"curtidores", "Doña Rosa se queda como curtidora del jugador")
	await _cuadros(3)
	var piletones: TrackLot = _parcela_de(&"olavarria", &"curtidores")
	_comprobar(piletones != null and piletones.ring == TrackLot.Ring.INDUSTRY, "Los piletones brotan en la zona industrial de Olavarría")
	var de_cueros: Mission = _principal(&"olavarria", &"hides")
	_comprobar(de_cueros != null and _tablero.find_source(de_cueros) == &"azul", "La curtidora pide cueros de los puesteros de Azul")
	if de_cueros != null:
		_avisar(_poblador(^"JefeDeEstacion"), de_cueros)
		_comprobar(de_cueros.is_completed(), "Avisado Don Ernesto, nace el flujo de cueros")
	# La miel: tres panales del monte de Azul, con las manos.
	var antes: int = _contar_objetos()
	for numero: int in range(1, 4):
		var panal := _mapa.get_node_or_null("Bosquecito/Panal%d/Miel/Harvestable" % numero) as Harvestable
		_comprobar(panal != null and panal.get_required_tool_id() == &"", "El panal %d se junta con las manos" % numero)
		if panal != null:
			for _i: int in 10:
				if panal.hit():
					break
	_comprobar(_contar_objetos() - antes == 3, "Caen 3 frascos de miel (%d)" % (_contar_objetos() - antes))
	var miel: Mission = _tablero.get_mission(&"miel_don_ernesto")
	plata = GameState.money
	_tablero.deliver(&"olavarria", &"honey", 3)
	_comprobar(miel != null and miel.is_completed() and miel.paid > 0 and GameState.money - plata == miel.paid, "Don Ernesto recibe la miel y paga $%d" % (miel.paid if miel != null else 0))


# 7. La cantera vieja: Don Aurelio la da, se pican las piedras de s_c y llegan 2 familias de canteros.
func _jugar_cantera_vieja() -> void:
	_paso("La cantera vieja")
	_hablar(_poblador(^"Cantero"))
	var cantera: Mission = _tablero.get_mission(&"cantera_vieja")
	_comprobar(cantera != null and cantera.is_active(), "Don Aurelio da la cantera vieja")
	_despejar(_mapa.get_node(^"PiedrasDesvio1"))
	_despejar(_mapa.get_node(^"PiedrasDesvio2"))
	await _cuadros(4)
	_comprobar(cantera != null and cantera.is_completed() and not _red.is_cut(&"s_c"), "Despejado s_c: la cantera vieja se cumple")
	_comprobar(_modelo.count_families(&"sierras_bayas", &"canteros") == 4, "Sierras Bayas tiene 4 familias de canteros")
	_comprobar(_ocupados(&"sierras_bayas").size() == 4, "Los 4 lotes de Sierras Bayas tienen su frente de cantera")
	var troncos: Mission = _principal(&"sierras_bayas", &"log")
	_comprobar(troncos != null and _tablero.can_report(troncos), "Los canteros nuevos piden más troncos de Azul")
	if troncos != null:
		_avisar(_poblador(^"Ramirez"), troncos)
		_comprobar(troncos.is_completed() and not troncos.offered, "Avisado Ramírez: el camino ya está estrenado, el Ferrocarril los trae")
	await _pasar_dia()
	_comprobar(_modelo.get_production(&"sierras_bayas").get(&"limestone", 0) == 40, "Con los dos frentes: 40 piedras por día")


# 8. Piedra para Azul y para Olavarría; los dos llegan al nivel 3.
func _jugar_nivel_3() -> void:
	_paso("Piedra para Azul y Olavarría: nivel 3")
	var azul: Mission = _principal(&"azul", &"limestone")
	var olav: Mission = _principal(&"olavarria", &"limestone")
	_comprobar(azul != null and _tablero.can_report(azul), "Azul pide piedra y ya hay")
	_comprobar(olav != null and _tablero.can_report(olav), "Olavarría pide más piedra y ya hay")
	if azul != null:
		_avisar(_poblador(^"DonaClara"), azul)
	if olav != null:
		_avisar(_poblador(^"JefeDeEstacion"), olav)
	_comprobar(azul != null and azul.is_completed() and olav != null and olav.is_completed(), "Avisados: nacen los dos flujos de piedra")
	for _i: int in MAX_DAYS_TO_LEVEL_3:
		if _modelo.get_level(&"azul") >= 3 and _modelo.get_level(&"olavarria") >= 3:
			break
		await _pasar_dia()
	_comprobar(_modelo.get_level(&"azul") == 3, "Azul llega al nivel 3 (nivel %d)" % _modelo.get_level(&"azul"))
	_comprobar(_modelo.get_level(&"olavarria") == 3, "Olavarría llega al nivel 3 (nivel %d)" % _modelo.get_level(&"olavarria"))


func _probar_final() -> void:
	_paso("Final")
	var pendientes: PackedStringArray = []
	for station_id: StringName in STATIONS:
		for mision: Mission in _tablero.get_main_missions(station_id):
			pendientes.append("%s: %s" % [station_id, mision.item_id])
	_comprobar(pendientes.is_empty(), "No queda ninguna principal pendiente (%s)" % ", ".join(pendientes))
	var secundarias: PackedStringArray = []
	for mision: Mission in _tablero.get_missions():
		if not mision.main and not mision.is_completed():
			secundarias.append(String(mision.id))
	_comprobar(secundarias.is_empty(), "Todas las secundarias cumplidas (faltan: %s)" % ", ".join(secundarias))
	for station_id: StringName in STATIONS:
		var familias: int = _modelo.get_families(station_id).size()
		_comprobar(_lotes.get_pending(station_id) == 0 and _ocupados(station_id).size() == familias, "%s: %d familias, todas con parcela" % [station_id, familias])
		_comprobar(_modelo.get_idle_families(station_id).is_empty(), "%s: todas las familias trabajan (sin trabajo: %s)" % [station_id, _modelo.get_idle_families(station_id)])
	_comprobar(GameState.money > START_MONEY, "Se terminó con más plata que al empezar ($%d)" % GameState.money)
	var texto: String = AgendaText.neighbors(_tablero, _modelo)
	_comprobar(texto.contains("los Etchegaray") and texto.contains("Doña Rosa"), "La pestaña Vecinos nombra a los Etchegaray y a Doña Rosa")


func _imprimir_resumen() -> void:
	print("")
	print("===== Resumen de la partida del Hito A =====")
	print("Días jugados: %d · plata: $%d" % [GameState.clock.current_day - _dias_al_empezar, GameState.money])
	for station_id: StringName in STATIONS:
		print("%s: nivel %d · familias %s · produce %s" % [_tablero.station_name(station_id), _modelo.get_level(station_id), _modelo.get_families(station_id), _modelo.get_production(station_id)])
		for lote: TrackLot in _ocupados(station_id):
			print("    ", lote.describe())
	print("Flujos:")
	for flujo: ProductionFlow in _modelo.get_flows():
		print("    ", flujo.describe(), " · entregó ", flujo.last_delivered)
	print(AgendaText.neighbors(_tablero, _modelo))
	print("============================================")


# --- Lo que hace el jugador ---


func _hablar(poblador: MissionGiver) -> String:
	if poblador == null:
		return ""
	var texto: String = poblador.talk(_jugador)
	print("    ", texto)
	return texto


# Le habla a quien da la principal hasta que recibe el aviso (antes puede contar un cierre).
func _avisar(poblador: MissionGiver, mision: Mission) -> void:
	for _i: int in 4:
		if mision.reported or not _tablero.can_report(mision):
			break
		_hablar(poblador)
	_comprobar(mision.reported, "%s recibe el aviso de %s" % [poblador.get_short_name() if poblador != null else "?", mision.item_id])


# Golpea el obstáculo hasta despejarlo (sin mirar la herramienta: eso lo prueba test_obstacles).
func _despejar(obstaculo: Node) -> void:
	var limpiable: Clearable = (obstaculo.get_node_or_null(^"Clearable") as Clearable) if obstaculo != null else null
	_comprobar(limpiable != null, "%s se puede despejar" % (String(obstaculo.name) if obstaculo != null else "?"))
	if limpiable == null:
		return
	for _i: int in 30:
		if limpiable.hit():
			return


# Un viaje en el coche propio: sube la gente en `desde` y baja en `hasta` (sin coche en la vía).
# Devuelve lo que pasó en `desde` (board_free, board_paid...).
func _viaje_en_coche(desde: StringName, hasta: StringName) -> Dictionary:
	var arriba: Dictionary = GameState.passengers.plan_exchange(desde, {} as Dictionary[StringName, int], 10)
	GameState.passengers.apply_exchange(desde, arriba)
	var a_bordo: Dictionary[StringName, int] = {}
	for clave: String in ["board_free", "board_paid"]:
		var parte: Dictionary = arriba.get(clave, {})
		for item_id: StringName in parte:
			a_bordo[item_id] = a_bordo.get(item_id, 0) + int(parte[item_id])
	_entregar_en_coche(hasta, a_bordo)
	return arriba


func _entregar_en_coche(station_id: StringName, a_bordo: Dictionary[StringName, int]) -> void:
	GameState.passengers.apply_exchange(station_id, GameState.passengers.plan_exchange(station_id, a_bordo, 10))


# Pone el tren en una vía libre de `station_id`, mirando hacia `toward`, como BorrowedTrains.
func _llevar(cabeza: Vehicle, station_id: StringName, toward: StringName, tren: Array[Vehicle]) -> void:
	var largo: float = 0.0
	for vehiculo: Vehicle in tren:
		largo += vehiculo.data.length + Vehicle.COUPLING_GAP
	var lugar: Array = _prestados.find_free_track(_red, station_id, largo, toward, tren)
	_comprobar(not lugar.is_empty(), "Hay vía libre en %s para el tren" % station_id)
	if lugar.is_empty():
		return
	var via: Path3D = lugar[0]
	var mira_al_final: bool = lugar[1]
	cabeza.throttle = 0.0
	for vehiculo: Vehicle in tren:
		vehiculo.speed = 0.0
	cabeza.place_on(via, _prestados._head_at_station(via, station_id, cabeza.data.length, largo, mira_al_final), not mira_al_final)
	cabeza.forget_route_ahead()
	for _i: int in 10:
		await get_tree().physics_frame


# Como la T sin trenes: hasta las 7 del día siguiente.
func _pasar_dia() -> void:
	GameState.clock.advance(GameClock.HOURS_PER_DAY - GameState.clock.time_of_day + SKIP_MORNING_HOUR)
	await _cuadros(4)
	print("    -- Día %d --" % GameState.clock.current_day)


func _esperar_tren(mission_id: StringName) -> Array[Vehicle]:
	for _i: int in 30:
		if _prestados.has_train(mission_id):
			break
		await get_tree().create_timer(0.2).timeout
	await _cuadros(3)
	return _prestados.get_train(mission_id)


func _cuadros(cantidad: int) -> void:
	for _i: int in cantidad:
		await get_tree().process_frame


# --- Consultas ---


func _poblador(camino: NodePath) -> MissionGiver:
	var poblador := _mapa.get_node_or_null(camino) as MissionGiver
	_comprobar(poblador != null, "Está %s" % camino)
	return poblador


func _principal(station_id: StringName, item_id: StringName) -> Mission:
	for mision: Mission in _tablero.get_main_missions(station_id):
		if mision.item_id == item_id:
			return mision
	return null


func _regalo_de(segment_id: StringName) -> WagonGift:
	for nodo: Node in get_tree().get_nodes_in_group(WagonGift.GROUP):
		var regalo := nodo as WagonGift
		if regalo != null and regalo.open_segment == segment_id:
			return regalo
	return null


func _coche_de(tren: Array[Vehicle]) -> PassengerCoach:
	for vehiculo: Vehicle in tren:
		if vehiculo is PassengerCoach:
			return vehiculo as PassengerCoach
	return null


# Los lotes de la estación con una familia (sin los galpones fijos).
func _ocupados(station_id: StringName) -> Array[TrackLot]:
	var lotes: Array[TrackLot] = []
	for lote: TrackLot in _lotes.get_lots(station_id):
		if not lote.is_free() and lote.fixed_scene == null:
			lotes.append(lote)
	return lotes


func _parcela_de(station_id: StringName, occupation_id: StringName) -> TrackLot:
	for lote: TrackLot in _ocupados(station_id):
		if lote.get_occupation_id() == occupation_id:
			return lote
	return null


func _contar_objetos() -> int:
	var cantidad: int = 0
	for hijo: Node in get_tree().current_scene.get_children():
		if hijo is WorldItem:
			cantidad += 1
	return cantidad


func _paso(titulo: String) -> void:
	print("")
	print("== %s (día %d, $%d) ==" % [titulo, GameState.clock.current_day, GameState.money])


func _comprobar(condicion: bool, texto: String) -> void:
	if condicion:
		print("  OK  ", texto)
	else:
		_fallos += 1
		push_error("  FALLA  " + texto)
