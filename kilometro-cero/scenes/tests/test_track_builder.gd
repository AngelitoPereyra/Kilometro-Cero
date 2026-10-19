extends Node3D
## Prueba de la tarea 7: cálculo de módulos (lógica pura), TrackSegment y TrackBuilder.
## Supone la vía recta de 200 m de la tarea 6 y módulos de 5 m.

const TOLERANCIA_M: float = 0.05

@onready var _track: ManualTrack = $Track
@onready var _segment: TrackSegment = $Track/TrackSegment
@onready var _builder: TrackBuilder = $Track/TrackBuilder

var _fallos: int = 0
var _senal_recibida: bool = false
var _valor_senal: float = -1.0


func _ready() -> void:
	_probar_calculo_de_modulos()
	_probar_segmento()
	_probar_constructor()

	if _fallos == 0:
		print("Constructor de Vias: todas las comprobaciones pasaron.")
	else:
		push_error("Constructor de Vias: fallaron %d comprobaciones." % _fallos)


func _probar_calculo_de_modulos() -> void:
	_comprobar(TrackBuilder.module_count(200.0, 5.0) == 40, "200 m con módulos de 5 m: 40 módulos")
	_comprobar(TrackBuilder.module_count(199.9999, 5.0) == 40, "Un error de redondeo (199.9999 m) no pierde un módulo")
	_comprobar(TrackBuilder.module_count(203.0, 5.0) == 40, "Un resto menor a un módulo no suma uno extra")
	_comprobar(TrackBuilder.module_count(4.0, 5.0) == 0, "Un tramo menor a un módulo no genera ninguno")
	_comprobar(TrackBuilder.module_count(100.0, 0.0) == 0, "Módulo de largo 0 no divide por cero")
	_comprobar(is_equal_approx(TrackBuilder.module_offset(0, 5.0), 2.5), "El primer módulo se centra a 2.5 m del inicio")


func _probar_segmento() -> void:
	_segment.condition_changed.connect(_al_cambiar_condicion)
	_segment.condition = 0.33
	_comprobar(_senal_recibida and is_equal_approx(_valor_senal, 0.33), "condition_changed se emite con el valor nuevo")
	_segment.condition_changed.disconnect(_al_cambiar_condicion)

	_segment.condition = 5.0
	_comprobar(is_equal_approx(_segment.condition, 1.0), "La condición se limita a 1.0")
	_segment.condition = -2.0
	_comprobar(is_equal_approx(_segment.condition, 0.0), "La condición se limita a 0.0")
	_segment.condition = 0.25
	_comprobar(is_equal_approx(_segment.get_wear(), 0.75), "Desgaste = 1 - condición")


func _probar_constructor() -> void:
	var instancia: MultiMeshInstance3D = _builder.get_modules_instance()
	var generado: bool = instancia != null and instancia.multimesh != null
	_comprobar(generado, "El constructor generó los módulos")
	if not generado:
		return

	var multimesh: MultiMesh = instancia.multimesh
	var curva: Curve3D = _track.curve
	var esperado: int = TrackBuilder.module_count(curva.get_baked_length(), _builder.module_length)
	_comprobar(multimesh.instance_count == esperado, "Cantidad de módulos: %d (esperado %d)" % [multimesh.instance_count, esperado])
	if multimesh.instance_count < 2:
		return

	# Cada módulo debe estar sobre la curva, en el centro de su tramo.
	var primero: Vector3 = multimesh.get_instance_transform(0).origin
	var segundo: Vector3 = multimesh.get_instance_transform(1).origin
	var ultimo: Vector3 = multimesh.get_instance_transform(multimesh.instance_count - 1).origin
	var esperado_primero: Vector3 = curva.sample_baked(TrackBuilder.module_offset(0, _builder.module_length), true)
	var esperado_ultimo: Vector3 = curva.sample_baked(TrackBuilder.module_offset(multimesh.instance_count - 1, _builder.module_length), true)
	_comprobar(primero.distance_to(esperado_primero) < TOLERANCIA_M, "El primer módulo está sobre la curva")
	_comprobar(ultimo.distance_to(esperado_ultimo) < TOLERANCIA_M, "El último módulo está sobre la curva")
	# En una vía recta, módulos consecutivos quedan separados justo por el largo del módulo.
	_comprobar(absf(primero.distance_to(segundo) - _builder.module_length) < TOLERANCIA_M, "Módulos consecutivos separados %.1f m" % _builder.module_length)

	var material := instancia.material_override as StandardMaterial3D
	_comprobar(material != null, "El módulo usa el material placeholder")
	if material == null:
		return
	_segment.condition = 1.0
	var color_sano: Color = material.albedo_color
	_segment.condition = 0.0
	var color_gastado: Color = material.albedo_color
	_comprobar(color_sano.is_equal_approx(TrackBuilder.COLOR_HEALTHY), "Condición 1.0: color sano")
	_comprobar(color_gastado.is_equal_approx(TrackBuilder.COLOR_WORN), "Condición 0.0: color de óxido")


func _al_cambiar_condicion(condicion: float) -> void:
	_senal_recibida = true
	_valor_senal = condicion


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK: ", descripcion)
	else:
		_fallos += 1
		push_error("FALLÓ: " + descripcion)
