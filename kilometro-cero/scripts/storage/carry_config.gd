class_name CarryConfig
extends Resource
## Cuánto puede cargar alguien y cómo lo penaliza el exceso (D20).
## Hasta `free_ratio` (100 % de la capacidad) no hay penalización. Entre `free_ratio` y
## `max_ratio` (150 %) la velocidad baja y la fatiga sube de forma gradual y lineal; pasado
## `max_ratio` no se puede recoger más. Valores provisorios: se balancean en la tarea 31.

# Margen para que un cociente exactamente en el tope (1.5) no quede afuera por redondeo.
const RATIO_EPSILON: float = 0.0001

## Capacidad sin mochila. Cada mochila equipada suma su `weight_capacity_bonus`.
@export_range(1.0, 500.0, 0.5, "suffix:kg") var base_capacity: float = 50.0

@export_group("Penalización por exceso")
## Hasta este cociente (peso / capacidad) no hay penalización.
@export_range(0.5, 2.0, 0.05) var free_ratio: float = 1.0
## Pasado este cociente no se puede recoger más. La penalización llega a su máximo acá.
@export_range(1.0, 3.0, 0.05) var max_ratio: float = 1.5
## Multiplicador de velocidad en `max_ratio` (0.5 = a mitad de velocidad).
@export_range(0.05, 1.0, 0.05) var min_speed_multiplier: float = 0.5
## Multiplicador del cansancio en `max_ratio` (2.0 = se cansa el doble).
@export_range(1.0, 10.0, 0.1) var max_fatigue_multiplier: float = 2.0


## 0.0 = sin penalización, 1.0 = penalización máxima. Lineal entre free_ratio y max_ratio.
func penalty_progress(ratio: float) -> float:
	if ratio <= free_ratio:
		return 0.0
	# Si la configuración está mal (max_ratio <= free_ratio) la penalización es inmediata:
	# así nunca dividimos por cero.
	if max_ratio <= free_ratio:
		return 1.0
	return clampf(inverse_lerp(free_ratio, max_ratio, ratio), 0.0, 1.0)


func speed_multiplier(ratio: float) -> float:
	return lerpf(1.0, min_speed_multiplier, penalty_progress(ratio))


func fatigue_multiplier(ratio: float) -> float:
	return lerpf(1.0, max_fatigue_multiplier, penalty_progress(ratio))


## Si se puede cargar con ese cociente (hasta `max_ratio` inclusive).
func can_carry(ratio: float) -> bool:
	return ratio <= max_ratio + RATIO_EPSILON
