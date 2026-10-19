extends Node3D
## Prueba de la tarea 12 (parte 2): el jugador con mochila y carga.
## Los números se calculan a partir de los datos (capacidad, capacidad de pila), así la
## prueba no se rompe si balanceás los .tres. Corren sincrónicas dentro de _ready().
## Después de las pruebas se puede jugar: Tab cambia la carga de la mochila y el HUD
## muestra cómo cambian la velocidad y la fatiga.

const CONTROLES: String = "WASD: caminar · Mouse: cámara · E: subir/bajar · Tab: cambiar la carga de la mochila"
## Con 10, una hora de juego pasa en 6 segundos: la fatiga se nota sin esperar demasiado.
const ESCALA_DE_TIEMPO_MANUAL: float = 10.0
## Fracciones de la zona mediana que se llenan al apretar Tab: 0 %, 45 %, 70 % y 100 %.
## Con el peso unitario de _crear_item_pesado() equivalen a 0, 79, 123 y 175 % de la capacidad.
const NIVELES_DE_CARGA: Array[float] = [0.0, 0.45, 0.7, 1.0]

@onready var _player: Player = $Player
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0
var _enc: Encumbrance
var _mochila: StorageContainer
var _needs: Needs
var _item_pesado: ItemData
var _zona_mediana: int = -1
var _unidades_maximas: int = 1
var _nivel_de_carga: int = 0
var _avisos_en_bus: Array[float] = []


func _ready() -> void:
	_enc = _player.get_encumbrance()
	_mochila = _player.get_backpack()
	_needs = _player.get_needs()
	EventBus.encumbrance_changed.connect(_al_cambiar_carga_en_bus)

	_probar_mochila()
	if _item_pesado != null:
		_probar_sin_carga()
		_probar_sobrecarga_media()
		_probar_sobrecarga_maxima()
		_probar_fatiga()

	if _fallos == 0:
		print("Carga (parte 2): todas las comprobaciones pasaron.")
	else:
		push_error("Carga (parte 2): fallaron %d comprobaciones." % _fallos)
	_dejar_listo_para_jugar()


func _process(_delta: float) -> void:
	_hud.text = "Carga: %.1f / %.1f kg (%.0f %%)  ·  velocidad x%.2f (%.1f m/s)  ·  fatiga x%.2f\nFatiga %3.0f  ·  Día %d, %s\n%s" % [
		_enc.get_total_weight(),
		_enc.get_capacity(),
		_enc.get_ratio() * 100.0,
		_enc.get_speed_multiplier(),
		_player.get_walk_speed(),
		_needs.fatigue_multiplier,
		_needs.get_value(Needs.FATIGUE),
		GameState.clock.current_day,
		GameClock.format_time(GameState.clock.time_of_day),
		CONTROLES,
	]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"inventory") and _item_pesado != null:
		_nivel_de_carga = (_nivel_de_carga + 1) % NIVELES_DE_CARGA.size()
		_cargar_fraccion(NIVELES_DE_CARGA[_nivel_de_carga])


func _probar_mochila() -> void:
	var completo: bool = _enc != null and _mochila != null and _player.backpack_data != null
	_comprobar(completo, "El jugador tiene Encumbrance, mochila y una BackpackData asignada")
	if not completo:
		return
	_comprobar(_mochila.get_zone_count() == _player.backpack_data.layout.get_zone_count(), "La mochila se armó con las zonas del layout (%d)" % _mochila.get_zone_count())
	_comprobar(is_equal_approx(_enc.get_capacity(), _enc.config.base_capacity + _player.backpack_data.weight_capacity_bonus), "La capacidad es la base más el bonus de la mochila")
	_zona_mediana = _buscar_zona(ItemData.SizeClass.MEDIUM)
	_comprobar(_zona_mediana != -1, "La mochila tiene una zona mediana para la prueba")
	if _zona_mediana == -1:
		return
	_unidades_maximas = _mochila.config.stack_capacity(ItemData.SizeClass.MEDIUM)
	_item_pesado = _crear_item_pesado()


func _probar_sin_carga() -> void:
	_comprobar(is_zero_approx(_enc.get_ratio()) and is_zero_approx(_enc.get_total_weight()), "Sin carga: peso y cociente en 0")
	_comprobar(is_equal_approx(_player.get_walk_speed(), _player.walk_speed), "Sin carga camina a la velocidad base")
	_comprobar(is_equal_approx(_needs.fatigue_multiplier, 1.0), "Sin carga la fatiga no se multiplica")


func _probar_sobrecarga_media() -> void:
	_avisos_en_bus.clear()
	_cargar_fraccion(0.7)
	var cociente: float = _enc.get_ratio()
	_comprobar(cociente > _enc.config.free_ratio and cociente < _enc.config.max_ratio, "Con el 70 %% de la zona, la mochila queda entre el 100 %% y el 150 %% (%.0f %%)" % (cociente * 100.0))
	_comprobar(is_equal_approx(_player.get_walk_speed(), _player.walk_speed * _enc.config.speed_multiplier(cociente)), "Con esa carga camina más lento")
	_comprobar(is_equal_approx(_needs.fatigue_multiplier, _enc.config.fatigue_multiplier(cociente)), "Con esa carga la fatiga se multiplica")
	_comprobar(not _avisos_en_bus.is_empty() and is_equal_approx(_avisos_en_bus.back(), cociente), "El jugador emite encumbrance_changed por el EventBus con el cociente")


func _probar_sobrecarga_maxima() -> void:
	_cargar_fraccion(1.0)
	var cociente: float = _enc.get_ratio()
	_comprobar(cociente > _enc.config.max_ratio, "Con la zona llena el cociente supera el tope (%.0f %%)" % (cociente * 100.0))
	_comprobar(is_equal_approx(_player.get_walk_speed(), _player.walk_speed * _enc.config.min_speed_multiplier), "Por encima del tope la velocidad queda en el mínimo")
	_comprobar(not _enc.can_pick_up(1.0), "Con la mochila sobrecargada no se puede levantar nada más")


func _probar_fatiga() -> void:
	# La carga máxima sigue puesta: la fatiga por hora debería multiplicarse por el máximo.
	_needs.change(Needs.FATIGUE, -100.0)
	_needs.tick(1.0)
	var esperado: float = _needs.config.fatigue_gain_per_hour * _enc.config.max_fatigue_multiplier
	_comprobar(is_equal_approx(_needs.get_value(Needs.FATIGUE), esperado), "Sobrecargado, una hora de juego cansa x%.1f" % _enc.config.max_fatigue_multiplier)
	_cargar_fraccion(0.0)
	_comprobar(is_equal_approx(_needs.fatigue_multiplier, 1.0) and is_equal_approx(_player.get_walk_speed(), _player.walk_speed), "Al vaciar la mochila vuelve todo a la normalidad")


# Un objeto de prueba de tamaño mediano. Su peso hace que la zona mediana llena equivalga al
# 175 % de la capacidad (por encima del tope de 150 %), sea cual sea el balance.
func _crear_item_pesado() -> ItemData:
	var item := ItemData.new()
	item.id = &"test_ingot"
	item.size_class = ItemData.SizeClass.MEDIUM
	item.unit_weight = _enc.get_capacity() * 1.75 / float(_unidades_maximas)
	return item


# Vacía la zona mediana y la vuelve a llenar con `unidades` del objeto de prueba.
func _cargar(unidades: int) -> void:
	var actual: ItemStack = _mochila.peek(_zona_mediana)
	if actual != null:
		_mochila.take(_zona_mediana, actual.quantity)
	if unidades > 0:
		_mochila.try_store(ItemStack.new(_item_pesado, unidades))


func _cargar_fraccion(fraccion: float) -> void:
	_cargar(roundi(fraccion * _unidades_maximas))


func _buscar_zona(tipo: ItemData.SizeClass) -> int:
	for i: int in _mochila.get_zone_count():
		if _mochila.get_zone_size(i) == tipo:
			return i
	return -1


func _dejar_listo_para_jugar() -> void:
	if _item_pesado != null:
		_cargar(0)
	_needs.change(Needs.WATER, 100.0)
	_needs.change(Needs.FOOD, 100.0)
	_needs.change(Needs.FATIGUE, -100.0)
	_player.global_position = Vector3(2.0, 0.0, 0.0)
	GameState.time_scale = ESCALA_DE_TIEMPO_MANUAL


func _al_cambiar_carga_en_bus(ratio: float) -> void:
	_avisos_en_bus.append(ratio)


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
