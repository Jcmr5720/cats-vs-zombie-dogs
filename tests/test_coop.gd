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

var _failures: Array[String] = []
var _checks: int = 0
var _frames: int = 0
var _level: Node
var _p1: Node
var _p2: Node
var _panel: Node
var _phase: String = "boot"
var _resolve_tries: int = 0
var _p2_xp_before: int = 0
var _p1_xp_before_rescue: int = 0
var _p1_level_before_rescue: int = 0
var _defer_frames: int = 0
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
		"resolve_all":
			_resolve_all_pending()
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
		"defer_resolve":
			_resolve_defer_pending()


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


func _check_p2_selection() -> void:
	_panel = get_tree().get_first_node_in_group("coop_upgrade_panel")
	_expect(_panel != null, "existe el panel coop de cartas")
	if _panel == null:
		_finish()
		return
	_expect(get_tree().paused, "la partida se pausa durante la seleccion")
	_expect(bool(_panel.call("is_open", 2)), "el lado del J2 esta abierto")
	_expect(not bool(_panel.call("is_open", 1)), "el lado del J1 NO esta abierto (no subio)")
	_expect(int(_p1.get("level")) == 1, "el nivel del J1 no cambio (niveles independientes)")
	_expect(int(_p2.get("level")) >= 2, "el J2 subio de nivel con su propia XP")
	# Elige la primera carta del J2.
	_panel.emit_signal("card_chosen", 2, 0)
	_phase = "p2_choice"


func _check_p2_applied() -> void:
	_expect(int(_p2.get("upgrades_chosen")) >= 1, "la carta aplico al J2")
	_expect(int(_p1.get("upgrades_chosen")) == 0, "la carta NO aplico al J1")
	if not bool(_panel.call("is_open", 2)):
		_expect(not get_tree().paused, "sin selecciones pendientes la partida se reanuda")
		_p2_xp_before = int(_p2.get("experience"))
		_p1.call("add_experience", 4)
		_phase = "xp_share"
	elif _frames > 240:
		_fail("el lado del J2 sigue abierto tras elegir")
		_finish()
	else:
		# Subio otra vez con la XP sobrante: resuelve la siguiente carta.
		_panel.emit_signal("card_chosen", 2, 0)


func _check_xp_share() -> void:
	# Fase 3 (rebalance): companero recibe XP_PARTNER_SHARE (35%): ceil(4*0.35)=2.
	var gained: int = int(_p2.get("experience")) - _p2_xp_before
	var leveled: bool = int(_p2.get("level")) > 2
	_expect(gained == 2 or leveled, "el J2 recibio el 35%% de la XP del J1 (delta: %d)" % gained)
	# Fase 4: ambos con cartas pendientes a la vez.
	_p1.call("add_experience", 40, true)
	_p2.call("add_experience", 40, true)
	_phase = "simultaneous"


func _check_simultaneous() -> void:
	_expect(get_tree().paused, "seleccion simultanea: partida pausada")
	_expect(bool(_panel.call("is_open", 1)), "lado del J1 abierto")
	_expect(bool(_panel.call("is_open", 2)), "lado del J2 abierto")
	_phase = "resolve_all"


func _resolve_all_pending() -> void:
	_resolve_tries += 1
	if _resolve_tries > 40:
		_fail("no se pudieron resolver todas las cartas pendientes")
		_finish()
		return
	var any_open: bool = false
	if bool(_panel.call("is_open", 1)):
		any_open = true
		_panel.emit_signal("card_chosen", 1, 0)
	if bool(_panel.call("is_open", 2)):
		any_open = true
		_panel.emit_signal("card_chosen", 2, 0)
	if not any_open and not get_tree().paused:
		_expect(int(_p1.get("upgrades_chosen")) >= 1, "el J1 aplico su propia carta")
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


## Fase 4/9: un jugador derribado con subidas PENDIENTES no abre cartas; se
## difieren (sin perderse) y se ofrecen al revivir.
func _setup_defer() -> void:
	# XP directa para acumular 2+ niveles pendientes en el P2 (abre su panel).
	_p2.call("add_experience", 400, true)
	_expect(bool(_panel.call("is_open", 2)), "el J2 tiene su panel abierto (varios niveles)")
	# Se derriba CON el panel abierto y resuelve una carta: la siguiente pendiente
	# debe DIFERIRSE (no reabrir el panel de un derribado) y despausar la partida.
	# La ventana de invulnerabilidad por golpe puede quedar congelada por la pausa
	# del panel: se limpia para que el derribo del test sea determinista.
	_p2.set("_damage_timer", 0.0)
	_p2.call("take_damage", 9999)
	_panel.emit_signal("card_chosen", 2, 0)
	_defer_frames = 0
	_phase = "defer_check"


func _check_defer() -> void:
	_defer_frames += 1
	if _defer_frames < 3:
		return
	_expect(bool(_p2.call("is_downed")), "el J2 esta derribado con niveles pendientes")
	_expect(not bool(_panel.call("is_open", 2)), "el panel del J2 se cierra al estar derribado")
	_expect(not get_tree().paused, "la partida NO queda congelada por pendientes diferidos")
	_phase = "defer_revive"


func _wait_defer_revive() -> void:
	_defer_frames += 1
	(_p1 as Node2D).global_position = (_p2 as Node2D).global_position + Vector2(40, 0)
	if bool(_p2.call("is_active")):
		_expect(true, "el J2 revivio de nuevo")
		_defer_frames = 0
		_phase = "defer_resolve"
		return
	if _defer_frames > 700:
		_fail("el J2 no revivio en la fase de diferido")
		_finish()


func _resolve_defer_pending() -> void:
	_defer_frames += 1
	if _defer_frames == 3:
		_expect(bool(_panel.call("is_open", 2)), "al revivir se reabren las cartas pendientes del J2")
	if _defer_frames < 3:
		return
	# Sin "Pasar" (Fase correccion): se resuelve eligiendo carta en ambos lados.
	if bool(_panel.call("is_open", 2)):
		_panel.emit_signal("card_chosen", 2, 0)
		return
	if bool(_panel.call("is_open", 1)):
		_panel.emit_signal("card_chosen", 1, 0)
		return
	if not get_tree().paused:
		_expect(true, "todas las cartas diferidas se resolvieron sin perder niveles")
		_finish()
	elif _defer_frames > 120:
		_fail("la partida sigue pausada tras resolver las cartas diferidas")
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
