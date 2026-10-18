class_name StorageConfig
extends Resource
## Reglas del almacenamiento, en datos para balancear sin tocar código (D23).
## Cuando lleguen las zonas de pasajeros y líquidos, se suma su capacidad acá.

@export_group("Capacidad de cada pila")
@export_range(1, 999) var small_stack_capacity: int = 50
@export_range(1, 999) var medium_stack_capacity: int = 30
@export_range(1, 999) var large_stack_capacity: int = 10

@export_group("Reglas")
## Si es falso, cada zona acepta solo objetos de su tamaño. Si es verdadero, una zona
## mayor también acepta objetos menores (por ejemplo bulones en una zona mediana).
@export var allow_smaller_items_in_larger_zones: bool = false
## Pares de etiquetas que no pueden estar juntos en un mismo contenedor.
@export var tag_conflicts: Array[TagConflict] = []


## Cuántas unidades entran en la pila de una zona de ese tipo.
func stack_capacity(zone_type: ItemData.SizeClass) -> int:
	match zone_type:
		ItemData.SizeClass.SMALL:
			return small_stack_capacity
		ItemData.SizeClass.MEDIUM:
			return medium_stack_capacity
		ItemData.SizeClass.LARGE:
			return large_stack_capacity
	push_error("StorageConfig no tiene capacidad definida para el tipo de zona %d" % zone_type)
	return 1


func zone_accepts(zone_type: ItemData.SizeClass, item_size: ItemData.SizeClass) -> bool:
	if item_size == zone_type:
		return true
	# Los valores del enum van de menor a mayor tamaño (D40): alcanza con compararlos.
	return allow_smaller_items_in_larger_zones and item_size < zone_type


func tags_conflict(tags_of_one: Array[StringName], tags_of_other: Array[StringName]) -> bool:
	for conflict: TagConflict in tag_conflicts:
		if conflict != null and conflict.matches(tags_of_one, tags_of_other):
			return true
	return false
