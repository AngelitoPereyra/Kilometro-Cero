class_name CabHud
extends CanvasLayer
## Lo que se ve en pantalla mientras se maneja (tarea 60c, provisorio hasta la interfaz de la
## tarea 67): arriba la marcha, la velocidad, el freno, las luces y las puertas; abajo las
## teclas; en la vista de la cabina, una mira en el centro y el nombre del botón apuntado.
## La crea y la borra la Cab al ocuparse y al quedar libre. Arma sus nodos por código.
## Tarea 62c.3e: el estado y las teclas van en carteles ferroviarios (RailTheme).

var _status: Label
var _keys: Label
var _cross: Label
var _aim: Label


func _init() -> void:
	layer = 5
	_status = _make_label(Control.PRESET_CENTER_TOP, HORIZONTAL_ALIGNMENT_CENTER, 22)
	RailTheme.style_label(_status)
	_status.offset_top = 12.0
	_keys = _make_label(Control.PRESET_CENTER_BOTTOM, HORIZONTAL_ALIGNMENT_CENTER, 16)
	RailTheme.style_label(_keys)
	_keys.offset_top = -40.0
	_keys.offset_bottom = -12.0
	_cross = _make_label(Control.PRESET_CENTER, HORIZONTAL_ALIGNMENT_CENTER, 24)
	_cross.text = "+"
	_aim = _make_label(Control.PRESET_CENTER, HORIZONTAL_ALIGNMENT_CENTER, 18)
	_aim.offset_top = 22.0
	_aim.offset_bottom = 48.0


## Vuelve a escribir todo según la cabina.
func refresh(cab: Cab) -> void:
	_status.text = status_text(cab)
	_keys.text = keys_text(cab.view)
	_cross.visible = cab.view == Cab.View.CAB
	var aimed: CabButton = cab.get_aimed()
	_aim.visible = _cross.visible and aimed != null
	_aim.text = "Clic: " + aimed.get_label() if aimed != null else ""


func get_status_text() -> String:
	return _status.text


func get_keys_text() -> String:
	return _keys.text


func get_aim_text() -> String:
	return _aim.text if _aim.visible else ""


## "Adelante 2/4 · 18 km/h · Sube 4 % · Precaución: máx. 15 km/h · Freno · Luces · Puertas abiertas"
static func status_text(cab: Cab) -> String:
	var parts: PackedStringArray = [Cab.notch_text(cab.notch, cab.forward_notches, cab.reverse_notches)]
	var vehicle: Vehicle = cab.get_vehicle()
	if vehicle != null:
		parts.append("%d km/h" % roundi(absf(vehicle.speed) * 3.6))
		# Pendiente (tarea 62c.1): hacia donde va el tren; parado, hacia donde mira.
		var slope: String = grade_text(vehicle.get_grade(), vehicle.speed) if not vehicle.automatic else ""
		if not slope.is_empty():
			parts.append(slope)
		# Zona de precaución (tarea 62b.5): el tope que pisa el tren.
		var zone: SpeedZone = SpeedZone.find_for(vehicle.get_train()) if not vehicle.automatic else null
		if zone != null:
			parts.append("Precaución: máx. %d km/h" % zone.get_kmh())
	if cab.braking:
		parts.append("Freno puesto" if cab.brake_latched else "Frenando")
	if cab.lights_on:
		parts.append("Luces")
	var coaches: Array[PassengerCoach] = cab.get_coaches()
	if not coaches.is_empty():
		var open: bool = false
		for coach: PassengerCoach in coaches:
			open = open or coach.doors_open
		parts.append("Puertas abiertas" if open else "Puertas cerradas")
	return " · ".join(parts)


## "Sube 4 %" o "Baja 3 %" según `grade` (hacia donde mira el tren) y el sentido de `direction`
## (la velocidad; 0 cuenta como adelante). Vacío si no llega al 1 %.
static func grade_text(grade: float, direction: float) -> String:
	var along: float = -grade if direction < 0.0 else grade
	var percent: int = roundi(absf(along) * 100.0)
	if percent == 0:
		return ""
	return ("Sube %d %%" if along > 0.0 else "Baja %d %%") % percent


static func keys_text(view: Cab.View) -> String:
	var common: String = "W/S marcha · Espacio freno · O puertas · L luces · H bocina · F salir"
	if view == Cab.View.CAB:
		return "V: vista de afuera · Clic: apretar botón · " + common
	return "V: vista de la cabina · Mouse: girar · Rueda: acercar · " + common


func _make_label(preset: Control.LayoutPreset, align: HorizontalAlignment, size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 5)
	add_child(label)
	label.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	return label
