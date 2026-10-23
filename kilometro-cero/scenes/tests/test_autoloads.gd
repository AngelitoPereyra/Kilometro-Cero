extends Node
## Prueba de la tarea 5: los tres autoloads existen y el bus entrega señales.

var _fallos: int = 0
var _recibido: bool = false
var _valor_recibido: float = 0.0


func _ready() -> void:
	_comprobar(has_node("/root/EventBus"), "EventBus está registrado")
	_comprobar(has_node("/root/GameState"), "GameState está registrado")
	_comprobar(has_node("/root/SaveSystem"), "SaveSystem está registrado")

	# Si el bus entrega una señal con sus argumentos, el cableado funciona.
	EventBus.time_advanced.connect(_al_avanzar_el_tiempo)
	EventBus.time_advanced.emit(42.0)
	_comprobar(_recibido and is_equal_approx(_valor_recibido, 42.0), "time_advanced llega con su valor")
	EventBus.time_advanced.disconnect(_al_avanzar_el_tiempo)

	if _fallos == 0:
		print("Tarea 5: todas las comprobaciones pasaron.")
	else:
		push_error("Tarea 5: fallaron %d comprobaciones." % _fallos)


func _al_avanzar_el_tiempo(hours: float) -> void:
	_recibido = true
	_valor_recibido = hours


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
