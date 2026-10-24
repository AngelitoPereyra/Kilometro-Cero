extends Node3D
## Prueba de la tarea 53: vagones por tipo de carga (D85), acople y topes.
## Supone una vía recta de 200 m, la locomotora en el avance 60, una plataforma con
## `couple_on_start` justo detrás (49,4) y otra plataforma suelta más atrás (20).
## Primero corre la lógica del tren paso a paso (sin esperar cuadros) y después, con
## cuadros de física reales, carga y descarga troncos en la plataforma; no toques nada
## durante unos 3 segundos.
## Después se puede jugar: hay troncos y bulones al lado de la plataforma.

const CONTROLES: String = "WASD: caminar · E: recoger o sacar del vagón · Q: soltar (adentro del vagón lo carga) · F: cabina · U: desacoplar el último vagón\nPara acoplar la plataforma suelta: desde la cabina, marcha atrás hasta tocarla."
const LOG_DATA: ItemData = preload("res://data/items/log.tres")
const PASO_S: float = 1.0 / 60.0
const INICIO_M: float = 60.0
## Sobre el piso de la plataforma, hacia la cola.
const SOBRE_LA_PLATAFORMA_LOCAL: Vector3 = Vector3(0.0, 0.85, 3.0)

@onready var _loco: Vehicle = $Track/Locomotive
@onready var _flatcar: Wagon = $Track/Flatcar
@onready var _suelta: Wagon = $Track/PlataformaSuelta
@onready var _track: Path3D = $Track
@onready var _player: Player = $Player
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0
var _bulon: ItemData


func _ready() -> void:
	_bulon = ItemData.new()
	_bulon.id = &"bolt"
	_bulon.display_name = "bulón"
	_probar_calculos()
	# couple_on_start acopla en diferido: al terminar el primer cuadro ya está.
	await get_tree().process_frame
	await get_tree().physics_frame
	_probar_armado()
	_probar_tren_paso_a_paso()
	await _probar_carga()

	if _fallos == 0:
		print("Vagones: todas las comprobaciones pasaron.")
	else:
		push_error("Vagones: fallaron %d comprobaciones." % _fallos)
	_preparar_para_jugar()


func _unhandled_input(event: InputEvent) -> void:
	var tecla := event as InputEventKey
	if tecla != null and tecla.pressed and not tecla.echo and tecla.physical_keycode == KEY_U:
		var ultimo: Vehicle = _loco.get_tail()
		if ultimo != _loco:
			ultimo.front.uncouple_rear()


func _process(_delta: float) -> void:
	var tren: PackedStringArray = []
	for vehiculo: Vehicle in _loco.get_train():
		tren.append(String(vehiculo.name))
	_hud.text = "%s\nTren: %s · Velocidad: %.0f km/h\nPlataforma: %s\nSuelta: %s" % [
		CONTROLES, " + ".join(tren), absf(_loco.speed) * 3.6,
		_texto_carga(_flatcar), _texto_carga(_suelta),
	]


func _probar_calculos() -> void:
	_comprobar(is_equal_approx(Vehicle.coupling_distance(10.0, 10.0), 10.6), "Dos vehículos de 10 m acoplados: centros a 10,6 m")
	_comprobar(is_equal_approx(Wagon.fill_ratio(5, 20), 0.25), "5 de 20 es un cuarto lleno")
	_comprobar(is_zero_approx(Wagon.fill_ratio(3, 0)) and is_equal_approx(Wagon.fill_ratio(30, 20), 1.0), "Sin capacidad da 0 y de más da 1")
	_comprobar(WagonData.cargo_type_name(WagonData.CargoType.HOPPER) == "tolva", "Nombre del tipo de carga")


func _probar_armado() -> void:
	_comprobar(_flatcar.front == _loco and _loco.rear == _flatcar, "La plataforma con couple_on_start se acopló a la locomotora")
	_comprobar(_suelta.front == null and _flatcar.rear == null, "La plataforma suelta quedó suelta")
	_comprobar(is_equal_approx(_loco.progress - _flatcar.progress, 10.6), "Acoplada queda a 10,6 m de centro a centro")
	_comprobar(_loco.get_train() == [_loco, _flatcar] and _flatcar.get_head() == _loco and _loco.get_tail() == _flatcar, "El tren es locomotora + plataforma")
	var carga: StorageContainer = _flatcar.get_cargo()
	_comprobar(carga != null and carga.capacity == 20 and carga.container_id == &"flatcar", "La plataforma lleva 20 unidades (de su WagonData)")
	_comprobar(carga.accepts(LOG_DATA) and not carga.accepts(_bulon), "Acepta troncos y no bulones")
	var limite: float = minf(_loco.data.get_max_speed(1.0), _flatcar.data.get_max_speed(1.0))
	_comprobar(is_equal_approx(_loco.get_max_speed(), limite) and is_equal_approx(_flatcar.get_max_speed(), limite), "La velocidad máxima es la del más lento del tren (%.0f m/s)" % limite)


# Con la simulación de los vehículos apagada: cada paso se da a mano con simulate().
func _probar_tren_paso_a_paso() -> void:
	for vehiculo: Vehicle in [_loco, _flatcar, _suelta]:
		vehiculo.set_physics_process(false)
	var largo: float = (_track.curve as Curve3D).get_baked_length()

	# Tope del final: la punta de la locomotora queda justo en el extremo.
	_poner(_loco, largo - 10.0, 10.0)
	_simular([_loco], 3.0)
	_comprobar(is_equal_approx(_loco.progress, largo - 5.0) and is_zero_approx(_loco.speed), "Al final de la vía frena con la punta en el tope (%.2f)" % _loco.progress)
	_comprobar(is_equal_approx(_loco.progress - _flatcar.progress, 10.6), "La plataforma lo sigue a la distancia de acople")

	# Marcha atrás contra la suelta: frena en seco sin superponerse y se le acopla.
	_poner(_loco, 100.0, -6.0)
	_simular([_loco, _suelta], 20.0)
	var hueco: float = (_flatcar.progress - 5.0) - (_suelta.progress + 5.0)
	_comprobar(is_equal_approx(hueco, Vehicle.COUPLING_GAP) and is_zero_approx(_loco.speed), "Marcha atrás contra un vagón suelto frena en seco con 0,6 m de hueco (%.2f m)" % hueco)
	_comprobar(_flatcar.rear == _suelta and _suelta.front == _flatcar, "Y se le acopla")
	_comprobar(_loco.get_train().size() == 3 and _suelta.get_head() == _loco, "El tren ahora tiene tres vehículos")
	_comprobar(_flatcar.get_node("Visual/Pasarela").visible and not _suelta.get_node("Visual/Pasarela").visible, "Aparece la pasarela de la plataforma del medio")

	# Desacoplar: la suelta vuelve a ser un tren aparte.
	_comprobar(_flatcar.uncouple_rear() == _suelta and _suelta.front == null and _flatcar.rear == null, "uncouple_rear suelta el último vagón")
	_comprobar(not _flatcar.get_node("Visual/Pasarela").visible, "Y su pasarela se esconde")
	_comprobar(_flatcar.uncouple_rear() == null, "Sin nada atrás, uncouple_rear devuelve null")
	_comprobar(not _flatcar.couple(_loco) and not _loco.couple(_suelta), "No se acopla a sí mismo ni a una cola ya ocupada")

	# Un vagón desacoplado en marcha sigue rodando y frena solo.
	_poner(_suelta, 30.0, 0.0)
	_poner(_loco, 150.0, 3.0)
	_loco.throttle = 3.0 / _loco.get_max_speed()
	_flatcar.front.uncouple_rear()
	_simular([_loco, _flatcar], 1.0)
	_comprobar(_flatcar.speed > 2.0 and _flatcar.speed < 3.0, "Desacoplada en marcha, la plataforma rueda y frena despacio (%.2f m/s)" % _flatcar.speed)
	_comprobar(is_equal_approx(_loco.speed, 3.0), "La locomotora sigue a su marcha")
	_loco.throttle = 0.0
	_poner(_flatcar, 50.0, 0.0)
	_poner(_loco, 70.0, 0.0)
	_comprobar(_loco.couple(_flatcar) and is_equal_approx(_flatcar.progress, 70.0 - 10.6), "couple() la trae a la distancia de acople")

	# Tope del principio: la cola no sale de la vía.
	_poner(_loco, 40.0, -6.0)
	_suelta.progress = 180.0
	_simular([_loco, _suelta], 10.0)
	_comprobar(is_equal_approx(_flatcar.progress, 5.0) and is_equal_approx(_loco.progress, 15.6), "Marcha atrás, frena con la cola de la plataforma en el tope (%.2f)" % _flatcar.progress)

	# De frente contra un vagón suelto: frena, sin superponerse ni acoplarse.
	_poner(_loco, 150.0, 10.0)
	_simular([_loco, _suelta], 5.0)
	var hueco_frente: float = (_suelta.progress - 5.0) - (_loco.progress + 5.0)
	_comprobar(is_equal_approx(hueco_frente, Vehicle.COUPLING_GAP) and _suelta.front == null and _loco.front == null, "De frente contra un vagón suelto frena con 0,6 m de hueco y no se acopla")

	# Si los pusieron superpuestos (por ejemplo en el editor), no salta de golpe: solo no empeora.
	_suelta.progress = _loco.progress + 6.0
	var antes: float = _loco.progress
	_poner(_loco, antes, 2.0)
	_simular([_loco], 0.2)
	_comprobar(is_equal_approx(_loco.progress, antes), "Superpuesto con otro, no avanza hacia él ni se teletransporta")

	_suelta.progress = 20.0
	_poner(_loco, INICIO_M, 0.0)
	for vehiculo: Vehicle in [_loco, _flatcar, _suelta]:
		vehiculo.set_physics_process(true)


func _probar_carga() -> void:
	var carga: StorageContainer = _flatcar.get_cargo()
	var visual: Node3D = _flatcar.get_node("Visual/Carga")
	_comprobar(not visual.visible, "Vacía, la carga no se ve")

	var tronco: WorldItem = _soltar_sobre_la_plataforma(LOG_DATA, Vector3(0.0, 1.6, 0.0))
	var bulon: WorldItem = _soltar_sobre_la_plataforma(_bulon, Vector3(0.0, 1.6, -4.0))
	await _esperar(45)
	_comprobar(carga.count_of(&"log") == 1 and not is_instance_valid(tronco), "Un tronco que cae en la plataforma se carga")
	_comprobar(visual.visible and is_equal_approx(visual.scale.y, 1.0 / 20.0), "La carga se ve, a 1/20 de altura")
	_comprobar(is_instance_valid(bulon) and carga.count_of(&"bolt") == 0, "Un bulón no es carga de plataforma: queda suelto")

	# Parado sobre la plataforma, E saca un tronco a la mano y Q lo vuelve a cargar.
	_player.global_position = _flatcar.global_transform * SOBRE_LA_PLATAFORMA_LOCAL
	_player.velocity = Vector3.ZERO
	await _esperar(10)
	var grabber: Grabber = _player.get_node("Grabber")
	_comprobar(grabber.try_grab(), "E al lado de la carga saca algo")
	_comprobar(carga.count_of(&"log") == 0 and grabber.get_held_item() != null and grabber.get_held_item().stack.item.id == &"log", "Sacó el tronco a las manos")
	await _esperar(5)
	_comprobar(grabber.drop_held(), "Q lo suelta")
	await _esperar(45)
	_comprobar(carga.count_of(&"log") == 1 and _player.get_hands().is_empty(), "Soltado sobre la plataforma, se vuelve a cargar")
	bulon.queue_free()


func _preparar_para_jugar() -> void:
	_player.global_position = Vector3(4.0, 0.2, -_flatcar.progress)
	_player.velocity = Vector3.ZERO
	for i: int in 6:
		var tronco: WorldItem = WorldItem.create(ItemStack.new(LOG_DATA, 1))
		add_child(tronco)
		tronco.global_position = Vector3(6.0, 0.3, -_flatcar.progress - 3.0 + i * 0.8)
	for i: int in 2:
		var bulon: WorldItem = WorldItem.create(ItemStack.new(_bulon, 1))
		add_child(bulon)
		bulon.global_position = Vector3(5.0, 0.3, -_flatcar.progress + 3.0 + i)


func _soltar_sobre_la_plataforma(dato: ItemData, local: Vector3) -> WorldItem:
	var objeto: WorldItem = WorldItem.create(ItemStack.new(dato, 1))
	add_child(objeto)
	objeto.global_position = _flatcar.global_transform * local
	return objeto


func _texto_carga(vagon: Wagon) -> String:
	var carga: StorageContainer = vagon.get_cargo()
	var partes: PackedStringArray = []
	for i: int in carga.get_stack_count():
		var pila: ItemStack = carga.peek(i)
		partes.append("%s x%d" % [pila.item.display_name, pila.quantity])
	var contenido: String = "vacía" if partes.is_empty() else ", ".join(partes)
	return "%s (%d de %d)" % [contenido, carga.get_total(), carga.capacity]


func _poner(vehiculo: Vehicle, avance: float, velocidad: float) -> void:
	vehiculo.progress = avance
	vehiculo.speed = velocidad
	vehiculo.throttle = signf(velocidad) if not is_zero_approx(velocidad) else 0.0
	vehiculo.place_rear_vehicles()


# Los vehículos de `cabezas` simulan en orden; los acoplados detrás los ubica su cabeza.
func _simular(cabezas: Array, segundos: float) -> void:
	for _i: int in roundi(segundos / PASO_S):
		for vehiculo: Vehicle in cabezas:
			vehiculo.simulate(PASO_S)


func _esperar(cuadros: int) -> void:
	for _i: int in cuadros:
		await get_tree().physics_frame


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
