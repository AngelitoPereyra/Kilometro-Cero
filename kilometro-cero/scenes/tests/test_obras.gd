extends Node
## Prueba de la tarea 62b.4 (D127, D130): obras. Una secundaria de tipo obra (MissionData.Kind.BUILD,
## "Las primeras casas de Azul") no recibe nada en el tablero: sus materiales se llevan a su
## ConstructionSite (MissionBoard.plan_build y deliver_build). La obra se arma de a partes y al
## terminar las carpas se van y aparecen las casas. Lo del tren prestado no cuenta
## (StationGoods.is_borrowed; los automáticos ya no cuentan nunca).
## Usa un tablero propio con Azul sola (no toca la partida de GameState). Entregar desde el tren, la
## mano y la mochila, con el cartel a la vista, se prueba jugando el Hito A.

const OBRA: String = "res://data/missions/primeras_casas.tres"
const ESCENA: String = "res://scenes/stations/construction_site.tscn"

var _fallos: int = 0
var _modelo: ProductionModel
var _tablero: MissionBoard
var _datos: MissionData
var _cumplidas: Array[StringName] = []


func _ready() -> void:
	_probar_datos()
	_probar_partes()
	_armar()
	_probar_obra_en_el_tablero()
	_probar_guardado()
	_probar_tren_prestado()
	await _probar_escena()
	if _fallos == 0:
		print("Obras: todas las comprobaciones pasaron.")
	else:
		push_error("Obras: fallaron %d comprobaciones." % _fallos)


func _probar_datos() -> void:
	_datos = load(OBRA) as MissionData
	_comprobar(_datos != null, "Carga primeras_casas.tres")
	if _datos == null:
		return
	_comprobar(_datos.kind == MissionData.Kind.BUILD and MissionData.kind_name(_datos.kind) == "obra", "Es una obra")
	_comprobar(_datos.validate().is_empty(), "Sus datos están bien (%s)" % [_datos.validate()])
	_comprobar(_datos.station_id == &"azul" and _datos.min_level == 2, "Es de Azul, desde el nivel 2")
	_comprobar(ItemAmount.sum_by_id(_datos.delivery) == ({&"log": 20} as Dictionary[StringName, int]), "Pide 20 troncos")
	var vacia := MissionData.new()
	vacia.id = &"obra_vacia"
	vacia.title = "Obra vacía"
	vacia.station_id = &"azul"
	vacia.kind = MissionData.Kind.BUILD
	_comprobar(vacia.validate().size() == 1 and vacia.validate()[0].contains("no pide materiales"), "Una obra sin materiales avisa")


# Cuántas partes se ven según lo entregado (lógica pura).
func _probar_partes() -> void:
	_comprobar(ConstructionSite.parts_for(0.0, 5) == 0, "Sin materiales no se ve ninguna parte")
	_comprobar(ConstructionSite.parts_for(0.2, 5) == 1, "Con 4 de 20 troncos, una parte de 5")
	_comprobar(ConstructionSite.parts_for(0.4, 5) == 2, "Con 8 de 20, dos partes")
	_comprobar(ConstructionSite.parts_for(0.99, 5) == 4, "Casi todo: cuatro partes (la última llega con lo último)")
	_comprobar(ConstructionSite.parts_for(1.0, 5) == 5 and ConstructionSite.parts_for(1.5, 5) == 5, "Completa: todas")
	_comprobar(ConstructionSite.parts_for(0.5, 0) == 0, "Sin partes, ninguna")


func _armar() -> void:
	_modelo = ProductionModel.new()
	for oficio: OccupationData in OccupationData.load_all():
		_modelo.add_occupation(oficio)
	_tablero = MissionBoard.new(_modelo)
	_tablero.mission_completed.connect(func(mission: Mission) -> void: _cumplidas.append(mission.id))
	_modelo.add_station(load("res://data/stations/azul.tres") as StationData, 1)
	_tablero.refresh()


func _probar_obra_en_el_tablero() -> void:
	if _datos == null:
		return
	var obra: Mission = _tablero.register_side(_datos)
	_comprobar(obra != null and obra.state == Mission.State.LOCKED, "Con Azul en el nivel 1 la obra está bloqueada")
	_comprobar(_tablero.is_build(obra) and obra.required == ({&"log": 20} as Dictionary[StringName, int]), "La misión es una obra de 20 troncos")
	_modelo.set_level(&"azul", 2)
	_comprobar(obra.state == Mission.State.AVAILABLE, "Azul en el nivel 2: la obra está disponible")
	_comprobar(_tablero.plan_build(obra.id, {&"log": 20} as Dictionary[StringName, int]).is_empty() and _tablero.deliver_build(obra.id, &"log", 5) == 0, "Disponible (sin aceptar) no recibe troncos")
	_comprobar(_tablero.start(obra.id) and obra.is_active(), "Se acepta")
	# El tablero de la estación no la ve como entrega.
	_comprobar(not _tablero.accepts_deliveries(obra), "El tablero no acepta entregas para la obra")
	_comprobar(not _tablero.plan_delivery(&"azul", {&"log": 20} as Dictionary[StringName, int]).has(&"log") and _tablero.deliver(&"azul", &"log", 20) == 0, "Los troncos no se entregan en el tablero de Azul")
	_comprobar(_tablero.plan_build(obra.id, {&"log": 30, &"limestone": 5} as Dictionary[StringName, int]) == ({&"log": 20} as Dictionary[StringName, int]), "La obra toma solo lo que le falta (20 de 30 troncos, nada de piedra)")
	_comprobar(_tablero.plan_build(obra.id, {&"log": 5} as Dictionary[StringName, int]) == ({&"log": 5} as Dictionary[StringName, int]), "Con 5 troncos al alcance entrega 5")
	_comprobar(_tablero.deliver_build(obra.id, &"log", 8) == 8 and is_equal_approx(_tablero.get_build_progress(obra), 0.4), "Se entregan 8: va el 40 %")
	var pasos: PackedStringArray = _tablero.get_pending_steps(obra)
	_comprobar(pasos.size() == 1 and pasos[0].begins_with("Llevar 12 tronco a la obra"), "Paso: llevar 12 troncos a la obra (%s)" % [pasos])
	_comprobar(obra.is_active() and _cumplidas.is_empty(), "A medio hacer sigue en curso")
	_comprobar(_tablero.deliver_build(obra.id, &"log", 20) == 12, "Se aceptan solo los 12 que faltaban")
	_comprobar(obra.is_completed() and _cumplidas == ([&"primeras_casas"] as Array[StringName]), "Con los 20 troncos la obra se cumple")
	_comprobar(is_equal_approx(_tablero.get_build_progress(obra), 1.0) and _tablero.deliver_build(obra.id, &"log", 1) == 0, "Cumplida: 100 % y no recibe más")


func _probar_guardado() -> void:
	if _datos == null:
		return
	var otro := MissionBoard.new(ProductionModel.new())
	otro.load_dict(_tablero.to_dict())
	var obra: Mission = otro.register_side(_datos)
	_comprobar(obra != null and obra.is_completed() and obra.delivered.get(&"log", 0) == 20, "Guardada: vuelve cumplida con sus 20 troncos")


# Lo del tren prestado no cuenta para las obras (D127).
func _probar_tren_prestado() -> void:
	var propio := Node.new()
	var prestado := Node.new()
	prestado.set_meta(BorrowedTrains.META, true)
	_comprobar(not StationGoods.is_borrowed(propio) and StationGoods.is_borrowed(prestado) and not StationGoods.is_borrowed(null), "El vagón del tren prestado se reconoce (no cuenta para la obra)")
	var bienes := StationGoods.new(null)
	_comprobar(not bienes.own_trains_only, "El tablero y el mercado siguen contando todos los trenes del jugador")
	propio.free()
	prestado.free()


# La escena de la obra: de a partes, y al terminar las carpas se van y aparecen las casas.
func _probar_escena() -> void:
	if _datos == null:
		return
	var modelo := ProductionModel.new()
	for oficio: OccupationData in OccupationData.load_all():
		modelo.add_occupation(oficio)
	var tablero := MissionBoard.new(modelo)
	modelo.add_station(load("res://data/stations/azul.tres") as StationData, 2)
	var obra := (load(ESCENA) as PackedScene).instantiate() as ConstructionSite
	obra.board = tablero
	obra.mission = _datos
	add_child(obra)
	await get_tree().process_frame
	var mision: Mission = tablero.get_mission(_datos.id)
	_comprobar(mision != null and mision.state == Mission.State.AVAILABLE, "La obra registra su misión (disponible en el nivel 2)")
	var partes: Array[Node3D] = obra.get_parts()
	_comprobar(partes.size() == 5, "La escena tiene 5 partes (cimientos, dos paredes, dos techos)")
	_comprobar(_visibles(partes) == 0 and _hijo(obra, "Antes").visible and not _hijo(obra, "Andamios").visible and not _hijo(obra, "Despues").visible, "Disponible: carpas, sin andamios ni partes")
	_comprobar(obra.get_prompt() == "Aceptar la obra: " + _datos.title and obra.can_interact(null), "F acepta la obra")
	_comprobar(obra.build_text().begins_with("Obra: " + _datos.title), "El cartel dice qué obra es")
	_comprobar(obra.accept() and mision.is_active(), "Aceptada desde el cartel")
	_comprobar(_hijo(obra, "Andamios").visible and obra.build_text().contains("Faltan 20 tronco"), "En curso: andamios y el cartel dice lo que falta")
	_comprobar(obra.get_delivery_plan().is_empty() and obra.deliver().is_empty(), "Sin nada al alcance no entrega")
	var partes_vistas: Array[int] = []
	obra.part_built.connect(func(count: int) -> void: partes_vistas.append(count))
	tablero.deliver_build(_datos.id, &"log", 8)
	obra.refresh()
	_comprobar(obra.get_built_count() == 2 and _visibles(partes) == 2 and partes[0].visible and partes[1].visible, "Con 8 troncos se ven 2 partes (las primeras)")
	_comprobar(partes_vistas == ([2] as Array[int]), "Avisa la parte nueva")
	var terminada: Array[bool] = [false]
	obra.finished.connect(func() -> void: terminada[0] = true)
	tablero.deliver_build(_datos.id, &"log", 12)
	obra.refresh()
	_comprobar(mision.is_completed() and obra.is_finished() and terminada[0], "Con todo, la obra termina y lo avisa")
	_comprobar(_visibles(partes) == 5 and not _hijo(obra, "Antes").visible and not _hijo(obra, "Andamios").visible and _hijo(obra, "Despues").visible, "Terminada: casas completas, sin carpas ni andamios")
	_comprobar(not obra.can_interact(null), "Terminada ya no se usa con F")
	# Al cargar con la obra cumplida aparece quieta y terminada.
	var cargada := (load(ESCENA) as PackedScene).instantiate() as ConstructionSite
	cargada.board = tablero
	cargada.mission = _datos
	add_child(cargada)
	await get_tree().process_frame
	_comprobar(cargada.is_finished() and _visibles(cargada.get_parts()) == 5 and not _hijo(cargada, "Antes").visible and _hijo(cargada, "Despues").visible, "Al cargar con la obra cumplida aparece terminada")
	_comprobar(cargada.build_text() == "", "Sin aviso, el cartel de una obra terminada queda vacío")
	await get_tree().create_timer(1.0).timeout
	obra.queue_free()
	cargada.queue_free()


func _visibles(piezas: Array[Node3D]) -> int:
	var cuenta: int = 0
	for pieza: Node3D in piezas:
		if pieza.visible:
			cuenta += 1
	return cuenta


func _hijo(nodo: Node, nombre: String) -> Node3D:
	return nodo.get_node(nombre) as Node3D


func _comprobar(ok: bool, texto: String) -> void:
	if ok:
		print("OK  ", texto)
	else:
		_fallos += 1
		push_error("FALLA  " + texto)
