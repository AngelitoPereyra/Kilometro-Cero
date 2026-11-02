extends Node3D
## Prueba de la tarea 62c.3h (D143): salud que baja con las horas y sube comiendo (R), carne, asado y
## pan, machete y jabalíes que huyen, embisten y se cazan, horno del vagón cocina, camas (vagón y
## taberna), acampar de noche (no con jabalíes cerca) y el desmayo que lleva a la última cama. Al
## final arma el Hito A y mira el machete, el vagón cocina enganchado, las tabernas y los jabalíes
## lejos de las vías. Toca la partida de GameState.

const PLAYER: String = "res://scenes/player/player.tscn"
const HITO_A: String = "res://scenes/hito_a/hito_a.tscn"
const CARNE: String = "res://data/items/raw_meat.tres"
const ASADO: String = "res://data/items/roast_meat.tres"
const PAN: String = "res://data/items/bread.tres"
const MACHETE: String = "res://data/items/machete.tres"
const COCINA: String = "res://scenes/vehicles/kitchen_wagon.tscn"
const TABERNA: String = "res://scenes/stations/tavern.tscn"

var _fallos: int = 0
var _jugador: Player
var _carne: FoodData
var _asado: FoodData
var _pan: FoodData


func _ready() -> void:
	_carne = load(CARNE) as FoodData
	_asado = load(ASADO) as FoodData
	_pan = load(PAN) as FoodData
	_probar_logica()
	GameState.reset_production()
	await _armar_mundo()
	await _probar_salud_y_comida()
	await _probar_horno()
	await _probar_camas()
	await _probar_acampar()
	await _probar_jabali()
	await _probar_desmayo()
	_probar_taberna()
	_jugador.queue_free()
	await _probar_hito_a()
	if _fallos == 0:
		print("Supervivencia: todas las comprobaciones pasaron.")
	else:
		push_error("Supervivencia: fallaron %d comprobaciones." % _fallos)


func _probar_logica() -> void:
	_comprobar(is_equal_approx(Health.after_hours(100.0, 24.0, 1.0), 76.0) and Health.after_hours(5.0, 10.0, 1.0) == 0.0, "La salud baja 1 por hora y no pasa de 0")
	_comprobar(Health.healed(90.0, 40.0, 100.0) == 100.0 and Health.healed(50.0, 20.0, 100.0) == 70.0, "Comer suma sin pasar del máximo")
	_comprobar(Health.bar_text(72.0, 100.0) == "▮▮▮▮▮▮▮▮▯▯" and Health.bar_text(0.0, 100.0) == "▯▯▯▯▯▯▯▯▯▯", "La barrita de salud del HUD")
	_comprobar(Sleeper.can_sleep_at(21.0) and Sleeper.can_sleep_at(3.0) and not Sleeper.can_sleep_at(12.0) and not Sleeper.can_sleep_at(5.5), "Se duerme de 19:00 a 5:00")
	_comprobar(is_equal_approx(Sleeper.hours_until_wake(21.0), 10.0) and is_equal_approx(Sleeper.hours_until_wake(2.0), 5.0), "Se despierta a las 7:00")
	_comprobar(Boar.decide(Boar.State.WANDER, 8.0, true, false, 12.0, 3.5, 25.0) == Boar.State.FLEE, "El jabalí huye si te acercás corriendo")
	_comprobar(Boar.decide(Boar.State.WANDER, 8.0, false, false, 12.0, 3.5, 25.0) == Boar.State.WANDER, "Caminando despacio no se asusta")
	_comprobar(Boar.decide(Boar.State.WANDER, 2.0, false, false, 12.0, 3.5, 25.0) == Boar.State.FLEE, "Muy cerca huye igual")
	_comprobar(Boar.decide(Boar.State.FLEE, 30.0, false, false, 12.0, 3.5, 25.0) == Boar.State.WANDER, "Lejos vuelve a pasear")
	_comprobar(Boar.decide(Boar.State.FLEE, 5.0, false, true, 12.0, 3.5, 25.0) == Boar.State.CHARGE, "Si le pegan, embiste")
	_comprobar(Boar.flee_direction(Vector3(5.0, 0.0, 0.0), Vector3.ZERO).is_equal_approx(Vector3.RIGHT), "Huye para el lado contrario")
	_comprobar(Boar.charge_hits(Vector3(1.0, 0.0, 0.0), Vector3.ZERO) and not Boar.charge_hits(Vector3(3.0, 0.0, 0.0), Vector3.ZERO), "La embestida pega de cerca")
	var tamano: int = BoarHerd.herd_size(1234, 2, 3)
	_comprobar(tamano >= 2 and tamano <= 3 and tamano == BoarHerd.herd_size(1234, 2, 3), "Los grupos son de 2 o 3, siempre igual con la misma semilla")
	var pilas: Array[ItemStack] = [null, ItemStack.new(_carne, 2), ItemStack.new(_pan, 1)]
	_comprobar(Eater.best_food_slot(pilas) == 2 and Eater.best_food_slot([null] as Array[ItemStack]) == -1, "Se come primero lo que más cura")
	_comprobar(Oven.prompt_for(2, 0, 0.0) == "Horno: asar 2 carnes" and Oven.prompt_for(0, 2, 0.25).begins_with("Horno: asándose") and Oven.prompt_for(0, 2, 0.0) == "Horno: sacar 2 asados", "Lo que dice el horno")
	_comprobar(_carne != null and _asado != null and _pan != null and _carne.cooked == _asado and is_equal_approx(_carne.heal, 10.0) and is_equal_approx(_asado.heal, 40.0) and is_equal_approx(_pan.heal, 20.0), "Carne +10, asado +40, pan +20; la carne se asa")
	var machete := load(MACHETE) as KeyItemData
	_comprobar(machete != null and machete.id == &"machete", "Existe el machete como herramienta clave")
	_comprobar(InputMap.has_action(&"eat") and InputMap.has_action(&"camp"), "Están las acciones R (comer) y N (acampar); si falla, correr tools/setup_project.gd")


func _armar_mundo() -> void:
	var piso := StaticBody3D.new()
	piso.name = "Piso"
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(400.0, 1.0, 400.0)
	forma.shape = caja
	forma.position = Vector3(0.0, -0.5, 0.0)
	piso.add_child(forma)
	add_child(piso)
	_jugador = (load(PLAYER) as PackedScene).instantiate() as Player
	add_child(_jugador)
	_jugador.global_position = Vector3(0.0, 0.1, 0.0)
	await _cuadros(6)
	_jugador.get_sleeper().fade_seconds = 0.0
	_jugador.get_sleeper().start_point = Vector3(0.0, 0.1, 0.0)
	_comprobar(_jugador.get_health() != null and _jugador.get_sleeper() != null, "El jugador tiene Salud, Comer y Dormir")


func _probar_salud_y_comida() -> void:
	var salud: Health = _jugador.get_health()
	salud.set_value(100.0)
	GameState.clock.advance(10.0)
	_comprobar(is_equal_approx(salud.value, 90.0), "Diez horas de juego bajan 10 de salud (queda %.1f)" % salud.value)
	var comer: Eater = _hijo(Eater) as Eater
	_comprobar(not comer.try_eat(), "Sin comida no se come")
	_jugador.get_backpack().try_store(ItemStack.new(_carne, 1))
	_jugador.get_backpack().try_store(ItemStack.new(_pan, 1))
	_comprobar(comer.try_eat() and is_equal_approx(salud.value, 100.0), "Comer el pan sube la salud a 100")
	_comprobar(_jugador.get_backpack().count_of(&"bread") == 0 and _jugador.get_backpack().count_of(&"raw_meat") == 1, "Se comió el pan (lo que más cura) y quedó la carne")
	_comprobar(not comer.try_eat(), "Con la salud llena no se come")
	salud.damage(30.0)
	_comprobar(comer.try_eat() and is_equal_approx(salud.value, 80.0), "La carne cruda suma 10")
	# El resto de la prueba pasa muchas horas: sin hambre, salvo donde se mide.
	salud.decays = false
	await _cuadros(1)


func _probar_horno() -> void:
	var cocina: Wagon = (load(COCINA) as PackedScene).instantiate() as Wagon
	var via := Path3D.new()
	via.curve = Curve3D.new()
	via.curve.add_point(Vector3(10.0, 0.0, -30.0))
	via.curve.add_point(Vector3(10.0, 0.0, 30.0))
	add_child(via)
	via.add_child(cocina)
	await _cuadros(3)
	var horno := cocina.get_node_or_null(^"Visual/Horno") as Oven
	var cama := cocina.get_node_or_null(^"Visual/Cama") as Bed
	_comprobar(horno != null and cama != null and cocina.get_wagon_data().personal, "El vagón cocina tiene horno y cama, y su baúl es personal")
	_comprobar(cocina.get_cargo() != null and cocina.get_cargo().capacity == 20, "El baúl lleva 20")
	if horno == null:
		return
	_jugador.get_backpack().try_store(ItemStack.new(_carne, 3))
	_comprobar(horno.count_raw(_jugador) == 3, "El horno ve las 3 carnes de la mochila")
	_comprobar(horno.load_from(_jugador) == 3 and _jugador.get_backpack().count_of(&"raw_meat") == 0 and horno.is_cooking(), "Las 3 carnes entran a asar")
	GameState.clock.advance(0.25)
	_comprobar(horno.is_cooking() and not horno.is_ready(), "A los 15 minutos todavía se asan")
	GameState.clock.advance(0.3)
	_comprobar(horno.is_ready(), "A la media hora están listas")
	_comprobar(horno.collect(_jugador) == 3 and _jugador.get_backpack().count_of(&"roast_meat") == 3, "Salen 3 carnes asadas a la mochila")
	horno.set_meta(&"probado", true)
	via.queue_free()


func _probar_camas() -> void:
	var cama := Bed.new()
	cama.price = 20
	cama.place_name = "la taberna de prueba"
	add_child(cama)
	cama.global_position = Vector3(3.0, 0.0, 0.0)
	var dormir: Sleeper = _jugador.get_sleeper()
	_ir_a_la_hora(12.0)
	GameState.money = 50
	_comprobar(not await dormir.sleep_in(cama) and GameState.money == 50, "De día no se duerme ni se paga")
	_ir_a_la_hora(21.0)
	var dia: int = GameState.clock.current_day
	var salud: Health = _jugador.get_health()
	salud.set_value(50.0)
	salud.decays = true
	_comprobar(await dormir.sleep_in(cama), "De noche se duerme en la cama")
	salud.decays = false
	_comprobar(GameState.money == 30 and dormir.last_bed == cama, "La taberna cobra $20 y queda como última cama")
	_comprobar(GameState.clock.current_day == dia + 1 and is_equal_approx(GameState.clock.time_of_day, 7.0), "Se despierta a las 7:00 del día siguiente")
	_comprobar(is_equal_approx(salud.value, 40.0), "Dormir no cura: las 10 horas de la noche bajan 10 (queda %.1f)" % salud.value)
	_ir_a_la_hora(22.0)
	GameState.money = 5
	_comprobar(not await dormir.sleep_in(cama), "Sin plata no se duerme en la taberna")
	GameState.money = 0


func _probar_acampar() -> void:
	var dormir: Sleeper = _jugador.get_sleeper()
	_ir_a_la_hora(10.0)
	_comprobar(not await dormir.camp(), "De día no se acampa")
	_ir_a_la_hora(20.0)
	var jabali := Boar.new()
	add_child(jabali)
	jabali.global_position = _jugador.global_position + Vector3(15.0, 0.3, 0.0)
	jabali.set_physics_process(false)
	await _cuadros(1)
	var motivo: Array[StringName] = []
	dormir.sleep_failed.connect(func(razon: StringName) -> void: motivo.append(razon), CONNECT_ONE_SHOT)
	_comprobar(not await dormir.camp() and motivo.size() == 1 and motivo[0] == &"boars", "Con un jabalí a 15 m no se acampa")
	jabali.global_position = _jugador.global_position + Vector3(60.0, 0.3, 0.0)
	_comprobar(await dormir.camp() and is_equal_approx(GameState.clock.time_of_day, 7.0), "Con el jabalí lejos se acampa hasta las 7:00")
	jabali.queue_free()
	await _cuadros(1)


func _probar_jabali() -> void:
	var llaves: KeyItems = _jugador.get_key_items()
	var usar: ToolUser = _hijo(ToolUser) as ToolUser
	var jabali := Boar.new()
	add_child(jabali)
	jabali.global_position = _jugador.global_position + Vector3(0.0, 0.3, -1.8)
	await _cuadros(2)
	var cazar := jabali.get_node_or_null(^"Huntable") as Huntable
	_comprobar(cazar != null and cazar.get_required_tool_id() == &"machete" and cazar.hits_required == 3, "El jabalí se caza con 3 golpes de machete")
	if cazar == null:
		return
	llaves.remove(&"machete")
	_comprobar(not usar.try_use(), "Sin machete no se lo puede cazar")
	llaves.add(load(MACHETE) as KeyItemData)
	_comprobar(usar.try_use() and jabali.state == Boar.State.CHARGE, "Al primer golpe embiste")
	var salud: Health = _jugador.get_health()
	salud.set_value(100.0)
	for _i: int in 40:
		await get_tree().physics_frame
		if salud.value < 100.0:
			break
	_comprobar(is_equal_approx(salud.value, 85.0), "La embestida saca 15 de salud una sola vez (queda %.1f)" % salud.value)
	_comprobar(jabali.state == Boar.State.FLEE, "Después de embestir, huye")
	jabali.set_physics_process(false)
	jabali.global_position = _jugador.global_position + Vector3(0.0, 0.3, -1.8)
	usar.try_use()
	var muerto: Array[bool] = [false]
	jabali.died.connect(func(_j: Boar) -> void: muerto[0] = true)
	usar.try_use()
	_comprobar(muerto[0], "Al tercer golpe cae")
	await _cuadros(2)
	var carnes: int = 0
	for nodo: Node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var cosa := nodo as WorldItem
		if cosa != null and cosa.stack != null and cosa.stack.item.id == &"raw_meat":
			carnes += 1
			cosa.queue_free()
	_comprobar(carnes == 2, "Suelta 2 carnes de jabalí (soltó %d)" % carnes)


func _probar_desmayo() -> void:
	var cama := Bed.new()
	cama.place_name = "la cama de prueba"
	add_child(cama)
	cama.global_position = Vector3(-20.0, 0.0, 5.0)
	var dormir: Sleeper = _jugador.get_sleeper()
	dormir.last_bed = cama
	var hora: float = GameState.clock.time_of_day
	var desmayos: Array[int] = [0]
	EventBus.player_fainted.connect(func() -> void: desmayos[0] += 1, CONNECT_ONE_SHOT)
	_jugador.get_health().damage(500.0)
	await _cuadros(3)
	_comprobar(desmayos[0] == 1, "En 0 de salud se desmaya")
	_comprobar(_jugador.global_position.distance_to(cama.get_wake_point()) < 1.5, "Despierta al lado de la última cama")
	_comprobar(is_equal_approx(_jugador.get_health().value, 30.0), "Despierta con 30 de salud")
	_comprobar(absf(GameState.clock.time_of_day - hora) < 0.1, "El desmayo no adelanta el reloj")
	_comprobar(_jugador.controls_enabled, "Vuelve a tener los controles")


func _probar_taberna() -> void:
	var taberna := (load(TABERNA) as PackedScene).instantiate() as Tavern
	taberna.town_name = "Azul"
	add_child(taberna)
	_comprobar(taberna.get_bed() != null and taberna.get_bed().price == 20 and taberna.get_bed().place_name == "la taberna de Azul", "La taberna tiene su cama a $20")
	var mostrador: FoodSeller = taberna.get_counter()
	_comprobar(mostrador != null and mostrador.item != null and mostrador.item.id == &"bread", "El mostrador vende pan")
	if mostrador == null:
		return
	GameState.money = 3
	_comprobar(not mostrador.buy(_jugador), "Sin plata no se compra pan")
	GameState.money = 10
	var antes: int = _jugador.get_backpack().count_of(&"bread")
	_comprobar(mostrador.buy(_jugador) and GameState.money == 5 and _jugador.get_backpack().count_of(&"bread") == antes + 1, "El pan cuesta $5 y va a la mochila")
	taberna.queue_free()


func _probar_hito_a() -> void:
	GameState.reset_production()
	var mapa := (load(HITO_A) as PackedScene).instantiate() as Node3D
	add_child(mapa)
	for _i: int in 12:
		await get_tree().physics_frame
	var jugador := mapa.get_node_or_null(^"Player") as Player
	_comprobar(jugador != null and jugador.get_key_items().has(&"machete"), "En el Hito A se arranca con el machete")
	# La locomotora se muda a la vía de Olavarría al empezar: se toma la del script del mapa.
	var loco := mapa.get(&"_loco") as Vehicle
	var detras: Wagon = loco.rear as Wagon if loco != null else null
	if loco != null and detras == null:
		for _i: int in 10:
			await get_tree().physics_frame
		detras = loco.rear as Wagon
	_comprobar(detras != null and detras.get_wagon_data().personal, "El vagón cocina va enganchado detrás de la locomotora")
	var tabernas: int = 0
	for nodo: Node in mapa.get_node(^"Tabernas").get_children():
		if nodo is Tavern:
			tabernas += 1
			_comprobar(_distancia_a_la_via(mapa, (nodo as Node3D).global_position) > 12.0, "La %s no pisa la vía" % nodo.name)
	_comprobar(tabernas == 3, "Hay una taberna en cada estación")
	var grupos: int = 0
	var jabalies: int = 0
	for nodo: Node in get_tree().get_nodes_in_group(BoarHerd.GROUP):
		var grupo := nodo as BoarHerd
		grupos += 1
		jabalies += grupo.get_alive_count()
		_comprobar(_distancia_a_la_via(mapa, grupo.global_position) > 50.0, "Los jabalíes de %s están lejos de las vías" % grupo.name)
	_comprobar(grupos == 4 and jabalies >= 8, "Cuatro grupos de jabalíes (%d jabalíes)" % jabalies)
	var terreno := get_tree().get_first_node_in_group(Terrain.GROUP) as Terrain
	if terreno != null:
		for nodo: Node in get_tree().get_nodes_in_group(Boar.GROUP):
			var jabali := nodo as Boar
			var suelo: float = terreno.height_at(jabali.global_position)
			_comprobar(not is_nan(suelo) and absf(jabali.global_position.y - suelo) < 2.0, "%s está sobre el terreno" % jabali.name)
	mapa.queue_free()
	await _cuadros(2)


# Distancia en el plano a la vía más cercana (curvas con TrackBuilder).
func _distancia_a_la_via(mapa: Node, punto: Vector3) -> float:
	var mejor: float = INF
	for nodo: Node in mapa.find_children("*", "", true, false):
		if not nodo is TrackBuilder:
			continue
		var camino := nodo.get_parent() as Path3D
		if camino == null or camino.curve == null:
			continue
		var cerca: Vector3 = camino.to_global(camino.curve.get_closest_point(camino.to_local(punto)))
		mejor = minf(mejor, Vector2(cerca.x - punto.x, cerca.z - punto.z).length())
	return mejor


func _ir_a_la_hora(hora: float) -> void:
	var ahora: float = GameState.clock.time_of_day
	var horas: float = hora - ahora if hora > ahora else GameClock.HOURS_PER_DAY - ahora + hora
	GameState.clock.advance(horas)


func _hijo(tipo: Variant) -> Node:
	for hijo: Node in _jugador.get_children():
		if is_instance_of(hijo, tipo):
			return hijo
	return null


func _cuadros(cuantos: int) -> void:
	for _i: int in cuantos:
		await get_tree().physics_frame


func _comprobar(condicion: bool, texto: String) -> void:
	if condicion:
		print("  ok  ", texto)
	else:
		_fallos += 1
		push_error("  FALLA  " + texto)
