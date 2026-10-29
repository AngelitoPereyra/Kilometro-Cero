extends Node
## Prueba de la tarea 62.9a: la cola del punto de carga (LoadingQueue), en lógica pura, sin mapa.
## Media hora de juego llena un vagón entero; primero descarga y después carga; lo pago espera sin
## vagones y lo que se iba a descargar se anula si el vagón se fue. La bahía y el mercado se
## prueban jugando el Hito A.

var _fallos: int = 0


func _ready() -> void:
	_probar_carga()
	_probar_descarga()
	_probar_espera()
	_probar_rol()
	if _fallos == 0:
		print("Punto de carga: todas las comprobaciones pasaron.")
	else:
		push_error("Punto de carga: fallaron %d comprobaciones." % _fallos)


func _probar_carga() -> void:
	var tronco := load("res://data/items/log.tres") as ItemData
	var vagon: StorageContainer = _vagon(20)
	var cola := LoadingQueue.new()
	cola.add_load(tronco, 30)
	var cargas: Array[StorageContainer] = [vagon]
	var hecho: Dictionary = cola.work(cargas, 0.25)
	_comprobar(vagon.get_total() == 10 and hecho["loaded"] == _dic({&"log": 10}), "Un cuarto de hora carga medio vagón (10 de 20): %d" % vagon.get_total())
	cola.work(cargas, 0.25)
	_comprobar(vagon.get_total() == 20 and cola.get_loads() == _dic({&"log": 10}), "Media hora llena el vagón; faltan 10 sin lugar")
	cola.work(cargas, 2.0)
	_comprobar(vagon.get_total() == 20 and cola.get_loads() == _dic({&"log": 10}), "Lleno, el tiempo pasa sin cargar")
	var otro: StorageContainer = _vagon(20)
	cargas.append(otro)
	cola.work(cargas, 0.1)
	_comprobar(otro.get_total() == 4, "El tiempo esperando no se acumula: con otro vagón vacío, 0,1 h cargan 4: %d" % otro.get_total())
	cola.work(cargas, 1.0)
	_comprobar(otro.get_total() == 10 and not cola.has_work(), "Termina de cargar los 30")
	vagon.queue_free()
	otro.queue_free()


func _probar_descarga() -> void:
	var tronco := load("res://data/items/log.tres") as ItemData
	var piedra := load("res://data/items/limestone.tres") as ItemData
	var vagon: StorageContainer = _vagon(20)
	vagon.try_store(ItemStack.new(tronco, 20))
	var cola := LoadingQueue.new()
	cola.add_load(piedra, 20)
	cola.add_unload(&"log", 20)
	var cargas: Array[StorageContainer] = [vagon]
	_comprobar(is_equal_approx(cola.hours_left(cargas), 1.0), "Bajar 20 y subir 20 tarda una hora: %.2f" % cola.hours_left(cargas))
	var hecho: Dictionary = cola.work(cargas, 0.5)
	_comprobar(hecho["unloaded"] == _dic({&"log": 20}) and (hecho["loaded"] as Dictionary).is_empty(), "Primero descarga los 20 troncos")
	cola.work(cargas, 0.5)
	_comprobar(vagon.count_of(&"limestone") == 20 and not cola.has_work(), "Después carga las 20 piedras")
	vagon.queue_free()


func _probar_espera() -> void:
	var tronco := load("res://data/items/log.tres") as ItemData
	var cola := LoadingQueue.new()
	cola.add_load(tronco, 5)
	cola.add_unload(&"log", 3)
	var ninguno: Array[StorageContainer] = []
	cola.work(ninguno, 1.0)
	_comprobar(cola.get_loads() == _dic({&"log": 5}) and cola.get_unloads().is_empty(), "Sin vagones lo pago espera y la descarga se anula")
	_comprobar(cola.pending_load_total() == 5 and cola.hours_left(ninguno) == 0.0, "Quedan 5 esperando")


func _probar_rol() -> void:
	_comprobar(StationTrack.role_name(StationTrack.Role.BAY) == "bahía de carga", "La vía nueva se llama bahía de carga")
	_comprobar(not AutoTrains.DEFAULT_TRACK_ROLES.has(StationTrack.Role.BAY) and not AutoTrains.PASSENGER_TRACK_ROLES.has(StationTrack.Role.BAY), "Los automáticos no paran en la bahía")
	_comprobar(Market.reason_text(&"no_room").contains("bahía de carga"), "El mercado avisa que hay que estacionar en la bahía")


func _vagon(capacidad: int) -> StorageContainer:
	var caja := StorageContainer.new()
	caja.configure(capacidad, [] as Array[StringName])
	add_child(caja)
	return caja


func _dic(valores: Dictionary) -> Dictionary[StringName, int]:
	var resultado: Dictionary[StringName, int] = {}
	for clave: StringName in valores:
		resultado[clave] = valores[clave]
	return resultado


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
