class_name Coupler
extends Interactable
## El enganche de la cola de un vehículo (tarea 61b, D113, pendiente de la 53): con el tren quieto
## y algo acoplado atrás, F lo desacopla. Para acoplar alcanza con tocar el otro vehículo con la
## cola, como desde la 53. Lo crea cada Vehicle; en los automáticos no se ve.

## Por debajo de esta velocidad (m/s) el tren cuenta como quieto.
const STOP_SPEED: float = 0.1


func _ready() -> void:
	reach = 2.5


func get_vehicle() -> Vehicle:
	return get_parent() as Vehicle


func can_interact(player: Player) -> bool:
	var vehicle: Vehicle = get_vehicle()
	return vehicle != null and vehicle.rear != null and not vehicle.automatic \
			and absf(vehicle.get_head().speed) < STOP_SPEED and super.can_interact(player)


func get_prompt() -> String:
	return "Desacoplar"


func _on_interact(_player: Player) -> void:
	get_vehicle().uncouple_rear()
