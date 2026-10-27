class_name TrackSwitch
extends RefCounted
## Un cambio de vía (tarea 61b, D113): una punta de vía (la del lado de la aguja) que sigue por
## dos o más vías. Lo arma RailNetwork donde se tocan las puntas; no es un nodo. Un tren que llega
## por la aguja sigue por la vía que marca `state`; uno que llega desde una de las otras vías pasa
## siempre (como un cambio de resorte). La palanca (SwitchLever) lo mueve con F; los automáticos lo
## mueven solos al pasar (Vehicle.switch_chooser).
## Lógica sin escena salvo is_fouled, que mira los vehículos del árbol.

signal state_changed(state: int)

## Cuánto más allá del medio vehículo tiene que estar un vehículo para que se pueda mover el cambio.
const FOULING_MARGIN: float = 1.0

var id: int = 0
## Dónde se juntan las vías (global).
var point: Vector3
## Hacia dónde sale un tren que deja la aguja por las otras vías (global, horizontal).
var direction: Vector3 = Vector3.FORWARD
## La punta del lado de la aguja: su curva y si es el final (true) o el principio de la curva.
var toe_path: Path3D
var toe_at_end: bool
## Por dónde puede seguir: [Path3D, bool entra por el final de la curva].
var options: Array = []
var state: int = 0
var station_id: StringName
var lever: SwitchLever


func option_count() -> int:
	return options.size()


func get_option_path(index: int) -> Path3D:
	return options[index][0] as Path3D if index >= 0 and index < options.size() else null


func get_option_track(index: int) -> TrackSegment:
	return RailNetwork.track_of(get_option_path(index))


## Texto de una salida: "vía principal", "vía de cruce", "línea a Pueblo".
func option_label(index: int) -> String:
	var track: TrackSegment = get_option_track(index)
	var station_track := track as StationTrack
	if station_track != null:
		return station_track.get_label()
	if track != null:
		var other: StringName = track.other_station(station_id)
		return "línea a %s" % _station_name(other if other != &"" else track.to_station)
	return "vía %d" % (index + 1)


## La salida que sigue a la actual (la palanca recorre todas en orden).
func next_state() -> int:
	return (state + 1) % maxi(1, options.size())


## Pone el cambio en `index`. Con un vehículo encima no se mueve (devuelve false), salvo `force`
## (lo usan los automáticos, que ya reservaron el camino). Devuelve true si quedó en `index`.
func set_state(index: int, force: bool = false) -> bool:
	if index < 0 or index >= options.size():
		return false
	if index == state:
		return true
	if not force and is_fouled():
		return false
	state = index
	state_changed.emit(state)
	return true


## Mueve la palanca a la salida que sigue.
func cycle() -> bool:
	return set_state(next_state())


## Si hay algún vehículo encima del cambio (no se puede mover la aguja debajo de un tren).
func is_fouled() -> bool:
	if toe_path == null or not toe_path.is_inside_tree():
		return false
	for node: Node in toe_path.get_tree().get_nodes_in_group(Vehicle.GROUP):
		var vehicle := node as Vehicle
		if vehicle == null or vehicle.data == null:
			continue
		if vehicle.global_position.distance_to(point) < vehicle.data.length * 0.5 + FOULING_MARGIN:
			return true
	return false


## Si la salida `index` es la principal o una línea (donde queda el cambio al armarse).
func is_main_option(index: int) -> bool:
	var track: TrackSegment = get_option_track(index)
	var station_track := track as StationTrack
	return station_track == null or station_track.is_main()


func _station_name(station: StringName) -> String:
	if toe_path != null and toe_path.is_inside_tree():
		var node: Station = Station.find(toe_path.get_tree(), station)
		if node != null:
			return node.get_display_name()
	return String(station)
