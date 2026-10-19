extends Node3D
## Prueba de la tarea 10: GameClock, GameState, Needs y el desmayo del jugador.
## Las comprobaciones corren sincrónicas dentro de _ready(), antes del primer cuadro, así
## el reloj de GameState no avanza solo mientras se prueba.
## Al terminar se acelera el tiempo para ver cómo bajan las necesidades y cómo se desmaya
## el jugador. También se puede caminar y manejar el vehículo, como en test_player.

const CONTROLES: String = "WASD: caminar · Mouse: cámara · E: subir/bajar · Espacio: empujar · S: marcha atrás"
## Con 30, una hora de juego pasa en 2 segundos reales: el agua llega a 0 en unos 40 s.
const ESCALA_DE_TIEMPO_MANUAL: float = 30.0
const TOLERANCIA_M: float = 0.01

@onready var _player: Player = $Player
@onready var _vehicle: Vehicle = $Track/Vehicle
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0
var _dias_recibidos: Array[int] = []
var _horas_recibidas: float = 0.0
var _cambios: Array[Array] = []
var _desmayos_needs: Array[StringName] = []
var _desmayos_bus: Array[StringName] = []


func _ready() -> void:
	EventBus.need_changed.connect(_al_cambiar_necesidad)
	EventBus.player_fainted.connect(_al_desmayar_en_bus)

	_probar_reloj()
	_probar_estado_global()
	_probar_necesidades()
	_probar_desmayo_de_necesidades()
	_probar_jugador()

	if _fallos == 0:
		print("Necesidades: todas las comprobaciones pasaron.")
	else:
		push_error("Necesidades: fallaron %d comprobaciones." % _fallos)
	_dejar_listo_para_jugar()


func _process(_delta: float) -> void:
	var needs: Needs = _player.get_needs()
	_hud.text = "Día %d · %s  (tiempo x%.0f)\nAgua %3.0f · Comida %3.0f · Fatiga %3.0f\nEstado: %s\n%s" % [
		GameState.clock.current_day,
		GameClock.format_time(GameState.clock.time_of_day),
		GameState.time_scale,
		needs.get_value(Needs.WATER),
		needs.get_value(Needs.FOOD),
		needs.get_value(Needs.FATIGUE),
		Player.State.keys()[_player.state],
		CONTROLES,
	]


func _probar_reloj() -> void:
	_comprobar(is_equal_approx(GameClock.hours_per_real_second(24.0), 1.0 / 60.0), "Un día de 24 min reales: 1 hora de juego por minuto")

	var reloj := GameClock.new()
	reloj.day_started.connect(_al_empezar_dia)
	reloj.time_advanced.connect(_al_avanzar_tiempo)
	_comprobar(reloj.current_day == 1 and is_equal_approx(reloj.time_of_day, 8.0), "El reloj arranca el día 1 a las 08:00")

	_dias_recibidos.clear()
	reloj.advance(2.5)
	_comprobar(is_equal_approx(reloj.time_of_day, 10.5), "Avanzar 2.5 h: son las 10:30")
	_comprobar(is_equal_approx(_horas_recibidas, 2.5), "time_advanced informa las horas que pasaron")

	reloj.advance(17.0)
	_comprobar(reloj.current_day == 2 and is_equal_approx(reloj.time_of_day, 3.5), "Pasada la medianoche: día 2, 03:30")
	_comprobar(_dias_recibidos.size() == 1 and _dias_recibidos[0] == 2, "day_started se emite una vez, con el día 2")

	reloj.advance(50.0)
	_comprobar(reloj.current_day == 4 and is_equal_approx(reloj.time_of_day, 5.5), "Un salto de 50 h cruza dos medianoches: día 4, 05:30")
	_comprobar(_dias_recibidos.size() == 3 and _dias_recibidos[1] == 3 and _dias_recibidos[2] == 4, "day_started se emite por cada día que empieza")

	var dia: int = reloj.current_day
	var hora: float = reloj.time_of_day
	_dias_recibidos.clear()
	reloj.advance(0.0)
	reloj.advance(-3.0)
	_comprobar(reloj.current_day == dia and is_equal_approx(reloj.time_of_day, hora) and _dias_recibidos.is_empty(), "Avanzar 0 o un valor negativo no hace nada")

	_comprobar(GameClock.format_time(8.5) == "08:30", "format_time(8.5) = 08:30")
	_comprobar(GameClock.format_time(23.999) == "23:59", "format_time(23.999) = 23:59 (nunca 24:00)")


func _probar_estado_global() -> void:
	_comprobar(GameState.clock != null, "GameState tiene un reloj")
	EventBus.day_started.connect(_al_empezar_dia)
	_dias_recibidos.clear()
	var dia: int = GameState.clock.current_day
	# Cerca de la medianoche: así el salto de día se prueba con una sola hora de juego.
	GameState.clock.time_of_day = 23.5
	GameState.clock.advance(1.0)
	EventBus.day_started.disconnect(_al_empezar_dia)
	_comprobar(_dias_recibidos.size() == 1 and _dias_recibidos[0] == dia + 1, "GameState reemite day_started por el EventBus")


func _probar_necesidades() -> void:
	var needs: Needs = _crear_needs(_config_de_prueba())
	_comprobar(is_equal_approx(needs.get_value(Needs.WATER), 100.0) and is_equal_approx(needs.get_value(Needs.FOOD), 100.0) and is_zero_approx(needs.get_value(Needs.FATIGUE)), "Empieza con agua y comida al máximo y sin fatiga")

	needs.tick(2.0)
	_comprobar(is_equal_approx(needs.get_value(Needs.WATER), 90.0) and is_equal_approx(needs.get_value(Needs.FOOD), 94.0) and is_equal_approx(needs.get_value(Needs.FATIGUE), 10.0), "2 horas: agua -10, comida -6, fatiga +10")

	needs.paused = true
	needs.tick(5.0)
	needs.paused = false
	_comprobar(is_equal_approx(needs.get_value(Needs.WATER), 90.0), "En pausa, el tiempo no gasta necesidades")
	needs.fatigue_multiplier = 2.0
	var fatiga_antes: float = needs.get_value(Needs.FATIGUE)
	needs.tick(1.0)
	_comprobar(is_equal_approx(needs.get_value(Needs.FATIGUE), fatiga_antes + 10.0), "Con multiplicador 2.0, la fatiga por hora se duplica (+10)")
	needs.fatigue_multiplier = -3.0
	_comprobar(is_zero_approx(needs.fatigue_multiplier), "El multiplicador de fatiga no puede ser negativo")
	needs.fatigue_multiplier = 1.0
	needs.change(Needs.WATER, 500.0)
	_comprobar(is_equal_approx(needs.get_value(Needs.WATER), 100.0), "El valor no pasa de 100")
	needs.change(Needs.FATIGUE, -500.0)
	_comprobar(is_zero_approx(needs.get_value(Needs.FATIGUE)), "La fatiga no baja de 0")

	_cambios.clear()
	needs.change(Needs.WATER, -10.0)
	var ultimo: Array = _cambios.back() if not _cambios.is_empty() else []
	_comprobar(ultimo.size() == 2 and ultimo[0] == Needs.WATER and is_equal_approx(ultimo[1], 90.0), "need_changed se emite con la necesidad y el valor nuevo")
	_cambios.clear()
	needs.change(Needs.WATER, 0.0)
	_comprobar(_cambios.is_empty(), "Si el valor no cambia, no se emite nada")

	needs.change(Needs.FATIGUE, 40.0)
	needs.restore_fatigue()
	_comprobar(is_zero_approx(needs.get_value(Needs.FATIGUE)), "restore_fatigue deja la fatiga en 0")

	var agua_antes: float = needs.get_value(Needs.WATER)
	EventBus.time_advanced.emit(1.0)
	_comprobar(is_equal_approx(needs.get_value(Needs.WATER), agua_antes - 5.0), "Las necesidades escuchan time_advanced del EventBus")
	needs.free()


func _probar_desmayo_de_necesidades() -> void:
	_comprobar(Needs.faint_cause(50.0, 50.0, 50.0) == &"", "Con todo en orden no hay desmayo")
	_comprobar(Needs.faint_cause(0.0, 50.0, 50.0) == Needs.WATER, "Sin agua: desmayo por agua")
	_comprobar(Needs.faint_cause(50.0, 0.0, 50.0) == Needs.FOOD, "Sin comida: desmayo por comida")
	_comprobar(Needs.faint_cause(50.0, 50.0, 100.0) == Needs.FATIGUE, "Fatiga al máximo: desmayo por fatiga")
	_comprobar(Needs.faint_cause(0.0, 0.0, 100.0) == Needs.WATER, "Con varias causas, el agua tiene prioridad")

	var needs: Needs = _crear_needs(_config_de_prueba())
	_desmayos_needs.clear()
	needs.change(Needs.WATER, -100.0)
	_comprobar(_desmayos_needs.size() == 1 and _desmayos_needs[0] == Needs.WATER, "Con el agua en 0 se emite fainted(&\"water\")")
	needs.change(Needs.FOOD, -100.0)
	needs.change(Needs.FATIGUE, 100.0)
	_comprobar(_desmayos_needs.size() == 1, "Ya desmayado, otras necesidades en el límite no emiten un segundo desmayo")
	needs.recover_from_faint()
	_comprobar(is_equal_approx(needs.get_value(Needs.WATER), 25.0) and is_equal_approx(needs.get_value(Needs.FOOD), 25.0) and is_equal_approx(needs.get_value(Needs.FATIGUE), 50.0), "Al recuperarse: agua y comida a 25, fatiga a 50")
	needs.change(Needs.WATER, -100.0)
	_comprobar(_desmayos_needs.size() == 2, "Tras recuperarse puede volver a desmayarse")
	needs.free()


func _probar_jugador() -> void:
	var needs: Needs = _player.get_needs()
	_comprobar(needs != null, "El jugador tiene un nodo Needs")
	if needs == null:
		return
	_player.global_position = Vector3(2.0, 0.0, 0.0)

	# Desmayo por una necesidad, caminando.
	_desmayos_bus.clear()
	needs.change(Needs.WATER, -1000.0)
	_comprobar(_player.state == Player.State.FAINTED, "Sin agua el jugador se desmaya")
	_comprobar(_desmayos_bus.size() == 1 and _desmayos_bus[0] == Needs.WATER, "El jugador emite player_fainted(&\"water\") por el EventBus")
	_comprobar(needs.paused, "Desmayado, las necesidades quedan en pausa")
	_comprobar(not _player.try_mount(), "Desmayado no puede subir a un vehículo")
	var horas_antes: float = _horas_totales()
	_player.wake_up()
	_comprobar(_player.state == Player.State.WALKING, "Al despertar vuelve a caminar")
	_comprobar(is_equal_approx(_horas_totales() - horas_antes, needs.config.faint_hours_lost), "El desmayo cuesta %.0f horas de juego" % needs.config.faint_hours_lost)
	_comprobar(needs.get_value(Needs.WATER) >= needs.config.faint_recovery_value, "Despierta con algo de agua")
	_comprobar(not needs.paused, "Las necesidades vuelven a correr")

	# Desmayo por comida, viajando en el vehículo.
	_player.global_position = Vector3(2.0, 0.0, 0.0)
	_comprobar(_player.try_mount(), "El jugador sube al vehículo para la prueba")
	_vehicle.speed = 0.0
	needs.change(Needs.FOOD, -1000.0)
	_comprobar(_player.state == Player.State.FAINTED, "Sin comida el jugador se desmaya aunque vaya en el vehículo")
	_comprobar(_player.global_position.distance_to(_vehicle.get_dismount_position()) < TOLERANCIA_M, "Cae al costado del vehículo, no sobre él")
	_comprobar(is_zero_approx(_vehicle.throttle), "El vehículo queda sin acelerador")
	_player.wake_up()

	# Accidente: bajarse a demasiada velocidad.
	_player.global_position = Vector3(2.0, 0.0, 0.0)
	_player.try_mount()
	_vehicle.speed = 5.0
	_desmayos_bus.clear()
	_player.dismount()
	_comprobar(_player.state == Player.State.FAINTED, "Bajarse a 5 m/s provoca un desmayo")
	_comprobar(_desmayos_bus.size() == 1 and _desmayos_bus[0] == &"accident", "La causa informada es 'accident'")
	_player.wake_up()


# Valores explícitos: la prueba no depende del balance que tengas en needs_config.tres.
func _config_de_prueba() -> NeedsConfig:
	var config := NeedsConfig.new()
	config.start_water = 100.0
	config.start_food = 100.0
	config.start_fatigue = 0.0
	config.water_loss_per_hour = 5.0
	config.food_loss_per_hour = 3.0
	config.fatigue_gain_per_hour = 5.0
	config.faint_hours_lost = 6.0
	config.faint_recovery_value = 25.0
	config.faint_recovery_fatigue = 50.0
	return config


func _crear_needs(config: NeedsConfig) -> Needs:
	var needs := Needs.new()
	needs.config = config
	needs.fainted.connect(_al_desmayar_needs)
	# Al entrar al árbol corre su _ready(): carga los valores iniciales y escucha el bus.
	add_child(needs)
	return needs


func _horas_totales() -> float:
	return GameState.clock.current_day * GameClock.HOURS_PER_DAY + GameState.clock.time_of_day


func _dejar_listo_para_jugar() -> void:
	var needs: Needs = _player.get_needs()
	needs.change(Needs.WATER, 100.0)
	needs.change(Needs.FOOD, 100.0)
	needs.change(Needs.FATIGUE, -100.0)
	_vehicle.throttle = 0.0
	_vehicle.speed = 0.0
	_vehicle.progress = 0.0
	_player.global_position = Vector3(2.0, 0.0, 0.0)
	GameState.time_scale = ESCALA_DE_TIEMPO_MANUAL


func _al_empezar_dia(day: int) -> void:
	_dias_recibidos.append(day)


func _al_avanzar_tiempo(hours: float) -> void:
	_horas_recibidas = hours


func _al_cambiar_necesidad(need: StringName, value: float) -> void:
	_cambios.append([need, value])


func _al_desmayar_needs(cause: StringName) -> void:
	_desmayos_needs.append(cause)


func _al_desmayar_en_bus(cause: StringName) -> void:
	_desmayos_bus.append(cause)


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
