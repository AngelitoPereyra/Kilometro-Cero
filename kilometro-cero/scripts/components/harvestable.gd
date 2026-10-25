class_name Harvestable
extends ToolTarget
## Algo que se recolecta con una herramienta clave (tarea 55, D83): un árbol que se tala con
## el hacha y deja troncos (el mismo tronco que en una estación de carga). Hijo del cuerpo que
## se ve (por ejemplo, un StaticBody3D). Al talarlo, el cuerpo se esconde y deja de chocar;
## con `regrow_hours` mayor que 0 vuelve a aparecer después de ese tiempo de juego.

## Horas de juego hasta que vuelve a crecer. 0: no vuelve.
@export_range(0.0, 240.0, 1.0, "suffix:h") var regrow_hours: float = 24.0

var _hours_since_harvest: float = 0.0
# Capas del cuerpo antes de esconderlo, para devolvérselas al crecer.
var _saved_layer: int = 0


func get_action_name() -> String:
	return "talar"


func _ready() -> void:
	super()
	EventBus.time_advanced.connect(_on_time_advanced)


## true si está talado y esperando volver a crecer.
func is_depleted() -> bool:
	return is_done(hits_done, hits_required)


## Cuántas horas de juego le faltan para volver (0 si no está talado; INF si no vuelve).
func get_hours_to_regrow() -> float:
	if not is_depleted():
		return 0.0
	if regrow_hours <= 0.0:
		return INF
	return maxf(regrow_hours - _hours_since_harvest, 0.0)


## Lo vuelve a mostrar entero (también lo llama el paso del tiempo).
func regrow() -> void:
	if not is_depleted():
		return
	reset_hits()
	_hours_since_harvest = 0.0
	_set_body_present(true)


func _on_finished() -> void:
	_hours_since_harvest = 0.0
	_set_body_present(false)


func _on_time_advanced(hours: float) -> void:
	if not is_depleted() or regrow_hours <= 0.0:
		return
	_hours_since_harvest += hours
	if _hours_since_harvest >= regrow_hours:
		regrow()


# Esconde o muestra el cuerpo. No se desactiva el nodo (process_mode) porque este componente
# es hijo suyo y tiene que seguir contando las horas.
func _set_body_present(present: bool) -> void:
	var body: Node3D = get_body()
	if body == null:
		return
	body.visible = present
	var collider := body as CollisionObject3D
	if collider == null:
		return
	if present:
		collider.collision_layer = _saved_layer
	else:
		_saved_layer = collider.collision_layer
		collider.collision_layer = 0
