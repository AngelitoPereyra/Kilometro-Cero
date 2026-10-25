class_name KeyItems
extends Node
## Las herramientas clave que tiene el jugador (tarea 55, D83). Hijo directo de Player.
## Es un conjunto: cada herramienta se tiene o no (no hay cantidad, durabilidad ni ranura).
## Lógica pura: no conoce al EventBus; Player reemite `item_added` (patrón D52).

## Se emite solo cuando se suma una herramienta que no se tenía.
signal item_added(item: KeyItemData)
## Se emite al sumar o quitar.
signal changed

## Con qué arranca (para pruebas, o una partida que empieza con el hacha).
@export var starting_items: Array[KeyItemData] = []

# id -> KeyItemData, en el orden en que se consiguieron.
var _items: Dictionary = {}


func _ready() -> void:
	for item: KeyItemData in starting_items:
		add(item)


## Suma una herramienta. Devuelve false si ya la tenía (o si es null o no tiene id).
func add(item: KeyItemData) -> bool:
	if item == null or item.id == &"" or _items.has(item.id):
		return false
	_items[item.id] = item
	item_added.emit(item)
	changed.emit()
	return true


## Quita una herramienta (a futuro: perderla o dejarla en el galpón). False si no estaba.
func remove(tool_id: StringName) -> bool:
	if not _items.erase(tool_id):
		return false
	changed.emit()
	return true


## true si tiene la herramienta. Una acción sin herramienta (&"") siempre se puede.
func has(tool_id: StringName) -> bool:
	return tool_id == &"" or _items.has(tool_id)


func get_items() -> Array[KeyItemData]:
	var list: Array[KeyItemData] = []
	list.assign(_items.values())
	return list


func get_ids() -> Array[StringName]:
	var list: Array[StringName] = []
	list.assign(_items.keys())
	return list


func get_count() -> int:
	return _items.size()


## "hacha, barreta", o "ninguna".
func describe() -> String:
	if _items.is_empty():
		return "ninguna"
	var names: PackedStringArray = []
	for item: KeyItemData in _items.values():
		names.append(item.display_name)
	return ", ".join(names)
