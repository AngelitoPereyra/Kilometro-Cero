class_name MeshBatcher
extends RefCounted
## Junta las mallas quietas de un modelo armado con muchas piezas (tarea 62c.3f): cada parcela tiene
## más de 150 MeshInstance3D (postes, vacas, árboles) y con todos los lotes ocupados eran miles de
## llamadas de dibujo por cuadro (los tirones del día 7). Junta las piezas que comparten material en
## una sola malla por material, en el marco del nodo raíz, y borra las sueltas. Se usa cuando ya se
## pintaron con la paleta (LookPainter: los materiales quedan compartidos por color) y cuando ya no
## se mueven (después de brotar). No toca lo que tiene hijos, la marca LookPainter.KEEP_META, ni
## lo que está escondido.

const MERGED_PREFIX: String = "Junta"


## Lógica pura: la clave con que se agrupa una superficie (el material y qué datos trae).
static func group_key(material: Material, format: int) -> String:
	return "%d|%d" % [material.get_instance_id() if material != null else 0, format]


## Qué datos trae una superficie (normales, tangentes, colores, UV, índices), como bits de
## Mesh.ARRAY_FORMAT_*: solo se juntan superficies que traen lo mismo.
static func surface_format(arrays: Array) -> int:
	var format: int = 0
	var bits: Dictionary[int, int] = {
		Mesh.ARRAY_NORMAL: Mesh.ARRAY_FORMAT_NORMAL,
		Mesh.ARRAY_TANGENT: Mesh.ARRAY_FORMAT_TANGENT,
		Mesh.ARRAY_COLOR: Mesh.ARRAY_FORMAT_COLOR,
		Mesh.ARRAY_TEX_UV: Mesh.ARRAY_FORMAT_TEX_UV,
		Mesh.ARRAY_TEX_UV2: Mesh.ARRAY_FORMAT_TEX_UV2,
		Mesh.ARRAY_INDEX: Mesh.ARRAY_FORMAT_INDEX,
	}
	for slot: int in bits:
		if arrays.size() > slot and arrays[slot] != null:
			format |= bits[slot]
	return format


## Junta las piezas de `root`. `view_distance` (> 0) es la distancia de vista de las mallas juntas.
## Devuelve cuántas piezas juntó (0 si no había nada que juntar).
static func merge(root: Node3D, view_distance: float = 0.0) -> int:
	if root == null or not root.is_inside_tree():
		return 0
	var to_root: Transform3D = root.global_transform.affine_inverse()
	var groups: Dictionary[String, Array] = {}
	var materials: Dictionary[String, Material] = {}
	var shadows: Dictionary[String, int] = {}
	var merged: Array[MeshInstance3D] = []
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if not _can_merge(instance):
			continue
		var relative: Transform3D = to_root * instance.global_transform
		for surface: int in instance.mesh.get_surface_count():
			var material: Material = instance.get_active_material(surface)
			var key: String = group_key(material, surface_format(instance.mesh.surface_get_arrays(surface)))
			if not groups.has(key):
				groups[key] = []
				materials[key] = material
				shadows[key] = instance.cast_shadow
			groups[key].append([instance.mesh, surface, relative])
		merged.append(instance)
	if merged.size() < 2:
		return 0
	var index: int = 0
	for key: String in groups:
		var surface_tool := SurfaceTool.new()
		surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for entry: Array in groups[key]:
			surface_tool.append_from(entry[0], entry[1], entry[2])
		var joined := MeshInstance3D.new()
		joined.name = "%s%d" % [MERGED_PREFIX, index]
		joined.mesh = surface_tool.commit()
		joined.material_override = materials[key]
		joined.cast_shadow = shadows[key] as GeometryInstance3D.ShadowCastingSetting
		if view_distance > 0.0:
			joined.visibility_range_end = view_distance
			joined.visibility_range_end_margin = view_distance * 0.1
		# Ya está pintada: que LookPainter no la vuelva a mirar.
		joined.set_meta(LookPainter.KEEP_META, true)
		root.add_child(joined)
		index += 1
	for instance: MeshInstance3D in merged:
		instance.get_parent().remove_child(instance)
		instance.queue_free()
	return merged.size()


static func _can_merge(instance: MeshInstance3D) -> bool:
	return instance != null and instance.mesh != null and instance.get_child_count() == 0 \
		and instance.is_visible_in_tree() and not instance.has_meta(LookPainter.KEEP_META) \
		and not String(instance.name).begins_with(MERGED_PREFIX) \
		and instance.mesh.get_surface_count() > 0 and _is_triangles(instance.mesh)


static func _is_triangles(mesh: Mesh) -> bool:
	var array_mesh := mesh as ArrayMesh
	if array_mesh == null:
		return mesh is PrimitiveMesh
	for surface: int in array_mesh.get_surface_count():
		if array_mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			return false
	return true
