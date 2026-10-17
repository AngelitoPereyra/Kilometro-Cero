extends Node3D
## Prueba de la tarea 6: la vía hecha a mano existe, es larga y plana, y el terreno
## está a la altura esperada (y = 0), que es donde van a apoyarse los objetos.

const LARGO_MINIMO_M: float = 100.0  # la tarea pide ~200 m; margen por si movés puntos
const TOLERANCIA_M: float = 0.01

@onready var _track: ManualTrack = $Track
@onready var _ground: StaticBody3D = $Ground

var _fallos: int = 0


func _ready() -> void:
	_comprobar_via()
	# El mundo de física recién está listo después del primer cuadro de física.
	await get_tree().physics_frame
	_comprobar_terreno()

	if _fallos == 0:
		print("Tarea 6: todas las comprobaciones pasaron.")
	else:
		push_error("Tarea 6: fallaron %d comprobaciones." % _fallos)


func _comprobar_via() -> void:
	var curva: Curve3D = _track.curve
	_comprobar(curva != null and curva.point_count >= 2, "La vía tiene una curva con al menos 2 puntos")
	if curva == null or curva.point_count < 2:
		return
	var largo: float = curva.get_baked_length()
	_comprobar(largo >= LARGO_MINIMO_M, "La vía mide %.1f m (mínimo %.0f)" % [largo, LARGO_MINIMO_M])
	var puntos: PackedVector3Array = curva.get_baked_points()
	var desnivel: float = absf(puntos[0].y - puntos[puntos.size() - 1].y)
	_comprobar(desnivel < TOLERANCIA_M, "La vía es plana (desnivel %.3f m)" % desnivel)


func _comprobar_terreno() -> void:
	_comprobar(_ground.get_collision_layer_value(1), "El terreno está en la capa 1 (mundo)")
	var espacio: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	# Rayo vertical de 10 m arriba a 10 m abajo, a mitad de la vía. La máscara 1 = capa "mundo".
	var consulta := PhysicsRayQueryParameters3D.create(Vector3(0.0, 10.0, -100.0), Vector3(0.0, -10.0, -100.0), 1)
	var impacto: Dictionary = espacio.intersect_ray(consulta)
	_comprobar(not impacto.is_empty(), "Un rayo vertical encuentra el terreno")
	if not impacto.is_empty():
		var altura: float = (impacto["position"] as Vector3).y
		_comprobar(absf(altura) < TOLERANCIA_M, "La superficie del terreno está en y = 0 (medido: %.3f)" % altura)


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
