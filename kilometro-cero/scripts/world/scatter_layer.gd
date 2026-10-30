class_name ScatterLayer
extends Resource
## Una capa de BiomeScatter (tarea 62c.3b, D136): qué se reparte, cuánto y dónde. Las formas salen
## de `kind` (BiomeScatter.make_parts), así no hacen falta modelos.

enum Kind { GRASS, BUSH, THISTLE, ROCK, TREE, EUCALYPTUS, WILLOW }

@export var id: StringName
@export var kind: Kind = Kind.GRASS
## Cuántos por cada 100 m² donde la capa toca (antes del ruido).
@export_range(0.001, 50.0, 0.001) var density: float = 1.0
@export_range(0.1, 5.0, 0.05) var min_scale: float = 0.8
@export_range(0.1, 5.0, 0.05) var max_scale: float = 1.2
## Rectángulo global (x, z) donde va; vacío: todo el terreno.
@export var area: Rect2 = Rect2()
## Manchas: solo donde el ruido (de -1 a 1) pasa de `noise_threshold`; -1 en todos lados.
@export_range(-1.0, 1.0, 0.01) var noise_threshold: float = -1.0
@export_range(0.0001, 0.1, 0.0001) var noise_frequency: float = 0.01
## Metros que se aparta de las vías, caminos y arroyos (y de estaciones y lotes, siempre afuera).
@export_range(0.0, 50.0, 0.5, "suffix:m") var keep_away: float = 4.0
## Solo cerca de un arroyo (TerrainCarve): a menos de estos metros de su orilla; 0 en cualquier lado.
@export_range(0.0, 100.0, 0.5, "suffix:m") var near_water: float = 0.0
## Pendiente máxima (subida por metro) donde todavía crece.
@export_range(0.0, 5.0, 0.01) var max_slope: float = 5.0
## Hasta dónde se ve (la distancia a cada trozo).
@export_range(10.0, 2000.0, 5.0, "suffix:m") var view_distance: float = 250.0
