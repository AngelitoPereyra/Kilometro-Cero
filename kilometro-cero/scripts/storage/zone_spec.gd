class_name ZoneSpec
extends Resource
## "N zonas de este tamaño": una línea de un StorageLayout.

@export var size_class: ItemData.SizeClass = ItemData.SizeClass.SMALL
@export_range(1, 50) var count: int = 1


func _init(zone_size: ItemData.SizeClass = ItemData.SizeClass.SMALL, amount: int = 1) -> void:
	size_class = zone_size
	count = amount
