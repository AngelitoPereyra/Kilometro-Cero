extends Node
## Prueba de ItemStack y StorageContainer (tarea 11, simplificado en la 53: sin zonas por
## tamaño ni compatibilidad, D85). Es lógica pura: no hay escena 3D. Todo se arma y se
## comprueba por código.

var _fallos: int = 0
var _almacenados: Array[ItemStack] = []
var _extraidos: Array[ItemStack] = []
var _bus: Array = []


func _ready() -> void:
	_probar_stack()
	_probar_almacenar()
	_probar_capacidad()
	_probar_carga_aceptada()
	_probar_sacar()
	_probar_senales()
	_probar_simulacion()
	_probar_herramientas()
	_probar_configure()
	_probar_event_bus()
	_probar_entradas_invalidas()

	if _fallos == 0:
		print("Almacenamiento: todas las comprobaciones pasaron.")
	else:
		push_error("Almacenamiento: fallaron %d comprobaciones." % _fallos)


func _probar_stack() -> void:
	var pernos := ItemStack.new(_bulones(), 50)
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


func _probar_almacenar() -> void:
	var caja := _contenedor(100)
	var original := ItemStack.new(_bulones(), 30)
	_comprobar(caja.try_store(original) == null, "30 bulones entran enteros")
	_comprobar(original.quantity == 30, "El stack recibido no se modifica")
	caja.try_store(ItemStack.new(_bulones(), 5))
	_comprobar(caja.get_stack_count() == 1 and caja.count_of(&"bolt") == 35, "El mismo objeto se suma a su pila (35 en una sola)")
	caja.try_store(ItemStack.new(_troncos(), 4))
	_comprobar(caja.get_stack_count() == 2 and caja.peek(1).item.id == &"log", "Otro objeto abre una pila nueva, al final")
	_comprobar(caja.get_total() == 39 and caja.get_free_space() == 61, "Total 39, quedan 61 lugares")
	caja.try_store(ItemStack.new(_rieles(), 2))
	_comprobar(caja.count_of(&"rail") == 2, "Sin zonas por tamaño: lo grande entra igual que lo chico")


func _probar_capacidad() -> void:
	var plataforma := _contenedor(20)
	var sobrante: ItemStack = plataforma.try_store(ItemStack.new(_troncos(), 25))
	_comprobar(sobrante != null and sobrante.quantity == 5, "De 25 troncos en una plataforma de 20 sobran 5")
	_comprobar(plataforma.count_of(&"log") == 20 and plataforma.get_free_space() == 0, "Queda llena")
	_comprobar(plataforma.try_store(ItemStack.new(_rieles(), 1)).quantity == 1, "Llena, no entra nada más")
	_comprobar(plataforma.can_store_amount(ItemStack.new(_troncos(), 1)) == 0, "La simulación también dice 0")


func _probar_carga_aceptada() -> void:
	var plataforma := _contenedor(20, [&"log", &"rail"])
	_comprobar(plataforma.accepts(_troncos()) and plataforma.accepts(_rieles()), "Una plataforma acepta troncos y rieles")
	_comprobar(not plataforma.accepts(_bulones()), "Pero no bulones (sin etiqueta de carga)")
	var rechazo: ItemStack = plataforma.try_store(ItemStack.new(_bulones(), 3))
	_comprobar(rechazo != null and rechazo.quantity == 3 and plataforma.is_empty(), "Los bulones vuelven enteros y no queda nada guardado")
	plataforma.try_store(ItemStack.new(_troncos(), 2))
	plataforma.try_store(ItemStack.new(_rieles(), 1))
	_comprobar(plataforma.count_of(&"log") == 2 and plataforma.count_of(&"rail") == 1, "Troncos y rieles conviven en la misma plataforma")
	var cualquiera := _contenedor(10)
	_comprobar(cualquiera.accepts(_bulones()) and cualquiera.accepts(_troncos()), "Sin etiquetas aceptadas, entra cualquier cosa")
	_comprobar(not cualquiera.accepts(null), "Un objeto nulo no se acepta")


func _probar_sacar() -> void:
	var caja := _contenedor(50)
	caja.try_store(ItemStack.new(_bulones(), 10))
	caja.try_store(ItemStack.new(_tuercas(), 1))
	var sacado: ItemStack = caja.take(0, 4)
	_comprobar(sacado != null and sacado.quantity == 4 and caja.count_of(&"bolt") == 6, "Sacar 4 de 10 deja 6")
	sacado = caja.take(0, 99)
	_comprobar(sacado.quantity == 6 and caja.count_of(&"bolt") == 0, "Pedir de más saca solo lo que hay")
	_comprobar(caja.get_stack_count() == 1 and caja.peek(0).item.id == &"nut", "La pila vacía desaparece y la de atrás se corre")
	_comprobar(caja.take(0, 0) == null, "Sacar 0 no saca nada")
	var copia: ItemStack = caja.peek(0)
	copia.quantity = 50
	_comprobar(caja.count_of(&"nut") == 1, "peek devuelve una copia: cambiarla no toca el contenido")


func _probar_senales() -> void:
	_almacenados.clear()
	_extraidos.clear()
	var plataforma := _contenedor(3)
	plataforma.try_store(ItemStack.new(_troncos(), 5))
	_comprobar(_almacenados.size() == 1 and _almacenados[0].quantity == 3, "item_stored avisa lo que entró (3), no lo pedido (5)")
	plataforma.try_store(ItemStack.new(_troncos(), 1))
	_comprobar(_almacenados.size() == 1, "Si no entra nada, no avisa")
	plataforma.take(0, 2)
	_comprobar(_extraidos.size() == 1 and _extraidos[0].quantity == 2, "item_taken avisa lo que salió")


func _probar_simulacion() -> void:
	var plataforma := _contenedor(20, [&"log"])
	plataforma.try_store(ItemStack.new(_troncos(), 15))
	_comprobar(plataforma.can_store_amount(ItemStack.new(_troncos(), 10)) == 5, "Simular 10 troncos con 5 lugares libres da 5")
	_comprobar(plataforma.can_store_amount(ItemStack.new(_bulones(), 1)) == 0, "Simular algo que no es su carga da 0")
	_comprobar(plataforma.count_of(&"log") == 15, "Simular no guarda nada")


func _probar_herramientas() -> void:
	var caja := _contenedor(5)
	caja.try_store(ItemStack.new(_hacha(), 1, 1.0))
	caja.try_store(ItemStack.new(_hacha(), 1, 0.4))
	_comprobar(caja.get_stack_count() == 2 and caja.count_of(&"axe") == 2, "Cada herramienta con desgaste ocupa su propia pila")
	_comprobar(is_equal_approx(caja.peek(1).durability, 0.4), "Y conserva su durabilidad")


func _probar_configure() -> void:
	var caja := _contenedor(10)
	caja.try_store(ItemStack.new(_bulones(), 4))
	var etiquetas: Array[StringName] = [&"log"]
	caja.configure(6, etiquetas)
	etiquetas.append(&"bolt")
	_comprobar(caja.capacity == 6 and caja.accepted_tags.size() == 1, "configure cambia capacidad y carga, con su propia copia de las etiquetas")
	_comprobar(caja.count_of(&"bolt") == 4 and caja.get_free_space() == 2, "configure no toca lo ya guardado")


func _probar_event_bus() -> void:
	EventBus.item_stored.connect(_al_guardar_en_bus)
	EventBus.item_taken.connect(_al_sacar_del_bus)
	_bus.clear()
	var sin_id := _contenedor(10)
	sin_id.try_store(ItemStack.new(_bulones(), 5))
	_comprobar(_bus.is_empty(), "Un contenedor sin container_id no emite por el EventBus")
	var con_id := _contenedor(10, [], &"flatcar")
	con_id.try_store(ItemStack.new(_bulones(), 5))
	con_id.take(0, 2)
	_comprobar(_bus.size() == 2 and _bus[0] == ["stored", &"flatcar", 5] and _bus[1] == ["taken", &"flatcar", 2], "Con container_id, el EventBus recibe item_stored e item_taken")
	EventBus.item_stored.disconnect(_al_guardar_en_bus)
	EventBus.item_taken.disconnect(_al_sacar_del_bus)


func _probar_entradas_invalidas() -> void:
	var caja := _contenedor(10)
	_comprobar(caja.try_store(null) == null, "Guardar null no hace nada")
	_comprobar(caja.try_store(ItemStack.new(_bulones(), 0)) == null, "Guardar una cantidad 0 no hace nada")
	_comprobar(caja.is_empty(), "Y no queda nada guardado")


# --- Ayudas para armar datos de prueba ---

func _item(id: StringName, size: ItemData.SizeClass, tags: Array[StringName] = []) -> ItemData:
	var item := ItemData.new()
	item.id = id
	item.size_class = size
	item.tags = tags
	return item


func _bulones() -> ItemData:
	return _item(&"bolt", ItemData.SizeClass.SMALL)


func _tuercas() -> ItemData:
	return _item(&"nut", ItemData.SizeClass.SMALL)


func _troncos() -> ItemData:
	return _item(&"log", ItemData.SizeClass.LARGE, [&"log"])


func _rieles() -> ItemData:
	return _item(&"rail", ItemData.SizeClass.LARGE, [&"rail"])


func _hacha() -> ItemData:
	return _item(&"axe", ItemData.SizeClass.SMALL)


func _contenedor(capacidad: int, etiquetas: Array[StringName] = [], id: StringName = &"") -> StorageContainer:
	var contenedor := StorageContainer.new()
	contenedor.container_id = id
	contenedor.configure(capacidad, etiquetas)
	contenedor.item_stored.connect(_al_guardar)
	contenedor.item_taken.connect(_al_sacar)
	# Hijo de esta escena: se libera solo cuando la prueba termina.
	add_child(contenedor)
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
