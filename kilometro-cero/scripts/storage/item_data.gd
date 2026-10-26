class_name ItemData
extends Resource
## Definición de un tipo de objeto (bulón, durmiente, riel, hacha...). Es una definición
## compartida: NO guarda estado (cantidad, durabilidad). Eso vive en ItemStack (D33).
## Los enums están acá y los usa también el almacenamiento: un solo SizeClass para
## objetos y zonas (D40). Se escribe ItemData.SizeClass.SMALL.

## Tamaño del objeto. El orden importa: va de menor a mayor.
enum SizeClass { SMALL, MEDIUM, LARGE }
## Cuántas manos necesita para levantarlo. CRANE: solo con vagón grúa (a futuro).
enum HandsRequired { ONE, TWO, CRANE }

## Etiqueta de los pasajeros (tarea 60b): solo viajan en coches de pasajeros. Nunca van a la
## mano, a la mochila ni a una grúa.
const PASSENGER_TAG: StringName = &"passenger"
## Etiqueta de los pasajeros especialistas (maestra, médico): la primera carga de su misión es
## uno solo (D103).
const SPECIALIST_TAG: StringName = &"specialist"

@export var id: StringName
@export var display_name: String
@export var size_class: SizeClass = SizeClass.SMALL
@export_range(0.0, 1000.0, 0.01, "suffix:kg") var unit_weight: float = 1.0
@export var hands: HandsRequired = HandsRequired.ONE
## Etiquetas para las reglas de compatibilidad (por ejemplo &"chemical", &"food").
@export var tags: Array[StringName] = []
@export var base_value: float = 0.0
## Cómo se nombra como carga de un tren ("troncos", "piedra"; tarea 61, D106). Vacío: su nombre.
@export var cargo_name: String = ""
## Cómo se ve el objeto suelto en el mundo (tarea 13).
@export var scene: PackedScene
@export var icon: Texture2D


## Si es un pasajero (tarea 60b). Sirve con null.
static func is_passenger(item: ItemData) -> bool:
	return item != null and item.tags.has(PASSENGER_TAG)


## Si es un pasajero especialista (tarea 60b). Sirve con null.
static func is_specialist(item: ItemData) -> bool:
	return item != null and item.tags.has(SPECIALIST_TAG)
