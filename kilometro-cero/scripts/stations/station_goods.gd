class_name StationGoods
extends RefCounted
## Lo que el jugador tiene al alcance en una estación (tareas 58 y 59): la carga de los vagones
## de los trenes detenidos en ella, lo que sostiene en la mano y su mochila. Lo usan el tablero
## (StationBoard, para entregar) y el mercado (Market, para comprar y vender). Se arma para una
## consulta y se tira: no guarda nada.
## Orden: para sacar, vagones, mano (solo entera) y mochila; para guardar, vagones y mochila
## (en la mano no se compra: lo grande va al tren).
## Sin `with_wagons` (tarea 62.9a: el mercado de una estación con bahía de carga) solo cuentan la
## mano y la mochila; los vagones los maneja el punto de carga (LoadingBay).
## Con `own_trains_only` (tarea 62b.4, D127: las obras) no cuentan los vagones del tren prestado
## (BorrowedTrains.META); los automáticos nunca cuentan (Station.get_stopped_trains los saltea).

## Unidades que se piden de más para medir el lugar libre.
const ROOM_PROBE: int = 9999

var station: Station
var player: Player
var with_wagons: bool = true
var own_trains_only: bool = false


## `who` null: el jugador que esté en la zona de la estación (o nadie).
func _init(at: Station, who: Player = null, wagons: bool = true) -> void:
	station = at
	player = who
	with_wagons = wagons
	if player == null and station != null:
		player = station.get_present_player()


## Si el vehículo es del tren prestado del Ferrocarril (tarea 62b.4).
static func is_borrowed(vehicle: Node) -> bool:
	return vehicle != null and vehicle.has_meta(BorrowedTrains.META)


## Las cargas de los vagones de los trenes detenidos en la estación.
func get_cargos() -> Array[StorageContainer]:
	var cargos: Array[StorageContainer] = []
	if station == null or not with_wagons:
		return cargos
	for head: Vehicle in station.get_stopped_trains():
		for vehicle: Vehicle in head.get_train():
			if own_trains_only and is_borrowed(vehicle):
				continue
			var wagon := vehicle as Wagon
			if wagon != null and wagon.get_cargo() != null:
				cargos.append(wagon.get_cargo())
	return cargos


func get_backpack() -> Inventory:
	return player.get_backpack() if player != null else null


func get_grabber() -> Grabber:
	if player == null:
		return null
	for child: Node in player.get_children():
		if child is Grabber:
			return child
	return null


## Lo que el jugador tiene en la mano, si lo sostiene su Grabber (si no, no cuenta).
func get_held() -> ItemStack:
	var grabber: Grabber = get_grabber()
	var item: WorldItem = grabber.get_held_item() if grabber != null else null
	return item.stack if item != null else null


## Todo lo que hay al alcance: id de objeto -> unidades.
func get_available() -> Dictionary[StringName, int]:
	var available: Dictionary[StringName, int] = {}
	for stack: ItemStack in _get_stacks():
		available[stack.item.id] = available.get(stack.item.id, 0) + stack.quantity
	return available


func count_of(item_id: StringName) -> int:
	return get_available().get(item_id, 0)


## El ItemData de algo que está al alcance (null si no hay ninguno).
func find_item(item_id: StringName) -> ItemData:
	for stack: ItemStack in _get_stacks():
		if stack.item.id == item_id:
			return stack.item
	return null


## Saca hasta `amount`: vagones, mano (solo si se saca todo lo que sostiene) y mochila, en ese
## orden. Devuelve cuántas sacó.
func take(item_id: StringName, amount: int) -> int:
	var taken: int = 0
	for cargo: StorageContainer in get_cargos():
		for index: int in range(cargo.get_stack_count() - 1, -1, -1):
			if taken >= amount:
				return taken
			if cargo.peek(index).item.id == item_id:
				var stack: ItemStack = cargo.take(index, amount - taken)
				taken += stack.quantity if stack != null else 0
	var held: ItemStack = get_held()
	if held != null and held.item.id == item_id and held.quantity <= amount - taken:
		var consumed: ItemStack = get_grabber().consume_held()
		taken += consumed.quantity if consumed != null else 0
	var backpack: Inventory = get_backpack()
	if backpack != null:
		for slot: int in backpack.get_slot_count():
			if taken >= amount:
				break
			var current: ItemStack = backpack.peek(slot)
			if current != null and current.item.id == item_id:
				var stack: ItemStack = backpack.take(slot, amount - taken)
				taken += stack.quantity if stack != null else 0
	return taken


## Cuántas unidades de `item` entran ahora en los vagones y la mochila.
func room_for(item: ItemData) -> int:
	if item == null:
		return 0
	var probe := ItemStack.new(item, ROOM_PROBE)
	var room: int = 0
	for cargo: StorageContainer in get_cargos():
		room += cargo.can_store_amount(probe)
	var backpack: Inventory = get_backpack()
	if backpack != null:
		room += backpack.can_store_amount(probe)
	return room


## Guarda `amount` unidades de `item` en los vagones y después en la mochila. Devuelve
## cuántas entraron.
func store(item: ItemData, amount: int) -> int:
	if item == null or amount <= 0:
		return 0
	var leftover: ItemStack = ItemStack.new(item, amount)
	for cargo: StorageContainer in get_cargos():
		leftover = cargo.try_store(leftover)
		if leftover == null:
			return amount
	var backpack: Inventory = get_backpack()
	if backpack != null:
		leftover = backpack.try_store(leftover)
	return amount - (leftover.quantity if leftover != null else 0)


func _get_stacks() -> Array[ItemStack]:
	var stacks: Array[ItemStack] = []
	for cargo: StorageContainer in get_cargos():
		for index: int in cargo.get_stack_count():
			stacks.append(cargo.peek(index))
	var held: ItemStack = get_held()
	if held != null:
		stacks.append(held)
	var backpack: Inventory = get_backpack()
	if backpack != null:
		for slot: int in backpack.get_slot_count():
			var stack: ItemStack = backpack.peek(slot)
			if stack != null:
				stacks.append(stack)
	return stacks
