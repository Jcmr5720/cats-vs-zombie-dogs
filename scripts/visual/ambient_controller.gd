extends Node2D
## Iluminacion global del nivel (FASE VISUAL 2). Aplica el ambiente del MapData:
## - CanvasModulate: tinte multiplicativo sobre TODO el mundo (el HUD vive en
##   CanvasLayers y no se ve afectado). Valores cercanos a 1 para no perder
##   legibilidad; cada mapa define su atmosfera (noche azulada, verdin, oxido).
## - Niebla baja opcional: 3 bancos grandes translucidos que derivan muy lento
##   sobre los actores. Baratisima (3 poligonos, un _process trivial) y se
##   desactiva sola en calidad baja o con los efectos apagados.
##
## Vive dentro de MainLevel: al reiniciar (R) o volver al menu se libera con la
## escena, de modo que nunca quedan modulaciones ni niebla duplicadas.

const FOG_BANKS: int = 3

var _canvas_modulate: CanvasModulate
var _fog_root: Node2D
var _fog_banks: Array[Polygon2D] = []
var _fog_time: float = 0.0
var _fog_strength: float = 0.0
## Ultimo MapData aplicado: permite re-aplicar la niebla al cambiar opciones.
var _last_map: Resource


func _ready() -> void:
	add_to_group("ambient_controller")
	set_process(false)


## La llama el MapManager al aplicar el mapa activo.
func configure(map_data) -> void:
	_last_map = map_data
	_apply_modulate(map_data)
	_apply_fog(map_data)


## FASE VISUAL 2.5: re-aplica la niebla con los ajustes actuales (la llama
## Feedback cuando cambian las opciones, sin reiniciar la partida).
func refresh_settings() -> void:
	if _last_map != null:
		_apply_fog(_last_map)


func _apply_modulate(map_data) -> void:
	var ambient: Color = map_data.ambient_color
	# Blanco puro = sin capa (no crear el nodo para no pagar nada).
	if ambient.is_equal_approx(Color(1, 1, 1, 1)):
		if is_instance_valid(_canvas_modulate):
			_canvas_modulate.color = Color(1, 1, 1, 1)
		return
	if not is_instance_valid(_canvas_modulate):
		_canvas_modulate = CanvasModulate.new()
		add_child(_canvas_modulate)
	# Entrada suave: el ambiente aparece en ~1 s en vez de golpear de un frame.
	_canvas_modulate.color = Color(1, 1, 1, 1)
	var tween := create_tween()
	tween.tween_property(_canvas_modulate, "color", ambient, 1.1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _apply_fog(map_data) -> void:
	_fog_strength = clampf(map_data.fog_strength, 0.0, 1.0)
	var fb: Node = get_node_or_null("/root/Feedback")
	# La niebla respeta su toggle propio (fog_enabled) ademas de la calidad.
	var effects_ok: bool = fb == null or (bool(fb.get("fog_enabled")) and fb.get("visual_quality") != &"baja")
	if _fog_strength <= 0.01 or not effects_ok:
		if is_instance_valid(_fog_root):
			_fog_root.queue_free()
			_fog_root = null
			_fog_banks.clear()
		set_process(false)
		return

	if not is_instance_valid(_fog_root):
		_fog_root = Node2D.new()
		# Por encima de actores (z 0) pero por debajo de numeros de dano/HUD.
		_fog_root.z_index = 30
		add_child(_fog_root)
		for i in FOG_BANKS:
			var bank := Polygon2D.new()
			var points := PackedVector2Array()
			# Nube alargada irregular (~900x360 px) con 12 vertices deterministas.
			for k in 12:
				var a: float = TAU * float(k) / 12.0
				var wobble: float = 1.0 + sin(float(i * 5 + k) * 2.7) * 0.28
				points.append(Vector2(cos(a) * 460.0 * wobble, sin(a) * 180.0 * wobble))
			bank.polygon = points
			_fog_root.add_child(bank)
			_fog_banks.append(bank)

	var fog: Color = map_data.fog_color
	for i in _fog_banks.size():
		# Alfa muy bajo por banco: la suma nunca tapa el combate.
		_fog_banks[i].color = Color(fog.r, fog.g, fog.b, 0.045 * _fog_strength * (1.0 + float(i) * 0.35))
	set_process(true)


func _process(delta: float) -> void:
	if _fog_banks.is_empty():
		return
	_fog_time += delta
	# Los bancos siguen a la camara con paralaje lentisimo + deriva senoidal.
	var camera := get_viewport().get_camera_2d()
	var center: Vector2 = camera.get_screen_center_position() if camera != null else Vector2.ZERO
	for i in _fog_banks.size():
		var f: float = float(i)
		var drift := Vector2(
			sin(_fog_time * 0.05 + f * 2.1) * 340.0 + fmod(_fog_time * (7.0 + f * 4.0), 2200.0) - 1100.0,
			cos(_fog_time * 0.04 + f * 1.3) * 240.0 + (f - 1.0) * 260.0
		)
		_fog_banks[i].global_position = center + drift
