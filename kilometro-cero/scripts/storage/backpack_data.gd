class_name BackpackData
extends ItemData
## Una mochila: un objeto (ItemData) que además define sus ranuras (D70, D86).
## Cada ranura apila un solo tipo de objeto; acepta pequeños y medianos, nunca grandes.
## Sin peso. Como es un ItemData, se puede guardar y soltar como cualquier objeto.
## Es una definición compartida: el contenido vive en el Inventory que se arma con ella.

## Cuántas ranuras tiene.
@export_range(1, 60, 1) var slot_count: int = 20
## Tope de cada pila de objetos pequeños.
@export_range(1, 999, 1) var small_stack_limit: int = 99
## Tope de cada pila de objetos medianos.
@export_range(1, 999, 1) var medium_stack_limit: int = 50

@export_group("Alertas")
## Fracción de ranuras ocupadas desde la que avisa "casi llena" (D59). Al 100 % avisa "llena".
@export_range(0.05, 0.99, 0.01) var almost_full_ratio: float = 0.75


## Cuántas unidades de un tamaño entran en una ranura. 0 = no entra (los grandes, D86).
func stack_limit(size: ItemData.SizeClass) -> int:
	match size:
		ItemData.SizeClass.SMALL:
			return small_stack_limit
		ItemData.SizeClass.MEDIUM:
			return medium_stack_limit
		_:
			return 0
