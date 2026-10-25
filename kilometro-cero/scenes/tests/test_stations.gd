extends Node3D
## Prueba de la tarea 56: estaciones (Station) con sus datos (StationData, StationLevelData,
## ItemAmount): producción y consumo por nivel, servicios, nodos por nivel y la zona que avisa
## los trenes detenidos y al jugador.
## ciudad --(a_b)-- pueblo --(b_c)-- maderera, con las tres plantillas de scenes/stations/.
## Primero corre las comprobaciones (tarda un par de segundos) y después vuelve a cargar la
## escena limpia para jugar.

const CONTROLES: String = "WASD: caminar · F: cabina · N: sube el nivel del pueblo · B: lo baja\nManejá el tren hasta el pueblo y la maderera: al frenar en una estación se avisa."
const LOG_PATH: String = "res://data/items/log.tres"

## Ya se corrieron las comprobaciones: al recargar la escena queda solo para jugar.
static var _probado: bool = false

@onready var _ida: Path3D = $Ida
@onready var _loco: Vehicle = $Ida/Locomotive
@onready var _flatcar: Wagon = $Ida/Flatcar
@onready var _ciudad: Station = $Ciudad
@onready var _pueblo: Station = $Pueblo
@onready var _maderera: Station = $Maderera
@onready var _player: Player = $Player
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0
var _niveles: Array = []
var _paradas: Array = []
var _estaciones_jugador: Array[StringName] = []
var _estacion_jugador: StringName = &""
var _mensaje: String = ""


func _ready() -> void:
	EventBus.station_level_changed.connect(func(id: StringName, nivel: int) -> void: _niveles.append([id, nivel]))
	EventBus.train_stopped_at_station.connect(_on_train_stopped)
	EventBus.player_station_changed.connect(_on_player_station_changed)
	if _probado:
		return
	_probado = true
	_probar_datos()
	_probar_archivos()
	# Las estaciones miran la red de forma diferida y la zona necesita pasos de física.
	await _esperar_fisica(3)
	await _probar_escena()

	if _fallos == 0:
		print("Estaciones: todas las comprobaciones pasaron.")
	else:
		push_error("Estaciones: fallaron %d comprobaciones." % _fallos)
	get_tree().reload_current_scene.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	var tecla := event as InputEventKey
	if tecla == null or not tecla.pressed or tecla.echo:
		return
	if tecla.physical_keycode == KEY_N:
		_pueblo.set_level(_pueblo.level + 1)
	elif tecla.physical_keycode == KEY_B:
		_pueblo.set_level(_pueblo.level - 1)


func _process(_delta: float) -> void:
	var lineas: PackedStringArray = []
	for estacion: Station in [_ciudad, _pueblo, _maderera]:
		lineas.append("%s · trenes: %d%s" % [estacion.describe(), estacion.get_trains_present().size(), " (detenido)" if estacion.has_stopped_train() else ""])
	var aca: String = "en ninguna estación"
	var estacion_actual: Station = Station.find(get_tree(), _estacion_jugador) if _estacion_jugador != &"" else null
	if estacion_actual != null:
		aca = "en %s · produce %s · consume %s · para crecer %s · mercado %s · taller %s" % [
			estacion_actual.get_display_name(), _texto(estacion_actual.get_production()), _texto(estacion_actual.get_consumption()),
			_texto(estacion_actual.get_growth_needs()), "sí" if estacion_actual.has_market() else "no", "sí" if estacion_actual.has_workshop() else "no",
		]
	_hud.text = "%s\n%s\nJugador: %s · tren %.0f km/h\n%s" % [CONTROLES, "\n".join(lineas), aca, absf(_loco.speed) * 3.6, _mensaje]


func _probar_datos() -> void:
	var tronco: ItemData = load(LOG_PATH)
	var piedra := ItemData.new()
	piedra.id = &"stone"
	piedra.display_name = "piedra"

	_comprobar(Station.level_of_node("Nivel2") == 2 and Station.level_of_node("Nivel10") == 10 and Station.level_of_node("Casas") == 1, "El número del nodo dice desde qué nivel se ve")
	var suma: Dictionary[StringName, int] = ItemAmount.sum_by_id([_cantidad(tronco, 3), _cantidad(piedra, 2), _cantidad(tronco, 4), null] as Array[ItemAmount])
	_comprobar(suma == ({&"log": 7, &"stone": 2} as Dictionary[StringName, int]), "Las cantidades se suman por objeto")
	_comprobar(_cantidad(tronco, 15).describe() == "15 tronco", "Texto de una cantidad")

	var vacia := StationData.new()
	vacia.id = &"x"
	vacia.display_name = "X"
	_comprobar(vacia.get_max_level() == 1 and vacia.clamp_level(5) == 1 and not vacia.can_grow(1), "Sin niveles: uno solo y no crece")
	_comprobar(vacia.get_production(1).is_empty() and vacia.get_growth_needs(1).is_empty() and not vacia.has_market(1), "Sin niveles no produce ni consume")
	_comprobar(vacia.validate().is_empty(), "Una estación mínima es válida")

	var datos := StationData.new()
	datos.id = &"prueba"
	datos.display_name = "Prueba"
	datos.production = [_cantidad(tronco, 5)] as Array[ItemAmount]
	datos.levels = [
		_nivel([_cantidad(tronco, 10)], [], false, false),
		_nivel([_cantidad(piedra, 4)], [_cantidad(tronco, 3), _cantidad(piedra, 1)], true, false),
		_nivel([], [], false, true),
	] as Array[StationLevelData]
	_comprobar(datos.get_max_level() == 3 and datos.clamp_level(0) == 1 and datos.clamp_level(7) == 3, "El nivel queda entre 1 y el máximo")
	_comprobar(datos.can_grow(2) and not datos.can_grow(3), "En el último nivel ya no crece")
	_comprobar(datos.get_production(1) == ({&"log": 5} as Dictionary[StringName, int]), "Nivel 1: produce la base")
	_comprobar(datos.get_production(2) == ({&"log": 8, &"stone": 1} as Dictionary[StringName, int]), "Nivel 2: la base más lo extra")
	_comprobar(datos.get_growth_needs(1) == ({&"log": 10} as Dictionary[StringName, int]) and datos.get_growth_needs(2) == ({&"stone": 4} as Dictionary[StringName, int]), "Para crecer pide el consumo nuevo de su nivel")
	_comprobar(datos.get_growth_needs(3).is_empty(), "En el último nivel no pide nada para crecer")
	_comprobar(datos.get_consumption(2) == ({&"log": 10, &"stone": 4} as Dictionary[StringName, int]), "Lo cubierto se sigue consumiendo")
	_comprobar(not datos.has_market(1) and datos.has_market(2) and datos.has_market(3), "El mercado abre en el nivel 2 y sigue abierto")
	_comprobar(not datos.has_workshop(2) and datos.has_workshop(3), "El taller abre en el nivel 3")
	_comprobar(datos.find_item(&"stone") == piedra and datos.find_item(&"nada") == null, "Encuentra los objetos de sus datos")
	_comprobar(datos.validate().is_empty(), "Los datos de prueba son válidos")

	var mala := StationData.new()
	mala.production = [_cantidad(tronco, 1), _cantidad(tronco, 2), _cantidad(null, 1)] as Array[ItemAmount]
	mala.levels = [null] as Array[StationLevelData]
	var problemas: PackedStringArray = mala.validate()
	_comprobar(problemas.size() == 5, "Avisa sin id, sin nombre, repetido, sin objeto y nivel vacío (%d avisos)" % problemas.size())


func _probar_archivos() -> void:
	var esperados: Dictionary = {
		"ciudad": StationData.StationType.CITY,
		"pueblo": StationData.StationType.TOWN,
		"maderera": StationData.StationType.FREIGHT,
	}
	for archivo: String in esperados:
		var datos: StationData = load("res://data/stations/%s.tres" % archivo)
		_comprobar(datos != null and datos.id == StringName(archivo) and datos.type == esperados[archivo] and datos.validate().is_empty(), "data/stations/%s.tres carga y es válido" % archivo)
	var maderera: StationData = load("res://data/stations/maderera.tres")
	_comprobar(maderera.get_production(1) == ({&"log": 15} as Dictionary[StringName, int]) and not maderera.can_grow(1), "La maderera produce 15 troncos por día")
	_comprobar(StationData.type_name(StationData.StationType.FREIGHT) == "estación de carga", "Nombre del tipo")


func _probar_escena() -> void:
	_comprobar(Station.find(get_tree(), &"pueblo") == _pueblo and Station.find(get_tree(), &"nada") == null, "Station.find encuentra por id")
	_comprobar((_pueblo.get_node("Cartel") as Label3D).text == "Pueblo", "El cartel muestra el nombre")
	_comprobar(_ciudad.is_on_network() and _pueblo.is_on_network() and _maderera.is_on_network(), "Las tres estaciones están en la red")
	var tramos: Array[StringName] = _pueblo.get_segments()
	_comprobar(tramos.size() == 2 and tramos.has(&"a_b") and tramos.has(&"b_c"), "Del pueblo salen a_b y b_c")
	_comprobar(_pueblo.describe() == "Pueblo (pueblo, nivel 1 de 3)", "Descripción: %s" % _pueblo.describe())

	# Niveles: los nodos NivelN se ven desde ese nivel; los cambios se avisan una sola vez.
	_comprobar(_visible(_pueblo, 1) and not _visible(_pueblo, 2) and not _visible(_pueblo, 3), "Nivel 1: solo se ven las casas del nivel 1")
	_niveles.clear()
	_comprobar(_pueblo.set_level(2) and _visible(_pueblo, 2) and not _visible(_pueblo, 3), "Nivel 2: aparecen sus casas")
	_comprobar(_niveles == [[&"pueblo", 2]], "El cambio de nivel se avisa por EventBus una vez")
	_comprobar(_pueblo.set_level(9) and _pueblo.level == 3 and _visible(_pueblo, 3), "No pasa del máximo")
	_comprobar(not _pueblo.set_level(3), "Poner el mismo nivel no cambia nada")
	_niveles.clear()
	EventBus.station_level_changed.emit(&"pueblo", 1)
	_comprobar(_pueblo.level == 1 and not _visible(_pueblo, 2) and _niveles.size() == 1, "Escucha el nivel que llega por EventBus sin volver a avisar")
	EventBus.station_level_changed.emit(&"ciudad", 2)
	_comprobar(_ciudad.level == 2 and _pueblo.level == 1, "Cada estación escucha solo su id")
	_comprobar(_ciudad.has_workshop() and _ciudad.has_market() and _ciudad.get_growth_needs() == ({&"log": 30} as Dictionary[StringName, int]), "Ciudad nivel 2: taller, mercado y pide 30 troncos")
	_ciudad.set_level(1)
	_comprobar(not _ciudad.has_workshop() and not _pueblo.has_market(), "Ciudad nivel 1 sin taller; pueblo nivel 1 sin mercado")

	# Zona: el tren parado en la ciudad ya avisó; al moverlo al pueblo, avisa allá.
	_comprobar(_ciudad.get_trains_present() == ([_loco] as Array[Vehicle]) and _ciudad.get_vehicles_present().has(_flatcar), "El tren (locomotora y plataforma) está en la ciudad")
	_comprobar(_paradas.has([&"ciudad", _loco]) and _ciudad.has_stopped_train(), "Se avisó que el tren está detenido en la ciudad")
	_comprobar(_pueblo.get_trains_present().is_empty(), "En el pueblo no hay trenes")
	_paradas.clear()
	_loco.place_on(_ida, 140.0)
	await _esperar_fisica(4)
	_comprobar(_ciudad.get_trains_present().is_empty() and _pueblo.get_trains_present() == ([_loco] as Array[Vehicle]), "Movido al pueblo: sale de la ciudad y entra al pueblo")
	_comprobar(_paradas == [[&"pueblo", _loco]], "Se avisó la parada en el pueblo una vez")
	await _esperar_fisica(10)
	_comprobar(_paradas.size() == 1, "Quieto no vuelve a avisar")

	# Arranca, frena sin salir de la zona: es otra parada.
	_loco.throttle = 1.0
	await _esperar_fisica(40)
	_comprobar(absf(_loco.speed) > Station.STOP_SPEED and not _pueblo.has_stopped_train(), "En marcha no cuenta como detenido")
	_loco.throttle = 0.0
	_loco.brake = 1.0
	await _esperar_fisica(60)
	_loco.brake = 0.0
	_comprobar(_pueblo.get_trains_present().has(_loco) and _paradas.size() == 2, "Al volver a frenar en el pueblo avisa otra parada")

	# Jugador: empezó en la ciudad; sale, entra al pueblo y sale.
	_comprobar(_ciudad.is_player_present() and _estacion_jugador == &"ciudad", "El jugador empieza en la ciudad")
	_player.global_position = Vector3(-40, 0.5, -90)
	await _esperar_fisica(4)
	_comprobar(not _ciudad.is_player_present() and _estacion_jugador == &"", "Sale de la ciudad")
	_estaciones_jugador.clear()
	_player.global_position = _pueblo.global_position + Vector3(-5, 0.7, 4)
	await _esperar_fisica(4)
	_comprobar(_pueblo.is_player_present() and _estaciones_jugador == [&"pueblo"], "El jugador llega al pueblo y se avisa %s" % [_estaciones_jugador])
	_player.global_position = _pueblo.global_position + Vector3(-40, 0.5, 40)
	await _esperar_fisica(4)
	_comprobar(not _pueblo.is_player_present() and _estaciones_jugador == [&"pueblo", &""], "Al irse se avisa con id vacío")


func _on_train_stopped(station_id: StringName, head: Vehicle) -> void:
	_paradas.append([station_id, head])
	var estacion: Station = Station.find(get_tree(), station_id)
	_mensaje = "El tren se detuvo en %s." % (estacion.get_display_name() if estacion != null else String(station_id))


func _on_player_station_changed(station_id: StringName) -> void:
	_estaciones_jugador.append(station_id)
	_estacion_jugador = station_id


func _visible(estacion: Station, nivel: int) -> bool:
	return (estacion.get_node("Niveles/Nivel%d" % nivel) as Node3D).visible


func _texto(cantidades: Dictionary[StringName, int]) -> String:
	if cantidades.is_empty():
		return "nada"
	var partes: PackedStringArray = []
	for id: StringName in cantidades:
		partes.append("%d %s" % [cantidades[id], id])
	return ", ".join(partes)


func _cantidad(item: ItemData, cantidad: int) -> ItemAmount:
	var resultado := ItemAmount.new()
	resultado.item = item
	resultado.amount = cantidad
	return resultado


func _nivel(necesita: Array, extra: Array, mercado: bool, taller: bool) -> StationLevelData:
	var resultado := StationLevelData.new()
	resultado.needs.assign(necesita)
	resultado.extra_production.assign(extra)
	resultado.market = mercado
	resultado.workshop = taller
	return resultado


func _esperar_fisica(pasos: int) -> void:
	for i: int in pasos:
		await get_tree().physics_frame


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
