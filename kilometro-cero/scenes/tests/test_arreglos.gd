extends Node3D
## Prueba de la tarea 62c.3f (arreglos de 07-debug.md): el TAB pausa el juego entero; el terreno
## tiene borde (no se cae al vacío desde la sierra); las barreras del paso a nivel bajan con el tren;
## los rieles cubren cada tramo hasta la punta (sin salto en las uniones); los que dan misiones
## están apoyados en el suelo; la locomotora es azul, blanca y amarilla; F11 y F3; las parcelas
## juntan sus mallas y lo lejano no se dibuja. Toca la partida de GameState.

const HITO_A: String = "res://scenes/hito_a/hito_a.tscn"
const CORRAL: String = "res://scenes/parcels/corral.tscn"

var _fallos: int = 0
var _mapa: Node3D


func _ready() -> void:
	_probar_logica()
	GameState.reset_production()
	_mapa = (load(HITO_A) as PackedScene).instantiate() as Node3D
	add_child(_mapa)
	for _i: int in 8:
		await get_tree().physics_frame
	_probar_rieles()
	_probar_borde()
	_probar_dadores()
	_probar_colores()
	_probar_distancias()
	await _probar_paso_a_nivel()
	await _probar_pausa()
	await _probar_juntar_mallas()
	get_tree().paused = false
	_mapa.queue_free()
	if _fallos == 0:
		print("Arreglos: todas las comprobaciones pasaron.")
	else:
		push_error("Arreglos: fallaron %d comprobaciones." % _fallos)


func _probar_logica() -> void:
	_comprobar(TrackBuilder.module_count(203.0, 5.0) == 41 and TrackBuilder.module_count(201.0, 5.0) == 40, "Los módulos de vía se estiran o achican para cubrir el tramo")
	_comprobar(is_equal_approx(TrackBuilder.module_step(201.0, 5.0) * 40.0, 201.0), "40 módulos de 5,025 m cubren 201 m justos")
	var paredes: Array[Rect2] = Terrain.edge_wall_rects(Vector2(500.0, 5400.0), 4.0)
	_comprobar(paredes.size() == 4 and is_equal_approx(paredes[0].position.x, -252.0) and is_equal_approx(paredes[3].position.y, 2702.0), "Cuatro paredes del borde, por fuera del terreno")
	var trenes: Array[Vector3] = [Vector3(0.0, 0.0, 200.0)]
	_comprobar(not LevelCrossing.any_near(Vector3.ZERO, trenes, 90.0) and LevelCrossing.any_near(Vector3.ZERO, trenes, 250.0), "El paso a nivel mira la distancia en el plano")
	var caja: Array = BoxMesh.new().get_mesh_arrays()
	_comprobar((MeshBatcher.surface_format(caja) & Mesh.ARRAY_FORMAT_NORMAL) != 0, "MeshBatcher ve que una caja trae normales")
	_comprobar(PerfOverlay.format_stats({"fps": 60}).begins_with("60 cuadros/s"), "El medidor de rendimiento arma su texto")
	_comprobar(InputMap.has_action(&"fullscreen") and InputMap.has_action(&"debug_stats"), "Están las acciones F11 (pantalla completa) y F3 (medidor); si falla, correr tools/setup_project.gd")


func _probar_rieles() -> void:
	var tramos: int = 0
	var cortos: Array[String] = []
	for nodo: Node in _todos():
		var constructor := nodo as TrackBuilder
		if constructor == null:
			continue
		var camino := constructor.get_parent() as Path3D
		var modulos: MultiMeshInstance3D = constructor.get_modules_instance()
		if camino == null or camino.curve == null or modulos == null or modulos.multimesh == null:
			continue
		var largo: float = camino.curve.get_baked_length()
		var cantidad: int = modulos.multimesh.instance_count
		tramos += 1
		if cantidad == 0 or absf(cantidad * TrackBuilder.module_step(largo, constructor.module_length) - largo) > 0.01:
			cortos.append(String(camino.name))
	_comprobar(tramos > 10 and cortos.is_empty(), "Los rieles de las %d vías llegan a las dos puntas (sin cubrir: %s)" % [tramos, cortos])


func _probar_borde() -> void:
	var terreno := get_tree().get_first_node_in_group(Terrain.GROUP) as Terrain
	_comprobar(terreno != null and terreno.get_edge_wall_count() == 4, "El terreno tiene sus cuatro paredes de borde")
	if terreno == null:
		return
	# Cerca de la punta sur (la sierra), caminando hacia afuera se choca con el borde.
	var sur: float = terreno.global_position.z - terreno.size.y * 0.5
	var desde := Vector3(0.0, terreno.height_at(Vector3(0.0, 0.0, sur + 10.0)) + 15.0, sur + 10.0)
	var hasta := desde + Vector3(0.0, 0.0, -30.0)
	var choque: Dictionary = _rayo(desde, hasta)
	_comprobar(not choque.is_empty() and (choque["position"] as Vector3).z <= sur + 0.5, "Al sur de la sierra hay borde: no se cae al vacío")


func _probar_dadores() -> void:
	var dadores: int = 0
	var flotando: Array[String] = []
	for nodo: Node in _todos():
		var dador := nodo as MissionGiver
		if dador == null:
			continue
		dadores += 1
		var antes: float = dador.global_position.y
		var apoyado: bool = dador.snap_now()
		if not apoyado or absf(dador.global_position.y - antes) > 0.05:
			flotando.append("%s (%.2f)" % [dador.name, dador.global_position.y - antes])
	_comprobar(dadores >= 5 and flotando.is_empty(), "Los %d que dan misiones están apoyados en el suelo (flotaban: %s)" % [dadores, flotando])


func _probar_colores() -> void:
	var loco := _locomotora()
	_comprobar(loco != null, "Está la locomotora del jugador")
	if loco == null:
		return
	_comprobar(_color_de(loco, ^"Visual/Caldera") == &"blanco", "La caldera (la máquina a vapor) es blanca")
	_comprobar(_color_de(loco, ^"Visual/Chimenea") == &"amarillo_senal", "La chimenea es amarilla")
	_comprobar(_color_de(loco, ^"Visual/CabinaFrenteCentro") == &"azul_noche" and _color_de(loco, ^"Visual/BarandaDerecha") == &"azul_noche", "El contorno (cabina y barandas) es azul")


func _probar_distancias() -> void:
	var loco := _locomotora()
	var caldera := loco.get_node_or_null(^"Visual/Caldera") as GeometryInstance3D if loco != null else null
	_comprobar(caldera != null and is_equal_approx(caldera.visibility_range_end, Vehicle.VIEW_DISTANCE), "Los vehículos no se dibujan pasando %d m" % int(Vehicle.VIEW_DISTANCE))
	var figura: BigHeadFigure = null
	for nodo: Node in _todos():
		if nodo is BigHeadFigure:
			figura = nodo as BigHeadFigure
			break
	var pieza: GeometryInstance3D = null
	if figura != null:
		for nodo: Node in _todos(figura):
			if nodo is MeshInstance3D:
				pieza = nodo as GeometryInstance3D
				break
	_comprobar(pieza != null and is_equal_approx(pieza.visibility_range_end, BigHeadFigure.VIEW_DISTANCE), "Los personajes no se dibujan pasando %d m" % int(BigHeadFigure.VIEW_DISTANCE))


func _probar_paso_a_nivel() -> void:
	var paso := _mapa.get_node_or_null(^"PasoANivel") as LevelCrossing
	_comprobar(paso != null and paso.get_barrier_count() == 2, "El paso a nivel tiene sus dos barreras")
	if paso == null:
		return
	_comprobar(not paso.check_now(), "Sin tren cerca las barreras están arriba")
	var loco := _locomotora()
	var linea := _mapa.get_node_or_null(^"OlavarriaAzul") as Path3D
	if loco == null or linea == null:
		_comprobar(false, "Están la locomotora y la vía Olavarría-Azul")
		return
	# Se suelta del resto del tren y se pone a 40 m del cruce.
	while loco.rear != null:
		loco.uncouple_rear()
	var en_el_cruce: float = linea.curve.get_closest_offset(linea.to_local(paso.global_position))
	loco.place_on(linea, maxf(en_el_cruce - 40.0, 10.0))
	await get_tree().physics_frame
	_comprobar(paso.check_now(), "Con un tren a 40 m las barreras bajan")
	paso.set_lowered_amount(1.0)
	var acostados: int = 0
	for nodo: Node in paso.find_children("Brazo", "MeshInstance3D", true, false):
		var brazo := nodo as Node3D
		var hacia_el_centro: float = absf(paso.to_local(brazo.global_position).z)
		if paso.to_local(brazo.global_position).y < 1.5 and hacia_el_centro < 1.0:
			acostados += 1
	_comprobar(acostados == 2, "Abajo, los dos brazos quedan acostados cruzando el camino")
	paso.set_lowered_amount(0.0)


func _probar_pausa() -> void:
	var interfaz: InventoryUI = null
	for nodo: Node in _todos():
		if nodo is InventoryUI:
			interfaz = nodo as InventoryUI
	_comprobar(interfaz != null, "El jugador tiene su TAB")
	if interfaz == null:
		return
	GameState.clock_running = true
	var loco := _locomotora()
	if loco != null:
		loco.speed = 5.0
		loco.throttle = 1.0
	interfaz.set_open(true)
	var donde: float = loco.progress if loco != null else 0.0
	var hora: float = GameState.clock.time_of_day
	for _i: int in 10:
		await get_tree().process_frame
	_comprobar(get_tree().paused, "Con el TAB abierto el juego entero está en pausa")
	_comprobar(loco == null or is_equal_approx(loco.progress, donde), "En pausa el tren no se mueve")
	_comprobar(is_equal_approx(GameState.clock.time_of_day, hora), "En pausa el reloj no corre")
	interfaz.show_tab(InventoryUI.Tab.AGENDA)
	_comprobar(interfaz.get_current_tab() == InventoryUI.Tab.AGENDA, "En pausa la ventana sigue andando (cambia de pestaña)")
	interfaz.set_open(false)
	_comprobar(not get_tree().paused, "Al cerrar el TAB el juego sigue")
	if loco != null:
		loco.throttle = 0.0
		loco.speed = 0.0


func _probar_juntar_mallas() -> void:
	var corral := (load(CORRAL) as PackedScene).instantiate() as Node3D
	add_child(corral)
	corral.global_position = Vector3(0.0, -500.0, 0.0)
	var antes: int = corral.find_children("*", "MeshInstance3D", true, false).size()
	var juntadas: int = MeshBatcher.merge(corral, TrackLot.PARCEL_VIEW_DISTANCE)
	await get_tree().process_frame
	var despues: int = corral.find_children("*", "MeshInstance3D", true, false).size()
	_comprobar(antes > 100 and juntadas == antes and despues < 25, "El corral pasa de %d piezas a %d mallas juntas" % [antes, despues])
	corral.queue_free()
	# Los lotes ocupados del mapa juntan las suyas solos después de brotar.
	await get_tree().create_timer(TrackLot.MERGE_WAIT + 0.3).timeout
	var sueltas: int = 0
	var lotes: int = 0
	for nodo: Node in get_tree().get_nodes_in_group(TrackLot.GROUP):
		var lote := nodo as TrackLot
		if lote.get_parcel() == null or not lote.merge_meshes:
			continue
		lotes += 1
		for pieza: Node in lote.get_parcel().find_children("*", "MeshInstance3D", true, false):
			if not String(pieza.name).begins_with(MeshBatcher.MERGED_PREFIX) and pieza.get_child_count() == 0:
				sueltas += 1
	print("Lotes ocupados al empezar: %d (piezas sin juntar: %d)." % [lotes, sueltas])
	_comprobar(sueltas == 0, "Las parcelas que ya estaban quedan con sus mallas juntas")


# Todo lo que cuelga de `raiz` (el mapa si es null), también los hijos internos.
func _todos(raiz: Node = null) -> Array[Node]:
	var nodos: Array[Node] = []
	var pendientes: Array[Node] = [raiz if raiz != null else _mapa]
	while not pendientes.is_empty():
		var nodo: Node = pendientes.pop_back()
		for hijo: Node in nodo.get_children(true):
			nodos.append(hijo)
			pendientes.append(hijo)
	return nodos


func _locomotora() -> Vehicle:
	var loco := _mapa.get_node_or_null(^"OlavarriaSierrasBayas/Locomotive") as Vehicle
	if loco != null:
		return loco
	for nodo: Node in _todos():
		var vehiculo := nodo as Vehicle
		if vehiculo != null and not vehiculo.automatic and vehiculo.scene_file_path.ends_with("locomotive.tscn"):
			return vehiculo
	return null


# El color de la paleta de una pieza (pintada con la paleta o todavía de bosquejo).
func _color_de(raiz: Node, camino: NodePath) -> StringName:
	var pieza := raiz.get_node_or_null(camino) as GeometryInstance3D
	if pieza == null or pieza.material_override == null:
		return &""
	var pintado := pieza.material_override as ShaderMaterial
	if pintado != null:
		return Palette.NAMES[int(pintado.get_shader_parameter(&"swatch"))]
	var liso := pieza.material_override as BaseMaterial3D
	return Palette.NAMES[Palette.nearest(liso.albedo_color)] if liso != null else &""


func _rayo(desde: Vector3, hasta: Vector3) -> Dictionary:
	var consulta := PhysicsRayQueryParameters3D.create(desde, hasta)
	consulta.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(consulta)


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
