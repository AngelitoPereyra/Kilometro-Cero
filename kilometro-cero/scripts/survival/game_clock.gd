class_name GameClock
extends RefCounted
## Reloj del juego (D34). Lógica pura: no sabe de cuadros ni de escenas.
## GameState le pasa el tiempo real y el mate o el desmayo le pasan saltos.
## Emite señales locales y GameState las reemite por el EventBus.

signal day_started(day: int)
signal time_advanced(hours: float)

const HOURS_PER_DAY: float = 24.0

var current_day: int = 1
## Hora del día, de 0.0 a 24.0 (8.5 = 08:30). El juego arranca a las 8 de la mañana.
var time_of_day: float = 8.0


## Horas de juego que pasan por cada segundo real, para un día de `day_length_minutes`.
static func hours_per_real_second(day_length_minutes: float) -> float:
	return HOURS_PER_DAY / (day_length_minutes * 60.0)


## "08:30". Se trunca el minuto para que 23.999 sea 23:59 y nunca "24:00".
static func format_time(time_of_day_hours: float) -> String:
	var total_minutes: int = clampi(floori(time_of_day_hours * 60.0), 0, 1439)
	# Dividir por 60.0 (decimal) y redondear hacia abajo da las horas enteras sin usar
	# división entera, que es la que dispara la advertencia.
	var hours: int = floori(total_minutes / 60.0)
	return "%02d:%02d" % [hours, total_minutes % 60]

## Avanza el reloj. Un salto largo (mate, desmayo) puede cruzar varias medianoches.
func advance(hours: float) -> void:
	if hours <= 0.0:
		return
	var total: float = time_of_day + hours
	var days_passed: int = floori(total / HOURS_PER_DAY)
	time_of_day = fposmod(total, HOURS_PER_DAY)
	# Primero se actualiza todo el estado y recién después se avisa: quien escucha ve
	# siempre un reloj coherente.
	var first_new_day: int = current_day + 1
	current_day += days_passed
	for day: int in range(first_new_day, current_day + 1):
		day_started.emit(day)
	time_advanced.emit(hours)
