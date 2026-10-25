class_name KeyItemData
extends ItemData
## Una herramienta clave (tarea 55, D83): el hacha, la barreta, la pala. No ocupa una ranura
## de la mochila ni se gasta: tenerla habilita acciones (talar, despejar). Al recogerla con E
## pasa a los KeyItems del jugador y el objeto del mundo desaparece.
## Es un ItemData para poder dejarla tirada en el mundo (WorldItem) o darla como recompensa.

## Qué habilita, para mostrarlo en la interfaz ("talar árboles y despejar troncos caídos").
@export_multiline var action_text: String = ""
