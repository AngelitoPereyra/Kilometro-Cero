extends Node
## Prueba de las tareas 62.1, 62.4, 62.5 y 62b.2: los datos del Hito A (Olavarría, Azul y Sierras
## Bayas, con el bioma de las sierras y las familias con oficio) y la cadena entera jugada en
## lógica, sin mapa ni trenes prestados (las principales se cumplen entregando; plan en
## tarea-62b/plan-62b.md). Usa su propio modelo, su tablero y su tráfico de pasajeros, así no
## toca la partida de GameState.
## Red: Azul --(o_a)-- Olavarría --(o_s)-- Sierras Bayas --(s_c, cortado)-- cantera vieja.
## o_a y o_s empiezan tapados por los troncos (la vía tapada) y se abren a mano.

const STATION_FILES: Array[String] = ["olavarria", "azul", "sierras_bayas"]
const MISSION_FILES: Array[String] = ["maestra_azul", "cantera_vieja"]
## Oficios del Hito A: id -> [tipo, rasgo, insumos, producción] (valores del plan de la 62b).
const OCCUPATIONS: Dictionary = {
	&"hacheros": [OccupationData.Kind.RAW, &"monte", {}, {&"log": 10}],
	&"puesteros": [OccupationData.Kind.RAW, &"campo", {}, {&"hides": 2}],
	&"canteros": [OccupationData.Kind.RAW, &"cantera", {&"log": 5}, {&"limestone": 10}],
	&"caleros": [OccupationData.Kind.PROCESSED, &"horno", {&"limestone": 10}, {&"cement": 5}],
	&"tamberos": [OccupationData.Kind.FOOD, &"campo", {}, {&"milk": 5}],
	&"curtidores": [OccupationData.Kind.PROCESSED, &"", {&"hides": 2}, {&"leather": 1}],
}
## Objetos nuevos de la 62b.2: id -> [tamaño, precio].
const NEW_ITEMS: Dictionary = {
	&"hides": [ItemData.SizeClass.MEDIUM, 25.0],
	&"milk": [ItemData.SizeClass.MEDIUM, 10.0],
	&"honey": [ItemData.SizeClass.SMALL, 30.0],
	&"leather": [ItemData.SizeClass.MEDIUM, 70.0],
}
## Tramos: id -> [estación, estación]. La cantera vieja no es una estación.
const SEGMENTS: Dictionary = {
	&"o_a": [&"olavarria", &"azul"],
	&"o_s": [&"olavarria", &"sierras_bayas"],
	&"s_c": [&"sierras_bayas", &"cantera_vieja"],
}

var _fallos: int = 0
var _cortados: Dictionary[StringName, bool] = {&"o_a": true, &"o_s": true, &"s_c": true}
var _modelo: ProductionModel
var _tablero: MissionBoard
var _economia: Economy
var _trafico: PassengerTraffic


func _ready() -> void:
	_probar_archivos()
	_probar_oficios_y_bioma()
	_armar()
	_probar_arranque()
	_probar_cadena()
	_probar_oficios_del_jugador()
	_probar_vuelta_atras()
	if _fallos == 0:
		print("Hito A (cadena): todas las comprobaciones pasaron.")
	else:
		push_error("Hito A (cadena): fallaron %d comprobaciones." % _fallos)


func _probar_archivos() -> void:
	# Tarea 62.5: la vía tapada de Olavarría la da el jefe de estación, con el hacha.
	var tapada := load("res://data/missions/la_via_tapada.tres") as MissionData
	_comprobar(tapada != null and tapada.validate().is_empty() and tapada.kind == MissionData.Kind.CLEAR_ZONE and tapada.zone_group == &"troncos_olavarria", "La vía tapada: despejar los troncos de Olavarría")
	_comprobar(tapada != null and tapada.gives_tools.size() == 1 and tapada.gives_tools[0] != null and tapada.gives_tools[0].id == &"axe", "La vía tapada da el hacha")
	var piedra := load("res://data/items/limestone.tres") as ItemData
	var cemento := load("res://data/items/cement.tres") as ItemData
	_comprobar(piedra != null and piedra.id == &"limestone" and piedra.size_class == ItemData.SizeClass.LARGE and piedra.tags.has(&"stone"), "Piedra caliza: grande, etiqueta stone")
	_comprobar(cemento != null and cemento.id == &"cement" and cemento.size_class == ItemData.SizeClass.MEDIUM and cemento.tags.has(&"cement"), "Cemento: mediano, etiqueta cement")
	_comprobar(piedra != null and piedra.scene != null and cemento != null and cemento.scene != null, "Piedra y cemento tienen escena")
	# Tarea 62b.2: cuero, leche, miel y cuero curtido.
	for item_id: StringName in NEW_ITEMS:
		var objeto := load("res://data/items/%s.tres" % item_id) as ItemData
		var esperado: Array = NEW_ITEMS[item_id]
		_comprobar(objeto != null and objeto.id == item_id and objeto.size_class == esperado[0] and is_equal_approx(objeto.base_value, esperado[1]) and objeto.scene != null and not objeto.cargo_name.is_empty(), "Objeto nuevo %s: tamaño, precio, escena y nombre de carga" % item_id)
	var miel := load("res://data/items/honey.tres") as ItemData
	_comprobar(miel != null and miel.tags.has(&"wild"), "La miel es un material silvestre")
	var plataforma := load("res://data/vehicles/flatcar.tres") as WagonData
	_comprobar(plataforma != null and plataforma.accepted_tags.has(&"stone") and plataforma.accepted_tags.has(&"log"), "La plataforma lleva piedra y troncos")
	var cerrado := load("res://data/vehicles/boxcar.tres") as WagonData
	_comprobar(cerrado != null and cerrado.cargo_type == WagonData.CargoType.BOXCAR and cerrado.capacity == 40 and cerrado.accepted_tags.size() == 1 and cerrado.accepted_tags.has(&"cement"), "Vagón cerrado: 40 bolsas de cemento")
	var escena := load("res://scenes/vehicles/boxcar.tscn") as PackedScene
	var vagon: Wagon = (escena.instantiate() as Wagon) if escena != null else null
	_comprobar(vagon != null and vagon.data == cerrado, "boxcar.tscn es un Wagon con boxcar.tres")
	if vagon != null:
		vagon.free()
	var roca := load("res://scenes/obstacles/rock.tscn") as PackedScene
	var obstaculo: Node = roca.instantiate() if roca != null else null
	var limpiable: Clearable = (obstaculo.get_node_or_null("Clearable") as Clearable) if obstaculo != null else null
	_comprobar(limpiable != null and limpiable.drop_item == piedra and limpiable.drop_amount == 3, "La piedra caída suelta 3 piedras")
	if obstaculo != null:
		obstaculo.free()
	var aflora := load("res://scenes/world/quarry_rock.tscn") as PackedScene
	var cuerpo: Node = aflora.instantiate() if aflora != null else null
	var cosecha: Harvestable = (cuerpo.get_node_or_null("Harvestable") as Harvestable) if cuerpo != null else null
	_comprobar(cosecha != null and cosecha.drop_item == piedra and cosecha.get_required_tool_id() == &"pickaxe", "El afloramiento da piedra con el pico (62.7)")
	if cuerpo != null:
		cuerpo.free()
	for nombre: String in STATION_FILES:
		var datos := load("res://data/stations/%s.tres" % nombre) as StationData
		_comprobar(datos != null and datos.id == StringName(nombre) and datos.validate().is_empty(), "Estación %s sin problemas %s" % [nombre, datos.validate() if datos != null else PackedStringArray()])
	for nombre: String in MISSION_FILES:
		var datos := load("res://data/missions/%s.tres" % nombre) as MissionData
		_comprobar(datos != null and datos.id == StringName(nombre) and datos.validate().is_empty(), "Misión %s sin problemas %s" % [nombre, datos.validate() if datos != null else PackedStringArray()])
	# Tarea 62b.2: la cantera vieja ya no da producción suelta sino dos familias de canteros.
	var cantera := load("res://data/missions/cantera_vieja.tres") as MissionData
	_comprobar(cantera != null and cantera.reward_production.is_empty() and cantera.reward_families.size() == 2 and cantera.reward_families[0] != null and cantera.reward_families[0].id == &"canteros" and cantera.reward_families[1] != null and cantera.reward_families[1].id == &"canteros", "La cantera vieja da 2 familias de canteros")


# Tarea 62b.2: los seis oficios, el bioma de las sierras y lo que tiene cada estación.
func _probar_oficios_y_bioma() -> void:
	var todos: Array[OccupationData] = OccupationData.load_all()
	_comprobar(todos.size() == OCCUPATIONS.size(), "load_all junta los %d oficios de data/occupations (encontró %d)" % [OCCUPATIONS.size(), todos.size()])
	for occupation_id: StringName in OCCUPATIONS:
		var oficio := load("res://data/occupations/%s.tres" % occupation_id) as OccupationData
		var esperado: Array = OCCUPATIONS[occupation_id]
		var bien: bool = oficio != null and oficio.id == occupation_id and oficio.validate().is_empty()
		bien = bien and oficio.kind == esperado[0] and oficio.requires_trait == esperado[1]
		bien = bien and oficio.get_needs() == _dic(esperado[2]) and oficio.get_production() == _dic(esperado[3])
		_comprobar(bien, "Oficio %s: tipo, rasgo, insumos y producción" % occupation_id)
	var sierras := load("res://data/biomes/sierras.tres") as BiomeData
	_comprobar(sierras != null and sierras.id == &"sierras" and sierras.validate().is_empty(), "Bioma sierras sin problemas")
	if sierras != null:
		_comprobar(_ids(sierras.own) == ([&"canteros", &"caleros", &"puesteros"] as Array[StringName]), "Sierras: propios canteros, caleros y puesteros")
		_comprobar(_ids(sierras.possible) == ([&"tamberos", &"curtidores"] as Array[StringName]), "Sierras: posibles tamberos y curtidores")
		_comprobar(not sierras.allows(&"hacheros"), "Los hacheros no son de las sierras: los habilita el monte")
		_comprobar(sierras.natural_demands.size() == 1 and sierras.natural_demands[0] != null and sierras.natural_demands[0].id == &"log", "Sierras: demanda natural de troncos")
	var rasgos: Dictionary = {&"olavarria": [&"horno"], &"azul": [&"monte", &"campo"], &"sierras_bayas": [&"cantera"]}
	var tipos: Dictionary = {&"olavarria": StationData.StationType.CITY, &"azul": StationData.StationType.TOWN, &"sierras_bayas": StationData.StationType.FREIGHT}
	for nombre: String in STATION_FILES:
		var datos := load("res://data/stations/%s.tres" % nombre) as StationData
		var id: StringName = StringName(nombre)
		var esperados: Array[StringName] = []
		esperados.assign(rasgos[id])
		_comprobar(datos != null and datos.biome == sierras and datos.traits == esperados and datos.type == tipos[id], "%s: bioma sierras, rasgos %s y tipo" % [nombre, esperados])


func _armar() -> void:
	_modelo = ProductionModel.new()
	_modelo.connection_check = _conectadas
	# Como GameState: todos los oficios, también los hacheros (solo los habilita el monte).
	for oficio: OccupationData in OccupationData.load_all():
		_modelo.add_occupation(oficio)
	_tablero = MissionBoard.new(_modelo)
	_tablero.route_finder = _camino
	_tablero.segment_check = func(segment_id: StringName) -> bool: return not _cortados.get(segment_id, false)
	_economia = Economy.new(_modelo)
	_trafico = PassengerTraffic.new(_tablero, _economia)
	for nombre: String in STATION_FILES:
		var datos := load("res://data/stations/%s.tres" % nombre) as StationData
		_modelo.add_station(datos, 1)
		_economia.add_station(datos)
	for nombre: String in MISSION_FILES:
		_tablero.register_side(load("res://data/missions/%s.tres" % nombre) as MissionData)
	_tablero.refresh()


# Al empezar: las familias del nivel 1 y lo que piden.
func _probar_arranque() -> void:
	_comprobar(_modelo.get_families(&"olavarria") == ([&"caleros", &"caleros"] as Array[StringName]), "Olavarría arranca con 2 familias de caleros (%s)" % [_modelo.get_families(&"olavarria")])
	_comprobar(_modelo.get_families(&"sierras_bayas") == ([&"canteros", &"canteros"] as Array[StringName]), "Sierras Bayas arranca con 2 familias de canteros (%s)" % [_modelo.get_families(&"sierras_bayas")])
	_comprobar(_modelo.get_family_count(&"azul") == 0, "Azul arranca sin familias nuevas (queda el último hachero)")
	_comprobar(_modelo.get_idle_families(&"olavarria").size() == 2 and _modelo.get_idle_families(&"sierras_bayas").size() == 2, "Sin piedra ni troncos, caleros y canteros no trabajan")
	_comprobar(_modelo.get_production(&"olavarria").get(&"cement", 0) == 0 and _modelo.get_production(&"sierras_bayas").get(&"limestone", 0) == 0, "Todavía no hay cemento ni piedra")
	_comprobar(_ids(_modelo.get_allowed_occupations(&"azul")) == ([&"puesteros", &"hacheros"] as Array[StringName]), "En Azul toman oficio solos puesteros (campo) y hacheros (monte) (%s)" % [_ids(_modelo.get_allowed_occupations(&"azul"))])
	_comprobar(_economia.get_item(&"hides") != null and _economia.get_item(&"leather") != null, "El mercado conoce los objetos de los oficios (cuero, cuero curtido)")


func _probar_cadena() -> void:
	# Tarea 62.4 (D120): los flujos empiezan el día siguiente y los primeros niveles crecen en un día.
	_tablero.flows_start_next_day = true
	# 1. Olavarría pide la piedra de sus caleros, que nadie da; Azul pide colonos de Olavarría;
	# Sierras Bayas pide los troncos de sus canteros, que Azul ya saca. o_a y o_s están tapados.
	var piedra_olav: Mission = _principal(&"olavarria", &"limestone")
	_comprobar(piedra_olav != null and piedra_olav.flow_amount == 20 and piedra_olav.required.get(&"limestone", 0) == 40, "Olavarría pide 20 piedras por día para sus caleros (primera carga de 40)")
	_comprobar(piedra_olav != null and _tablero.find_source(piedra_olav) == &"", "Nadie da piedra todavía (los canteros no tienen troncos)")
	var colonos: Mission = _principal(&"azul", &"settlers")
	_comprobar(colonos != null and colonos.flow_amount == 5 and colonos.required.get(&"settlers", 0) == 10 and _tablero.find_source(colonos) == &"olavarria", "Azul pide 5 colonos por día de Olavarría (primera carga de 10)")
	var troncos: Mission = _principal(&"sierras_bayas", &"log")
	_comprobar(_modelo.get_production(&"azul").get(&"log", 0) == 10, "Azul ya saca 10 troncos por día (el último hachero)")
	_comprobar(troncos != null and troncos.flow_amount == 10 and _tablero.find_source(troncos) == &"azul" and _tablero.get_cut_segments(troncos).size() == 2, "Sierras Bayas pide 10 troncos de Azul: faltan despejar o_a y o_s")
	_comprobar(_tablero.get_passenger_missions_from(&"olavarria").has(colonos) and _tablero.is_reserved_passenger(&"settlers"), "Los colonos suben gratis en Olavarría")
	# 2. Colonos para Azul: con la vía tapada esperan; despejada se cumple y Azul crece al otro día.
	_entregar_en_coche(&"azul", &"settlers", 10)
	_comprobar(colonos.is_active(), "Con o_a tapado los colonos esperan")
	_abrir(&"o_a")
	_abrir(&"o_s")
	_comprobar(colonos.is_completed() and colonos.flow != null and colonos.flow.round_trip and colonos.flow.pending, "Despejada la vía: nace el flujo de colonos ida y vuelta, desde mañana")
	_comprobar(troncos != null and troncos.is_active(), "Los troncos de Sierras Bayas siguen esperando su primera carga")
	_modelo.advance_day()
	_comprobar(_modelo.get_level(&"azul") == 2, "Azul sube a nivel 2 en un día (nivel %d)" % _modelo.get_level(&"azul"))
	_comprobar(_modelo.get_families(&"azul") == ([&"puesteros", &"hacheros"] as Array[StringName]), "Llegan 2 familias a Azul: puesteros y hacheros (%s)" % [_modelo.get_families(&"azul")])
	var produce_azul: Dictionary[StringName, int] = _modelo.get_production(&"azul")
	_comprobar(produce_azul.get(&"log", 0) == 20 and produce_azul.get(&"hides", 0) == 2, "Azul nivel 2: 20 troncos y 2 cueros por día")
	var piedra_azul: Mission = _principal(&"azul", &"limestone")
	var cemento_azul: Mission = _principal(&"azul", &"cement")
	_comprobar(piedra_azul != null and piedra_azul.flow_amount == 10 and _tablero.find_source(piedra_azul) == &"", "Azul pide 10 piedras y todavía no hay")
	_comprobar(cemento_azul != null and cemento_azul.flow_amount == 5 and _tablero.find_source(cemento_azul) == &"", "Azul pide 5 cemento y los caleros todavía no queman")
	# 3. Troncos para Sierras Bayas: los canteros pican al otro día y la cantera crece.
	_tablero.deliver(&"sierras_bayas", &"log", 20)
	_comprobar(troncos != null and troncos.is_completed() and troncos.flow != null and troncos.flow.pending, "20 troncos en Sierras Bayas: nace el flujo de troncos, desde mañana")
	_comprobar(_modelo.get_production(&"sierras_bayas").get(&"limestone", 0) == 0, "Hoy los canteros todavía no pican")
	_modelo.advance_day()
	_comprobar(troncos != null and troncos.flow.last_delivered == 10, "Al otro día el flujo entrega 10 troncos")
	_comprobar(_modelo.get_idle_families(&"sierras_bayas").is_empty() and _modelo.get_production(&"sierras_bayas").get(&"limestone", 0) == 20, "Los canteros trabajan: 20 piedras por día")
	_comprobar(_modelo.get_level(&"sierras_bayas") == 2, "Sierras Bayas nivel 2 en un día (nivel %d)" % _modelo.get_level(&"sierras_bayas"))
	# 4. Piedra para Olavarría: los caleros queman, sale cemento y la ciudad crece.
	_comprobar(_tablero.find_source(piedra_olav) == &"sierras_bayas", "Ahora la piedra de Olavarría sale de Sierras Bayas")
	_tablero.deliver(&"olavarria", &"limestone", 40)
	_comprobar(piedra_olav.is_completed(), "40 piedras en Olavarría: nace el flujo de piedra")
	_comprobar(_tablero.find_source(piedra_azul) == &"", "Para Azul no queda piedra libre")
	_modelo.advance_day()
	_comprobar(_modelo.get_level(&"olavarria") == 2, "Olavarría sube a nivel 2 en un día (nivel %d)" % _modelo.get_level(&"olavarria"))
	_comprobar(_modelo.get_families(&"olavarria") == ([&"caleros", &"caleros", &"caleros"] as Array[StringName]), "Llega una tercera familia de caleros (%s)" % [_modelo.get_families(&"olavarria")])
	_comprobar(_modelo.get_idle_families(&"olavarria") == ([&"caleros"] as Array[StringName]), "La familia nueva no tiene piedra: no trabaja")
	var produce: Dictionary[StringName, int] = _modelo.get_production(&"olavarria")
	_comprobar(produce.get(&"cement", 0) == 10 and produce.get(&"teacher", 0) == 1, "Olavarría nivel 2: 10 cemento y 1 maestra por día")
	var piedra_olav2: Mission = _principal(&"olavarria", &"limestone")
	_comprobar(piedra_olav2 != null and piedra_olav2.flow_amount == 10 and _tablero.find_source(piedra_olav2) == &"", "Olavarría pide 10 piedras más y a la cantera no le quedan")
	# 5. Cemento para Azul y la maestra de Azul (secundaria de pasajeros).
	_comprobar(_tablero.find_source(cemento_azul) == &"olavarria", "El cemento de Azul sale de Olavarría")
	_tablero.deliver(&"azul", &"cement", 10)
	_comprobar(cemento_azul != null and cemento_azul.is_completed(), "10 cemento en Azul: nace el flujo de cemento")
	var maestra: Mission = _tablero.get_mission(&"maestra_azul")
	_comprobar(maestra != null and maestra.state == Mission.State.AVAILABLE, "La maestra de Azul queda disponible con Azul en nivel 2")
	_tablero.start(&"maestra_azul")
	_comprobar(_tablero.passenger_source(maestra, &"teacher") == &"olavarria", "La maestra sale de Olavarría")
	_comprobar(_tablero.get_passenger_missions_from(&"olavarria").has(maestra) and _tablero.is_reserved_passenger(&"teacher"), "La maestra sube gratis en Olavarría (reservada)")
	var plan: Dictionary = _trafico.plan_exchange(&"azul", {&"teacher": 1} as Dictionary[StringName, int], 10)
	_comprobar(int((plan["mission"] as Dictionary).get(&"teacher", 0)) == 1, "Al abrir las puertas en Azul la maestra baja para su misión")
	_trafico.apply_exchange(&"azul", plan)
	_comprobar(maestra.is_completed() and _tablero.has_delivered(&"azul", &"teacher"), "Llegó la maestra: secundaria cumplida (abre la escuela)")
	_comprobar(not _tablero.is_reserved_passenger(&"teacher"), "Cumplida, la maestra ya no está reservada")
	# 6. La cantera vieja: llegan 2 familias de canteros que piden más troncos de Azul.
	var cantera: Mission = _tablero.get_mission(&"cantera_vieja")
	_comprobar(cantera != null and cantera.state == Mission.State.AVAILABLE, "La cantera vieja queda disponible con Sierras Bayas en nivel 2")
	_tablero.start(&"cantera_vieja")
	_comprobar(cantera.is_active(), "Con s_c cortado la cantera vieja sigue en curso")
	_abrir(&"s_c")
	_comprobar(cantera.is_completed() and _modelo.count_families(&"sierras_bayas", &"canteros") == 4, "Despejado s_c: Sierras Bayas suma 2 familias de canteros (tiene %d)" % _modelo.count_families(&"sierras_bayas", &"canteros"))
	_comprobar(_modelo.get_idle_families(&"sierras_bayas").size() == 2 and _modelo.get_production(&"sierras_bayas").get(&"limestone", 0) == 20, "Las familias nuevas no tienen troncos: todavía 20 piedras")
	var troncos2: Mission = _principal(&"sierras_bayas", &"log")
	_comprobar(troncos2 != null and troncos2.flow_amount == 10 and _tablero.find_source(troncos2) == &"azul", "Sierras Bayas pide 10 troncos más: los de los hacheros de Azul")
	_tablero.deliver(&"sierras_bayas", &"log", 20)
	_comprobar(troncos2 != null and troncos2.is_completed(), "20 troncos más: nace el segundo flujo de troncos")
	_modelo.advance_day()
	_comprobar(_modelo.get_idle_families(&"sierras_bayas").is_empty() and _modelo.get_production(&"sierras_bayas").get(&"limestone", 0) == 40, "Con los dos frentes: 40 piedras por día")
	# 7. Ahora la piedra alcanza para Azul y Olavarría y los dos llegan al nivel 3.
	_comprobar(_tablero.find_source(piedra_azul) == &"sierras_bayas" and _tablero.find_source(piedra_olav2) == &"sierras_bayas", "La piedra alcanza para Azul y Olavarría")
	_tablero.deliver(&"azul", &"limestone", 20)
	_tablero.deliver(&"olavarria", &"limestone", 20)
	_comprobar(piedra_azul != null and piedra_azul.is_completed() and piedra_olav2 != null and piedra_olav2.is_completed(), "Entregadas: nacen los dos flujos de piedra")
	_modelo.advance_days(2)
	_comprobar(_modelo.get_level(&"azul") == 3, "Azul llega a nivel 3 (nivel %d)" % _modelo.get_level(&"azul"))
	_comprobar(_modelo.get_level(&"olavarria") == 3, "Olavarría llega a nivel 3 (nivel %d)" % _modelo.get_level(&"olavarria"))
	_comprobar(_modelo.get_idle_families(&"olavarria").is_empty() and _modelo.get_production(&"olavarria").get(&"cement", 0) == 15, "Los 3 caleros trabajan: 15 cemento por día")
	var pendientes: int = 0
	for nombre: String in STATION_FILES:
		pendientes += _tablero.get_main_missions(StringName(nombre)).size()
	_comprobar(pendientes == 0, "No queda ninguna principal pendiente en el Hito A (quedan %d)" % pendientes)
	print("Flujos al final:")
	for flujo: ProductionFlow in _modelo.get_flows():
		print("  ", flujo.describe(), " · entregó ", flujo.last_delivered)


# Tarea 62b.2: lo que puede traer el jugador en el Hito A (las mudanzas y encargos son de la 62b.6).
func _probar_oficios_del_jugador() -> void:
	_comprobar(_modelo.can_add_player_family(&"azul", &"tamberos"), "Azul acepta tamberos del jugador (posible de las sierras, con campo)")
	_comprobar(not _modelo.can_add_player_family(&"olavarria", &"tamberos"), "Olavarría no: no tiene campo")
	_comprobar(not _modelo.can_add_player_family(&"azul", &"hacheros"), "Los hacheros no los trae el jugador (no son de las sierras)")
	_comprobar(not _modelo.can_add_player_family(&"sierras_bayas", &"canteros"), "Sierras Bayas es de carga: el jugador no trae familias")
	_comprobar(_modelo.get_player_slots(&"azul") == 1 and _modelo.get_player_slots(&"olavarria") == 3, "Lugar para el jugador: 1 en Azul, 3 en Olavarría")
	# Doña Rosa se queda como curtidora: pide cueros y nace la principal que los trae de Azul.
	_comprobar(_modelo.add_player_family(&"olavarria", &"curtidores"), "Doña Rosa se queda en Olavarría como curtidora")
	_comprobar(_modelo.get_idle_families(&"olavarria") == ([&"curtidores"] as Array[StringName]), "Sin cueros la curtidora no trabaja")
	var cueros: Mission = _principal(&"olavarria", &"hides")
	_comprobar(cueros != null and cueros.flow_amount == 2 and _tablero.find_source(cueros) == &"azul", "Nace la principal de 2 cueros por día, de los puesteros de Azul")
	_tablero.deliver(&"olavarria", &"hides", 4)
	_modelo.advance_day()
	_comprobar(cueros != null and cueros.is_completed() and _modelo.get_production(&"olavarria").get(&"leather", 0) == 1, "Con los cueros, 1 cuero curtido por día")
	_comprobar(_modelo.get_player_slots(&"olavarria") == 2, "A Olavarría le quedan 2 lugares para el jugador")


# Tarea 62.4: un automático trabado vuelve a la estación de donde salió y prueba otra vez.
func _probar_vuelta_atras() -> void:
	var run := AutoTrainRun.new()
	run.home = &"a"
	run.away = &"b"
	run.behind = 20.0
	var piezas: Array[StringName] = [AutoTrainRun.station_piece(&"a", "Principal", true), &"a_b", AutoTrainRun.station_piece(&"b", "Principal", false)]
	var largos: Array[float] = [100.0, 300.0, 100.0]
	_comprobar(run.depart(piezas, largos) and run.state == AutoTrainRun.State.OUTBOUND, "Sale de a hacia b")
	run.advance(150.0, 0.0)
	var donde: float = run.position
	_comprobar(run.turn_back() and run.turned_back and not run.loco_leads, "Trabado, da la vuelta: la locomotora queda atrás y empuja")
	_comprobar(run.leg_from() == &"b" and run.leg_to() == &"a" and is_equal_approx(run.position, 500.0 - donde), "El viaje se dio vuelta desde donde estaba, hacia a")
	_comprobar(run.leg[0] == AutoTrainRun.station_piece(&"b", "Principal", true) and run.leg[2] == AutoTrainRun.station_piece(&"a", "Principal", false), "Las vías de estación se recorren al revés")
	_comprobar(run.advance(1000.0, 1.0) and run.dwelling and not run.is_moving(), "Llega a a como a una parada")
	_comprobar(run.leg_from() == &"a" and run.leg_to() == &"b" and run.loco_leads and not run.turned_back, "Espera en a y vuelve a probar hacia b con la locomotora adelante")
	_comprobar(is_equal_approx(run.due, 1.0 + AutoTrainRun.MIN_DWELL_HOURS) and run.state == AutoTrainRun.State.OUTBOUND, "Sale de nuevo en media hora, todavía de ida")


# Entrega pasajeros como al abrir las puertas del coche en la estación.
func _entregar_en_coche(station_id: StringName, item_id: StringName, amount: int) -> void:
	var a_bordo: Dictionary[StringName, int] = {item_id: amount}
	_trafico.apply_exchange(station_id, _trafico.plan_exchange(station_id, a_bordo, 10))


func _abrir(segment_id: StringName) -> void:
	_cortados[segment_id] = false
	_tablero.refresh()


func _principal(station_id: StringName, item_id: StringName) -> Mission:
	for mision: Mission in _tablero.get_main_missions(station_id):
		if mision.item_id == item_id:
			return mision
	return null


# Camino de tramos entre dos estaciones (también por los cortados), o null.
func _camino(from: StringName, to: StringName) -> Variant:
	var previo: Dictionary = {from: [] as Array[StringName]}
	var cola: Array[StringName] = [from]
	while not cola.is_empty():
		var actual: StringName = cola.pop_front()
		if actual == to:
			return previo[actual]
		for segment_id: StringName in SEGMENTS:
			var puntas: Array = SEGMENTS[segment_id]
			if not puntas.has(actual):
				continue
			var otra: StringName = puntas[1] if puntas[0] == actual else puntas[0]
			if previo.has(otra):
				continue
			var ruta: Array[StringName] = (previo[actual] as Array[StringName]).duplicate()
			ruta.append(segment_id)
			previo[otra] = ruta
			cola.append(otra)
	return null


func _conectadas(from: StringName, to: StringName) -> bool:
	var ruta: Variant = _camino(from, to)
	if ruta == null:
		return false
	for segment_id: StringName in ruta:
		if _cortados.get(segment_id, false):
			return false
	return true


func _ids(list: Array[OccupationData]) -> Array[StringName]:
	var result: Array[StringName] = []
	for oficio: OccupationData in list:
		result.append(oficio.id if oficio != null else &"")
	return result


func _dic(values: Dictionary) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	for key: StringName in values:
		result[key] = int(values[key])
	return result


func _comprobar(ok: bool, texto: String) -> void:
	if ok:
		print("OK  ", texto)
	else:
		_fallos += 1
		push_error("FALLA  " + texto)
