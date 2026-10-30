class_name Wagon
extends Vehicle
## Vagón por tipo de carga (D85, tarea 53). Es un Vehicle con un WagonData como `data` y un
## StorageContainer hijo que guarda la carga; el vagón le copia la capacidad y las etiquetas
## aceptadas de su WagonData. Para cargar soltando dentro, al lado del contenedor va un
## StorageArea (D54); para descargar, el Grabber saca de a una unidad.
## Si tiene un nodo "Visual/Carga", lo estira en altura según lo lleno que esté.

## Cambió lo que lleva: unidades en total y capacidad.
signal cargo_changed(total: int, capacity: int)

## Nodo que muestra la carga: su escala Y va de 0 (vacío, oculto) a 1 (lleno).
const CARGO_VISUAL_PATH: NodePath = ^"Visual/Carga"

var _cargo: StorageContainer
var _cargo_visual: Node3D
# Carga de adorno de un tren automático (tarea 61); -1: se ve la carga de verdad.
var _display_units: int = -1


func _ready() -> void:
	super._ready()
	var wagon_data := data as WagonData
	if wagon_data == null:
		push_error("Wagon necesita un WagonData como data.")
		return
	_cargo = _find_cargo()
	if _cargo == null:
		push_error("Wagon necesita un StorageContainer hijo para la carga.")
		return
	_cargo.configure(wagon_data.capacity, wagon_data.accepted_tags)
	if _cargo.container_id == &"":
		_cargo.container_id = wagon_data.id
	_cargo.item_stored.connect(_on_cargo_changed)
	_cargo.item_taken.connect(_on_cargo_changed)
	_cargo_visual = get_node_or_null(CARGO_VISUAL_PATH) as Node3D
	_update_cargo_visual()


func get_wagon_data() -> WagonData:
	return data as WagonData


## El contenedor de la carga, o null si el vagón está mal armado.
func get_cargo() -> StorageContainer:
	return _cargo


## Qué tan lleno se ve, de 0.0 a 1.0 (con la carga de adorno, si tiene).
func get_fill_ratio() -> float:
	return fill_ratio(get_shown_units(), _cargo.capacity) if _cargo != null else 0.0


## Muestra `units` unidades sin cargar nada de verdad (trenes automáticos, tarea 61): el
## contenedor sigue vacío, así no se descarga ni cuenta para el tablero. -1 vuelve a mostrar
## la carga de verdad.
func set_display_load(units: int) -> void:
	_display_units = units
	_update_cargo_visual()


## Lo que se ve cargado: la carga de adorno o, si no hay, la de verdad.
func get_shown_units() -> int:
	if _display_units >= 0:
		return _display_units
	return _cargo.get_total() if _cargo != null else 0


## Peso con la carga de verdad (tarea 62c.1): la de adorno de los automáticos no pesa.
func get_weight() -> float:
	var fill: float = fill_ratio(_cargo.get_total(), _cargo.capacity) if _cargo != null else 0.0
	return data.weight + data.load_weight * fill


## Lógica pura: fracción llena, sin pasar de 1 ni dividir por 0.
static func fill_ratio(total: int, capacity: int) -> float:
	return clampf(float(total) / float(capacity), 0.0, 1.0) if capacity > 0 else 0.0


func _find_cargo() -> StorageContainer:
	for child: Node in get_children():
		var container := child as StorageContainer
		if container != null:
			return container
	return null


func _on_cargo_changed(_stack: ItemStack) -> void:
	_update_cargo_visual()
	cargo_changed.emit(_cargo.get_total(), _cargo.capacity)


func _update_cargo_visual() -> void:
	if _cargo_visual == null:
		return
	var ratio: float = get_fill_ratio()
	# Con escala 0 la base queda degenerada: vacío, simplemente se oculta.
	_cargo_visual.visible = ratio > 0.0
	if ratio > 0.0:
		_cargo_visual.scale = Vector3(1.0, ratio, 1.0)
