extends Node3D
## Prueba de la tarea 62c.3e (estética base, D140 y D141): la paleta compartida, el repintado de los
## bosquejos, el entorno (AgX, SSAO, glow, niebla y cielo de degradado), la luz y los colores por
## hora, el viento, la vitalidad por zona, el tema de interfaz de cartel ferroviario y los personajes
## cabezones. Después deja el Hito A con una cámara fija en la llegada a Olavarría para comparar los cuatro horarios con el boceto
## (https://claude.ai/artifact/QaUUHvi9gwtTxYVsZ28PNK), y otra en Azul para ver la vitalidad.
## Teclas: 1 mañana, 2 mediodía, 3 atardecer, 4 noche, Espacio pasa solo de uno a otro;
## Z cámara de Olavarría o de Azul; V vitalidad de Azul (según su nivel, 0 o 1); C de cerca, el
## jugador con cuatro pobladores (uno con cada sombrero).
## Toca la partida de GameState.

const HITO_A: String = "res://scenes/hito_a/hito_a.tscn"
const DIA: String = "res://data/look/dia_pampa.tres"
const HORAS: Array[float] = [8.0, 12.5, 19.0, 23.0]
const NOMBRES: Array[String] = ["Mañana", "Mediodía", "Atardecer", "Noche"]
## Segundos de cada horario en el paso automático.
const PASO_AUTOMATICO: float = 5.0

## Dónde está la cámara fija y adónde mira (llegando a Olavarría desde Azul).
@export var camera_position: Vector3 = Vector3(16.0, 6.0, 300.0)
@export var camera_target: Vector3 = Vector3(-4.0, 3.0, 40.0)
## La cámara de Azul, relativa a la estación.
@export var azul_camera_offset: Vector3 = Vector3(45.0, 14.0, -150.0)
@export var azul_target_offset: Vector3 = Vector3(-10.0, 2.0, 10.0)

var _fallos: int = 0
var _mapa: Node3D
var _estetica: LookDirector
var _cartel: Label
var _horario: int = 1
var _automatico: bool = false
var _espera: float = 0.0
var _camara: Camera3D
var _en_azul: bool = false
var _de_cerca: bool = false
# Vitalidad de Azul: -1 según su nivel, 0 o 1.
var _vida_azul: float = -1.0


func _ready() -> void:
	_probar_paleta()
	_probar_pintor()
	_probar_dia()
	_probar_sol()
	_probar_vitalidad()
	_probar_tema()
	_probar_figura()
	GameState.reset_production()
	GameState.clock_running = false
	_mapa = (load(HITO_A) as PackedScene).instantiate() as Node3D
	add_child(_mapa)
	for _i: int in 8:
		await get_tree().process_frame
	_probar_escena()
	if _fallos == 0:
		print("Estética: todas las comprobaciones pasaron.")
	else:
		push_error("Estética: fallaron %d comprobaciones." % _fallos)
	_armar_vista()


func _process(delta: float) -> void:
	if not _automatico or _estetica == null:
		return
	_espera += delta
	if _espera >= PASO_AUTOMATICO:
		_espera = 0.0
		_mostrar_horario((_horario + 1) % HORAS.size())


func _unhandled_input(event: InputEvent) -> void:
	var tecla := event as InputEventKey
	if tecla == null or not tecla.pressed or tecla.echo or _estetica == null:
		return
	match tecla.physical_keycode:
		KEY_1, KEY_2, KEY_3, KEY_4:
			_automatico = false
			_mostrar_horario(tecla.physical_keycode - KEY_1)
		KEY_SPACE:
			_automatico = not _automatico
			_espera = 0.0
			_mostrar_horario(_horario)
		KEY_Z:
			_en_azul = not _en_azul
			_de_cerca = false
			_ubicar_camara()
		KEY_C:
			_de_cerca = not _de_cerca
			_ubicar_camara()
		KEY_V:
			_vida_azul = 0.0 if _vida_azul < 0.0 else (1.0 if _vida_azul < 0.5 else -1.0)
			var campo: VitalityField = VitalityField.find_in(get_tree())
			var azul := _mapa.get_node_or_null(^"Azul") as Station
			if campo != null and azul != null:
				campo.set_station_override(azul.get_station_id(), _vida_azul)
			_mostrar_horario(_horario)


func _probar_paleta() -> void:
	_comprobar(Palette.size() == 64 and Palette.HEX.size() == 64, "La paleta tiene 64 colores con nombre")
	var propios: int = 0
	for indice: int in Palette.size():
		if Palette.nearest(Palette.color_at(indice)) == indice:
			propios += 1
	_comprobar(propios == Palette.size(), "Cada color de la paleta se reconoce a sí mismo (%d de %d)" % [propios, Palette.size()])
	var rojo_oscuro: StringName = Palette.NAMES[Palette.nearest(Color(0.55, 0.1, 0.08))]
	_comprobar(rojo_oscuro in [&"bordo", &"bordo_oscuro", &"oxido", &"ropa_roja", &"teja"], "Un rojo oscuro de bosquejo cae en un rojizo de la paleta (%s)" % rojo_oscuro)
	_comprobar(Palette.material(&"bordo") == Palette.material(&"bordo"), "Los que piden el mismo color comparten el material")
	_comprobar(Palette.material(&"bordo") != Palette.material(&"bordo", true), "Una cara y dos caras son materiales distintos")
	var imagen: Image = (load(Palette.TEXTURE_PATH) as Texture2D).get_image()
	if imagen != null:
		var celda: int = floori(imagen.get_width() / float(Palette.COLUMNS))
		var mitad: int = floori(celda * 0.5)
		var indice: int = Palette.index_of(&"verde_estacion")
		var fila: int = floori(indice / float(Palette.COLUMNS))
		var pixel: Color = imagen.get_pixel((indice % Palette.COLUMNS) * celda + mitad, fila * celda + mitad)
		_comprobar(pixel.is_equal_approx(Palette.color(&"verde_estacion")) or pixel.to_html(false) == Palette.color(&"verde_estacion").to_html(false), "La imagen de la paleta y los colores del código coinciden (verde estación)")


func _probar_pintor() -> void:
	var liso := StandardMaterial3D.new()
	liso.albedo_color = Palette.color(&"verde_estacion")
	var brillante := StandardMaterial3D.new()
	brillante.emission_enabled = true
	var transparente := StandardMaterial3D.new()
	transparente.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_comprobar(LookPainter.can_paint(liso) and not LookPainter.can_paint(brillante) and not LookPainter.can_paint(transparente), "Se repinta lo liso; lo que brilla y lo transparente no")
	var pintor := LookPainter.new()
	var pintado := pintor.convert_material(liso) as ShaderMaterial
	_comprobar(pintado != null and int(pintado.get_shader_parameter(&"swatch")) == Palette.index_of(&"verde_estacion"), "Un material verde estación pasa a la celda verde estación")
	_comprobar(pintor.convert_material(liso) == pintado, "Cada material se convierte una sola vez")
	var malla := MeshInstance3D.new()
	malla.mesh = BoxMesh.new()
	(malla.mesh as BoxMesh).material = liso
	pintor.paint_node(malla)
	_comprobar(malla.get_surface_override_material(0) == pintado, "La malla queda con el material de la paleta")
	var guardada := MeshInstance3D.new()
	guardada.material_override = liso
	guardada.set_meta(LookPainter.KEEP_META, true)
	pintor.paint_node(guardada)
	_comprobar(guardada.material_override == liso, "Lo marcado para no repintar queda como estaba")
	malla.free()
	guardada.free()


func _probar_dia() -> void:
	var dia := load(DIA) as DayLook
	_comprobar(dia != null and dia.keys.size() >= 4, "El día tiene sus momentos (data/look/dia_pampa.tres)")
	if dia == null:
		return
	var mediodia: DayLookKey = dia.sample(12.5)
	var noche: DayLookKey = dia.sample(23.0)
	_comprobar(mediodia.sun_energy > 1.0 and noche.sun_energy < 0.3, "Al mediodía el sol pega fuerte y de noche la luna apenas")
	_comprobar(noche.ambient_color.b > noche.ambient_color.r and mediodia.ambient_color.b > mediodia.ambient_color.r, "La luz ambiente es azulada: las sombras nunca son grises (D140)")
	var antes: DayLookKey = dia.sample(23.95)
	var despues: DayLookKey = dia.sample(0.05)
	_comprobar(_distancia(antes.sky_top, despues.sky_top) < 0.05, "El cielo no salta a la medianoche")
	_comprobar(_distancia(dia.sample(-1.0).sky_top, dia.sample(23.0).sky_top) < 0.001, "Las horas dan la vuelta (-1 es las 23)")
	var atardecer: DayLookKey = dia.sample(19.0)
	_comprobar(atardecer.sky_horizon.r > atardecer.sky_horizon.b, "Al atardecer el horizonte es naranja")


func _probar_sol() -> void:
	var mediodia: Vector3 = LookDirector.light_direction(13.0, 6.0, 20.0, 62.0, 40.0)
	var manana: Vector3 = LookDirector.light_direction(7.0, 6.0, 20.0, 62.0, 40.0)
	var tarde: Vector3 = LookDirector.light_direction(19.0, 6.0, 20.0, 62.0, 40.0)
	var noche: Vector3 = LookDirector.light_direction(1.0, 6.0, 20.0, 62.0, 40.0)
	_comprobar(mediodia.y > 0.85 and mediodia.z > 0.4, "Al mediodía el sol está alto y al norte")
	_comprobar(manana.dot(LookDirector.EAST) > 0.8 and tarde.dot(LookDirector.EAST) < -0.8, "Sale por el este y se pone por el oeste")
	_comprobar(noche.y > 0.0 and is_equal_approx(LookDirector.light_direction(6.0, 6.0, 20.0, 62.0, 40.0).y, sin(deg_to_rad(4.0))), "De noche hay luna y la luz nunca queda bajo el suelo")


func _probar_vitalidad() -> void:
	_comprobar(is_equal_approx(VitalityField.station_vitality(1, 4, 0.3, 1.0), 0.3) and is_equal_approx(VitalityField.station_vitality(4, 4, 0.3, 1.0), 1.0), "Una estación sin crecer está apagada y en su último nivel tiene todo el color")
	_comprobar(VitalityField.station_vitality(2, 4, 0.3, 1.0) > 0.3 and VitalityField.station_vitality(2, 4, 0.3, 1.0) < VitalityField.station_vitality(3, 4, 0.3, 1.0), "Cada nivel le devuelve color (D141)")
	_comprobar(is_equal_approx(VitalityField.weight_at(10.0, 25.0, 30.0), 1.0) and is_equal_approx(VitalityField.weight_at(60.0, 25.0, 30.0), 0.0), "La vida de una vía llega a su costado y se funde lejos")


func _probar_escena_vitalidad() -> void:
	var campo: VitalityField = VitalityField.find_in(get_tree())
	var azul := _mapa.get_node_or_null(^"Azul") as Station
	_comprobar(campo != null and azul != null, "El Hito A tiene su mapa de vitalidad (nodo Vitalidad)")
	if campo == null or azul == null:
		return
	campo.set_station_override(azul.get_station_id(), 0.0)
	campo.rebuild()
	var apagada: float = campo.get_vitality_at(azul.global_position)
	campo.set_station_override(azul.get_station_id(), 1.0)
	campo.rebuild()
	var viva: float = campo.get_vitality_at(azul.global_position)
	campo.set_station_override(azul.get_station_id(), -1.0)
	campo.rebuild()
	var propia: float = campo.get_vitality_at(azul.global_position)
	print("Vitalidad en Azul: %.2f apagada, %.2f viva, %.2f con su nivel (%d); campo suelto %.2f." % [apagada, viva, propia, azul.level, campo.base_vitality])
	_comprobar(apagada < 0.05 and viva > 0.95, "En Azul la vitalidad va de 0 a 1 según se pida")
	_comprobar(propia >= apagada and propia <= viva, "Con su nivel queda en el medio")


func _probar_tema() -> void:
	var tema: Theme = RailTheme.get_theme()
	_comprobar(tema == RailTheme.get_theme() and InventoryUI.make_theme() == tema, "Un solo tema de cartel ferroviario, el mismo del TAB y el mercado")
	_comprobar(tema.get_type_variation_base(RailTheme.CARTEL) == &"Label" and tema.get_color(&"font_color", RailTheme.CARTEL) == RailTheme.CREAM, "Los carteles de pantalla son verdes con letra crema")
	var caja := tema.get_stylebox(&"normal", RailTheme.CARTEL) as StyleBoxFlat
	_comprobar(caja != null and caja.bg_color.g > caja.bg_color.r and caja.border_color == RailTheme.CREAM, "Fondo verde estación con filete crema")
	var fuente := RailTheme.sign_font() as SystemFont
	_comprobar(fuente != null and fuente.font_names.has("Bahnschrift"), "Letra de boletería (Bahnschrift o la condensada que haya)")


func _probar_figura() -> void:
	var opciones: Array[StringName] = [&"pelo", &"barro"]
	var rng := RandomNumberGenerator.new()
	_comprobar(BigHeadFigure.pick(&"bordo", opciones, rng) == &"bordo" and opciones.has(BigHeadFigure.pick(&"", opciones, rng)), "El cabezón usa el color pedido o uno de la lista")
	var figura := BigHeadFigure.new()
	figura.look_seed = 7
	figura.shirt = &"ropa_roja"
	figura.random_hat = false
	figura.hat = BigHeadFigure.Hat.CAP
	add_child(figura)
	var mirada: Dictionary[StringName, Variant] = figura.get_look()
	_comprobar(mirada.get(&"shirt") == &"ropa_roja" and mirada.get(&"hat") == BigHeadFigure.Hat.CAP and BigHeadFigure.SKINS.has(mirada.get(&"skin")), "Arma la ropa pedida y elige el resto")
	var otra := BigHeadFigure.new()
	otra.look_seed = 7
	otra.shirt = &"ropa_roja"
	otra.random_hat = false
	otra.hat = BigHeadFigure.Hat.CAP
	add_child(otra)
	_comprobar(otra.get_look() == mirada, "La misma semilla da el mismo personaje")
	var piezas: Array[MeshInstance3D] = []
	_juntar_mallas(figura, piezas)
	var cabeza_ok: bool = false
	var de_paleta: bool = not piezas.is_empty()
	for malla: MeshInstance3D in piezas:
		var esfera := malla.mesh as SphereMesh
		if esfera != null and is_equal_approx(esfera.radius, BigHeadFigure.HEAD_RADIUS):
			cabeza_ok = true
		de_paleta = de_paleta and malla.material_override is ShaderMaterial
	_comprobar(piezas.size() >= 12 and cabeza_ok and de_paleta and figura.get_child_count() == 0, "Cuerpo de piezas internas, cabeza grande, todo con la paleta")
	_comprobar(BigHeadFigure.HEAD_RADIUS * 2.0 / (BigHeadFigure.HEAD_Y + BigHeadFigure.HEAD_RADIUS) > 0.3, "La cabeza mide casi un tercio del alto")
	figura.auto_walk = false
	for _i: int in 30:
		figura.animate(1.4, 0.05)
	var caminando: float = figura.get_walk_amount()
	for _i: int in 30:
		figura.animate(0.0, 0.05)
	_comprobar(caminando > 0.9 and figura.get_walk_amount() < 0.05, "Mueve piernas y brazos al caminar y se para derecho quieto")
	figura.free()
	otra.free()


# Incluye los hijos internos (el cuerpo del cabezón lo es).
func _juntar_mallas(raiz: Node, mallas: Array[MeshInstance3D]) -> void:
	for hijo: Node in raiz.get_children(true):
		if hijo is MeshInstance3D:
			mallas.append(hijo as MeshInstance3D)
		_juntar_mallas(hijo, mallas)


func _probar_escena_figuras() -> void:
	var cuerpo := _mapa.get_node_or_null(^"Player/Visual/Figura") as BigHeadFigure
	_comprobar(cuerpo != null and cuerpo.get_look().get(&"hat") == BigHeadFigure.Hat.CAP, "El jugador es un maquinista cabezón con gorra")
	var pobladores: int = 0
	var colonos: int = 0
	for nodo: Node in _mapa.find_children("*", "", true, false):
		if nodo is Townsperson and (nodo as Townsperson).get_figure() != null:
			pobladores += 1
		elif nodo is MissionGiver and nodo.get_node_or_null(^"Figura") is BigHeadFigure:
			colonos += 1
	print("Estética: %d pobladores y %d personajes con historia cabezones." % [pobladores, colonos])
	_comprobar(pobladores > 0 and colonos > 0, "Pobladores y personajes con historia son cabezones")


func _probar_escena_tema() -> void:
	var cartel := _mapa.get_node_or_null(^"Hud/Label") as Label
	_comprobar(cartel != null and cartel.theme_type_variation == RailTheme.CARTEL, "El cartel del día y la plata del Hito A es un cartel ferroviario")
	var tablero_ok: bool = false
	for nodo: Node in _mapa.find_children("*", "", true, false):
		if nodo is StationBoard:
			var texto := nodo.get_node_or_null(StationBoard.TEXT_PATH) as Label3D
			tablero_ok = texto != null and texto.font == RailTheme.sign_font() and texto.modulate == RailTheme.CREAM
			break
	_comprobar(tablero_ok, "El tablero de la estación escribe con letra crema de cartel")


func _probar_escena() -> void:
	_estetica = LookDirector.find_in(get_tree())
	_comprobar(_estetica != null, "El Hito A tiene su LookDirector (nodo Estetica)")
	if _estetica == null:
		return
	print("Estética: %d superficies repintadas con la paleta." % _estetica.get_painter().get_painted_count())
	_comprobar(_estetica.get_painter().get_painted_count() > 100, "Se repintaron los bosquejos del Hito A")
	var ambiente := _mapa.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if ambiente != null:
		var entorno: Environment = ambiente.environment
		_comprobar(entorno.tonemap_mode == Environment.TONE_MAPPER_AGX, "Tonemap AgX")
		_comprobar(entorno.ssao_enabled and entorno.glow_enabled and entorno.fog_enabled, "SSAO suave, glow bajo y niebla")
		_comprobar(entorno.sky != null and entorno.sky.sky_material is ShaderMaterial, "Cielo de degradado con shader")
	var terreno := _mapa.get_node_or_null(^"Terreno/Malla") as MeshInstance3D
	_comprobar(terreno != null and terreno.get_surface_override_material(0) is ShaderMaterial, "El terreno pinta con el material del mundo")
	var horizonte := _mapa.get_node_or_null(^"Horizonte") as HorizonRing
	_comprobar(horizonte != null and horizonte.material_override is ShaderMaterial, "El horizonte cambia de color con la hora")
	var pasto: MultiMeshInstance3D = null
	var vegetacion: BiomeScatter = BiomeScatter.find_in(get_tree())
	if vegetacion != null:
		for hijo: Node in vegetacion.get_children():
			if hijo.name.begins_with("pasto_largo") and hijo is MultiMeshInstance3D:
				pasto = hijo as MultiMeshInstance3D
				break
	var material_pasto: ShaderMaterial = (pasto.material_override as ShaderMaterial) if pasto != null else null
	_comprobar(material_pasto != null and float(material_pasto.get_shader_parameter(&"wind")) > 0.0, "El pasto se mueve con el viento")
	var loco := _primera_locomotora()
	_comprobar(loco != null and _tiene_material_del_mundo(loco), "La locomotora quedó repintada con la paleta")
	_estetica.fixed_hour = 23.0
	_estetica.apply(23.0)
	_comprobar(_estetica.sun.light_energy < 0.3 and _estetica.sun.global_basis.z.y > 0.0, "A las 23 la luz es la de la luna, que está arriba")
	_estetica.fixed_hour = 12.5
	_estetica.apply(12.5)
	_comprobar(_estetica.sun.light_energy > 1.0, "A las 12:30 pega el sol")
	_probar_escena_vitalidad()
	_probar_escena_tema()
	_probar_escena_figuras()


func _armar_vista() -> void:
	if _estetica == null:
		return
	var jugador := _mapa.get_node_or_null(^"Player") as Node3D
	if jugador != null:
		jugador.process_mode = Node.PROCESS_MODE_DISABLED
		var visual := jugador.get_node_or_null(^"Visual") as Node3D
		if visual != null:
			visual.rotation.y = 0.0
		for i: int in 4:
			var poblador := BigHeadFigure.new()
			poblador.look_seed = 100 + i
			poblador.random_hat = false
			poblador.hat = i as BigHeadFigure.Hat
			poblador.auto_walk = false
			poblador.position = jugador.global_position + Vector3(-2.4 + i * 1.2 + (1.2 if i >= 2 else 0.0), 0.0, 0.6)
			add_child(poblador)
	_camara = Camera3D.new()
	_camara.name = "CamaraFija"
	_camara.fov = 60.0
	_camara.far = 4000.0
	add_child(_camara)
	_ubicar_camara()
	var capa := CanvasLayer.new()
	capa.layer = 10
	add_child(capa)
	_cartel = Label.new()
	_cartel.add_theme_font_size_override(&"font_size", 22)
	_cartel.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_cartel.add_theme_constant_override(&"outline_size", 6)
	_cartel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_cartel.position.y = 12.0
	capa.add_child(_cartel)
	_mostrar_horario(1)


func _ubicar_camara() -> void:
	var azul := _mapa.get_node_or_null(^"Azul") as Node3D
	var jugador := _mapa.get_node_or_null(^"Player") as Node3D
	if _de_cerca and jugador != null:
		_camara.global_position = jugador.global_position + Vector3(0.8, 1.7, -5.5)
		_camara.look_at(jugador.global_position + Vector3(0.0, 1.0, 0.0))
	elif _en_azul and azul != null:
		_camara.global_position = azul.global_position + azul_camera_offset
		_camara.look_at(azul.global_position + azul_target_offset)
	else:
		_camara.global_position = camera_position
		_camara.look_at(camera_target)
	_camara.make_current()


func _mostrar_horario(indice: int) -> void:
	_horario = indice
	_estetica.fixed_hour = HORAS[indice]
	var vida: String = "según su nivel" if _vida_azul < 0.0 else ("0 (abandonada)" if _vida_azul < 0.5 else "1 (llena de vida)")
	_cartel.text = "%s (%s) · 1 a 4: horario · Espacio: %s\nZ: cámara de %s · V: vitalidad de Azul, %s · C: personajes de cerca" % [NOMBRES[indice], GameClock.format_time(HORAS[indice]), "parar" if _automatico else "pasar solo", "Olavarría" if _en_azul else "Azul", vida]


func _primera_locomotora() -> Node:
	for nodo: Node in _mapa.find_children("*", "", true, false):
		if nodo is Vehicle and nodo.scene_file_path.ends_with("locomotive.tscn"):
			return nodo
	return null


func _tiene_material_del_mundo(raiz: Node) -> bool:
	for nodo: Node in raiz.find_children("*", "MeshInstance3D", true, false):
		var malla := nodo as MeshInstance3D
		if malla.material_override is ShaderMaterial or (malla.mesh != null and malla.get_surface_override_material(0) is ShaderMaterial):
			return true
	return false


static func _distancia(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _comprobar(condicion: bool, mensaje: String) -> void:
	if condicion:
		print("OK: ", mensaje)
	else:
		_fallos += 1
		push_error("FALLÓ: " + mensaje)
