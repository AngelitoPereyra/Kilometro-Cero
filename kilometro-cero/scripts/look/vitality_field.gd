class_name VitalityField
extends Node
## Vitalidad por zona (tarea 62c.3e, D141): el color mide el crecimiento. Arma un mapa del terreno
## (un valor de 0 a 1 por cuadro) que el material del mundo lee para desaturar y empolvar lo
## abandonado: el campo suelto queda a medias, cerca de una vía cortada se apaga, cerca de una
## abierta o mejorada revive, y cada estación brilla más cuanto más creció. Cuando algo cambia
## (EventBus: station_level_changed, segment_state_changed) se rehace y el color pasa de a poco.
## Busca el Terrain, las estaciones y las vías en la escena. Las flores, la ropa tendida y las luces
## de noche que también suman vida llegan con el pueblo y la ciudad (62c.4 y 62c.5).

const GROUP: StringName = &"vitality_field"

## Lado de cada cuadro del mapa.
@export_range(2.0, 32.0, 1.0, "suffix:m") var cell_size: float = 8.0
## El campo suelto, lejos de todo.
@export_range(0.0, 1.0, 0.01) var base_vitality: float = 0.55
## Cerca de una vía cortada, abierta y mejorada.
@export_range(0.0, 1.0, 0.01) var cut_vitality: float = 0.15
@export_range(0.0, 1.0, 0.01) var open_vitality: float = 0.75
@export_range(0.0, 1.0, 0.01) var improved_vitality: float = 0.9
## Hasta dónde llega una vía (medio ancho lleno y fundido).
@export_range(1.0, 200.0, 1.0, "suffix:m") var track_reach: float = 25.0
@export_range(1.0, 200.0, 1.0, "suffix:m") var track_fade: float = 30.0
## Una estación en su primer nivel y en el último.
@export_range(0.0, 1.0, 0.01) var station_min_vitality: float = 0.3
@export_range(0.0, 1.0, 0.01) var station_max_vitality: float = 1.0
@export_range(1.0, 1000.0, 1.0, "suffix:m") var station_reach: float = 150.0
@export_range(1.0, 500.0, 1.0, "suffix:m") var station_fade: float = 90.0
## Segundos que tarda el color en pasar de un mapa al siguiente.
@export_range(0.0, 20.0, 0.1, "suffix:s") var transition_time: float = 4.0

var _terrain: Terrain
var _rect: Rect2 = Rect2()
var _columns: int = 0
var _rows: int = 0
var _values: PackedFloat32Array = PackedFloat32Array()
var _texture: ImageTexture
var _previous: ImageTexture
var _blend: float = 1.0
var _dirty: bool = true
# Vitalidad fija por estación (id -> valor), para pruebas y fotos.
var _overrides: Dictionary[StringName, float] = {}


func _ready() -> void:
	add_to_group(GROUP)
	Palette.ensure_globals()
	EventBus.station_level_changed.connect(_on_station_level_changed)
	EventBus.segment_state_changed.connect(_on_segment_state_changed)


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(&"vitality_enabled", 0.0)


static func find_in(tree: SceneTree) -> VitalityField:
	return tree.get_first_node_in_group(GROUP) as VitalityField if tree != null else null


func _process(delta: float) -> void:
	if _dirty:
		_dirty = false
		rebuild()
	if _blend < 1.0:
		_blend = minf(_blend + delta / maxf(transition_time, 0.01), 1.0)
		RenderingServer.global_shader_parameter_set(&"vitality_mix", _blend)


## Lógica pura: la vitalidad de una estación según su nivel.
static func station_vitality(level: int, max_level: int, minimum: float, maximum: float) -> float:
	if max_level <= 1:
		return maximum if level >= max_level else minimum
	return lerpf(minimum, maximum, clampf(float(level - 1) / float(max_level - 1), 0.0, 1.0))


## Lógica pura: cuánto pesa algo a esa distancia (1 adentro de `reach`, 0 pasando `reach + fade`).
static func weight_at(distance: float, reach: float, fade: float) -> float:
	return 1.0 - smoothstep(reach, reach + maxf(fade, 0.001), distance)


## Fija la vitalidad de una estación (de 0 a 1); un valor negativo la devuelve a su nivel.
func set_station_override(station_id: StringName, value: float) -> void:
	if value < 0.0:
		_overrides.erase(station_id)
	else:
		_overrides[station_id] = clampf(value, 0.0, 1.0)
	_dirty = true


## La vitalidad del mapa en ese punto del mundo (la del último rehacer, sin la transición).
func get_vitality_at(point: Vector3) -> float:
	if _values.is_empty():
		return 1.0
	var i: int = clampi(floori((point.x - _rect.position.x) / cell_size), 0, _columns - 1)
	var j: int = clampi(floori((point.z - _rect.position.y) / cell_size), 0, _rows - 1)
	return _values[j * _columns + i]


## Rehace el mapa ya mismo (si no, se rehace solo cuando algo cambia).
func rebuild() -> void:
	_terrain = get_tree().get_first_node_in_group(Terrain.GROUP) as Terrain
	if _terrain == null:
		RenderingServer.global_shader_parameter_set(&"vitality_enabled", 0.0)
		return
	var half: Vector2 = _terrain.size * 0.5
	_rect = Rect2(Vector2(_terrain.global_position.x, _terrain.global_position.z) - half, _terrain.size)
	_columns = maxi(ceili(_rect.size.x / cell_size), 1)
	_rows = maxi(ceili(_rect.size.y / cell_size), 1)
	var count: int = _columns * _rows
	var cut := PackedFloat32Array()
	var open := PackedFloat32Array()
	var improved := PackedFloat32Array()
	cut.resize(count)
	cut.fill(INF)
	open.resize(count)
	open.fill(INF)
	improved.resize(count)
	improved.fill(INF)
	for node: Node in get_tree().get_nodes_in_group(TrackSegment.GROUP):
		var segment := node as TrackSegment
		var path: Path3D = segment.get_track_path() if segment != null else null
		if path == null or path.curve == null:
			continue
		match segment.state:
			TrackSegment.State.CUT:
				_stamp_path(path, cut)
			TrackSegment.State.IMPROVED:
				_stamp_path(path, improved)
			_:
				_stamp_path(path, open)
	_values.resize(count)
	_values.fill(base_vitality)
	for index: int in count:
		var value: float = base_vitality
		value = lerpf(value, cut_vitality, weight_at(cut[index], track_reach, track_fade))
		value = lerpf(value, open_vitality, weight_at(open[index], track_reach, track_fade))
		value = lerpf(value, improved_vitality, weight_at(improved[index], track_reach, track_fade))
		_values[index] = value
	for node: Node in get_tree().get_nodes_in_group(Station.GROUP):
		var station := node as Station
		if station != null:
			_stamp_station(station)
	_publish()


func _stamp_station(station: Station) -> void:
	var target: float = _overrides.get(station.get_station_id(), station_vitality(station.level, station.get_max_level(), station_min_vitality, station_max_vitality))
	var center := Vector2(station.global_position.x, station.global_position.z)
	var reach: float = station_reach + station_fade
	var first := Vector2i(floori((center.x - reach - _rect.position.x) / cell_size), floori((center.y - reach - _rect.position.y) / cell_size))
	var last := Vector2i(floori((center.x + reach - _rect.position.x) / cell_size), floori((center.y + reach - _rect.position.y) / cell_size))
	for j: int in range(maxi(first.y, 0), mini(last.y, _rows - 1) + 1):
		for i: int in range(maxi(first.x, 0), mini(last.x, _columns - 1) + 1):
			var index: int = j * _columns + i
			var weight: float = weight_at(_cell_center(i, j).distance_to(center), station_reach, station_fade)
			_values[index] = lerpf(_values[index], target, weight)


# Distancia de cada cuadro a la vía más cercana de esa clase, hasta donde llega.
func _stamp_path(path: Path3D, grid: PackedFloat32Array) -> void:
	var length: float = path.curve.get_baked_length()
	var reach: float = track_reach + track_fade
	var cells: int = ceili(reach / cell_size)
	for k: int in ceili(length / cell_size) + 1:
		var point: Vector3 = path.to_global(path.curve.sample_baked(minf(k * cell_size, length)))
		var flat := Vector2(point.x, point.z)
		var ci: int = floori((point.x - _rect.position.x) / cell_size)
		var cj: int = floori((point.z - _rect.position.y) / cell_size)
		for j: int in range(maxi(cj - cells, 0), mini(cj + cells, _rows - 1) + 1):
			for i: int in range(maxi(ci - cells, 0), mini(ci + cells, _columns - 1) + 1):
				var index: int = j * _columns + i
				var distance: float = _cell_center(i, j).distance_to(flat)
				if distance < grid[index]:
					grid[index] = distance


func _cell_center(i: int, j: int) -> Vector2:
	return _rect.position + Vector2((i + 0.5) * cell_size, (j + 0.5) * cell_size)


func _publish() -> void:
	var image := Image.create(_columns, _rows, false, Image.FORMAT_L8)
	for j: int in _rows:
		for i: int in _columns:
			var value: float = _values[j * _columns + i]
			image.set_pixel(i, j, Color(value, value, value))
	var fresh := ImageTexture.create_from_image(image)
	_previous = _texture if _texture != null else fresh
	_texture = fresh
	_blend = 0.0 if _previous != _texture and transition_time > 0.0 else 1.0
	RenderingServer.global_shader_parameter_set(&"vitality_map_prev", _previous)
	RenderingServer.global_shader_parameter_set(&"vitality_map", _texture)
	RenderingServer.global_shader_parameter_set(&"vitality_mix", _blend)
	RenderingServer.global_shader_parameter_set(&"vitality_rect", Vector4(_rect.position.x, _rect.position.y, _rect.size.x, _rect.size.y))
	RenderingServer.global_shader_parameter_set(&"vitality_enabled", 1.0)


func _on_station_level_changed(_station_id: StringName, _level: int) -> void:
	_dirty = true


func _on_segment_state_changed(_segment_id: StringName, _state: int) -> void:
	_dirty = true
