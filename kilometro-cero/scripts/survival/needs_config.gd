class_name NeedsConfig
extends Resource
## Tasas de las necesidades y reglas del desmayo. Es un recurso para balancear desde el
## inspector sin tocar código (D15). Los valores son provisorios: se ajustan en la tarea 31.
## "Hora" = hora de juego. Con un día de 24 min reales, una hora de juego dura 1 minuto real.

@export_range(1.0, 120.0, 0.5, "suffix:min") var day_length_minutes: float = 24.0

@export_group("Valores iniciales")
@export_range(0.0, 100.0, 1.0) var start_water: float = 100.0
@export_range(0.0, 100.0, 1.0) var start_food: float = 100.0
## La fatiga sube: 0 = descansado, 100 = agotado.
@export_range(0.0, 100.0, 1.0) var start_fatigue: float = 0.0

@export_group("Cambio por hora de juego")
@export_range(0.0, 50.0, 0.1) var water_loss_per_hour: float = 5.0
@export_range(0.0, 50.0, 0.1) var food_loss_per_hour: float = 3.0
@export_range(0.0, 50.0, 0.1) var fatigue_gain_per_hour: float = 5.0

@export_group("Desmayo")
## Horas de juego que se pierden mientras está inconsciente.
@export_range(0.0, 24.0, 0.5, "suffix:h") var faint_hours_lost: float = 6.0
## Segundos reales que queda en el suelo.
@export_range(0.5, 30.0, 0.5, "suffix:s") var faint_duration_seconds: float = 3.0
## Al despertar, agua y comida suben al menos a este valor...
@export_range(0.0, 100.0, 1.0) var faint_recovery_value: float = 25.0
## ...y la fatiga baja como mucho a este.
@export_range(0.0, 100.0, 1.0) var faint_recovery_fatigue: float = 50.0
