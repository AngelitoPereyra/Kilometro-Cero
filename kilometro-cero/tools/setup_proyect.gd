@tool
extends EditorScript
## Configuración inicial del proyecto (tarea 3): acciones del InputMap, nombres de
## capas de colisión y archivos .gitkeep. Se corre desde File > Run (Ctrl+Shift+X).
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


func _run() -> void:
	var acciones: Dictionary = _definir_acciones()
	_registrar_acciones(acciones)
	_nombrar_capas()

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
		&"move_forward": [_tecla(KEY_W)],
		&"move_back": [_tecla(KEY_S)],
		&"move_left": [_tecla(KEY_A)],
		&"move_right": [_tecla(KEY_D)],
		&"interact": [_tecla(KEY_E)],        # subir/bajar del vehículo, usar
		&"push": [_tecla(KEY_SPACE)],        # mantener para empujar la zorra
		&"grab": [_boton_mouse(MOUSE_BUTTON_LEFT)],
		&"drop": [_tecla(KEY_Q)],
		&"place": [_boton_mouse(MOUSE_BUTTON_RIGHT)],  # confirma el fantasma
		# Dos acciones porque una sola no sabe en qué dirección giró la rueda.
		&"rotate_cw": [_boton_mouse(MOUSE_BUTTON_WHEEL_UP)],
		&"rotate_ccw": [_boton_mouse(MOUSE_BUTTON_WHEEL_DOWN)],
		&"inventory": [_tecla(KEY_TAB)],
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


func _nombrar_capas() -> void:
	for i: int in CAPAS_FISICAS_3D.size():
		# Con nombre, el inspector muestra "mundo" en vez de "Layer 1".
		ProjectSettings.set_setting("layer_names/3d_physics/layer_%d" % (i + 1), CAPAS_FISICAS_3D[i])


# Releemos la configuración guardada para confirmar que quedó cargada de verdad.
func _verificar_acciones(acciones: Dictionary) -> void:
	InputMap.load_from_project_settings()
	for nombre: StringName in acciones:
		if not InputMap.has_action(nombre) or InputMap.action_get_events(nombre).is_empty():
			push_warning("Falta la acción: %s" % nombre)


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
