class_name WagonData
extends VehicleData
## Definición de un tipo de vagón (D85): qué carga lleva y cuánta. Un vagón es un vehículo
## más (largo, velocidad máxima), así que extiende VehicleData. Igual que VehicleData, es
## una definición compartida: lo que lleva cargado vive en el StorageContainer del Wagon.

## Tipo de carga. Solo informa (interfaz, misiones); lo que entra lo decide `accepted_tags`.
enum CargoType { FLATCAR, HOPPER, BOXCAR, TANK, PASSENGER }

const CARGO_TYPE_NAMES: Array[String] = ["plataforma", "tolva", "cerrado", "tanque", "pasajeros"]

@export var cargo_type: CargoType = CargoType.FLATCAR
## Unidades de carga que entran, sumando todo lo que lleve.
@export_range(1, 9999) var capacity: int = 20
## Solo entra lo que tenga al menos una de estas etiquetas (ItemData.tags). Vacío: todo.
@export var accepted_tags: Array[StringName] = []


# Los vagones pesan menos que una locomotora, suman peso con la carga y no tiran (tarea 62c.1). Se
# ponen acá y no en cada .tres: un valor que el .tres no guarda queda con el de _init.
func _init() -> void:
	weight = 0.4
	load_weight = 0.6
	climb_power = 0.0


static func cargo_type_name(type: CargoType) -> String:
	return CARGO_TYPE_NAMES[type]
