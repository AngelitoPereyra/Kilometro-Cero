class_name TrainRoute
extends RefCounted
## Las curvas que ocupa un tren, una detrás de otra (tarea 54). Con esto un tren puede estar
## repartido entre dos tramos al pasar por una estación: cada vehículo se ubica a su distancia
## de la cabeza sobre la ruta y no sobre una sola curva.
## La ruta es una recta imaginaria de 0 (atrás de todo) a get_length() (adelante de todo),
## hecha con pedazos de curva. Cada pedazo tiene su sentido: +1 si el frente del tren mira hacia
## donde crece el avance de esa curva, -1 si mira al revés (el vehículo va dado vuelta sobre
## ella). `head` es la coordenada del centro de la cabeza del tren.
## Lógica pura sobre las curvas: no mueve nodos ni consulta la red.

## Coordenada del centro de la cabeza del tren sobre la ruta.
var head: float = 0.0

# Pedazos de atrás hacia adelante.
var _paths: Array[Path3D] = []
var _dirs: Array[int] = []


## Una ruta de un solo pedazo, con la cabeza en `progress` de `path`.
func reset(path: Path3D, dir: int, progress: float) -> void:
	_paths = [path]
	_dirs = [1 if dir >= 0 else -1]
	head = (progress - _back_end(0)) * _dirs[0]


func duplicate_route() -> TrainRoute:
	var copy := TrainRoute.new()
	copy._paths = _paths.duplicate()
	copy._dirs = _dirs.duplicate()
	copy.head = head
	return copy


func get_piece_count() -> int:
	return _paths.size()


func get_path(index: int) -> Path3D:
	return _paths[index]


func get_dir(index: int) -> int:
	return _dirs[index]


func has_path(path: Path3D) -> bool:
	return _paths.has(path)


## Largo total de la ruta.
func get_length() -> float:
	var total: float = 0.0
	for i: int in _paths.size():
		total += piece_length(i)
	return total


func piece_length(index: int) -> float:
	var path: Path3D = _paths[index]
	if path == null or path.curve == null:
		return 0.0
	return path.curve.get_baked_length()


## Coordenada donde empieza un pedazo (su punta de atrás).
func piece_start(index: int) -> float:
	var total: float = 0.0
	for i: int in index:
		total += piece_length(i)
	return total


## En qué pedazo y en qué avance de su curva cae la coordenada `s` (se limita a la ruta).
## Devuelve [índice, avance].
func locate(s: float) -> Array:
	var start: float = 0.0
	var last: int = _paths.size() - 1
	for i: int in _paths.size():
		var length: float = piece_length(i)
		if s <= start + length or i == last:
			var local: float = clampf(s - start, 0.0, length)
			return [i, _back_end(i) + _dirs[i] * local]
		start += length
	return [0, 0.0]


## Coordenada de un punto (`progress` sobre `path`), o NAN si esa curva no está en la ruta.
func coordinate_of(path: Path3D, progress: float) -> float:
	var index: int = _paths.find(path)
	if index < 0:
		return NAN
	return piece_start(index) + (progress - _back_end(index)) * _dirs[index]


## Suma un pedazo adelante.
func push_front(path: Path3D, dir: int) -> void:
	_paths.append(path)
	_dirs.append(1 if dir >= 0 else -1)


## Suma un pedazo atrás. Todas las coordenadas corren lo que mide.
func push_back(path: Path3D, dir: int) -> void:
	_paths.insert(0, path)
	_dirs.insert(0, 1 if dir >= 0 else -1)
	head += piece_length(0)


## Cambia el pedazo `index` por otra curva. Si es el de atrás de todo, las coordenadas corren
## lo que cambia el largo.
func replace_piece(index: int, path: Path3D, dir: int) -> void:
	var old_length: float = piece_length(index)
	_paths[index] = path
	_dirs[index] = 1 if dir >= 0 else -1
	if index == 0:
		head += piece_length(0) - old_length


## Saca los pedazos que quedan enteros fuera de [from, to], salvo `keep` pedazos de cada lado
## (la memoria de por dónde vino el tren, para poder volver marcha atrás).
func trim(from: float, to: float, keep: int = 1) -> void:
	# Adelante.
	while _paths.size() > 1 and _count_front_outside(to) > keep:
		_paths.pop_back()
		_dirs.pop_back()
	# Atrás.
	while _paths.size() > 1 and _count_back_outside(from) > keep:
		head -= piece_length(0)
		_paths.pop_front()
		_dirs.pop_front()


## Saca el pedazo de adelante de todo (si queda más de uno).
func drop_front() -> void:
	if _paths.size() > 1:
		_paths.pop_back()
		_dirs.pop_back()


## Saca el pedazo de atrás de todo (si queda más de uno). Las coordenadas corren lo que medía.
func drop_back() -> void:
	if _paths.size() > 1:
		head -= piece_length(0)
		_paths.pop_front()
		_dirs.pop_front()


## La punta delantera del pedazo de adelante de todo: [curva, avance]. Ahí está la estación
## por donde sigue el tren hacia adelante.
func front_end() -> Array:
	var last: int = _paths.size() - 1
	return [_paths[last], _front_end(last)]


## La punta trasera del pedazo de atrás de todo: [curva, avance].
func back_end() -> Array:
	return [_paths[0], _back_end(0)]


# Pedazos de adelante que quedan enteros más allá de `to`.
func _count_front_outside(to: float) -> int:
	var count: int = 0
	for i: int in range(_paths.size() - 1, 0, -1):
		if piece_start(i) > to:
			count += 1
		else:
			break
	return count


# Pedazos de atrás que quedan enteros antes de `from`.
func _count_back_outside(from: float) -> int:
	var count: int = 0
	var end: float = 0.0
	for i: int in range(0, _paths.size() - 1):
		end += piece_length(i)
		if end < from:
			count += 1
		else:
			break
	return count


# Avance de la punta de atrás y de adelante de un pedazo, según su sentido.
func _back_end(index: int) -> float:
	return 0.0 if _dirs[index] > 0 else piece_length(index)


func _front_end(index: int) -> float:
	return piece_length(index) if _dirs[index] > 0 else 0.0
