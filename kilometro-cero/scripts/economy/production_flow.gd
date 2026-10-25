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


func _init(new_from: StringName = &"", new_to: StringName = &"", new_item: StringName = &"", new_amount: int = 0) -> void:
	from_station = new_from
	to_station = new_to
	item_id = new_item
	amount = new_amount


## "10 log de maderera a pueblo" (para pruebas y avisos).
func describe() -> String:
	return "%d %s de %s a %s" % [amount, item_id, from_station, to_station]


## Para el guardado (tarea 65).
func to_dict() -> Dictionary:
	return {
		"id": id,
		"from": String(from_station),
		"to": String(to_station),
		"item": String(item_id),
		"amount": amount,
	}


static func from_dict(values: Dictionary) -> ProductionFlow:
	var flow := ProductionFlow.new(
		StringName(values.get("from", "")), StringName(values.get("to", "")),
		StringName(values.get("item", "")), int(values.get("amount", 0)))
	flow.id = int(values.get("id", 0))
	return flow
