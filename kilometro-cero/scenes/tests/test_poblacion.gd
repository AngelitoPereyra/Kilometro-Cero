extends Node
## Prueba de la tarea 62b.1: biomas, rasgos y familias con oficio (OccupationData, BiomeData,
## población del ProductionModel; D129 y D132). Lógica pura, sin mapa: arma los oficios, el
## bioma de las sierras y las tres estaciones del Hito A en código (los .tres llegan en la 62b.2).

const LOG_PATH: String = "res://data/items/log.tres"
const STONE_PATH: String = "res://data/items/limestone.tres"
const CEMENT_PATH: String = "res://data/items/cement.tres"

var _fallos: int = 0
var _tronco: ItemData
var _piedra: ItemData
var _cemento: ItemData
var _cuero: ItemData
var _leche: ItemData
var _curtido: ItemData
var _trigo: ItemData
# Oficios del Hito A (valores del plan de la 62b).
var _hacheros: OccupationData
var _puesteros: OccupationData
var _canteros: OccupationData
var _caleros: OccupationData
var _tamberos: OccupationData
var _curtidores: OccupationData
var _sierras: BiomeData


func _ready() -> void:
	_armar_datos()
	_probar_datos()
	_probar_asignacion()
	_probar_orden()
	_probar_jugador()
	_probar_insumos()
	_probar_crecimiento()
	_probar_guardado()
	if _fallos == 0:
		print("Población: todas las comprobaciones pasaron.")
	else:
		push_error("Población: fallaron %d comprobaciones." % _fallos)


# --- Datos ---


func _armar_datos() -> void:
	_tronco = load(LOG_PATH) as ItemData
	_piedra = load(STONE_PATH) as ItemData
	_cemento = load(CEMENT_PATH) as ItemData
	_cuero = _objeto(&"hides", "cuero")
	_leche = _objeto(&"milk", "tarro de leche")
	_curtido = _objeto(&"leather", "cuero curtido")
	_trigo = _objeto(&"wheat", "bolsa de trigo")
	_hacheros = _oficio(&"hacheros", OccupationData.Kind.RAW, [], [[_tronco, 10]], &"monte")
	_puesteros = _oficio(&"puesteros", OccupationData.Kind.RAW, [], [[_cuero, 2]], &"campo")
	_canteros = _oficio(&"canteros", OccupationData.Kind.RAW, [[_tronco, 5]], [[_piedra, 10]], &"cantera")
	_caleros = _oficio(&"caleros", OccupationData.Kind.PROCESSED, [[_piedra, 10]], [[_cemento, 5]], &"horno")
	_tamberos = _oficio(&"tamberos", OccupationData.Kind.FOOD, [], [[_leche, 5]], &"campo")
	_curtidores = _oficio(&"curtidores", OccupationData.Kind.PROCESSED, [[_cuero, 2]], [[_curtido, 1]], &"")
	_sierras = BiomeData.new()
	_sierras.id = &"sierras"
	_sierras.display_name = "Sierras"
	_sierras.own = [_canteros, _caleros, _puesteros] as Array[OccupationData]
	_sierras.possible = [_tamberos, _curtidores] as Array[OccupationData]
	_sierras.natural_demands = [_tronco, _trigo] as Array[ItemData]


func _probar_datos() -> void:
	_comprobar(_canteros.get_needs() == _dic({&"log": 5}) and _canteros.get_production() == _dic({&"limestone": 10}), "Oficio: insumos y producción por familia")
	_comprobar(_canteros.produces_item(&"limestone") and not _canteros.produces_item(&"log"), "Oficio: qué produce")
	_comprobar(_canteros.find_item(&"log") == _tronco and _canteros.find_item(&"milk") == null, "Oficio: encuentra sus objetos")
	_comprobar(_canteros.validate().is_empty(), "Oficio bien armado: sin problemas")
	_comprobar(not OccupationData.new().validate().is_empty(), "Oficio vacío: avisa problemas")
	_comprobar(_sierras.is_own(&"canteros") and _sierras.is_possible(&"tamberos") and not _sierras.is_own(&"tamberos"), "Bioma: propios y posibles")
	_comprobar(_sierras.allows(&"curtidores") and not _sierras.allows(&"hacheros"), "Bioma: el jugador puede traer propios o posibles, no otros")
	_comprobar(_sierras.get_occupations().size() == 5 and _sierras.validate().is_empty(), "Bioma: 5 oficios y sin problemas")

	var azul: StationData = _azul()
	var olavarria: StationData = _olavarria()
	var sierras_bayas: StationData = _sierras_bayas()
	_comprobar(azul.get_max_player_occupations() == 1 and olavarria.get_max_player_occupations() == 3 and sierras_bayas.get_max_player_occupations() == 0, "Tope del jugador por tipo: pueblo 1, ciudad 3, carga 0")
	azul.max_player_occupations = 2
	_comprobar(azul.get_max_player_occupations() == 2, "El tope puesto a mano manda")
	_comprobar(sierras_bayas.get_family_quota(1) == 2 and sierras_bayas.get_family_quota(2) == 4 and azul.get_family_quota(1) == 0, "Cupo de familias por nivel")
	_comprobar(azul.has_trait(&"monte") and not azul.has_trait(&"cantera"), "Rasgos de la estación")
	_comprobar(sierras_bayas.find_item(&"cement") == _cemento, "find_item busca también en los oficios del bioma")
	_comprobar(sierras_bayas.validate().is_empty(), "Estación con bioma y familias: sin problemas")
	sierras_bayas.biome = null
	sierras_bayas.traits = [] as Array[StringName]
	_comprobar(not sierras_bayas.validate().is_empty(), "Con familias y sin bioma ni rasgos avisa")


# --- Asignación sola ---


func _probar_asignacion() -> void:
	var modelo: ProductionModel = _modelo_hito()
	var llegadas: Array = []
	modelo.family_added.connect(func(id: StringName, oficio: OccupationData, origen: int) -> void: llegadas.append([id, oficio.id, origen]))
	_comprobar(_lista(modelo.get_families(&"sierras_bayas")) == "canteros, canteros", "Sierras Bayas arranca con 2 familias de canteros (rasgo cantera)")
	_comprobar(_lista(modelo.get_families(&"olavarria")) == "caleros, caleros", "Olavarría arranca con 2 familias de caleros (rasgo horno)")
	_comprobar(modelo.get_family_count(&"azul") == 0, "Azul en el nivel 1 no tiene familias")
	_comprobar(llegadas.is_empty(), "Las familias del arranque no se avisan")
	var permitidos: Array[StringName] = []
	for oficio: OccupationData in modelo.get_allowed_occupations(&"azul"):
		permitidos.append(oficio.id)
	_comprobar(_lista(permitidos) == "puesteros, hacheros", "En Azul se asignan solos puesteros (propio, campo) y hacheros (monte); no canteros, caleros ni tamberos (posible): %s" % _lista(permitidos))

	modelo.set_level(&"azul", 2)
	var azul: Array[StringName] = modelo.get_families(&"azul")
	_comprobar(azul.size() == 2 and azul.has(&"hacheros") and azul.has(&"puesteros"), "Azul sube al 2 y llegan hacheros y puesteros: %s" % _lista(azul))
	_comprobar(llegadas.size() == 2 and llegadas[0][0] == &"azul" and llegadas[0][2] == ProductionModel.FamilyOrigin.LEVEL, "Avisa las 2 familias del nivel nuevo")

	var sin_rasgos := StationData.new()
	sin_rasgos.id = &"loma"
	sin_rasgos.display_name = "Loma"
	sin_rasgos.biome = _sierras
	modelo.add_station(sin_rasgos)
	_comprobar(modelo.choose_occupation(&"loma") == null and modelo.get_allowed_occupations(&"loma").is_empty(), "Sin rasgos, los oficios de las sierras que piden rasgo no se asignan")

	var sin_hacheros := ProductionModel.new()
	sin_hacheros.add_station(_azul(), 2)
	_comprobar(_lista(sin_hacheros.get_families(&"azul")) == "puesteros, puesteros", "Sin registrar los hacheros, el monte no los habilita")

	modelo.add_family(&"sierras_bayas", &"canteros")
	_comprobar(modelo.count_families(&"sierras_bayas", &"canteros") == 3, "add_family suma una familia elegida (recompensa)")
	modelo.set_level(&"sierras_bayas", 2)
	_comprobar(modelo.count_families(&"sierras_bayas", &"canteros") == 5, "La de recompensa no cuenta para el cupo: en el nivel 2 llegan 2 más")
	_comprobar(not modelo.add_family(&"sierras_bayas", &"nadie") and not modelo.add_family(&"nada", &"canteros"), "add_family con oficio o estación desconocidos no suma")


func _probar_orden() -> void:
	var chacareros: OccupationData = _oficio(&"chacareros", OccupationData.Kind.RAW, [], [[_trigo, 10]], &"")
	var molineros: OccupationData = _oficio(&"molineros", OccupationData.Kind.PROCESSED, [[_trigo, 10]], [[_objeto(&"flour", "harina"), 5]], &"")
	var lecheros: OccupationData = _oficio(&"lecheros", OccupationData.Kind.FOOD, [], [[_leche, 5]], &"")
	var pampa := BiomeData.new()
	pampa.id = &"pampa"
	pampa.display_name = "Pampa húmeda"
	pampa.own = [molineros, chacareros, lecheros] as Array[OccupationData]
	var pueblo: StationData = _estacion(&"chacra", StationData.StationType.TOWN, pampa, [], [3])
	var modelo := ProductionModel.new()
	modelo.add_station(pueblo)
	_comprobar(_lista(modelo.get_families(&"chacra")) == "lecheros, chacareros, chacareros", "Orden de D129: primero comida, después materia prima (el procesado espera): %s" % _lista(modelo.get_families(&"chacra")))

	var lenadores: OccupationData = _oficio(&"lenadores", OccupationData.Kind.RAW, [], [[_tronco, 10]], &"")
	var monte := BiomeData.new()
	monte.id = &"monte"
	monte.display_name = "Monte"
	monte.own = [_oficio(&"criadores", OccupationData.Kind.RAW, [], [[_cuero, 2]], &""), lenadores] as Array[OccupationData]
	var con_falta: StationData = _estacion(&"aldea", StationData.StationType.TOWN, monte, [], [1])
	con_falta.levels[0].needs = [_cantidad(_tronco, 10)] as Array[ItemAmount]
	var otro := ProductionModel.new()
	otro.add_station(con_falta)
	_comprobar(_lista(otro.get_families(&"aldea")) == "lenadores", "Entre los del mismo grupo gana el que da lo que falta (troncos)")
	_comprobar(otro.is_covered(&"aldea") and otro.get_free_production(&"aldea") == _dic({&"log": 0}), "Los leñadores cubren el consumo del pueblo con lo propio")


# --- Tope del jugador ---


func _probar_jugador() -> void:
	var modelo: ProductionModel = _modelo_hito()
	modelo.set_level(&"azul", 2)
	_comprobar(modelo.get_player_slots(&"azul") == 1 and modelo.get_player_slots(&"olavarria") == 3 and modelo.get_player_slots(&"sierras_bayas") == 0, "Lugares del jugador: Azul 1, Olavarría 3, Sierras Bayas 0")
	_comprobar(not modelo.can_add_player_family(&"azul", &"hacheros"), "No trae hacheros: no son del bioma de las sierras (aunque Azul tenga monte)")
	var llegadas: Array = []
	modelo.family_added.connect(func(id: StringName, oficio: OccupationData, origen: int) -> void: llegadas.append([id, oficio.id, origen]))
	_comprobar(modelo.add_player_family(&"azul", &"tamberos"), "Trae a los tamberos a Azul (posible del bioma, rasgo campo)")
	_comprobar(llegadas == [[&"azul", &"tamberos", ProductionModel.FamilyOrigin.PLAYER]], "Avisa la familia del jugador")
	_comprobar(_lista(modelo.get_player_families(&"azul")) == "tamberos" and modelo.get_player_slots(&"azul") == 0, "Azul ya usó su lugar")
	_comprobar(not modelo.add_player_family(&"azul", &"curtidores"), "Una segunda familia del jugador en un pueblo no entra")
	_comprobar(not modelo.add_player_family(&"olavarria", &"tamberos"), "Tamberos en Olavarría no: falta el rasgo campo")
	_comprobar(not modelo.add_player_family(&"sierras_bayas", &"curtidores"), "En una estación de carga el jugador no trae familias")
	var entraron: int = 0
	for _i: int in 4:
		if modelo.add_player_family(&"olavarria", &"curtidores"):
			entraron += 1
	_comprobar(entraron == 3, "En una ciudad entran 3 familias del jugador y la cuarta no")
	_comprobar(modelo.count_families(&"olavarria", &"caleros") == 2, "Las del jugador no cambian las del cupo")


# --- Insumos ---


func _probar_insumos() -> void:
	var modelo: ProductionModel = _modelo_hito()
	modelo.set_level(&"azul", 2)
	_comprobar(modelo.get_production(&"sierras_bayas") == _dic({}) and modelo.get_idle_families(&"sierras_bayas").size() == 2, "Sin troncos los canteros no pican")
	_comprobar(modelo.get_consumption(&"sierras_bayas") == _dic({&"log": 10}) and modelo.get_missing(&"sierras_bayas") == _dic({&"log": 10}), "Sierras Bayas consume lo de sus familias: 10 troncos")
	_comprobar(modelo.get_uncommitted_needs(&"sierras_bayas") == _dic({&"log": 10}), "Eso es lo que pediría su principal")
	_comprobar(modelo.get_production(&"azul") == _dic({&"log": 10, &"hides": 2}), "Azul produce lo de sus hacheros y puesteros")

	var abierto: Array[bool] = [true]
	modelo.connection_check = func(desde: StringName, hasta: StringName) -> bool: return abierto[0] or not (desde == &"azul" and hasta == &"sierras_bayas")
	var troncos: ProductionFlow = modelo.add_flow(&"azul", &"sierras_bayas", &"log", 10)
	_comprobar(modelo.get_production(&"sierras_bayas") == _dic({&"limestone": 20}) and modelo.get_idle_families(&"sierras_bayas").is_empty(), "Con 10 troncos de Azul, los canteros dan 20 piedras")
	modelo.add_flow(&"sierras_bayas", &"olavarria", &"limestone", 20)
	_comprobar(modelo.get_production(&"olavarria").get(&"cement", 0) == 10, "La cadena se resuelve en el mismo día: troncos -> piedra -> 10 de cemento en Olavarría")
	_comprobar(modelo.is_covered(&"sierras_bayas") and modelo.is_covered(&"olavarria"), "Las dos quedan cubiertas")
	_comprobar(modelo.get_free_production(&"olavarria") == _dic({&"cement": 10}), "El cemento queda libre (mercado, misiones)")

	modelo.remove_flow(troncos)
	modelo.add_flow(&"azul", &"sierras_bayas", &"log", 7)
	_comprobar(modelo.get_production(&"sierras_bayas") == _dic({&"limestone": 10}) and modelo.get_idle_families(&"sierras_bayas").size() == 1, "Con 7 troncos trabaja una sola familia de canteros")
	_comprobar(modelo.get_production(&"olavarria").get(&"cement", 0) == 5 and modelo.get_idle_families(&"olavarria").size() == 1, "Y en Olavarría trabaja un solo calero")
	abierto[0] = false
	_comprobar(modelo.get_production(&"sierras_bayas") == _dic({}) and modelo.get_production(&"olavarria").get(&"cement", 0) == 0, "Cortado o_s, se para toda la cadena")

	var mixta: StationData = _estacion(&"mixta", StationData.StationType.TOWN, _sierras, [&"monte", &"cantera"], [0])
	var propio := ProductionModel.new()
	propio.add_occupation(_hacheros)
	propio.add_station(mixta)
	propio.add_family(&"mixta", &"hacheros")
	propio.add_family(&"mixta", &"canteros")
	_comprobar(propio.get_production(&"mixta") == _dic({&"log": 10, &"limestone": 10}), "Los canteros toman los troncos de los hacheros del mismo pueblo")
	_comprobar(propio.get_free_production(&"mixta") == _dic({&"log": 5, &"limestone": 10}) and propio.is_covered(&"mixta"), "Lo que usan no queda libre")


func _probar_crecimiento() -> void:
	var modelo: ProductionModel = _modelo_hito()
	modelo.set_level(&"azul", 3)  # en su último nivel, así no crece en esta prueba
	modelo.add_flow(&"azul", &"sierras_bayas", &"log", 10)
	var avisos: Array = []
	modelo.level_changed.connect(func(id: StringName, nivel: int) -> void: avisos.append(["nivel", id, nivel]))
	modelo.family_added.connect(func(id: StringName, oficio: OccupationData, _origen: int) -> void: avisos.append(["familia", id, oficio.id]))
	modelo.advance_day()
	_comprobar(modelo.get_level(&"sierras_bayas") == 2 and modelo.count_families(&"sierras_bayas", &"canteros") == 4, "Cubierta, Sierras Bayas crece y llegan 2 familias más de canteros")
	_comprobar(avisos.size() == 3 and avisos[0] == ["nivel", &"sierras_bayas", 2] and avisos[1] == ["familia", &"sierras_bayas", &"canteros"], "Avisa primero el nivel y después cada familia")
	_comprobar(modelo.get_missing(&"sierras_bayas") == _dic({&"log": 10}) and modelo.get_idle_families(&"sierras_bayas").size() == 2, "Las nuevas piden 10 troncos más y sin ellos no pican")


# --- Guardado ---


func _probar_guardado() -> void:
	var modelo: ProductionModel = _modelo_hito()
	modelo.set_level(&"azul", 2)
	modelo.add_player_family(&"azul", &"tamberos")
	modelo.add_family(&"sierras_bayas", &"canteros")
	var guardado: Dictionary = modelo.to_dict()

	var antes := ProductionModel.new()
	antes.load_dict(guardado)
	antes.add_occupation(_hacheros)
	antes.add_station(_azul())
	antes.add_station(_olavarria())
	antes.add_station(_sierras_bayas())
	_comprobar(_lista(antes.get_families(&"azul")) == _lista(modelo.get_families(&"azul")) and antes.get_level(&"azul") == 2, "Cargado antes de registrar: Azul conserva nivel y familias")
	_comprobar(antes.count_families(&"sierras_bayas", &"canteros") == 3, "No duplica el cupo y conserva la familia de recompensa")
	_comprobar(antes.get_player_slots(&"azul") == 0 and _lista(antes.get_player_families(&"azul")) == "tamberos", "La familia del jugador sigue siendo suya")

	var despues: ProductionModel = _modelo_hito()
	despues.load_dict(guardado)
	_comprobar(_lista(despues.get_families(&"azul")) == _lista(modelo.get_families(&"azul")) and despues.count_families(&"sierras_bayas", &"canteros") == 3, "Cargado después de registrar: mismas familias")

	var viejo := ProductionModel.new()
	viejo.load_dict({"levels": {"sierras_bayas": 1}})
	viejo.add_station(_sierras_bayas())
	_comprobar(viejo.count_families(&"sierras_bayas", &"canteros") == 2, "Un guardado sin familias completa el cupo")


# --- Ayudas ---


func _modelo_hito() -> ProductionModel:
	var modelo := ProductionModel.new()
	modelo.add_occupation(_hacheros)
	modelo.add_station(_azul())
	modelo.add_station(_olavarria())
	modelo.add_station(_sierras_bayas())
	return modelo


func _azul() -> StationData:
	return _estacion(&"azul", StationData.StationType.TOWN, _sierras, [&"monte", &"campo"], [0, 2, 0])


func _olavarria() -> StationData:
	return _estacion(&"olavarria", StationData.StationType.CITY, _sierras, [&"horno"], [2, 1, 0, 0])


func _sierras_bayas() -> StationData:
	return _estacion(&"sierras_bayas", StationData.StationType.FREIGHT, _sierras, [&"cantera"], [2, 2])


# Una estación con un nivel por cada cupo de familias (días para crecer: 1, sin consumo propio).
func _estacion(id: StringName, tipo: StationData.StationType, bioma: BiomeData, rasgos: Array, cupos: Array) -> StationData:
	var datos := StationData.new()
	datos.id = id
	datos.display_name = String(id).capitalize()
	datos.type = tipo
	datos.biome = bioma
	datos.traits.assign(rasgos)
	var niveles: Array[StationLevelData] = []
	for cupo: int in cupos:
		var nivel := StationLevelData.new()
		nivel.days_to_grow = 1
		nivel.families = cupo
		niveles.append(nivel)
	datos.levels = niveles
	return datos


# entradas: [[ItemData, cantidad], ...]
func _oficio(id: StringName, tipo: OccupationData.Kind, insumos: Array, produce: Array, rasgo: StringName) -> OccupationData:
	var oficio := OccupationData.new()
	oficio.id = id
	oficio.display_name = String(id)
	oficio.kind = tipo
	oficio.requires_trait = rasgo
	for par: Array in insumos:
		oficio.needs.append(_cantidad(par[0], par[1]))
	for par: Array in produce:
		oficio.produces.append(_cantidad(par[0], par[1]))
	return oficio


func _objeto(id: StringName, nombre: String) -> ItemData:
	var objeto := ItemData.new()
	objeto.id = id
	objeto.display_name = nombre
	return objeto


func _cantidad(objeto: ItemData, unidades: int) -> ItemAmount:
	var cantidad := ItemAmount.new()
	cantidad.item = objeto
	cantidad.amount = unidades
	return cantidad


func _dic(valores: Dictionary) -> Dictionary[StringName, int]:
	var resultado: Dictionary[StringName, int] = {}
	for clave: StringName in valores:
		resultado[clave] = int(valores[clave])
	return resultado


func _lista(ids: Array[StringName]) -> String:
	var textos: PackedStringArray = []
	for id: StringName in ids:
		textos.append(String(id))
	return ", ".join(textos)


func _comprobar(ok: bool, texto: String) -> void:
	if ok:
		print("  OK  ", texto)
	else:
		_fallos += 1
		push_error("  FALLA  " + texto)
