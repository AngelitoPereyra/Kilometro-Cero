extends Node3D
## Prueba de la tarea 57: modelo de producción y consumo (ProductionModel, ProductionFlow, D79).
## Primero la lógica pura con modelos propios; después el modelo de GameState con estaciones
## de verdad (plantillas de scenes/stations/), el reloj y una red con un tramo que se corta.
## Al terminar queda el Hito A para jugar con el teclado (ver CONTROLES).

const CONTROLES: String = "D: pasa un día · 1: flujo de 10 troncos maderera → pueblo · 2: flujo de 15 troncos maderera → ciudad\nX: borra el último flujo · C: corta o abre el tramo maderera–pueblo (la ciudad queda detrás del pueblo)"
const LOG_PATH: String = "res://data/items/log.tres"
const TOWN_SCENE: String = "res://scenes/stations/town_station.tscn"
const CITY_SCENE: String = "res://scenes/stations/city_station.tscn"
const FREIGHT_SCENE: String = "res://scenes/stations/freight_station.tscn"

@onready var _hud: Label = $Hud/Label

var _fallos: int = 0
var _niveles: Array = []
var _red: RailNetwork
var _estaciones: Array[Station] = []


func _ready() -> void:
	EventBus.station_level_changed.connect(func(id: StringName, nivel: int) -> void: _niveles.append([id, nivel]))
	_probar_datos()
	_probar_reparto()
	_probar_crecimiento()
	_probar_estancamiento()
	_probar_corte()
	_probar_tope_y_set_level()
	_probar_guardado()
	_probar_archivos()
	await _probar_game_state()

	if _fallos == 0:
		print("Producción: todas las comprobaciones pasaron.")
	else:
		push_error("Producción: fallaron %d comprobaciones." % _fallos)
	_armar_juego()


func _unhandled_input(event: InputEvent) -> void:
	var tecla := event as InputEventKey
	if tecla == null or not tecla.pressed or tecla.echo:
		return
	var modelo: ProductionModel = GameState.production
	match tecla.physical_keycode:
		KEY_D:
			GameState.clock.advance(GameClock.HOURS_PER_DAY)
		KEY_1:
			modelo.add_flow(&"maderera", &"pueblo", &"log", 10)
		KEY_2:
			modelo.add_flow(&"maderera", &"ciudad", &"log", 15)
		KEY_X:
			var flujos: Array[ProductionFlow] = modelo.get_flows()
			if not flujos.is_empty():
				modelo.remove_flow(flujos.back())
		KEY_C:
			var cortado: bool = _red.is_cut(&"m_p")
			_red.set_state(&"m_p", TrackSegment.State.OPEN if cortado else TrackSegment.State.CUT)


func _process(_delta: float) -> void:
	var modelo: ProductionModel = GameState.production
	var lineas: PackedStringArray = [CONTROLES, "Día %d" % GameState.clock.current_day]
	for estacion: Station in _estaciones:
		if not is_instance_valid(estacion):
			continue
		var id: StringName = estacion.get_station_id()
		var estado: String = "no crece más"
		if estacion.get_days_to_grow() > 0:
			estado = "creciendo %d/%d días" % [estacion.get_growth_progress(), estacion.get_days_to_grow()]
			if not estacion.get_missing().is_empty():
				estado = "estancada (%d/%d días), falta %s" % [estacion.get_growth_progress(), estacion.get_days_to_grow(), _texto(estacion.get_missing())]
		lineas.append("%s · produce %s · libre %s · recibe %s · consume %s · %s" % [
			estacion.describe(), _texto(estacion.get_production()), _texto(modelo.get_free_production(id)),
			_texto(estacion.get_supply()), _texto(estacion.get_consumption()), estado,
		])
	for flujo: ProductionFlow in modelo.get_flows():
		lineas.append("Flujo %d: %s · entregó %d%s" % [flujo.id, flujo.describe(), flujo.last_delivered, "" if modelo.is_flow_connected(flujo) else " · CORTADO"])
	if _red != null:
		lineas.append("Tramo maderera–pueblo: %s" % ("cortado" if _red.is_cut(&"m_p") else "abierto"))
	_hud.text = "\n".join(lineas)


# --- Lógica pura ---


func _probar_datos() -> void:
	var datos: StationData = _pueblo_de_prueba()
	_comprobar(datos.get_days_to_grow(1) == 3 and datos.get_days_to_grow(2) == 1, "Días para crecer según el nivel (3 por defecto)")
	_comprobar(datos.get_days_to_grow(3) == 0, "En el último nivel no hay días para crecer")


func _probar_reparto() -> void:
	var modelo: ProductionModel = _modelo_hito()
	_comprobar(modelo.add_flow(&"maderera", &"nada", &"log", 5) == null, "No se crea un flujo a una estación desconocida")
	_comprobar(modelo.add_flow(&"maderera", &"maderera", &"log", 5) == null, "Ni a la misma estación")
	_comprobar(modelo.add_flow(&"maderera", &"pueblo", &"log", 0) == null, "Ni con cantidad 0")
	_comprobar(modelo.get_flows().is_empty(), "Los inválidos no quedan")

	var viejo: ProductionFlow = modelo.add_flow(&"maderera", &"pueblo", &"log", 10)
	_comprobar(viejo != null and viejo.id == 1 and viejo.describe() == "10 log de maderera a pueblo", "Flujo de 10 troncos de la maderera al pueblo")
	_comprobar(modelo.get_free_production(&"maderera") == _dic({&"log": 5}), "A la maderera le quedan 5 troncos libres")
	_comprobar(modelo.get_supply(&"pueblo") == _dic({&"log": 10}) and modelo.is_covered(&"pueblo"), "Al pueblo le llegan 10 y está cubierto")

	var nuevo: ProductionFlow = modelo.add_flow(&"maderera", &"ciudad", &"log", 15)
	_comprobar(nuevo.id == 2, "El flujo nuevo tiene id 2")
	var plan: Dictionary[int, int] = modelo.plan_deliveries()
	_comprobar(plan[1] == 10 and plan[2] == 5, "Si no alcanza, el más viejo cobra entero y el nuevo lo que queda (10 y 5)")
	_comprobar(modelo.get_free_production(&"maderera") == _dic({&"log": 0}), "Ya no queda nada libre")
	_comprobar(modelo.get_missing(&"ciudad") == _dic({&"log": 15}), "A la ciudad le faltan 15 de sus 20")
	_comprobar(modelo.get_flows_from(&"maderera").size() == 2 and modelo.get_flows_to(&"ciudad").size() == 1 and modelo.get_flows_to(&"ciudad")[0] == nuevo, "Flujos por origen y por destino")

	modelo.advance_day()
	_comprobar(viejo.last_delivered == 10 and nuevo.last_delivered == 5, "Al pasar el día cada flujo anota lo que entregó")
	_comprobar(modelo.remove_flow(viejo) and not modelo.remove_flow(viejo), "Se borra un flujo (y una sola vez)")
	_comprobar(modelo.plan_deliveries()[2] == 15, "Sin el viejo, el nuevo recibe sus 15")


func _probar_crecimiento() -> void:
	var modelo: ProductionModel = _modelo_hito()
	var avisos: Array = []
	modelo.level_changed.connect(func(id: StringName, nivel: int) -> void: avisos.append([id, nivel]))
	modelo.add_flow(&"maderera", &"pueblo", &"log", 10)
	_comprobar(modelo.is_growing(&"pueblo") and modelo.get_days_to_grow(&"pueblo") == 3, "Cubierto, el pueblo está creciendo y necesita 3 días")
	modelo.advance_days(2)
	_comprobar(modelo.get_level(&"pueblo") == 1 and modelo.get_growth_progress(&"pueblo") == 2, "A los 2 días sigue en nivel 1 con 2 días juntados")
	modelo.advance_day()
	_comprobar(modelo.get_level(&"pueblo") == 2 and modelo.get_growth_progress(&"pueblo") == 0, "Al tercer día sube al nivel 2 y vuelve a contar")
	_comprobar(avisos == [[&"pueblo", 2]], "Avisa el cambio de nivel una vez")
	_comprobar(modelo.get_consumption(&"pueblo") == _dic({&"log": 25, &"settlers": 5}) and modelo.get_missing(&"pueblo") == _dic({&"log": 15, &"settlers": 5}), "Nace el consumo nuevo: ahora pide 25 troncos y 5 colonos; le faltan 15 y los colonos")
	_comprobar(modelo.get_level(&"ciudad") == 1 and modelo.get_growth_progress(&"ciudad") == 0, "La ciudad sin flujos no avanza")
	_comprobar(modelo.get_growth_progress(&"maderera") == 0 and modelo.get_days_to_grow(&"maderera") == 0, "La maderera (un solo nivel) no crece")


func _probar_estancamiento() -> void:
	var modelo: ProductionModel = _modelo_hito()
	modelo.set_level(&"pueblo", 2)
	modelo.add_flow(&"maderera", &"pueblo", &"log", 10)
	modelo.advance_days(10)
	_comprobar(modelo.get_level(&"pueblo") == 2 and modelo.get_growth_progress(&"pueblo") == 0, "Sin cubrir todo, el pueblo se estanca en el nivel 2 (no baja)")
	_comprobar(not modelo.is_growing(&"pueblo"), "Estancado no cuenta como creciendo")
	modelo.add_flow(&"maderera", &"pueblo", &"log", 15)
	_comprobar(modelo.get_supply(&"pueblo") == _dic({&"log": 15}), "La maderera solo puede dar 15 de los 25")
	# Recibir más de lo que pide también lo cubre.
	var otro: ProductionModel = _modelo_hito()
	otro.add_flow(&"maderera", &"pueblo", &"log", 15)
	otro.advance_days(3)
	_comprobar(otro.get_level(&"pueblo") == 2, "Recibir de más también cubre")


func _probar_corte() -> void:
	var modelo: ProductionModel = _modelo_hito()
	var abierto: Array[bool] = [true]
	modelo.connection_check = func(desde: StringName, hasta: StringName) -> bool: return abierto[0] or not (desde == &"maderera" and hasta == &"pueblo")
	var al_pueblo: ProductionFlow = modelo.add_flow(&"maderera", &"pueblo", &"log", 10)
	var a_la_ciudad: ProductionFlow = modelo.add_flow(&"maderera", &"ciudad", &"log", 15)
	modelo.advance_days(2)
	_comprobar(modelo.get_growth_progress(&"pueblo") == 2 and a_la_ciudad.last_delivered == 5, "Con el tramo abierto el pueblo junta 2 días y a la ciudad le llegan 5")
	abierto[0] = false
	_comprobar(not modelo.is_flow_connected(al_pueblo) and modelo.is_flow_connected(a_la_ciudad), "Cortado el camino al pueblo, ese flujo queda sin conexión")
	modelo.advance_days(4)
	_comprobar(al_pueblo.last_delivered == 0 and modelo.get_level(&"pueblo") == 1, "El flujo cortado no entrega y el pueblo no crece")
	_comprobar(modelo.get_growth_progress(&"pueblo") == 2, "Pero no pierde los 2 días juntados")
	_comprobar(a_la_ciudad.last_delivered == 15, "La producción que no sale por el tramo cortado la usa el otro flujo")
	_comprobar(modelo.get_free_production(&"maderera") == _dic({&"log": 0}), "Lo libre sigue contando el flujo cortado (vuelve a pedir lo suyo)")
	abierto[0] = true
	modelo.advance_day()
	_comprobar(modelo.get_level(&"pueblo") == 2 and al_pueblo.last_delivered == 10 and a_la_ciudad.last_delivered == 5, "Reparado, el pueblo completa sus 3 días y crece")


func _probar_tope_y_set_level() -> void:
	var modelo := ProductionModel.new()
	var datos: StationData = _pueblo_de_prueba()
	var fuente := StationData.new()
	fuente.id = &"fuente"
	fuente.display_name = "Fuente"
	fuente.production = [_cantidad(_tronco(), 50)] as Array[ItemAmount]
	_comprobar(modelo.add_station(datos, 9) == 3, "add_station limita el nivel inicial")
	_comprobar(modelo.add_station(datos, 1) == 3, "Registrarla de nuevo conserva el nivel del modelo")
	modelo.add_station(fuente)
	modelo.add_flow(&"fuente", &"prueba", &"log", 50)
	modelo.advance_days(5)
	_comprobar(modelo.get_level(&"prueba") == 3 and modelo.get_growth_progress(&"prueba") == 0, "En el último nivel no sigue sumando días")

	var avisos: Array = []
	modelo.level_changed.connect(func(id: StringName, nivel: int) -> void: avisos.append([id, nivel]))
	_comprobar(modelo.set_level(&"prueba", 1) and avisos == [[&"prueba", 1]], "set_level cambia el nivel y avisa")
	modelo.advance_day()
	_comprobar(modelo.get_growth_progress(&"prueba") == 1, "Junta un día en el nivel 1")
	_comprobar(modelo.set_level(&"prueba", 2, false) and avisos.size() == 1, "set_level sin avisar no emite")
	_comprobar(modelo.get_growth_progress(&"prueba") == 0, "Cambiar el nivel a mano vuelve a contar los días")
	_comprobar(not modelo.set_level(&"prueba", 2) and not modelo.set_level(&"nada", 2), "Mismo nivel o estación desconocida: no cambia")
	modelo.advance_day()
	_comprobar(modelo.get_level(&"prueba") == 3, "Con days_to_grow 1, crece al día siguiente")
	_comprobar(modelo.get_station_ids() == ([&"prueba", &"fuente"] as Array[StringName]), "Lista de estaciones en el orden de registro")
	modelo.clear()
	_comprobar(modelo.get_station_ids().is_empty() and modelo.get_flows().is_empty(), "clear olvida todo")


func _probar_guardado() -> void:
	var modelo: ProductionModel = _modelo_hito()
	modelo.add_flow(&"maderera", &"pueblo", &"log", 10)
	modelo.add_flow(&"maderera", &"ciudad", &"log", 5)
	modelo.set_level(&"ciudad", 2)
	modelo.advance_days(2)
	var guardado: Dictionary = modelo.to_dict()
	var copia := ProductionModel.new()
	copia.load_dict(JSON.parse_string(JSON.stringify(guardado)))
	_comprobar(copia.get_level(&"ciudad") == 2, "El nivel cargado está antes de registrar las estaciones")
	for archivo: String in ["maderera", "pueblo", "ciudad"]:
		copia.add_station(load("res://data/stations/%s.tres" % archivo), 1)
	_comprobar(copia.get_level(&"ciudad") == 2 and copia.get_level(&"pueblo") == 1 and copia.get_growth_progress(&"pueblo") == 2, "Se recuperan los niveles y los días (pasando por JSON)")
	var flujos: Array[ProductionFlow] = copia.get_flows()
	_comprobar(flujos.size() == 2 and flujos[0].describe() == "10 log de maderera a pueblo" and flujos[1].id == 2, "Se recuperan los flujos en orden")
	_comprobar(copia.add_flow(&"maderera", &"ciudad", &"log", 1).id == 3, "Los ids nuevos siguen después de los cargados")


func _probar_archivos() -> void:
	var modelo: ProductionModel = _modelo_hito()
	_comprobar(modelo.get_production(&"maderera") == _dic({&"log": 15}) and modelo.get_consumption(&"ciudad") == _dic({&"log": 20}), "Los datos del Hito A: la maderera da 15 y la ciudad pide 20")
	modelo.add_flow(&"maderera", &"ciudad", &"log", 15)
	modelo.advance_days(10)
	_comprobar(modelo.get_level(&"ciudad") == 1 and modelo.get_missing(&"ciudad") == _dic({&"log": 5}), "Con toda la maderera, a la ciudad todavía le faltan 5")


# --- Con GameState y escenas ---


func _probar_game_state() -> void:
	GameState.reset_production()
	_niveles.clear()
	var maderera: Station = _poner_estacion(FREIGHT_SCENE, "res://data/stations/maderera.tres", Vector3(-12, 0, 0))
	var pueblo: Station = _poner_estacion(TOWN_SCENE, "res://data/stations/pueblo.tres", Vector3(0, 0, 0))
	await get_tree().process_frame
	var modelo: ProductionModel = GameState.production
	_comprobar(modelo.has_station(&"maderera") and modelo.has_station(&"pueblo"), "Las estaciones se registran solas en GameState.production")
	modelo.add_flow(&"maderera", &"pueblo", &"log", 10)
	_comprobar(pueblo.get_supply() == _dic({&"log": 10}) and pueblo.get_missing().is_empty(), "Station muestra lo que recibe y lo que le falta")

	GameState.clock.advance(GameClock.HOURS_PER_DAY * 3.0)
	_comprobar(pueblo.level == 2 and _visible(pueblo, 2), "Tres días del reloj: el pueblo sube al nivel 2 y se ven sus casas nuevas")
	_comprobar(_niveles == [[&"pueblo", 2]], "Se avisó una vez por EventBus (%s)" % [_niveles])
	_comprobar(pueblo.get_days_to_grow() == 3 and pueblo.get_growth_progress() == 0 and not pueblo.get_missing().is_empty(), "En el nivel 2 vuelve a contar y le falta abastecimiento")

	pueblo.set_level(3)
	_comprobar(modelo.get_level(&"pueblo") == 3 and _niveles.size() == 2, "Station.set_level se copia al modelo sin avisar dos veces")

	# Una estación nueva con el mismo id (escena recargada) toma el nivel del modelo.
	pueblo.queue_free()
	await get_tree().process_frame
	var otro: Station = _poner_estacion(TOWN_SCENE, "res://data/stations/pueblo.tres", Vector3(0, 0, 0))
	await get_tree().process_frame
	_comprobar(otro.level == 3, "Al volver a cargarse, la estación toma el nivel del modelo")

	# Con red: el flujo depende del tramo.
	_armar_red()
	await get_tree().process_frame
	await get_tree().process_frame
	var flujo: ProductionFlow = modelo.get_flows()[0]
	_comprobar(modelo.is_flow_connected(flujo), "Con la red y el tramo abierto, el flujo está conectado")
	_red.set_state(&"m_p", TrackSegment.State.CUT)
	_comprobar(not modelo.is_flow_connected(flujo) and otro.get_supply().is_empty(), "Con el tramo cortado no llega nada")
	_red.set_state(&"m_p", TrackSegment.State.OPEN)
	maderera.queue_free()
	otro.queue_free()
	await get_tree().process_frame


func _armar_juego() -> void:
	GameState.reset_production()
	GameState.clock_running = false
	_estaciones = [
		_poner_estacion(CITY_SCENE, "res://data/stations/ciudad.tres", Vector3(14, 0, 0)),
		_poner_estacion(TOWN_SCENE, "res://data/stations/pueblo.tres", Vector3(0, 0, 0)),
		_poner_estacion(FREIGHT_SCENE, "res://data/stations/maderera.tres", Vector3(-14, 0, 0)),
	]


# maderera --(m_p)-- pueblo --(p_c)-- ciudad. Las vías no se ven: solo arman el grafo.
func _armar_red() -> void:
	if _red != null:
		return
	_red = RailNetwork.new()
	_red.name = "Red"
	add_child(_red)
	_poner_tramo(&"m_p", &"maderera", &"pueblo", -14.0, 0.0)
	_poner_tramo(&"p_c", &"pueblo", &"ciudad", 0.0, 14.0)
	_red.rebuild()


func _poner_tramo(id: StringName, desde: StringName, hasta: StringName, x_desde: float, x_hasta: float) -> void:
	var curva := Path3D.new()
	curva.name = String(id)
	curva.curve = Curve3D.new()
	curva.curve.add_point(Vector3(x_desde, 0, 4))
	curva.curve.add_point(Vector3(x_hasta, 0, 4))
	var tramo := TrackSegment.new()
	tramo.segment_id = id
	tramo.from_station = desde
	tramo.to_station = hasta
	curva.add_child(tramo)
	add_child(curva)


func _poner_estacion(escena: String, datos: String, lugar: Vector3) -> Station:
	var estacion: Station = (load(escena) as PackedScene).instantiate()
	estacion.data = load(datos)
	estacion.position = lugar
	add_child(estacion)
	return estacion


func _modelo_hito() -> ProductionModel:
	var modelo := ProductionModel.new()
	for archivo: String in ["maderera", "pueblo", "ciudad"]:
		modelo.add_station(load("res://data/stations/%s.tres" % archivo))
	return modelo


# Tres niveles: el 1 pide 10 troncos (3 días), el 2 pide 4 más (1 día), el 3 es el último.
func _pueblo_de_prueba() -> StationData:
	var datos := StationData.new()
	datos.id = &"prueba"
	datos.display_name = "Prueba"
	var primero := StationLevelData.new()
	primero.needs = [_cantidad(_tronco(), 10)] as Array[ItemAmount]
	var segundo := StationLevelData.new()
	segundo.needs = [_cantidad(_tronco(), 4)] as Array[ItemAmount]
	segundo.days_to_grow = 1
	datos.levels = [primero, segundo, StationLevelData.new()] as Array[StationLevelData]
	return datos


func _tronco() -> ItemData:
	return load(LOG_PATH)


func _cantidad(item: ItemData, cantidad: int) -> ItemAmount:
	var resultado := ItemAmount.new()
	resultado.item = item
	resultado.amount = cantidad
	return resultado


func _dic(valores: Dictionary) -> Dictionary[StringName, int]:
	var resultado: Dictionary[StringName, int] = {}
	for clave: StringName in valores:
		resultado[clave] = valores[clave]
	return resultado


func _visible(estacion: Station, nivel: int) -> bool:
	var nodo := estacion.get_node_or_null("Niveles/Nivel%d" % nivel) as Node3D
	return nodo != null and nodo.visible


func _texto(cantidades: Dictionary[StringName, int]) -> String:
	if cantidades.is_empty():
		return "nada"
	var partes: PackedStringArray = []
	for id: StringName in cantidades:
		partes.append("%d %s" % [cantidades[id], id])
	return ", ".join(partes)


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
