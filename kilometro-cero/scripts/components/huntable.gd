class_name Huntable
extends ToolTarget
## Un animal que se caza a golpes con una herramienta clave (tarea 62c.3h, D143): el jabalí con el
## machete. Hijo del animal (un Boar). Cada golpe que no lo tumba lo enoja (Boar.provoke) y al
## último suelta la carne (`drop_item`, `drop_amount`) y el animal se muere (Boar.die).


func get_action_name() -> String:
	return "cazar"


func hit() -> bool:
	var done: bool = super()
	var boar := get_body() as Boar
	if boar != null and not done and hits_done > 0:
		boar.provoke()
	return done


func _on_finished() -> void:
	var boar := get_body() as Boar
	if boar != null:
		boar.die()
	elif get_body() != null:
		get_body().queue_free()
