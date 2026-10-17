@tool
class_name TrackSegment
extends Node
## Tramo de vía: guarda su condición, de 0.0 (rota) a 1.0 (perfecta).
## Por ahora es un dato con una señal. En la tarea 20, RailNetwork va a calcular
## `target_condition` según las estaciones cercanas y acercar `condition` de a poco.
## Es @tool para que el cambio de condición se note en el editor al mover el slider.

## Se emite solo cuando la condición cambia de verdad.
signal condition_changed(condition: float)

@export_range(0.0, 1.0, 0.01) var condition: float = 0.2:
	set(value):
		# Limitar acá evita que cualquier sistema deje un valor fuera de rango.
		var clamped: float = clampf(value, 0.0, 1.0)
		if is_equal_approx(clamped, condition):
			return
		condition = clamped
		condition_changed.emit(condition)

## Hacia dónde tiende la condición. Lo escribe RailNetwork (tarea 20).
var target_condition: float = 0.2


## Desgaste visual: 0.0 sano, 1.0 destruido. Es el parámetro que recibe el material.
func get_wear() -> float:
	return 1.0 - condition
