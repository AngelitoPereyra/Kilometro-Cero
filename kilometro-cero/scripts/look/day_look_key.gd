class_name DayLookKey
extends Resource
## Un momento del día en DayLook (tarea 62c.3e, D140): los colores de la luz, el cielo, la niebla y
## el horizonte a esa hora. Entre dos momentos se mezclan.

@export_range(0.0, 24.0, 0.25) var hour: float = 12.0
@export var sun_color: Color = Color(1.0, 0.95, 0.88)
@export_range(0.0, 4.0, 0.01) var sun_energy: float = 1.2
## La luz ambiente: tiñe las sombras (azul o violeta, nunca gris, D140).
@export var ambient_color: Color = Color(0.56, 0.66, 0.82)
@export_range(0.0, 4.0, 0.01) var ambient_energy: float = 0.6
@export var sky_top: Color = Color(0.44, 0.7, 0.88)
@export var sky_horizon: Color = Color(0.81, 0.91, 0.96)
@export var fog_color: Color = Color(0.81, 0.91, 0.96)
## Las lomas cercanas y las lejanas del horizonte (HorizonRing).
@export var horizon_near: Color = Color(0.55, 0.65, 0.5)
@export var horizon_far: Color = Color(0.62, 0.71, 0.79)
@export_range(0.0, 1.0, 0.01) var stars: float = 0.0


## Lógica pura: la mezcla de dos momentos (t 0 es `a`, 1 es `b`).
static func blend(a: DayLookKey, b: DayLookKey, t: float) -> DayLookKey:
	var mixed := DayLookKey.new()
	mixed.hour = lerpf(a.hour, b.hour, t)
	mixed.sun_color = a.sun_color.lerp(b.sun_color, t)
	mixed.sun_energy = lerpf(a.sun_energy, b.sun_energy, t)
	mixed.ambient_color = a.ambient_color.lerp(b.ambient_color, t)
	mixed.ambient_energy = lerpf(a.ambient_energy, b.ambient_energy, t)
	mixed.sky_top = a.sky_top.lerp(b.sky_top, t)
	mixed.sky_horizon = a.sky_horizon.lerp(b.sky_horizon, t)
	mixed.fog_color = a.fog_color.lerp(b.fog_color, t)
	mixed.horizon_near = a.horizon_near.lerp(b.horizon_near, t)
	mixed.horizon_far = a.horizon_far.lerp(b.horizon_far, t)
	mixed.stars = lerpf(a.stars, b.stars, t)
	return mixed
