extends Node
## Prueba de la tarea 62.8: los textos de las pestañas Agenda y Tren del TAB (AgendaText), en
## lógica pura, sin jugador ni mapa.

var _fallos: int = 0


func _ready() -> void:
	_probar_carga()
	_probar_trenes()
	if _fallos == 0:
		print("Agenda: todas las comprobaciones pasaron.")
	else:
		push_error("Agenda: fallaron %d comprobaciones." % _fallos)


func _probar_carga() -> void:
	var tronco := load("res://data/items/log.tres") as ItemData
	var caja := StorageContainer.new()
	caja.configure(20, [&"log", &"stone"] as Array[StringName])
	add_child(caja)
	_comprobar(AgendaText.cargo_text(caja, null) == "", "Vacía: sin carga")
	caja.try_store(ItemStack.new(tronco, 18))
	_comprobar(AgendaText.cargo_text(caja, null) == "18 log", "18 troncos (sin tablero, por su id): %s" % AgendaText.cargo_text(caja, null))
	_comprobar(AgendaText.cargo_text(caja, GameState.missions).begins_with("18 "), "Con el tablero dice el nombre: %s" % AgendaText.cargo_text(caja, GameState.missions))
	var vacio: Array[Vehicle] = []
	_comprobar(AgendaText.train(vacio, null).contains("No encontré tu tren"), "Sin tren lo dice")
	caja.queue_free()


func _probar_trenes() -> void:
	var sin_nada: String = AgendaText.agenda(null, null, null)
	_comprobar(sin_nada.contains("Trenes automáticos") and sin_nada.contains("No hay ninguno"), "Sin automáticos lo dice")
	var run := AutoTrainRun.new()
	run.display_name = "Tren de carga de Olavarría a Azul"
	run.home = &"olavarria"
	run.away = &"azul"
	run.due = 31.0
	var renglon: String = AgendaText.run_line(null, run, 20.0)
	_comprobar(renglon.contains("Tren de carga de Olavarría a Azul") and renglon.contains("próxima salida 07:00 (mañana)"), "Parado: dice su próxima salida y si es mañana: %s" % renglon)
	run.due = 22.0
	renglon = AgendaText.run_line(null, run, 20.0)
	_comprobar(renglon.contains("próxima salida 22:00") and not renglon.contains("mañana"), "Hoy, sin 'mañana': %s" % renglon)
	var con_extra: String = AgendaText.agenda(null, null, null, PackedStringArray(["Coche de pasajeros: listo"]))
	_comprobar(con_extra.contains("• Coche de pasajeros: listo"), "Suma los renglones de la escena")


func _comprobar(ok: bool, texto: String) -> void:
	if ok:
		print("  OK  ", texto)
	else:
		_fallos += 1
		push_error("  FALLA  " + texto)
