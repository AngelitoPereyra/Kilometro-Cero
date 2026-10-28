class_name ProductionFlow
extends RefCounted
## Un flujo permanente (D79, D80, tarea 57): `amount` unidades por día de `item_id` que salen
## de la producción de `from_station` hacia `to_station`. Lo crea el ProductionModel (desde la
## tarea 58, al cumplir una misión de entrega) y lo va a mostrar un tren automático (tarea 61).
## Sale solo de lo que produce la estación de origen: no reenvía lo que ella recibe.

## Identificador dentro del modelo (crece con cada flujo nuevo: el más viejo tiene el menor).
var id: int = 0
var from_station: StringName
var to_station: StringName
var item_id: StringName
## Unidades por día que se comprometen.
var amount: int = 0
## Lo que entregó en el último día simulado (menos que `amount` si no alcanzó la producción,
## 0 si el camino estaba cortado).
var last_delivered: int = 0
## Flujo de pasajeros (tarea 60b): el tren va y vuelve con gente (a la ida los que llegan al
## pueblo; a la vuelta estudiantes y compradores hacia la ciudad). Lo usa la tarea 61.
var round_trip: bool = false
## Nombre especial del flujo y de su tren ("El Marplatense", D106); vacío: el armado por
## FlowNames. Se guarda.
var custom_name: String = ""
## Recién nacido (tarea 62.4, D120): empieza el día siguiente. Mientras tanto ya compromete la
## producción y el consumo (no nace otra misión por lo mismo), pero no entrega ni lleva tren.
var pending: bool = false


func _init(new_from: StringName = &"", new_to: StringName = &"", new_item: StringName = &"", new_amount: int = 0) -> void:
	from_station = new_from
	to_station = new_to
	item_id = new_item
	amount = new_amount


## "10 log de maderera a pueblo" (para pruebas y avisos).
func describe() -> String:
	var text: String = "%d %s de %s a %s" % [amount, item_id, from_station, to_station]
	if round_trip:
		text += ", ida y vuelta"
	return text + " (empieza mañana)" if pending else text


## Para el guardado (tarea 65).
func to_dict() -> Dictionary:
	return {
		"id": id,
		"from": String(from_station),
		"to": String(to_station),
		"item": String(item_id),
		"amount": amount,
		"round_trip": round_trip,
		"name": custom_name,
		"pending": pending,
	}


static func from_dict(values: Dictionary) -> ProductionFlow:
	var flow := ProductionFlow.new(
		StringName(values.get("from", "")), StringName(values.get("to", "")),
		StringName(values.get("item", "")), int(values.get("amount", 0)))
	flow.id = int(values.get("id", 0))
	flow.round_trip = bool(values.get("round_trip", false))
	flow.custom_name = String(values.get("name", ""))
	flow.pending = bool(values.get("pending", false))
	return flow
