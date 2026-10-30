extends Node3D
## Prueba de la tarea 62c.3a: el trazado nuevo del Hito A. o_a mide unos 2,5 km y pasa por una
## loma antes de Azul; o_s es el ramal de unos 2 km a Sierras Bayas, que sube entre lomas hacia la
## sierra (D139: Sierras Bayas es anexo de Olavarría). Azul y Sierras Bayas se corrieron con todo lo
## suyo (pobladores, lotes, regalo, monte y cantera) y el terreno cubre todo, con la sierra detrás
## de la cantera vieja. Desde el arreglo de Sierras Bayas como anexo (62c.3d, idea de Batmi) la
## Línea del Sud sigue al sur de Olavarría (o_s hasta el empalme norte, e_ns hasta el empalme sur y
## e_sur, cortada, hasta perderse en la sierra) y Sierras Bayas sale en Y de los dos: los ramales
## e_nr y e_sr se juntan en el empalme del ramal y de ahí e_s llega a la estación, que está al
## costado, con la bahía del jugador en sus propias vías y el desvío a la cantera vieja desde su
## punta sur. Toca la partida de GameState (la vacía al empezar).

const HITO_A: String = "res://scenes/hito_a/hito_a.tscn"
## Cada cuánto se mira la vía.
const PASO: float = 8.0
const TOLERANCIA_ALTURA: float = 0.35
const PENDIENTE_MAXIMA: float = 0.04
const CERCA_DE_SU_ESTACION: float = 80.0
const TRAMOS: Array[StringName] = [&"o_a", &"o_s", &"s_c", &"e_ns", &"e_sur", &"e_nr", &"e_sr", &"e_s"]

var _fallos: int = 0
var _mapa: Node3D


func _ready() -> void:
	GameState.reset_production()
	_mapa = (load(HITO_A) as PackedScene).instantiate() as Node3D
	add_child(_mapa)
	for _i: int in 6:
		await get_tree().process_frame
	_probar_largos()
	_probar_estaciones()
	_probar_terreno()
	_probar_lotes()
	_probar_lo_corrido()
	_probar_anexo()
	_mapa.queue_free()
	if _fallos == 0:
		print("Trazado: todas las comprobaciones pasaron.")
	else:
		push_error("Trazado: fallaron %d comprobaciones." % _fallos)


func _probar_largos() -> void:
	var o_a: Path3D = _via(&"o_a")
	var o_s: Path3D = _via(&"o_s")
	_comprobar(o_a != null and o_s != null and _via(&"s_c") != null and _via(&"e_s") != null and _via(&"e_sur") != null, "Están o_a, o_s, s_c, e_s y e_sur")
	if o_a == null or o_s == null:
		return
	var largo_a: float = o_a.curve.get_baked_length()
	var largo_s: float = o_s.curve.get_baked_length()
	_comprobar(largo_a > 2300.0 and largo_a < 2600.0, "o_a mide unos 2,5 km (%d m)" % largo_a)
	_comprobar(largo_s > 1400.0 and largo_s < 1700.0, "o_s mide unos 1,5 km hasta el empalme norte (%d m)" % largo_s)
	_comprobar(_mas_alto(o_a) > 4.0, "o_a pasa por la loma antes de Azul (%.1f m)" % _mas_alto(o_a))
	_comprobar(_mas_alto(o_s) > 6.0, "o_s sube entre las lomas (%.1f m)" % _mas_alto(o_s))
	for via: Path3D in [o_a, o_s, _via(&"e_ns"), _via(&"e_sur"), _via(&"e_nr"), _via(&"e_sr"), _via(&"e_s")]:
		if via == null:
			continue
		var pendiente: float = _pendiente_maxima(via)
		_comprobar(pendiente < PENDIENTE_MAXIMA, "%s no pasa del %d %% (%.1f %%)" % [via.name, roundi(PENDIENTE_MAXIMA * 100.0), pendiente * 100.0])


func _probar_estaciones() -> void:
	var olavarria := Station.find(get_tree(), &"olavarria")
	var azul := Station.find(get_tree(), &"azul")
	var sierras := Station.find(get_tree(), &"sierras_bayas")
	_comprobar(olavarria != null and azul != null and sierras != null, "Están las tres estaciones")
	if olavarria == null or azul == null or sierras == null:
		return
	_comprobar(absf(azul.global_position.z - olavarria.global_position.z) > 2400.0, "Azul queda a más de 2,4 km de Olavarría")
	_comprobar(absf(sierras.global_position.z - olavarria.global_position.z) > 1700.0, "Sierras Bayas queda a unos 1,8 km de Olavarría")
	_comprobar(_punta_cerca(_via(&"o_a"), olavarria, azul), "o_a va de la punta norte de Olavarría a Azul")
	var o_s: Path3D = _via(&"o_s")
	var e_s: Path3D = _via(&"e_s")
	_comprobar(o_s != null and o_s.to_global(o_s.curve.sample_baked(0.0)).distance_to(olavarria.global_position) < 150.0, "o_s sale de la punta sur de Olavarría")
	_comprobar(e_s != null and e_s.to_global(e_s.curve.sample_baked(e_s.curve.get_baked_length())).distance_to(sierras.global_position) < 150.0, "e_s llega a Sierras Bayas")
	var red: RailNetwork = RailNetwork.find_in(get_tree())
	if red != null:
		var camino: Array[StringName] = red.find_route(&"olavarria", &"sierras_bayas", true)
		_comprobar(camino == ([&"o_s", &"e_nr", &"e_s"] as Array[StringName]), "De Olavarría a Sierras Bayas: o_s, e_nr y e_s, por el lado norte del triángulo (%s)" % str(camino))
		var largo: float = red.get_route_length(camino)
		_comprobar(largo > 1700.0 and largo < 2100.0, "Sierras Bayas queda a unos 1,8 km por vía (%d m)" % largo)


func _probar_terreno() -> void:
	var terreno := get_tree().get_first_node_in_group(Terrain.GROUP) as Terrain
	_comprobar(terreno != null, "Hay terreno")
	if terreno == null:
		return
	for segmento: StringName in TRAMOS:
		var via: Path3D = _via(segmento)
		if via == null:
			continue
		var peor: float = 0.0
		var afuera: int = 0
		var largo: float = via.curve.get_baked_length()
		for k: int in ceili(largo / PASO) + 1:
			var punto: Vector3 = via.to_global(via.curve.sample_baked(minf(k * PASO, largo)))
			var suelo: float = terreno.height_at(punto)
			if is_nan(suelo):
				afuera += 1
				continue
			# Sobre el arroyo la vía va por el puente (62c.3c).
			if terreno.is_carved(punto):
				continue
			peor = maxf(peor, absf(suelo - punto.y))
		_comprobar(afuera == 0, "El terreno cubre toda %s (%d puntos afuera)" % [segmento, afuera])
		_comprobar(peor < TOLERANCIA_ALTURA, "El suelo acompaña a %s (peor %.2f m)" % [segmento, peor])
	var sierras := Station.find(get_tree(), &"sierras_bayas")
	var frente := _mapa.get_node_or_null(^"Cantera/FrenteViejo1") as Node3D
	if frente != null:
		var sierra: float = terreno.height_at(frente.global_position + Vector3(0.0, 0.0, -120.0))
		_comprobar(sierra > 30.0, "Detrás de la cantera vieja está la sierra (%.0f m)" % sierra)
	if sierras != null:
		var anden: float = terreno.height_at(sierras.global_position + Vector3(-12.0, 0.0, 0.0))
		_comprobar(absf(anden - sierras.global_position.y) < TOLERANCIA_ALTURA, "Sierras Bayas sigue en plano")
	var azul := Station.find(get_tree(), &"azul")
	if azul != null:
		var atras: float = terreno.height_at(azul.global_position + Vector3(0.0, 0.0, 380.0))
		_comprobar(not is_nan(atras), "El terreno llega a los lotes de atrás de Azul")


func _probar_lotes() -> void:
	var vias: Array[Path3D] = []
	for segmento: StringName in TRAMOS:
		if _via(segmento) != null:
			vias.append(_via(segmento))
	var pisados: PackedStringArray = []
	var lejos: PackedStringArray = []
	var lotes: int = 0
	for nodo: Node in _mapa.find_children("*", "", true, false):
		var lote := nodo as TrackLot
		if lote == null:
			continue
		lotes += 1
		var estacion := Station.find(get_tree(), lote.station_id)
		if estacion != null and lote.global_position.distance_to(estacion.global_position) > 600.0:
			lejos.append(lote.name)
		var medio: Vector2 = lote.get_size() * 0.5
		var al_lote: Transform3D = lote.global_transform.affine_inverse()
		for via: Path3D in vias:
			var largo: float = via.curve.get_baked_length()
			for k: int in ceili(largo / 4.0) + 1:
				var adentro: Vector3 = al_lote * via.to_global(via.curve.sample_baked(minf(k * 4.0, largo)))
				if Terrain.rect_distance(Vector2(adentro.x, adentro.z), medio) <= 0.0:
					pisados.append(lote.name)
					break
	_comprobar(lotes == 36, "Están los 36 lotes (%d)" % lotes)
	_comprobar(pisados.is_empty(), "Ninguna vía pisa un lote (%s)" % ", ".join(pisados))
	_comprobar(lejos.is_empty(), "Cada lote sigue cerca de su estación (%s)" % ", ".join(lejos))


func _probar_lo_corrido() -> void:
	var azul := Station.find(get_tree(), &"azul")
	var sierras := Station.find(get_tree(), &"sierras_bayas")
	if azul == null or sierras == null:
		return
	for camino: NodePath in [^"Vecina", ^"DonaClara", ^"LlegadaEtchegaray", ^"RegaloAzul", ^"Pico", ^"Bosquecito/Arbol1", ^"Bosquecito/Panal1"]:
		_comprobar(_cerca(camino, azul), "%s sigue en Azul" % camino)
	for camino: NodePath in [^"Ramirez", ^"Cantero", ^"Cantera/Afloramiento1"]:
		_comprobar(_cerca(camino, sierras), "%s sigue en Sierras Bayas" % camino)
	var s_c: Path3D = _via(&"s_c")
	for camino: NodePath in [^"PiedrasDesvio1", ^"PiedrasDesvio2", ^"Cantera/FrenteViejo1"]:
		var nodo := _mapa.get_node_or_null(camino) as Node3D
		var distancia: float = INF
		if nodo != null and s_c != null:
			distancia = s_c.to_global(s_c.curve.get_closest_point(s_c.to_local(nodo.global_position))).distance_to(nodo.global_position)
		_comprobar(distancia < 20.0, "%s sigue junto al desvío de la cantera vieja" % camino)


# 62c.3d (D139, idea de Batmi): la Línea del Sud sigue al sur y Sierras Bayas sale en Y de dos
# empalmes, uno de cada lado, que se juntan en el empalme del ramal.
func _probar_anexo() -> void:
	var olavarria := Station.find(get_tree(), &"olavarria")
	var sierras := Station.find(get_tree(), &"sierras_bayas")
	var red: RailNetwork = RailNetwork.find_in(get_tree())
	var norte := _mapa.get_node_or_null(^"EmpalmeNorte") as Path3D
	var sur := _mapa.get_node_or_null(^"EmpalmeSur") as Path3D
	var vertice := _mapa.get_node_or_null(^"EmpalmeRamal") as Path3D
	var tramos: Dictionary = {}
	for segmento: StringName in TRAMOS:
		tramos[segmento] = _via(segmento)
	if olavarria == null or sierras == null or red == null or norte == null or sur == null or vertice == null or tramos.values().has(null):
		_comprobar(false, "Están las estaciones, la red, los tres empalmes y sus tramos")
		return
	_comprobar(absf(sierras.global_position.x - olavarria.global_position.x) > 80.0, "Sierras Bayas queda al costado, fuera del eje de la línea (%.0f m)" % (sierras.global_position.x - olavarria.global_position.x))
	_comprobar(sierras.get_node_or_null(^"Ramal") == null and sierras.get_node_or_null(^"Bahia2") == null, "Ya no están el ramal y las bahías puestos a mano")
	for par: Array in [[norte, &"empalme_norte"], [sur, &"empalme_sur"], [vertice, &"empalme_ramal"]]:
		var via := RailNetwork.track_of(par[0]) as StationTrack
		_comprobar(via != null and via.is_main() and via.get_station_id() == par[1] and red.is_junction(par[1]), "%s es un empalme: una vía principal suelta, sin estación" % par[1])
	_comprobar(not red.is_junction(&"sierras_bayas") and not red.is_junction(&"olavarria"), "Las estaciones no son empalmes")
	_comprobar(red.is_cut(&"e_sur") and not red.is_cut(&"e_ns") and not red.is_cut(&"e_nr") and not red.is_cut(&"e_sr") and not red.is_cut(&"e_s"), "La Línea del Sud sigue cortada al sur; el triángulo y el ramal están abiertos")
	var e_sur: Path3D = tramos[&"e_sur"]
	var fin_sur: Vector3 = e_sur.to_global(e_sur.curve.sample_baked(e_sur.curve.get_baked_length()))
	_comprobar(fin_sur.z < sierras.global_position.z - 200.0, "La línea se pierde al sur, más allá de Sierras Bayas")
	# Los tres cambios del triángulo: en cada empalme de la línea sigue derecho la principal.
	var cambio_norte: TrackSwitch = red.find_switch(norte, true)
	var cambio_sur: TrackSwitch = red.find_switch(sur, false)
	var cambio_ramal: TrackSwitch = red.find_switch(vertice, false)
	_comprobar(cambio_norte != null and cambio_norte.is_junction() and cambio_norte.get_option_path(cambio_norte.main_option) == tramos[&"e_ns"] and cambio_norte.option_index(tramos[&"e_nr"]) >= 0, "Empalme norte: la principal sigue derecho y el ramal sale al costado")
	_comprobar(cambio_sur != null and cambio_sur.is_junction() and cambio_sur.get_option_path(cambio_sur.main_option) == tramos[&"e_ns"] and cambio_sur.option_index(tramos[&"e_sr"]) >= 0, "Empalme sur: la principal sigue derecho y el ramal sale al costado")
	_comprobar(cambio_ramal != null and cambio_ramal.option_index(tramos[&"e_nr"]) >= 0 and cambio_ramal.option_index(tramos[&"e_sr"]) >= 0, "En el empalme del ramal se juntan los dos lados")
	_comprobar(cambio_norte != null and cambio_norte.state == cambio_norte.main_option and cambio_sur != null and cambio_sur.state == cambio_sur.main_option, "Los cambios de la línea arrancan para la principal")
	_comprobar(cambio_norte != null and cambio_norte.option_label(cambio_norte.option_index(tramos[&"e_nr"])) == "línea a Empalme del ramal", "La palanca dice adónde va cada salida")
	var vias := sierras.get_node_or_null(^"Vias") as StationTracks
	_comprobar(vias != null, "Sierras Bayas arma sus vías")
	if vias == null:
		return
	var puntas: Array[Vector3] = vias.get_ends()
	var e_s: Path3D = tramos[&"e_s"]
	var fin_ramal: Vector3 = e_s.to_global(e_s.curve.sample_baked(e_s.curve.get_baked_length()))
	_comprobar(fin_ramal.distance_to(puntas[1]) < RailNetwork.JOIN_DISTANCE, "El ramal llega a la punta norte de Sierras Bayas")
	var s_c: Path3D = tramos[&"s_c"]
	var principio: Vector3 = s_c.to_global(s_c.curve.sample_baked(0.0))
	_comprobar(principio.distance_to(puntas[0]) < RailNetwork.JOIN_DISTANCE, "El desvío a la cantera vieja sale de la punta sur")
	var bahia: StationTrack = null
	for via: StationTrack in vias.get_tracks():
		if via.role == StationTrack.Role.BAY:
			bahia = via
	_comprobar(bahia != null and red.has_links(bahia.get_track_path(), false) and red.has_links(bahia.get_track_path(), true), "La bahía de carga del jugador sale de las vías de la estación")
	var punto := sierras.get_node_or_null(^"PuntoDeCarga") as Node3D
	if bahia != null and punto != null:
		var camino: Path3D = bahia.get_track_path()
		var cerca: Vector3 = camino.to_global(camino.curve.get_closest_point(camino.to_local(punto.global_position)))
		_comprobar(cerca.distance_to(punto.global_position) < 6.0, "El punto de carga está junto a la bahía (%.1f m)" % cerca.distance_to(punto.global_position))
	var autos: AutoTrains = AutoTrains.find_in(get_tree())
	if autos != null:
		_comprobar(autos.get_signal(&"o_s", &"empalme_norte") == null and autos.get_signal(&"e_nr", &"empalme_norte") == null, "En los empalmes no hay carteles de línea amontonados")
	var cartel := _mapa.get_node_or_null(^"CartelEmpalme") as Node3D
	_comprobar(cartel != null and cartel.global_position.distance_to(vertice.global_position + vertice.curve.sample_baked(0.0)) < 60.0, "En el triángulo, el cartel del empalme")


func _via(segment_id: StringName) -> Path3D:
	for nodo: Node in get_tree().get_nodes_in_group(TrackSegment.GROUP):
		var tramo := nodo as TrackSegment
		if tramo != null and tramo.segment_id == segment_id:
			return tramo.get_track_path()
	return null


func _mas_alto(via: Path3D) -> float:
	var alto: float = -INF
	for punto: Vector3 in via.curve.get_baked_points():
		alto = maxf(alto, via.to_global(punto).y)
	return alto


func _pendiente_maxima(via: Path3D) -> float:
	var peor: float = 0.0
	var largo: float = via.curve.get_baked_length()
	var anterior: Vector3 = via.curve.sample_baked(0.0)
	for k: int in range(1, ceili(largo / PASO) + 1):
		var punto: Vector3 = via.curve.sample_baked(minf(k * PASO, largo))
		var plano: float = Vector2(punto.x - anterior.x, punto.z - anterior.z).length()
		if plano > 0.5:
			peor = maxf(peor, absf(punto.y - anterior.y) / plano)
		anterior = punto
	return peor


# Las dos puntas de la vía, una en cada estación.
func _punta_cerca(via: Path3D, desde: Station, hasta: Station) -> bool:
	if via == null:
		return false
	var largo: float = via.curve.get_baked_length()
	var principio: Vector3 = via.to_global(via.curve.sample_baked(0.0))
	var fin: Vector3 = via.to_global(via.curve.sample_baked(largo))
	return principio.distance_to(desde.global_position) < 150.0 and fin.distance_to(hasta.global_position) < 150.0


func _cerca(camino: NodePath, estacion: Station) -> bool:
	var nodo := _mapa.get_node_or_null(camino) as Node3D
	return nodo != null and nodo.global_position.distance_to(estacion.global_position) < CERCA_DE_SU_ESTACION


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
