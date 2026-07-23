extends Node2D
## Soak test del coop (Rework Coop): corre MainLevel REAL en local_coop durante
## ~2400 frames moviendo a ambos jugadores, resolviendo cartas automaticamente y
## derribando/reviviendo al P2 a mitad de la corrida. No valida logica fina (eso
## es TestCoop): busca ERRORES DE RUNTIME (nulls, nodos perdidos, flush de fisica)
## con todos los sistemas vivos: spawner, orbes, companeros, split screen.
##   godot --headless --path . res://tests/TestCoopSoak.tscn

const MAIN_LEVEL := "res://scenes/levels/MainLevel.tscn"
const TOTAL_FRAMES: int = 2400

var _frames: int = 0
var _p1: Node2D
var _p2: Node2D
var _drift1: Vector2 = Vector2.RIGHT
var _drift2: Vector2 = Vector2.DOWN

# Metricas de la corrida (Fase 12): se imprimen al final como informe.
var _fps_min: float = INF
var _fps_sum: float = 0.0
var _fps_samples: int = 0
var _max_enemies: int = 0
var _max_projectiles: int = 0
var _max_orbs: int = 0
var _max_nodes: int = 0
var _reported: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var gf: Node = get_node_or_null("/root/GameFlow")
	if gf != null:
		gf.set("game_mode", "local_coop")
	add_child((load(MAIN_LEVEL) as PackedScene).instantiate())


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 10:
		for p in get_tree().get_nodes_in_group("players"):
			if int(p.get("player_id")) <= 1:
				_p1 = p
			else:
				_p2 = p
			# El soak no da input: se fuerza el auto-apuntado para que el combate
			# medido sea el de siempre (la mira manual apuntaria a un punto fijo).
			if p.has_method("set_aim_mode"):
				p.set_aim_mode(&"auto")

	# Deriva de movimiento: los jugadores se separan y se juntan en ciclos para
	# ejercitar spawns lejanos, iman de orbes y flechas de companero.
	if is_instance_valid(_p1) and is_instance_valid(_p2) and not get_tree().paused:
		if _frames % 240 == 0:
			_drift1 = Vector2.RIGHT.rotated(randf() * TAU)
			_drift2 = Vector2.RIGHT.rotated(randf() * TAU)
		_p1.global_position += _drift1 * 3.0
		_p2.global_position += _drift2 * 3.0

	# Derriba al P2 a mitad de corrida y deja que el P1 lo reviva.
	if _frames == 1200 and is_instance_valid(_p2) and not get_tree().paused:
		_p2.call("take_damage", 9999)
	if _frames > 1200 and _frames < 1500 and is_instance_valid(_p1) and is_instance_valid(_p2):
		if _p2.has_method("is_downed") and _p2.is_downed():
			_p1.global_position = _p2.global_position + Vector2(40, 0)

	# FASE 12: ya no hay cartas. Se recoge el botín del suelo para que el soak coop
	# siga ejercitando la progresión real (power-ups + armas).
	if _frames % 3 == 0:
		for pickup in get_tree().get_nodes_in_group("pickups"):
			if not is_instance_valid(pickup) or not pickup.has_method("collect"):
				continue
			if not pickup.has_method("is_claimed") or pickup.is_claimed():
				continue
			var p: Node = get_tree().get_first_node_in_group("player")
			if p != null:
				pickup.call("collect", p)

	# Muestreo de metricas (tras el warmup inicial de carga de escena).
	if _frames > 120:
		var fps: float = Engine.get_frames_per_second()
		_fps_min = minf(_fps_min, fps)
		_fps_sum += fps
		_fps_samples += 1
		_max_enemies = maxi(_max_enemies, get_tree().get_node_count_in_group("enemies"))
		_max_projectiles = maxi(_max_projectiles, get_tree().get_node_count_in_group("projectiles"))
		_max_orbs = maxi(_max_orbs, get_tree().get_node_count_in_group("xp_orbs"))
		_max_nodes = maxi(_max_nodes, get_tree().get_node_count())

	if _frames >= TOTAL_FRAMES and not _reported:
		_reported = true
		print("CoopSoak: %d frames sin crash. Jugadores validos: %s/%s" % [
			_frames, str(is_instance_valid(_p1)), str(is_instance_valid(_p2))])
		var fps_avg: float = _fps_sum / maxf(1.0, float(_fps_samples))
		print("CoopSoak METRICAS: fps_min=%.0f fps_avg=%.0f max_enemigos=%d max_proyectiles=%d max_orbes=%d max_nodos=%d mem_estatica=%.1fMB huerfanos=%d" % [
			_fps_min, fps_avg, _max_enemies, _max_projectiles, _max_orbs, _max_nodes,
			OS.get_static_memory_usage() / 1048576.0,
			_orphan_node_count()])
		get_tree().paused = false
		get_tree().quit(0)


## Nodos huerfanos via el singleton NATIVO Performance: el autoload del proyecto
## llamado "Performance" (performance_manager.gd) hace sombra al nombre en GDScript.
func _orphan_node_count() -> int:
	var perf: Object = Engine.get_singleton(&"Performance")
	if perf != null and perf.has_method("get_monitor"):
		# Performance.OBJECT_ORPHAN_NODE_COUNT == 3
		return int(perf.call("get_monitor", 3))
	return -1
