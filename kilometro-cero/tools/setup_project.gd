@tool
extends EditorScript
## Configuración inicial del proyecto (tarea 3): acciones del InputMap, nombres de
## capas de colisión, variables globales de shader (62c.3e) y archivos .gitkeep. Se corre desde File > Run (Ctrl+Shift+X).
## Es idempotente: correrlo de nuevo deja todo igual. Por eso la configuración vive
## en código versionado y no depende de clics manuales en el editor.

# Orden = número de capa (la primera es la capa 1). Debe coincidir con
# la sección 9 de 02-arquitectura.md.
const CAPAS_FISICAS_3D: Array[String] = [
	"mundo",
	"jugador",
	"objetos_sueltos",
	"interactuables",
	"fantasmas",
	"zonas_almacenamiento",
]

# Acciones que existieron antes y ya no se usan. Se borran para que el Input Map
# no acumule teclas muertas (D68, D71: una sola mano, una sola acción de soltar;
# D91: el vehículo avanza con W y se libera Espacio para saltar).
const ACCIONES_OBSOLETAS: Array[StringName] = [
	&"drop_left",
	&"drop_right",
	&"backpack_store",
	&"backpack_take",
	&"push",
]


func _run() -> void:
	var acciones: Dictionary = _definir_acciones()
	_registrar_acciones(acciones)
	_borrar_obsoletas()
	_nombrar_capas()
	_declarar_globales_de_shader()

	var error: Error = ProjectSettings.save()
	if error != OK:
		push_error("No se pudo guardar la configuración (código %d)" % error)
		return

	_verificar_acciones(acciones)
	_crear_gitkeep("res://")
	print("Listo: %d acciones y %d capas configuradas." % [acciones.size(), CAPAS_FISICAS_3D.size()])


# Nombre de la acción -> lista de entradas que la disparan.
# El código del juego solo conoce los nombres, nunca las teclas (02-arquitectura, sección 4).
func _definir_acciones() -> Dictionary:
	return {
		&"move_forward": [_tecla(KEY_W)],    # también acelera el vehículo
		&"move_back": [_tecla(KEY_S)],
		&"move_left": [_tecla(KEY_A)],
		&"move_right": [_tecla(KEY_D)],
		&"interact": [_tecla(KEY_F)],        # entrar y salir de la cabina (D84)
		&"grab": [_tecla(KEY_E)],            # recolectar (D69)
		&"drop": [_tecla(KEY_Q)],            # soltar lo que hay en la mano
		&"place": [_boton_mouse(MOUSE_BUTTON_RIGHT)],  # toque: soltar; mantener: apuntar el fantasma
		# Dos acciones porque una sola no sabe en qué dirección giró la rueda.
		&"rotate_cw": [_boton_mouse(MOUSE_BUTTON_WHEEL_UP)],
		&"rotate_ccw": [_boton_mouse(MOUSE_BUTTON_WHEEL_DOWN)],
		&"inventory": [_tecla(KEY_TAB), _tecla(KEY_G)],  # abrir y cerrar el inventario (D71, D72)
		&"sprint": [_tecla(KEY_SHIFT)],      # correr mientras se mantiene, sin costo (D91)
		&"jump": [_tecla(KEY_SPACE)],        # saltar (D91)
		&"crouch": [_tecla(KEY_CTRL)],       # agacharse mientras se mantiene (D91)
		# En la cabina W y S mueven la palanca y Espacio frena (D91): reusan las de arriba.
		&"lights": [_tecla(KEY_L)],          # luces de la locomotora (D91)
		&"horn": [_tecla(KEY_H)],            # bocina (D91)
		&"doors": [_tecla(KEY_O)],           # puertas de los coches de pasajeros (tarea 60b)
		&"camera_view": [_tecla(KEY_V)],     # cabina o cámara exterior del tren (tarea 60c)
		&"use_tool": [_boton_mouse(MOUSE_BUTTON_LEFT)],  # golpear con la herramienta clave (D91, tarea 55)
	}


func _tecla(codigo: Key) -> InputEventKey:
	var evento := InputEventKey.new()
	# physical_keycode usa la posición de la tecla, no la letra: WASD sigue
	# siendo "las cuatro de la izquierda" aunque el teclado tenga otra distribución.
	evento.physical_keycode = codigo
	return evento


func _boton_mouse(boton: MouseButton) -> InputEventMouseButton:
	var evento := InputEventMouseButton.new()
	evento.button_index = boton
	return evento


func _registrar_acciones(acciones: Dictionary) -> void:
	for nombre: StringName in acciones:
		# Es el mismo formato que usa el editor al guardar el Input Map.
		ProjectSettings.set_setting(
			"input/" + String(nombre),
			{"deadzone": 0.5, "events": acciones[nombre]}
		)


func _borrar_obsoletas() -> void:
	for nombre: StringName in ACCIONES_OBSOLETAS:
		var clave: String = "input/" + String(nombre)
		if ProjectSettings.has_setting(clave):
			# Poner un ajuste en null lo elimina de ProjectSettings.
			ProjectSettings.set_setting(clave, null)
			print("Acción obsoleta eliminada: %s" % nombre)


func _nombrar_capas() -> void:
	for i: int in CAPAS_FISICAS_3D.size():
		# Con nombre, el inspector muestra "mundo" en vez de "Layer 1".
		ProjectSettings.set_setting("layer_names/3d_physics/layer_%d" % (i + 1), CAPAS_FISICAS_3D[i])


# Las variables globales que lee el material del mundo (tarea 62c.3e, vitalidad D141). Sin ellas
# el shader no compila; Palette.ensure_globals las agrega igual mientras corre el juego.
func _declarar_globales_de_shader() -> void:
	var globales: Dictionary = {
		"vitality_map": {"type": "sampler2D", "value": ""},
		"vitality_map_prev": {"type": "sampler2D", "value": ""},
		"vitality_mix": {"type": "float", "value": 1.0},
		"vitality_rect": {"type": "vec4", "value": Vector4(0.0, 0.0, 1.0, 1.0)},
		"vitality_enabled": {"type": "float", "value": 0.0},
	}
	for nombre: String in globales:
		var clave: String = "shader_globals/" + nombre
		if not ProjectSettings.has_setting(clave):
			ProjectSettings.set_setting(clave, globales[nombre])


# Releemos la configuración guardada para confirmar que quedó cargada de verdad.
func _verificar_acciones(acciones: Dictionary) -> void:
	InputMap.load_from_project_settings()
	for nombre: StringName in acciones:
		if not InputMap.has_action(nombre) or InputMap.action_get_events(nombre).is_empty():
			push_warning("Falta la acción: %s" % nombre)
	for nombre: StringName in ACCIONES_OBSOLETAS:
		if InputMap.has_action(nombre):
			push_warning("Sigue existiendo la acción obsoleta: %s" % nombre)


# Git no guarda carpetas vacías: dejamos un .gitkeep en las que no tengan nada.
# DirAccess ignora los archivos y carpetas ocultos, así que no toca .git ni .godot.
func _crear_gitkeep(ruta: String) -> void:
	var directorio := DirAccess.open(ruta)
	if directorio == null:
		return
	var subcarpetas: PackedStringArray = directorio.get_directories()
	if subcarpetas.is_empty() and directorio.get_files().is_empty() and ruta != "res://":
		FileAccess.open(ruta.path_join(".gitkeep"), FileAccess.WRITE)
	for subcarpeta: String in subcarpetas:
		_crear_gitkeep(ruta.path_join(subcarpeta))
