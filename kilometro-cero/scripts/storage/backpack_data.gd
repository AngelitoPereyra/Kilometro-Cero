class_name BackpackData
extends ItemData
## Una mochila: un objeto (ItemData) que además define sus zonas de almacenamiento.
## Sin peso (D86): pasa a ranuras en la tarea 48. Como es un ItemData, se puede guardar, soltar y
## pesar como cualquier objeto. Es una definición compartida: el contenido vive en el
## StorageContainer que se arma con su `layout`.

## Cómo se divide la mochila. La de la beta: 4 zonas chicas y 1 mediana.
@export var layout: StorageLayout
