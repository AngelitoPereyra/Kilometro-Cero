@tool
class_name Terrain
extends StaticBody3D
## Terreno de la maqueta (tarea 62c.1, D134). Reemplaza al campo plano: una grilla de alturas que
## sale de un mapa de alturas pintado a mano (`height_map`, gris) más ruido suave (`noise`, lomas),
## con su malla y su forma de choque armadas por código.
## La vía manda sobre el terreno: debajo de cada vía dibujada (un Path3D con TrackBuilder), de cada
## estación y de cada lote junto a la vía (TrackLot) el terreno se aplana solo a su altura, con un
## talud que se abre según cuánto haya que subir o bajar (terraplén o trinchera). Así se dibuja la
## vía y el terreno se acomoda; nada se retoca a mano.
## Busca vías, estaciones y lotes debajo de su padre (la escena donde está). En el editor se arma
## al abrir la escena y con el botón "Rehacer terreno" (después de mover una vía); en el juego, al
## empezar. El origen del nodo es el centro del terreno y su y es la altura 0 del mapa; no se gira.
## Tarea 62c.3c: los arroyos (TerrainCarve) se cavan después de aplanar, también debajo de las
## vías (las cruzan con un puente); `is_carved` dice si un punto cae en uno.

const GROUP: StringName = &"terrain"
const MESH_NODE_NAME: String = "Malla"
const SHAPE_NODE_NAME: String = "Forma"
## Colores de bosquejo (tiny, de maqueta): pasto, tierra de los taludes empinados y roca de lo alto.
const COLOR_GRASS: Color = Color(0.45, 0.58, 0.3)
const COLOR_DIRT: Color = Color(0.55, 0.45, 0.3)
const COLOR_ROCK: Color = Color(0.58, 0.56, 0.52)
## Desde qué pendiente (1 - normal.y) el pasto pasa a tierra, y en cuánto termina de pasar.
const DIRT_SLOPE_START: float = 0.08
const DIRT_SLOPE_FULL: float = 0.25
## Cuánto mide la transición del pasto a la roca, por encima de `rock_height`.
const ROCK_BLEND_M: float = 6.0

## Ancho y largo (X y Z) del terreno, centrado en el nodo.
@export var size: Vector2 = Vector2(400.0, 400.0)
## Lado de cada cuadro de la grilla.
@export_range(1.0, 20.0, 0.5, "suffix:m") var cell_size: float = 4.0
## Mapa de alturas pintado: cubre todo el terreno; negro es 0 y blanco `height_map_scale`.
@export var height_map: Texture2D
@export_range(0.0, 200.0, 0.5, "suffix:m") var height_map_scale: float = 20.0
## Ruido de las lomas, que se suma al mapa: va de 0 a `noise_height` (nunca baja del plano).
@export var noise: FastNoiseLite
@export_range(0.0, 100.0, 0.5, "suffix:m") var noise_height: float = 4.0
## Medio ancho del corredor plano debajo de cada vía (12 m en total: con cuadros de 4 m, todo lo que
## está a 2 m de la vía cae entre vértices planos y la vía nunca queda tapada).
@export_range(1.0, 20.0, 0.5, "suffix:m") var corridor_half_width: float = 6.0
## Talud: metros de ancho por cada metro de altura que sube o baja (1:2 por defecto).
@export_range(0.5, 10.0, 0.1) var slope_ratio: float = 2.0
## El talud más angosto y el más ancho. Con un mínimo grande las lomas crecen de a poco desde la vía.
@export_range(1.0, 200.0, 0.5, "suffix:m") var min_blend: float = 8.0
@export_range(1.0, 200.0, 0.5, "suffix:m") var max_blend: float = 60.0
## Rectángulo plano alrededor de cada estación (X de costado, Z a lo largo de la vía).
@export var station_flat_size: Vector2 = Vector2(120.0, 260.0)
## Altura desde la que lo alto se pinta de roca (la sierra).
@export_range(0.0, 500.0, 0.5, "suffix:m") var rock_height: float = 18.0
@export_tool_button("Rehacer terreno") var rebuild_button: Callable = rebuild

var _heights: PackedFloat32Array = PackedFloat32Array()
var _columns: int = 0
var _rows: int = 0
# Posición local (x, z) del vértice (0, 0).
var _origin: Vector2 = Vector2.ZERO
# Lo que se aplana mientras se arma: distancia de cada vértice a lo más cercano que lo aplana
# (negativa adentro del corredor de una vía, así entre varios puntos de la vía gana el más cercano,
# y 0 adentro de un rectángulo) y la altura que le pide.
var _flat_distance: PackedFloat32Array = PackedFloat32Array()
var _flat_target: PackedFloat32Array = PackedFloat32Array()
var _image: Image
# Los arroyos que cava (los busca al rehacerse).
var _carves: Array[TerrainCarve] = []


func _ready() -> void:
	add_to_group(GROUP)
	rebuild()


## Vuelve a armar la grilla, la malla y la forma de choque.
func rebuild() -> void:
	if not is_inside_tree():
		return
	_columns = maxi(2, int(size.x / cell_size) + 1)
	_rows = maxi(2, int(size.y / cell_size) + 1)
	_origin = -Vector2(_columns - 1, _rows - 1) * cell_size * 0.5
	_image = _read_image()
	_flat_distance = PackedFloat32Array()
	_flat_distance.resize(_columns * _rows)
	_flat_distance.fill(INF)
	_flat_target = PackedFloat32Array()
	_flat_target.resize(_columns * _rows)
	var root: Node = get_parent() if get_parent() != null else self
	_carves.clear()
	_stamp_features(root)
	_heights = PackedFloat32Array()
	_heights.resize(_columns * _rows)
	for j: int in _rows:
		for i: int in _columns:
			var index: int = j * _columns + i
			var point: Vector2 = vertex_position(i, j)
			var base: float = base_height_at(point.x, point.y)
			var distance: float = _flat_distance[index]
			if distance == INF:
				_heights[index] = base
				continue
			var target: float = _flat_target[index]
			var weight: float = blend_weight(maxf(distance, 0.0), base - target, min_blend, max_blend, slope_ratio)
			_heights[index] = lerpf(target, base, weight)
	for carve: TerrainCarve in _carves:
		_apply_carve(carve)
	_flat_distance = PackedFloat32Array()
	_flat_target = PackedFloat32Array()
	_image = null
	_build_mesh_and_shape()


## Si el punto (global) cae en un arroyo o en sus barrancas.
func is_carved(global_point: Vector3) -> bool:
	for carve: TerrainCarve in _carves:
		if not is_instance_valid(carve) or carve.curve == null:
			continue
		var local: Vector3 = carve.to_local(global_point)
		var closest: Vector3 = carve.curve.get_closest_point(local)
		if Vector2(local.x - closest.x, local.z - closest.z).length() < carve.get_reach():
			return true
	return false


func get_columns() -> int:
	return _columns


func get_rows() -> int:
	return _rows


## Posición local (x, z) del vértice de la columna `i` y la fila `j`.
func vertex_position(i: int, j: int) -> Vector2:
	return _origin + Vector2(i, j) * cell_size


## Altura local del vértice, ya aplanada.
func vertex_height(i: int, j: int) -> float:
	return _heights[j * _columns + i]


## Altura del suelo (y global) debajo de ese punto, igual que la malla; NAN fuera del terreno.
func height_at(global_point: Vector3) -> float:
	var local: Vector3 = to_local(global_point)
	var height: float = local_height_at(local.x, local.z)
	return height + global_position.y if not is_nan(height) else NAN


## Altura local en (x, z) del nodo, interpolada en el mismo triángulo que dibuja la malla.
func local_height_at(x: float, z: float) -> float:
	if _heights.is_empty():
		return NAN
	var grid: Vector2 = (Vector2(x, z) - _origin) / cell_size
	if grid.x < 0.0 or grid.y < 0.0 or grid.x > _columns - 1 or grid.y > _rows - 1:
		return NAN
	var i: int = mini(int(grid.x), _columns - 2)
	var j: int = mini(int(grid.y), _rows - 2)
	var fx: float = grid.x - i
	var fz: float = grid.y - j
	var a: float = vertex_height(i, j)
	var b: float = vertex_height(i + 1, j)
	var c: float = vertex_height(i, j + 1)
	var d: float = vertex_height(i + 1, j + 1)
	# Cada cuadro son dos triángulos con la diagonal de (i, j) a (i + 1, j + 1).
	if fx >= fz:
		return a + (b - a) * fx + (d - b) * fz
	return a + (c - a) * fz + (d - c) * fx


## Altura local sin aplanar: mapa de alturas más lomas.
func base_height_at(x: float, z: float) -> float:
	var height: float = 0.0
	if _image != null:
		var uv: Vector2 = (Vector2(x, z) - _origin) / (Vector2(_columns - 1, _rows - 1) * cell_size)
		height += sample_image(_image, uv) * height_map_scale
	if noise != null:
		height += (noise.get_noise_2d(x, z) * 0.5 + 0.5) * noise_height
	return height


## Lógica pura: cuánto pesa la altura propia del terreno a esa distancia de lo que lo aplana (0:
## toda la altura pedida, 1: la propia). El talud se abre con el desnivel, entre el mínimo y el máximo.
static func blend_weight(distance: float, height_gap: float, min_width: float, max_width: float, slope: float) -> float:
	var width: float = clampf(absf(height_gap) * slope, min_width, maxf(min_width, max_width))
	return smoothstep(0.0, width, distance)


## Lógica pura: distancia de un punto (en el marco del rectángulo) al rectángulo; 0 adentro.
static func rect_distance(local_point: Vector2, half_size: Vector2) -> float:
	var outside := Vector2(maxf(absf(local_point.x) - half_size.x, 0.0), maxf(absf(local_point.y) - half_size.y, 0.0))
	return outside.length()


## Lógica pura: gris de la imagen en `uv` (0 a 1), interpolado entre los cuatro píxeles vecinos.
static func sample_image(image: Image, uv: Vector2) -> float:
	var width: int = image.get_width()
	var height: int = image.get_height()
	var pixel: Vector2 = Vector2(clampf(uv.x, 0.0, 1.0) * (width - 1), clampf(uv.y, 0.0, 1.0) * (height - 1))
	var x0: int = int(pixel.x)
	var y0: int = int(pixel.y)
	var x1: int = mini(x0 + 1, width - 1)
	var y1: int = mini(y0 + 1, height - 1)
	var fx: float = pixel.x - x0
	var fy: float = pixel.y - y0
	var top: float = lerpf(image.get_pixel(x0, y0).r, image.get_pixel(x1, y0).r, fx)
	var bottom: float = lerpf(image.get_pixel(x0, y1).r, image.get_pixel(x1, y1).r, fx)
	return lerpf(top, bottom, fy)


func _read_image() -> Image:
	if height_map == null:
		return null
	var image: Image = height_map.get_image()
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	return image


# Vías, estaciones y lotes, en cualquier lugar debajo de `node`.
func _stamp_features(node: Node) -> void:
	for child: Node in node.get_children():
		if child == self:
			continue
		if child is TerrainCarve:
			_carves.append(child as TerrainCarve)
		elif child is Path3D and _has_track_builder(child):
			_stamp_track(child as Path3D)
		elif child is Station:
			_stamp_rect(_relative_transform(child as Station), station_flat_size * 0.5)
		elif child is TrackLot:
			var lot := child as TrackLot
			_stamp_rect(_relative_transform(lot), lot.get_size() * 0.5)
		_stamp_features(child)


func _has_track_builder(path: Node) -> bool:
	for child: Node in path.get_children():
		if child is TrackBuilder:
			return true
	return false


# La curva, de a medio cuadro: cada punto aplana un círculo del ancho del corredor.
func _stamp_track(path: Path3D) -> void:
	var curve: Curve3D = path.curve
	if curve == null or curve.point_count < 2:
		return
	var length: float = curve.get_baked_length()
	var step: float = cell_size * 0.5
	var to_terrain: Transform3D = _relative_transform(path)
	for k: int in ceili(length / step) + 1:
		_stamp_point(to_terrain * curve.sample_baked(minf(k * step, length)))


# Baja el terreno a lo largo del arroyo: cada vértice toma el punto de la curva más cercano.
func _apply_carve(carve: TerrainCarve) -> void:
	var curve: Curve3D = carve.curve
	if curve == null or curve.point_count < 2:
		return
	var reach: float = carve.get_reach()
	var nearest := PackedFloat32Array()
	nearest.resize(_columns * _rows)
	nearest.fill(INF)
	var level := PackedFloat32Array()
	level.resize(_columns * _rows)
	var touched := PackedInt32Array()
	var to_terrain: Transform3D = _relative_transform(carve)
	var length: float = curve.get_baked_length()
	var step: float = cell_size * 0.5
	for k: int in ceili(length / step) + 1:
		var local: Vector3 = to_terrain * curve.sample_baked(minf(k * step, length))
		var first: Vector2i = _cell_of(Vector2(local.x, local.z) - Vector2(reach, reach))
		var last: Vector2i = _cell_of(Vector2(local.x, local.z) + Vector2(reach, reach)) + Vector2i.ONE
		for j: int in range(maxi(first.y, 0), mini(last.y, _rows - 1) + 1):
			for i: int in range(maxi(first.x, 0), mini(last.x, _columns - 1) + 1):
				var index: int = j * _columns + i
				var distance: float = vertex_position(i, j).distance_to(Vector2(local.x, local.z))
				if distance < nearest[index]:
					if nearest[index] == INF:
						touched.append(index)
					nearest[index] = distance
					level[index] = local.y
	for index: int in touched:
		var bed: float = level[index] - carve.depth
		var weight: float = TerrainCarve.carve_weight(nearest[index], carve.half_width, carve.bank_width)
		_heights[index] = minf(_heights[index], lerpf(bed, maxf(_heights[index], level[index]), weight))


func _stamp_point(local: Vector3) -> void:
	var reach: float = corridor_half_width + max_blend
	var first: Vector2i = _cell_of(Vector2(local.x, local.z) - Vector2(reach, reach))
	var last: Vector2i = _cell_of(Vector2(local.x, local.z) + Vector2(reach, reach)) + Vector2i.ONE
	for j: int in range(maxi(first.y, 0), mini(last.y, _rows - 1) + 1):
		for i: int in range(maxi(first.x, 0), mini(last.x, _columns - 1) + 1):
			var point: Vector2 = vertex_position(i, j)
			var distance: float = point.distance_to(Vector2(local.x, local.z)) - corridor_half_width
			_keep_closest(j * _columns + i, distance, local.y)


# Un rectángulo plano: `to_terrain` lleva de su marco (centro, X y Z) al del terreno.
func _stamp_rect(to_terrain: Transform3D, half_size: Vector2) -> void:
	var reach: float = max_blend
	var corners: Array[Vector3] = [
		to_terrain * Vector3(-half_size.x, 0.0, -half_size.y), to_terrain * Vector3(half_size.x, 0.0, -half_size.y),
		to_terrain * Vector3(-half_size.x, 0.0, half_size.y), to_terrain * Vector3(half_size.x, 0.0, half_size.y),
	]
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner: Vector3 in corners:
		low = Vector2(minf(low.x, corner.x), minf(low.y, corner.z))
		high = Vector2(maxf(high.x, corner.x), maxf(high.y, corner.z))
	var first: Vector2i = _cell_of(low - Vector2(reach, reach))
	var last: Vector2i = _cell_of(high + Vector2(reach, reach)) + Vector2i.ONE
	var to_rect: Transform3D = to_terrain.affine_inverse()
	for j: int in range(maxi(first.y, 0), mini(last.y, _rows - 1) + 1):
		for i: int in range(maxi(first.x, 0), mini(last.x, _columns - 1) + 1):
			var point: Vector2 = vertex_position(i, j)
			var inside: Vector3 = to_rect * Vector3(point.x, 0.0, point.y)
			_keep_closest(j * _columns + i, rect_distance(Vector2(inside.x, inside.z), half_size), to_terrain.origin.y)


func _keep_closest(index: int, distance: float, target: float) -> void:
	if distance < _flat_distance[index]:
		_flat_distance[index] = distance
		_flat_target[index] = target


func _cell_of(point: Vector2) -> Vector2i:
	var grid: Vector2 = (point - _origin) / cell_size
	return Vector2i(floori(grid.x), floori(grid.y))


# Transform de `node` en el marco del terreno.
func _relative_transform(node: Node3D) -> Transform3D:
	return global_transform.affine_inverse() * node.global_transform


func _build_mesh_and_shape() -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(_columns * _rows)
	normals.resize(_columns * _rows)
	colors.resize(_columns * _rows)
	for j: int in _rows:
		for i: int in _columns:
			var index: int = j * _columns + i
			var point: Vector2 = vertex_position(i, j)
			var height: float = _heights[index]
			vertices[index] = Vector3(point.x, height, point.y)
			var left: float = vertex_height(maxi(i - 1, 0), j)
			var right: float = vertex_height(mini(i + 1, _columns - 1), j)
			var back: float = vertex_height(i, maxi(j - 1, 0))
			var ahead: float = vertex_height(i, mini(j + 1, _rows - 1))
			var normal: Vector3 = Vector3(left - right, 2.0 * cell_size, back - ahead).normalized()
			normals[index] = normal
			colors[index] = ground_color(height, normal.y, rock_height)
	var indices := PackedInt32Array()
	indices.resize((_columns - 1) * (_rows - 1) * 6)
	var k: int = 0
	for j: int in _rows - 1:
		for i: int in _columns - 1:
			var a: int = j * _columns + i
			var b: int = a + 1
			var c: int = a + _columns
			var d: int = c + 1
			for corner: int in [a, b, d, a, d, c]:
				indices[k] = corner
				k += 1
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	# Así no importa para qué lado gira cada triángulo.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	mesh.surface_set_material(0, material)
	var instance: MeshInstance3D = get_node_or_null(MESH_NODE_NAME) as MeshInstance3D
	if instance == null:
		instance = MeshInstance3D.new()
		instance.name = MESH_NODE_NAME
		add_child(instance)
	instance.mesh = mesh
	var shape_node: CollisionShape3D = get_node_or_null(SHAPE_NODE_NAME) as CollisionShape3D
	if shape_node == null:
		shape_node = CollisionShape3D.new()
		shape_node.name = SHAPE_NODE_NAME
		add_child(shape_node)
	# La misma malla, triángulo por triángulo: el jugador pisa justo lo que se ve.
	shape_node.shape = mesh.create_trimesh_shape()


## Lógica pura: color del suelo según la altura y lo plano (normal.y, 1 en el plano).
static func ground_color(height: float, flatness: float, rock_from: float) -> Color:
	var slope: float = 1.0 - flatness
	var color: Color = COLOR_GRASS.lerp(COLOR_DIRT, smoothstep(DIRT_SLOPE_START, DIRT_SLOPE_FULL, slope))
	return color.lerp(COLOR_ROCK, smoothstep(rock_from, rock_from + ROCK_BLEND_M, height))
