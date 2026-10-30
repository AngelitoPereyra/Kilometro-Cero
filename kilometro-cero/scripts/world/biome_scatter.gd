class_name BiomeScatter
extends Node3D
## Vegetación repartida (tarea 62c.3b, D136, adelanta parte de la 68): pasto largo que se mueve con
## el viento, matas, cardos, piedras y árboles sobre el Terrain hermano, con semilla fija. No pisa
## vías, caminos (DirtRoad), arroyos (TerrainCarve), estaciones ni lotes. Se dibuja con un
## MultiMeshInstance3D por trozo y por pieza, cada uno con su distancia de vista. Sin choque: se
## camina a través del pasto y de los árboles de adorno (los que se talan siguen siendo Tree).
## Se arma en _ready, después del terreno (va debajo en la escena).

const GROUP: StringName = &"biome_scatter"
## Grilla de lo que no se pisa (metros por cuadro).
const BLOCK_CELL: float = 4.0
const CELL_HALF_DIAGONAL: float = BLOCK_CELL * 0.7072
## Hasta dónde se mira la distancia a vías, caminos y arroyos.
const BLOCK_REACH: float = 40.0
const WIND_SHADER: String = """
shader_type spatial;
render_mode cull_disabled;
uniform float strength = 0.18;
varying vec3 tint;
void vertex() {
	tint = COLOR.rgb;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 1.7 + world.x * 0.15 + world.z * 0.11) + 0.5 * sin(TIME * 3.1 + world.z * 0.3);
	VERTEX.x += sway * strength * UV.y;
	VERTEX.z += sway * strength * 0.5 * UV.y;
}
void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 1.0;
}
"""

@export var layers: Array[ScatterLayer] = []
@export var scatter_seed: int = 62
## Lado de cada trozo.
@export_range(16.0, 512.0, 1.0, "suffix:m") var chunk_size: float = 96.0
## Margen alrededor de estaciones y lotes.
@export_range(0.0, 30.0, 0.5, "suffix:m") var lot_margin: float = 3.0

var _terrain: Terrain
# Lo que se puso: id de capa -> posiciones globales.
var _placed: Dictionary[StringName, PackedVector3Array] = {}
var _chunks: int = 0
# Distancia a lo más cercano que no se pisa, por cuadro (0 adentro de estaciones y lotes).
var _block: PackedFloat32Array = PackedFloat32Array()
var _water: PackedFloat32Array = PackedFloat32Array()
var _block_origin: Vector2 = Vector2.ZERO
var _block_columns: int = 0
var _block_rows: int = 0


func _ready() -> void:
	add_to_group(GROUP)
	rebuild()


static func find_in(tree: SceneTree) -> BiomeScatter:
	return tree.get_first_node_in_group(GROUP) as BiomeScatter if tree != null else null


## Vuelve a repartir todo.
func rebuild() -> void:
	for child: Node in get_children():
		child.queue_free()
	_placed.clear()
	_chunks = 0
	_terrain = _find_terrain()
	if _terrain == null:
		push_warning("BiomeScatter %s: no hay Terrain." % name)
		return
	_build_block_grid()
	for index: int in layers.size():
		var layer: ScatterLayer = layers[index]
		if layer != null:
			_scatter(layer, index)
	_block = PackedFloat32Array()
	_water = PackedFloat32Array()


func get_positions(layer_id: StringName) -> PackedVector3Array:
	return _placed.get(layer_id, PackedVector3Array())


func get_instance_count(layer_id: StringName = &"") -> int:
	if layer_id != &"":
		return get_positions(layer_id).size()
	var total: int = 0
	for positions: PackedVector3Array in _placed.values():
		total += positions.size()
	return total


## Cuántos MultiMeshInstance3D se armaron.
func get_chunk_count() -> int:
	return _chunks


## Lógica pura: separación de la grilla con jitter para una densidad por 100 m².
static func spacing_for(density: float) -> float:
	return 10.0 / sqrt(maxf(density, 0.0001))


## Las piezas de cada forma: [{mesh, material}], con la base en y 0.
static func make_parts(kind: ScatterLayer.Kind) -> Array[Dictionary]:
	match kind:
		ScatterLayer.Kind.GRASS:
			var wind := ShaderMaterial.new()
			var shader := Shader.new()
			shader.code = WIND_SHADER
			wind.shader = shader
			return [{"mesh": _grass_mesh(), "material": wind}]
		ScatterLayer.Kind.BUSH:
			return [_part(_sphere(0.7, 0.9), Vector3(0.0, 0.35, 0.0), Color(0.25, 0.4, 0.2))]
		ScatterLayer.Kind.THISTLE:
			return [_part(_cylinder(0.03, 0.03, 0.9), Vector3(0.0, 0.45, 0.0), Color(0.45, 0.52, 0.4)),
				_part(_sphere(0.13, 0.2), Vector3(0.0, 0.95, 0.0), Color(0.55, 0.3, 0.6))]
		ScatterLayer.Kind.ROCK:
			return [_part(_sphere(1.0, 1.1), Vector3(0.0, 0.15, 0.0), Color(0.6, 0.58, 0.54))]
		ScatterLayer.Kind.TREE:
			return [_part(_cylinder(0.22, 0.3, 3.0), Vector3(0.0, 1.5, 0.0), Color(0.42, 0.28, 0.15)),
				_part(_sphere(2.2, 3.4), Vector3(0.0, 4.2, 0.0), Color(0.24, 0.45, 0.2))]
		ScatterLayer.Kind.EUCALYPTUS:
			return [_part(_cylinder(0.16, 0.26, 9.0), Vector3(0.0, 4.5, 0.0), Color(0.78, 0.76, 0.7)),
				_part(_sphere(2.0, 6.0), Vector3(0.0, 10.0, 0.0), Color(0.36, 0.46, 0.38))]
		ScatterLayer.Kind.WILLOW:
			return [_part(_cylinder(0.25, 0.35, 3.0), Vector3(0.0, 1.5, 0.0), Color(0.4, 0.33, 0.24)),
				_part(_sphere(3.0, 4.0), Vector3(0.0, 3.6, 0.0), Color(0.45, 0.58, 0.3))]
	return []


func _scatter(layer: ScatterLayer, index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = scatter_seed * 7919 + index * 104729
	var noise := FastNoiseLite.new()
	noise.seed = scatter_seed + index
	noise.frequency = layer.noise_frequency
	var bounds: Rect2 = _terrain_bounds()
	var area: Rect2 = layer.area.intersection(bounds) if layer.area.has_area() else bounds
	var step: float = spacing_for(layer.density)
	var by_chunk: Dictionary[Vector2i, Array] = {}
	var positions := PackedVector3Array()
	var z: float = area.position.y + step * 0.5
	while z < area.end.y:
		var x: float = area.position.x + step * 0.5
		while x < area.end.x:
			var point := Vector2(x + rng.randf_range(-0.45, 0.45) * step, z + rng.randf_range(-0.45, 0.45) * step)
			var yaw: float = rng.randf() * TAU
			var size: float = rng.randf_range(layer.min_scale, layer.max_scale)
			x += step
			if layer.noise_threshold > -1.0 and noise.get_noise_2d(point.x, point.y) < layer.noise_threshold:
				continue
			if not _is_free(point, layer):
				continue
			var ground: float = _terrain.height_at(Vector3(point.x, 0.0, point.y))
			if is_nan(ground):
				continue
			if layer.max_slope < 5.0 and _slope_at(point, ground) > layer.max_slope:
				continue
			var at := Vector3(point.x, ground, point.y)
			positions.append(at)
			var key := Vector2i(floori(point.x / chunk_size), floori(point.y / chunk_size))
			if not by_chunk.has(key):
				by_chunk[key] = []
			by_chunk[key].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), at))
		z += step
	_placed[layer.id] = positions
	var parts: Array[Dictionary] = make_parts(layer.kind)
	for key: Vector2i in by_chunk:
		var center := Vector3((key.x + 0.5) * chunk_size, 0.0, (key.y + 0.5) * chunk_size)
		var transforms: Array = by_chunk[key]
		for part_index: int in parts.size():
			var part: Dictionary = parts[part_index]
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = part["mesh"]
			multimesh.instance_count = transforms.size()
			for i: int in transforms.size():
				var placed: Transform3D = transforms[i]
				multimesh.set_instance_transform(i, Transform3D(placed.basis, placed.origin - center))
			var instance := MultiMeshInstance3D.new()
			instance.name = "%s_%d_%d_%d" % [layer.id, key.x, key.y, part_index]
			instance.multimesh = multimesh
			instance.material_override = part["material"]
			instance.visibility_range_end = layer.view_distance
			instance.visibility_range_end_margin = layer.view_distance * 0.1
			instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if layer.kind == ScatterLayer.Kind.GRASS else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(instance)
			instance.global_position = center
			_chunks += 1


func _is_free(point: Vector2, layer: ScatterLayer) -> bool:
	var cell := Vector2i(floori((point.x - _block_origin.x) / BLOCK_CELL), floori((point.y - _block_origin.y) / BLOCK_CELL))
	if cell.x < 0 or cell.y < 0 or cell.x >= _block_columns or cell.y >= _block_rows:
		return false
	var index: int = cell.y * _block_columns + cell.x
	# La distancia es la del centro del cuadro: se descuenta medio cuadro en diagonal.
	if _block[index] - CELL_HALF_DIAGONAL <= layer.keep_away:
		return false
	if layer.near_water > 0.0 and _water[index] > layer.near_water:
		return false
	return true


func _slope_at(point: Vector2, ground: float) -> float:
	var east: float = _terrain.height_at(Vector3(point.x + 2.0, 0.0, point.y))
	var north: float = _terrain.height_at(Vector3(point.x, 0.0, point.y + 2.0))
	if is_nan(east) or is_nan(north):
		return 0.0
	return Vector2(east - ground, north - ground).length() / 2.0


# Distancia (recortada a BLOCK_REACH) a vías, caminos y arroyos; 0 en estaciones y lotes; y aparte la
# distancia a la orilla de los arroyos.
func _build_block_grid() -> void:
	var bounds: Rect2 = _terrain_bounds()
	_block_origin = bounds.position
	_block_columns = ceili(bounds.size.x / BLOCK_CELL) + 1
	_block_rows = ceili(bounds.size.y / BLOCK_CELL) + 1
	_block = PackedFloat32Array()
	_block.resize(_block_columns * _block_rows)
	_block.fill(BLOCK_REACH)
	_water = PackedFloat32Array()
	_water.resize(_block_columns * _block_rows)
	_water.fill(INF)
	var root: Node = get_parent() if get_parent() != null else self
	for node: Node in root.find_children("*", "", true, false):
		if node is TerrainCarve:
			var carve := node as TerrainCarve
			_stamp_path(carve, carve.half_width, _block)
			_stamp_path(carve, carve.half_width, _water)
		elif node is DirtRoad:
			_stamp_path(node as Path3D, (node as DirtRoad).width * 0.5, _block)
		elif node is Path3D and _has_track_builder(node):
			_stamp_path(node as Path3D, 1.5, _block)
		elif node is Station:
			_stamp_rect(node as Node3D, _terrain.station_flat_size * 0.5 + Vector2.ONE * lot_margin)
		elif node is TrackLot:
			_stamp_rect(node as Node3D, (node as TrackLot).get_size() * 0.5 + Vector2.ONE * lot_margin)


func _stamp_path(path: Path3D, half_width: float, grid: PackedFloat32Array) -> void:
	var curve: Curve3D = path.curve
	if curve == null or curve.point_count < 2:
		return
	var length: float = curve.get_baked_length()
	var reach: int = ceili(BLOCK_REACH / BLOCK_CELL)
	for k: int in ceili(length / BLOCK_CELL) + 1:
		var point: Vector3 = path.to_global(curve.sample_baked(minf(k * BLOCK_CELL, length)))
		var center := Vector2i(floori((point.x - _block_origin.x) / BLOCK_CELL), floori((point.z - _block_origin.y) / BLOCK_CELL))
		for j: int in range(maxi(center.y - reach, 0), mini(center.y + reach, _block_rows - 1) + 1):
			for i: int in range(maxi(center.x - reach, 0), mini(center.x + reach, _block_columns - 1) + 1):
				var cell := Vector2(_block_origin.x + (i + 0.5) * BLOCK_CELL, _block_origin.y + (j + 0.5) * BLOCK_CELL)
				var distance: float = maxf(cell.distance_to(Vector2(point.x, point.z)) - half_width, 0.0)
				var index: int = j * _block_columns + i
				if distance < grid[index]:
					grid[index] = distance


func _stamp_rect(node: Node3D, half_size: Vector2) -> void:
	var to_rect: Transform3D = node.global_transform.affine_inverse()
	var radius: float = half_size.length()
	var center: Vector3 = node.global_position
	var first := Vector2i(floori((center.x - radius - _block_origin.x) / BLOCK_CELL), floori((center.z - radius - _block_origin.y) / BLOCK_CELL))
	var last := Vector2i(floori((center.x + radius - _block_origin.x) / BLOCK_CELL), floori((center.z + radius - _block_origin.y) / BLOCK_CELL))
	for j: int in range(maxi(first.y, 0), mini(last.y, _block_rows - 1) + 1):
		for i: int in range(maxi(first.x, 0), mini(last.x, _block_columns - 1) + 1):
			var inside: Vector3 = to_rect * Vector3(_block_origin.x + (i + 0.5) * BLOCK_CELL, center.y, _block_origin.y + (j + 0.5) * BLOCK_CELL)
			if Terrain.rect_distance(Vector2(inside.x, inside.z), half_size) <= 0.0:
				_block[j * _block_columns + i] = 0.0


func _has_track_builder(path: Node) -> bool:
	for child: Node in path.get_children():
		if child is TrackBuilder:
			return true
	return false


func _find_terrain() -> Terrain:
	var parent: Node = get_parent()
	if parent != null:
		for child: Node in parent.get_children():
			if child is Terrain:
				return child as Terrain
	return get_tree().get_first_node_in_group(Terrain.GROUP) as Terrain if is_inside_tree() else null


# El rectángulo global (x, z) del terreno (no se gira).
func _terrain_bounds() -> Rect2:
	var half: Vector2 = _terrain.size * 0.5
	var center := Vector2(_terrain.global_position.x, _terrain.global_position.z)
	return Rect2(center - half, _terrain.size)


static func _part(mesh: Mesh, offset: Vector3, color: Color) -> Dictionary:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.append_from(mesh, 0, Transform3D(Basis.IDENTITY, offset))
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return {"mesh": surface.commit(), "material": material}


static func _sphere(radius: float, height: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 6
	return mesh


static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 6
	mesh.rings = 1
	return mesh


# Tres planos cruzados que se afinan arriba; UV.y es la altura (el viento mueve la punta).
static func _grass_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := Color(0.32, 0.45, 0.2)
	var tip := Color(0.7, 0.72, 0.38)
	for blade: int in 3:
		var angle: float = blade * PI / 3.0
		var side := Vector3(cos(angle), 0.0, sin(angle)) * 0.45
		var top_side: Vector3 = side * 0.35
		var corners: Array[Vector3] = [-side, side, top_side + Vector3.UP * 0.95, -top_side + Vector3.UP * 0.95]
		var heights: Array[float] = [0.0, 0.0, 1.0, 1.0]
		for corner: int in [0, 1, 2, 0, 2, 3]:
			surface.set_color(base.lerp(tip, heights[corner]))
			surface.set_uv(Vector2(0.0, heights[corner]))
			surface.set_normal(Vector3.UP)
			surface.add_vertex(corners[corner])
	return surface.commit()
