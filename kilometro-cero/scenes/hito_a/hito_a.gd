extends Node3D
## El Hito A (tarea 62.3, D77 y D119): Azul --(o_a, cortado por un árbol caído)-- Olavarría
## --(o_s)-- Sierras Bayas --(s_c, desvío cortado por piedras)-- cantera vieja, en la Línea del
## Sud. El texto de arriba es provisorio hasta la interfaz de la tarea 67.
## Tarea 62.4 (D120, después de la primera partida de Batmi): los flujos empiezan el día siguiente
## de cumplida la misión (la primera entrega es la del jugador) y los trenes automáticos se guardan
## entre viaje y viaje (TrenesAutomaticos.park_hidden).
## Tarea 62.5 (D121, prueba de Batmi para darle más uso a las herramientas): arranca solo con la
## locomotora en la principal de Olavarría (en la escena está en o_s y se pasa a la estación al
## empezar), encerrada por dos árboles caídos (grupo troncos_olavarria, en o_a y en o_s). Don
## Ernesto, el jefe de estación, da "La vía tapada" y el hacha. Los vagones son regalos vacíos
## (WagonGift) que carga el jugador: una plataforma en Azul al despejar o_a (troncos del monte),
## otra en Sierras Bayas al cumplir la de los troncos (piedra con el pico de Azul) y un vagón
## cerrado en Olavarría al cumplir la de la piedra (cemento).
## Tarea 62.6 (D122): mesa giratoria en la punta libre de Azul (Azul/Vias.turntable) y la T adelanta
## el reloj hasta un poco antes de la próxima salida de un tren automático (sin trenes, hasta las
## 7 del día siguiente) en vez de sumar un día entero.
## Tarea 62.7 (D123): el jugador guarda solo en la mochila lo que levanta (Player/Grabber
## .prefer_backpack) y con Q y la mano vacía junto al vagón le pasa la mochila; la piedra se
## pica con el pico (en Azul, con una marca arriba que se apaga al levantarlo).
## Tarea 62.8 (D124): pantalla lo más limpia posible, con carteles chicos sobre fondo oscuro:
## arriba a la izquierda día, hora y plata; a la izquierda al medio "TAB: Inventario" y
## "H: Teclas" (H abre la lista de teclas, una por renglón); arriba a la derecha la misión que
## sigue (un paso por renglón) y los regalos sin enganchar; abajo al centro lo que hay cerca para
## la F y el último aviso. Lo demás va a la pestaña Agenda del TAB y la carga, a la pestaña Tren.
## Tarea 62b.3 (D127, D128): las principales se avisan a quien las da (Don Ernesto en Olavarría,
## Doña Clara en Azul, Ramírez en Sierras Bayas: MissionGiver.main_station) y la primera carga la
## trae el Ferrocarril; si el camino tiene un tramo que abrió el jugador sin estrenar, en un tren
## prestado que maneja el jugador (TrenesPrestados). Se sacaron los regalos de vagón de Sierras
## Bayas y Olavarría (eran para las primeras cargas); queda la plataforma de Azul.

const CONTROLES: String = "WASD: caminar\nE: agarrar (va a la mochila)\nClic: golpear (hacha, pico)\nQ con la mano vacía junto al vagón: pasarle la mochila\nF: cabina, tablero, mercado, taller o hablar\nO: puertas del coche (en la cabina)\nT: hasta la próxima salida de un tren\nTAB: inventario\nH: esconder las teclas"
const AYUDA: String = "TAB: Inventario\nH: Teclas"
const HUD_FONT_SIZE: int = 16
## Letra del cartel de la misión y cuántas letras entran por renglón: queda angosto y alto.
const MISSION_FONT_SIZE: int = 12
const MISSION_CHARS: int = 28
## Margen de los carteles de pantalla al borde.
const HUD_MARGIN: int = 16
## Pesos con que arranca la partida (D119): alcanzan para el cemento del coche de regalo.
const START_MONEY: int = 150
const STATIONS: Array[StringName] = [&"azul", &"olavarria", &"sierras_bayas"]
## Dónde queda la locomotora en la principal de Olavarría: metros al norte del centro del andén.
const START_AHEAD: float = 12.0
## Con la T el reloj queda esto (horas) antes de la próxima salida, para verla.
const SKIP_BEFORE_HOURS: float = 0.25
## Sin trenes automáticos, la T lleva a esta hora del día siguiente.
const SKIP_MORNING_HOUR: float = 7.0

@onready var _player: Player = $Player
@onready var _loco: Vehicle = $OlavarriaSierrasBayas/Locomotive
@onready var _olavarria: Station = $Olavarria
@onready var _taller: CoachGift = $Olavarria/Taller
@onready var _hud: Label = $Hud/Label
@onready var _pico: Node3D = $Pico
@onready var _marca_pico: Label3D = $MarcaPico

## Último aviso de la mochila y hasta cuándo se muestra (segundos de Time).
var _aviso: String = ""
var _aviso_hasta: float = 0.0
var _mostrar_teclas: bool = false
# Los otros carteles de pantalla (los arma _armar_hud): las teclas a la izquierda al medio, la
# misión arriba a la derecha y abajo al centro lo que hay cerca para la F y el último aviso.
var _hud_teclas: Label
var _hud_mision: Label
var _hud_abajo: Label


func _ready() -> void:
	if GameState.money < START_MONEY:
		GameState.add_money(START_MONEY - GameState.money)
	GameState.missions.flows_start_next_day = true
	var agarrador: Grabber = null
	for hijo: Node in _player.get_children():
		if hijo is Grabber:
			agarrador = hijo as Grabber
	if agarrador != null:
		agarrador.prefer_backpack = true
		agarrador.backpack_unloaded.connect(func(cantidad: int) -> void: _avisar("Pasaste %d de la mochila al vagón" % cantidad))
		agarrador.grab_failed.connect(func(motivo: StringName) -> void: _avisar(InventoryUI.failure_text(motivo)))
	for hijo: Node in _player.get_children():
		if hijo is InventoryUI:
			(hijo as InventoryUI).agenda_extra = _renglones_de_agenda
	_armar_hud()
	# Las vías de estación y el acople de los vagones se arman diferidos.
	for _i: int in 3:
		await get_tree().physics_frame
	_poner_tren_en_la_ciudad()


# Pasa el tren a la vía principal de Olavarría, con la locomotora mirando hacia Azul (+Z).
func _poner_tren_en_la_ciudad() -> void:
	var vias := _olavarria.get_node_or_null(^"Vias") as StationTracks
	var principal: StationTrack = vias.get_main_track() if vias != null else null
	var camino: Path3D = principal.get_track_path() if principal != null else null
	if camino == null or camino.curve == null:
		push_warning("HitoA: no encontré la vía principal de Olavarría; el tren queda en o_s.")
		return
	var punto: Vector3 = camino.to_local(_olavarria.global_position + Vector3(0.0, 0.0, START_AHEAD))
	var avance: float = camino.curve.get_closest_offset(punto)
	var hacia_el_final: Vector3 = camino.to_global(camino.curve.sample_baked(camino.curve.get_baked_length()))
	var hacia_el_principio: Vector3 = camino.to_global(camino.curve.sample_baked(0.0))
	_loco.place_on(camino, avance, hacia_el_final.z < hacia_el_principio.z)


func _unhandled_input(event: InputEvent) -> void:
	var tecla := event as InputEventKey
	if tecla == null or not tecla.pressed or tecla.echo:
		return
	match tecla.physical_keycode:
		KEY_T:
			_adelantar_reloj()
		KEY_H:
			_mostrar_teclas = not _mostrar_teclas


# Hasta un poco antes de la próxima salida de un tren automático (tarea 62.6); sin trenes, hasta
# la mañana siguiente.
func _adelantar_reloj() -> void:
	var ahora: float = AutoTrains.now_hours()
	var autos: AutoTrains = AutoTrains.find_in(get_tree())
	var salida: float = autos.next_departure(ahora + SKIP_BEFORE_HOURS) if autos != null else INF
	var horas: float = salida - SKIP_BEFORE_HOURS - ahora
	if is_inf(salida):
		horas = GameClock.HOURS_PER_DAY - GameState.clock.time_of_day + SKIP_MORNING_HOUR
	GameState.clock.advance(maxf(horas, 0.0))


func _avisar(texto: String) -> void:
	if texto == "":
		return
	_aviso = texto
	_aviso_hasta = Time.get_ticks_msec() / 1000.0 + 4.0


func _process(_delta: float) -> void:
	if _marca_pico.visible and not is_instance_valid(_pico):
		_marca_pico.visible = false
	_hud.text = "Día %d / %s\n$%d" % [GameState.clock.current_day, GameClock.format_time(GameState.clock.time_of_day), GameState.money]
	_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, HUD_MARGIN)
	_hud_teclas.text = CONTROLES if _mostrar_teclas else AYUDA
	_hud_teclas.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, HUD_MARGIN)
	var derecha: PackedStringArray = []
	var mision: String = _mision_que_sigue()
	if mision != "":
		derecha.append(mision)
	for nodo: Node in get_tree().get_nodes_in_group(WagonGift.GROUP):
		var regalo := nodo as WagonGift
		var vagon: Wagon = regalo.get_wagon() if regalo != null else null
		if vagon != null and vagon.front == null and vagon.rear == null:
			derecha.append("%s\nesperando en la vía, engánchalo" % regalo.describe())
	var prestados: BorrowedTrains = BorrowedTrains.find_in(get_tree())
	if prestados != null:
		derecha.append_array(prestados.get_waiting_lines())
	_mostrar(_hud_mision, _envolver("\n\n".join(derecha), MISSION_CHARS), Control.PRESET_TOP_RIGHT)
	var abajo: PackedStringArray = []
	if _aviso != "" and Time.get_ticks_msec() / 1000.0 < _aviso_hasta:
		abajo.append(_aviso)
	var cerca: Interactable = Interactable.find_nearest(get_tree(), _player.global_position, _player)
	if cerca != null:
		abajo.append("F: " + cerca.get_prompt())
	if _player.is_in_cab():
		# En la cabina abajo al centro van las teclas de manejo (CabHud).
		abajo.clear()
	_mostrar(_hud_abajo, "\n".join(abajo), Control.PRESET_CENTER_BOTTOM)


# Escribe un cartel y lo pone en su lugar, achicado al texto; sin texto lo esconde.
func _mostrar(cartel: Label, texto: String, lugar: Control.LayoutPreset) -> void:
	cartel.visible = texto != ""
	if cartel.visible:
		cartel.text = texto
		cartel.set_anchors_and_offsets_preset(lugar, Control.PRESET_MODE_MINSIZE, HUD_MARGIN)


# Fondo oscuro y letra más grande para los carteles de pantalla.
func _armar_hud() -> void:
	_estilo_de_cartel(_hud)
	_hud_teclas = _nuevo_cartel("Teclas")
	_hud_mision = _nuevo_cartel("Mision")
	_hud_mision.add_theme_font_size_override(&"font_size", MISSION_FONT_SIZE)
	_hud_abajo = _nuevo_cartel("Cerca")
	_hud_abajo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


# Corta cada renglón en palabras para que no pase de `ancho` letras.
static func _envolver(texto: String, ancho: int) -> String:
	var salida: PackedStringArray = []
	for renglon: String in texto.split("\n"):
		var actual: String = ""
		for palabra: String in renglon.split(" ", false):
			if actual != "" and actual.length() + 1 + palabra.length() > ancho:
				salida.append(actual)
				actual = "  " + palabra
			else:
				actual = palabra if actual == "" else actual + " " + palabra
		salida.append(actual)
	return "\n".join(salida)


func _estilo_de_cartel(cartel: Label) -> void:
	var fondo := StyleBoxFlat.new()
	fondo.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	fondo.set_corner_radius_all(6)
	fondo.set_content_margin_all(8.0)
	cartel.add_theme_stylebox_override(&"normal", fondo)
	cartel.add_theme_font_size_override(&"font_size", HUD_FONT_SIZE)
	cartel.add_theme_constant_override(&"outline_size", 4)
	cartel.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	cartel.size = Vector2.ZERO


func _nuevo_cartel(nombre: String) -> Label:
	var cartel := Label.new()
	cartel.name = nombre
	_estilo_de_cartel(cartel)
	_hud.get_parent().add_child(cartel)
	return cartel


# La primera misión en curso con algo por hacer, en el orden de STATIONS: el título y debajo un
# paso por renglón.
func _mision_que_sigue() -> String:
	var tablero: MissionBoard = GameState.missions
	for station_id: StringName in STATIONS:
		for mision: Mission in tablero.get_active_missions(station_id):
			var pasos: PackedStringArray = tablero.get_pending_steps(mision)
			if pasos.is_empty():
				continue
			var titulo: String = tablero.get_title(mision) if mision.main else mision.data.title
			return "Ahora: %s\n• %s" % [titulo, "\n• ".join(pasos)]
	return ""


# Lo que la agenda del TAB suma en el Hito A: el coche de regalo.
func _renglones_de_agenda() -> PackedStringArray:
	var renglones: PackedStringArray = []
	var tablero: MissionBoard = GameState.missions
	var coche: PassengerTraffic.CoachState = GameState.passengers.coach_state
	if coche == PassengerTraffic.CoachState.REPAIRING and _taller != null:
		var faltan_coche: PackedStringArray = []
		for item_id: StringName in _taller.get_remaining():
			faltan_coche.append("%d %s" % [_taller.get_remaining()[item_id], tablero.name_of(item_id)])
		renglones.append("Coche de pasajeros: en el taller de Olavarría, detrás del andén (faltan %s; el cemento se compra en el mercado)" % ", ".join(faltan_coche))
	elif coche != PassengerTraffic.CoachState.NONE:
		renglones.append("Coche de pasajeros: " + PassengerTraffic.coach_state_name(coche))
	return renglones
