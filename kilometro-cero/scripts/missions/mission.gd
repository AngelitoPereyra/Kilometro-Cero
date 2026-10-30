class_name Mission
extends RefCounted
## Una misión en juego (D80, tarea 58): su estado y lo entregado. La crea y la maneja el
## MissionBoard.
## - Principal: sale sola de un consumo sin flujo ("Abastecer al pueblo de 10 troncos por día").
##   Pide una primera carga de FIRST_DELIVERY_DAYS días de consumo y, con la conexión abierta
##   y un productor con producción libre, crea el flujo permanente.
## - Secundaria: viene de un MissionData (entrega, habilitar tramo, despejar zona u obra).
## - Principal con aviso (tarea 62b.3, D128): si la estación tiene quien da sus principales
##   (MissionGiver.main_station), el jugador abre el camino y le avisa (`reported`); el
##   Ferrocarril manda la primera carga en un tren prestado que maneja el jugador (`inaugural`)
##   o, si el camino ya lo estrenó un tren, la manda solo.

## LOCKED: todavía no se puede conseguir. AVAILABLE: un poblador la ofrece. ACTIVE: en curso.
## COMPLETED: cumplida.
enum State { LOCKED, AVAILABLE, ACTIVE, COMPLETED }

const STATE_NAMES: Array[String] = ["bloqueada", "disponible", "en curso", "cumplida"]
## La primera carga de una principal: estos días de consumo.
const FIRST_DELIVERY_DAYS: int = 2

var id: StringName
var main: bool = false
var station_id: StringName
var kind: MissionData.Kind = MissionData.Kind.DELIVERY
var state: State = State.LOCKED
## Lo que hay que entregar en total (id de objeto -> unidades).
var required: Dictionary[StringName, int] = {}
## Lo que ya se entregó.
var delivered: Dictionary[StringName, int] = {}
## Principal: objeto y unidades por día del flujo que crea.
var item_id: StringName
var flow_amount: int = 0
## Principal: el flujo que creó al cumplirse.
var flow: ProductionFlow
## Secundaria: sus datos (null en las principales).
var data: MissionData
## Secundaria: si el poblador ya contó el cierre (MissionGiver).
var outro_told: bool = false
## Principal con aviso (tarea 62b.3): ya se le avisó a quien la da que el camino está habilitado.
var reported: bool = false
## Principal con aviso: el tren prestado espera en el tablero del productor que el jugador lo tome
## (viaje inaugural opcional, ajuste de Batmi a la 62b.3); si no, al otro día lo trae el Ferrocarril.
var offered: bool = false
## Principal con aviso: la primera carga va en el tren prestado (viaje inaugural, en curso).
var inaugural: bool = false
## Principal con aviso: la estación productora elegida al avisar (de ahí sale el tren prestado).
var source_id: StringName
## Secundaria cumplida: los pesos que se cobraron (tarea 62b.6: un encargo queda con el precio del
## momento en que se cumplió).
var paid: int = 0


## Id de la principal de una estación y un objeto: "main:pueblo:log".
static func main_id(station: StringName, item: StringName) -> StringName:
	return StringName("main:%s:%s" % [station, item])


static func create_main(station: StringName, item: StringName, amount: int) -> Mission:
	var mission := Mission.new()
	mission.id = main_id(station, item)
	mission.main = true
	mission.station_id = station
	mission.item_id = item
	mission.flow_amount = amount
	mission.required = {item: amount * FIRST_DELIVERY_DAYS}
	mission.state = State.ACTIVE
	return mission


static func create_side(mission_data: MissionData) -> Mission:
	var mission := Mission.new()
	mission.id = mission_data.id
	mission.data = mission_data
	mission.station_id = mission_data.station_id
	mission.kind = mission_data.kind
	if mission_data.kind == MissionData.Kind.DELIVERY or mission_data.kind == MissionData.Kind.BUILD:
		mission.required = ItemAmount.sum_by_id(mission_data.delivery)
	return mission


static func state_name(value: State) -> String:
	return STATE_NAMES[value]


func is_active() -> bool:
	return state == State.ACTIVE


func is_completed() -> bool:
	return state == State.COMPLETED


## Lo que falta entregar (vacío si ya está todo o si no es de entrega).
func get_remaining() -> Dictionary[StringName, int]:
	var remaining: Dictionary[StringName, int] = {}
	for item: StringName in required:
		var lacking: int = required[item] - delivered.get(item, 0)
		if lacking > 0:
			remaining[item] = lacking
	return remaining


func is_delivery_done() -> bool:
	return get_remaining().is_empty()


## Suma lo entregado sin pasarse de lo pedido. Devuelve cuánto aceptó.
func add_delivery(item: StringName, amount: int) -> int:
	var accepted: int = mini(amount, get_remaining().get(item, 0))
	if accepted > 0:
		delivered[item] = delivered.get(item, 0) + accepted
	return accepted


func get_title() -> String:
	if data != null:
		return data.title
	return "Abastecer con %d %s por día" % [flow_amount, item_id]


## "Abastecer con 10 log por día (en curso, 5/20 log)".
func describe() -> String:
	var parts: PackedStringArray = []
	for item: StringName in required:
		parts.append("%d/%d %s" % [delivered.get(item, 0), required[item], item])
	var detail: String = state_name(state)
	if not parts.is_empty():
		detail += ", " + ", ".join(parts)
	return "%s (%s)" % [get_title(), detail]


## Para el guardado (tarea 65). Las secundarias se vuelven a unir a sus datos por id.
func to_dict() -> Dictionary:
	var saved_delivered: Dictionary = {}
	for item: StringName in delivered:
		saved_delivered[String(item)] = delivered[item]
	var values: Dictionary = {
		"id": String(id),
		"main": main,
		"station": String(station_id),
		"state": state,
		"delivered": saved_delivered,
		"outro_told": outro_told,
		"paid": paid,
	}
	if main:
		values["item"] = String(item_id)
		values["amount"] = flow_amount
		values["reported"] = reported
		values["offered"] = offered
		values["inaugural"] = inaugural
		values["source"] = String(source_id)
	return values


## Una principal desde el guardado (las secundarias se arman con create_side y apply_dict).
static func main_from_dict(values: Dictionary) -> Mission:
	var mission: Mission = create_main(StringName(values.get("station", "")), StringName(values.get("item", "")), int(values.get("amount", 0)))
	mission.apply_dict(values)
	return mission


## Copia estado y entregas guardados.
func apply_dict(values: Dictionary) -> void:
	state = int(values.get("state", state)) as State
	outro_told = bool(values.get("outro_told", false))
	paid = int(values.get("paid", 0))
	reported = bool(values.get("reported", false))
	offered = bool(values.get("offered", false))
	inaugural = bool(values.get("inaugural", false))
	source_id = StringName(values.get("source", ""))
	delivered.clear()
	var saved_delivered: Dictionary = values.get("delivered", {})
	for key: String in saved_delivered:
		delivered[StringName(key)] = int(saved_delivered[key])
