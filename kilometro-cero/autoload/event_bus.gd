extends Node
## Bus de señales globales. NO tiene lógica: solo declara señales.
## Quien emite no conoce a quien escucha, y así los sistemas lejanos (UI, misiones,
## estaciones) se comunican sin referenciarse entre sí (02-arquitectura, sección 1).
##
## No lleva `class_name`: el autoload ya se llama EventBus, y repetir el nombre
## como clase hace que Godot dé error por conflicto.
##
## Señales con `ItemStack` (item_held, item_released, item_placed, item_stored,
## item_taken) se agregan en las tareas 11, 13 y 15, cuando esa clase exista.
## event_triggered se agrega con los eventos especiales (tarea 71).

# Estas señales se emiten desde otros scripts, no desde este: Godot avisaría
# "señal declarada pero no usada" por cada una. El aviso no aplica a un bus.
@warning_ignore_start("unused_signal")

## Empieza un día de juego nuevo.
signal day_started(day: int)
## Avanza el reloj de juego (por ejemplo, al acampar).
signal time_advanced(hours: float)
## El jugador toma o suelta algo con las manos.
signal hands_changed()
## Se da un golpe con una herramienta clave (&"" si fue con las manos). Sin durabilidad (D83).
signal tool_used(tool_id: StringName)
## El jugador consigue una herramienta clave nueva (tarea 55). La emite Player.
signal key_item_obtained(item_id: StringName)
## Se despeja un obstáculo del tramo `segment_id` (tarea 55). El tramo se abre recién cuando
## no le queda ninguno: para eso, segment_state_changed.
signal obstacle_cleared(segment_id: StringName)
## Se entregan materiales en una estación para sus misiones (tarea 58). La emite StationBoard
## al aprobar una entrega.
signal contribution_delivered(station_id: StringName, item_id: StringName, amount: int)
## Una misión nueva: una principal que nace (ya en curso) o una secundaria que ya se puede
## conseguir (tarea 58). Las emite GameState desde GameState.missions.
signal mission_available(mission_id: StringName)
## Se tomó una secundaria (hablando con un poblador).
signal mission_started(mission_id: StringName)
## Se entregó algo para una misión.
signal mission_progressed(mission_id: StringName)
signal mission_completed(mission_id: StringName)
## Cambió el dinero del jugador (GameState.money, D96).
signal money_changed(money: int)
## El jugador compró (amount positivo) o vendió (negativo) en el mercado de una estación;
## `total` son los pesos que pagó o cobró (tarea 59). La emite Market.
signal item_traded(station_id: StringName, item_id: StringName, amount: int, total: int)
## Se abrieron las puertas de un coche en una estación (tarea 60b): pasajeros que bajaron, que
## subieron y pesos que pagaron los sobrantes al subir. La emite PassengerCoach.
signal passengers_exchanged(station_id: StringName, alighted: int, boarded: int, fare: int)
## Cambió el coche de pasajeros que regala la ciudad (valores de PassengerTraffic.CoachState).
## La emite GameState.
signal coach_gift_changed(state: int)
## Una estación cambió de nivel de crecimiento (D79). La emite Station.set_level (y desde la
## tarea 57 el modelo de producción); cada Station escucha la suya y muestra sus nodos.
signal station_level_changed(station_id: StringName, level: int)
## Un tren se detuvo en una estación (tarea 56). La emite Station, una vez por parada.
signal train_stopped_at_station(station_id: StringName, head: Vehicle)
## El jugador entró a la zona de una estación, o salió (&"") (tarea 56). La emite Station.
signal player_station_changed(station_id: StringName)
## Cambia la condición (0.0 a 1.0) de un tramo de vía.
signal track_condition_changed(segment_id: StringName, condition: float)
## Un tramo pasa a cortado, abierto o mejorado (valores de TrackSegment.State). La emite
## RailNetwork, una vez por tramo aunque tenga vía doble (tarea 54).
signal segment_state_changed(segment_id: StringName, state: int)
## Se aplica una mejora a un vehículo.
signal vehicle_upgraded(vehicle_id: StringName, upgrade_id: StringName)
## Cambia el Índice de Recuperación Regional de una región.
signal irr_changed(region_id: StringName, value: float)
## Entra algo a un contenedor con identificador (mochila, vagón, depósito).
signal item_stored(container_id: StringName, stack: ItemStack)
## Sale algo de un contenedor con identificador.
signal item_taken(container_id: StringName, stack: ItemStack)
## Cambia el nivel de alerta de la mochila (D59): 0 normal, 1 casi llena, 2 llena
## (los valores de Inventory.Alert). La interfaz avisa solo cuando sube.
signal backpack_alert_changed(alert: int)
## El jugador toma con las manos un objeto del mundo.
signal item_held(stack: ItemStack)
## El jugador suelta un objeto que tenía en las manos.
signal item_released(stack: ItemStack)
## Se confirma una colocación precisa (clic derecho mantenido). `position` es dónde quedó.
signal item_placed(stack: ItemStack, position: Vector3)

@warning_ignore_restore("unused_signal")
