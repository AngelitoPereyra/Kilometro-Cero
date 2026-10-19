class_name VehicleColliderInstaller extends Node
## Provisorio, para las pruebas: agrega un cuerpo físico a cada Vehicle que no
## tenga uno, con una caja del tamaño de su mesh. Se borra cuando exista la escena
## definitiva del vehículo (tareas 16 y 23), que ya traerá su propio cuerpo.
## Un Vehicle es un PathFollow3D, que NO es un cuerpo físico: una CollisionShape3D
## colgada de él no hace nada. Por eso la forma va dentro de un AnimatableBody3D.

const BODY_NAME: String = "CuerpoFisico"


func _ready() -> void:
	# Dos cuadros de física de espera: así los vehículos que genera el script de
	# la prueba ya existen y están en su grupo.
	await get_tree().physics_frame
	await get_tree().physics_frame
	for node: Node in get_tree().get_nodes_in_group(Vehicle.GROUP):
		var vehicle := node as Vehicle
		if vehicle != null:
			_install(vehicle)


func _install(vehicle: Vehicle) -> void:
	# Si ya tiene un cuerpo físico propio, no se toca.
	for child: Node in vehicle.get_children():
		if child is CollisionObject3D:
			return
	var mesh_node: MeshInstance3D = _first_mesh(vehicle)
	if mesh_node == null or mesh_node.mesh == null:
		push_warning("VehicleColliderInstaller: el vehículo '%s' no tiene un MeshInstance3D con mesh; no se le agrega colisión." % vehicle.name)
		return

	# Posición y giro del mesh respecto del vehículo, para que la caja coincida con lo que se ve.
	var local: Transform3D = vehicle.global_transform.affine_inverse() * mesh_node.global_transform
	var bounds: AABB = mesh_node.mesh.get_aabb()
	var box := BoxShape3D.new()
	box.size = (local.basis.get_scale() * bounds.size).abs()
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.transform = Transform3D(local.basis.orthonormalized(), local * bounds.get_center())

	# AnimatableBody3D: lo mueve el PathFollow3D (no la física). sync_to_physics queda
	# APAGADO: ese modo solo escucha los cambios del propio nodo y no los de su padre,
	# y acá quien se mueve es el padre (el Vehicle, que ya avanza en _physics_process).
	var body := AnimatableBody3D.new()
	body.name = BODY_NAME
	body.sync_to_physics = false
	# Capa 1 (mundo): es contra la que chocan los objetos sueltos.
	body.collision_layer = WorldItem.LAYER_WORLD
	body.collision_mask = 0
	body.add_child(shape)
	vehicle.add_child(body)


func _first_mesh(root: Node) -> MeshInstance3D:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node != null:
			return mesh_node
	return null
