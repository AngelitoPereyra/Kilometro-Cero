class_name FoodData
extends ItemData
## Algo que se come (tarea 62c.3h, D143): suma `heal` de salud. Si tiene `cooked`, el horno del vagón
## cocina lo convierte en eso (la carne cruda de jabalí pasa a carne asada). Se come con R (Eater):
## lo de la mano o, con la mano vacía, lo que más cura de la mochila.

## Salud que suma al comerlo.
@export_range(0.0, 100.0, 1.0) var heal: float = 10.0
## En qué se convierte en el horno. Vacío: no se cocina.
@export var cooked: FoodData


## true si `item` se come. Lógica pura.
static func is_food(item: ItemData) -> bool:
	return item is FoodData


## true si `item` se puede asar en el horno.
static func is_cookable(item: ItemData) -> bool:
	var food := item as FoodData
	return food != null and food.cooked != null
