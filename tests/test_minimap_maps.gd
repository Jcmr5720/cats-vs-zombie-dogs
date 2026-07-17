extends Node2D
## Sistema Minimapa: validacion en TODOS los mapas y en varias resoluciones.
##   godot --headless --path . res://tests/TestMinimapMaps.tscn
## 1) Carga MainLevel con cada MapData del juego (neighborhood, park, industrial)
##    y comprueba que el minimapa existe, esta visible y dibuja puntos sin errores.
## 2) En el ultimo mapa, cambia el tamano de ventana a 16:9, 16:10 y ultrawide y
##    comprueba que el panel queda dentro de la pantalla, pegado al borde derecho.

const MAIN_LEVEL := "res://scenes/levels/MainLevel.tscn"
const MAPS: Array = [
	"res://data/maps/neighborhood_map.tres",
	"res://data/maps/park_map.tres",
	"res://data/maps/industrial_alley_map.tres",
]
const RESOLUTIONS: Array = [
	Vector2i(1920, 1080),  # 16:9
	Vector2i(1920, 1200),  # 16:10
	Vector2i(3440, 1440),  # ultrawide 21:9
	Vector2i(1280, 720),   # resolucion baja
]

var _failures: Array[String] = []
var _checks: int = 0
var _map_index: int = -1
var _res_index: int = 0
var _level: Node
var _phase: String = "next_map"
var _wait_seconds: float = 0.0
var _next_phase: String = ""
var _done: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if _done:
		return
	if _wait_seconds > 0.0:
		_wait_seconds -= delta
		if _wait_seconds <= 0.0:
			_phase = _next_phase
		return
	match _phase:
		"next_map":
			_load_next_map()
		"check_map":
			_check_map()
		"next_res":
			_apply_next_resolution()
		"check_res":
			_check_resolution()


func _wait(seconds: float, next_phase: String) -> void:
	_wait_seconds = seconds
	_next_phase = next_phase
	_phase = "waiting"


func _load_next_map() -> void:
	_map_index += 1
	if _map_index >= MAPS.size():
		_phase = "next_res"
		return
	if is_instance_valid(_level):
		_level.queue_free()
	var gf: Node = get_node_or_null("/root/GameFlow")
	gf.set("game_mode", "solo")
	gf.set("selected_map", load(MAPS[_map_index]))
	_level = (load(MAIN_LEVEL) as PackedScene).instantiate()
	# Diferido: el nivel anterior aun se esta liberando este frame.
	call_deferred("add_child", _level)
	_wait(1.2, "check_map")


func _check_map() -> void:
	var map_name: String = MAPS[_map_index].get_file()
	var hud: Node = get_tree().get_first_node_in_group("hud")
	var c1: Control = hud.get_node_or_null("Minimap1") as Control if hud != null else null
	_expect(c1 != null, "%s: existe el minimapa" % map_name)
	if c1 != null:
		_expect(c1.visible, "%s: el minimapa esta visible" % map_name)
		var dots: Control = c1.get_node_or_null("Dots") as Control
		_expect(dots != null, "%s: existe el DotLayer" % map_name)
		var markers: int = _visible_player_markers(c1)
		_expect(markers >= 1, "%s: el jugador esta marcado (%d)" % [map_name, markers])
	_phase = "next_map"


func _visible_player_markers(ctrl: Control) -> int:
	var count: int = 0
	var pool = ctrl.get("_marker_pool")
	if pool == null:
		return 0
	for m in pool:
		if is_instance_valid(m) and (m as CanvasItem).visible and m.get("kind") == &"player":
			count += 1
	return count


func _apply_next_resolution() -> void:
	if _res_index >= RESOLUTIONS.size():
		_finish()
		return
	get_window().size = RESOLUTIONS[_res_index]
	_wait(0.4, "check_res")


func _check_resolution() -> void:
	var res: Vector2i = RESOLUTIONS[_res_index]
	var hud: Node = get_tree().get_first_node_in_group("hud")
	var c1: Control = hud.get_node_or_null("Minimap1") as Control if hud != null else null
	if c1 == null:
		_fail("%s: no hay minimapa" % str(res))
		_res_index += 1
		_phase = "next_res"
		return
	# En coordenadas del lienzo del HUD: el panel debe quedar dentro de la vista,
	# anclado cerca del borde derecho.
	var view: Vector2 = c1.get_viewport_rect().size
	var rect: Rect2 = c1.get_global_rect()
	_expect(rect.position.x >= 0.0 and rect.end.x <= view.x + 0.5,
		"%s: el minimapa cabe horizontalmente (%.0f..%.0f de %.0f)" % [str(res), rect.position.x, rect.end.x, view.x])
	_expect(rect.end.y <= view.y, "%s: el minimapa cabe verticalmente" % str(res))
	_expect(view.x - rect.end.x < 120.0, "%s: sigue pegado al borde derecho" % str(res))
	_res_index += 1
	_phase = "next_res"


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  OK  ", message)
	else:
		_failures.append(message)
		printerr("  FALLO  ", message)


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("  FALLO  ", message)


func _finish() -> void:
	if _done:
		return
	_done = true
	print("")
	print("TestMinimapMaps: %d checks, %d fallos" % [_checks, _failures.size()])
	for f in _failures:
		printerr(" - " + f)
	get_tree().paused = false
	get_tree().quit(0 if _failures.is_empty() else 1)
