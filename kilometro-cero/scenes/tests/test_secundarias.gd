extends Node3D
## Prueba de la tarea 62b.6 (D129, D130): secundarias del tren propio en lógica pura y el panal.
## - Encargo (MissionData.pays_market_multiplier): "Miel para Don Ernesto" (3 frascos al triple del
##   valor) y "Cueros para Doña Rosa" (6 cueros al doble del mercado, después se queda como
##   curtidora). Lo que paga se fija al cumplirse.
## - Mudanza (MissionData.reward_family): "Los Etchegaray" viajan en el coche de Olavarría a Azul
##   (suben gratis aunque no estén en el stock, MissionData.passenger_from) y quedan como tamberos del
##   jugador. Una mudanza sin lugar en la estación (tope de D129) no se desbloquea.
## - Familias con nombre en el ProductionModel (se guardan), la pestaña Vecinos (AgendaText.neighbors)
##   y el vagón cerrado que lleva cueros, leche, miel y cuero curtido.
## - El panal de miel (scenes/world/honey_comb.tscn): Harvestable sin herramienta, da 1 frasco y
##   vuelve a las 24 h.
## Usa un modelo y un tablero propios con Olavarría y Azul (no toca la partida de GameState). Subir
## a los Etchegaray con el coche de verdad, juntar miel con el clic y ver a los Etchegaray mudarse
## con humo se prueba jugando el Hito A.

const MISSIONS: String = "res://data/missions/"
const PANAL: String = "res://scenes/world/honey_comb.tscn"

var _fallos: int = 0
var _modelo: ProductionModel
var _tablero: MissionBoard
var _mercado: Economy
var _pasajeros: PassengerTraffic


func _ready() -> void:
	_probar_datos()
	_armar()
	_probar_miel()
	_probar_cueros()
	_probar_mudanza()
	_probar_guardado()
	_probar_vecinos()
	_probar_pestanas()
	await _probar_panal()
	if _fallos == 0:
		print("Secundarias: todas las comprobaciones pasaron.")
	else:
		push_error("Secundarias: fallaron %d comprobaciones." % _fallos)


func _datos(nombre: String) -> MissionData:
	return load(MISSIONS + nombre + ".tres") as MissionData


func _probar_datos() -> void:
	for nombre: String in ["miel_don_ernesto", "cueros_dona_rosa", "los_etchegaray"]:
		var datos: MissionData = _datos(nombre)
		_comprobar(datos != null and datos.validate().is_empty(), "%s carga y sus datos están bien (%s)" % [nombre, str(datos.validate()) if datos != null else "no carga"])
	var miel: MissionData = _datos("miel_don_ernesto")
	var cueros: MissionData = _datos("cueros_dona_rosa")
	var etche: MissionData = _datos("los_etchegaray")
	if miel == null or cueros == null or etche == null:
		return
	_comprobar(miel.is_order() and not miel.is_move() and is_equal_approx(miel.pays_market_multiplier, 3.0), "La miel es un encargo al triple")
	_comprobar(cueros.is_order() and cueros.is_move() and cueros.reward_family.id == &"curtidores" and cueros.reward_family_name == "Doña Rosa", "Los cueros: encargo al doble y Doña Rosa se queda como curtidora")
	_comprobar(etche.is_move() and not etche.is_order() and etche.reward_family.id == &"tamberos" and etche.passenger_from == &"olavarria", "Los Etchegaray: mudanza de tamberos que espera en Olavarría")
	_comprobar(etche.requires.has(&"primeras_casas") and etche.station_id == &"azul" and etche.min_level == 2, "Los Etchegaray llegan después de las primeras casas de Azul")
	var familia: ItemData = etche.delivery[0].item
	_comprobar(ItemData.is_passenger(familia) and ItemData.is_specialist(familia) and not Economy.is_tradable(familia), "La familia viaja en el coche, de a una, y no se vende")
	var mala := MissionData.new()
	mala.id = &"mala"
	mala.title = "Mala"
	mala.station_id = &"azul"
	mala.kind = MissionData.Kind.CLEAR_ZONE
	mala.zone_group = &"nada"
	mala.pays_market_multiplier = 2.0
	mala.reward_family = etche.reward_family
	var problemas: PackedStringArray = mala.validate()
	_comprobar(problemas.size() == 2, "Avisa un encargo que no es de entrega y una familia sin nombre (%s)" % [problemas])
	var cerrado := load("res://data/vehicles/boxcar.tres") as WagonData
	var acepta: bool = cerrado != null
	for etiqueta: StringName in [&"cement", &"hides", &"leather", &"milk", &"honey"]:
		acepta = acepta and cerrado.accepted_tags.has(etiqueta)
	_comprobar(acepta, "El vagón cerrado lleva cemento, cueros, cuero curtido, leche y miel")


func _armar() -> void:
	_modelo = ProductionModel.new()
	for oficio: OccupationData in OccupationData.load_all():
		_modelo.add_occupation(oficio)
	_mercado = Economy.new(_modelo)
	_tablero = MissionBoard.new(_modelo)
	_tablero.price_check = _mercado.get_buy_price
	_pasajeros = PassengerTraffic.new(_tablero, _mercado)
	for nombre: String in ["olavarria", "azul"]:
		var datos := load("res://data/stations/%s.tres" % nombre) as StationData
		_modelo.add_station(datos, 1)
		_mercado.add_station(datos)
	for oficio: OccupationData in _modelo.get_occupations():
		_mercado.register_occupation(oficio)
	_tablero.refresh()


func _probar_miel() -> void:
	var via: Mission = _tablero.register_side(_datos("la_via_tapada"))
	var miel: Mission = _tablero.register_side(_datos("miel_don_ernesto"))
	_comprobar(miel != null and miel.state == Mission.State.LOCKED, "La miel espera a la vía tapada")
	_tablero.start(via.id)
	_comprobar(via.is_completed() and miel.state == Mission.State.AVAILABLE, "Despejada la vía, Don Ernesto pide la miel")
	_comprobar(_tablero.get_order_payment(miel) == 270 and _tablero.get_reward_money(miel) == 270, "Paga 3 × 30 × 3 = $270 (dice %d)" % _tablero.get_order_payment(miel))
	_tablero.start(miel.id)
	var pasos: PackedStringArray = _tablero.get_pending_steps(miel)
	_comprobar(pasos.size() == 2 and pasos[0].begins_with("Entregar 3 ") and pasos[1] == "Paga $270 al entregar todo", "Pasos: entregar 3 frascos y lo que paga (%s)" % [pasos])
	_comprobar(_tablero.plan_delivery(&"olavarria", {&"honey": 5} as Dictionary[StringName, int]) == ({&"honey": 3} as Dictionary[StringName, int]), "El tablero de Olavarría toma 3 de 5 frascos")
	_comprobar(_tablero.deliver(&"olavarria", &"honey", 3) == 3 and miel.is_completed(), "Con 3 frascos se cumple")
	_comprobar(miel.paid == 270 and _tablero.get_reward_money(miel) == 270, "Se cobraron $270")


func _probar_cueros() -> void:
	var cueros: Mission = _tablero.register_side(_datos("cueros_dona_rosa"))
	_comprobar(cueros.state == Mission.State.LOCKED, "Con Olavarría en el nivel 1 Doña Rosa todavía no pide")
	_modelo.set_level(&"olavarria", 2)
	_comprobar(cueros.state == Mission.State.AVAILABLE, "Olavarría nivel 2: Doña Rosa pide los cueros")
	_comprobar(_tablero.get_order_payment(cueros) == 300, "Paga 6 × $25 × 2 = $300 (dice %d)" % _tablero.get_order_payment(cueros))
	_tablero.start(cueros.id)
	_tablero.deliver(&"olavarria", &"hides", 6)
	_comprobar(cueros.is_completed(), "Con 6 cueros se cumple")
	_comprobar(_modelo.get_player_families(&"olavarria") == ([&"curtidores"] as Array[StringName]) and _modelo.get_player_slots(&"olavarria") == 2, "Doña Rosa es la primera vecina del jugador en Olavarría (quedan 2 lugares)")
	var lista: Array[Dictionary] = _modelo.get_player_family_list(&"olavarria")
	_comprobar(lista.size() == 1 and lista[0]["name"] == "Doña Rosa" and not lista[0]["working"], "Se llama Doña Rosa y sin cueros no trabaja")
	_comprobar(_principal(&"olavarria", &"hides") != null, "Nace la principal de cueros para Olavarría")
	_comprobar(_mercado.get_buy_price(&"olavarria", &"hides") > 25 and cueros.paid == 300, "Ahora los cueros valen más en Olavarría, pero se cobró lo prometido ($%d)" % cueros.paid)


func _probar_mudanza() -> void:
	var casas: Mission = _tablero.register_side(_datos("primeras_casas"))
	var etche: Mission = _tablero.register_side(_datos("los_etchegaray"))
	var otra_datos := MissionData.new()
	otra_datos.id = &"otra_mudanza"
	otra_datos.title = "Otra familia"
	otra_datos.station_id = &"azul"
	otra_datos.delivery = _datos("los_etchegaray").delivery
	otra_datos.min_level = 2
	otra_datos.requires = [&"los_etchegaray"] as Array[StringName]
	otra_datos.reward_family = _datos("los_etchegaray").reward_family
	otra_datos.reward_family_name = "los Otros"
	otra_datos.passenger_from = &"olavarria"
	var otra: Mission = _tablero.register_side(otra_datos)
	_comprobar(etche.state == Mission.State.LOCKED, "Con Azul en el nivel 1 no hay mudanza")
	_modelo.set_level(&"azul", 2)
	_comprobar(casas.state == Mission.State.AVAILABLE and etche.state == Mission.State.LOCKED, "Azul nivel 2: primero las casas")
	_tablero.start(casas.id)
	_tablero.deliver_build(casas.id, &"log", 20)
	_comprobar(casas.is_completed() and etche.state == Mission.State.AVAILABLE, "Con las casas hechas, los Etchegaray piden venir")
	_comprobar(_tablero.passenger_source(etche, &"family") == &"olavarria" and _tablero.boards_without_stock(etche), "Esperan en Olavarría, fuera del stock")
	_comprobar(_tablero.get_passenger_needs(etche).is_empty(), "Sin aceptarla no se reserva a nadie")
	_tablero.start(etche.id)
	var pasos: PackedStringArray = _tablero.get_pending_steps(etche)
	_comprobar(pasos.size() == 1 and pasos[0].begins_with("Traer 1 familia desde Olavarría"), "Paso: traer la familia desde Olavarría (%s)" % [pasos])
	var arriba: Dictionary = _pasajeros.plan_exchange(&"olavarria", {} as Dictionary[StringName, int], 20)
	_comprobar(arriba["board_free"].get(&"family", 0) == 1 and arriba["board_paid"].get(&"family", 0) == 0, "En Olavarría la familia sube gratis aunque no haya stock")
	_pasajeros.apply_exchange(&"olavarria", arriba)
	var abajo: Dictionary = _pasajeros.plan_exchange(&"azul", {&"family": 1} as Dictionary[StringName, int], 20)
	_comprobar(abajo["mission"].size() == 1 and abajo["mission"].get(&"family", 0) == 1, "En Azul baja para su mudanza")
	_comprobar(_pasajeros.plan_exchange(&"sierras_bayas", {&"family": 1} as Dictionary[StringName, int], 20)["alight"].is_empty(), "En otra estación no se baja")
	_pasajeros.apply_exchange(&"azul", abajo)
	_comprobar(etche.is_completed() and etche.paid == 100, "Llegaron: se cumple y paga $100")
	var lista: Array[Dictionary] = _modelo.get_player_family_list(&"azul")
	_comprobar(lista.size() == 1 and lista[0]["occupation"] == &"tamberos" and lista[0]["name"] == "los Etchegaray" and lista[0]["working"], "Los Etchegaray son tamberos de Azul y trabajan")
	_comprobar(_modelo.get_production(&"azul").get(&"milk", 0) == 5 and _modelo.get_player_slots(&"azul") == 0, "Azul da 5 tarros de leche y no le quedan lugares")
	_comprobar(otra.state == Mission.State.LOCKED, "Otra mudanza a Azul no se desbloquea: no hay lugar")


func _probar_guardado() -> void:
	var otro := ProductionModel.new()
	for oficio: OccupationData in OccupationData.load_all():
		otro.add_occupation(oficio)
	otro.load_dict(_modelo.to_dict())
	for nombre: String in ["olavarria", "azul"]:
		otro.add_station(load("res://data/stations/%s.tres" % nombre) as StationData, 1)
	var azul: Array[Dictionary] = otro.get_player_family_list(&"azul")
	var olav: Array[Dictionary] = otro.get_player_family_list(&"olavarria")
	_comprobar(azul.size() == 1 and azul[0]["name"] == "los Etchegaray" and olav.size() == 1 and olav[0]["name"] == "Doña Rosa", "Las familias se guardan con su nombre")
	var miel: Mission = _tablero.get_mission(&"miel_don_ernesto")
	var copia: Mission = Mission.create_side(miel.data)
	copia.apply_dict(miel.to_dict())
	_comprobar(copia.paid == 270, "Lo cobrado se guarda")


func _probar_vecinos() -> void:
	var texto: String = AgendaText.neighbors(_tablero, _modelo)
	_comprobar(texto.contains("Vecinos que trajiste") and texto.contains("los Etchegaray") and texto.contains("tamberos") and texto.contains("Doña Rosa") and texto.contains("curtidores"), "La pestaña Vecinos nombra a las dos familias y sus oficios")
	_comprobar(texto.contains("trabajando") and texto.contains("sin trabajar") and texto.contains("piden 2 "), "Dice quién trabaja y lo que piden")
	_comprobar(texto.contains("Azul 1 de 1") and texto.contains("Olavarría 1 de 3"), "Dice los lugares de cada estación")
	var vacio := ProductionModel.new()
	vacio.add_station(load("res://data/stations/azul.tres") as StationData, 1)
	_comprobar(AgendaText.neighbors(MissionBoard.new(vacio), vacio).contains("Todavía no trajiste a nadie"), "Sin vecinos lo dice")
	print(texto)


func _probar_pestanas() -> void:
	_comprobar(InventoryUI.TAB_NAMES.size() == 4 and InventoryUI.TAB_NAMES[InventoryUI.Tab.NEIGHBORS] == "Vecinos", "El TAB tiene la cuarta pestaña, Vecinos")


func _probar_panal() -> void:
	var escena := load(PANAL) as PackedScene
	_comprobar(escena != null, "Carga el panal")
	if escena == null:
		return
	var panal: Node3D = escena.instantiate()
	add_child(panal)
	await get_tree().process_frame
	var juntar := panal.get_node_or_null(^"Miel/Harvestable") as Harvestable
	_comprobar(juntar != null and juntar.required_tool == null and juntar.get_required_tool_id() == &"", "El panal se junta con las manos")
	if juntar == null:
		return
	_comprobar(juntar.get_action_name() == "juntar miel" and juntar.drop_item.id == &"honey" and juntar.drop_amount == 1 and is_equal_approx(juntar.regrow_hours, 24.0), "Da 1 frasco de miel y vuelve en 24 h")
	var antes: int = _contar_objetos()
	_comprobar(not juntar.hit() and juntar.hit(), "Con dos golpes se termina")
	_comprobar(_contar_objetos() == antes + 1, "Cayó un frasco")
	var miel := panal.get_node(^"Miel") as Node3D
	var tronco := panal.get_node(^"Tronco") as Node3D
	_comprobar(not miel.visible and tronco.visible and not juntar.is_available(), "Se va el panal y queda el tronco")
	EventBus.time_advanced.emit(24.0)
	_comprobar(miel.visible and juntar.is_available(), "A las 24 h vuelve")
	panal.queue_free()


func _contar_objetos() -> int:
	var cantidad: int = 0
	for hijo: Node in get_tree().current_scene.get_children():
		if hijo is WorldItem:
			cantidad += 1
	return cantidad


func _principal(station_id: StringName, item_id: StringName) -> Mission:
	for mision: Mission in _tablero.get_main_missions(station_id):
		if mision.item_id == item_id:
			return mision
	return null


func _comprobar(ok: bool, texto: String) -> void:
	if ok:
		print("  OK  ", texto)
	else:
		_fallos += 1
		push_error("  FALLA  " + texto)
