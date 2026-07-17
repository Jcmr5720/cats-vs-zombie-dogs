extends Node2D
## Pruebas de integracion del Sistema Minimapa. Se ejecuta como ESCENA para
## contar con autoloads reales (GameFlow, Feedback, Settings...):
##   godot --headless --path . res://tests/TestMinimap.tscn
## Valida por fases:
## 1) SOLO: el HUD monta MinimapSystem con 1 minimapa visible, jugador centrado.
## 2) Puntos de enemigos en el DotLayer (y elites diferenciados).
## 3) Jefe que aparece DESPUES de empezar: marcador de jefe; al morir, desaparece.
## 4) Entidad lejisima: marcador sujetado al borde (off_map) dentro del panel.
## 5) Accion minimap_expand (input real): el panel crece y vuelve.
## 6) Pausa: el minimapa se oculta; al reanudar, vuelve.
## 7) Horda grande (120+): agrupado por celdas en vez de un punto por enemigo.
## 8) Liberacion masiva de enemigos registrados: sin errores ni puntos fantasma.
## 9) COOP: 2 minimapas (uno por mitad), companero lejano indicado en el borde.

const MAIN_LEVEL := "res://scenes/levels/MainLevel.tscn"


## Enemigo "elite" minimo: expone la misma propiedad interna que enemy.gd
## (_elite_kind) que el minimapa lee de forma defensiva.
class EliteStub:
	extends Node2D
	var _elite_kind: StringName = &"gigante"

var _failures: Array[String] = []
var _checks: int = 0
var _frames: int = 0
var _phase: String = "boot"
## Espera en SEGUNDOS reales (headless corre a FPS sin tope: los frames no sirven
## para esperar cadencias del radar, que van por tiempo).
var _wait_seconds: float = 0.0
var _next_phase: String = ""
var _level: Node
var _player: Node2D
var _stub_boss: Node2D
var _stub_rescue: Node2D
var _horde: Array = []
var _done: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var gf: Node = get_node_or_null("/root/GameFlow")
	if gf == null:
		_fail("no existe el autoload GameFlow")
		_finish()
		return
	gf.set("game_mode", "solo")
	_level = (load(MAIN_LEVEL) as PackedScene).instantiate()
	add_child(_level)


func _process(delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _wait_seconds > 0.0:
		_wait_seconds -= delta
		if _wait_seconds <= 0.0:
			_phase = _next_phase
		return
	match _phase:
		"boot":
			if _frames >= 20:
				_check_solo_structure()
		"dots":
			_check_enemy_dots()
		"boss_appear":
			_check_boss_marker()
		"boss_gone":
			_check_boss_gone()
		"edge":
			_check_edge_clamp()
		"expand":
			_check_expand()
		"expand_check":
			_check_expand_applied()
		"pause":
			_check_pause_hidden()
		"unpause":
			_check_unpause_visible()
		"horde":
			_check_horde_clusters()
		"free_horde":
			_check_freed_enemies()
		"coop_boot":
			_boot_coop()
		"coop_check":
			_check_coop()


func _wait(seconds: float, next_phase: String) -> void:
	_wait_seconds = seconds
	_next_phase = next_phase


# --- Helpers de acceso ----------------------------------------------------------

func _hud() -> Node:
	return get_tree().get_first_node_in_group("hud")


func _system() -> Node:
	var hud := _hud()
	return hud.get_node_or_null("MinimapSystem") if hud != null else null


func _controller(id: int) -> Control:
	var hud := _hud()
	return hud.get_node_or_null("Minimap%d" % id) as Control if hud != null else null


func _registry() -> Node:
	var sys := _system()
	return sys.get_node_or_null("MinimapEntityRegistry") if sys != null else null


func _dot_layer(ctrl: Control) -> Control:
	return ctrl.get_node_or_null("Dots") as Control if ctrl != null else null


func _visible_markers(ctrl: Control, kind: StringName) -> int:
	var count: int = 0
	var pool = ctrl.get("_marker_pool")
	if pool == null:
		return 0
	for m in pool:
		if is_instance_valid(m) and (m as CanvasItem).visible and m.get("kind") == kind:
			count += 1
	return count


func _spawn_stub(groups: Array, pos: Vector2) -> Node2D:
	var n := Node2D.new()
	for g in groups:
		n.add_to_group(g)
	_level.add_child(n)
	n.global_position = pos
	return n


# --- Fase 1: estructura en solo ---------------------------------------------------

func _check_solo_structure() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node2D
	_expect(_player != null, "existe el jugador")
	var sys := _system()
	_expect(sys != null, "el HUD monta MinimapSystem")
	var c1 := _controller(1)
	_expect(c1 != null, "existe el minimapa del J1")
	_expect(_controller(2) == null, "en solo NO hay minimapa del J2")
	_expect(_registry() != null, "existe el MinimapEntityRegistry")
	if c1 == null or _player == null:
		_finish()
		return
	_expect(c1.visible, "el minimapa esta visible en partida")
	_expect(c1.size.x > 100.0, "el panel tiene tamano util (%.0f px)" % c1.size.x)
	# El jugador local se dibuja centrado.
	var players: int = _visible_markers(c1, &"player")
	_expect(players >= 1, "hay marcador de jugador (encontrados: %d)" % players)
	var pool = c1.get("_marker_pool")
	for m in pool:
		if m.get("kind") == &"player" and (m as CanvasItem).visible:
			var center: Vector2 = c1.size * 0.5
			_expect(((m as Control).position - center).length() < 1.0, "el jugador local esta centrado en el radar")
			break
	_wait(0.3, "dots")


# --- Fase 2: puntos de enemigos ------------------------------------------------------

func _check_enemy_dots() -> void:
	# Enemigos garantizados cerca del jugador (ademas de los del spawner real).
	for i in 6:
		_spawn_stub(["enemies"], _player.global_position + Vector2(120 + i * 40, 60))
	# Un "elite" con la propiedad interna que usa enemy.gd (_elite_kind).
	var elite := EliteStub.new()
	elite.add_to_group("enemies")
	_level.add_child(elite)
	elite.global_position = _player.global_position + Vector2(-160, 0)
	var reg := _registry()
	reg.call("refresh_now", &"enemies")
	_wait(0.8, "boss_appear")


# --- Fase 3: jefe que aparece a mitad de partida --------------------------------------

func _check_boss_marker() -> void:
	var c1 := _controller(1)
	var dots := _dot_layer(c1)
	var normal: int = (dots.get("normal_points") as PackedVector2Array).size()
	var elites: int = (dots.get("elite_points") as PackedVector2Array).size()
	_expect(normal > 0, "hay puntos rojos de zombies en el DotLayer (%d)" % normal)
	_expect(elites > 0, "el elite se dibuja como punto especial (%d)" % elites)

	# Jefe y mini-jefe surgen DESPUES de iniciada la partida (grupos reales).
	_stub_boss = _spawn_stub(["enemies", "boss"], _player.global_position + Vector2(300, 0))
	_spawn_stub(["enemies", "miniboss"], _player.global_position + Vector2(0, 260))
	_stub_rescue = _spawn_stub(["rescue_points"], _player.global_position + Vector2(-260, 120))
	var reg := _registry()
	reg.call("refresh_now", &"boss")
	reg.call("refresh_now", &"miniboss")
	reg.call("refresh_now", &"rescue_points")
	_wait(0.5, "boss_gone")


func _check_boss_gone() -> void:
	var c1 := _controller(1)
	_expect(_visible_markers(c1, &"boss") >= 1, "el jefe tiene marcador grande en el minimapa")
	_expect(_visible_markers(c1, &"miniboss") >= 1, "el mini-jefe tiene su marcador")
	_expect(_visible_markers(c1, &"rescue") >= 1, "el punto de rescate aparece en amarillo")
	# El jefe muere: su marcador debe desaparecer sin errores.
	_stub_boss.queue_free()
	var reg := _registry()
	reg.call("refresh_now", &"boss")
	_wait(0.5, "edge")


# --- Fase 4: entidad muy lejana sujeta al borde ---------------------------------------

func _check_edge_clamp() -> void:
	var c1 := _controller(1)
	_expect(_visible_markers(c1, &"boss") == 0, "el marcador del jefe desaparece al morir")
	_stub_boss = _spawn_stub(["enemies", "boss"], _player.global_position + Vector2(50000, -20000))
	var reg := _registry()
	reg.call("refresh_now", &"boss")
	_wait(0.5, "expand")


func _check_expand() -> void:
	var c1 := _controller(1)
	var pool = c1.get("_marker_pool")
	var found: bool = false
	for m in pool:
		if m.get("kind") == &"boss" and (m as CanvasItem).visible:
			found = true
			_expect(bool(m.get("off_map")), "el jefe lejano se marca como flecha de borde (off_map)")
			var pos: Vector2 = (m as Control).position
			var inside: bool = pos.x >= 0.0 and pos.x <= c1.size.x and pos.y >= 0.0 and pos.y <= c1.size.y
			_expect(inside, "la flecha de borde queda DENTRO del panel (%s)" % str(pos))
	_expect(found, "el jefe a 50k px sigue indicado en el minimapa")
	_stub_boss.queue_free()

	# Fase 5: ampliar via la ACCION DE INPUT real.
	_expect(InputMap.has_action("minimap_expand"), "existe la accion minimap_expand")
	var before: float = c1.size.x
	_expect(not bool(c1.call("is_expanded")), "el minimapa arranca sin ampliar")
	var ev := InputEventAction.new()
	ev.action = "minimap_expand"
	ev.pressed = true
	Input.parse_input_event(ev)
	set_meta("size_before_expand", before)
	_wait(0.3, "expand_check")


func _check_expand_applied() -> void:
	var c1 := _controller(1)
	var before: float = float(get_meta("size_before_expand"))
	_expect(bool(c1.call("is_expanded")), "la accion de input amplia el minimapa")
	_expect(c1.size.x > before + 50.0, "el panel ampliado es mas grande (%.0f -> %.0f)" % [before, c1.size.x])
	# Vuelve al tamano normal para el resto del test.
	c1.call("set_expanded", false)
	var sys := _system()
	sys.set("_expanded", false)
	_wait(0.2, "pause")


# --- Fase 6: pausa ---------------------------------------------------------------------

func _check_pause_hidden() -> void:
	get_tree().paused = true
	_wait(0.2, "unpause")


func _check_unpause_visible() -> void:
	var c1 := _controller(1)
	_expect(not c1.visible, "en pausa el minimapa se oculta")
	get_tree().paused = false
	_wait(0.2, "horde")


# --- Fase 7: horda grande (agrupado) ----------------------------------------------------

func _check_horde_clusters() -> void:
	var c1 := _controller(1)
	_expect(c1.visible, "al reanudar el minimapa vuelve a verse")
	for i in 140:
		var offset := Vector2(randf_range(-500, 500), randf_range(-500, 500))
		_horde.append(_spawn_stub(["enemies"], _player.global_position + offset))
	var reg := _registry()
	reg.call("refresh_now", &"enemies")
	_wait(0.8, "free_horde")


func _check_freed_enemies() -> void:
	var c1 := _controller(1)
	var dots := _dot_layer(c1)
	var clusters: int = (dots.get("cluster_points") as PackedVector2Array).size()
	var normal: int = (dots.get("normal_points") as PackedVector2Array).size()
	_expect(clusters > 0, "con 140+ enemigos se agrupan en celdas (%d celdas)" % clusters)
	_expect(normal == 0, "en modo horda no hay un punto por enemigo")
	# Fase 8: liberacion masiva mientras siguen registrados en la foto del registry.
	for e in _horde:
		if is_instance_valid(e):
			e.queue_free()
	_horde.clear()
	_wait(1.2, "coop_boot")


# --- Fase 9: coop ------------------------------------------------------------------------

func _boot_coop() -> void:
	var c1 := _controller(1)
	var dots := _dot_layer(c1)
	var clusters: int = (dots.get("cluster_points") as PackedVector2Array).size()
	_expect(clusters == 0, "tras liberar la horda no quedan celdas fantasma (%d)" % clusters)

	# Reinicia el nivel en modo coop local.
	_level.queue_free()
	var gf: Node = get_node_or_null("/root/GameFlow")
	gf.set("game_mode", "local_coop")
	_wait(0.5, "coop_spawn")
	_next_phase = "coop_spawn"
	# El add del nivel nuevo se hace cuando termina la espera: usa un callback simple.
	get_tree().create_timer(0.05).timeout.connect(func() -> void:
		_level = (load(MAIN_LEVEL) as PackedScene).instantiate()
		add_child(_level)
		_frames = 0
		_wait(1.0, "coop_check"))


func _check_coop() -> void:
	var c1 := _controller(1)
	var c2 := _controller(2)
	_expect(c1 != null, "coop: existe el minimapa del J1")
	_expect(c2 != null, "coop: existe el minimapa del J2 (creado al entrar el P2)")
	if c1 == null or c2 == null:
		_finish()
		return
	_expect(bool(c1.get("coop")), "coop: el minimapa J1 usa identidad coop")
	_expect(is_zero_approx(float(c1.get("_anchor_x"))) and not bool(c1.get("_grow_left")), "coop: minimapa J1 en la esquina exterior izquierda")
	_expect(is_equal_approx(float(c2.get("_anchor_x")), 1.0) and bool(c2.get("_grow_left")), "coop: minimapa J2 en la esquina exterior derecha")
	_expect(c1.visible and c2.visible, "coop: ambos minimapas visibles")

	# Jugadores muy separados: cada radar sigue mostrando al companero en el borde.
	var p1: Node2D
	var p2: Node2D
	for p in get_tree().get_nodes_in_group("players"):
		if int(p.get("player_id")) <= 1:
			p1 = p
		else:
			p2 = p
	_expect(p1 != null and p2 != null, "coop: hay 2 jugadores")
	if p1 != null and p2 != null:
		p2.global_position = p1.global_position + Vector2(6000, 0)
		var reg := _registry()
		reg.call("refresh_now", &"players")
		_wait(0.5, "coop_partner")
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			var markers: int = _visible_markers(c1, &"player")
			_expect(markers >= 2, "coop: el companero LEJANO sigue indicado en el radar del J1 (%d marcadores)" % markers)
			var pool = c1.get("_marker_pool")
			var found_edge: bool = false
			for m in pool:
				if m.get("kind") == &"player" and (m as CanvasItem).visible and bool(m.get("off_map")):
					found_edge = true
			_expect(found_edge, "coop: el companero lejano usa flecha de borde")
			_finish())
	else:
		_finish()


# --- Reporte ------------------------------------------------------------------------------

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
	print("TestMinimap: %d checks, %d fallos" % [_checks, _failures.size()])
	for f in _failures:
		printerr(" - " + f)
	get_tree().paused = false
	get_tree().quit(0 if _failures.is_empty() else 1)
