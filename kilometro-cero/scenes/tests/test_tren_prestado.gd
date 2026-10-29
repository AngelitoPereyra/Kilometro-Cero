extends Node
## Prueba de la tarea 62b.3 (D127, D128): principales con aviso y tren prestado, en lógica, con los
## datos del Hito A y un tablero propio (no toca la partida de GameState). Quien da cada principal
## (Don Ernesto, Doña Clara, Ramírez) pide que le avisen cuando el camino está habilitado; con un
## tramo que abrió el jugador sin estrenar el aviso arranca el viaje inaugural (tren prestado) y si
## no, el Ferrocarril manda la carga solo. También: tramos abiertos en RailNetwork, los vagones del
## tren prestado (BorrowedTrains.plan_wagons) y el humo (SmokePuff).
## Red: Azul --(o_a)-- Olavarría --(o_s)-- Sierras Bayas. Los dos tramos empiezan tapados.
## El tren prestado de verdad (aparecer, manejar, entregar y desaparecer con humo) se prueba
## jugando el Hito A.

const STATION_FILES: Array[String] = ["olavarria", "azul", "sierras_bayas"]
const SEGMENTS: Dictionary = {
	&"o_a": [&"olavarria", &"azul"],
	&"o_s": [&"olavarria", &"sierras_bayas"],
}

var _fallos: int = 0
var _cortados: Dictionary[StringName, bool] = {&"o_a": true, &"o_s": true}
# Los que abrió el jugador (como RailNetwork.was_opened).
var _abiertos: Dictionary[StringName, bool] = {}
var _modelo: ProductionModel
var _tablero: MissionBoard
var _trafico: PassengerTraffic
var _inaugurales: Array[StringName] = []


func _ready() -> void:
	_probar_red()
	_probar_vagones()
	_armar()
	_probar_aviso_y_viajes()
	_probar_sin_quien_la_de()
	_probar_guardado()
	await _probar_humo()
	if _fallos == 0:
		print("Tren prestado: todas las comprobaciones pasaron.")
	else:
		push_error("Tren prestado: fallaron %d comprobaciones." % _fallos)


# RailNetwork recuerda los tramos que estuvieron cortados y se abrieron.
func _probar_red() -> void:
	var red := RailNetwork.new()
	var curva := Path3D.new()
	var tramo := TrackSegment.new()
	tramo.segment_id = &"a_b"
	tramo.from_station = &"a"
	tramo.to_station = &"b"
	curva.add_child(tramo)
	red.add_track(tramo)
	_comprobar(not red.was_opened(&"a_b"), "Un tramo que nunca se cortó no lo abrió el jugador")
	var arbol := Node.new()
	red.add_blocker(&"a_b", arbol)
	_comprobar(red.is_cut(&"a_b") and not red.was_opened(&"a_b"), "Tapado: cortado y todavía sin abrir")
	red.remove_blocker(&"a_b", arbol)
	_comprobar(not red.is_cut(&"a_b") and red.was_opened(&"a_b"), "Despejado: el jugador lo abrió")
	arbol.free()
	curva.free()
	red.free()


# Los vagones del tren prestado según la carga (lógica pura).
func _probar_vagones() -> void:
	var tipo := func(item_id: StringName) -> StringName: return AutoTrains.KIND_COACH if item_id == &"settlers" else AutoTrains.KIND_FLATCAR
	var lugares := func(kind: StringName) -> int: return 10 if kind == AutoTrains.KIND_COACH else 20
	var troncos: Array[Dictionary] = BorrowedTrains.plan_wagons({&"log": 20}, tipo, lugares)
	_comprobar(troncos.size() == 1 and troncos[0]["kind"] == AutoTrains.KIND_FLATCAR and int(troncos[0]["amount"]) == 20, "20 troncos: una plataforma")
	var piedra: Array[Dictionary] = BorrowedTrains.plan_wagons({&"limestone": 50}, tipo, lugares)
	_comprobar(piedra.size() == 3 and int(piedra[2]["amount"]) == 10, "50 piedras: tres plataformas (20, 20 y 10)")
	var colonos: Array[Dictionary] = BorrowedTrains.plan_wagons({&"settlers": 10}, tipo, lugares)
	_comprobar(colonos.size() == 1 and colonos[0]["kind"] == AutoTrains.KIND_COACH, "10 colonos: un coche")


func _armar() -> void:
	_modelo = ProductionModel.new()
	_modelo.connection_check = _conectadas
	for oficio: OccupationData in OccupationData.load_all():
		_modelo.add_occupation(oficio)
	_tablero = MissionBoard.new(_modelo)
	_tablero.route_finder = _camino
	_tablero.segment_check = func(segment_id: StringName) -> bool: return not _cortados.get(segment_id, false)
	_tablero.opened_check = func(segment_id: StringName) -> bool: return _abiertos.has(segment_id)
	_tablero.flows_start_next_day = true
	_tablero.inaugural_started.connect(func(mission: Mission) -> void: _inaugurales.append(mission.id))
	var economia := Economy.new(_modelo)
	_trafico = PassengerTraffic.new(_tablero, economia)
	for nombre: String in STATION_FILES:
		var datos := load("res://data/stations/%s.tres" % nombre) as StationData
		_modelo.add_station(datos, 1)
		economia.add_station(datos)
	_tablero.register_main_giver(&"olavarria", "Don Ernesto")
	_tablero.register_main_giver(&"azul", "Doña Clara")
	_tablero.register_main_giver(&"sierras_bayas", "Ramírez")
	_tablero.refresh()


func _probar_aviso_y_viajes() -> void:
	var colonos: Mission = _principal(&"azul", &"settlers")
	var troncos: Mission = _principal(&"sierras_bayas", &"log")
	_comprobar(colonos != null and troncos != null, "Azul pide colonos y Sierras Bayas troncos")
	if colonos == null or troncos == null:
		return
	_comprobar(_tablero.needs_report(colonos) and _tablero.get_main_giver(&"azul") == "Doña Clara", "Las principales de Azul las da Doña Clara")
	# 1. Con la vía tapada: abrir el camino; el jugador no puede llevar la carga.
	_comprobar(_tablero.get_stage(colonos) == MissionBoard.Stage.OPEN_ROUTE and not _tablero.can_report(colonos), "Con o_a tapado: abrir el camino (todavía no se avisa)")
	var pasos: PackedStringArray = _tablero.get_pending_steps(colonos)
	_comprobar(pasos.size() == 2 and pasos[0].begins_with("Habilitar el tramo o_a") and pasos[1].contains("Doña Clara"), "Pasos: habilitar o_a y después avisarle a Doña Clara (%s)" % [pasos])
	_comprobar(not _tablero.accepts_deliveries(colonos) and _tablero.get_passenger_needs(colonos).is_empty() and not _tablero.is_reserved_passenger(&"settlers"), "Los colonos no los lleva el jugador: no están reservados ni suben gratis")
	_comprobar(_tablero.plan_delivery(&"sierras_bayas", {&"log": 20} as Dictionary[StringName, int]).is_empty() and _tablero.deliver(&"sierras_bayas", &"log", 20) == 0, "Sierras Bayas no acepta troncos del jugador para su principal")
	# 2. Despejado: avisarle.
	_abrir(&"o_a")
	_abrir(&"o_s")
	_comprobar(_tablero.get_stage(colonos) == MissionBoard.Stage.REPORT and _tablero.can_report(colonos), "Despejado o_a: hay que avisarle a Doña Clara")
	pasos = _tablero.get_pending_steps(colonos)
	_comprobar(pasos.size() == 1 and pasos[0].begins_with("Avisarle a Doña Clara en Azul"), "Paso: avisarle (%s)" % [pasos])
	_comprobar(colonos.is_active(), "Sin aviso, la principal no se cumple sola")
	# 3. Aviso con o_a sin estrenar: viaje inaugural desde Olavarría.
	_comprobar(_tablero.get_unchristened_segments(&"olavarria", &"azul") == ([&"o_a"] as Array[StringName]), "o_a lo abrió el jugador y nadie lo estrenó")
	_comprobar(_tablero.report(colonos.id), "Se le avisa a Doña Clara")
	_comprobar(colonos.reported and colonos.inaugural and colonos.source_id == &"olavarria" and _inaugurales.has(colonos.id), "Empieza el viaje inaugural: tren prestado desde Olavarría")
	_comprobar(_tablero.get_stage(colonos) == MissionBoard.Stage.INAUGURAL and not _tablero.report(colonos.id), "En viaje inaugural; no se avisa dos veces")
	pasos = _tablero.get_pending_steps(colonos)
	_comprobar(pasos.size() == 2 and pasos[0].begins_with("Llevar el tren prestado de Olavarría a Azul") and pasos[1].begins_with("Abrir las puertas del coche en Azul"), "Pasos: llevar el tren prestado y abrir las puertas (%s)" % [pasos])
	_comprobar(_tablero.is_reserved_passenger(&"settlers") and _tablero.get_passenger_needs(colonos).get(&"settlers", 0) == 10, "Los 10 colonos del tren prestado van reservados")
	# 4. Llegan: al abrir las puertas en Azul bajan y nace el flujo; o_a queda estrenado.
	var plan: Dictionary = _trafico.plan_exchange(&"azul", {&"settlers": 10} as Dictionary[StringName, int], 10)
	_trafico.apply_exchange(&"azul", plan)
	_comprobar(colonos.is_completed() and colonos.flow != null and colonos.flow.pending and not colonos.inaugural, "Bajaron los colonos: principal cumplida y flujo desde mañana")
	_comprobar(_tablero.is_christened(&"o_a") and not _tablero.is_christened(&"o_s"), "o_a quedó estrenado; o_s todavía no")
	# 5. Troncos para Sierras Bayas: o_s sin estrenar, otro viaje inaugural desde Azul.
	_comprobar(_tablero.can_report(troncos) and _tablero.report(troncos.id) and troncos.inaugural and troncos.source_id == &"azul", "Aviso a Ramírez: tren prestado de troncos desde Azul (o_s sin estrenar)")
	_comprobar(_tablero.plan_delivery(&"sierras_bayas", {&"log": 30} as Dictionary[StringName, int]).get(&"log", 0) == 20, "En el viaje inaugural el tablero acepta los 20 troncos")
	_comprobar(_tablero.deliver(&"sierras_bayas", &"log", 20) == 20 and troncos.is_completed() and _tablero.is_christened(&"o_s"), "Entregados en el tablero: cumplida y o_s estrenado")
	_modelo.advance_day()
	_comprobar(_modelo.get_production(&"sierras_bayas").get(&"limestone", 0) == 20, "Al otro día los canteros pican 20 piedras")
	# 6. Piedra para Olavarría: el camino ya está estrenado, el Ferrocarril la manda solo.
	var piedra: Mission = _principal(&"olavarria", &"limestone")
	_comprobar(piedra != null and _tablero.can_report(piedra), "Hay que avisarle a Don Ernesto de la piedra")
	if piedra != null:
		var antes: int = _inaugurales.size()
		_comprobar(_tablero.report(piedra.id) and not piedra.inaugural and piedra.is_completed() and _inaugurales.size() == antes, "Aviso a Don Ernesto: sin viaje inaugural, la principal se cumple sola")
		_comprobar(piedra.flow != null and piedra.flow.from_station == &"sierras_bayas" and piedra.flow.pending, "Nace el flujo de piedra desde Sierras Bayas, desde mañana")


# Una estación sin quien dé sus principales sigue como antes: el jugador lleva la primera carga.
func _probar_sin_quien_la_de() -> void:
	var modelo := ProductionModel.new()
	var tablero := MissionBoard.new(modelo)
	var datos := load("res://data/stations/azul.tres") as StationData
	modelo.add_station(datos, 2)
	tablero.refresh()
	var alguna: Mission = null
	for mision: Mission in tablero.get_main_missions(&"azul"):
		alguna = mision
	_comprobar(alguna != null and not tablero.needs_report(alguna) and tablero.accepts_deliveries(alguna) and tablero.get_stage(alguna) == MissionBoard.Stage.OPEN_ROUTE, "Sin quien la dé, la principal acepta entregas como antes")


func _probar_guardado() -> void:
	var colonos: Mission = null
	for mision: Mission in _tablero.get_missions():
		if mision.main and mision.item_id == &"settlers":
			colonos = mision
	var copia: Mission = Mission.main_from_dict(colonos.to_dict()) if colonos != null else null
	_comprobar(copia != null and copia.reported and copia.source_id == &"olavarria", "La principal guarda el aviso y su productor")
	var otro := MissionBoard.new(ProductionModel.new())
	otro.load_dict(_tablero.to_dict())
	_comprobar(otro.is_christened(&"o_a") and otro.is_christened(&"o_s"), "El tablero guarda los tramos estrenados")


func _probar_humo() -> void:
	var sonido: AudioStreamWAV = SmokePuff.make_sound()
	_comprobar(sonido != null and sonido.data.size() == int(SmokePuff.SOUND_RATE * SmokePuff.SOUND_SECONDS) * 2 and SmokePuff.make_sound() == sonido, "El puf: ruido de 0,35 s armado una sola vez")
	var humo: SmokePuff = SmokePuff.spawn(self, Vector3(1.0, 2.0, 3.0))
	_comprobar(humo != null and humo.get_node_or_null(^"Humo") is CPUParticles3D and humo.get_node_or_null(^"Puf") is AudioStreamPlayer3D, "La nube tiene partículas y sonido")
	_comprobar(humo != null and humo.global_position.is_equal_approx(Vector3(1.0, 2.0, 3.0)), "La nube queda donde se la pidió")
	await get_tree().create_timer(SmokePuff.LIFETIME + 0.5).timeout
	_comprobar(not is_instance_valid(humo), "La nube se borra sola")


func _abrir(segment_id: StringName) -> void:
	_cortados[segment_id] = false
	_abiertos[segment_id] = true
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
