extends Node3D
## Prueba de la tarea 62c.1 (D134): relieve y vía con altura. El Terrain se aplana solo debajo de
## la vía y de un lote, con taludes, y deja las lomas en el resto; el tren siente la pendiente
## (en subida pide menos según su peso, en punto muerto la gravedad lo frena o lo empuja, parado no
## rueda y los automáticos no la sienten); el jugador viaja dentro del tren en subida sin
## deslizarse. Arma todo por código: una vía de unos 700 m que sube 8 m al 4 %, sigue arriba 100 m
## y baja, la locomotora con una plataforma y un lote de campo al costado del tramo plano.
## Las cuentas del tren usan pasos fijos; lo del jugador, unos 6 segundos de cuadros reales (no
## toques nada). Al final te deja sentado en la cabina para manejar por la loma (F para bajarte).

const CONTROLES: String = "WASD: caminar · Shift: correr · Espacio: saltar · F: entrar o salir de la cabina · Esc: soltar el mouse\nEn la cabina: W / S marcha · Espacio freno · V vista"
const PASO: float = 1.0 / 60.0
## Velocidad de la marcha en las cuentas (en m/s; la locomotora llega a 25).
const MARCHA: float = 15.0
## Avance donde empieza la subida, mitad de la subida y mitad de la bajada.
const PIE_DE_LA_LOMA: float = 110.0
const EN_LA_SUBIDA: float = 230.0
const EN_LA_BAJADA: float = 480.0
const PASILLO_LOCAL: Vector3 = Vector3(1.0, 0.85, -2.0)
## Dentro de la cabina, a medio metro del puesto (como en test_walkable_train).
const CERCA_DEL_PUESTO_LOCAL: Vector3 = Vector3(0.4, 0.85, 2.1)

var _fallos: int = 0
var _via: Path3D
var _terreno: Terrain
var _lote: TrackLot
var _loco: Vehicle
var _plataforma: Wagon
var _jugador: Player
var _hud: Label


func _ready() -> void:
	_armar()
	_probar_calculos()
	_probar_terreno()
	await _probar_choque()
	_probar_pendiente()
	await _probar_caminar()
	if _fallos == 0:
		print("Relieve: todas las comprobaciones pasaron.")
	else:
		push_error("Relieve: fallaron %d comprobaciones." % _fallos)
	await _dejar_para_jugar()


func _process(_delta: float) -> void:
	if _hud == null or _loco == null:
		return
	var pendiente: String = CabHud.grade_text(_loco.get_grade(), _loco.speed)
	_hud.text = "%s\n%.0f km/h · %s · Peso del tren: %.1f" % [CONTROLES, absf(_loco.speed) * 3.6, pendiente if not pendiente.is_empty() else "En plano", _loco.get_train_weight()]


func _armar() -> void:
	var ambiente := WorldEnvironment.new()
	ambiente.environment = Environment.new()
	ambiente.environment.background_mode = Environment.BG_SKY
	ambiente.environment.sky = Sky.new()
	ambiente.environment.sky.sky_material = ProceduralSkyMaterial.new()
	add_child(ambiente)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sol.shadow_enabled = true
	add_child(sol)

	# Plano 100 m, sube 8 m en 200 m (manijas cortas: casi todo al 4 %), arriba 100 m, baja igual y plano.
	var curva := Curve3D.new()
	curva.add_point(Vector3(0, 0, 0), Vector3.ZERO, Vector3(0, 0, -15))
	curva.add_point(Vector3(0, 0, -100), Vector3(0, 0, 15), Vector3(0, 0, -15))
	curva.add_point(Vector3(0, 8, -300), Vector3(0, 0, 15), Vector3(0, 0, -15))
	curva.add_point(Vector3(0, 8, -400), Vector3(0, 0, 15), Vector3(0, 0, -15))
	curva.add_point(Vector3(0, 0, -600), Vector3(0, 0, 15), Vector3(0, 0, -15))
	curva.add_point(Vector3(0, 0, -700), Vector3(0, 0, 15), Vector3.ZERO)
	_via = Path3D.new()
	_via.name = "Loma"
	_via.curve = curva
	add_child(_via)
	var tramo := TrackSegment.new()
	tramo.name = "TrackSegment"
	tramo.segment_id = &"loma"
	tramo.condition = 1.0
	_via.add_child(tramo)
	var modulo := BoxMesh.new()
	modulo.size = Vector3(1.6, 0.2, 4.8)
	var constructor := TrackBuilder.new()
	constructor.module_mesh = modulo
	constructor.segment = tramo
	_via.add_child(constructor)

	_loco = (load("res://scenes/vehicles/locomotive.tscn") as PackedScene).instantiate() as Vehicle
	_via.add_child(_loco)
	_plataforma = (load("res://scenes/vehicles/flatcar.tscn") as PackedScene).instantiate() as Wagon
	_via.add_child(_plataforma)
	# Las cuentas van con pasos fijos: que no simulen solos hasta la prueba del jugador.
	_loco.set_physics_process(false)
	_plataforma.set_physics_process(false)
	_loco.absolute_throttle = true
	_comprobar(_loco.couple(_plataforma), "La plataforma se acopla detrás de la locomotora")

	# Lote de campo al costado del tramo plano: queda plano a su altura (0) aunque haya lomas.
	_lote = TrackLot.new()
	_lote.station_id = &"loma"
	_lote.position = Vector3(70, 0, -40)
	_lote.rotation_degrees = Vector3(0, -90, 0)
	add_child(_lote)

	var ruido := FastNoiseLite.new()
	ruido.seed = 7
	ruido.frequency = 0.01
	_terreno = Terrain.new()
	_terreno.name = "Terreno"
	_terreno.position = Vector3(0, 0, -350)
	_terreno.size = Vector2(300, 800)
	_terreno.noise = ruido
	_terreno.noise_height = 12.0
	# Se agrega último: al entrar al árbol se arma con la vía y el lote que encuentra.
	add_child(_terreno)


func _probar_calculos() -> void:
	_comprobar(is_zero_approx(Terrain.blend_weight(0.0, 5.0, 8.0, 60.0, 2.0)), "Pegado a la vía pesa solo la altura de la vía")
	_comprobar(is_equal_approx(Terrain.blend_weight(100.0, 5.0, 8.0, 60.0, 2.0), 1.0), "Lejos pesa solo la altura propia")
	_comprobar(is_equal_approx(Terrain.blend_weight(10.0, 10.0, 8.0, 60.0, 2.0), 0.5), "Un desnivel de 10 m abre un talud de 20 m (a 10 m, mitad y mitad)")
	_comprobar(is_equal_approx(Terrain.blend_weight(4.0, 0.5, 8.0, 60.0, 2.0), 0.5), "Con poco desnivel el talud no baja del mínimo (8 m)")
	_comprobar(is_zero_approx(Terrain.rect_distance(Vector2(1, -2), Vector2(5, 5))), "Adentro del rectángulo la distancia es 0")
	_comprobar(is_equal_approx(Terrain.rect_distance(Vector2(8, 0), Vector2(5, 5)), 3.0) and is_equal_approx(Terrain.rect_distance(Vector2(8, -9), Vector2(5, 5)), 5.0), "Distancia al rectángulo de costado y en diagonal")
	_comprobar(is_equal_approx(Vehicle.grade_of(Vector3(0, 1, -25)), 0.04), "Subir 1 m en 25 m es el 4 %")
	_comprobar(is_equal_approx(Vehicle.climb_fraction(0.04, 3.0, 30.0), 0.6), "Peso 3 en el 4 % con fuerza 30: el 60 % de la marcha")
	_comprobar(is_equal_approx(Vehicle.climb_fraction(-0.04, 3.0, 30.0), 1.0), "En bajada pide toda su marcha")
	_comprobar(is_equal_approx(Vehicle.climb_fraction(0.5, 3.0, 30.0), Vehicle.MIN_CLIMB_FRACTION) and is_equal_approx(Vehicle.climb_fraction(0.01, 1.0, 0.0), Vehicle.MIN_CLIMB_FRACTION), "Nunca pide menos que el mínimo, y sin fuerza se arrastra")
	_comprobar(is_zero_approx(Vehicle.roll(0.0, 0.05, 1.0)), "Parado en la pendiente no rueda")
	_comprobar(is_equal_approx(Vehicle.roll(5.0, -0.04, 1.0), 5.0 + Vehicle.GRADE_GRAVITY * 0.04), "En bajada la gravedad lo empuja")
	_comprobar(is_zero_approx(Vehicle.roll(0.3, 0.1, 1.0)), "En subida la gravedad lo frena hasta pararlo, sin darlo vuelta")
	_comprobar(CabHud.grade_text(0.04, 5.0) == "Sube 4 %" and CabHud.grade_text(0.04, -5.0) == "Baja 4 %", "La cabina dice si sube o baja según para dónde va")
	_comprobar(CabHud.grade_text(0.004, 1.0) == "" and CabHud.grade_text(-0.03, 0.0) == "Baja 3 %", "Casi en plano no dice nada; parado cuenta hacia donde mira")
	var vagon := WagonData.new()
	_comprobar(is_equal_approx(vagon.weight, 0.4) and is_equal_approx(vagon.load_weight, 0.6) and is_zero_approx(vagon.climb_power), "Un vagón pesa 0,4, suma 0,6 lleno y no tira")
	_comprobar(is_equal_approx(_loco.data.weight, 1.0) and _loco.data.climb_power > 0.0, "La locomotora pesa 1 y tira")


func _probar_terreno() -> void:
	_comprobar(_terreno.get_columns() == 76 and _terreno.get_rows() == 201, "Grilla de 300 x 800 m en cuadros de 4 m (%d x %d vértices)" % [_terreno.get_columns(), _terreno.get_rows()])
	var largo: float = _via.curve.get_baked_length()
	var peor: float = 0.0
	var peor_costado: float = 0.0
	var paso: float = 0.0
	while paso <= largo:
		var punto: Vector3 = _via.global_transform * _via.curve.sample_baked(paso)
		peor = maxf(peor, absf(_terreno.height_at(punto) - punto.y))
		peor_costado = maxf(peor_costado, absf(_terreno.height_at(punto + Vector3(2, 0, 0)) - punto.y))
		paso += 5.0
	_comprobar(peor < 0.15, "Debajo de la vía el suelo va a la altura de la vía, también en la subida (peor: %.3f m)" % peor)
	_comprobar(peor_costado < 0.15, "A 2 m de costado sigue el corredor plano (peor: %.3f m)" % peor_costado)
	var lote_peor: float = 0.0
	for x: float in [-45.0, 0.0, 45.0]:
		for z: float in [-45.0, 0.0, 45.0]:
			lote_peor = maxf(lote_peor, absf(_terreno.height_at(_lote.global_transform * Vector3(x, 0, z))))
	_comprobar(lote_peor < 0.01, "El lote queda plano a su altura (peor: %.3f m)" % lote_peor)
	# Un vértice lejos de todo conserva la altura propia; en el terreno hay lomas de verdad.
	var lejos: Vector2 = _terreno.vertex_position(2, 100)
	_comprobar(is_equal_approx(_terreno.vertex_height(2, 100), _terreno.base_height_at(lejos.x, lejos.y)), "Lejos de la vía el terreno conserva su loma")
	var alto: float = 0.0
	var empinado: float = 0.0
	for j: int in _terreno.get_rows():
		for i: int in _terreno.get_columns():
			alto = maxf(alto, _terreno.vertex_height(i, j))
			if i > 0:
				empinado = maxf(empinado, absf(_terreno.vertex_height(i, j) - _terreno.vertex_height(i - 1, j)) / _terreno.cell_size)
			if j > 0:
				empinado = maxf(empinado, absf(_terreno.vertex_height(i, j) - _terreno.vertex_height(i, j - 1)) / _terreno.cell_size)
	_comprobar(alto > 4.0, "Hay lomas (la más alta: %.1f m)" % alto)
	_comprobar(empinado < 1.0, "Ni la vía ni el lote dejan paredes: el talud más empinado sube %.2f m por metro" % empinado)
	# Arriba de la loma la vía va en terraplén o en trinchera: al costado, entre la vía y la loma.
	var cima: Vector3 = _via.global_transform * _via.curve.sample_baked(350.0)
	var lado: Vector3 = cima + Vector3(-12, 0, 0)
	var propia: float = _terreno.base_height_at(_terreno.to_local(lado).x, _terreno.to_local(lado).z)
	var al_lado: float = _terreno.height_at(lado)
	_comprobar(al_lado >= minf(cima.y, propia) - 0.01 and al_lado <= maxf(cima.y, propia) + 0.01, "A 12 m de la vía el talud queda entre la vía (%.1f m) y la loma (%.1f m): %.1f m" % [cima.y, propia, al_lado])
	var malla := _terreno.get_node_or_null(Terrain.MESH_NODE_NAME) as MeshInstance3D
	_comprobar(malla != null and malla.mesh != null and _terreno.is_in_group(Terrain.GROUP), "El terreno tiene su malla y está en el grupo terrain")


func _probar_choque() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var desde := Vector3(-30, 60, -200)
	var consulta := PhysicsRayQueryParameters3D.create(desde, desde + Vector3(0, -120, 0))
	var golpe: Dictionary = get_world_3d().direct_space_state.intersect_ray(consulta)
	var esperado: float = _terreno.height_at(desde)
	_comprobar(not golpe.is_empty() and golpe.get("collider") == _terreno, "El terreno se pisa (tiene forma de choque)")
	if not golpe.is_empty():
		var altura: float = (golpe["position"] as Vector3).y
		_comprobar(absf(altura - esperado) < 0.05, "Se pisa donde se ve (choque %.2f m, malla %.2f m)" % [altura, esperado])


func _probar_pendiente() -> void:
	_poner(20.0, MARCHA, MARCHA)
	_correr(3.0)
	_comprobar(absf(_loco.speed - MARCHA) < 0.1 and absf(_loco.get_grade()) < 0.005, "En plano anda a su marcha (%.1f m/s)" % _loco.speed)
	_poner(EN_LA_SUBIDA, 0.0, 0.0)
	var subida: float = _loco.get_grade()
	_comprobar(subida > 0.03 and subida < 0.06, "En la subida el tren mira para arriba (%.1f %%)" % (subida * 100.0))
	_poner(EN_LA_BAJADA, 0.0, 0.0)
	_comprobar(_loco.get_grade() < -0.03, "En la bajada mira para abajo (%.1f %%)" % (_loco.get_grade() * 100.0))

	var vacio: float = _subir()
	var esperado: float = MARCHA * Vehicle.climb_fraction(_loco.get_grade(), _loco.get_train_weight(), _loco.get_train_climb_power())
	_comprobar(vacio < MARCHA - 1.0 and absf(vacio - esperado) < 0.4, "Subiendo con la plataforma vacía va más despacio (%.1f m/s; esperado %.1f)" % [vacio, esperado])
	var sobrante: ItemStack = _plataforma.get_cargo().try_store(ItemStack.new(load("res://data/items/limestone.tres") as ItemData, 20))
	_comprobar(sobrante == null and is_equal_approx(_plataforma.get_weight(), 1.0), "Con 20 piedras la plataforma pesa 1 (%.2f)" % _plataforma.get_weight())
	var lleno: float = _subir()
	_comprobar(lleno < vacio - 0.5, "Cargado sube más despacio que vacío (%.1f contra %.1f m/s)" % [lleno, vacio])
	_plataforma.get_cargo().take(0, 20)
	_loco.uncouple_rear()
	_plataforma.progress = 690.0
	var solo: float = _subir()
	_comprobar(solo > vacio + 0.4, "La locomotora sola sube más rápido (%.1f m/s)" % solo)

	_poner(EN_LA_BAJADA - 30.0, 8.0, 0.0)
	_correr(5.0)
	_comprobar(_loco.speed > 8.25, "En punto muerto, en bajada, acelera (8 a %.2f m/s)" % _loco.speed)
	_poner(150.0, 8.0, 0.0)
	_correr(3.0)
	_comprobar(_loco.speed < 6.5 and _loco.speed > 0.0, "En punto muerto, en subida, frena más que en plano (8 a %.2f m/s)" % _loco.speed)
	_poner(EN_LA_SUBIDA, 0.0, 0.0)
	_correr(3.0)
	_comprobar(is_zero_approx(_loco.speed) and is_equal_approx(_loco.progress, EN_LA_SUBIDA), "Parado en la subida no rueda para atrás")
	_poner(EN_LA_BAJADA, 0.0, 0.0)
	_correr(3.0)
	_comprobar(is_zero_approx(_loco.speed), "Parado en la bajada tampoco")

	_loco.automatic = true
	_loco.absolute_throttle = false
	_poner(PIE_DE_LA_LOMA, MARCHA, MARCHA)
	_loco.throttle = MARCHA / _loco.get_max_speed()
	_correr_hasta(EN_LA_SUBIDA)
	_comprobar(absf(_loco.speed - MARCHA) < 0.1, "Un automático no siente la pendiente (%.1f m/s)" % _loco.speed)
	_loco.automatic = false
	_loco.absolute_throttle = true
	# De vuelta con la plataforma para lo que sigue.
	_poner(PIE_DE_LA_LOMA, 0.0, 0.0)
	_plataforma.progress = PIE_DE_LA_LOMA - Vehicle.coupling_distance(_loco.data.length, _plataforma.data.length)
	_comprobar(_loco.couple(_plataforma), "Se vuelve a acoplar la plataforma")
	_loco.place_rear_vehicles()


# Arranca parado al pie de la loma y sube con la marcha puesta: la velocidad a mitad de subida.
func _subir() -> float:
	_poner(PIE_DE_LA_LOMA, 0.0, MARCHA)
	_correr_hasta(EN_LA_SUBIDA)
	return _loco.speed


func _probar_caminar() -> void:
	_jugador = (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	add_child(_jugador)
	# La cámara de afuera de la cabina entró antes al árbol y quedó como la actual: la del jugador manda.
	_camara_del_jugador().make_current()
	_jugador.get_camera().set_process_unhandled_input(false)
	_poner(PIE_DE_LA_LOMA, 0.0, 0.0)
	_loco.set_physics_process(true)
	_plataforma.set_physics_process(true)
	await _esperar(2)
	_jugador.global_position = _loco.global_transform * PASILLO_LOCAL
	_jugador.velocity = Vector3.ZERO
	await _esperar(20)
	_comprobar(_jugador.get_platform() == _loco, "Parado sobre la locomotora queda enganchado a ella")
	var antes: Vector3 = _loco.global_transform.affine_inverse() * _jugador.global_position
	var altura: float = _jugador.global_position.y
	_loco.speed = 8.0
	_loco.throttle = 8.0 / _loco.data.max_speed
	await _esperar(480)
	var recorrido: float = _loco.progress - PIE_DE_LA_LOMA
	var subio: float = _jugador.global_position.y - altura
	var deslizamiento: float = (_loco.global_transform.affine_inverse() * _jugador.global_position).distance_to(antes)
	_comprobar(recorrido > 30.0 and subio > 1.0, "El tren subió la loma con el jugador arriba (%.0f m, %.1f m más alto)" % [recorrido, subio])
	_comprobar(_jugador.get_platform() == _loco and deslizamiento < 0.15, "Subiendo no se desliza (%.3f m) y sigue enganchado" % deslizamiento)


func _dejar_para_jugar() -> void:
	_loco.throttle = 0.0
	_poner(20.0, 0.0, 0.0)
	await _esperar(2)
	# Directo al puesto: la cabina solo deja entrar a 1,5 m del puesto, yendo arriba de la locomotora.
	_jugador.global_position = _loco.global_transform * CERCA_DEL_PUESTO_LOCAL
	_jugador.velocity = Vector3.ZERO
	await _esperar(20)
	_jugador.get_camera().set_process_unhandled_input(true)
	if not _jugador.try_enter_cab():
		_camara_del_jugador().make_current()
		push_warning("Relieve: no pude sentarte en la cabina; subí por la rampa y apretá F junto al puesto.")


func _camara_del_jugador() -> Camera3D:
	return _jugador.find_children("*", "Camera3D", true, false)[0] as Camera3D
	var capa := CanvasLayer.new()
	_hud = Label.new()
	_hud.position = Vector2(12, 12)
	_hud.add_theme_font_size_override(&"font_size", 16)
	_hud.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override(&"outline_size", 5)
	capa.add_child(_hud)
	add_child(capa)


# La locomotora en `avance` con esa velocidad y el acelerador pidiendo `marcha` m/s.
func _poner(avance: float, velocidad: float, marcha: float) -> void:
	_loco.progress = avance
	_loco.speed = velocidad
	_loco.brake = 0.0
	_loco.throttle = marcha / _loco.data.max_speed
	_loco.place_rear_vehicles()


func _correr(segundos: float) -> void:
	for _i: int in roundi(segundos / PASO):
		_loco.simulate(PASO)


func _correr_hasta(avance: float) -> void:
	for _i: int in roundi(60.0 / PASO):
		if _loco.progress >= avance:
			return
		_loco.simulate(PASO)


func _esperar(cuadros: int) -> void:
	for _i: int in cuadros:
		await get_tree().physics_frame


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
