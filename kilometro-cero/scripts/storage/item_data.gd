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

@export var id: StringName
@export var display_name: String
@export var size_class: SizeClass = SizeClass.SMALL
@export_range(0.0, 1000.0, 0.01, "suffix:kg") var unit_weight: float = 1.0
@export var hands: HandsRequired = HandsRequired.ONE
## Etiquetas para las reglas de compatibilidad (por ejemplo &"chemical", &"food").
@export var tags: Array[StringName] = []
@export var base_value: float = 0.0
## Cómo se ve el objeto suelto en el mundo (tarea 13).
@export var scene: PackedScene
@export var icon: Texture2D
