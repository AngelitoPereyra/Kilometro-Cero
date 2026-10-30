extends Node3D
## Prueba de la tarea 62c.2 (D139): estaciones de producción como anexos. Una estación de carga que
## no está en ninguna línea troncal es anexo de la estación de una línea más cercana por vía (su
## cabecera); lo que sale o llega a un anexo va en dos trenes: el de ramal hasta la cabecera y la
## troncal (o el tren de su conexión) desde ahí. La economía no cambia (acopio invisible).
## Primero la lógica pura (AnnexRoutes) y después el Hito A: la Línea del Sud es Azul-Olavarría y
## Sierras Bayas es anexo de Olavarría. Toca la partida de GameState (la vacía al empezar).

const HITO_A: String = "res://scenes/hito_a/hito_a.tscn"

var _fallos: int = 0


func _ready() -> void:
	_probar_cabeceras()
	_probar_partir()
	await _probar_hito_a()
	if _fallos == 0:
		print("Anexos: todas las comprobaciones pasaron.")
	else:
		push_error("Anexos: fallaron %d comprobaciones." % _fallos)


func _probar_cabeceras() -> void:
	var carga: int = StationData.StationType.FREIGHT
	var tipos: Dictionary = {
		&"azul": StationData.StationType.TOWN, &"olavarria": StationData.StationType.CITY,
		&"sierras_bayas": carga, &"cantera_lejana": carga, &"maderera_en_linea": carga, &"aislada": carga,
	}
	var lineas: Array[Array] = [[&"azul", &"olavarria", &"maderera_en_linea"] as Array[StringName]]
	# Distancias por vía de mentira: Sierras Bayas está a 800 m de Olavarría y a 1800 de Azul.
	var largos: Dictionary = {
		"sierras_bayas>olavarria": 800.0, "sierras_bayas>azul": 1800.0, "sierras_bayas>maderera_en_linea": 2500.0,
		"cantera_lejana>olavarria": 3000.0, "cantera_lejana>azul": 1200.0, "cantera_lejana>maderera_en_linea": 4000.0,
	}
	var distancia := func(from: StringName, to: StringName) -> float: return float(largos.get("%s>%s" % [from, to], INF))
	var cabeceras: Dictionary[StringName, StringName] = AnnexRoutes.find_hubs(tipos, lineas, distancia)
	_comprobar(cabeceras.get(&"sierras_bayas", &"") == &"olavarria", "Sierras Bayas es anexo de Olavarría (la más cercana por vía)")
	_comprobar(cabeceras.get(&"cantera_lejana", &"") == &"azul", "Otra cantera es anexo de la que le queda más cerca (Azul)")
	_comprobar(not cabeceras.has(&"maderera_en_linea"), "Una estación de carga que está en la línea no es anexo")
	_comprobar(not cabeceras.has(&"aislada"), "Sin camino a ninguna línea no tiene cabecera")
	_comprobar(not cabeceras.has(&"azul") and not cabeceras.has(&"olavarria"), "Pueblos y ciudades nunca son anexos")
	_comprobar(AnnexRoutes.find_hubs(tipos, [] as Array[Array], distancia).is_empty(), "Sin líneas troncales no hay anexos")
	_comprobar(AnnexRoutes.annexes_of(&"olavarria", cabeceras) == ([&"sierras_bayas"] as Array[StringName]), "Los anexos de Olavarría")


func _probar_partir() -> void:
	var cabeceras: Dictionary[StringName, StringName] = {&"sierras_bayas": &"olavarria", &"cantera_lejana": &"azul", &"otra": &"olavarria"}
	_comprobar(AnnexRoutes.route_stops(&"sierras_bayas", &"olavarria", cabeceras) == ([&"sierras_bayas", &"olavarria"] as Array[StringName]), "Del anexo a su cabecera: un solo tramo")
	_comprobar(AnnexRoutes.route_stops(&"azul", &"sierras_bayas", cabeceras) == ([&"azul", &"olavarria", &"sierras_bayas"] as Array[StringName]), "De Azul a Sierras Bayas pasa por Olavarría")
	_comprobar(AnnexRoutes.route_stops(&"sierras_bayas", &"cantera_lejana", cabeceras) == ([&"sierras_bayas", &"olavarria", &"azul", &"cantera_lejana"] as Array[StringName]), "De un anexo a otro: por las dos cabeceras")
	_comprobar(AnnexRoutes.route_stops(&"sierras_bayas", &"otra", cabeceras) == ([&"sierras_bayas", &"olavarria", &"otra"] as Array[StringName]), "Dos anexos de la misma cabecera: por la cabecera una sola vez")
	_comprobar(AnnexRoutes.route_stops(&"azul", &"olavarria", cabeceras) == ([&"azul", &"olavarria"] as Array[StringName]), "Sin anexos, igual")

	var piedra := ProductionFlow.new(&"sierras_bayas", &"azul", &"limestone", 10)
	piedra.id = 7
	piedra.custom_name = "El Piedrero"
	var cemento := ProductionFlow.new(&"olavarria", &"azul", &"cement", 5)
	cemento.id = 8
	var pedazos: Array[ProductionFlow] = AnnexRoutes.split([piedra, cemento] as Array[ProductionFlow], cabeceras)
	_comprobar(pedazos.size() == 3, "La piedra a Azul se parte en dos y el cemento queda igual (%d pedazos)" % pedazos.size())
	if pedazos.size() == 3:
		_comprobar(pedazos[0].from_station == &"sierras_bayas" and pedazos[0].to_station == &"olavarria" and pedazos[1].from_station == &"olavarria" and pedazos[1].to_station == &"azul", "Ramal hasta Olavarría y troncal hasta Azul")
		_comprobar(pedazos[0].id == 7 and pedazos[1].id == 7 and pedazos[0].amount == 10 and pedazos[1].item_id == &"limestone" and pedazos[1].custom_name == "El Piedrero", "Los pedazos llevan el mismo flujo (id, carga, cantidad y nombre)")
		_comprobar(pedazos[2] == cemento, "El flujo que no toca anexos es el mismo objeto")
	_comprobar(piedra.to_station == &"azul", "El flujo de la economía no cambia (sigue de Sierras Bayas a Azul)")
	var texto: String = StationBoard.annex_line("Sierras Bayas", {&"log": 10} as Dictionary[StringName, int], {&"limestone": 20} as Dictionary[StringName, int], func(amounts: Dictionary[StringName, int]) -> String: return "%d %s" % [amounts.values()[0], amounts.keys()[0]])
	_comprobar(texto == "Anexo Sierras Bayas: pide 10 log · da 20 limestone", "El renglón del anexo en el tablero de la cabecera (%s)" % texto)


func _probar_hito_a() -> void:
	GameState.reset_production()
	var mapa := (load(HITO_A) as PackedScene).instantiate() as Node3D
	add_child(mapa)
	for _i: int in 12:
		await get_tree().process_frame
	var autos: AutoTrains = AutoTrains.find_in(get_tree())
	var modelo: ProductionModel = GameState.production
	var linea: Array[TrunkLine] = TrunkLine.find_all(get_tree())
	_comprobar(linea.size() == 1 and linea[0].get_station_ids() == ([&"azul", &"olavarria"] as Array[StringName]), "La Línea del Sud es Azul-Olavarría")
	if autos == null:
		_comprobar(false, "El Hito A tiene trenes automáticos")
		return
	var troncos: ProductionFlow = modelo.add_flow(&"azul", &"sierras_bayas", &"log", 10)
	var piedra: ProductionFlow = modelo.add_flow(&"sierras_bayas", &"olavarria", &"limestone", 20)
	var cal: ProductionFlow = modelo.add_flow(&"olavarria", &"azul", &"limestone", 5)
	autos.sync_flows()
	_comprobar(autos.get_hub(&"sierras_bayas") == &"olavarria" and autos.get_hub(&"azul") == &"" and autos.get_annexes(&"olavarria") == ([&"sierras_bayas"] as Array[StringName]), "En el Hito A, Sierras Bayas es anexo de Olavarría")
	var ramales: Array[AutoTrainRun] = []
	var en_troncal: Array[int] = []
	for run: AutoTrainRun in autos.get_runs():
		if run.is_trunk():
			en_troncal.append_array(run.flow_ids)
		else:
			ramales.append(run)
	var ramal: AutoTrainRun = null
	var directo: bool = false
	for run: AutoTrainRun in ramales:
		var clave: String = AutoTrains.connection_key(run.home, run.away)
		if clave == AutoTrains.connection_key(&"olavarria", &"sierras_bayas"):
			ramal = run
		elif clave == AutoTrains.connection_key(&"azul", &"sierras_bayas"):
			directo = true
	_comprobar(ramal != null, "Hay un tren de ramal Olavarría-Sierras Bayas")
	_comprobar(not directo, "Ningún tren va directo de Azul a Sierras Bayas")
	_comprobar(ramal != null and ramal.flow_ids.has(troncos.id) and ramal.flow_ids.has(piedra.id), "El tren de ramal lleva la piedra y los troncos")
	_comprobar(en_troncal.has(troncos.id) and en_troncal.has(cal.id) and not en_troncal.has(piedra.id), "La troncal lleva los troncos de Azul hasta Olavarría y la cal, pero no la piedra del ramal")
	_comprobar(troncos.to_station == &"sierras_bayas" and troncos.from_station == &"azul" and modelo.get_flows().has(troncos), "Los flujos de la economía siguen como estaban")
	var olavarria: String = _tablero_de(mapa.get_node(^"Olavarria"))
	var sierras: String = _tablero_de(mapa.get_node(^"SierrasBayas"))
	_comprobar(olavarria.contains("Anexo Sierras Bayas:"), "El tablero de Olavarría muestra lo que pide y da su anexo")
	_comprobar(sierras.contains("Anexo de Olavarría"), "El tablero de Sierras Bayas dice de quién es anexo")
	mapa.queue_free()


func _tablero_de(estacion: Node) -> String:
	for hijo: Node in estacion.find_children("*", "", true, false):
		if hijo is StationBoard:
			return (hijo as StationBoard).build_text()
	return ""


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
