extends Node2D
## Pruebas de la eliminacion del salto de tarjetas (Fase correccion).
##   godot --headless --path . res://tests/TestCardsNoSkip.tscn
## Valida en partida REAL:
## SOLO:
## - No existe boton "Pasar" ni señal/metodo de skip.
## - ESC no cierra la seleccion; clic fuera no consume el nivel.
## - No se otorga XP ni cura por intentar cerrar.
## - Cada eleccion consume EXACTAMENTE un nivel pendiente; varios pendientes se
##   procesan en cadena; doble confirmacion no aplica dos veces.
## COOP:
## - El panel no tiene opcion de saltar; los controles de un jugador no eligen
##   por el otro; sin auto-pick por defecto (solo via ajuste de accesibilidad).

const MAIN_LEVEL := "res://scenes/levels/MainLevel.tscn"

var _failures: Array[String] = []
var _checks: int = 0
var _phase: String = "boot"
var _wait_seconds: float = 0.0
var _next_phase: String = ""
var _level: Node
var _player: Node
var _done: bool = false
var _frames: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var gf: Node = get_node_or_null("/root/GameFlow")
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
			if _frames >= 15:
				_check_solo_no_skip()
		"escape":
			_check_escape_and_outside()
		"choose":
			_check_choice_consumes_one()
		"multi":
			_check_multi_pending()
		"coop_boot":
			_boot_coop()
		"coop_check":
			_check_coop_no_skip()
		"coop_isolation":
			_check_coop_isolation()
		"coop_autopick":
			_check_no_autopick()


func _wait(seconds: float, next_phase: String) -> void:
	_wait_seconds = seconds
	_next_phase = next_phase
	_phase = "waiting"


func _hud() -> Node:
	return get_tree().get_first_node_in_group("hud")


func _manager() -> Node:
	for n in _find_all(_level, "UpgradeManager"):
		return n
	return null


func _find_all(root: Node, node_name: String) -> Array:
	var out: Array = []
	if root == null:
		return out
	if root.name == node_name:
		out.append(root)
	for c in root.get_children():
		out.append_array(_find_all(c, node_name))
	return out


func _coop_panel() -> Node:
	return get_tree().get_first_node_in_group("coop_upgrade_panel")


func _press_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


# --- SOLO -----------------------------------------------------------------------

func _check_solo_no_skip() -> void:
	_player = get_tree().get_first_node_in_group("player")
	var hud := _hud()
	var um := _manager()
	_expect(um != null, "existe UpgradeManager")
	_expect(hud != null and not hud.has_signal("skip_requested"), "el HUD ya no tiene señal skip_requested")
	_expect(um != null and not um.has_method("request_skip"), "UpgradeManager ya no tiene request_skip")
	# El HUD no debe contener ningun boton "Pasar".
	_expect(not _any_button_contains(hud, "Pasar"), "no existe boton 'Pasar' en el HUD")

	# Sube de nivel: la seleccion se abre y pausa.
	_player.call("add_experience", int(_player.get("experience_to_level")), true)
	_wait(0.3, "escape")


func _any_button_contains(root: Node, text: String) -> bool:
	if root is Button and (root as Button).text.contains(text):
		return true
	for c in root.get_children():
		if _any_button_contains(c, text):
			return true
	return false


func _check_escape_and_outside() -> void:
	var hud := _hud()
	var panel: CanvasItem = hud.get("upgrade_panel")
	var um := _manager()
	_expect(panel.visible, "la seleccion esta abierta")
	_expect(get_tree().paused, "la partida esta pausada durante la seleccion")
	var pending_before: int = int(um.get("_pending_level_ups"))
	var xp_before: int = int(_player.get("experience"))
	var hp_before: int = int(_player.get("current_health"))

	# ESC / boton atras del mando: no debe cerrar ni consumir.
	_press_action("ui_cancel")
	_press_action("p2_pause")
	# Clic fuera del panel (esquina superior izquierda).
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(5, 5)
	Input.parse_input_event(click)

	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		_expect(panel.visible, "ESC/atras/clic-fuera NO cierran la seleccion")
		_expect(get_tree().paused, "la partida sigue pausada")
		_expect(int(um.get("_pending_level_ups")) == pending_before, "el nivel pendiente NO se consumio")
		_expect(int(_player.get("experience")) == xp_before, "no se otorgo XP por intentar cerrar")
		_expect(int(_player.get("current_health")) == hp_before, "no se otorgo cura por intentar cerrar")
		_phase = "choose"
		_wait_seconds = 0.0)
	_phase = "waiting"
	_wait_seconds = 999.0


func _check_choice_consumes_one() -> void:
	var hud := _hud()
	var um := _manager()
	var upgrades_before: int = int(_player.get("upgrades_chosen"))
	# Doble confirmacion en el mismo frame: solo debe aplicar UNA.
	hud.emit_signal("upgrade_card_selected", 0)
	hud.emit_signal("upgrade_card_selected", 0)
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		_expect(int(_player.get("upgrades_chosen")) == upgrades_before + 1,
			"doble confirmacion aplica exactamente UNA mejora")
		_expect(int(um.get("_pending_level_ups")) == 0, "consume exactamente un nivel pendiente")
		_expect(not get_tree().paused, "al elegir, la partida se reanuda")
		_expect(not (hud.get("upgrade_panel") as CanvasItem).visible, "el panel se cierra tras elegir")
		_phase = "multi"
		_wait_seconds = 0.0)
	_phase = "waiting"
	_wait_seconds = 999.0


func _check_multi_pending() -> void:
	var hud := _hud()
	var um := _manager()
	var upgrades_before: int = int(_player.get("upgrades_chosen"))
	# Dos subidas de golpe: dos selecciones encadenadas obligatorias.
	var need: int = int(_player.get("experience_to_level"))
	_player.call("add_experience", need, true)
	_player.call("add_experience", 9999, true)
	get_tree().create_timer(0.25).timeout.connect(func() -> void:
		var pending: int = int(um.get("_pending_level_ups"))
		_expect(pending >= 2 or bool(um.get("_selection_active")), "varios niveles quedan encolados (%d pendientes)" % pending)
		# Resuelve todos eligiendo carta 0.
		_drain_solo_selections(hud, um, upgrades_before, 0)
		)
	_phase = "waiting"
	_wait_seconds = 999.0


func _drain_solo_selections(hud: Node, um: Node, upgrades_before: int, guard: int) -> void:
	if guard > 30:
		_fail("las selecciones encadenadas no terminaron")
		_phase = "coop_boot"
		_wait_seconds = 0.0
		return
	if (hud.get("upgrade_panel") as CanvasItem).visible:
		hud.emit_signal("upgrade_card_selected", 0)
		get_tree().create_timer(0.12).timeout.connect(func() -> void:
			_drain_solo_selections(hud, um, upgrades_before, guard + 1))
		return
	var gained: int = int(_player.get("upgrades_chosen")) - upgrades_before
	_expect(gained >= 2, "cada nivel encolado exigio su eleccion (aplicadas: %d)" % gained)
	_expect(int(um.get("_pending_level_ups")) == 0, "no se pierden niveles pendientes")
	_expect(not get_tree().paused, "todo resuelto: partida reanudada")
	_phase = "coop_boot"
	_wait_seconds = 0.0


# --- COOP -----------------------------------------------------------------------

func _boot_coop() -> void:
	_level.queue_free()
	var gf: Node = get_node_or_null("/root/GameFlow")
	gf.set("game_mode", "local_coop")
	get_tree().create_timer(0.1).timeout.connect(func() -> void:
		_level = (load(MAIN_LEVEL) as PackedScene).instantiate()
		add_child(_level)
		_wait(1.0, "coop_check"))
	_phase = "waiting"
	_wait_seconds = 999.0


func _p(pid: int) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and int(p.get("player_id")) == pid:
			return p
	return null


func _check_coop_no_skip() -> void:
	var p2 := _p(2)
	_expect(p2 != null, "coop: hay J2")
	if p2 == null:
		_finish()
		return
	p2.call("add_experience", int(p2.get("experience_to_level")), true)
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		var panel := _coop_panel()
		_expect(panel != null, "coop: el panel de cartas existe")
		if panel == null:
			_finish()
			return
		_expect(not panel.has_signal("skip_chosen"), "coop: el panel ya no tiene señal skip_chosen")
		_expect(not _any_button_contains(panel, "Pasar"), "coop: no existe boton 'Pasar'")
		_expect(bool(panel.call("is_open", 2)) and not bool(panel.call("is_open", 1)),
			"coop: solo el lado del J2 esta abierto")
		_phase = "coop_isolation"
		_wait_seconds = 0.0)
	_phase = "waiting"
	_wait_seconds = 999.0


func _check_coop_isolation() -> void:
	var panel := _coop_panel()
	var p2 := _p(2)
	var upgrades_before: int = int(p2.get("upgrades_chosen"))
	# El confirmar del J1 NO debe elegir por el J2 (lado 2 abierto, lado 1 cerrado).
	_press_action("p1_card_confirm")
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		_expect(bool(panel.call("is_open", 2)), "coop: el confirmar de J1 no elige por J2")
		_expect(int(p2.get("upgrades_chosen")) == upgrades_before, "coop: J2 sigue sin mejora aplicada")
		_phase = "coop_autopick"
		_wait_seconds = 0.0)
	_phase = "waiting"
	_wait_seconds = 999.0


func _check_no_autopick() -> void:
	var panel := _coop_panel()
	var p2 := _p(2)
	# Acelera el reloj: si existiera auto-pick por defecto, 30 s "de juego" de
	# inactividad lo dispararian. El panel debe seguir abierto (sin accesibilidad).
	Engine.time_scale = 25.0
	get_tree().create_timer(35.0).timeout.connect(func() -> void:
		Engine.time_scale = 1.0
		_expect(bool(panel.call("is_open", 2)), "coop: SIN auto-pick por defecto (panel sigue abierto tras 35 s)")
		# Via de accesibilidad explicita: al activar el ajuste, el auto-pick actua.
		var settings: Node = get_node_or_null("/root/Settings")
		if settings != null and settings.has_method("set_value"):
			settings.set_value("card_auto_pick", true)
			if panel.has_method("refresh_accessibility"):
				panel.call("refresh_accessibility")
			Engine.time_scale = 25.0
			get_tree().create_timer(35.0).timeout.connect(func() -> void:
				Engine.time_scale = 1.0
				_expect(not bool(panel.call("is_open", 2)),
					"coop: con el ajuste de accesibilidad activo, el auto-pick resuelve")
				_expect(int(_p(2).get("upgrades_chosen")) >= 1, "coop: el auto-pick aplico una carta REAL")
				settings.set_value("card_auto_pick", false)
				_finish())
		else:
			_finish())
	_phase = "waiting"
	_wait_seconds = 9999.0


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
	Engine.time_scale = 1.0
	print("")
	print("TestCardsNoSkip: %d checks, %d fallos" % [_checks, _failures.size()])
	for f in _failures:
		printerr(" - " + f)
	get_tree().paused = false
	get_tree().quit(0 if _failures.is_empty() else 1)
