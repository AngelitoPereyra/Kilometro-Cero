extends Node3D
## Prueba de la tarea 62b.5 (D131): lotes junto a la vía, parcelas de oficio y zona de precaución.
## Cada familia hace brotar la parcela de su oficio (OccupationData.landscape_scene) en el lote libre
## más cercano a su estación (TrackLots, TrackLot): los procesados prefieren la zona industrial y la
## comida y la materia prima el campo (hectáreas); el anillo del pueblo va segundo para todos. Las familias del principio aparecen quietas; las que llegan jugando, brotando. La zona de
## precaución (SpeedZone) baja el tope del tren del jugador y no el de los automáticos.
## Usa un modelo propio (no toca la partida de GameState). Al final deja la escena armada para mirar:
## los lotes y las seis parcelas a la vista.

const OFICIOS: Dictionary[StringName, String] = {
	&"hacheros": "monte_talado", &"puesteros": "corral", &"canteros": "frente_cantera",
	&"caleros": "horno_cal", &"tamberos": "tambo", &"curtidores": "piletones",
}
const HITO_A: String = "res://scenes/hito_a/hito_a.tscn"

var _fallos: int = 0
var _modelo: ProductionModel
var _lotes: TrackLots
var _brotes: Array[String] = []
var _posiciones: Dictionary[StringName, Vector3] = {
	&"azul": Vector3(0, 0, 0), &"olavarria": Vector3(200, 0, 0), &"sierras_bayas": Vector3(-200, 0, 0),
}


func _ready() -> void:
	_probar_datos()
	_probar_eleccion()
	await _probar_lotes()
	await _probar_zona()
	_probar_hito_a()
	_armar_vista()
	if _fallos == 0:
		print("Parcelas: todas las comprobaciones pasaron.")
	else:
		push_error("Parcelas: fallaron %d comprobaciones." % _fallos)


# Los seis oficios tienen su parcela, de varias piezas que brotan.
func _probar_datos() -> void:
	for oficio: OccupationData in OccupationData.load_all():
		var escena: String = OFICIOS.get(oficio.id, "")
		_comprobar(oficio.landscape_scene != null and oficio.landscape_scene.resource_path.ends_with(escena + ".tscn"), "%s tiene su parcela (%s)" % [oficio.id, escena])
		if oficio.landscape_scene == null:
			continue
		var parcela := oficio.landscape_scene.instantiate() as Node3D
		_comprobar(parcela != null and GrowthCelebration.get_pieces(parcela).size() >= 4, "La parcela de los %s brota en varias piezas" % oficio.display_name)
		if oficio.id == &"caleros":
			_comprobar(parcela.get_node_or_null("Horno1/Humo") is CPUParticles3D, "El horno de cal echa humo blanco")
		parcela.free()


# Lógica pura de TrackLots.pick_lot (los lotes tienen que estar en el árbol por la posición).
func _probar_eleccion() -> void:
	var cerca := _lote(&"x", Vector3(10, 0, 0), TrackLot.Ring.INDUSTRY)
	var lejos := _lote(&"x", Vector3(30, 0, 0), TrackLot.Ring.FIELD)
	var medio := _lote(&"x", Vector3(20, 0, 0), TrackLot.Ring.FIELD)
	var pueblo := _lote(&"x", Vector3(5, 0, 0), TrackLot.Ring.TOWN)
	var lotes: Array[TrackLot] = [cerca, lejos, medio]
	_comprobar(TrackLots.pick_lot(lotes, Vector3.ZERO, true) == cerca, "Un procesado elige el lote de la zona industrial")
	_comprobar(TrackLots.pick_lot(lotes, Vector3.ZERO, false) == medio, "La materia prima elige el más cercano de los de afuera")
	_comprobar(TrackLots.pick_lot(lotes, null, false) == lejos, "Sin la posición de la estación, el primero de los que prefiere")
	var sin_campo: Array[TrackLot] = [cerca, pueblo]
	_comprobar(TrackLots.pick_lot(sin_campo, Vector3.ZERO, false) == pueblo, "Sin campo libre, la materia prima va al anillo del pueblo antes que a la industria")
	var sin_industria: Array[TrackLot] = [lejos, pueblo]
	_comprobar(TrackLots.pick_lot(sin_industria, Vector3.ZERO, true) == pueblo, "Sin zona industrial libre, el procesado va al anillo del pueblo")
	var solo_industria: Array[TrackLot] = [cerca]
	_comprobar(TrackLots.pick_lot(solo_industria, Vector3.ZERO, false) == cerca, "Si no queda de los que prefiere, cualquiera")
	_comprobar(lejos.get_size() == Vector2(100, 100) and cerca.get_size() == Vector2(50, 50) and pueblo.get_size() == Vector2(16, 12), "Medidas: hectárea en el campo, 50 x 50 en la industria, 16 x 12 en el pueblo")
	_comprobar(TrackLots.pick_lot([] as Array[TrackLot], Vector3.ZERO, false) == null, "Sin lotes, ninguno")
	var fijo := TrackLot.new()
	fijo.fixed_scene = load("res://scenes/parcels/galpon_ferroviario.tscn") as PackedScene
	add_child(fijo)
	_comprobar(not fijo.is_free() and fijo.get_parcel() != null and TrackLots.pick_lot([fijo] as Array[TrackLot], null, true) == null, "Un lote con el galpón ferroviario fijo nunca recibe familias")
	fijo.free()
	for lote: TrackLot in lotes:
		lote.free()
	pueblo.free()


func _probar_lotes() -> void:
	_modelo = ProductionModel.new()
	for oficio: OccupationData in OccupationData.load_all():
		_modelo.add_occupation(oficio)
	_modelo.add_station(load("res://data/stations/azul.tres") as StationData, 1)
	_modelo.add_station(load("res://data/stations/olavarria.tres") as StationData, 1)
	_modelo.add_station(load("res://data/stations/sierras_bayas.tres") as StationData, 1)
	_comprobar(_modelo.get_family_count(&"azul") == 0 and _modelo.get_family_count(&"olavarria") == 2 and _modelo.get_family_count(&"sierras_bayas") == 2, "Al empezar: Azul sin familias, Olavarría 2 de caleros, Sierras Bayas 2 de canteros")
	# Azul: tres lotes de campo a 10, 20 y 30 m. Olavarría: dos de zona industrial y uno de campo.
	# Sierras Bayas: uno solo (una familia queda esperando).
	var campo: TrackLot.Ring = TrackLot.Ring.FIELD
	var azul: Array[TrackLot] = [_lote(&"azul", Vector3(20, 0, 20), campo), _lote(&"azul", Vector3(0, 0, 10), campo), _lote(&"azul", Vector3(-30, 0, 0), campo)]
	var pueblo1 := _lote(&"olavarria", Vector3(210, 0, 0), TrackLot.Ring.INDUSTRY)
	var pueblo2 := _lote(&"olavarria", Vector3(190, 0, 5), TrackLot.Ring.INDUSTRY)
	var afuera := _lote(&"olavarria", Vector3(180, 0, 0), campo)
	var sierras := _lote(&"sierras_bayas", Vector3(-210, 0, 0), campo)
	_lotes = TrackLots.new()
	_lotes.model = _modelo
	_lotes.station_position = func(station_id: StringName) -> Variant: return _posiciones.get(station_id)
	_lotes.parcel_placed.connect(func(lot: TrackLot, occupation: OccupationData, animated: bool) -> void: _brotes.append("%s %s %s" % [lot.station_id, occupation.id, animated]))
	add_child(_lotes)
	await get_tree().process_frame
	_comprobar(not pueblo1.is_free() and not pueblo2.is_free() and afuera.is_free(), "Los caleros (procesado) ocupan los dos lotes de la zona industrial de Olavarría")
	_comprobar(pueblo1.get_occupation_id() == &"caleros" and pueblo1.get_parcel() != null and pueblo1.get_parcel().scale.is_equal_approx(Vector3.ONE), "Las parcelas del principio aparecen quietas (sin brotar)")
	_comprobar(pueblo1.get_message() == null, "Al empezar no flota ningún cartel")
	_comprobar(sierras.get_occupation_id() == &"canteros" and _lotes.get_pending(&"sierras_bayas") == 1, "Sierras Bayas: un frente de cantera y una familia esperando lote")
	_comprobar(_brotes.size() == 3 and not _brotes.has("olavarria caleros true"), "Avisó las 3 parcelas del principio, sin animar (%s)" % [_brotes])
	_comprobar(_lotes.get_free_lots(&"azul").size() == 3, "Azul todavía tiene sus 3 lotes libres")
	# Azul sube al nivel 2: llegan hacheros y puesteros, a los dos lotes más cercanos.
	_brotes.clear()
	_modelo.set_level(&"azul", 2)
	_comprobar(_brotes.size() == 2 and _brotes.has("azul hacheros true") and _brotes.has("azul puesteros true"), "Azul en el nivel 2: brotan hacheros y puesteros (%s)" % [_brotes])
	_comprobar(not azul[1].is_free() and not azul[0].is_free() and azul[2].is_free(), "Ocupan los dos lotes más cercanos a Azul")
	var primero: TrackLot = azul[1]
	_comprobar(primero.get_occupation_id() == _modelo.get_families(&"azul")[0], "El más cercano es de la primera familia que llegó")
	var piezas: Array[Node3D] = GrowthCelebration.get_pieces(primero.get_parcel())
	_comprobar(not piezas.is_empty() and piezas[0].scale.x < 0.5, "Jugando, las piezas de la parcela brotan de chiquitas")
	_comprobar(primero.get_message() != null and primero.get_message().text.begins_with("¡Llegaron los "), "Flota el cartel \"¡Llegaron los ...!\"")
	_comprobar(primero.describe() == "Lote de azul (campo): %s" % primero.get_occupation().display_name and azul[2].describe() == "Lote de azul (campo, libre)", "describe() dice el lote, su anillo y su oficio")
	# Olavarría: los curtidores (procesado) ya no tienen lote en la zona industrial y van al campo.
	_comprobar(_modelo.add_family(&"olavarria", &"curtidores"), "Llega una familia de curtidores a Olavarría")
	_comprobar(afuera.get_occupation_id() == &"curtidores", "Sin lote industrial libre, los curtidores van al de campo")
	# Azul: los tamberos al último lote; otra familia más queda esperando.
	_comprobar(_modelo.add_family(&"azul", &"tamberos") and azul[2].get_occupation_id() == &"tamberos", "Los tamberos ocupan el último lote de Azul")
	_comprobar(_modelo.add_family(&"azul", &"hacheros") and _lotes.get_pending(&"azul") == 1, "Sin lotes libres la familia queda esperando")
	# Un lote nuevo en Sierras Bayas: la familia que esperaba brota.
	var nuevo := _lote(&"sierras_bayas", Vector3(-220, 0, 0), campo)
	_comprobar(_lotes.sync_station(&"sierras_bayas") == 1 and nuevo.get_occupation_id() == &"canteros" and _lotes.get_pending(&"sierras_bayas") == 0, "Con un lote nuevo brota la familia que esperaba")
	_comprobar(nuevo.place(_modelo.get_occupation(&"canteros")) == null, "Un lote ocupado no acepta otra parcela")
	_comprobar(_lotes.sync_station(&"sierras_bayas") == 0, "Volver a sincronizar no repite parcelas")


func _probar_zona() -> void:
	var zonas_antes: int = SpeedZone.get_zones().size()
	var zona := SpeedZone.new()
	zona.length = 50.0
	zona.width = 10.0
	add_child(zona)
	_comprobar(SpeedZone.get_zones().has(zona) and SpeedZone.has_zones(), "La zona se registra al entrar al árbol")
	_comprobar(zona.get_kmh() == 15 and zona.sign_text() == "PRECAUCIÓN\n15 km/h", "El cartel dice PRECAUCIÓN 15 km/h")
	_comprobar(SpeedZone.contains_local(Vector3(0, 0, -10), 50.0, 10.0) and SpeedZone.contains_local(Vector3(4, 1, -50), 50.0, 10.0), "Adentro: entre el cartel y 50 m hacia la estación")
	_comprobar(not SpeedZone.contains_local(Vector3(0, 0, 5), 50.0, 10.0) and not SpeedZone.contains_local(Vector3(0, 0, -51), 50.0, 10.0) and not SpeedZone.contains_local(Vector3(6, 0, -10), 50.0, 10.0), "Afuera: antes del cartel, pasada la zona o al costado")
	# Una vía recta de z -100 a 100 que pasa por la zona (z de -50 a 0).
	var via := Path3D.new()
	via.curve = Curve3D.new()
	via.curve.add_point(Vector3(0, 0, -100))
	via.curve.add_point(Vector3(0, 0, 100))
	var tramo := TrackSegment.new()
	tramo.segment_id = &"prueba"
	tramo.condition = 1.0
	via.add_child(tramo)
	var loco := Vehicle.new()
	loco.data = load("res://data/vehicles/locomotive.tres") as VehicleData
	via.add_child(loco)
	add_child(via)
	loco.progress = 150.0
	await get_tree().process_frame
	var libre: float = loco.data.get_max_speed(loco.get_track_condition())
	_comprobar(is_equal_approx(loco.get_max_speed(), libre) and SpeedZone.find_for(loco.get_train()) == null, "Fuera de la zona el tope es el de la vía (%.1f m/s)" % libre)
	loco.progress = 75.0
	_comprobar(is_equal_approx(loco.get_max_speed(), zona.max_speed) and SpeedZone.find_for(loco.get_train()) == zona, "En la zona el tope baja a %.1f m/s" % zona.max_speed)
	loco.speed = libre
	loco.throttle = 1.0
	loco.simulate(0.5)
	_comprobar(loco.speed < libre and loco.speed > zona.max_speed, "Entrando rápido, frena hacia el tope (%.1f m/s)" % loco.speed)
	loco.automatic = true
	_comprobar(is_equal_approx(loco.get_max_speed(), libre), "Un automático no mira la zona")
	loco.automatic = false
	var lenta := SpeedZone.new()
	lenta.length = 50.0
	lenta.width = 10.0
	lenta.max_speed = 2.0
	add_child(lenta)
	_comprobar(is_equal_approx(loco.get_max_speed(), 2.0), "Con dos zonas encimadas vale la más lenta")
	lenta.queue_free()
	via.queue_free()
	zona.queue_free()
	await get_tree().process_frame
	# Ya están borradas: se cuenta en vez de buscarlas (has() con un objeto borrado da error).
	_comprobar(SpeedZone.get_zones().size() == zonas_antes, "Al salir del árbol la zona se borra de la lista")


# El Hito A tiene lotes para todas sus familias y las dos zonas de Olavarría.
func _probar_hito_a() -> void:
	var escena := (load(HITO_A) as PackedScene).instantiate()
	var lotes: Node = escena.get_node_or_null("Lotes")
	_comprobar(lotes is TrackLots, "El Hito A tiene su nodo Lotes")
	var cuenta: Dictionary[StringName, int] = {}
	var anillos: Dictionary[int, int] = {}
	var fijos: int = 0
	if lotes != null:
		for hijo: Node in lotes.get_children():
			var lote := hijo as TrackLot
			if lote != null:
				cuenta[lote.station_id] = cuenta.get(lote.station_id, 0) + 1
				if lote.station_id == &"olavarria":
					anillos[lote.ring] = anillos.get(lote.ring, 0) + 1
				if lote.fixed_scene != null:
					fijos += 1
	_comprobar(cuenta.get(&"azul", 0) == 12 and cuenta.get(&"olavarria", 0) == 20 and cuenta.get(&"sierras_bayas", 0) == 4, "Lotes: 12 en Azul (6 en la entrada y 6 del otro lado), 20 en Olavarría y 4 en Sierras Bayas (%s)" % [cuenta])
	_comprobar(anillos.get(TrackLot.Ring.FIELD, 0) == 8 and anillos.get(TrackLot.Ring.INDUSTRY, 0) == 8 and anillos.get(TrackLot.Ring.TOWN, 0) == 4, "Olavarría: 8 de campo, 8 industriales y 4 del pueblo (%s)" % [anillos])
	_comprobar(fijos == 2, "Dos galpones ferroviarios fijos, uno en cada entrada de Olavarría")
	var azul := escena.get_node_or_null("Azul") as Node3D
	_comprobar(azul != null and is_equal_approx(azul.position.z, 1040.0), "Azul quedó 500 m más lejos (z 1040)")
	for nombre: String in ["PrecaucionNorte", "PrecaucionSur"]:
		var zona := escena.get_node_or_null(nombre) as SpeedZone
		_comprobar(zona != null and zona.length >= 100.0, "%s: zona de precaución en la entrada de Olavarría" % nombre)
	escena.free()


# Deja a la vista un lote vacío y las seis parcelas, en fila, para mirarlas.
func _armar_vista() -> void:
	if _lotes != null:
		_lotes.queue_free()
	for nodo: Node in get_tree().get_nodes_in_group(TrackLot.GROUP):
		nodo.queue_free()
	var x: float = -330.0
	_lote(&"vista", Vector3(x - 110.0, 0, 0), TrackLot.Ring.FIELD)
	for oficio: OccupationData in OccupationData.load_all():
		var anillo: TrackLot.Ring = TrackLot.Ring.INDUSTRY if oficio.kind == OccupationData.Kind.PROCESSED else TrackLot.Ring.FIELD
		var lote := _lote(&"vista", Vector3(x, 0, 0), anillo)
		lote.place(oficio, true)
		x += 110.0
	var galpon := TrackLot.new()
	galpon.ring = TrackLot.Ring.INDUSTRY
	galpon.fixed_scene = load("res://scenes/parcels/galpon_ferroviario.tscn") as PackedScene
	add_child(galpon)
	galpon.global_position = Vector3(x, 0, 0)
	var suelo := MeshInstance3D.new()
	var malla := BoxMesh.new()
	malla.size = Vector3(900, 0.1, 160)
	suelo.mesh = malla
	suelo.position = Vector3(0, -0.06, 0)
	add_child(suelo)
	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-50, 30, 0)
	add_child(luz)
	var camara := Camera3D.new()
	add_child(camara)
	camara.far = 2000.0
	camara.look_at_from_position(Vector3(-60, 160, 260), Vector3(-60, 0, 0))


func _lote(station_id: StringName, at: Vector3, ring: TrackLot.Ring) -> TrackLot:
	var lote := TrackLot.new()
	lote.station_id = station_id
	lote.ring = ring
	add_child(lote)
	lote.global_position = at
	return lote


func _comprobar(condicion: bool, texto: String) -> void:
	if condicion:
		print("  OK  ", texto)
	else:
		_fallos += 1
		push_error("  FALLA  " + texto)
