extends Node
## Prueba de las tareas 62.1, 62.4 y 62.5: los datos del Hito A (Olavarría, Azul y Sierras Bayas) y la cadena
## entera jugada en lógica, sin mapa (plan en tarea-62/plan-62.md). Usa su propio modelo, su
## tablero y su tráfico de pasajeros, así no toca la partida de GameState.
## Red: Azul --(o_a, cortado)-- Olavarría --(o_s)-- Sierras Bayas --(s_c, cortado)-- cantera vieja.

const STATION_FILES: Array[String] = ["olavarria", "azul", "sierras_bayas"]
const MISSION_FILES: Array[String] = ["maestra_azul", "cantera_vieja"]
## Tramos: id -> [estación, estación]. La cantera vieja no es una estación.
const SEGMENTS: Dictionary = {
	&"o_a": [&"olavarria", &"azul"],
	&"o_s": [&"olavarria", &"sierras_bayas"],
	&"s_c": [&"sierras_bayas", &"cantera_vieja"],
}

var _fallos: int = 0
var _cortados: Dictionary[StringName, bool] = {&"o_a": true, &"s_c": true}
var _modelo: ProductionModel
var _tablero: MissionBoard
var _economia: Economy
var _trafico: PassengerTraffic


func _ready() -> void:
	_probar_archivos()
	_armar()
	_probar_cadena()
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


func _armar() -> void:
	_modelo = ProductionModel.new()
	_modelo.connection_check = _conectadas
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


func _probar_cadena() -> void:
	# Tarea 62.4 (D120): los flujos empiezan el día siguiente y los primeros niveles crecen en un día.
	_tablero.flows_start_next_day = true
	# 1. Al empezar: Olavarría pide piedra que nadie da; Azul pide colonos de Olavarría; Sierras
	# Bayas pide los troncos que Azul ya saca, pero o_a está cortado.
	var piedra_olav: Mission = _principal(&"olavarria", &"limestone")
	_comprobar(piedra_olav != null and piedra_olav.flow_amount == 10 and piedra_olav.required.get(&"limestone", 0) == 20, "Olavarría pide 10 piedras por día (primera carga de 20: una plataforma)")
	_comprobar(piedra_olav != null and _tablero.find_source(piedra_olav) == &"", "Nadie da piedra todavía (Sierras Bayas parada)")
	var colonos: Mission = _principal(&"azul", &"settlers")
	_comprobar(colonos != null and colonos.flow_amount == 5 and _tablero.find_source(colonos) == &"olavarria", "Azul pide 5 colonos por día de Olavarría")
	var troncos: Mission = _principal(&"sierras_bayas", &"log")
	_comprobar(_modelo.get_production(&"azul").get(&"log", 0) == 10, "Azul ya saca 10 troncos por día")
	_comprobar(troncos != null and _tablero.find_source(troncos) == &"azul" and _tablero.get_cut_segments(troncos).has(&"o_a"), "Sierras Bayas pide los troncos de Azul: falta despejar o_a")
	_comprobar(_tablero.get_passenger_missions_from(&"olavarria").has(colonos) and _tablero.is_reserved_passenger(&"settlers"), "Los colonos suben gratis en Olavarría")
	# 2. Con o_a cortado las entregas esperan; al despejarlo se cumplen y los flujos empiezan mañana.
	_entregar_en_coche(&"azul", &"settlers", 10)
	_tablero.deliver(&"sierras_bayas", &"log", 20)
	_comprobar(colonos.is_active() and troncos != null and troncos.is_active(), "Con o_a cortado las de colonos y troncos esperan")
	_abrir(&"o_a")
	_comprobar(colonos.is_completed() and colonos.flow != null and colonos.flow.round_trip, "Despejado o_a: nace el flujo de colonos ida y vuelta")
	_comprobar(troncos != null and troncos.is_completed() and troncos.flow != null, "Despejado o_a: nace el flujo de troncos (los 20 del regalo de Azul)")
	_comprobar(troncos != null and troncos.flow.pending and _modelo.get_running_flows().is_empty(), "Los flujos nuevos empiezan mañana (62.4)")
	_comprobar(_modelo.get_supply(&"sierras_bayas").get(&"log", 0) == 0, "Hoy todavía no llegan troncos por el flujo")
	_comprobar(_principal(&"sierras_bayas", &"log") == null and _principal(&"azul", &"settlers") == null, "Pero ya comprometen: no nace otra misión por lo mismo")
	# 3. Al otro día empiezan, y Azul y Sierras Bayas crecen en un día.
	_modelo.advance_day()
	_comprobar(troncos != null and not troncos.flow.pending and troncos.flow.last_delivered == 10, "Al otro día el flujo de troncos entrega 10")
	_comprobar(_modelo.get_level(&"azul") == 2 and _modelo.get_production(&"azul").get(&"log", 0) == 20, "Azul sube a nivel 2 en un día: 20 troncos por día (nivel %d)" % _modelo.get_level(&"azul"))
	_comprobar(_modelo.get_level(&"sierras_bayas") == 2 and _modelo.get_production(&"sierras_bayas").get(&"limestone", 0) == 20, "Sierras Bayas nivel 2 en un día: 20 piedras por día")
	# 4. Olavarría recibe su piedra (los 20 del regalo de Sierras Bayas).
	_comprobar(_tablero.find_source(piedra_olav) == &"sierras_bayas", "Ahora la piedra de Olavarría sale de Sierras Bayas")
	_tablero.deliver(&"olavarria", &"limestone", 20)
	_comprobar(piedra_olav.is_completed(), "20 piedras en Olavarría: nace el flujo de piedra")
	_modelo.advance_day()
	_comprobar(_modelo.get_level(&"olavarria") == 2, "Olavarría sube a nivel 2 en un día (nivel %d)" % _modelo.get_level(&"olavarria"))
	var produce: Dictionary[StringName, int] = _modelo.get_production(&"olavarria")
	_comprobar(produce.get(&"cement", 0) == 15 and produce.get(&"teacher", 0) == 1, "Olavarría nivel 2: 15 cemento y 1 maestra por día")
	var piedra_olav2: Mission = _principal(&"olavarria", &"limestone")
	_comprobar(piedra_olav2 != null and piedra_olav2.flow_amount == 10 and _tablero.find_source(piedra_olav2) == &"sierras_bayas", "Olavarría nivel 2 pide 10 piedras más: a la cantera le quedan 10 libres")
	_tablero.deliver(&"olavarria", &"limestone", 20)
	_comprobar(piedra_olav2 != null and piedra_olav2.is_completed(), "20 piedras más: nace el segundo flujo de piedra")
	# 5. La maestra de Azul (secundaria de pasajeros).
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
	# 6. Azul pide piedra y cemento: solo el cemento tiene productor libre.
	var piedra_azul: Mission = _principal(&"azul", &"limestone")
	var cemento: Mission = _principal(&"azul", &"cement")
	_comprobar(piedra_azul != null and piedra_azul.flow_amount == 10 and _tablero.find_source(piedra_azul) == &"", "Azul pide 10 piedras y no alcanza la cantera")
	_comprobar(cemento != null and cemento.flow_amount == 5 and _tablero.find_source(cemento) == &"olavarria", "Azul pide 5 cemento de Olavarría")
	_tablero.deliver(&"azul", &"cement", 10)
	_comprobar(cemento != null and cemento.is_completed(), "10 cemento en Azul: nace el flujo de cemento")
	_modelo.advance_days(2)
	_comprobar(_modelo.get_level(&"olavarria") == 3, "Olavarría llega a nivel 3 en dos días (nivel %d)" % _modelo.get_level(&"olavarria"))
	var piedra_olav3: Mission = _principal(&"olavarria", &"limestone")
	_comprobar(piedra_olav3 != null and piedra_olav3.flow_amount == 10 and _tablero.find_source(piedra_olav3) == &"", "Olavarría nivel 3 pide 10 piedras más y no alcanza")
	# 7. La cantera vieja suma 20 y alcanza para los dos.
	var cantera: Mission = _tablero.get_mission(&"cantera_vieja")
	_comprobar(cantera != null and cantera.state == Mission.State.AVAILABLE, "La cantera vieja queda disponible con Sierras Bayas en nivel 2")
	_tablero.start(&"cantera_vieja")
	_comprobar(cantera.is_active(), "Con s_c cortado la cantera vieja sigue en curso")
	_abrir(&"s_c")
	_comprobar(cantera.is_completed() and _modelo.get_production(&"sierras_bayas").get(&"limestone", 0) == 40, "Despejado s_c: Sierras Bayas da 40 piedras por día")
	_comprobar(piedra_azul != null and _tablero.find_source(piedra_azul) == &"sierras_bayas" and piedra_olav3 != null and _tablero.find_source(piedra_olav3) == &"sierras_bayas", "Ahora la piedra alcanza para Azul y Olavarría")
	_tablero.deliver(&"azul", &"limestone", 20)
	_tablero.deliver(&"olavarria", &"limestone", 20)
	_comprobar(piedra_azul != null and piedra_azul.is_completed() and piedra_olav3 != null and piedra_olav3.is_completed(), "Entregadas: nacen los dos flujos de piedra")
	_modelo.advance_days(3)
	_comprobar(_modelo.get_level(&"azul") == 3, "Azul llega a nivel 3 (nivel %d)" % _modelo.get_level(&"azul"))
	_comprobar(_modelo.get_level(&"olavarria") == 4, "Olavarría llega a nivel 4 (nivel %d)" % _modelo.get_level(&"olavarria"))
	print("Flujos al final:")
	for flujo: ProductionFlow in _modelo.get_flows():
		print("  ", flujo.describe(), " · entregó ", flujo.last_delivered)


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


func _comprobar(ok: bool, texto: String) -> void:
	if ok:
		print("OK  ", texto)
	else:
		_fallos += 1
		push_error("FALLA  " + texto)
