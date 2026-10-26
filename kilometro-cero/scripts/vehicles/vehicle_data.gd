class_name VehicleData
extends Resource
## Definición de un tipo de vehículo (zorra, autovía, locomotora...).
## Es una definición compartida: NO guarda estado (velocidad actual, posición).
## Eso vive en Vehicle, igual que ItemData/ItemStack (D33).
## Los valores son provisorios y se balancean en la tarea 31.

# Margen para que 0.2 + error de redondeo no deje afuera al vehículo en su propio mínimo.
const CONDITION_EPSILON: float = 0.0001

@export var id: StringName
@export var display_name: String
@export var level: int = 1
## Largo de tope a tope. Con él se separan los vehículos acoplados y se frena en los
## extremos de la vía sin que nada quede afuera (tarea 53).
@export_range(0.5, 40.0, 0.1, "suffix:m") var length: float = 4.0

## Condición de vía (0.0 a 1.0) por debajo de la cual el vehículo no puede andar.
@export_range(0.0, 1.0, 0.01) var min_track_condition: float = 0.2
## Velocidad máxima con la vía perfecta.
@export_range(0.1, 100.0, 0.1, "suffix:m/s") var max_speed: float = 6.0
## Qué fracción de `max_speed` alcanza justo en la condición mínima.
@export_range(0.0, 1.0, 0.01) var min_speed_fraction: float = 0.4
@export_range(0.1, 20.0, 0.1, "suffix:m/s²") var acceleration: float = 1.0
## Desaceleración con el freno a fondo (Vehicle.brake).
@export_range(0.1, 20.0, 0.1, "suffix:m/s²") var braking: float = 2.5
## Desaceleración al soltar el acelerador sin frenar (rozamiento, punto muerto). Por defecto
## igual que `braking`: los vehículos sin freno propio (la zorra) frenan al soltar (tarea 52).
@export_range(0.01, 20.0, 0.01, "suffix:m/s²") var coast_deceleration: float = 2.5
## Cuántos vagones puede arrastrar como locomotora de un tren automático (tarea 61, D110).
@export_range(0, 20) var max_wagons: int = 4


func can_enter(track_condition: float) -> bool:
	return track_condition + CONDITION_EPSILON >= min_track_condition


## Velocidad máxima sobre un tramo con esa condición: 0 si no puede entrar y, si puede,
## crece linealmente desde `min_speed_fraction` hasta `max_speed`.
func get_max_speed(track_condition: float) -> float:
	if not can_enter(track_condition):
		return 0.0
	# Un vehículo que exige vía perfecta no tiene rango que interpolar (evita dividir por 0).
	if min_track_condition >= 1.0:
		return max_speed
	var t: float = clampf(inverse_lerp(min_track_condition, 1.0, track_condition), 0.0, 1.0)
	return max_speed * lerpf(min_speed_fraction, 1.0, t)
