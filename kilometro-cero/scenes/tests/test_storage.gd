extends Node
## Prueba de la tarea 11: ItemStack, StorageConfig y StorageContainer.
## Es lógica pura: no hay escena 3D. Todo se arma y se comprueba por código.

var _fallos: int = 0
var _almacenados: Array[ItemStack] = []
var _extraidos: Array[ItemStack] = []
var _bus: Array = []


func _ready() -> void:
	_probar_stack()
	_probar_config()
	_probar_almacenar()
	_probar_desborde()
	_probar_tipos_y_tamanos()
	_probar_sacar()
	_probar_senales()
	_probar_simulacion()
	_probar_herramientas()
	_probar_incompatibilidades()
	_probar_zonas_mayores()
	_probar_setup()
	_probar_event_bus()
	_probar_entradas_invalidas()

	if _fallos == 0:
		print("Tarea 11: todas las comprobaciones pasaron.")
	else:
		push_error("Tarea 11: fallaron %d comprobaciones." % _fallos)


func _probar_stack() -> void:
	var pernos := ItemStack.new(_bulones(), 50)
	_comprobar(is_equal_approx(pernos.get_weight(), 5.0), "50 bulones de 0.1 kg pesan 5 kg")
	_comprobar(pernos.can_merge(ItemStack.new(_bulones(), 3)), "Dos pilas del mismo objeto se pueden fusionar (aunque sean recursos distintos con el mismo id)")
	_comprobar(not pernos.can_merge(ItemStack.new(_tuercas(), 3)), "Objetos distintos no se fusionan")
	var hacha_a := ItemStack.new(_hacha(), 1, 1.0)
	var hacha_b := ItemStack.new(_hacha(), 1, 0.5)
	_comprobar(not hacha_a.can_merge(hacha_b), "Los objetos con durabilidad nunca se fusionan")
	var copia := pernos.duplicate_stack(10)
	copia.quantity = 99
	_comprobar(pernos.quantity == 50, "duplicate_stack devuelve una copia independiente")
	var copia_hacha := hacha_b.duplicate_stack()
	_comprobar(copia_hacha.quantity == 1 and is_equal_approx(copia_hacha.durability, 0.5), "La copia conserva cantidad y durabilidad")


func _probar_config() -> void:
	var config := StorageConfig.new()
	_comprobar(config.stack_capacity(ItemData.SizeClass.SMALL) == 50 and config.stack_capacity(ItemData.SizeClass.MEDIUM) == 30 and config.stack_capacity(ItemData.SizeClass.LARGE) == 10, "Capacidades por defecto: chica 50, mediana 30, grande 10")
	_comprobar(config.zone_accepts(ItemData.SizeClass.SMALL, ItemData.SizeClass.SMALL) and not config.zone_accepts(ItemData.SizeClass.MEDIUM, ItemData.SizeClass.SMALL), "Por defecto cada zona acepta solo su tamaño")
	config.allow_smaller_items_in_larger_zones = true
	_comprobar(config.zone_accepts(ItemData.SizeClass.MEDIUM, ItemData.SizeClass.SMALL) and not config.zone_accepts(ItemData.SizeClass.SMALL, ItemData.SizeClass.MEDIUM), "Con la opción activada, una zona mayor acepta objetos menores pero no al revés")
	config.tag_conflicts.append(TagConflict.new(&"chemical", &"food"))
	_comprobar(config.tags_conflict([&"chemical"], [&"food"]) and config.tags_conflict([&"food"], [&"chemical"]), "Un conflicto de etiquetas vale en ambos sentidos")
	_comprobar(not config.tags_conflict([&"chemical"], [&"metal"]) and not config.tags_conflict([], [&"food"]), "Etiquetas sin conflicto no molestan")


func _probar_almacenar() -> void:
	var mochila := _contenedor(4, 1, 0)
	_comprobar(mochila.get_zone_count() == 5, "La mochila tiene 5 zonas (4 chicas + 1 mediana)")
	_comprobar(mochila.get_zone_size(0) == ItemData.SizeClass.SMALL and mochila.get_zone_size(4) == ItemData.SizeClass.MEDIUM, "Las zonas respetan el orden y el tamaño del layout")

	var sobrante: ItemStack = mochila.try_store(ItemStack.new(_bulones(), 20))
	_comprobar(sobrante == null, "20 bulones entran enteros")
	_comprobar(mochila.count_of(&"bolt") == 20 and mochila.peek(0).quantity == 20, "Quedan en la primera zona chica")

	sobrante = mochila.try_store(ItemStack.new(_bulones(), 40))
	_comprobar(sobrante == null and mochila.peek(0).quantity == 50 and mochila.peek(1).quantity == 10, "Otros 40: la primera zona se completa (50) y el resto va a la segunda")
	_comprobar(mochila.count_of(&"bolt") == 60, "En total hay 60 bulones")


func _probar_desborde() -> void:
	var mochila := _contenedor(4, 1, 0)
	var entrada := ItemStack.new(_bulones(), 500)
	var sobrante: ItemStack = mochila.try_store(entrada)
	_comprobar(sobrante != null and sobrante.quantity == 300, "500 bulones en 4 zonas chicas: entran 200 y sobran 300")
	_comprobar(entrada.quantity == 500, "El stack recibido no se modifica")
	_comprobar(sobrante != entrada, "El sobrante es un stack nuevo, no el mismo objeto")
	_comprobar(mochila.count_of(&"bolt") == 200, "Quedan 200 bulones guardados")


func _probar_tipos_y_tamanos() -> void:
	var mochila := _contenedor(4, 1, 0)
	mochila.try_store(ItemStack.new(_bulones(), 10))
	mochila.try_store(ItemStack.new(_tuercas(), 10))
	_comprobar(mochila.peek(0).item.id == &"bolt" and mochila.peek(1).item.id == &"nut", "Una zona guarda un solo tipo: las tuercas van a otra zona")
	var sobrante: ItemStack = mochila.try_store(ItemStack.new(_durmientes(), 40))
	_comprobar(sobrante != null and sobrante.quantity == 10 and mochila.peek(4).quantity == 30, "40 durmientes: la zona mediana guarda 30 y sobran 10")
	sobrante = mochila.try_store(ItemStack.new(_rieles(), 2))
	_comprobar(sobrante != null and sobrante.quantity == 2, "Sin zona grande, los rieles no entran en la mochila")
	_comprobar(mochila.count_of(&"rail") == 0, "Y no queda ningún riel guardado")
	# 10 bulones (1 kg) + 10 tuercas (0.5 kg) + 30 durmientes (750 kg)
	_comprobar(is_equal_approx(mochila.get_total_weight(), 751.5), "El peso total suma todas las zonas (751.5 kg)")


func _probar_sacar() -> void:
	var mochila := _contenedor(4, 1, 0)
	mochila.try_store(ItemStack.new(_bulones(), 20))
	var sacado: ItemStack = mochila.take(0, 15)
	_comprobar(sacado != null and sacado.quantity == 15 and sacado.item.id == &"bolt", "take(0, 15) devuelve 15 bulones")
	_comprobar(mochila.peek(0).quantity == 5, "En la zona quedan 5")
	sacado = mochila.take(0, 100)
	_comprobar(sacado.quantity == 5, "Pedir más de lo que hay devuelve solo lo que hay")
	_comprobar(mochila.peek(0) == null, "La zona vacía queda libre")
	_comprobar(mochila.take(0, 1) == null, "Sacar de una zona vacía devuelve null")
	_comprobar(mochila.take(1, 0) == null, "Sacar una cantidad 0 devuelve null")
	mochila.try_store(ItemStack.new(_tuercas(), 5))
	_comprobar(mochila.peek(0) != null and mochila.peek(0).item.id == &"nut", "La zona liberada se reutiliza para otro tipo")


func _probar_senales() -> void:
	var mochila := _contenedor(4, 1, 0)
	_almacenados.clear()
	mochila.try_store(ItemStack.new(_bulones(), 70))
	_comprobar(_almacenados.size() == 1 and _almacenados[0].quantity == 70, "item_stored se emite una vez con el total guardado (70)")

	var chico := _contenedor(1, 0, 0)
	_almacenados.clear()
	chico.try_store(ItemStack.new(_bulones(), 80))
	_comprobar(_almacenados.size() == 1 and _almacenados[0].quantity == 50, "Con sobrante, item_stored informa solo lo que entró (50)")
	_almacenados.clear()
	chico.try_store(ItemStack.new(_bulones(), 5))
	_comprobar(_almacenados.is_empty(), "Si no entra nada, no se emite item_stored")
	_extraidos.clear()
	chico.take(0, 20)
	_comprobar(_extraidos.size() == 1 and _extraidos[0].quantity == 20, "item_taken informa lo que salió (20)")


func _probar_simulacion() -> void:
	var mochila := _contenedor(2, 0, 0)
	var candidato := ItemStack.new(_bulones(), 130)
	_comprobar(mochila.can_store_amount(candidato) == 100, "can_store_amount: de 130 bulones entrarían 100")
	_comprobar(mochila.count_of(&"bolt") == 0, "Y la simulación no guardó nada")
	var sobrante: ItemStack = mochila.try_store(candidato)
	_comprobar(sobrante.quantity == 30 and mochila.count_of(&"bolt") == 100, "try_store guarda exactamente lo que se había previsto")
	_comprobar(mochila.can_store_amount(candidato) == 0, "Con las zonas llenas ya no entra nada")


func _probar_herramientas() -> void:
	var mochila := _contenedor(3, 0, 0)
	mochila.try_store(ItemStack.new(_hacha(), 1, 1.0))
	mochila.try_store(ItemStack.new(_hacha(), 1, 0.5))
	_comprobar(mochila.peek(0) != null and mochila.peek(1) != null and is_equal_approx(mochila.peek(0).durability, 1.0) and is_equal_approx(mochila.peek(1).durability, 0.5), "Dos hachas con distinta durabilidad ocupan dos zonas, cada una con la suya")
	var sobrante: ItemStack = mochila.try_store(ItemStack.new(_hacha(), 3, 0.8))
	_comprobar(sobrante != null and sobrante.quantity == 2, "Una zona guarda una sola unidad con durabilidad: de 3 entra 1")
	_comprobar(is_equal_approx(sobrante.durability, 0.8), "El sobrante conserva la durabilidad")


func _probar_incompatibilidades() -> void:
	var config := StorageConfig.new()
	config.tag_conflicts.append(TagConflict.new(&"chemical", &"food"))
	var vagon := _contenedor(2, 0, 0, config)
	var comida := ItemStack.new(_item(&"bread", ItemData.SizeClass.SMALL, 0.5, [&"food"]), 5)
	var quimico := ItemStack.new(_item(&"acid", ItemData.SizeClass.SMALL, 2.0, [&"chemical"]), 5)
	vagon.try_store(comida)
	var sobrante: ItemStack = vagon.try_store(quimico)
	_comprobar(sobrante != null and sobrante.quantity == 5 and vagon.count_of(&"acid") == 0, "Un químico no entra en un contenedor que lleva comida")
	vagon.take(0, 5)
	sobrante = vagon.try_store(quimico)
	_comprobar(sobrante == null and vagon.count_of(&"acid") == 5, "Sin la comida, el químico sí entra")
	sobrante = vagon.try_store(comida)
	_comprobar(sobrante != null and sobrante.quantity == 5, "Y ahora la comida no entra junto al químico")
	_comprobar(vagon.can_store_amount(comida) == 0, "can_store_amount también respeta las incompatibilidades")


func _probar_zonas_mayores() -> void:
	var config := StorageConfig.new()
	config.allow_smaller_items_in_larger_zones = true
	# La zona mediana va primero en el layout: aun así, un objeto chico prefiere la chica.
	var layout := StorageLayout.new()
	layout.zones.append(ZoneSpec.new(ItemData.SizeClass.MEDIUM, 1))
	layout.zones.append(ZoneSpec.new(ItemData.SizeClass.SMALL, 1))
	var mochila := _contenedor_desde(layout, config)
	mochila.try_store(ItemStack.new(_bulones(), 10))
	_comprobar(mochila.peek(0) == null and mochila.peek(1) != null, "Un objeto chico prefiere la zona chica aunque la mediana esté primero")
	var sobrante: ItemStack = mochila.try_store(ItemStack.new(_bulones(), 60))
	_comprobar(sobrante == null and mochila.peek(1).quantity == 50 and mochila.peek(0).quantity == 20, "Completa la pila chica (50) y el resto va a la zona mediana (20)")
	_comprobar(mochila.can_store_amount(ItemStack.new(_rieles(), 1)) == 0, "Un objeto grande no entra en zonas más chicas")


func _probar_setup() -> void:
	var mochila := _contenedor(2, 0, 0)
	mochila.try_store(ItemStack.new(_bulones(), 10))
	mochila.setup(_layout(3, 1, 0), StorageConfig.new())
	_comprobar(mochila.get_zone_count() == 4 and mochila.count_of(&"bolt") == 0, "Llamar a setup de nuevo rearma las zonas y descarta el contenido")


func _probar_event_bus() -> void:
	EventBus.item_stored.connect(_al_guardar_en_bus)
	EventBus.item_taken.connect(_al_sacar_del_bus)
	_bus.clear()
	var sin_id := _contenedor(1, 0, 0)
	sin_id.try_store(ItemStack.new(_bulones(), 5))
	_comprobar(_bus.is_empty(), "Un contenedor sin container_id no emite por el EventBus")
	var con_id := _contenedor(1, 0, 0, null, &"backpack")
	con_id.try_store(ItemStack.new(_bulones(), 5))
	con_id.take(0, 2)
	_comprobar(_bus.size() == 2 and _bus[0] == ["stored", &"backpack", 5] and _bus[1] == ["taken", &"backpack", 2], "Con container_id, el EventBus recibe item_stored e item_taken")
	EventBus.item_stored.disconnect(_al_guardar_en_bus)
	EventBus.item_taken.disconnect(_al_sacar_del_bus)


func _probar_entradas_invalidas() -> void:
	var mochila := _contenedor(1, 0, 0)
	_comprobar(mochila.try_store(null) == null, "Guardar null no hace nada")
	_comprobar(mochila.try_store(ItemStack.new(_bulones(), 0)) == null, "Guardar una cantidad 0 no hace nada")
	_comprobar(mochila.count_of(&"bolt") == 0, "Y no queda nada guardado")


# --- Ayudas para armar datos de prueba ---

func _item(id: StringName, size: ItemData.SizeClass, weight: float = 1.0, tags: Array[StringName] = []) -> ItemData:
	var item := ItemData.new()
	item.id = id
	item.size_class = size
	item.unit_weight = weight
	item.tags = tags
	return item


func _bulones() -> ItemData:
	return _item(&"bolt", ItemData.SizeClass.SMALL, 0.1)


func _tuercas() -> ItemData:
	return _item(&"nut", ItemData.SizeClass.SMALL, 0.05)


func _durmientes() -> ItemData:
	return _item(&"sleeper", ItemData.SizeClass.MEDIUM, 25.0)


func _rieles() -> ItemData:
	return _item(&"rail", ItemData.SizeClass.LARGE, 60.0)


func _hacha() -> ItemData:
	return _item(&"axe", ItemData.SizeClass.SMALL, 2.0)


func _layout(small: int, medium: int, large: int) -> StorageLayout:
	var layout := StorageLayout.new()
	if small > 0:
		layout.zones.append(ZoneSpec.new(ItemData.SizeClass.SMALL, small))
	if medium > 0:
		layout.zones.append(ZoneSpec.new(ItemData.SizeClass.MEDIUM, medium))
	if large > 0:
		layout.zones.append(ZoneSpec.new(ItemData.SizeClass.LARGE, large))
	return layout


func _contenedor(small: int, medium: int, large: int, config: StorageConfig = null, id: StringName = &"") -> StorageContainer:
	return _contenedor_desde(_layout(small, medium, large), config, id)


func _contenedor_desde(layout: StorageLayout, config: StorageConfig = null, id: StringName = &"") -> StorageContainer:
	var contenedor := StorageContainer.new()
	contenedor.container_id = id
	contenedor.item_stored.connect(_al_guardar)
	contenedor.item_taken.connect(_al_sacar)
	# Hijo de esta escena: se libera solo cuando la prueba termina.
	add_child(contenedor)
	contenedor.setup(layout, config if config != null else StorageConfig.new())
	return contenedor


func _al_guardar(stack: ItemStack) -> void:
	_almacenados.append(stack)


func _al_sacar(stack: ItemStack) -> void:
	_extraidos.append(stack)


func _al_guardar_en_bus(container_id: StringName, stack: ItemStack) -> void:
	_bus.append(["stored", container_id, stack.quantity])


func _al_sacar_del_bus(container_id: StringName, stack: ItemStack) -> void:
	_bus.append(["taken", container_id, stack.quantity])


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
