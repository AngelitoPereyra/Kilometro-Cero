class_name Bed
extends Interactable
## Una cama (tarea 62c.3h, D143): la del vagón cocina (gratis) o la de una taberna (`price`). Con F,
## de noche (Sleeper.can_sleep_at), el jugador duerme hasta las 7:00 y queda como su última cama:
## ahí despierta si se desmaya. Dormir no cura.

const BED_GROUP: StringName = &"beds"

@export var price: int = 0
## "la cama del vagón", "la taberna de Azul".
@export var place_name: String = "la cama"


func _enter_tree() -> void:
	super()
	add_to_group(GROUP)


## Dónde queda parado el jugador al despertar (al lado de la cama, un poco arriba).
func get_wake_point() -> Vector3:
	return global_transform * Vector3(0.0, 0.3, 0.9)


func get_prompt() -> String:
	var hour: float = GameState.clock.time_of_day
	if not Sleeper.can_sleep_at(hour):
		return "Cama: se duerme de noche (desde las %02d:00)" % int(Sleeper.SLEEP_FROM)
	if price > 0:
		return "Dormir hasta las %02d:00 ($%d)" % [int(Sleeper.WAKE_HOUR), price]
	return "Dormir hasta las %02d:00" % int(Sleeper.WAKE_HOUR)


func _on_interact(player: Player) -> void:
	var sleeper: Sleeper = player.get_sleeper()
	if sleeper != null:
		sleeper.sleep_in(self)
