extends Node2D
## FASE 13 (coop) — Ejercita en COOP local las rutas de UI de claridad que ni el
## TestCoop ni el soak disparan, y verifica que no crashean ni dejan huerfanos:
##   godot --headless --path . res://tests/TestCoopClarity.tscn
##
## 1) El J2 recoge un power-up del suelo -> toast en SU mitad (lado 2).
## 2) El J2 recoge un arma con hueco -> toast de arma nueva.
## 3) Panel de build (tecla B): una columna por jugador, sin pausar.
## 4) Leyenda del minimapa (expand): visible sin error.
## 5) Sin nodos huerfanos tras liberar los paneles.

const MAIN_LEVEL := "res://scenes/levels/MainLevel.tscn"
const PowerUpPickupScript := preload("res://scripts/loot/power_up_pickup.gd")
const WeaponPickupScript := preload("res://scripts/loot/weapon_pickup.gd")

var _failures: Array[String] = []
var _checks: int = 0
var _frames: int = 0
var _level: Node
var _p1: Node
var _p2: Node
var _hud: Node
var _phase: String = "boot"
var _busy: bool = false
var _done: bool = false
var _orphans_baseline: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var gf: Node = get_node_or_null("/root/GameFlow")
	if gf == null:
		_fail("no existe GameFlow")
		_finish()
		return
	gf.set("game_mode", "local_coop")
	var packed: PackedScene = load(MAIN_LEVEL)
	_level = packed.instantiate()
	add_child(_level)


func _process(_delta: float) -> void:
	if _done or _busy:
		return
	_frames += 1
	match _phase:
		"boot":
			if _frames >= 20:
				_boot()
		"powerup":
			_test_powerup()
		"weapon":
			_test_weapon()
		"build_panel":
			_test_build_panel()
		"legend":
			_test_legend()
		"orphans":
			_test_orphans()


func _boot() -> void:
	var players := get_tree().get_nodes_in_group("players")
	for p in players:
		if int(p.get("player_id")) <= 1:
			_p1 = p
		else:
			_p2 = p
	_check(_p1 != null and _p2 != null, "los 2 jugadores existen en coop")
	_hud = get_tree().get_first_node_in_group("hud")
	_check(_hud != null and _hud.has_method("show_loot_toast"), "el HUD expone show_loot_toast")
	if _p1 == null or _p2 == null or _hud == null:
		_finish()
		return
	_orphans_baseline = _orphan_count()
	_phase = "powerup"


func _test_powerup() -> void:
	_busy = true
	# Lejos de ambos para que el collect sea el manual del test, no el de contacto.
	var data: PowerUpData = load("res://data/powerups/weapon_damage.tres") as PowerUpData
	var pickup = PowerUpPickupScript.spawn(data, _level, (_p2 as Node2D).global_position + Vector2(700, 700))
	await get_tree().process_frame
	var before: int = int(_p2.get("upgrades_chosen"))
	var ok: bool = bool(pickup.call("collect", _p2))
	_check(ok, "el J2 recoge el power-up en coop")
	_check(int(_p2.get("upgrades_chosen")) == before + 1, "el power-up aplico al J2")
	# El HUD registro el toast del lado 2 (mitad del J2).
	await get_tree().process_frame
	var by_side = _hud.get("_loot_toast_by_side")
	_check(by_side is Dictionary and by_side.has(2), "el toast del power-up salio en la mitad del J2")
	_check(int(_p2.get("powerup_counts").get(&"weapon_damage", 0)) >= 1,
		"el conteo de mejoras del J2 subio (para el panel de build)")
	_phase = "weapon"
	_busy = false


func _test_weapon() -> void:
	_busy = true
	# El J2 tiene hueco: un arma que no posea entra sola al tocarla. Comprobamos
	# que el pickup construye su tarjeta y que recogerla no crashea en coop.
	var weapon = load("res://data/weapons/yarn_bomb.tres")
	var wpickup = WeaponPickupScript.spawn(weapon, _level, (_p2 as Node2D).global_position)
	for _i in 12:
		await get_tree().process_frame
	var wm: Node = _p2.call("get_weapon_manager")
	_check(wm != null and wm.has_weapon(&"yarn_bomb"), "el J2 recoge el arma con hueco libre en coop")
	var by_side = _hud.get("_loot_toast_by_side")
	_check(by_side is Dictionary and by_side.has(2), "el toast de arma nueva salio en la mitad del J2")
	_phase = "build_panel"
	_busy = false


func _test_build_panel() -> void:
	_busy = true
	# Abrir el panel de build no debe pausar ni fallar y debe cubrir a los 2.
	_hud.call("_toggle_build_panel")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not get_tree().paused, "el panel de build NO pausa la partida (coop)")
	var panel = _hud.get("_build_panel")
	_check(panel != null and is_instance_valid(panel), "el panel de build se creo")
	if panel != null:
		# Debe mencionar a los dos jugadores (tags J1/J2) y las 4 secciones.
		_check(_find_text(panel, "Armas"), "el panel de build lista Armas")
		_check(_find_text(panel, "Mutaciones"), "el panel de build lista Mutaciones")
		var tag2: String = CoopConfig.player_tag(2)
		_check(_find_text(panel, tag2), "el panel de build muestra la columna del J2 (%s)" % tag2)
	# Cerrar: liberar el panel (no debe dejar huerfanos).
	_hud.call("_toggle_build_panel")
	await get_tree().process_frame
	_check(_hud.get("_build_panel") == null, "cerrar el panel de build lo libera")
	_phase = "legend"
	_busy = false


func _test_legend() -> void:
	_busy = true
	# Ampliar el radar (lo que hace el handler de Tab/Select): enciende la leyenda.
	# Se llama set_expanded directo porque en headless el input sintetico no
	# propaga a _unhandled_input de forma fiable.
	var controllers := _find_nodes_by_script(_hud, "minimap_controller.gd")
	_check(controllers.size() == 2, "hay 2 minimapas en coop (uno por mitad)")
	for c in controllers:
		c.call("set_expanded", true)
	for _i in 6:
		await get_tree().process_frame
	var legends_visible: int = 0
	var legends_total: int = 0
	for c in controllers:
		var legend = c.get("_legend")
		if legend != null and is_instance_valid(legend):
			legends_total += 1
			if legend.visible:
				legends_visible += 1
	_check(legends_total == 2, "cada minimapa coop tiene su leyenda (%d)" % legends_total)
	_check(legends_visible == 2, "ambas leyendas aparecen al ampliar (%d visibles)" % legends_visible)
	# Contraer: la leyenda se apaga.
	for c in controllers:
		c.call("set_expanded", false)
	for _i in 4:
		await get_tree().process_frame
	var still_visible: int = 0
	for c in controllers:
		var legend = c.get("_legend")
		if legend != null and is_instance_valid(legend) and legend.visible:
			still_visible += 1
	_check(still_visible == 0, "al contraer, las leyendas se ocultan (%d aun visibles)" % still_visible)
	_phase = "orphans"
	_busy = false


func _test_orphans() -> void:
	_busy = true
	for _i in 6:
		await get_tree().process_frame
	var now: int = _orphan_count()
	# Tolerancia: los sistemas de combate crean/liberan nodos; solo alertamos de
	# una fuga NETA grande atribuible a la UI de la fase.
	_check(now - _orphans_baseline <= 12,
		"sin fuga de nodos por la UI de claridad (delta huerfanos: %d)" % (now - _orphans_baseline))
	_finish()
	_busy = false


# --- Utilidades ---------------------------------------------------------------

func _orphan_count() -> int:
	var perf: Object = Engine.get_singleton(&"Performance")
	if perf != null and perf.has_method("get_monitor"):
		return int(perf.call("get_monitor", 3))  # OBJECT_ORPHAN_NODE_COUNT
	return 0


func _find_text(root: Node, needle: String) -> bool:
	if root is Label and (root as Label).text.contains(needle):
		return true
	for child in root.get_children():
		if _find_text(child, needle):
			return true
	return false


func _find_nodes_by_script(root: Node, script_suffix: String, out: Array = []) -> Array:
	var scr = root.get_script()
	if scr != null and str(scr.resource_path).ends_with(script_suffix):
		out.append(root)
	for child in root.get_children():
		_find_nodes_by_script(child, script_suffix, out)
	return out


func _check(condition: bool, name: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(name)
		print("  [FALLO] %s" % name)
	else:
		print("  OK  %s" % name)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _done:
		return
	_done = true
	print("")
	if _failures.is_empty():
		print("TestCoopClarity: OK (%d comprobaciones)" % _checks)
	else:
		print("TestCoopClarity: %d/%d FALLOS" % [_failures.size(), _checks])
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("shutdown"):
		audio.shutdown()
	get_tree().quit(0 if _failures.is_empty() else 1)
