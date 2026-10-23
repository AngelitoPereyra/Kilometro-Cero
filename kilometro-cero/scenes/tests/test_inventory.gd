extends Node3D
## Prueba de la interfaz del inventario (tarea 49, D72): pasar de una ranura a la mano,
## cambiar lo de la mano por una ranura, guardar la mano, mochila llena, y que abrir
## el inventario pause el reloj y apague los controles. Las comprobaciones corren
## solas al empezar; después queda la mochila cargada para probar a mano con TAB o G.

const CONTROLES: String = "TAB o G: inventario · WASD: caminar · E: recolectar · Q: soltar"
## Ranuras de la mochila de prueba: chica, para llegar fácil a "llena".
const RANURAS_DE_PRUEBA: int = 4

@onready var _player: Player = $Player
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0
var _grabber: Grabber
var _ui: InventoryUI
var _mochila: Inventory


func _ready() -> void:
	_probar_textos()
	_probar_lugar_tras_sacar()
	# Un cuadro de física: el Player ya armó todo y los objetos pueden entrar al mundo.
	await get_tree().physics_frame
	_grabber = _player.get_node_or_null("Grabber") as Grabber
	_ui = _player.get_node_or_null("InventoryUI") as InventoryUI
	_mochila = _player.get_backpack()
	_comprobar(_grabber != null and _ui != null and _mochila != null, "El Player tiene Grabber, InventoryUI y mochila")
	if _grabber != null and _ui != null and _mochila != null:
		_usar_mochila_de_prueba()
		_probar_ranura_a_mano()
		_probar_mochila_llena()
		_probar_abrir_y_cerrar()

	if _fallos == 0:
		print("Inventario: todas las comprobaciones pasaron.")
	else:
		push_error("Inventario: fallaron %d comprobaciones." % _fallos)
	_dejar_listo_para_jugar()


func _process(_delta: float) -> void:
	var reloj: String = "corre" if GameState.clock_running else "pausado"
	_hud.text = "Día %d, %s (reloj %s)\n%s" % [
		GameState.clock.current_day,
		GameClock.format_time(GameState.clock.time_of_day),
		reloj,
		CONTROLES,
	]


func _probar_textos() -> void:
	var tabla := _crear_item(&"tabla", ItemData.SizeClass.MEDIUM)
	_comprobar(InventoryUI.slot_text(null) == "", "Ranura vacía: sin texto")
	_comprobar(InventoryUI.slot_text(ItemStack.new(tabla, 1)) == "tabla", "Una unidad: solo el nombre (sin nombre visible, usa el id)")
	tabla.display_name = "Tabla"
	_comprobar(InventoryUI.slot_text(ItemStack.new(tabla, 7)) == "Tabla\nx7", "Varias unidades: nombre y cantidad")
	_comprobar(InventoryUI.slot_text(ItemStack.new(tabla, 1, 0.5)) == "Tabla\n50 %", "Con durabilidad: el porcentaje")
	_comprobar(InventoryUI.failure_text(&"no_room") != "", "no_room tiene mensaje")
	_comprobar(InventoryUI.failure_text(&"nothing_near") == "", "Los motivos que no son del inventario no se muestran")


# Inventory.can_store_amount_after_take: simula sin tocar nada.
func _probar_lugar_tras_sacar() -> void:
	var inv := _crear_inventario(2, 5, 3)
	var cambios: Array[int] = [0]
	inv.slots_changed.connect(func() -> void: cambios[0] += 1)
	var tornillo := _crear_item(&"test_tornillo", ItemData.SizeClass.SMALL)
	var tabla := _crear_item(&"test_tabla", ItemData.SizeClass.MEDIUM)
	var hacha := _crear_item(&"test_hacha", ItemData.SizeClass.MEDIUM)
	inv.try_store(ItemStack.new(tornillo, 5))   # ranura 0: tornillos x5 (llena)
	inv.try_store(ItemStack.new(tabla, 1))      # ranura 1: tabla x1
	cambios[0] = 0

	_comprobar(inv.can_store_amount(ItemStack.new(hacha, 1, 1.0)) == 0, "Llena: un hacha no entra")
	_comprobar(inv.can_store_amount_after_take(ItemStack.new(hacha, 1, 1.0), 1, 1) == 1, "Si se saca la única tabla, el hacha entra en esa ranura")
	_comprobar(inv.can_store_amount_after_take(ItemStack.new(hacha, 1, 1.0), 0, 1) == 0, "Si se saca un tornillo de cinco, la ranura sigue ocupada")
	_comprobar(inv.can_store_amount_after_take(ItemStack.new(tornillo, 3), 0, 1) == 1, "Del mismo tipo: entra la unidad que se sacó")
	_comprobar(inv.can_store_amount_after_take(ItemStack.new(tabla, 5), 1, 1) == 3, "Ranura liberada: entra un tope entero de medianos")
	_comprobar(inv.peek(0).quantity == 5 and inv.peek(1).quantity == 1, "La simulación deja las ranuras como estaban")
	_comprobar(cambios[0] == 0, "La simulación no emite slots_changed")
	inv.free()


func _probar_ranura_a_mano() -> void:
	var tabla := _crear_item(&"tabla", ItemData.SizeClass.MEDIUM)
	var ramitas := _crear_item(&"ramitas", ItemData.SizeClass.SMALL)
	_mochila.try_store(ItemStack.new(tabla, 2))     # ranura 0
	_mochila.try_store(ItemStack.new(ramitas, 10))  # ranura 1
	var manos: Hands = _player.get_hands()

	_comprobar(_grabber.take_from_backpack(0), "Clic en la tabla: pasa a la mano")
	_comprobar(not manos.is_empty() and manos.get_held().item.id == &"tabla" and manos.get_held().quantity == 1, "En la mano hay UNA tabla")
	_comprobar(_mochila.count_of(&"tabla") == 1, "En la mochila queda una tabla")
	_comprobar(_grabber.get_held_item() != null and _grabber.get_held_item().is_inside_tree(), "La tabla de la mano existe en el mundo")

	_comprobar(_grabber.take_from_backpack(1), "Clic en las ramitas con la tabla en la mano: se cambian")
	_comprobar(manos.get_held().item.id == &"ramitas", "Ahora en la mano hay ramitas")
	_comprobar(_mochila.count_of(&"tabla") == 2 and _mochila.count_of(&"ramitas") == 9, "La tabla volvió a la mochila (2) y quedan 9 ramitas")

	_comprobar(_grabber.stow_held(), "Clic en la mano: se guarda")
	_comprobar(manos.is_empty() and _mochila.count_of(&"ramitas") == 10, "Mano vacía y vuelven a ser 10 ramitas")
	_comprobar(not _grabber.stow_held(), "Con la mano vacía no hay nada que guardar")

	var vacia: int = _mochila.get_slot_count() - 1
	_comprobar(not _grabber.take_from_backpack(vacia), "Una ranura vacía no da nada")
	_vaciar_mochila()


# Mochila de 4 ranuras llena con 4 tipos; en la mano, un quinto tipo.
func _probar_mochila_llena() -> void:
	var limite: int = _mochila.stack_limit_of(_crear_item(&"x", ItemData.SizeClass.SMALL))
	_mochila.try_store(ItemStack.new(_crear_item(&"caja", ItemData.SizeClass.MEDIUM), 1))  # ranura 0: x1
	for i: int in 3:
		_mochila.try_store(ItemStack.new(_crear_item(StringName("lleno_%d" % i), ItemData.SizeClass.SMALL), limite))
	_comprobar(_mochila.get_used_slot_count() == 4, "Mochila de prueba llena (4 de 4)")
	var motivos: Array[StringName] = []
	_grabber.grab_failed.connect(func(motivo: StringName) -> void: motivos.append(motivo))

	# La caja sale a la mano y su ranura se ocupa con otra cosa: queda llena otra vez.
	_comprobar(_grabber.take_from_backpack(_ranura_de(&"caja")), "La caja pasa a la mano")
	_mochila.try_store(ItemStack.new(_crear_item(&"suelto", ItemData.SizeClass.MEDIUM), 1))
	_comprobar(_mochila.get_alert() == Inventory.Alert.FULL, "Con la caja en la mano, la mochila vuelve a estar llena")

	var antes: int = _mochila.count_of(&"lleno_0")
	_comprobar(not _grabber.take_from_backpack(_ranura_de(&"lleno_0")), "Llena: no se cambia la caja por una unidad de una pila que no se vacía")
	_comprobar(motivos.has(&"no_room"), "Avisa no_room")
	_comprobar(_mochila.count_of(&"lleno_0") == antes and _player.get_hands().get_held().item.id == &"caja", "Y no cambió nada")
	_comprobar(not _grabber.stow_held(), "Llena: la caja no se puede guardar")

	_comprobar(_grabber.take_from_backpack(_ranura_de(&"suelto")), "Llena: sí se cambia por la única unidad de una ranura (deja su lugar)")
	_comprobar(_player.get_hands().get_held().item.id == &"suelto" and _mochila.count_of(&"caja") == 1, "La caja quedó en esa ranura")
	_vaciar_mochila()
	_grabber.stow_held()
	_vaciar_mochila()


func _probar_abrir_y_cerrar() -> void:
	GameState.clock_running = true
	_ui.set_open(true)
	_comprobar(_ui.is_open() and _ui.visible, "set_open(true) muestra el inventario")
	_comprobar(not GameState.clock_running, "Abierto, el reloj está pausado (D72)")
	_comprobar(not _player.controls_enabled, "Abierto, el jugador no se mueve ni actúa")
	_comprobar(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Abierto, el mouse queda libre")

	_mochila.try_store(ItemStack.new(_crear_item(&"tabla", ItemData.SizeClass.MEDIUM), 3))
	_comprobar(_ui.get_slot_button_text(0) == "tabla\nx3", "La ranura muestra \"tabla x3\"")
	_ui.press_slot(0)
	_comprobar(_ui.get_hand_text() == "tabla" and _ui.get_slot_button_text(0) == "tabla\nx2", "Clic en la ranura: la mano muestra la tabla y la ranura x2")
	_ui.press_slot(1)
	_comprobar(_ui.get_status_text() != "", "Clic en una ranura vacía: aparece un aviso")
	_ui.press_hand()
	_comprobar(_ui.get_hand_text() == "vacía", "Clic en la mano: queda vacía")

	_ui.set_open(false)
	_comprobar(not _ui.is_open() and not _ui.visible, "set_open(false) lo oculta")
	_comprobar(GameState.clock_running, "Cerrado, el reloj vuelve a correr")
	_comprobar(_player.controls_enabled, "Cerrado, vuelven los controles")

	GameState.clock_running = false
	_ui.set_open(true)
	_ui.set_open(false)
	_comprobar(not GameState.clock_running, "Si el reloj ya estaba pausado, al cerrar sigue pausado")
	GameState.clock_running = true
	_vaciar_mochila()


func _usar_mochila_de_prueba() -> void:
	var datos := BackpackData.new()
	datos.slot_count = RANURAS_DE_PRUEBA
	if _player.backpack_data != null:
		datos.small_stack_limit = _player.backpack_data.small_stack_limit
		datos.medium_stack_limit = _player.backpack_data.medium_stack_limit
	_mochila.setup(datos)


func _dejar_listo_para_jugar() -> void:
	if _mochila == null:
		return
	if _player.backpack_data != null:
		_mochila.setup(_player.backpack_data)
	_mochila.try_store(ItemStack.new(_crear_item(&"ramitas", ItemData.SizeClass.SMALL), 12))
	_mochila.try_store(ItemStack.new(_crear_item(&"bulones", ItemData.SizeClass.SMALL), 40))
	_mochila.try_store(ItemStack.new(_crear_item(&"tabla", ItemData.SizeClass.MEDIUM), 3))
	_mochila.try_store(ItemStack.new(_crear_item(&"hacha", ItemData.SizeClass.MEDIUM), 1, 0.8))


func _ranura_de(id: StringName) -> int:
	for i: int in _mochila.get_slot_count():
		var actual: ItemStack = _mochila.peek(i)
		if actual != null and actual.item.id == id:
			return i
	return -1


func _vaciar_mochila() -> void:
	for i: int in _mochila.get_slot_count():
		var actual: ItemStack = _mochila.peek(i)
		if actual != null:
			_mochila.take(i, actual.quantity)


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


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
