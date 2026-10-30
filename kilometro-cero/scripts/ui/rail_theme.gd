class_name RailTheme
extends RefCounted
## Tema de interfaz de cartel ferroviario (tarea 62c.3e, D141; adelanta parte de la 67): los
## carteles esmaltados de Ferrocarriles Argentinos de época. Verde estación, bordó y crema (los de
## Palette), con letra de boletería: Bahnschrift (la DIN de Windows), o la condensada que haya.
## Lo usan los carteles de pantalla del Hito A (variación CARTEL de Label), la cabina (CabHud),
## el TAB y el mercado (InventoryUI.make_theme) y el tablero de cada estación (StationBoard).

## Variación de Label para los carteles de pantalla: fondo verde, filete crema y letra crema.
const CARTEL: StringName = &"CartelFerroviario"
const GREEN: Color = Color(0.184, 0.420, 0.310)
const GREEN_DARK: Color = Color(0.122, 0.290, 0.216)
const BORDO: Color = Color(0.478, 0.180, 0.204)
const CREAM: Color = Color(0.953, 0.937, 0.902)
const CREAM_DARK: Color = Color(0.910, 0.863, 0.753)
const CREAM_HOVER: Color = Color(0.930, 0.900, 0.830)
const INK: Color = Color(0.149, 0.161, 0.180)
const FONT_NAMES: PackedStringArray = ["Bahnschrift", "DIN Condensed", "DIN Alternate", "Roboto Condensed", "Arial Narrow", "sans-serif"]
const FONT_SIZE: int = 18

static var _theme: Theme
static var _font: SystemFont
static var _bold: SystemFont


## El tema, armado una sola vez y compartido.
static func get_theme() -> Theme:
	if _theme == null:
		_theme = build()
	return _theme


## La letra de los carteles (semicondensada y un poco gruesa).
static func sign_font(bold: bool = false) -> Font:
	if _font == null:
		_font = _make_font(600)
		_bold = _make_font(800)
	return _bold if bold else _font


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = sign_font()
	theme.default_font_size = FONT_SIZE
	# Ventanas (TAB, mercado): crema con marco bordó.
	theme.set_stylebox(&"panel", &"PanelContainer", sign_box(CREAM, BORDO, 8, 3, 6.0))
	theme.set_stylebox(&"panel", &"TabContainer", sign_box(CREAM, GREEN, 4, 2, 6.0))
	theme.set_stylebox(&"tab_selected", &"TabContainer", sign_box(GREEN, GREEN_DARK, 4, 2, 6.0))
	theme.set_stylebox(&"tab_unselected", &"TabContainer", sign_box(CREAM_DARK, GREEN, 4, 1, 6.0))
	theme.set_stylebox(&"tab_hovered", &"TabContainer", sign_box(CREAM_HOVER, GREEN, 4, 1, 6.0))
	theme.set_color(&"font_selected_color", &"TabContainer", CREAM)
	theme.set_color(&"font_unselected_color", &"TabContainer", INK)
	theme.set_color(&"font_hovered_color", &"TabContainer", INK)
	theme.set_color(&"font_color", &"Label", INK)
	theme.set_color(&"default_color", &"RichTextLabel", INK)
	theme.set_font(&"bold_font", &"RichTextLabel", sign_font(true))
	# Botones: verde con letra crema; bordó al pasar por encima.
	theme.set_stylebox(&"normal", &"Button", sign_box(GREEN, GREEN_DARK, 4, 2, 6.0))
	theme.set_stylebox(&"hover", &"Button", sign_box(BORDO, GREEN_DARK, 4, 2, 6.0))
	theme.set_stylebox(&"pressed", &"Button", sign_box(GREEN_DARK, GREEN_DARK, 4, 2, 6.0))
	theme.set_stylebox(&"disabled", &"Button", sign_box(CREAM_DARK, CREAM_DARK, 4, 2, 6.0))
	theme.set_stylebox(&"focus", &"Button", StyleBoxEmpty.new())
	for color_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
		theme.set_color(color_name, &"Button", CREAM)
	theme.set_color(&"font_disabled_color", &"Button", Color(INK, 0.5))
	# Carteles de pantalla: el esmaltado verde con filete crema.
	theme.set_type_variation(CARTEL, &"Label")
	var cartel: StyleBoxFlat = sign_box(Color(GREEN, 0.93), CREAM, 6, 2, 10.0)
	cartel.content_margin_top = 6.0
	cartel.content_margin_bottom = 6.0
	cartel.shadow_color = Color(0.0, 0.0, 0.0, 0.3)
	cartel.shadow_size = 4
	theme.set_stylebox(&"normal", CARTEL, cartel)
	theme.set_color(&"font_color", CARTEL, CREAM)
	theme.set_constant(&"outline_size", CARTEL, 0)
	return theme


static func sign_box(fill: Color, border: Color, radius: int, border_width: int, margin: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	return box


## Le pone a un cartel de pantalla el tema y la variación de cartel.
static func style_label(label: Label, font_size: int = 0) -> void:
	label.theme = get_theme()
	label.theme_type_variation = CARTEL
	if font_size > 0:
		label.add_theme_font_size_override(&"font_size", font_size)


## Le pone a un cartel 3D (Label3D sobre un tablero verde) la letra y el color de cartel.
static func style_label_3d(label: Label3D) -> void:
	label.font = sign_font()
	label.modulate = CREAM
	label.outline_modulate = GREEN_DARK


static func _make_font(weight: int) -> SystemFont:
	var font := SystemFont.new()
	font.font_names = FONT_NAMES
	font.font_weight = weight
	font.font_stretch = 87
	return font
