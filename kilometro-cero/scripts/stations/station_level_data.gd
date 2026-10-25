class_name StationLevelData
extends Resource
## Un nivel de crecimiento de una estación (D79, tarea 56): qué necesita por día para crecer
## al siguiente, qué produce de más y qué servicios abre. Va dentro de StationData.levels
## (el primero es el nivel 1). Los valores son provisorios hasta el Hito A (tarea 62).

## Consumo por día que nace en este nivel. Cubierto, la estación crece al siguiente; en el
## último nivel no hace falta (no hay a dónde crecer), pero se sigue consumiendo si se pone.
@export var needs: Array[ItemAmount] = []
## Días seguidos (o no: un día sin cubrir no los borra, D79) con todo el consumo cubierto que
## hacen falta para crecer al siguiente nivel (tarea 57).
@export_range(1, 365) var days_to_grow: int = 3
## Producción por día que se suma a la base desde este nivel.
@export var extra_production: Array[ItemAmount] = []
## Abre el mercado desde este nivel (compra y venta, tarea 59).
@export var market: bool = false
## Abre el taller desde este nivel (además lo habilita una misión principal, D80, tarea 63).
@export var workshop: bool = false
## Qué cambia en el pueblo (para la interfaz y para quien arma la escena).
@export_multiline var description: String = ""
