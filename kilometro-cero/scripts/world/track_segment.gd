@tool
class_name TrackSegment
extends Node
## Una vía de un tramo de la red (tarea 54, D78). Cuelga del Path3D de su curva: el avance 0
## está en `from_station` y el final en `to_station`. Un tramo con vía doble (D81) son dos
## Path3D con un TrackSegment cada uno y el mismo `segment_id` (normalmente uno de A a B y el
## otro de B a A); RailNetwork los trata como un solo tramo y les mantiene igual el estado.
## Guarda el estado (cortado, abierto o mejorado) y la condición, de 0.0 (rota) a 1.0
## (perfecta), que solo cambia el aspecto y la velocidad máxima.
## Es @tool para que el cambio de condición se note en el editor al mover el slider.

## Cortado: ningún tren entra. Abierto: se anda según la condición. Mejorado: se anda como
## con la vía perfecta.
enum State { CUT, OPEN, IMPROVED }

## Se emite solo cuando la condición cambia de verdad.
signal condition_changed(condition: float)
## Se emite solo cuando el estado cambia de verdad.
signal state_changed(state: State)

## Grupo de todas las vías: de acá arma RailNetwork el grafo.
const GROUP: StringName = &"track_segments"

## Identificador del tramo. Dos vías con el mismo id son la vía doble de un tramo.
@export var segment_id: StringName
## Estación al principio de la curva (avance 0).
@export var from_station: StringName
## Estación al final de la curva.
@export var to_station: StringName
@export var state: State = State.OPEN:
	set(value):
		if value == state:
			return
		state = value
		state_changed.emit(state)

@export_range(0.0, 1.0, 0.01) var condition: float = 0.2:
	set(value):
		# Limitar acá evita que cualquier sistema deje un valor fuera de rango.
		var clamped: float = clampf(value, 0.0, 1.0)
		if is_equal_approx(clamped, condition):
			return
		condition = clamped
		condition_changed.emit(condition)

## Hacia dónde tiende la condición. Lo va a escribir el modelo de los pueblos (D78).
var target_condition: float = 0.2


func _enter_tree() -> void:
	add_to_group(GROUP)


## Desgaste visual: 0.0 sano, 1.0 destruido. Es el parámetro que recibe el material.
func get_wear() -> float:
	return 1.0 - condition


## La condición con la que se calcula la velocidad: mejorado anda como vía perfecta.
func get_effective_condition() -> float:
	return 1.0 if state == State.IMPROVED else condition


func is_cut() -> bool:
	return state == State.CUT


## La curva de esta vía (el Path3D padre), o null.
func get_track_path() -> Path3D:
	return get_parent() as Path3D


## Largo de la curva en metros (0 si no tiene).
func get_length() -> float:
	var path: Path3D = get_track_path()
	if path == null or path.curve == null:
		return 0.0
	return path.curve.get_baked_length()


## La estación del otro extremo, o &"" si `station` no es un extremo de esta vía.
func other_station(station: StringName) -> StringName:
	if station == from_station:
		return to_station
	if station == to_station:
		return from_station
	return &""


static func state_name(value: State) -> String:
	match value:
		State.CUT:
			return "cortado"
		State.IMPROVED:
			return "mejorado"
	return "abierto"
