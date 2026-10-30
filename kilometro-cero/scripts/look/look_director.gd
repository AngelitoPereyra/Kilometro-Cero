class_name LookDirector
extends Node
## La estética base de una escena (tarea 62c.3e, D140): repinta con la paleta todo lo que hay y lo
## que aparece después (LookPainter), y según la hora del juego mueve el sol (o la luna) y cambia
## su luz, la luz ambiente, el cielo de degradado, la niebla y el horizonte (DayLook). Adelanta la
## parte visual de la 65: GameClock no cambia.
## El norte del mapa es +z (Azul queda al norte de Olavarría) y el este es -x; el sol sale por el
## este, pasa por el norte (hemisferio sur) y se pone por el oeste.

const GROUP: StringName = &"look_director"
const NORTH: Vector3 = Vector3(0.0, 0.0, 1.0)
const EAST: Vector3 = Vector3(-1.0, 0.0, 0.0)

@export var look: DayLook
@export var world_environment: WorldEnvironment
@export var sun: DirectionalLight3D
## Opcional: el horizonte toma los colores de la hora.
@export var horizon: HorizonRing
## Repintar con la paleta la escena (el padre de este nodo) y lo que se agregue después.
@export var paint_scene: bool = true
## Hora fija, para pruebas y fotos; -1 sigue al reloj del juego.
@export_range(-1.0, 24.0, 0.25) var fixed_hour: float = -1.0
@export_range(0.0, 24.0, 0.25) var sunrise_hour: float = 6.0
@export_range(0.0, 24.0, 0.25) var sunset_hour: float = 20.0
## Qué tan alto llega el sol al mediodía y la luna a medianoche.
@export_range(5.0, 89.0, 1.0, "suffix:°") var sun_max_elevation: float = 62.0
@export_range(5.0, 89.0, 1.0, "suffix:°") var moon_max_elevation: float = 40.0

var _painter: LookPainter = LookPainter.new()
var _sky_material: ShaderMaterial
# Lo que llegó al árbol y falta repintar (se repinta al cuadro siguiente, ya con sus materiales).
var _pending: Array[Node] = []


func _ready() -> void:
	add_to_group(GROUP)
	Palette.ensure_globals()
	if world_environment != null and world_environment.environment != null and world_environment.environment.sky != null:
		_sky_material = world_environment.environment.sky.sky_material as ShaderMaterial
	if paint_scene:
		get_tree().node_added.connect(_on_node_added)
		_queue(get_parent() if get_parent() != null else self)
	apply(get_hour())


static func find_in(tree: SceneTree) -> LookDirector:
	return tree.get_first_node_in_group(GROUP) as LookDirector if tree != null else null


func _process(_delta: float) -> void:
	if not _pending.is_empty():
		var batch: Array[Node] = _pending
		_pending = []
		for node: Node in batch:
			if is_instance_valid(node) and node.is_inside_tree():
				_painter.paint_tree(node)
	apply(get_hour())


func get_hour() -> float:
	if fixed_hour >= 0.0:
		return fixed_hour
	return GameState.clock.time_of_day


func get_painter() -> LookPainter:
	return _painter


## Pone la escena como se ve a esa hora.
func apply(hour: float) -> void:
	if look == null:
		return
	var key: DayLookKey = look.sample(hour)
	if sun != null:
		var toward: Vector3 = light_direction(hour, sunrise_hour, sunset_hour, sun_max_elevation, moon_max_elevation)
		sun.global_basis = Basis.looking_at(-toward, Vector3.UP if absf(toward.y) < 0.99 else Vector3.FORWARD)
		sun.light_color = key.sun_color
		sun.light_energy = key.sun_energy
	if world_environment != null and world_environment.environment != null:
		var environment: Environment = world_environment.environment
		environment.ambient_light_color = key.ambient_color
		environment.ambient_light_energy = key.ambient_energy
		environment.fog_light_color = key.fog_color
	if _sky_material != null:
		_sky_material.set_shader_parameter(&"top_color", key.sky_top)
		_sky_material.set_shader_parameter(&"horizon_color", key.sky_horizon)
		_sky_material.set_shader_parameter(&"ground_color", key.horizon_near)
		_sky_material.set_shader_parameter(&"sun_color", key.sun_color)
		_sky_material.set_shader_parameter(&"stars", key.stars)
	if horizon != null:
		horizon.set_colors(key.horizon_near, key.horizon_far)


## Lógica pura: hacia dónde está la luz a esa hora (vector unitario que apunta al sol de día y a la
## luna de noche). Sale por el este, culmina por el norte y se pone por el oeste; nunca baja de 4°.
static func light_direction(hour: float, sunrise: float, sunset: float, sun_elevation: float, moon_elevation: float) -> Vector3:
	var now: float = fposmod(hour, 24.0)
	var day_length: float = fposmod(sunset - sunrise, 24.0)
	var since_sunrise: float = fposmod(now - sunrise, 24.0)
	var progress: float
	var top: float
	if since_sunrise <= day_length:
		progress = since_sunrise / maxf(day_length, 0.01)
		top = sun_elevation
	else:
		progress = (since_sunrise - day_length) / maxf(24.0 - day_length, 0.01)
		top = moon_elevation
	var angle: float = PI * progress
	var flat: Vector3 = EAST * cos(angle) + NORTH * sin(angle)
	var elevation: float = deg_to_rad(lerpf(4.0, top, sin(angle)))
	return (flat * cos(elevation) + Vector3.UP * sin(elevation)).normalized()


func _on_node_added(node: Node) -> void:
	if node is MeshInstance3D or node is MultiMeshInstance3D:
		_queue(node)


func _queue(node: Node) -> void:
	_pending.append(node)
