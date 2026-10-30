class_name DayLook
extends Resource
## Cómo se ve cada hora del día (tarea 62c.3e, D140; adelanta la parte visual de la 65): una lista
## de momentos (DayLookKey) que LookDirector mezcla según el reloj del juego. Se edita en el
## inspector: data/look/dia_pampa.tres.

@export var keys: Array[DayLookKey] = []


## Lógica pura: el aspecto a esa hora, mezclando los dos momentos que la rodean (da la vuelta por
## la medianoche). Sin momentos devuelve uno por defecto.
func sample(hour: float) -> DayLookKey:
	var sorted: Array[DayLookKey] = []
	for key: DayLookKey in keys:
		if key != null:
			sorted.append(key)
	if sorted.is_empty():
		return DayLookKey.new()
	sorted.sort_custom(func(a: DayLookKey, b: DayLookKey) -> bool: return a.hour < b.hour)
	var now: float = fposmod(hour, 24.0)
	var after_index: int = 0
	while after_index < sorted.size() and sorted[after_index].hour <= now:
		after_index += 1
	var before: DayLookKey = sorted[(after_index - 1 + sorted.size()) % sorted.size()]
	var after: DayLookKey = sorted[after_index % sorted.size()]
	var span: float = fposmod(after.hour - before.hour, 24.0)
	if span <= 0.0:
		return DayLookKey.blend(before, before, 0.0)
	var t: float = fposmod(now - before.hour, 24.0) / span
	var mixed: DayLookKey = DayLookKey.blend(before, after, t)
	mixed.hour = now
	return mixed
