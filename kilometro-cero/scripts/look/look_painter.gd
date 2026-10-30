class_name LookPainter
extends RefCounted
## Repinta con la paleta (tarea 62c.3e, D140) los materiales de bosquejo que ya están: cada
## StandardMaterial3D liso pasa al material compartido del mundo, con la celda de Palette más
## parecida a su color. Así lo que ya existe (tren, vagones, estaciones, parcelas, objetos) entra
## en la paleta y en la vitalidad sin rehacer cada escena, y lo que se arme después también.
## No toca lo que brilla, lo transparente, lo que no tiene sombreado ni lo que tiene textura; ni los
## nodos con la marca KEEP_META (los que cambian su propio color, como el desgaste de la vía).
## Cada material se convierte una sola vez: todos los que lo comparten reciben el mismo.

const KEEP_META: StringName = &"look_keep"

# Material original -> el que lo reemplaza (o el mismo si no se toca).
var _converted: Dictionary[Material, Material] = {}
var _painted: int = 0


## Lógica pura: si ese material se puede pasar a la paleta.
static func can_paint(material: BaseMaterial3D) -> bool:
	return material != null \
		and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
		and material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL \
		and not material.emission_enabled \
		and material.albedo_texture == null \
		and material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED \
		and material.albedo_color.a > 0.99


## El material de la paleta que reemplaza a ese, o el mismo si no se toca.
func convert_material(material: Material) -> Material:
	if material == null:
		return null
	if _converted.has(material):
		return _converted[material]
	var result: Material = material
	var base := material as BaseMaterial3D
	if can_paint(base):
		var double_sided: bool = base.cull_mode == BaseMaterial3D.CULL_DISABLED
		if base.vertex_color_use_as_albedo:
			result = Palette.vertex_material(double_sided)
		else:
			result = Palette.material_for(base.albedo_color, double_sided)
	_converted[material] = result
	return result


## Repinta ese nodo y todo lo que tiene adentro (también los hijos internos).
func paint_tree(root: Node) -> void:
	paint_node(root)
	for child: Node in root.get_children(true):
		paint_tree(child)


func paint_node(node: Node) -> void:
	if node.has_meta(KEEP_META):
		return
	if node is MeshInstance3D:
		_paint_mesh_instance(node as MeshInstance3D)
	elif node is MultiMeshInstance3D:
		_paint_multimesh_instance(node as MultiMeshInstance3D)


## Cuántas superficies o nodos cambió.
func get_painted_count() -> int:
	return _painted


func _paint_mesh_instance(instance: MeshInstance3D) -> void:
	if instance.material_override != null:
		_set_override(instance)
		return
	if instance.mesh == null:
		return
	for surface: int in instance.mesh.get_surface_count():
		var current: Material = instance.get_surface_override_material(surface)
		if current == null:
			current = instance.mesh.surface_get_material(surface)
		var painted: Material = convert_material(current)
		if painted != current:
			instance.set_surface_override_material(surface, painted)
			_painted += 1


func _paint_multimesh_instance(instance: MultiMeshInstance3D) -> void:
	if instance.material_override != null:
		_set_override(instance)
		return
	if instance.multimesh == null or instance.multimesh.mesh == null or instance.multimesh.mesh.get_surface_count() != 1:
		return
	var current: Material = instance.multimesh.mesh.surface_get_material(0)
	var painted: Material = convert_material(current)
	if painted != current:
		instance.material_override = painted
		_painted += 1


func _set_override(instance: GeometryInstance3D) -> void:
	var painted: Material = convert_material(instance.material_override)
	if painted != instance.material_override:
		instance.material_override = painted
		_painted += 1
