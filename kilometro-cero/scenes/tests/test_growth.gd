extends Node3D
## Prueba de la tarea 60: crecimiento visible (D79). Station.grew, GrowthCelebration (lo nuevo
## brota, campana, papelitos y cartel), Townsperson (pobladores que pasean), NightLight (faroles
## de noche) y AmbientLayer (una capa de sonido por nivel). Pueblo y ciudad sin vías.
## Primero corre las comprobaciones (tarda unos 20 segundos) y después vuelve a cargar la
## escena limpia para jugar (ver CONTROLES).

const CONTROLES: String = "WASD: caminar · N: sube el nivel del pueblo · B: lo baja · M: sube la ciudad · H: noche o día\nAcercate a cada pueblo para oír sus capas de sonido."
## Hora del día y de la noche que pone H.
const DAY_HOUR: float = 10.0
const NIGHT_HOUR: float = 21.0

## Ya se corrieron las comprobaciones: al recargar la escena queda solo para jugar.
static var _probado: bool = false

@onready var _pueblo: Station = $Pueblo
@onready var _ciudad: Station = $Ciudad
@onready var _festejo: GrowthCelebration = $Pueblo/Festejo
@onready var _sol: DirectionalLight3D = $DirectionalLight3D
@onready var _entorno: WorldEnvironment = $WorldEnvironment
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0
var _crecimientos: Array = []
var _festejos: int = 0


func _ready() -> void:
	_pueblo.grew.connect(func(nivel: int, anterior: int) -> void: _crecimientos.append([nivel, anterior]))
	_festejo.celebrated.connect(func(_nivel: int) -> void: _festejos += 1)
	if _probado:
		return
	_probado = true
	_probar_logica()
	await _probar_escena()

	if _fallos == 0:
		print("Crecimiento: todas las comprobaciones pasaron.")
	else:
		push_error("Crecimiento: fallaron %d comprobaciones." % _fallos)
	# Partida limpia para jugar, de día.
	GameState.reset_production()
	GameState.clock.time_of_day = DAY_HOUR
	get_tree().reload_current_scene.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	var tecla := event as InputEventKey
	if tecla == null or not tecla.pressed or tecla.echo:
		return
	match tecla.physical_keycode:
		KEY_N:
			_pueblo.set_level(_pueblo.level + 1)
		KEY_B:
			_pueblo.set_level(_pueblo.level - 1)
		KEY_M:
			_ciudad.set_level(_ciudad.level + 1)
		KEY_H:
			_poner_hora(DAY_HOUR if _es_de_noche() else NIGHT_HOUR)


func _process(_delta: float) -> void:
	# Sin cielo de noche todavía (tarea 65): la prueba oscurece el sol para ver los faroles.
	var noche: bool = _es_de_noche()
	_sol.light_energy = 0.05 if noche else 1.0
	_entorno.environment.background_energy_multiplier = 0.1 if noche else 1.0
	_entorno.environment.ambient_light_energy = 0.1 if noche else 1.0
	var lineas: PackedStringArray = [CONTROLES, "Hora %s (%s)" % [GameClock.format_time(GameState.clock.time_of_day), "noche" if noche else "día"]]
	for estacion: Station in [_pueblo, _ciudad]:
		lineas.append("%s · pobladores: %d · faroles prendidos: %d · capas de sonido: %d" % [
			estacion.describe(), _visibles(estacion, Townsperson), _faroles_prendidos(estacion), _capas_sonando(estacion)])
	_hud.text = "\n".join(lineas)


# --- Lógica pura ---


func _probar_logica() -> void:
	var adentro: bool = true
	for i: int in 50:
		var punto: Vector3 = Townsperson.pick_target(Vector3(2, 1, 3), 4.0, randf(), randf())
		adentro = adentro and punto.y == 1.0 and Vector2(punto.x - 2, punto.z - 3).length() <= 4.0 + 0.001
	_comprobar(adentro, "Los paseos quedan dentro del radio y a la misma altura")
	_comprobar(is_zero_approx(Townsperson.facing_angle(Vector3.FORWARD) - TAU) or is_zero_approx(Townsperson.facing_angle(Vector3.FORWARD)), "Mirar hacia -Z es no girar")
	var giro := Basis(Vector3.UP, Townsperson.facing_angle(Vector3.RIGHT))
	_comprobar((-giro.z).is_equal_approx(Vector3.RIGHT), "Mira hacia donde camina")

	_comprobar(NightLight.is_night_at(21.0, 19.0, 6.5) and NightLight.is_night_at(3.0, 19.0, 6.5), "Prendida a las 21 y a las 3")
	_comprobar(not NightLight.is_night_at(12.0, 19.0, 6.5) and not NightLight.is_night_at(6.5, 19.0, 6.5), "Apagada a las 12 y a las 6:30")
	_comprobar(NightLight.is_night_at(19.0, 19.0, 6.5), "Se prende justo a la hora")
	_comprobar(NightLight.is_night_at(10.0, 8.0, 16.0) and not NightLight.is_night_at(17.0, 8.0, 16.0), "Horario sin cruzar la medianoche")
	_comprobar(not NightLight.is_night_at(10.0, 5.0, 5.0), "Misma hora de prender y apagar: nunca")

	var nivel := Node3D.new()
	var casa := MeshInstance3D.new()
	nivel.add_child(casa)
	nivel.add_child(AudioStreamPlayer3D.new())
	nivel.add_child(OmniLight3D.new())
	nivel.add_child(Node.new())
	_comprobar(GrowthCelebration.get_pieces(nivel) == ([casa] as Array[Node3D]), "Brotan las piezas que se ven, no el sonido ni las luces sueltas")
	nivel.free()


# --- Escena ---


func _probar_escena() -> void:
	await _esperar(0.2)
	var casa1: Node3D = _pueblo.get_node("Niveles/Nivel1/Casa1")
	var casa2: Node3D = _pueblo.get_node("Niveles/Nivel2/Casa2")
	var casa4: Node3D = _pueblo.get_node("Niveles/Nivel3/Casa4")
	var capa1: AmbientLayer = _pueblo.get_node("Niveles/Nivel1/Ambiente")
	var capa2: AmbientLayer = _pueblo.get_node("Niveles/Nivel2/Ambiente")
	var poblador3: Townsperson = _pueblo.get_node("Niveles/Nivel2/Poblador3")
	var poblador6: Townsperson = _pueblo.get_node("Niveles/Nivel3/Poblador6")
	var farol1: NightLight = _pueblo.get_node("Niveles/Nivel1/Farol1/Luz")

	# Al cargar: nivel 1 quieto, sin festejo.
	_comprobar(_pueblo.get_level_node(2) == _pueblo.get_node("Niveles/Nivel2") and _pueblo.get_level_node(9) == null, "get_level_node encuentra NivelN")
	_comprobar(_pueblo.level == 1 and casa1.scale.is_equal_approx(Vector3.ONE), "Al cargar, lo del nivel 1 está entero")
	_comprobar(_festejo.get_message() == null and (_ciudad.get_node("Festejo") as GrowthCelebration).get_message() == null, "Al cargar la escena no se festeja")
	_comprobar(_visibles(_pueblo, Townsperson) == 2 and _visibles(_ciudad, Townsperson) == 3, "Nivel 1: 2 pobladores en el pueblo y 3 en la ciudad")
	var inicio6: Vector3 = poblador6.position
	await _esperar(2.3)
	_comprobar(capa1.is_audible() and is_equal_approx(capa1.get_fade(), capa1.loudness), "La capa del nivel 1 suena entera después del fundido")
	_comprobar(not capa2.is_audible() and not capa2.playing, "La capa del nivel 2 no suena")

	# Crece al nivel 2: brota, suena, cartel.
	_comprobar(_pueblo.set_level(2) and _crecimientos == [[2, 1]] and _festejos == 1, "Subir de nivel avisa Station.grew(2, 1) y festeja una vez")
	_comprobar(casa2.scale.x < 0.1, "Lo nuevo arranca chiquito")
	var cartel: Label3D = _festejo.get_message()
	_comprobar(cartel != null and cartel.text == "¡Pueblo creció!\nNivel 2", "Aparece el cartel: %s" % (cartel.text if cartel != null else "ninguno"))
	await _esperar(0.5)
	_comprobar(casa2.scale.x > 0.1, "Va brotando")
	await _esperar(2.5)
	_comprobar(casa2.scale.is_equal_approx(Vector3.ONE) and casa1.scale.is_equal_approx(Vector3.ONE), "Terminó de brotar a su tamaño; lo viejo no se tocó")
	_comprobar(capa2.is_audible() and capa1.is_audible(), "Se suma la capa de sonido del nivel 2")
	_comprobar(_visibles(_pueblo, Townsperson) == 5, "Nivel 2: 5 pobladores")

	# Pasean dentro de su radio; el del nivel 3, escondido, no se movió.
	var movidos: int = 0
	var en_radio: bool = true
	for persona: Townsperson in _todos(_pueblo, Townsperson):
		if not persona.is_visible_in_tree():
			continue
		var lejos: float = Vector2(persona.position.x - persona.get_home().x, persona.position.z - persona.get_home().z).length()
		if lejos > 0.01:
			movidos += 1
		en_radio = en_radio and lejos <= persona.wander_radius + 0.01
	_comprobar(movidos >= 3, "Los pobladores pasean (%d de 5 lejos de su lugar)" % movidos)
	_comprobar(en_radio, "Ninguno sale de su radio")
	_comprobar(poblador6.position == inicio6, "Un poblador escondido no camina")
	_comprobar(poblador3.position.y == poblador3.get_home().y, "Caminan sin cambiar de altura")

	# Bajar no festeja y apaga su capa.
	_crecimientos.clear()
	_pueblo.set_level(1)
	_comprobar(_crecimientos.is_empty() and _festejos == 1, "Bajar de nivel no festeja")
	await _esperar(2.3)
	_comprobar(not capa2.is_audible() and not capa2.playing, "La capa del nivel 2 se apagó con fundido")

	# Por EventBus (como lo hace el modelo de producción) de 1 a 3: brotan los dos niveles.
	EventBus.station_level_changed.emit(&"pueblo", 3)
	_comprobar(_crecimientos == [[3, 1]] and _festejos == 2, "El crecimiento que llega por EventBus también festeja")
	_comprobar(casa2.scale.x < 0.1 and casa4.scale.x < 0.1, "Brota lo de los niveles 2 y 3")
	_comprobar(_festejo.get_message() != null and _festejo.get_message().text.ends_with("Nivel 3"), "Un solo cartel, con el nivel nuevo")

	# Faroles: de noche prendidos (y su vidrio brilla), de día apagados.
	_poner_hora(NIGHT_HOUR)
	var vidrio: StandardMaterial3D = (_pueblo.get_node("Niveles/Nivel1/Farol1/Farol") as MeshInstance3D).material_override
	_comprobar(farol1.is_lit() and farol1.visible and vidrio.emission_enabled, "De noche el farol alumbra y su vidrio brilla")
	var farol_ciudad: NightLight = _ciudad.get_node("Niveles/Nivel2/Farol3/Luz")
	_comprobar(farol_ciudad.is_lit() and not farol_ciudad.is_visible_in_tree(), "El farol de un nivel que no llegó no se ve")
	var otro_vidrio: StandardMaterial3D = (_pueblo.get_node("Niveles/Nivel2/Farol2/Farol") as MeshInstance3D).material_override
	_comprobar(otro_vidrio != vidrio, "Cada farol tiene su propio vidrio")
	_poner_hora(DAY_HOUR)
	_comprobar(not farol1.is_lit() and not farol1.visible and not vidrio.emission_enabled, "De día se apaga")
	GameState.clock.time_of_day = 18.9
	GameState.clock.advance(0.2)
	_comprobar(farol1.is_lit(), "Se prende solo al pasar las 19 con el reloj")
	_poner_hora(DAY_HOUR)

	# El cartel se va solo.
	await _esperar(GrowthCelebration.MESSAGE_TIME + 0.5)
	_comprobar(_festejo.get_message() == null, "El cartel se borra después de flotar")
	_comprobar(casa4.scale.is_equal_approx(Vector3.ONE), "Lo del nivel 3 quedó entero")


func _poner_hora(hora: float) -> void:
	GameState.clock.time_of_day = hora
	for luz: NightLight in _todas_las_luces():
		luz.refresh()


func _es_de_noche() -> bool:
	return NightLight.is_night_at(GameState.clock.time_of_day, 19.0, 6.5)


func _todas_las_luces() -> Array[NightLight]:
	var luces: Array[NightLight] = []
	for estacion: Station in [_pueblo, _ciudad]:
		for nodo: Node in _todos(estacion, NightLight):
			luces.append(nodo as NightLight)
	return luces


func _todos(estacion: Station, clase: Script) -> Array[Node]:
	return estacion.get_node("Niveles").find_children("*", "", true, false).filter(func(nodo: Node) -> bool: return is_instance_of(nodo, clase))


func _visibles(estacion: Station, clase: Script) -> int:
	return _todos(estacion, clase).filter(func(nodo: Node) -> bool: return (nodo as Node3D).is_visible_in_tree()).size()


func _faroles_prendidos(estacion: Station) -> int:
	return _todos(estacion, NightLight).filter(func(nodo: Node) -> bool: return (nodo as NightLight).is_lit() and (nodo as Node3D).is_visible_in_tree()).size()


func _capas_sonando(estacion: Station) -> int:
	return _todos(estacion, AmbientLayer).filter(func(nodo: Node) -> bool: return (nodo as AmbientLayer).is_audible()).size()


func _esperar(segundos: float) -> void:
	await get_tree().create_timer(segundos).timeout


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
