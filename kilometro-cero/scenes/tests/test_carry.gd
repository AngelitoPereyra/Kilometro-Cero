extends Node3D
## Prueba del jugador con mochila. Desde la tarea 47 no hay peso (D86): la carga no
## cambia la velocidad. Los números salen de los datos (capacidad de pila), así la
## prueba no se rompe si balanceás los .tres. Corren sincrónicas dentro de _ready().
## Después de las pruebas se puede jugar: Tab cambia la carga de la mochila y el HUD
## muestra que la velocidad no cambia.

const CONTROLES: String = "WASD: caminar · Mouse: cámara · F: subir/bajar · Tab: cambiar la carga de la mochila"
## Fracciones de la zona mediana que se llenan al apretar Tab: 0 %, 45 %, 70 % y 100 %.
const NIVELES_DE_CARGA: Array[float] = [0.0, 0.45, 0.7, 1.0]

@onready var _player: Player = $Player
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0
var _mochila: StorageContainer
var _item_pesado: ItemData
var _zona_mediana: int = -1
var _unidades_maximas: int = 1
var _nivel_de_carga: int = 0


func _ready() -> void:
	_mochila = _player.get_backpack()

	_probar_mochila()
	if _item_pesado != null:
		_probar_sin_peso()

	if _fallos == 0:
		print("Mochila: todas las comprobaciones pasaron.")
	else:
		push_error("Mochila: fallaron %d comprobaciones." % _fallos)
	_dejar_listo_para_jugar()


func _process(_delta: float) -> void:
	var cantidad: int = 0
	if _mochila != null and _zona_mediana != -1:
		var actual: ItemStack = _mochila.peek(_zona_mediana)
		cantidad = actual.quantity if actual != null else 0
	_hud.text = "Zona mediana: %d / %d  ·  velocidad %.1f m/s\nDía %d, %s\n%s" % [
		cantidad,
		_unidades_maximas,
		_player.get_walk_speed(),
		GameState.clock.current_day,
		GameClock.format_time(GameState.clock.time_of_day),
		CONTROLES,
	]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"inventory") and _item_pesado != null:
		_nivel_de_carga = (_nivel_de_carga + 1) % NIVELES_DE_CARGA.size()
		_cargar_fraccion(NIVELES_DE_CARGA[_nivel_de_carga])


func _probar_mochila() -> void:
	var completo: bool = _mochila != null and _player.backpack_data != null
	_comprobar(completo, "El jugador tiene mochila y una BackpackData asignada")
	if not completo:
		return
	_comprobar(_mochila.get_zone_count() == _player.backpack_data.layout.get_zone_count(), "La mochila se armó con las zonas del layout (%d)" % _mochila.get_zone_count())
	_zona_mediana = _buscar_zona(ItemData.SizeClass.MEDIUM)
	_comprobar(_zona_mediana != -1, "La mochila tiene una zona mediana para la prueba")
	if _zona_mediana == -1:
		return
	_unidades_maximas = _mochila.config.stack_capacity(ItemData.SizeClass.MEDIUM)
	_item_pesado = _crear_item_pesado()


func _probar_sin_peso() -> void:
	_comprobar(is_equal_approx(_player.get_walk_speed(), _player.walk_speed), "Sin carga camina a la velocidad base")
	_cargar_fraccion(1.0)
	var lleno: ItemStack = _mochila.peek(_zona_mediana)
	_comprobar(lleno != null and lleno.quantity == _unidades_maximas, "La zona mediana se llena con %d unidades" % _unidades_maximas)
	_comprobar(is_equal_approx(_player.get_walk_speed(), _player.walk_speed), "Con la mochila llena de algo muy pesado camina igual (D86)")
	_cargar_fraccion(0.0)
	_comprobar(_mochila.peek(_zona_mediana) == null, "Al vaciarla, la zona queda vacía")


# Un objeto mediano muy pesado: antes de la tarea 47 frenaba al jugador; ahora no.
func _crear_item_pesado() -> ItemData:
	var item := ItemData.new()
	item.id = &"test_ingot"
	item.size_class = ItemData.SizeClass.MEDIUM
	item.unit_weight = 50.0
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
	_player.global_position = Vector3(2.0, 0.0, 0.0)


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
