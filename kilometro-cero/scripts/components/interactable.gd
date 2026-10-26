class_name Interactable
extends Node3D
## Algo que se usa con F (acción `interact`) estando cerca: el tablero de una estación, un
## poblador (tarea 58). La cabina tiene prioridad (Player.try_enter_cab); si no se entra a una,
## Player usa el Interactable más cercano dentro de su alcance (Player.try_interact).
## Las clases hijas redefinen get_prompt y _on_interact.

## Se usó (después de _on_interact).
signal interacted(player: Player)

const GROUP: StringName = &"interactables"

## Distancia máxima (m) desde el jugador.
@export_range(0.5, 10.0, 0.1, "suffix:m") var reach: float = 3.0


## El Interactable más cercano a `point` dentro de su alcance que se pueda usar, o null.
static func find_nearest(tree: SceneTree, point: Vector3, player: Player = null) -> Interactable:
	var best: Interactable = null
	var best_distance: float = INF
	for node: Node in tree.get_nodes_in_group(GROUP):
		var interactable := node as Interactable
		if interactable == null or not interactable.can_interact(player):
			continue
		var distance: float = interactable.global_position.distance_to(point)
		if distance <= interactable.reach and distance < best_distance:
			best = interactable
			best_distance = distance
	return best


func _enter_tree() -> void:
	add_to_group(GROUP)


## Si ahora se puede usar.
func can_interact(_player: Player) -> bool:
	return is_visible_in_tree()


## Qué hace F ahora ("Hablar", "Entregar 20 troncos"...). Para la interfaz (tarea 67).
func get_prompt() -> String:
	return "Usar"


## Lo usa el jugador (Player.try_interact). Devuelve false si no se podía.
func interact(player: Player) -> bool:
	if not can_interact(player):
		return false
	_on_interact(player)
	interacted.emit(player)
	return true


func _on_interact(_player: Player) -> void:
	pass
