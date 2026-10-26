extends Node3D
## Prueba de la tarea 60c: cámara exterior del tren (TrainCamera, tecla V), botonera de la
## cabina (CabButton, clic con la mira) y CabHud. Una vía recta con la locomotora, una
## plataforma y el jugador al lado. Al terminar vuelve a cargar la escena para jugar.

const CONTROLES: String = "WASD: caminar · F: entrar o salir de la cabina · V: cámara de afuera o de la cabina\nEn la cabina: clic en los botones (con la mira) o W/S marcha · Espacio freno · L luces · H bocina\nAfuera: mouse gira alrededor del tren, rueda acerca y aleja"

static var _probado: bool = false

@onready var _loco: Vehicle = $Linea/Locomotive
@onready var _player: Player = $Player
@onready var _hud: Label = $Hud/Label

var _fallos: int = 0


func _ready() -> void:
	_asegurar_acciones()
	if _probado:
		return
	_probado = true
	await _esperar_fisica(4)
	await _probar_cabina()
	if _fallos == 0:
		print("Cámara y botonera: todas las comprobaciones pasaron.")
	else:
		push_error("Cámara y botonera: fallaron %d comprobaciones." % _fallos)
	get_tree().reload_current_scene.call_deferred()


func _process(_delta: float) -> void:
	var cab: Cab = _loco.get_node("Cab")
	_hud.text = CONTROLES + "\n" + CabHud.status_text(cab)


func _probar_cabina() -> void:
	var cab: Cab = _loco.get_node("Cab")
	var exterior: TrainCamera = cab.get_exterior_camera()
	_comprobar(exterior != null and exterior.name == &"CamaraExterior", "La cabina arma su cámara exterior")
	var botones: Dictionary = {}
	for boton: CabButton in cab.get_buttons():
		botones[boton.control] = boton
	_comprobar(botones.size() == 4 and botones.has(&"brake") and botones.has(&"lights") and botones.has(&"horn") and botones.has(&"doors"), "La botonera tiene Freno, Luces, Bocina y Puertas (la marcha va con la palanca)")
	_probar_orientacion(cab)
	_comprobar(cab.view == Cab.View.CAB, "Arranca en la vista de la cabina")

	cab.occupy(_player)
	await _esperar_fisica(2)
	_comprobar(cab.get_camera().current, "Al entrar se ve desde la cabina")
	_comprobar(cab.get_hud() != null and cab.get_hud().get_status_text().contains("Punto muerto"), "El cartel muestra la marcha")
	_comprobar(cab.get_hud().get_keys_text().contains("V: vista de afuera"), "El cartel dice cómo cambiar de vista")

	_tocar(&"move_forward")
	_comprobar(cab.notch == 1 and _loco.throttle > 0.0, "W sube una muesca")
	# Apuntar la mira al botón Freno y hacer clic.
	_apuntar(cab, botones[&"brake"])
	await _esperar_fisica(2)
	await _esperar_cuadros(2)
	_comprobar(cab.get_aimed_button() == botones[&"brake"], "La mira encuentra el botón Freno")
	_comprobar(botones[&"brake"].is_hovered() and cab.get_hud().get_aim_text() == "Clic: Freno", "El botón apuntado se ilumina y el cartel lo nombra")
	_tocar(&"use_tool")
	_comprobar(cab.brake_latched, "Clic en Freno pone el freno")
	await _esperar_fisica(2)
	_comprobar(cab.braking and _loco.brake == 1.0, "El freno de botón frena sin mantener Espacio")
	await _esperar_cuadros(2)   # el cartel se escribe en _process
	_comprobar(cab.get_hud().get_status_text().contains("Freno puesto"), "El cartel muestra el freno puesto")
	_comprobar(botones[&"brake"].press() and not cab.brake_latched, "Otro clic saca el freno")
	botones[&"brake"].press()
	_tocar(&"move_forward")
	await _esperar_fisica(2)
	_comprobar(cab.notch == 2 and not cab.brake_latched and not cab.braking, "Mover la palanca saca el freno de botón")

	_comprobar(botones[&"lights"].press() and cab.lights_on, "El botón Luces prende las luces")
	var bocina: Array[bool] = [false]
	cab.horn_sounded.connect(func() -> void: bocina[0] = true)
	botones[&"horn"].press()
	_comprobar(bocina[0], "El botón Bocina toca la bocina")
	_comprobar(not botones[&"doors"].press(), "Sin coche, el botón Puertas no hace nada")
	_comprobar(cab.press_control(&"back") and cab.notch == 1, "S (press_control back) baja una muesca")

	# Cámara exterior.
	_tocar(&"camera_view")
	await _esperar_cuadros(2)
	_comprobar(cab.view == Cab.View.EXTERIOR and exterior.current, "V pasa a la cámara de afuera")
	var objetivo: Vector3 = exterior.get_target()
	var frente: Vector3 = -_loco.global_basis.z
	_comprobar((exterior.global_position - objetivo).dot(frente) < -5.0, "Empieza detrás del tren")
	_comprobar(absf(exterior.global_position.distance_to(objetivo) - 18.0) < 0.1, "A 18 m del centro del tren")
	_comprobar(exterior.global_position.y > objetivo.y, "Mira desde arriba")
	_comprobar(cab.get_aimed() == null and cab.get_hud().get_aim_text() == "", "Afuera no hay mira")
	_comprobar(cab.get_hud().get_keys_text().contains("Rueda"), "El cartel cambia las teclas")
	exterior.orbit(PI, 0.0)
	_comprobar((exterior.global_position - exterior.get_target()).dot(frente) > 5.0, "El mouse gira la cámara alrededor del tren")
	_tocar(&"rotate_cw")
	_comprobar(absf(exterior.distance - 16.0) < 0.01, "La rueda acerca")
	exterior.zoom(100.0)
	_comprobar(exterior.distance == exterior.max_distance, "No se aleja más que el máximo")
	_tocar(&"move_forward")
	_tocar(&"lights")
	_comprobar(cab.notch == 2 and not cab.lights_on, "Afuera las teclas siguen manejando")
	_tocar(&"use_tool")
	_comprobar(cab.notch == 2, "Afuera el clic no aprieta botones")
	# Sigue al tren cuando avanza.
	var antes: Vector3 = exterior.global_position
	await _esperar_fisica(30)
	await _esperar_cuadros(2)
	_comprobar(antes.distance_to(exterior.global_position) > 0.1 and absf(exterior.global_position.distance_to(exterior.get_target()) - exterior.distance) < 0.1, "La cámara sigue al tren")

	cab.release()
	_player.get_camera().make_current()   # lo hace Player al salir
	await _esperar_cuadros(2)
	_comprobar(not exterior.current and not cab.get_camera().current and cab.get_hud() == null, "Al salir se apagan las cámaras y el cartel")
	cab.occupy(_player)
	_comprobar(cab.view == Cab.View.EXTERIOR and exterior.current, "Al volver recuerda la vista de afuera")
	_tocar(&"camera_view")
	_comprobar(cab.view == Cab.View.CAB and cab.get_camera().current, "V vuelve a la cabina")
	cab.set_notch(0)
	cab.release()


# La botonera mira al puesto: inclinada hacia el maquinista y con los carteles derechos.
func _probar_orientacion(cab: Cab) -> void:
	var ojo: Vector3 = cab.get_camera().global_position
	var botonera: Node3D = cab.get_node("Botonera")
	var hacia_ojo: Vector3 = ojo - botonera.global_position
	var normal: Vector3 = botonera.global_basis.y
	_comprobar(normal.dot(hacia_ojo.normalized()) > 0.3, "La botonera está inclinada hacia el puesto")
	_comprobar(botonera.global_position.distance_to(cab.get_node("Palanca").global_position) < 0.6, "La botonera está junto a la palanca")
	var derechos: bool = true
	for boton: CabButton in cab.get_buttons():
		var cartel: Label3D = null
		for hijo: Node in boton.get_children():
			if hijo is Label3D:
				cartel = hijo
		if cartel == null:
			derechos = false
			continue
		var mirada: Basis = Basis.looking_at(cartel.global_position - ojo)
		var frente_ok: bool = cartel.global_basis.z.dot(ojo - cartel.global_position) > 0.0
		var arriba_ok: bool = cartel.global_basis.y.dot(mirada.y) > 0.5
		derechos = derechos and frente_ok and arriba_ok
	_comprobar(derechos, "Los carteles de los botones se leen derechos desde el puesto")


# Gira la cabeza para que la mira (el centro de la cámara) apunte al botón.
func _apuntar(cab: Cab, boton: CabButton) -> void:
	var camara: Camera3D = cab.get_camera()
	var local: Vector3 = cab.global_basis.inverse() * (boton.global_position - camara.global_position)
	var yaw: float = atan2(-local.x, -local.z)
	var pitch: float = atan2(local.y, Vector2(local.x, local.z).length())
	cab.look(yaw - cab.look_yaw, pitch - cab.look_pitch)


func _tocar(accion: StringName) -> void:
	var evento := InputEventAction.new()
	evento.action = accion
	evento.pressed = true
	Input.parse_input_event(evento)
	Input.flush_buffered_events()
	evento = InputEventAction.new()
	evento.action = accion
	evento.pressed = false
	Input.parse_input_event(evento)
	Input.flush_buffered_events()


# Las acciones las crea tools/setup_project.gd; si todavía no se corrió, la prueba las agrega.
func _asegurar_acciones() -> void:
	for par: Array in [[&"doors", KEY_O], [&"camera_view", KEY_V]]:
		if InputMap.has_action(par[0]):
			continue
		InputMap.add_action(par[0])
		var tecla := InputEventKey.new()
		tecla.physical_keycode = par[1]
		InputMap.action_add_event(par[0], tecla)


func _esperar_cuadros(cuadros: int) -> void:
	for i: int in cuadros:
		await get_tree().process_frame


func _esperar_fisica(pasos: int) -> void:
	for i: int in pasos:
		await get_tree().physics_frame


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
