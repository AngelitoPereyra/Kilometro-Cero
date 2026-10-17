extends Node
## Bus de señales globales. NO tiene lógica: solo declara señales.
## Quien emite no conoce a quien escucha, y así los sistemas lejanos (UI, necesidades,
## estaciones) se comunican sin referenciarse entre sí (02-arquitectura, sección 1).
##
## No lleva `class_name`: el autoload ya se llama EventBus, y repetir el nombre
## como clase hace que Godot dé error por conflicto.
##
## Señales con `ItemStack` (item_held, item_released, item_placed, item_stored,
## item_taken) se agregan en las tareas 11, 13 y 15, cuando esa clase exista.
## contract_completed y event_triggered se agregan en las tareas 43 y 44.

# Estas señales se emiten desde otros scripts, no desde este: Godot avisaría
# "señal declarada pero no usada" por cada una. El aviso no aplica a un bus.
@warning_ignore_start("unused_signal")

## Cambia agua, comida o fatiga. `need` es &"water", &"food" o &"fatigue".
signal need_changed(need: StringName, value: float)
## Empieza un día de juego nuevo.
signal day_started(day: int)
## Avanza el reloj de juego (por ejemplo, al tomar mate).
signal time_advanced(hours: float)
## Desmayo por una necesidad en 0 o por un accidente.
signal player_fainted(cause: StringName)
## El jugador toma o suelta algo con las manos.
signal hands_changed()
## Cambia la relación peso/capacidad (1.0 = al límite sin penalización).
signal encumbrance_changed(ratio: float)
## Se usa una herramienta; `durability` es lo que le queda.
signal tool_used(tool_id: StringName, durability: float)
## Una herramienta se rompió y deja de servir.
signal tool_broken(tool_id: StringName)
## Se entregan materiales al depósito de una estación.
signal contribution_delivered(station_id: StringName, item_id: StringName, amount: int)
## El pueblo terminó una mejora de la estación.
signal station_level_changed(station_id: StringName, level: int)
## Cambia la condición (0.0 a 1.0) de un tramo de vía.
signal track_condition_changed(segment_id: StringName, condition: float)
## Se aplica una mejora a un vehículo.
signal vehicle_upgraded(vehicle_id: StringName, upgrade_id: StringName)
## Cambia el Índice de Recuperación Regional de una región.
signal irr_changed(region_id: StringName, value: float)
## Empieza un salto de viaje con mate.
signal mate_started(destination_id: StringName)
## Termina el salto de viaje.
signal mate_ended()

@warning_ignore_restore("unused_signal")
