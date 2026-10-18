extends Node
## Prueba de la tarea 12 (parte 1): CarryConfig, Encumbrance y BackpackData.
## Es lógica pura: no hay escena 3D. La conexión con el jugador llega en la parte 2.

var _fallos: int = 0
var _ratios: Array[float] = []


func _ready() -> void:
	_probar_config_de_carga()
	_probar_encumbrance()
	_probar_senales()
	_probar_fuentes_y_capacidad()
	_probar_recoger()
	_probar_contenedores()
	_probar_mochila()
	_probar_balance_inicial()

	if _fallos == 0:
		print("Tarea 12 (parte 1): todas las comprobaciones pasaron.")
	else:
		push_error("Tarea 12 (parte 1): fallaron %d comprobaciones." % _fallos)


func _probar_config_de_carga() -> void:
	var config := CarryConfig.new()
	_comprobar(is_equal_approx(config.base_capacity, 50.0) and is_equal_approx(config.free_ratio, 1.0) and is_equal_approx(config.max_ratio, 1.5), "Por defecto: capacidad 50 kg, sin penalización hasta 100 %, tope en 150 %")
	_comprobar(is_equal_approx(config.speed_multiplier(0.0), 1.0) and is_equal_approx(config.speed_multiplier(1.0), 1.0), "Hasta el 100 % no hay penalización de velocidad")
	_comprobar(is_equal_approx(config.speed_multiplier(1.25), 0.75), "A mitad de camino (125 %) la velocidad es x0.75")
	_comprobar(is_equal_approx(config.speed_multiplier(1.5), 0.5) and is_equal_approx(config.speed_multiplier(3.0), 0.5), "En el tope (150 %) y más allá la velocidad no baja de x0.5")
	_comprobar(is_equal_approx(config.fatigue_multiplier(0.9), 1.0) and is_equal_approx(config.fatigue_multiplier(1.25), 1.5) and is_equal_approx(config.fatigue_multiplier(1.5), 2.0), "La fatiga sube de x1.0 a x2.0 entre 100 % y 150 %")
	_comprobar(config.can_carry(0.0) and config.can_carry(1.5) and not config.can_carry(1.51), "Se puede cargar hasta el 150 %, no más")
	var rota := CarryConfig.new()
	rota.free_ratio = 1.0
	rota.max_ratio = 1.0
	_comprobar(is_equal_approx(rota.speed_multiplier(1.2), rota.min_speed_multiplier), "Con max_ratio igual a free_ratio no divide por cero: la penalización es inmediata")


func _probar_encumbrance() -> void:
	var enc: Encumbrance = _crear(CarryConfig.new())
	_comprobar(is_zero_approx(enc.get_total_weight()) and is_equal_approx(enc.get_capacity(), 50.0) and is_zero_approx(enc.get_ratio()), "Vacío: peso 0, capacidad 50 kg, cociente 0")
	enc.set_load(&"hands", 25.0)
	_comprobar(is_equal_approx(enc.get_total_weight(), 25.0) and is_equal_approx(enc.get_ratio(), 0.5), "25 kg sobre 50 kg de capacidad: cociente 0.5")
	enc.set_load(&"backpack", 15.0)
	_comprobar(is_equal_approx(enc.get_total_weight(), 40.0), "El peso suma todas las fuentes (25 + 15 = 40)")
	enc.set_load(&"hands", 30.0)
	_comprobar(is_equal_approx(enc.get_total_weight(), 45.0), "Volver a informar una fuente reemplaza su peso, no lo suma")
	enc.clear_load(&"hands")
	_comprobar(is_equal_approx(enc.get_total_weight(), 15.0), "clear_load quita el peso de una fuente")
	enc.set_load(&"hands", -5.0)
	_comprobar(is_equal_approx(enc.get_total_weight(), 15.0), "Un peso negativo se toma como 0")


func _probar_senales() -> void:
	var enc: Encumbrance = _crear(CarryConfig.new())
	_ratios.clear()
	enc.set_load(&"hands", 25.0)
	_comprobar(_ratios.size() == 1 and is_equal_approx(_ratios[0], 0.5), "ratio_changed se emite con el cociente nuevo")
	enc.set_load(&"hands", 25.0)
	_comprobar(_ratios.size() == 1, "Si el cociente no cambia, no se emite nada")


func _probar_fuentes_y_capacidad() -> void:
	var enc: Encumbrance = _crear(CarryConfig.new())
	enc.set_load(&"backpack", 40.0)
	enc.set_capacity_bonus(&"backpack", 10.0)
	_comprobar(is_equal_approx(enc.get_capacity(), 60.0) and is_equal_approx(enc.get_ratio(), 40.0 / 60.0), "Una mochila con +10 kg sube la capacidad a 60 kg y baja el cociente")
	enc.set_capacity_bonus(&"backpack", 0.0)
	_comprobar(is_equal_approx(enc.get_capacity(), 50.0), "Un bonus de 0 quita la ampliación de capacidad")
	enc.set_load(&"hands", 22.5)
	_comprobar(is_equal_approx(enc.get_ratio(), 1.25) and is_equal_approx(enc.get_speed_multiplier(), 0.75) and is_equal_approx(enc.get_fatigue_multiplier(), 1.5), "Al 125 %: velocidad x0.75 y fatiga x1.5")


func _probar_recoger() -> void:
	var enc: Encumbrance = _crear(CarryConfig.new())
	enc.set_load(&"backpack", 30.0)
	_comprobar(enc.can_pick_up(45.0), "Con 30 kg encima se puede levantar hasta llegar al 150 % (75 kg)")
	_comprobar(not enc.can_pick_up(45.1), "Un poco más ya no se puede")
	_comprobar(is_equal_approx(enc.get_pickup_room(), 45.0), "Quedan 45 kg de margen")
	_comprobar(enc.can_pick_up(0.0) and enc.can_pick_up(-3.0), "Levantar nada (o soltar) siempre se puede")
	enc.set_load(&"hands", 200.0)
	_comprobar(is_zero_approx(enc.get_pickup_room()) and not enc.can_pick_up(1.0), "Por encima del tope el margen es 0 y no se puede levantar nada")


func _probar_contenedores() -> void:
	var enc: Encumbrance = _crear(CarryConfig.new())
	var mochila: StorageContainer = _contenedor(4, 1)
	enc.track_container(&"backpack", mochila)
	_comprobar(is_zero_approx(enc.get_total_weight()), "Una mochila vacía recién enganchada no pesa")
	mochila.try_store(ItemStack.new(_item(&"bolt", ItemData.SizeClass.SMALL, 0.1), 50))
	_comprobar(is_equal_approx(enc.get_total_weight(), 5.0), "Al guardar 50 bulones de 0.1 kg, el peso sube a 5 kg")
	mochila.take(0, 20)
	_comprobar(is_equal_approx(enc.get_total_weight(), 3.0), "Al sacar 20, baja a 3 kg")
	var carrito: StorageContainer = _contenedor(0, 0, 1)
	carrito.try_store(ItemStack.new(_item(&"rail", ItemData.SizeClass.LARGE, 60.0), 2))
	enc.track_container(&"cart", carrito)
	_comprobar(is_equal_approx(enc.get_total_weight(), 123.0), "Un contenedor que ya traía carga suma su peso al engancharse (3 + 120 kg)")


func _probar_mochila() -> void:
	var datos := BackpackData.new()
	datos.id = &"backpack_basic"
	datos.weight_capacity_bonus = 10.0
	datos.layout = _layout(4, 1, 0)
	# Se asigna a una variable de tipo ItemData: así se comprueba que la mochila ES un objeto.
	var como_objeto: ItemData = datos
	_comprobar(como_objeto.id == &"backpack_basic", "Una mochila es un ItemData: se guarda, se suelta y se pesa como cualquier objeto")
	_comprobar(datos.layout.get_zone_count() == 5 and is_equal_approx(datos.weight_capacity_bonus, 10.0), "BackpackData guarda su layout (5 zonas) y su bonus de capacidad")
	var enc: Encumbrance = _crear(CarryConfig.new())
	enc.set_capacity_bonus(&"backpack", datos.weight_capacity_bonus)
	_comprobar(is_equal_approx(enc.get_capacity(), 60.0), "El bonus de la mochila equipada amplía la capacidad (50 + 10)")


func _probar_balance_inicial() -> void:
	var enc: Encumbrance = _crear(CarryConfig.new())
	enc.set_load(&"hands", 60.0)
	_comprobar(enc.config.can_carry(enc.get_ratio()) and is_equal_approx(enc.get_speed_multiplier(), 0.8), "Un riel (60 kg) con la capacidad base se puede cargar, pero frena a x0.8")
	_comprobar(not enc.can_pick_up(60.0), "Un segundo riel (120 kg, 240 %) ya no se puede levantar")


# --- Ayudas para armar datos de prueba ---

func _crear(config: CarryConfig) -> Encumbrance:
	var enc := Encumbrance.new()
	enc.config = config
	enc.ratio_changed.connect(_al_cambiar_cociente)
	# Hijo de esta escena: se libera solo cuando la prueba termina. Al entrar al árbol corre _ready().
	add_child(enc)
	return enc


func _item(id: StringName, size: ItemData.SizeClass, weight: float) -> ItemData:
	var item := ItemData.new()
	item.id = id
	item.size_class = size
	item.unit_weight = weight
	return item


func _layout(small: int, medium: int, large: int) -> StorageLayout:
	var layout := StorageLayout.new()
	if small > 0:
		layout.zones.append(ZoneSpec.new(ItemData.SizeClass.SMALL, small))
	if medium > 0:
		layout.zones.append(ZoneSpec.new(ItemData.SizeClass.MEDIUM, medium))
	if large > 0:
		layout.zones.append(ZoneSpec.new(ItemData.SizeClass.LARGE, large))
	return layout


func _contenedor(small: int, medium: int, large: int = 0) -> StorageContainer:
	var contenedor := StorageContainer.new()
	add_child(contenedor)
	contenedor.setup(_layout(small, medium, large), StorageConfig.new())
	return contenedor


func _al_cambiar_cociente(ratio: float) -> void:
	_ratios.append(ratio)


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
	
