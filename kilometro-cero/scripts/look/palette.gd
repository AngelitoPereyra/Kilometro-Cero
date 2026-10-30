@tool
class_name Palette
extends RefCounted
## Paleta compartida (tarea 62c.3e, D140): todos los modelos pintan con estos 64 colores, así todo
## combina y cambiar el clima o el estilo es cambiar una imagen. La imagen (assets/look/paleta.png,
## 8 x 8 celdas) es la que lee el shader del mundo; HEX dice qué color tiene cada nombre y sirve
## para elegir la celda más parecida a un color suelto (LookPainter repinta así los bosquejos).
## Si se cambia un color, cambiarlo en los dos lados.
## Filas: pampa, sierra y cantera, pueblo ferroviario, vía y madera, paredes, gente, flores y agua,
## luces y noche.

const TEXTURE_PATH: String = "res://assets/look/paleta.png"
const SHADER_PATH: String = "res://assets/shaders/mundo.gdshader"
const SHADER_DOUBLE_PATH: String = "res://assets/shaders/mundo_doble.gdshader"
const COLUMNS: int = 8
const NAMES: Array[StringName] = [
	&"trigo", &"rastrojo", &"alfalfa", &"pasto", &"pasto_oscuro", &"monte", &"eucalipto", &"eucalipto_sombra",
	&"cal", &"tosca", &"piedra_rosa", &"piedra", &"polvo", &"piedra_azul", &"tierra", &"barro",
	&"ladrillo", &"teja", &"cal_pared", &"chapa", &"verde_estacion", &"verde_oscuro", &"bordo", &"bordo_oscuro",
	&"hierro", &"riel", &"balasto", &"durmiente", &"madera", &"madera_clara", &"oxido", &"carbon",
	&"rosa_pared", &"celeste_pared", &"amarillo_pared", &"crema", &"ocre", &"mostaza", &"blanco", &"gris_claro",
	&"piel_clara", &"piel_media", &"piel_morena", &"pelo", &"ropa_azul", &"ropa_roja", &"ropa_verde", &"ropa_gris",
	&"cardo", &"flor_amarilla", &"flor_blanca", &"sauce", &"mata", &"agua", &"agua_clara", &"cielo",
	&"ambar", &"naranja", &"rojo_senal", &"amarillo_senal", &"noche", &"azul_noche", &"vidrio", &"humo",
]
const HEX: Array[String] = [
	"d9b45a", "c9a64d", "a9c26a", "7fa65a", "6f9a4e", "3f6b45", "4d7d4a", "335a45",
	"f1ece0", "d8c7a4", "b88c6a", "b9b4a8", "8a8f9b", "5f6f86", "9a7a55", "6e5640",
	"b65a3c", "9c4a35", "f3efe6", "9aa3a6", "2f6b4f", "1f4a37", "7a2e34", "5e2229",
	"3a3f47", "5b6068", "a59b8c", "6b4f3a", "8a6a4a", "b08d62", "8a4a2a", "26292e",
	"e6b8a8", "a9cbd6", "e9d49a", "e8dcc0", "c48a3a", "d9a441", "f7f5ef", "c9ccd0",
	"e8c4a0", "c99670", "9a6644", "3b2a22", "4f6d8f", "a84438", "6a8a5a", "7e848c",
	"8e5a9e", "f0cf4a", "f4f1e8", "8fb05a", "5a7a3e", "5f8fa8", "8fb8c8", "8fc4e3",
	"ffc66b", "ff9a3d", "c8423a", "e8c547", "1d2a4a", "34507a", "3d5466", "f2f2f0",
]
## Variables globales de shader que pide el material (se declaran en project.godot, sección
## shader_globals; si faltan, ensure_globals las agrega mientras corre).
const GLOBALS: Dictionary = {
	&"vitality_map": RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D,
	&"vitality_map_prev": RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D,
	&"vitality_mix": RenderingServer.GLOBAL_VAR_TYPE_FLOAT,
	&"vitality_rect": RenderingServer.GLOBAL_VAR_TYPE_VEC4,
	&"vitality_enabled": RenderingServer.GLOBAL_VAR_TYPE_FLOAT,
}

static var _colors: PackedColorArray = PackedColorArray()
static var _globals_checked: bool = false
# Materiales ya armados, por clave (el mismo color y las mismas opciones dan el mismo material).
static var _materials: Dictionary[String, ShaderMaterial] = {}


static func size() -> int:
	return NAMES.size()


## La celda de ese nombre; -1 si no existe.
static func index_of(swatch: StringName) -> int:
	return NAMES.find(swatch)


static func color_at(index: int) -> Color:
	_load_colors()
	return _colors[clampi(index, 0, _colors.size() - 1)]


static func color(swatch: StringName) -> Color:
	var index: int = index_of(swatch)
	if index < 0:
		push_warning("Palette: no hay un color \"%s\"." % swatch)
		return Color.MAGENTA
	return color_at(index)


## Lógica pura: la celda cuyo color se parece más (distancia "redmean", que pesa el rojo y el azul
## según cuán rojo es el color, cerca de cómo lo ve el ojo).
static func nearest(target: Color) -> int:
	_load_colors()
	var best: int = 0
	var best_distance: float = INF
	for index: int in _colors.size():
		var candidate: Color = _colors[index]
		var red_mean: float = (candidate.r + target.r) * 0.5
		var dr: float = candidate.r - target.r
		var dg: float = candidate.g - target.g
		var db: float = candidate.b - target.b
		var distance: float = (2.0 + red_mean) * dr * dr + 4.0 * dg * dg + (3.0 - red_mean) * db * db
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


## Material de un color de la paleta. Lo comparten todos los que piden lo mismo.
static func material(swatch: StringName, double_sided: bool = false) -> ShaderMaterial:
	return material_at(maxi(index_of(swatch), 0), double_sided)


static func material_at(index: int, double_sided: bool = false, options: Dictionary = {}) -> ShaderMaterial:
	var key: String = "%d|%s|%s" % [index, double_sided, options]
	if _materials.has(key):
		return _materials[key]
	var made: ShaderMaterial = _make(double_sided)
	made.set_shader_parameter(&"swatch", index)
	for parameter: StringName in options:
		made.set_shader_parameter(parameter, options[parameter])
	_materials[key] = made
	return made


## Material de la celda más parecida a ese color.
static func material_for(target: Color, double_sided: bool = false) -> ShaderMaterial:
	return material_at(nearest(target), double_sided)


## Material con viento (pasto y árboles): la punta se mueve `wind` metros; lo de abajo de
## `wind_height` se mueve menos. Con `tip` el color pasa de `swatch` a `tip` hasta `tip_height`.
static func wind_material(swatch: StringName, wind: float, wind_height: float, tip: StringName = &"", tip_height: float = 0.0, double_sided: bool = false) -> ShaderMaterial:
	var options: Dictionary = {&"wind": wind, &"wind_height": wind_height}
	if tip != &"":
		options[&"swatch_alt"] = maxi(index_of(tip), 0)
		options[&"alt_height"] = tip_height
	return material_at(maxi(index_of(swatch), 0), double_sided, options)


## Material de un personaje: siempre con todo su color (la gente es la vida, no se empolva, D141).
static func figure_material(swatch: StringName) -> ShaderMaterial:
	return material_at(maxi(index_of(swatch), 0), false, {&"vitality_override": 1.0})


## Material que pinta con el color de cada vértice (en sRGB, como los de HEX). Compartido.
static func vertex_material(double_sided: bool = true) -> ShaderMaterial:
	var key: String = "vertex|%s" % double_sided
	if not _materials.has(key):
		var made: ShaderMaterial = _make(double_sided)
		made.set_shader_parameter(&"color_mode", 1)
		_materials[key] = made
	return _materials[key]


## Material propio (no compartido) que mezcla dos colores según el rojo de cada vértice, para
## lo que cambia de color con la hora (el horizonte). Sin vitalidad.
static func tint_material(double_sided: bool = true) -> ShaderMaterial:
	var made: ShaderMaterial = _make(double_sided)
	made.set_shader_parameter(&"color_mode", 2)
	made.set_shader_parameter(&"vitality_override", 1.0)
	return made


## Un material propio de un color, para cambiarle parámetros sin tocar a los demás.
static func unique_material(swatch: StringName, double_sided: bool = false) -> ShaderMaterial:
	var made: ShaderMaterial = _make(double_sided)
	made.set_shader_parameter(&"swatch", maxi(index_of(swatch), 0))
	return made


## Agrega las variables globales que pide el shader si el proyecto todavía no las tiene (las
## declara project.godot; setup_project.gd las vuelve a poner).
static func ensure_globals() -> void:
	if _globals_checked:
		return
	_globals_checked = true
	for global_name: StringName in GLOBALS:
		if ProjectSettings.has_setting("shader_globals/%s" % global_name):
			continue
		var default_value: Variant = 0.0
		match GLOBALS[global_name]:
			RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D:
				default_value = null
			RenderingServer.GLOBAL_VAR_TYPE_VEC4:
				default_value = Vector4(0.0, 0.0, 1.0, 1.0)
		RenderingServer.global_shader_parameter_add(global_name, GLOBALS[global_name], default_value)


static func _make(double_sided: bool) -> ShaderMaterial:
	ensure_globals()
	var made := ShaderMaterial.new()
	made.shader = load(SHADER_DOUBLE_PATH if double_sided else SHADER_PATH) as Shader
	made.set_shader_parameter(&"palette", load(TEXTURE_PATH) as Texture2D)
	return made


static func _load_colors() -> void:
	if not _colors.is_empty():
		return
	for code: String in HEX:
		_colors.append(Color.html(code))
