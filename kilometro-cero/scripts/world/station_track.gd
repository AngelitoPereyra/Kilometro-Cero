@tool
class_name StationTrack
extends TrackSegment
## Una vía de una estación (tarea 61b, D112): la principal, una de cruce, la de carga o una cola
## de maniobras. No es un tramo de la red: no tiene `segment_id` ni estaciones en las puntas; es
## de la estación que la contiene. Sus puntas se unen con los tramos de línea y con las otras vías
## de la estación por cercanía, y donde se juntan tres puntas hay un cambio (RailNetwork los arma).
## Mientras no está habilitada (una vía de ciudad que todavía no creció), no se ve y ningún cambio
## lleva a ella. Normalmente las arma StationTracks; también se puede poner a mano en un Path3D.

enum Role { MAIN, SIDING, FREIGHT, HEADSHUNT }

signal enabled_changed(enabled: bool)

## Para qué es la vía: la principal la usan los trenes que pasan; las de cruce, los que esperan.
@export var role: Role = Role.MAIN
## Nombre para los carteles ("vía principal", "vía de cruce 2"). Vacío: el del rol.
@export var display_name: String = ""
## La estación. Vacío: la del Station que la contiene.
@export var station_id: StringName
@export var enabled: bool = true:
	set(value):
		if value == enabled:
			return
		enabled = value
		_apply_enabled()
		enabled_changed.emit(enabled)


func _ready() -> void:
	_apply_enabled()


## La estación de esta vía (la propia o la del Station que la contiene), o &"".
func get_station_id() -> StringName:
	if station_id != &"":
		return station_id
	var node: Node = get_parent()
	while node != null:
		var station := node as Station
		if station != null:
			# En el editor solo se leen propiedades del recurso (puede ser un placeholder).
			return station.data.id if station.data != null else &""
		node = node.get_parent()
	return &""


func is_main() -> bool:
	return role == Role.MAIN


## Texto para los carteles: "vía principal", "vía de cruce 2", "vía de carga".
func get_label() -> String:
	return display_name if display_name != "" else role_name(role)


static func role_name(value: Role) -> String:
	match value:
		Role.SIDING:
			return "vía de cruce"
		Role.FREIGHT:
			return "vía de carga"
		Role.HEADSHUNT:
			return "cola de maniobras"
	return "vía principal"


func _apply_enabled() -> void:
	var path := get_parent() as Path3D
	if path != null:
		path.visible = enabled
