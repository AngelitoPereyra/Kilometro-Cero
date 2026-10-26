class_name NightLight
extends OmniLight3D
## Luz que se prende de noche (D79, tarea 60): faroles y ventanas de los pueblos. Mira la hora
## de GameState.clock con cada EventBus.time_advanced. Si tiene `glow_mesh`, también le prende
## la emisión (el vidrio del farol brilla). El cielo de noche llega con la tarea 65; hasta
## entonces se nota en la escena de prueba, que oscurece el sol.
## Dentro de "Niveles/NivelN" de una estación, solo alumbra desde ese nivel.

## Se prendió (true) o se apagó (false).
signal switched(lit: bool)

## Hora a la que se prende y a la que se apaga (0 a 24; puede cruzar la medianoche).
@export_range(0.0, 24.0, 0.25) var on_hour: float = 19.0
@export_range(0.0, 24.0, 0.25) var off_hour: float = 6.5
## Malla cuyo material (material_override, StandardMaterial3D) brilla con la luz prendida.
@export var glow_mesh: NodePath

var _lit: bool = false
var _glow_material: StandardMaterial3D


## Lógica pura: si a esa hora la luz va prendida (de `on` a `off`, también cruzando las 0).
static func is_night_at(hour: float, on: float, off: float) -> bool:
	if is_equal_approx(on, off):
		return false
	if on > off:
		return hour >= on or hour < off
	return hour >= on and hour < off


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var glow := get_node_or_null(glow_mesh) as MeshInstance3D
	if glow != null and glow.material_override is StandardMaterial3D:
		# Copia propia: cada farol se prende por su cuenta.
		_glow_material = glow.material_override.duplicate()
		glow.material_override = _glow_material
	EventBus.time_advanced.connect(func(_hours: float) -> void: refresh())
	_apply(is_night_at(GameState.clock.time_of_day, on_hour, off_hour))


## Mira la hora otra vez (por ejemplo, después de mover el reloj a mano).
func refresh() -> void:
	var night: bool = is_night_at(GameState.clock.time_of_day, on_hour, off_hour)
	if night != _lit:
		_apply(night)


func is_lit() -> bool:
	return _lit


func _apply(value: bool) -> void:
	_lit = value
	visible = value
	if _glow_material != null:
		_glow_material.emission_enabled = value
	switched.emit(value)
