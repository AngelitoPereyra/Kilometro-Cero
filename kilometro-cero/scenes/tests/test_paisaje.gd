extends Node3D
## Prueba de las tareas 62c.3b y 62c.3c: el paisaje del Hito A. La vegetación repartida (BiomeScatter)
## no pisa vías, caminos, arroyos, estaciones ni lotes y se dibuja por trozos; los postes, alambrados
## y mojones (TrackDecor) quedan al costado de la vía y en el suelo; el arroyo Tapalqué cava el
## terreno debajo del puente; el camino del paso a nivel, el apeadero abandonado (con cosas para
## juntar), el horizonte, la niebla y las zonas de sonido. Toca la partida de GameState.

const HITO_A: String = "res://scenes/hito_a/hito_a.tscn"
## Cada cuántas instancias se mira una (la prueba completa sería lenta).
const MUESTRA: int = 7
const LEJOS_DE_LA_VIA: float = 2.5

var _fallos: int = 0
var _mapa: Node3D
var _vias: Array[Path3D] = []


func _ready() -> void:
	_probar_logica()
	GameState.reset_production()
	var antes: int = Time.get_ticks_msec()
	_mapa = (load(HITO_A) as PackedScene).instantiate() as Node3D
	add_child(_mapa)
	print("El Hito A tardó %d ms en armarse." % (Time.get_ticks_msec() - antes))
	for _i: int in 6:
		await get_tree().process_frame
	for nodo: Node in get_tree().get_nodes_in_group(TrackSegment.GROUP):
		var tramo := nodo as TrackSegment
		if tramo != null and tramo.get_track_path() != null:
			_vias.append(tramo.get_track_path())
	_probar_vegetacion()
	_probar_decoracion()
	_probar_arroyo()
	_probar_lugares()
	_probar_ambiente()
	_mapa.queue_free()
	if _fallos == 0:
		print("Paisaje: todas las comprobaciones pasaron.")
	else:
		push_error("Paisaje: fallaron %d comprobaciones." % _fallos)


func _probar_logica() -> void:
	_comprobar(is_equal_approx(BiomeScatter.spacing_for(1.0), 10.0) and is_equal_approx(BiomeScatter.spacing_for(4.0), 5.0), "Uno por cada 100 m²: cada 10 m; cuatro: cada 5 m")
	_comprobar(BiomeScatter.make_parts(ScatterLayer.Kind.GRASS).size() == 1 and BiomeScatter.make_parts(ScatterLayer.Kind.EUCALYPTUS).size() == 2, "El pasto es una pieza y el eucalipto dos (tronco y copa)")
	_comprobar(TrackDecor.km_at(1000.0, 0.0, 0.02) == 20 and TrackDecor.km_at(250.0, 3.0, 0.02) == 8, "Mojones con kilómetros reales (D135: 20 km por km de maqueta)")
	_comprobar(is_equal_approx(TerrainCarve.carve_weight(2.0, 4.0, 10.0), 0.0) and is_equal_approx(TerrainCarve.carve_weight(20.0, 4.0, 10.0), 1.0), "El arroyo cava todo en el cauce y nada pasada la barranca")
	_comprobar(is_equal_approx(AmbientZone.zone_weight(10.0, 20.0, 30.0), 1.0) and is_equal_approx(AmbientZone.zone_weight(60.0, 20.0, 30.0), 0.0) and AmbientZone.zone_weight(35.0, 20.0, 30.0) > 0.0, "El sonido de una zona se apaga de a poco")
	var ruido := FastNoiseLite.new()
	_comprobar(HorizonRing.hill_at(ruido, Vector2(0.0, -3000.0), 35.0, 110.0, -1800.0) > HorizonRing.hill_at(ruido, Vector2(0.0, 3000.0), 35.0, 110.0, -1800.0), "Del lado de la sierra el horizonte es más alto")


func _probar_vegetacion() -> void:
	var vegetacion: BiomeScatter = BiomeScatter.find_in(get_tree())
	_comprobar(vegetacion != null, "Hay vegetación")
	if vegetacion == null:
		return
	print("Vegetación: %d instancias en %d trozos (pasto %d, eucaliptos %d, monte %d, sauces %d, cardos %d)." % [vegetacion.get_instance_count(), vegetacion.get_chunk_count(), vegetacion.get_instance_count(&"pasto_largo"), vegetacion.get_instance_count(&"eucaliptos"), vegetacion.get_instance_count(&"monte_o_a"), vegetacion.get_instance_count(&"sauces"), vegetacion.get_instance_count(&"cardos")])
	_comprobar(vegetacion.get_instance_count(&"pasto_largo") > 10000, "Pasto largo por todos lados")
	_comprobar(vegetacion.get_instance_count(&"monte_o_a") > 20, "El monte de eucaliptos de o_a")
	_comprobar(vegetacion.get_instance_count(&"sauces") > 5, "Sauces en el arroyo")
	_comprobar(vegetacion.get_instance_count(&"cardos") > 100, "Cardos hacia la sierra")
	_comprobar(vegetacion.get_instance_count() < 200000 and vegetacion.get_chunk_count() < 6000, "No se pasa de instancias ni de trozos")
	for posicion: Vector3 in vegetacion.get_positions(&"cardos"):
		if posicion.z > -300.0:
			_comprobar(false, "Los cardos quedan del lado de la sierra (hay uno en z %.0f)" % posicion.z)
			break
	var pisan_via: int = 0
	var pisan_lote: int = 0
	var pisan_agua: int = 0
	var terreno := get_tree().get_first_node_in_group(Terrain.GROUP) as Terrain
	var arroyo := _mapa.get_node_or_null(^"ArroyoTapalque") as TerrainCarve
	var lotes: Array[TrackLot] = _lotes()
	for capa: StringName in [&"pasto_largo", &"matas", &"eucaliptos", &"monte_o_a", &"arboles", &"sauces", &"cardos", &"piedras"]:
		var posiciones: PackedVector3Array = vegetacion.get_positions(capa)
		for k: int in range(0, posiciones.size(), MUESTRA):
			var posicion: Vector3 = posiciones[k]
			if _distancia_a_las_vias(posicion) < LEJOS_DE_LA_VIA:
				pisan_via += 1
			if _en_algun_lote(posicion, lotes):
				pisan_lote += 1
			if arroyo != null and _distancia_a_curva(arroyo, posicion) < arroyo.half_width:
				pisan_agua += 1
			if terreno != null and absf(terreno.height_at(posicion) - posicion.y) > 0.05:
				_comprobar(false, "%s queda apoyado en el suelo" % capa)
				break
	_comprobar(pisan_via == 0, "Nada crece sobre la vía (%d)" % pisan_via)
	_comprobar(pisan_lote == 0, "Nada crece en los lotes (%d)" % pisan_lote)
	_comprobar(pisan_agua == 0, "Nada crece en el agua (%d)" % pisan_agua)


func _probar_decoracion() -> void:
	var decoraciones: Array[TrackDecor] = []
	for nodo: Node in _mapa.find_children("*", "", true, false):
		if nodo is TrackDecor:
			decoraciones.append(nodo as TrackDecor)
	_comprobar(decoraciones.size() == 4, "o_a, o_s y la Línea del Sud entre los empalmes y al sur tienen postes, alambrados y mojones")
	var terreno := get_tree().get_first_node_in_group(Terrain.GROUP) as Terrain
	var lotes: Array[TrackLot] = _lotes()
	for decoracion: TrackDecor in decoraciones:
		var via := decoracion.get_parent() as Path3D
		var largo: float = via.curve.get_baked_length()
		var postes: PackedVector3Array = decoracion.get_pole_positions()
		_comprobar(postes.size() > largo / decoracion.pole_spacing * 0.5, "%s: postes de telégrafo a lo largo (%d)" % [via.name, postes.size()])
		_comprobar(decoracion.get_post_positions().size() > largo / decoracion.post_spacing, "%s: alambrado a los dos lados (%d postes)" % [via.name, decoracion.get_post_positions().size()])
		_comprobar(decoracion.get_milestones().size() >= floori(largo / decoracion.milestone_spacing) - 3, "%s: mojones (%d)" % [via.name, decoracion.get_milestones().size()])
		var mal: int = 0
		for punto: Vector3 in postes + decoracion.get_post_positions():
			if _distancia_a_las_vias(punto) < 4.0 or _en_algun_lote(punto, lotes):
				mal += 1
			elif terreno != null and absf(terreno.height_at(punto) - punto.y) > 0.05:
				mal += 1
		_comprobar(mal == 0, "%s: ningún poste en la vía, en un lote ni en el aire (%d)" % [via.name, mal])
	var camino := _mapa.get_node_or_null(^"CaminoDelPaso") as DirtRoad
	if camino != null and not decoraciones.is_empty():
		var en_el_camino: int = 0
		for decoracion: TrackDecor in decoraciones:
			for punto: Vector3 in decoracion.get_post_positions():
				if camino.is_on_road(punto, 1.0):
					en_el_camino += 1
		_comprobar(en_el_camino == 0, "El alambrado deja pasar el camino del paso a nivel")


func _probar_arroyo() -> void:
	var terreno := get_tree().get_first_node_in_group(Terrain.GROUP) as Terrain
	var puente := _mapa.get_node_or_null(^"PuenteTapalque") as Node3D
	var arroyo := _mapa.get_node_or_null(^"ArroyoTapalque") as TerrainCarve
	_comprobar(terreno != null and puente != null and arroyo != null, "Están el arroyo Tapalqué y su puente")
	if terreno == null or puente == null or arroyo == null:
		return
	var debajo: float = terreno.height_at(puente.global_position)
	_comprobar(debajo < puente.global_position.y - arroyo.depth * 0.8, "Debajo del puente el terreno baja al cauce (%.1f m)" % debajo)
	_comprobar(terreno.is_carved(puente.global_position) and not terreno.is_carved(puente.global_position + Vector3(0.0, 0.0, 60.0)), "is_carved dice dónde está el arroyo")
	_comprobar(_distancia_a_las_vias(puente.global_position) < 1.0, "El puente está sobre la vía")
	_comprobar(arroyo.get_node_or_null(^"Agua") is MeshInstance3D, "El arroyo tiene agua")


func _probar_lugares() -> void:
	var camino := _mapa.get_node_or_null(^"CaminoDelPaso") as DirtRoad
	var paso := _mapa.get_node_or_null(^"PasoANivel") as Node3D
	_comprobar(camino != null and paso != null and camino.get_node_or_null(^"Cinta") is MeshInstance3D, "Está el camino de tierra con su paso a nivel")
	if camino != null and paso != null:
		_comprobar(camino.is_on_road(paso.global_position) and _distancia_a_las_vias(paso.global_position) < 1.0, "El camino cruza la vía en el paso a nivel")
	var apeadero := _mapa.get_node_or_null(^"ApeaderoAbandonado") as Node3D
	_comprobar(apeadero != null and _distancia_a_las_vias(apeadero.global_position) < 1.0, "El apeadero abandonado está junto a o_s")
	if apeadero != null:
		var cosas: int = 0
		for hijo: Node in apeadero.get_children():
			if hijo is WorldItem:
				cosas += 1
		_comprobar(cosas == 4, "En el apeadero hay cosas para juntar (%d)" % cosas)
	var horizonte := _mapa.get_node_or_null(^"Horizonte") as MeshInstance3D
	_comprobar(horizonte != null and horizonte.mesh != null and horizonte.mesh.get_aabb().size.z > 5000.0, "El horizonte rodea toda la maqueta")


func _probar_ambiente() -> void:
	var ambiente := _mapa.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	_comprobar(ambiente != null and ambiente.environment.fog_enabled, "Hay niebla suave")
	var zonas: int = 0
	for nodo: Node in _mapa.find_children("*", "", true, false):
		if nodo is AmbientZone:
			zonas += 1
	_comprobar(zonas >= 4, "Zonas de sonido: viento, pájaros y agua (%d)" % zonas)
	var agua := _mapa.get_node_or_null(^"Sonidos/AguaTapalque") as AmbientZone
	var puente := _mapa.get_node_or_null(^"PuenteTapalque") as Node3D
	if agua != null and puente != null:
		_comprobar(agua.distance_to_point(puente.global_position) < 5.0, "El agua se oye desde el puente")


func _lotes() -> Array[TrackLot]:
	var lotes: Array[TrackLot] = []
	for nodo: Node in _mapa.find_children("*", "", true, false):
		if nodo is TrackLot:
			lotes.append(nodo as TrackLot)
	return lotes


func _en_algun_lote(punto: Vector3, lotes: Array[TrackLot]) -> bool:
	for lote: TrackLot in lotes:
		var adentro: Vector3 = lote.global_transform.affine_inverse() * punto
		if Terrain.rect_distance(Vector2(adentro.x, adentro.z), lote.get_size() * 0.5) <= 0.0:
			return true
	return false


func _distancia_a_las_vias(punto: Vector3) -> float:
	var mejor: float = INF
	for via: Path3D in _vias:
		mejor = minf(mejor, _distancia_a_curva(via, punto))
	return mejor


func _distancia_a_curva(camino: Path3D, punto: Vector3) -> float:
	var cerca: Vector3 = camino.to_global(camino.curve.get_closest_point(camino.to_local(punto)))
	return Vector2(cerca.x - punto.x, cerca.z - punto.z).length()


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
