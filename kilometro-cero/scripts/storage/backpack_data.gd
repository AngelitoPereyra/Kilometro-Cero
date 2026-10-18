class_name BackpackData
extends ItemData
## Una mochila: un objeto (ItemData) que además define sus zonas de almacenamiento y cuánta
## capacidad de peso extra permite cargar. Como es un ItemData, se puede guardar, soltar y
## pesar como cualquier objeto. Es una definición compartida: el contenido vive en el
## StorageContainer que se arma con su `layout`.

## Cómo se divide la mochila. La de la beta: 4 zonas chicas y 1 mediana.
@export var layout: StorageLayout
## Kilos que suma a la capacidad de carga de quien la lleva equipada.
@export_range(0.0, 200.0, 0.5, "suffix:kg") var weight_capacity_bonus: float = 0.0
