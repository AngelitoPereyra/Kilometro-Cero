@tool
class_name ItemAmount
extends Resource
## Una cantidad de un objeto: "15 troncos". La usan los datos de las estaciones (producción y
## consumo por día, tarea 56) y la van a usar las misiones y los flujos (tareas 57 y 58).
## Es una definición: no guarda estado.

@export var item: ItemData
@export_range(1, 9999) var amount: int = 1


## Lógica pura: suma una lista de cantidades por id de objeto (las repetidas se juntan y las
## que no tienen objeto se saltean). Suma sobre `into` si se lo pasa.
static func sum_by_id(amounts: Array[ItemAmount], into: Dictionary[StringName, int] = {}) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = into.duplicate()
	for entry: ItemAmount in amounts:
		if entry == null or entry.item == null:
			continue
		result[entry.item.id] = result.get(entry.item.id, 0) + entry.amount
	return result


## "15 tronco" (para pruebas y avisos; la interfaz final arma su propio texto).
func describe() -> String:
	return "%d %s" % [amount, item.display_name if item != null else "?"]
