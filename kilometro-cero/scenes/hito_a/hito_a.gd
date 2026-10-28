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
## otra en Sierras Bayas al cumplir la de los troncos (piedra con la barreta de Azul) y un vagón
## cerrado en Olavarría al cumplir la de la piedra (cemento).

const CONTROLES: String = "WASD: caminar · E: agarrar · clic: golpear (hacha, barreta) · F: cabina, tablero, mercado, taller o hablar · O: puertas del coche (en la cabina)\nT: pasa un día (provisorio, para probar) · H: esconde o muestra este texto"
## Pesos con que arranca la partida (D119): alcanzan para el cemento del coche de regalo.
const START_MONEY: int = 150
const STATIONS: Array[StringName] = [&"azul", &"olavarria", &"sierras_bayas"]
## Dónde queda la locomotora en la principal de Olavarría: metros al norte del centro del andén.
const START_AHEAD: float = 12.0

@onready var _player: Player = $Player
@onready var _loco: Vehicle = $OlavarriaSierrasBayas/Locomotive
@onready var _olavarria: Station = $Olavarria
@onready var _taller: CoachGift = $Olavarria/Taller
@onready var _hud: Label = $Hud/Label


func _ready() -> void:
	if GameState.money < START_MONEY:
		GameState.add_money(START_MONEY - GameState.money)
	GameState.missions.flows_start_next_day = true
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
			GameState.clock.advance(GameClock.HOURS_PER_DAY)
		KEY_H:
			_hud.visible = not _hud.visible


func _process(_delta: float) -> void:
	if not _hud.visible:
		return
	var tablero: MissionBoard = GameState.missions
	var modelo: ProductionModel = GameState.production
	var lineas: PackedStringArray = [CONTROLES, "Día %d · %s · $%d" % [GameState.clock.current_day, GameClock.format_time(GameState.clock.time_of_day), GameState.money]]
	for station_id: StringName in STATIONS:
		if not modelo.has_station(station_id):
			continue
		var faltan: Dictionary[StringName, int] = modelo.get_missing(station_id)
		var texto: String = "%s · nivel %d de %d" % [tablero.station_name(station_id), modelo.get_level(station_id), modelo.get_data(station_id).get_max_level()]
		if modelo.get_days_to_grow(station_id) > 0 and faltan.is_empty():
			texto += " · creciendo (%d de %d días)" % [modelo.get_growth_progress(station_id), modelo.get_days_to_grow(station_id)]
		lineas.append(texto)
		for mision: Mission in tablero.get_active_missions(station_id):
			var pasos: PackedStringArray = tablero.get_pending_steps(mision)
			var titulo: String = tablero.get_title(mision) if mision.main else mision.data.title
			lineas.append("   %s%s" % [titulo, (": " + ", ".join(pasos)) if not pasos.is_empty() else ""])
	var coche: PassengerTraffic.CoachState = GameState.passengers.coach_state
	if coche == PassengerTraffic.CoachState.REPAIRING and _taller != null:
		var faltan_coche: PackedStringArray = []
		for item_id: StringName in _taller.get_remaining():
			faltan_coche.append("%d %s" % [_taller.get_remaining()[item_id], tablero.name_of(item_id)])
		lineas.append("Coche de pasajeros: en el taller de Olavarría, detrás del andén (faltan %s; el cemento se compra en el mercado)" % ", ".join(faltan_coche))
	elif coche != PassengerTraffic.CoachState.NONE:
		lineas.append("Coche de pasajeros: " + PassengerTraffic.coach_state_name(coche))
	for flujo: ProductionFlow in modelo.get_flows():
		lineas.append("Flujo: %s · entregó %d" % [flujo.describe(), flujo.last_delivered])
	for nodo: Node in get_tree().get_nodes_in_group(WagonGift.GROUP):
		var regalo := nodo as WagonGift
		var vagon: Wagon = regalo.get_wagon() if regalo != null else null
		if vagon != null and vagon.front == null and vagon.rear == null:
			lineas.append("%s · esperando en la vía, engánchalo" % regalo.describe())
	var cerca: Interactable = Interactable.find_nearest(get_tree(), _player.global_position, _player)
	if cerca != null:
		lineas.append("F: " + cerca.get_prompt())
	_hud.text = "\n".join(lineas)
