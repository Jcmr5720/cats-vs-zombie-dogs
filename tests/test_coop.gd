extends Node2D
## Pruebas de integracion del Rework Coop (pantalla dividida + cartas por jugador).
## Se ejecuta como ESCENA para contar con autoloads reales:
##   godot --headless --path . res://tests/TestCoop.tscn
## Carga MainLevel REAL en modo local_coop y valida por fases (frames):
## 1) Estructura: P2 spawneado, pantalla dividida con 2 SubViewports compartiendo
##    world_2d, camaras propias, HUD clasico de P1 oculto.
## 2) Cartas independientes: la subida de nivel del P2 abre SOLO su lado del panel,
##    pausa el juego y su eleccion aplica SOLO a P2.
## 3) XP compartida parcial (50% al companero).
## 4) Seleccion simultanea: ambos suben -> ambos lados abiertos a la vez.
## 5) Revive por proximidad: P2 derribado + P1 cerca -> P2 vuelve a estar activo.

const MAIN_LEVEL := "res://scenes/levels/MainLevel.tscn"
const PowerUpPickupScript := preload("res://scripts/loot/power_up_pickup.gd")

var _failures: Array[String] = []
var _checks: int = 0
var _frames: int = 0
var _level: Node
var _p1: Node
var _p2: Node
var _phase: String = "boot"
var _p2_xp_before: int = 0
var _p1_xp_before_rescue: int = 0
var _p1_level_before_rescue: int = 0
var _defer_frames: int = 0
## True mientras una fase-corrutina esta a medias (ver _process).
var _busy: bool = false
var _done: bool = false


func _ready() -> void:
	# El arbol se pausa durante la seleccion de cartas: el test debe seguir corriendo.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var gf: Node = get_node_or_null("/root/GameFlow")
	if gf == null:
		_fail("no existe el autoload GameFlow")
		_finish()
		return
	gf.set("game_mode", "local_coop")
	var packed: PackedScene = load(MAIN_LEVEL)
	_level = packed.instantiate()
	add_child(_level)


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	# Algunas fases son corrutinas (esperan un frame de proceso para que el pickup
	# entre al arbol). Sin esta guarda, _process reentraria en la misma fase antes
	# de que termine y soltaria pickups duplicados.
	if _busy:
		return
	match _phase:
		"boot":
			if _frames >= 10:
				_check_structure()
		"p2_level":
			_check_p2_selection()
		"p2_choice":
			_check_p2_applied()
		"xp_share":
			_check_xp_share()
		"simultaneous":
			_check_simultaneous()
		"revive_setup":
			_setup_revive()
		"revive_wait":
			_wait_revive()
		"defer_invuln":
			_wait_defer_invuln()
		"defer_setup":
			_setup_defer()
		"defer_check":
			_check_defer()
		"defer_revive":
			_wait_defer_revive()


func _check_structure() -> void:
	var players := get_tree().get_nodes_in_group("players")
	_expect(players.size() == 2, "hay 2 jugadores (encontrados: %d)" % players.size())
	for p in players:
		if int(p.get("player_id")) <= 1:
			_p1 = p
		else:
			_p2 = p
	_expect(_p1 != null, "existe el Jugador 1")
	_expect(_p2 != null, "existe el Jugador 2 (spawneado por PlayerManager)")
	if _p1 == null or _p2 == null:
		_finish()
		return

	var hud: Node = get_tree().get_first_node_in_group("hud")
	var split: Node = hud.get_node_or_null("CoopSplitScreen") if hud != null else null
	_expect(split != null, "la pantalla dividida cuelga del HUD")
	if split != null:
		_expect(hud.get_child(0) == split, "el split es el PRIMER hijo del HUD (debajo de los paneles)")
		var viewports: Array = []
		_collect_subviewports(split, viewports)
		_expect(viewports.size() == 2, "hay 2 SubViewports (encontrados: %d)" % viewports.size())
		var world: World2D = get_viewport().world_2d
		for vp in viewports:
			_expect((vp as SubViewport).world_2d == world, "el SubViewport comparte el mundo del nivel")
			var has_camera: bool = false
			for child in (vp as Node).get_children():
				if child is Camera2D:
					has_camera = true
			_expect(has_camera, "el SubViewport tiene su camara propia")
	var top_left: CanvasItem = hud.get_node_or_null("TopLeft") if hud != null else null
	_expect(top_left != null and not top_left.visible, "el bloque de stats P1 del HUD clasico esta oculto en coop")
	var p2_cam: Camera2D = (_p2 as Node).get_node_or_null("Camera2D") as Camera2D
	_expect(p2_cam == null or not p2_cam.enabled, "la camara embebida del P2 esta desactivada")

	# Fase 2: el P2 sube de nivel por su cuenta (XP directa sin reparto).
	_p2.call("add_experience", 60, true)
	_phase = "p2_level"


func _collect_subviewports(node: Node, result: Array) -> void:
	for child in node.get_children():
		if child is SubViewport:
			result.append(child)
		_collect_subviewports(child, result)


## FASE 12: ya no hay panel de cartas ni pausa. Subir de nivel aplica su bonus
## automatico al jugador que subio, y a nadie mas.
func _check_p2_selection() -> void:
	_expect(not get_tree().paused, "subir de nivel NO pausa la partida")
	_expect(int(_p1.get("level")) == 1, "el nivel del J1 no cambio (niveles independientes)")
	_expect(int(_p2.get("level")) >= 2, "el J2 subio de nivel con su propia XP")
	_phase = "p2_choice"


func _check_p2_applied() -> void:
	_busy = true
	# El bonus de nivel es del jugador que sube, igual que antes lo era su carta.
	_expect(int(_p2.get("upgrades_chosen")) >= 1, "el bonus de nivel aplico al J2")
	_expect(int(_p1.get("upgrades_chosen")) == 0, "el bonus de nivel NO aplico al J1")

	# Un power-up del suelo lo cobra UN solo jugador: el primero que lo reclama.
	# Es la guarda que impide que los dos cobren el mismo objeto el mismo frame.
	# Lejos de ambos jugadores: si naciera a los pies del J2, el PickupArea de
	# contacto podria cobrarlo en un tick de fisica ANTES del collect manual del
	# test (carrera intermitente). El collect manual no depende de la distancia.
	var data: PowerUpData = load("res://data/powerups/weapon_damage.tres") as PowerUpData
	var pickup = PowerUpPickupScript.spawn(data, _level,
		(_p2 as Node2D).global_position + Vector2(600, 600))
	await get_tree().process_frame
	var p2_before: int = int(_p2.get("upgrades_chosen"))
	var p1_before: int = int(_p1.get("upgrades_chosen"))
	_expect(bool(pickup.call("collect", _p2)), "el J2 recoge el power-up del suelo")
	_expect(not bool(pickup.call("collect", _p1)),
		"el J1 NO puede volver a cobrar el mismo power-up")
	_expect(int(_p2.get("upgrades_chosen")) == p2_before + 1, "el power-up aplico al J2")
	_expect(int(_p1.get("upgrades_chosen")) == p1_before, "el power-up NO aplico al J1")

	_p2_xp_before = int(_p2.get("experience"))
	_p1.call("add_experience", 4)
	_phase = "xp_share"
	_busy = false


func _check_xp_share() -> void:
	# Fase 3 (rebalance): companero recibe XP_PARTNER_SHARE (35%): ceil(4*0.35)=2.
	var gained: int = int(_p2.get("experience")) - _p2_xp_before
	var leveled: bool = int(_p2.get("level")) > 2
	_expect(gained == 2 or leveled, "el J2 recibio el 35%% de la XP del J1 (delta: %d)" % gained)
	# Fase 4: ambos suben a la vez. Con loot en el suelo eso ya no abre nada.
	_p1.call("add_experience", 40, true)
	_p2.call("add_experience", 40, true)
	_phase = "simultaneous"


## FASE 12: dos subidas simultaneas no pausan ni encolan nada; cada jugador cobra
## su bonus en el acto. Esta era la fase mas fragil del sistema de cartas coop.
func _check_simultaneous() -> void:
	_expect(not get_tree().paused, "dos subidas simultaneas NO pausan la partida")
	_expect(int(_p1.get("upgrades_chosen")) >= 1, "el J1 aplico su propio bonus de nivel")
	_expect(int(_p2.get("upgrades_chosen")) >= 1, "el J2 aplico su propio bonus de nivel")
	_phase = "revive_setup"


func _setup_revive() -> void:
	# Derriba al P2: en coop NO muere mientras quede el P1 en pie.
	_p1_xp_before_rescue = int(_p1.get("experience"))
	_p1_level_before_rescue = int(_p1.get("level"))
	_p2.call("take_damage", 9999)
	_expect(bool(_p2.call("is_downed")), "el J2 queda DERRIBADO (no muerto)")
	_expect(not bool(_p2.call("is_dead")), "el J2 no esta muerto")
	_expect(bool(_p1.call("is_active")), "el J1 sigue activo")
	_phase = "revive_wait"


func _wait_revive() -> void:
	# Mantiene al P1 pegado al P2 para que el revive por proximidad progrese.
	(_p1 as Node2D).global_position = (_p2 as Node2D).global_position + Vector2(40, 0)
	if bool(_p2.call("is_active")):
		_expect(true, "el J2 revivio por proximidad del J1")
		_expect(int(_p2.get("current_health")) > 0, "el J2 revive con vida")
		var xp_gain: int = int(_p1.get("experience")) - _p1_xp_before_rescue
		var leveled: bool = int(_p1.get("level")) > _p1_level_before_rescue
		_expect(xp_gain > 0 or leveled, "el J1 recibio XP por el rescate (delta: %d)" % xp_gain)
		_defer_frames = 0
		_phase = "defer_invuln"
		return
	if _frames > 700:
		_fail("el J2 no revivio a tiempo (frames: %d)" % _frames)
		_finish()


## Prepara un entorno determinista para la fase de diferido: apaga el spawner y
## elimina los enemigos vivos (que a estas alturas derriban al J2 e interfieren),
## y espera a que expire la invulnerabilidad post-revive (REVIVE_INVULN_SECONDS)
## para que el derribo forzado surta efecto.
func _wait_defer_invuln() -> void:
	if _defer_frames == 0:
		var spawner: Node = get_tree().get_first_node_in_group("enemy_spawner")
		if spawner == null:
			spawner = _level.get_node_or_null("EnemySpawner")
		if spawner != null:
			spawner.set_process(false)
			spawner.set_physics_process(false)
		for e in get_tree().get_nodes_in_group("enemies"):
			e.queue_free()
	if get_tree().paused:
		return
	_defer_frames += 1
	# El J2 pudo quedar derribado otra vez antes de limpiar: el J1 lo revive.
	if bool(_p2.call("is_downed")):
		(_p1 as Node2D).global_position = (_p2 as Node2D).global_position + Vector2(40, 0)
		_defer_frames = 1
		return
	if _defer_frames >= 160:
		_defer_frames = 0
		_phase = "defer_setup"


## FASE 12: un jugador DERRIBADO no cobra botin. Antes esto se probaba con el
## diferido de cartas pendientes; ahora la regla equivalente es que ni la XP ni un
## power-up del suelo entran mientras estas en el suelo, y que nada pausa.
func _setup_defer() -> void:
	_p2.set("_damage_timer", 0.0)
	_p2.call("take_damage", 9999)
	_defer_frames = 0
	_phase = "defer_check"


func _check_defer() -> void:
	_defer_frames += 1
	if _defer_frames < 3:
		return
	_busy = true
	_expect(bool(_p2.call("is_downed")), "el J2 esta derribado")
	_expect(not get_tree().paused, "un derribo NO congela la partida")

	# Ni XP ni power-ups entran a un derribado.
	var xp_before: int = int(_p2.get("experience"))
	var upgrades_before: int = int(_p2.get("upgrades_chosen"))
	_p2.call("add_experience", 400, true)
	_expect(int(_p2.get("experience")) == xp_before, "un derribado no acumula XP")

	var data: PowerUpData = load("res://data/powerups/player_speed.tres") as PowerUpData
	var pickup = PowerUpPickupScript.spawn(data, _level, (_p2 as Node2D).global_position)
	await get_tree().process_frame
	# El area de recoleccion del jugador ignora a los derribados; el pickup sigue
	# ahi para quien pueda cogerlo.
	_expect(int(_p2.get("upgrades_chosen")) == upgrades_before,
		"un derribado no cobra el power-up que tiene encima")
	if is_instance_valid(pickup):
		pickup.queue_free()
	_phase = "defer_revive"
	_busy = false


func _wait_defer_revive() -> void:
	_defer_frames += 1
	(_p1 as Node2D).global_position = (_p2 as Node2D).global_position + Vector2(40, 0)
	if bool(_p2.call("is_active")):
		_busy = true
		_expect(true, "el J2 revivio de nuevo")
		# Ya activo, vuelve a cobrar normalmente.
		var upgrades_before: int = int(_p2.get("upgrades_chosen"))
		var data: PowerUpData = load("res://data/powerups/player_speed.tres") as PowerUpData
		var pickup = PowerUpPickupScript.spawn(data, _level, (_p2 as Node2D).global_position)
		await get_tree().process_frame
		pickup.call("collect", _p2)
		_expect(int(_p2.get("upgrades_chosen")) == upgrades_before + 1,
			"tras revivir vuelve a cobrar botin")
		_finish()
		return
	if _defer_frames > 700:
		_fail("el J2 no revivio en la fase de diferido")
		_finish()


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
	_done = true
	print("")
	print("TestCoop: %d checks, %d fallos" % [_checks, _failures.size()])
	for f in _failures:
		printerr(" - " + f)
	get_tree().paused = false
	get_tree().quit(0 if _failures.is_empty() else 1)
