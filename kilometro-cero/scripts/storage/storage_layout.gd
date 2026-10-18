class_name StorageLayout
extends Resource
## Cómo está dividido un contenedor en zonas. Ejemplo, la mochila de la beta: una línea
## de 4 zonas chicas y otra de 1 zona mediana. Una zona = una pila de un solo tipo.

@export var zones: Array[ZoneSpec] = []


func get_zone_count() -> int:
	var total: int = 0
	for spec: ZoneSpec in zones:
		if spec != null:
			total += spec.count
	return total
