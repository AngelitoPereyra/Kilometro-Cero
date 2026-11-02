class_name Sleeper
extends Node
## Dormir y desmayarse (tarea 62c.3h, D143; completa D88). De noche (de las 19:00 a las 5:00) el
## jugador duerme hasta las 7:00 en una cama (Bed: la del vagón cocina gratis o la de una taberna,
## pagando) o acampando donde esté con N (acción `camp`): en el suelo, fuera del tren y sin jabalíes
## cerca. Dormir no cura y no guarda (eso es la tarea 65). Al dormir en una cama, queda como la
## última: si la salud llega a 0, el jugador se desmaya y despierta ahí a la mañana siguiente con
## `Health.faint_health`, sin perder nada (el desmayo no adelanta el reloj). Sin cama todavía, despierta donde empezó la partida.
## Hijo directo de Player. La pantalla se funde a negro (CanvasLayer propio) mientras pasa la noche.

signal slept(hours: float, where: String)
## &"day", &"in_cab", &"on_train", &"in_air", &"boars", &"money", &"busy".
signal sleep_failed(reason: StringName)
signal fainted

## Desde qué hora y hasta cuál se puede dormir.
const SLEEP_FROM: float = 19.0
const SLEEP_UNTIL: float = 5.0
## A qué hora se despierta.
const WAKE_HOUR: float = 7.0
## Sin jabalíes a menos de esto para acampar.
const CAMP_SAFE_RADIUS: float = 30.0

## Segundos del fundido a negro (0: todo en el acto, para las pruebas).
@export_range(0.0, 3.0, 0.05, "suffix:s") var fade_seconds: float = 0.6

## La última cama donde durmió (ahí despierta si se desmaya).
var last_bed: Bed
## Donde empezó la partida: despierta ahí si se desmaya sin haber dormido en una cama.
var start_point: Vector3

var _player: Player
var _busy: bool = false
var _faint_pending: bool = false
var _overlay: ColorRect


## Si a esa hora se puede dormir. Lógica pura.
static func can_sleep_at(hour: float) -> bool:
	return hour >= SLEEP_FROM or hour < SLEEP_UNTIL


## Horas hasta la próxima hora de despertar (las 7:00 de hoy si todavía no son, si no las de
## mañana). Lógica pura.
static func hours_until_wake(hour: float) -> float:
	if hour < WAKE_HOUR:
		return WAKE_HOUR - hour
	return GameClock.HOURS_PER_DAY - hour + WAKE_HOUR


## Texto para la interfaz. Lógica pura.
static func failure_text(reason: StringName) -> String:
	match reason:
		&"day":
			return "Todavía no es de noche: se duerme desde las %02d:00." % int(SLEEP_FROM)
		&"in_cab":
			return "Para dormir, salí de la cabina."
		&"on_train":
			return "En el tren se duerme en la cama del vagón cocina."
		&"in_air":
			return "Para acampar hay que estar en el suelo."
		&"boars":
			return "Hay jabalíes cerca: no es seguro acampar acá."
		&"money":
			return "No te alcanza la plata para la cama."
	return ""


func _ready() -> void:
	_player = get_parent() as Player
	if _player == null:
		push_error("Sleeper debe ser hijo directo de un Player.")
		set_process_unhandled_input(false)
		return
	start_point = _player.global_position
	var health: Health = _player.get_health()
	if health != null:
		health.depleted.connect(_on_depleted)
	_build_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if not InputMap.has_action(&"camp") or not event.is_action_pressed(&"camp"):
		return
	if not _player.controls_enabled:
		return
	camp()


func is_busy() -> bool:
	return _busy


## Duerme en `bed`. Devuelve false (y avisa por `sleep_failed`) si no se pudo.
func sleep_in(bed: Bed) -> bool:
	var reason: StringName = _check_common()
	if reason == &"" and bed != null and GameState.money < bed.price:
		reason = &"money"
	if reason != &"":
		sleep_failed.emit(reason)
		return false
	if bed != null:
		if bed.price > 0:
			GameState.add_money(-bed.price)
		last_bed = bed
	await _sleep(bed.place_name if bed != null else "la cama", null)
	return true


## Acampa donde está. Devuelve false (y avisa por `sleep_failed`) si no se pudo.
func camp() -> bool:
	var reason: StringName = _check_common()
	if reason == &"" and _player.get_platform() != null:
		reason = &"on_train"
	if reason == &"" and not _player.is_on_floor():
		reason = &"in_air"
	if reason == &"" and BoarHerd.count_near(get_tree(), _player.global_position, CAMP_SAFE_RADIUS) > 0:
		reason = &"boars"
	if reason != &"":
		sleep_failed.emit(reason)
		return false
	await _sleep("el campamento", _make_tent())
	return true


## Desmayo: la pantalla se funde y despierta en la última cama con poca salud (el reloj sigue).
func faint() -> void:
	if _busy:
		_faint_pending = true
		return
	_busy = true
	if _player.is_in_cab():
		_player.exit_cab()
	_player.set_controls_enabled(false)
	await _fade(1.0)
	_player.teleport_to(last_bed.get_wake_point() if last_bed != null and is_instance_valid(last_bed) else start_point)
	var health: Health = _player.get_health()
	if health != null:
		health.set_value(health.faint_health)
	fainted.emit()
	EventBus.player_fainted.emit()
	await _fade(0.0)
	_player.set_controls_enabled(true)
	_busy = false


func _check_common() -> StringName:
	if _busy:
		return &"busy"
	if _player.is_in_cab():
		return &"in_cab"
	if not can_sleep_at(GameState.clock.time_of_day):
		return &"day"
	return &""


func _sleep(where: String, tent: Node3D) -> void:
	_busy = true
	_player.set_controls_enabled(false)
	await _fade(1.0)
	var hours: float = hours_until_wake(GameState.clock.time_of_day)
	GameState.clock.advance(hours)
	slept.emit(hours, where)
	EventBus.player_slept.emit(hours)
	if tent != null:
		tent.queue_free()
	await _fade(0.0)
	_player.set_controls_enabled(true)
	_busy = false
	if _faint_pending:
		_faint_pending = false
		faint()


func _on_depleted() -> void:
	faint.call_deferred()


# Una carpa chica delante del jugador mientras duerme.
func _make_tent() -> Node3D:
	var tent := MeshInstance3D.new()
	tent.name = "Carpa"
	var prism := PrismMesh.new()
	prism.size = Vector3(1.6, 1.1, 2.0)
	tent.mesh = prism
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.5, 0.33)
	tent.material_override = material
	var parent: Node = get_tree().current_scene if get_tree().current_scene != null else _player.get_parent()
	parent.add_child(tent)
	var ahead: Vector3 = Basis(Vector3.UP, _player.get_facing_yaw()) * Vector3(0.0, 0.0, -1.8)
	tent.global_position = _player.global_position + ahead + Vector3.UP * 0.55
	tent.rotation.y = _player.get_facing_yaw()
	return tent


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Fundido"
	layer.layer = 20
	add_child(layer)
	_overlay = ColorRect.new()
	_overlay.color = Color(0.03, 0.03, 0.08, 0.0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_overlay)


func _fade(alpha: float) -> void:
	if _overlay == null:
		return
	if fade_seconds <= 0.0 or not is_inside_tree():
		_overlay.color.a = alpha
		return
	var tween: Tween = create_tween()
	tween.tween_property(_overlay, "color:a", alpha, fade_seconds)
	await tween.finished
