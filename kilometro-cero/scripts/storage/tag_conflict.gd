class_name TagConflict
extends Resource
## Par de etiquetas que no pueden convivir en el mismo contenedor (por ejemplo "chemical"
## y "food"). El conflicto vale en ambos sentidos.

@export var tag_a: StringName
@export var tag_b: StringName


func _init(first: StringName = &"", second: StringName = &"") -> void:
	tag_a = first
	tag_b = second


## Si un objeto con `tags_of_one` y otro con `tags_of_other` no pueden compartir contenedor.
func matches(tags_of_one: Array[StringName], tags_of_other: Array[StringName]) -> bool:
	# Un par sin completar no declara ningún conflicto. Sin esta guarda, un TagConflict
	# vacío chocaría con cualquier objeto que tenga una etiqueta en blanco.
	if tag_a == &"" or tag_b == &"":
		return false
	return (tags_of_one.has(tag_a) and tags_of_other.has(tag_b)) \
			or (tags_of_one.has(tag_b) and tags_of_other.has(tag_a))
