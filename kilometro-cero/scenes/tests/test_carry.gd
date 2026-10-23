extends Node3D
## Prueba de la mochila de ranuras (tarea 48, D70, D86, D59). Las comprobaciones de
## lógica usan una mochila chica armada acá (4 ranuras), así no dependen de cómo
## balancees backpack_basic.tres; las del jugador leen los números de sus datos.
## Corren sincrónicas dentro de _ready(). Después se puede jugar: C llena la mochila
## del jugador al 0 %, 50 %, 75 % y 100 % de las ranuras y el HUD muestra la alerta.
## (TAB ya no sirve para esto: desde la tarea 49 abre el inventario.)

const CONTROLES: String = "WASD: caminar · Mouse: cámara · C: cambiar la carga de la mochila · TAB: inventario"
## Fracciones de ranuras que se ocupan al apretar C.
const NIVELES_DE_CARGA: Array[float] = [0.0, 0.5, 0.75, 1.0]
const NOMBRES_DE_ALERTA: Array[String] = ["normal", "casi llena", "llena"]

@onready var _player: Player = $Player
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0
var _mochila: Inventory
var _nivel_de_carga: int = 0
var _ultima_alerta_del_bus: int = -1
var _alertas_del_bus: int = 0


func _ready() -> void:
	_mochila = _player.get_backpack()
	EventBus.backpack_alert_changed.connect(_on_backpack_alert_changed)

	_probar_alerta_pura()
	_probar_ranuras()
	_probar_durabilidad()
	if _probar_mochila_del_jugador():
		_probar_alertas_del_jugador()

	if _fallos == 0:
		print("Mochila: todas las comprobaciones pasaron.")
	else:
		push_error("Mochila: fallaron %d comprobaciones." % _fallos)
	_dejar_listo_para_jugar()


func _process(_delta: float) -> void:
	var usadas: int = _mochila.get_used_slot_count() if _mochila != null else 0
	var total: int = _mochila.get_slot_count() if _mochila != null else 0
	var alerta: String = NOMBRES_DE_ALERTA[_mochila.get_alert()] if _mochila != null else "—"
	_hud.text = "Ranuras: %d / %d  ·  alerta: %s  ·  velocidad %.1f m/s\nDía %d, %s\n%s" % [
		usadas,
		total,
		alerta,
		_player.get_walk_speed(),
		GameState.clock.current_day,
		GameClock.format_time(GameState.clock.time_of_day),
		CONTROLES,
	]


func _unhandled_input(event: InputEvent) -> void:
	var tecla := event as InputEventKey
	if tecla != null and tecla.pressed and not tecla.echo and tecla.physical_keycode == KEY_C and _mochila != null:
		_nivel_de_carga = (_nivel_de_carga + 1) % NIVELES_DE_CARGA.size()
		_ocupar_fraccion(NIVELES_DE_CARGA[_nivel_de_carga])


func _probar_alerta_pura() -> void:
	var casi := Inventory.Alert.ALMOST_FULL
	_comprobar(Inventory.alert_for(0, 20, 0.75) == Inventory.Alert.NONE, "Vacía: sin alerta")
	_comprobar(Inventory.alert_for(14, 20, 0.75) == Inventory.Alert.NONE, "14 de 20 ranuras: sin alerta")
	_comprobar(Inventory.alert_for(15, 20, 0.75) == casi, "15 de 20 ranuras (75 %): casi llena")
	_comprobar(Inventory.alert_for(20, 20, 0.75) == Inventory.Alert.FULL, "20 de 20 ranuras: llena")
	_comprobar(Inventory.alert_for(0, 0, 0.75) == Inventory.Alert.NONE, "Sin ranuras: sin alerta")


# Mochila chica: 4 ranuras, pilas de 5 (pequeños) y 3 (medianos).
func _probar_ranuras() -> void:
	var inv := _crear_inventario(4, 5, 3)
	var alertas: Array = []
	inv.alert_changed.connect(func(alerta: Inventory.Alert) -> void: alertas.append(alerta))

	var tornillos := ItemStack.new(_crear_item(&"test_tornillo", ItemData.SizeClass.SMALL), 12)
	var sobra: ItemStack = inv.try_store(tornillos)
	_comprobar(sobra == null, "12 pequeños entran enteros")
	_comprobar(tornillos.quantity == 12, "El stack recibido no se modifica")
	_comprobar(inv.get_used_slot_count() == 3, "12 pequeños con tope 5 ocupan 3 ranuras (5 + 5 + 2)")
	_comprobar(inv.peek(2) != null and inv.peek(2).quantity == 2, "La tercera ranura tiene 2")
	_comprobar(alertas == [Inventory.Alert.ALMOST_FULL], "Al ocupar 3 de 4 avisa \"casi llena\" una sola vez")

	var motor := ItemStack.new(_crear_item(&"test_motor", ItemData.SizeClass.LARGE), 1)
	_comprobar(not inv.accepts(motor.item), "Un objeto grande no se acepta (D86)")
	_comprobar(inv.can_store_amount(motor) == 0, "De un grande entran 0 unidades")
	sobra = inv.try_store(motor)
	_comprobar(sobra != null and sobra.quantity == 1, "Guardar un grande devuelve todo como sobrante")

	var tablas := ItemStack.new(_crear_item(&"test_tabla", ItemData.SizeClass.MEDIUM), 5)
	_comprobar(inv.can_store_amount(tablas) == 3, "Con una ranura libre entran 3 medianos (su tope)")
	sobra = inv.try_store(tablas)
	_comprobar(sobra != null and sobra.quantity == 2, "De 5 medianos sobran 2")
	_comprobar(inv.get_alert() == Inventory.Alert.FULL, "Con las 4 ranuras ocupadas está llena")
	_comprobar(alertas == [Inventory.Alert.ALMOST_FULL, Inventory.Alert.FULL], "Avisa \"llena\" al cruzar el 100 %")

	_comprobar(inv.can_store_amount(ItemStack.new(tornillos.item, 10)) == 3, "Llena, todavía se completa la pila de 2 tornillos (entran 3)")
	_comprobar(inv.count_of(&"test_tornillo") == 12, "count_of suma todas las ranuras del mismo tipo")

	var sacado: ItemStack = inv.take(3, 10)
	_comprobar(sacado != null and sacado.quantity == 3, "take saca como mucho lo que hay en la ranura")
	_comprobar(inv.peek(3) == null, "La ranura vaciada queda libre")
	_comprobar(inv.get_alert() == Inventory.Alert.ALMOST_FULL, "Al liberar una ranura vuelve a \"casi llena\"")
	inv.take(2, 2)
	_comprobar(inv.get_alert() == Inventory.Alert.NONE, "Con 2 de 4 ranuras no hay alerta (se rearma)")
	inv.try_store(ItemStack.new(tornillos.item, 2))
	_comprobar(alertas.count(Inventory.Alert.ALMOST_FULL) == 3, "Al volver a subir avisa de nuevo")
	_comprobar(inv.take(0, 0) == null, "take con cantidad 0 no saca nada")
	inv.free()


# Las herramientas tienen durabilidad: nunca se apilan, cada una usa su ranura.
func _probar_durabilidad() -> void:
	var inv := _crear_inventario(4, 5, 3)
	var hacha := _crear_item(&"test_hacha", ItemData.SizeClass.MEDIUM)
	inv.try_store(ItemStack.new(hacha, 1, 1.0))
	inv.try_store(ItemStack.new(hacha, 1, 0.4))
	_comprobar(inv.get_used_slot_count() == 2, "Dos hachas con durabilidad usan dos ranuras")
	_comprobar(inv.peek(1) != null and is_equal_approx(inv.peek(1).durability, 0.4), "Cada hacha conserva su durabilidad")
	inv.free()


func _probar_mochila_del_jugador() -> bool:
	var completo: bool = _mochila != null and _player.backpack_data != null
	_comprobar(completo, "El jugador tiene mochila (Inventory) y una BackpackData asignada")
	if not completo:
		return false
	var datos: BackpackData = _player.backpack_data
	_comprobar(_mochila.get_slot_count() == datos.slot_count, "La mochila tiene las ranuras de sus datos (%d)" % datos.slot_count)
	_comprobar(_mochila.get_used_slot_count() == 0, "Arranca vacía")
	_comprobar(_mochila.stack_limit_of(_crear_item(&"x", ItemData.SizeClass.SMALL)) == datos.small_stack_limit, "Pilas de pequeños de %d" % datos.small_stack_limit)
	_comprobar(_mochila.stack_limit_of(_crear_item(&"x", ItemData.SizeClass.MEDIUM)) == datos.medium_stack_limit, "Pilas de medianos de %d" % datos.medium_stack_limit)
	_comprobar(is_equal_approx(_player.get_walk_speed(), _player.walk_speed), "Sin peso: camina a la velocidad base (D86)")
	return true


# El jugador reemite las alertas por el bus (D59, patrón D50).
func _probar_alertas_del_jugador() -> void:
	_alertas_del_bus = 0
	_ocupar_fraccion(1.0)
	_comprobar(_mochila.get_alert() == Inventory.Alert.FULL, "Con todas las ranuras ocupadas, la mochila del jugador está llena")
	_comprobar(_ultima_alerta_del_bus == Inventory.Alert.FULL, "El bus recibió backpack_alert_changed con \"llena\"")
	_comprobar(_alertas_del_bus == 2, "El bus avisó dos veces al llenarla (casi llena y llena)")
	_comprobar(is_equal_approx(_player.get_walk_speed(), _player.walk_speed), "Llena, camina igual (D86)")
	_ocupar_fraccion(0.0)
	_comprobar(_ultima_alerta_del_bus == Inventory.Alert.NONE, "Al vaciarla el bus vuelve a \"normal\"")


func _crear_inventario(ranuras: int, tope_chico: int, tope_mediano: int) -> Inventory:
	var datos := BackpackData.new()
	datos.slot_count = ranuras
	datos.small_stack_limit = tope_chico
	datos.medium_stack_limit = tope_mediano
	datos.almost_full_ratio = 0.75
	var inv := Inventory.new()
	inv.setup(datos)
	return inv


func _crear_item(id: StringName, size: ItemData.SizeClass) -> ItemData:
	var item := ItemData.new()
	item.id = id
	item.size_class = size
	return item


# Vacía la mochila del jugador y ocupa `fraccion` de sus ranuras, una ranura por tipo.
func _ocupar_fraccion(fraccion: float) -> void:
	for i: int in _mochila.get_slot_count():
		var actual: ItemStack = _mochila.peek(i)
		if actual != null:
			_mochila.take(i, actual.quantity)
	var ranuras: int = roundi(fraccion * _mochila.get_slot_count())
	for i: int in ranuras:
		_mochila.try_store(ItemStack.new(_crear_item(StringName("test_cosa_%d" % i), ItemData.SizeClass.SMALL), 1))


func _on_backpack_alert_changed(alerta: int) -> void:
	_ultima_alerta_del_bus = alerta
	_alertas_del_bus += 1


func _dejar_listo_para_jugar() -> void:
	if _mochila != null:
		_ocupar_fraccion(0.0)
	_player.global_position = Vector3(2.0, 0.0, 0.0)


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
