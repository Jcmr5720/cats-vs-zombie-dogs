extends Node
## Autoload "Performance" (Fase 08.75). Vigila la salud de rendimiento de la
## partida para que el EnemySpawner pueda aplicar backpressure y, en el peor caso,
## una limpieza de emergencia. Mide FPS suavizado y cuenta nodos vivos por grupo
## (enemigos, proyectiles, orbes de XP, efectos, jefes) sin recorrer toda la escena.
##
## Expone `performance_state`: &"normal" / &"warning" / &"critical", y contadores
## que otros sistemas consultan. Es barato: solo se recalcula cada `sample_interval`.
##
## Es autoload: persiste entre partidas; los conteos se derivan de grupos, así que
## al reiniciar (R) vuelven a cero solos cuando la escena se recarga.

signal state_changed(new_state: StringName)

@export_group("Umbrales de FPS")
@export var fps_warning: float = 49.0
@export var fps_critical: float = 35.0
## FPS por debajo del cual, sostenido `critical_fps_seconds`, se considera crítico
## aunque haya pocos enemigos (última red de seguridad).
@export var fps_hard_floor: float = 25.0
@export var critical_fps_seconds: float = 3.0

@export_group("Umbrales de enemigos")
@export var enemies_warning: int = 120
@export var enemies_critical: int = 180

@export_group("Muestreo")
## Cada cuánto (s) se recalcula el estado. Muestrear cada frame es innecesario.
@export var sample_interval: float = 0.25
## Suavizado del FPS (0..1): más alto = reacciona más rápido, más ruidoso.
@export_range(0.02, 1.0, 0.01) var fps_smoothing: float = 0.2

var performance_state: StringName = &"normal"
var smoothed_fps: float = 60.0
var alive_enemies: int = 0
var alive_projectiles: int = 0
var alive_xp_orbs: int = 0
var alive_effects: int = 0
var alive_obstacles: int = 0
var boss_active: bool = false
## Multiplicador de spawn actual (lo publica el EnemySpawner para el overlay F8).
var spawn_multiplier: float = 1.0

var _sample_accum: float = 0.0
var _low_fps_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	smoothed_fps = float(Engine.get_frames_per_second())


func _process(delta: float) -> void:
	# FPS suavizado siempre (barato); el resto solo cada intervalo.
	var instant_fps: float = float(Engine.get_frames_per_second())
	if instant_fps > 0.0:
		smoothed_fps = lerpf(smoothed_fps, instant_fps, fps_smoothing)

	_sample_accum += delta
	if _sample_accum < sample_interval:
		return
	_sample_accum = 0.0
	_sample_counts()
	_update_low_fps_timer(delta)
	_evaluate_state()


func _sample_counts() -> void:
	var tree := get_tree()
	if tree == null:
		return
	alive_enemies = tree.get_node_count_in_group(&"enemies")
	alive_projectiles = tree.get_node_count_in_group(&"projectiles")
	alive_xp_orbs = tree.get_node_count_in_group(&"xp_orbs")
	alive_effects = tree.get_node_count_in_group(&"vfx")
	alive_obstacles = tree.get_node_count_in_group(&"obstacles")
	boss_active = tree.get_node_count_in_group(&"boss") > 0 or tree.get_node_count_in_group(&"miniboss") > 0


func _update_low_fps_timer(_delta: float) -> void:
	if smoothed_fps < fps_hard_floor:
		_low_fps_timer += sample_interval
	else:
		_low_fps_timer = 0.0


func _evaluate_state() -> void:
	var new_state: StringName = &"normal"
	if smoothed_fps < fps_critical or alive_enemies > enemies_critical \
			or _low_fps_timer >= critical_fps_seconds:
		new_state = &"critical"
	elif smoothed_fps < fps_warning or alive_enemies > enemies_warning:
		new_state = &"warning"

	if new_state != performance_state:
		performance_state = new_state
		state_changed.emit(new_state)


func is_warning() -> bool:
	return performance_state == &"warning"


func is_critical() -> bool:
	return performance_state == &"critical"


## True si el FPS lleva `critical_fps_seconds` bajo el piso duro: gatillo para la
## limpieza de emergencia junto con el conteo absoluto de enemigos del spawner.
func fps_sustained_critical() -> bool:
	return _low_fps_timer >= critical_fps_seconds


## Snapshot para HUD/depuración (F8) y documentación.
func get_debug_line() -> String:
	return "FPS %d | %s | E:%d P:%d XP:%d FX:%d OB:%d | spawn x%.2f%s" % [
		int(round(smoothed_fps)),
		String(performance_state).to_upper(),
		alive_enemies,
		alive_projectiles,
		alive_xp_orbs,
		alive_effects,
		alive_obstacles,
		spawn_multiplier,
		"  BOSS" if boss_active else "",
	]
