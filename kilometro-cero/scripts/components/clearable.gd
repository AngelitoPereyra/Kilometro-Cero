class_name Clearable
extends ToolTarget
## Obstáculo que se despeja con una herramienta clave (tarea 55, D78 y D83): un árbol caído
## con el hacha, una piedra con la barreta. Hijo del obstáculo. Al despejarse suelta lo que
## deja (el árbol caído, troncos) y desaparece: si el padre es un Obstacle, este lo borra y
## libera el tramo; si no, se borra el padre.


func get_action_name() -> String:
	return "despejar"


func _on_finished() -> void:
	var obstacle := get_parent() as Obstacle
	if obstacle != null:
		obstacle.clear()
	elif get_parent() != null:
		get_parent().queue_free()
