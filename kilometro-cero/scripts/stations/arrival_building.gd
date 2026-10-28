class_name ArrivalBuilding
extends Node3D
## Un edificio que abre cuando llega un especialista (D103, tarea 60b): por ejemplo la escuela
## del pueblo cuando llega la maestra. Va dentro de una Station (normalmente en
## Niveles/NivelN). En el editor se ve siempre, para acomodarlo; jugando aparece cuando la
## estación tiene un flujo de `item_id` (la principal del especialista se cumplió) y brota como
## en el festejo. Al cargar una partida con el flujo ya hecho, aparece quieto. Desde la tarea
## 62 también abre si el especialista llegó con una secundaria (MissionBoard.has_delivered).

signal opened

## El pasajero que lo abre (&"teacher": la maestra).
@export var item_id: StringName = &"teacher"

## Cada cuánto (s) revisa si llegó.
const REFRESH_TIME: float = 0.5

var _station: Station
var _timer: float = 0.0
var _open: bool = false


func _ready() -> void:
	var node: Node = get_parent()
	while node != null and not node is Station:
		node = node.get_parent()
	_station = node as Station
	if _station == null:
		push_warning("ArrivalBuilding %s: no está dentro de una Station." % name)
		return
	_open = has_arrived()
	visible = _open


func _process(delta: float) -> void:
	if _station == null or _open:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH_TIME
	if has_arrived():
		_open = true
		visible = true
		GrowthCelebration.pop(self)
		opened.emit()


func is_open() -> bool:
	return _open


## Si a la estación ya le llega `item_id` por un flujo o, desde la tarea 62, si llegó con una
## secundaria cumplida (la maestra de Azul).
func has_arrived() -> bool:
	if _station == null:
		return false
	var station_id: StringName = _station.get_station_id()
	if GameState.production.get_committed_supply(station_id).get(item_id, 0) > 0:
		return true
	return GameState.missions != null and GameState.missions.has_delivered(station_id, item_id)
