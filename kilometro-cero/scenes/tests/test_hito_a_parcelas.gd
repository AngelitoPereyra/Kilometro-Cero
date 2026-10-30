extends Node
## Prueba automática de la 62b.5 sobre el mapa del Hito A, para no tener que jugarlo entero: arma
## hito_a.tscn de verdad (con GameState) y mira los lotes, las parcelas que aparecen al empezar y
## las que brotan cuando Azul sube al nivel 2, la entrada lenta a Olavarría, las marchas en km/h y
## que el tren solo y lejos del jugador frene. Al terminar deja el Hito A abierto para mirar
## (la cámara del jugador está en Olavarría; las parcelas de Azul quedan brotadas).

const HITO_A: String = "res://scenes/hito_a/hito_a.tscn"

var _fallos: int = 0
var _mapa: Node3D
var _lotes: TrackLots


func _ready() -> void:
	GameState.reset_production()
	_mapa = (load(HITO_A) as PackedScene).instantiate() as Node3D
	add_child(_mapa)
	for i: int in 10:
		await get_tree().process_frame
	_lotes = TrackLots.find_in(get_tree())
	_comprobar(_lotes != null, "El Hito A tiene su nodo Lotes")
	if _lotes != null:
		_probar_inicio()
		_probar_azul()
	_probar_marchas_y_zona()
	await _probar_tren_que_se_escapa()
	if _fallos == 0:
		print("Hito A con parcelas: todas las comprobaciones pasaron.")
	else:
		push_error("Hito A con parcelas: fallaron %d comprobaciones." % _fallos)


# Al empezar: los caleros de Olavarría en la zona industrial, los canteros de Sierras Bayas en el
# campo, los galpones ferroviarios fijos y Azul (nivel 1, sin familias) con sus 12 lotes libres.
func _probar_inicio() -> void:
	var caleros: Array[TrackLot] = _ocupados(&"olavarria")
	_comprobar(caleros.size() == 4, "Olavarría: 2 parcelas de caleros y 2 galpones ferroviarios (%d)" % caleros.size())
	var con_familia: int = 0
	for lote: TrackLot in caleros:
		if lote.fixed_scene != null:
			continue
		con_familia += 1
		_comprobar(lote.get_occupation_id() == &"caleros" and lote.ring == TrackLot.Ring.INDUSTRY, "%s: caleros en la zona industrial" % lote.name)
		_comprobar(lote.get_parcel() != null and lote.get_parcel().scale.is_equal_approx(Vector3.ONE), "%s: aparece quieta (sin brotar)" % lote.name)
	_comprobar(con_familia == 2, "Las dos familias de caleros tienen parcela")
	var canteros: Array[TrackLot] = _ocupados(&"sierras_bayas")
	_comprobar(canteros.size() == 2, "Sierras Bayas: 2 frentes de cantera")
	for lote: TrackLot in canteros:
		_comprobar(lote.get_occupation_id() == &"canteros" and lote.ring == TrackLot.Ring.FIELD, "%s: canteros en una hectárea" % lote.name)
	_comprobar(_ocupados(&"azul").is_empty() and _lotes.get_free_lots(&"azul").size() == 12, "Azul arranca sin parcelas y con sus 12 lotes libres")
	for station_id: StringName in [&"olavarria", &"sierras_bayas", &"azul"]:
		_comprobar(_lotes.get_pending(station_id) == 0, "%s: ninguna familia esperando lote" % station_id)


# Azul sube al nivel 2: brotan hacheros y puesteros en las hectáreas de la entrada (no las de
# atrás del pueblo).
func _probar_azul() -> void:
	GameState.production.set_level(&"azul", 2)
	var nuevos: Array[TrackLot] = _ocupados(&"azul")
	var oficios: Array[StringName] = []
	for lote: TrackLot in nuevos:
		oficios.append(lote.get_occupation_id())
	_comprobar(nuevos.size() == 2 and oficios.has(&"hacheros") and oficios.has(&"puesteros"), "Azul en el nivel 2: monte talado y corral (%s)" % [oficios])
	var azul := Station.find(get_tree(), &"azul")
	for lote: TrackLot in nuevos:
		_comprobar(lote.global_position.z < azul.global_position.z, "%s está en la entrada, antes de la estación" % lote.name)
		var piezas: Array[Node3D] = GrowthCelebration.get_pieces(lote.get_parcel())
		_comprobar(not piezas.is_empty() and piezas[0].scale.x < 0.5 and lote.get_message() != null, "%s brota con su cartel" % lote.name)


func _probar_marchas_y_zona() -> void:
	var loco := _mapa.get_node_or_null(^"OlavarriaSierrasBayas/Locomotive") as Vehicle
	if loco == null:
		loco = _buscar_locomotora()
	_comprobar(loco != null, "Está la locomotora del jugador")
	if loco == null:
		return
	var cab := _cabina(loco)
	_comprobar(cab != null and loco.absolute_throttle, "La cabina pide velocidades fijas")
	if cab == null:
		return
	var esperadas: Array[int] = [20, 43, 60, 90]
	for muesca: int in range(1, 5):
		cab.set_notch(muesca)
		var kmh: int = roundi(loco.throttle * loco.data.max_speed * 3.6)
		_comprobar(kmh == esperadas[muesca - 1], "Adelante %d: %d km/h (pide %d)" % [muesca, esperadas[muesca - 1], kmh])
	cab.set_notch(0)
	var zona: SpeedZone = SpeedZone.find_for(loco.get_train())
	_comprobar(zona != null and is_equal_approx(loco.get_max_speed(), zona.max_speed), "Al empezar el tren está en la zona de precaución de Olavarría: tope 15 km/h")


# El jugador se va a más de 100 m con el tren andando: punto muerto y freno; al volver a la
# cabina el freno se suelta.
func _probar_tren_que_se_escapa() -> void:
	var loco := _buscar_locomotora()
	var cab := _cabina(loco)
	var jugador := _mapa.get_node_or_null(^"Player") as Player
	_comprobar(jugador != null, "Está el jugador")
	if cab == null or jugador == null:
		return
	cab.set_notch(3)
	loco.get_head().speed = 3.0
	_comprobar(not cab.check_runaway(jugador), "Con el jugador cerca no frena")
	jugador.global_position = loco.global_position + Vector3(150, 2, 0)
	_comprobar(cab.check_runaway(jugador), "Con el jugador a 150 m el tren frena solo")
	await get_tree().physics_frame
	_comprobar(cab.notch == 0 and cab.braking and loco.get_head().brake > 0.0 and cab.is_auto_stopped(), "Quedó en punto muerto y frenando")
	_comprobar(not cab.check_runaway(jugador), "No vuelve a frenar dos veces")
	cab.occupy(jugador)
	await get_tree().physics_frame
	_comprobar(not cab.is_auto_stopped() and not cab.braking, "Al entrar a la cabina el freno se suelta")
	cab.release()
	# Para mirar al terminar: de vuelta en el andén de Olavarría, quieto (antes quedaba a 150 m).
	var olavarria := Station.find(get_tree(), &"olavarria")
	if olavarria != null:
		jugador.global_position = olavarria.global_position + Vector3(-6.0, 1.0, -12.0)
		jugador.velocity = Vector3.ZERO


func _ocupados(station_id: StringName) -> Array[TrackLot]:
	var lotes: Array[TrackLot] = []
	for lote: TrackLot in _lotes.get_lots(station_id):
		if not lote.is_free():
			lotes.append(lote)
	return lotes


func _buscar_locomotora() -> Vehicle:
	var prestados := _mapa.get_node_or_null(^"TrenesPrestados") as BorrowedTrains
	return prestados.player_train if prestados != null else null


func _cabina(loco: Vehicle) -> Cab:
	if loco == null:
		return null
	for nodo: Node in loco.find_children("*", "Cab", true, false):
		return nodo as Cab
	return null


func _comprobar(condicion: bool, texto: String) -> void:
	if condicion:
		print("  OK  ", texto)
	else:
		_fallos += 1
		push_error("  FALLA  " + texto)
