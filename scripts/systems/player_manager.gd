extends Node2D
## PlayerManager (Fase Coop Local). Nodo de MainLevel que coordina a los jugadores.
##
## - SOLO: registra al unico jugador y no hace nada mas (comportamiento clasico).
## - LOCAL_COOP: instancia al Jugador 2, monta la camara cooperativa y un overlay de
##   HUD, gestiona el revive por proximidad y decide el Game Over del equipo.
##
## Diseño defensivo: todo lo coop se activa SOLO si GameFlow.is_coop(). El jugador 1
## sigue siendo el nodo Player de la escena (grupo "player"), asi que ningun sistema
## clasico cambia de comportamiento en solo.

const COOP_CAMERA_SCRIPT := preload("res://scripts/systems/coop_camera.gd")

signal player_downed(player_id: int)
signal player_revived(player_id: int)
signal team_wiped

## Escena del jugador (Player.tscn) para instanciar al P2 en coop.
@export var player_scene: PackedScene
## Jugador 1 ya presente en la escena.
@export var player_path: NodePath
@export var hud_path: NodePath

## Parametros de revive (Fase Coop, seccion 8).
@export var revive_radius: float = 74.0
@export var revive_time: float = 2.0
@export var revive_health_percent: float = 0.4
## Separacion inicial del P2 respecto al P1 al spawnear.
@export var p2_spawn_offset: Vector2 = Vector2(64, 0)

@export_group("Balance coop (Fase Coop 1.5)")
## Dano por jugador en coop: con 2 disparando, el total no debe duplicarse.
@export_range(0.5, 1.0, 0.01) var coop_player_damage_multiplier: float = 0.85

@export_group("Camara / correa (leash)")
## A partir de esta separacion (px) se avisa "¡No se separen!".
@export var soft_distance_limit: float = 700.0
## A partir de esta separacion (px) la correa empuja suavemente hacia el centro.
@export var hard_distance_limit: float = 950.0
## Fuerza de correccion de la correa por frame (0..1). Suave para no dar tirones.
@export_range(0.0, 0.5, 0.01) var leash_correction: float = 0.14
## Margen (px de pantalla) para considerar a un jugador "fuera de camara".
@export var offscreen_margin: float = 54.0

var _coop: bool = false
var _player1: Node2D
var _player2: Node2D
var _hud: Node
var _map_manager: Node
var _camera: Camera2D
var _ended: bool = false

## Progreso de revive por jugador derribado (segundos acumulados con un rescatador cerca).
var _revive_progress: Dictionary = {}
## Nodos del overlay de HUD coop (tarjetas de jugador con barra de vida).
var _overlay: CanvasLayer
var _p1_bar: ProgressBar
var _p2_bar: ProgressBar
var _p1_hp: Label
var _p2_hp: Label
var _revive_label: Label
var _revive_bar: ProgressBar
## Aviso de separacion (correa) y su marco de alerta.
var _separation_label: Label
var _separation_border: Panel
## Indicadores de jugador fuera de camara (uno por jugador, reutilizados).
var _offscreen_arrows: Dictionary = {}  # player_id -> {arrow: Polygon2D, tag: Label}

const P1_COLOR := Color(0.99, 0.72, 0.28)
const P2_COLOR := Color(0.4, 0.72, 1.0)


func _ready() -> void:
	add_to_group("player_manager")
	_player1 = get_node_or_null(player_path) as Node2D
	_hud = get_node_or_null(hud_path)
	_map_manager = get_tree().get_first_node_in_group("map_manager")

	var gf: Node = get_node_or_null("/root/GameFlow")
	_coop = gf != null and gf.has_method("is_coop") and gf.is_coop()

	_register_player(_player1)
	if not _coop:
		return

	# --- Modo cooperativo local ---
	# Se difiere: en _ready el MainLevel aun esta instanciando hijos y no admite
	# add_child (P2, camara, overlay). Al diferirlo corre cuando el arbol esta listo.
	call_deferred("_start_coop")


func _start_coop() -> void:
	_spawn_player_two()
	_setup_coop_camera()
	_setup_overlay()
	_apply_coop_difficulty()
	_apply_coop_damage()


## Reduce el dano por jugador (0.85) para que 2 jugadores no dupliquen el dano total.
func _apply_coop_damage() -> void:
	for p in get_players():
		if is_instance_valid(p) and p.has_method("get_weapon_manager"):
			var wm: Node = p.get_weapon_manager()
			if wm != null and wm.has_method("set_coop_damage_mult"):
				wm.set_coop_damage_mult(coop_player_damage_multiplier)


func _process(delta: float) -> void:
	if not _coop or _ended:
		return
	if _run_ended():
		_hide_coop_warnings()
		return

	var active := get_active_players()
	var downed := get_downed_players()

	# Game Over del equipo: todos derribados.
	if active.is_empty() and not downed.is_empty():
		_trigger_team_wipe()
		return

	_update_revive(delta, active, downed)
	_update_overlay(active, downed)
	_update_leash(active)
	_update_offscreen_indicators()


# --- Correa / separacion (Fase Coop 1.5) -------------------------------------

## Avisa al separarse (soft) y empuja suavemente hacia el centro al pasar el limite
## duro (hard), sin teletransportes ni tirones bruscos.
func _update_leash(active: Array) -> void:
	if active.size() < 2:
		_set_separation_warning(false)
		return
	var a := active[0] as Node2D
	var b := active[1] as Node2D
	var dist: float = a.global_position.distance_to(b.global_position)
	_set_separation_warning(dist > soft_distance_limit)
	if dist > hard_distance_limit:
		var mid: Vector2 = (a.global_position + b.global_position) * 0.5
		var half: float = hard_distance_limit * 0.5
		for p in [a, b]:
			var node := p as Node2D
			var dir: Vector2 = (node.global_position - mid)
			if dir.length() < 0.01:
				continue
			var target: Vector2 = mid + dir.normalized() * half
			node.global_position = node.global_position.lerp(target, leash_correction)


func _set_separation_warning(on: bool) -> void:
	if is_instance_valid(_separation_label):
		_separation_label.visible = on
	if is_instance_valid(_separation_border):
		_separation_border.visible = on
		if on:
			# Pulso sutil del borde para llamar la atencion sin marear.
			var a: float = 0.5 + 0.35 * abs(sin(Time.get_ticks_msec() * 0.006))
			_separation_border.modulate.a = a


# --- Indicadores de jugador fuera de camara ----------------------------------

func _update_offscreen_indicators() -> void:
	var cam: Camera2D = _camera
	if not is_instance_valid(cam):
		cam = get_viewport().get_camera_2d()
	if not is_instance_valid(cam):
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var center: Vector2 = cam.get_screen_center_position()
	var zoom: Vector2 = cam.zoom
	for pid in _offscreen_arrows.keys():
		var entry: Dictionary = _offscreen_arrows[pid]
		var arrow: Polygon2D = entry["arrow"]
		var tag: Label = entry["tag"]
		var player: Node2D = _player_by_id(int(pid))
		if not is_instance_valid(player) or (player.has_method("is_active") and not player.is_active()):
			arrow.visible = false
			tag.visible = false
			continue
		var world: Vector2 = player.global_position
		var screen: Vector2 = (world - center) * zoom + vp * 0.5
		var inside: bool = screen.x >= offscreen_margin and screen.x <= vp.x - offscreen_margin \
			and screen.y >= offscreen_margin and screen.y <= vp.y - offscreen_margin
		if inside:
			arrow.visible = false
			tag.visible = false
			continue
		# Fuera de camara: clava la flecha en el borde apuntando hacia el jugador.
		var clamped := Vector2(
			clampf(screen.x, offscreen_margin, vp.x - offscreen_margin),
			clampf(screen.y, offscreen_margin, vp.y - offscreen_margin))
		var dir: Vector2 = (screen - vp * 0.5)
		arrow.position = clamped
		arrow.rotation = dir.angle() if dir.length() > 0.01 else 0.0
		arrow.visible = true
		tag.position = clamped + Vector2(-8, 12)
		tag.visible = true


func _hide_coop_warnings() -> void:
	_set_separation_warning(false)
	for pid in _offscreen_arrows.keys():
		var entry: Dictionary = _offscreen_arrows[pid]
		entry["arrow"].visible = false
		entry["tag"].visible = false


func _player_by_id(pid: int) -> Node2D:
	if pid == 1:
		return _player1
	if pid == 2:
		return _player2
	return null


# --- Registro de jugadores ---------------------------------------------------

func _register_player(player: Node2D) -> void:
	if not is_instance_valid(player):
		return
	if player.has_signal("downed") and not player.downed.is_connected(_on_player_downed):
		player.downed.connect(_on_player_downed)
	if player.has_signal("revived") and not player.revived.is_connected(_on_player_revived):
		player.revived.connect(_on_player_revived)


func _spawn_player_two() -> void:
	if player_scene == null or not is_instance_valid(_player1):
		push_warning("PlayerManager: no hay player_scene o P1 para spawnear al P2")
		return
	var p2 := player_scene.instantiate() as Node2D
	if p2 == null:
		return
	p2.set("player_id", 2)
	_player1.get_parent().add_child(p2)
	p2.global_position = _player1.global_position + p2_spawn_offset
	_player2 = p2
	_register_player(p2)


# --- Consultas de estado (API para camara/spawner/HUD) -----------------------

func get_players() -> Array:
	return get_tree().get_nodes_in_group("players")


func get_active_players() -> Array:
	var result: Array = []
	for p in get_players():
		if is_instance_valid(p) and p.has_method("is_active") and p.is_active():
			result.append(p)
	return result


func get_downed_players() -> Array:
	var result: Array = []
	for p in get_players():
		if is_instance_valid(p) and p.has_method("is_downed") and p.is_downed():
			result.append(p)
	return result


func all_downed() -> bool:
	return get_active_players().is_empty() and not get_downed_players().is_empty()


# --- Armas de equipo (Fase Coop 1.5) -----------------------------------------
# Las cartas de arma se comparten: al elegir una, la reciben TODOS los jugadores.
# Asi P2 progresa igual que P1 y ambos WeaponManagers quedan sincronizados.

func get_active_weapon_managers() -> Array:
	var result: Array = []
	for p in get_players():
		if is_instance_valid(p) and p.has_method("get_weapon_manager"):
			var wm: Node = p.get_weapon_manager()
			if wm != null:
				result.append(wm)
	return result


func add_weapon_to_team(data) -> void:
	for wm in get_active_weapon_managers():
		if wm.has_method("add_weapon"):
			wm.add_weapon(data)


func apply_weapon_upgrade_to_team(weapon_id: StringName) -> void:
	for wm in get_active_weapon_managers():
		if wm.has_method("level_up_weapon"):
			wm.level_up_weapon(weapon_id)


## Aplica una carta de stat a los jugadores SECUNDARIOS (P2...). El P1 ya la aplico
## por su cuenta; aqui se replica solo el efecto PROPIO (sin tocar companeros).
func apply_stat_upgrade_to_secondaries(upgrade_id: StringName) -> void:
	for p in get_players():
		if is_instance_valid(p) and not p.is_in_group("player") and p.has_method("apply_upgrade"):
			p.apply_upgrade(upgrade_id, false)


## Punto central del equipo (jugadores activos). Lo puede usar la camara/spawner.
func team_center() -> Vector2:
	var active := get_active_players()
	if active.is_empty():
		active = get_players()
	if active.is_empty():
		return global_position
	var sum: Vector2 = Vector2.ZERO
	for p in active:
		sum += (p as Node2D).global_position
	return sum / float(active.size())


# --- Revive ------------------------------------------------------------------

func _update_revive(delta: float, active: Array, downed: Array) -> void:
	# Limpia progreso de jugadores que ya no estan derribados.
	for key in _revive_progress.keys():
		if not is_instance_valid(key) or not (key in downed):
			_revive_progress.erase(key)

	for d in downed:
		var rescuer := _nearest_rescuer(d as Node2D, active)
		if rescuer != null:
			var progress: float = float(_revive_progress.get(d, 0.0)) + delta
			if progress >= revive_time:
				_revive_progress.erase(d)
				if d.has_method("revive_player"):
					d.revive_player(revive_health_percent)
			else:
				_revive_progress[d] = progress
		else:
			# Se aleja el rescatador: el progreso se cancela.
			_revive_progress.erase(d)


func _nearest_rescuer(downed_player: Node2D, active: Array) -> Node2D:
	var best: Node2D = null
	var best_distance: float = revive_radius
	for a in active:
		if not is_instance_valid(a) or a == downed_player:
			continue
		var dist: float = downed_player.global_position.distance_to((a as Node2D).global_position)
		if dist <= best_distance:
			best_distance = dist
			best = a
	return best


func revive_fraction(downed_player: Node) -> float:
	return clampf(float(_revive_progress.get(downed_player, 0.0)) / max(0.01, revive_time), 0.0, 1.0)


# --- Game Over del equipo ----------------------------------------------------

func _trigger_team_wipe() -> void:
	if _ended:
		return
	_ended = true
	team_wiped.emit()
	# Reutiliza el Game Over clasico: el jugador principal emite "died", que ya
	# escuchan GameManager y MapManager. Nada extra que cablear.
	if is_instance_valid(_player1) and _player1.has_method("force_team_death"):
		_player1.force_team_death()
	elif is_instance_valid(_player1) and _player1.has_signal("died"):
		_player1.died.emit()


func _on_player_downed(id: int) -> void:
	player_downed.emit(id)


func _on_player_revived(id: int) -> void:
	player_revived.emit(id)


func _run_ended() -> bool:
	return is_instance_valid(_map_manager) and _map_manager.has_method("is_run_ended") and _map_manager.is_run_ended()


# --- Camara coop -------------------------------------------------------------

func _setup_coop_camera() -> void:
	var cam := Camera2D.new()
	cam.set_script(COOP_CAMERA_SCRIPT)
	cam.name = "CoopCamera"
	_player1.get_parent().add_child(cam)
	cam.global_position = team_center()
	cam.make_current()
	_camera = cam


# --- Dificultad coop ---------------------------------------------------------

func _apply_coop_difficulty() -> void:
	var spawner: Node = get_tree().get_first_node_in_group("enemy_spawner")
	if spawner == null:
		# El spawner no esta en grupo; se busca por la escena.
		var root := _player1.get_parent()
		spawner = root.get_node_or_null("EnemySpawner")
	if spawner != null and spawner.has_method("set_coop_players"):
		spawner.set_coop_players(get_players().size())


# --- Overlay de HUD coop -----------------------------------------------------

func _setup_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 50
	add_child(_overlay)

	# Tarjeta de equipo (roster) abajo a la izquierda: una fila por jugador con
	# icono de color, etiqueta, barra de vida y estado. Estilizada y ordenada.
	var roster := PanelContainer.new()
	roster.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	roster.position = Vector2(22, -150)
	var roster_box := StyleBoxFlat.new()
	roster_box.bg_color = Color(0.06, 0.07, 0.10, 0.82)
	roster_box.border_color = Color(0.3, 0.34, 0.42, 0.7)
	roster_box.set_border_width_all(1)
	roster_box.set_corner_radius_all(10)
	roster_box.set_content_margin_all(10)
	roster.add_theme_stylebox_override("panel", roster_box)
	_overlay.add_child(roster)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	roster.add_child(rows)

	var p1_refs: Dictionary = _build_player_row(rows, "P1", P1_COLOR)
	_p1_bar = p1_refs["bar"]
	_p1_hp = p1_refs["hp"]
	var p2_refs: Dictionary = _build_player_row(rows, "P2", P2_COLOR)
	_p2_bar = p2_refs["bar"]
	_p2_hp = p2_refs["hp"]

	# Aviso de revive centrado en la parte inferior.
	var revive_box := VBoxContainer.new()
	revive_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	revive_box.position = Vector2(-140, -90)
	revive_box.custom_minimum_size = Vector2(280, 0)
	revive_box.add_theme_constant_override("separation", 4)
	_overlay.add_child(revive_box)

	_revive_label = _make_label(revive_box, Color(0.7, 1.0, 0.8))
	_revive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_revive_bar = ProgressBar.new()
	_revive_bar.custom_minimum_size = Vector2(280, 14)
	_revive_bar.min_value = 0.0
	_revive_bar.max_value = 1.0
	_revive_bar.show_percentage = false
	_revive_bar.visible = false
	revive_box.add_child(_revive_bar)

	_setup_separation_warning()
	_setup_offscreen_indicators()


## Marco de alerta + texto "¡No se separen!" cuando los jugadores se alejan mucho.
func _setup_separation_warning() -> void:
	_separation_border = Panel.new()
	_separation_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_separation_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.draw_center = false  # solo el borde, sin tapar la accion
	box.border_color = Color(1.0, 0.5, 0.35, 0.9)
	box.set_border_width_all(6)
	_separation_border.add_theme_stylebox_override("panel", box)
	_separation_border.visible = false
	_overlay.add_child(_separation_border)

	_separation_label = Label.new()
	_separation_label.text = "¡No se separen!"
	_separation_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_separation_label.position = Vector2(-90, 70)
	_separation_label.add_theme_font_size_override("font_size", 22)
	_separation_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.4))
	_separation_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_separation_label.add_theme_constant_override("outline_size", 5)
	_separation_label.visible = false
	_overlay.add_child(_separation_label)


## Crea (una sola vez) una flecha + etiqueta por jugador, reutilizadas cada frame.
func _setup_offscreen_indicators() -> void:
	for pid in [1, 2]:
		var color: Color = P1_COLOR if pid == 1 else P2_COLOR
		var arrow := Polygon2D.new()
		arrow.polygon = PackedVector2Array([Vector2(0, -9), Vector2(20, 0), Vector2(0, 9)])
		arrow.color = color
		arrow.visible = false
		_overlay.add_child(arrow)
		var tag := Label.new()
		tag.text = "P%d" % pid
		tag.add_theme_font_size_override("font_size", 15)
		tag.add_theme_color_override("font_color", color)
		tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		tag.add_theme_constant_override("outline_size", 4)
		tag.visible = false
		_overlay.add_child(tag)
		_offscreen_arrows[pid] = {"arrow": arrow, "tag": tag}


func _make_label(parent: Node, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	parent.add_child(label)
	return label


## Fila de jugador del roster: [icono color][P1/P2][barra de vida][vida/estado].
func _build_player_row(parent: Node, tag: String, color: Color) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(12, 12)
	dot.color = color
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)

	var name_label := Label.new()
	name_label.text = tag
	name_label.custom_minimum_size = Vector2(28, 0)
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", color)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	name_label.add_theme_constant_override("outline_size", 3)
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(132, 14)
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_hp_bar(bar, Color(0.35, 0.85, 0.45))
	row.add_child(bar)

	var hp := Label.new()
	hp.custom_minimum_size = Vector2(96, 0)
	hp.add_theme_font_size_override("font_size", 13)
	hp.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
	hp.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	hp.add_theme_constant_override("outline_size", 3)
	hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hp)

	return {"bar": bar, "hp": hp}


func _style_hp_bar(bar: ProgressBar, fill: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.06, 0.09, 0.95)
	bg.border_color = Color(0.26, 0.29, 0.36, 0.85)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(5)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.border_color = fill.lightened(0.25)
	fg.border_width_top = 2
	fg.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)


func _update_overlay(_active: Array, downed: Array) -> void:
	if _overlay == null:
		return
	_update_player_row(_player1, _p1_bar, _p1_hp)
	_update_player_row(_player2, _p2_bar, _p2_hp)

	# Aviso de revive: muestra el primer jugador derribado y su progreso.
	if downed.is_empty():
		_revive_label.visible = false
		_revive_bar.visible = false
		return
	var d: Node = downed[0]
	var pid: int = int(d.get_player_id()) if d.has_method("get_player_id") else 0
	var frac: float = revive_fraction(d)
	_revive_label.visible = true
	if frac > 0.0:
		_revive_label.text = "Reviviendo P%d..." % pid
		_revive_bar.visible = true
		_revive_bar.value = frac
	else:
		_revive_label.text = "P%d derribado — acércate para revivir" % pid
		_revive_bar.visible = false


## Actualiza una fila del roster con la vida/estado del jugador. Barra verde->rojo
## por ratio; en DERRIBADO la barra se vacia en rojo y el texto lo indica.
func _update_player_row(player: Node, bar: ProgressBar, hp: Label) -> void:
	if not is_instance_valid(bar) or not is_instance_valid(hp):
		return
	if not is_instance_valid(player):
		bar.value = 0.0
		hp.text = "—"
		return
	var cur: int = int(player.get("current_health"))
	var mx: int = maxi(1, int(player.get("max_health")))
	var downed: bool = player.has_method("is_downed") and player.is_downed()
	if downed:
		bar.value = 0.0
		_recolor_hp_bar(bar, Color(0.7, 0.25, 0.25))
		hp.text = "DERRIBADO"
		hp.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4))
		return
	var ratio: float = clampf(float(cur) / float(mx), 0.0, 1.0)
	bar.value = ratio * 100.0
	# Verde -> ambar -> rojo segun la vida.
	var fill: Color = Color(0.85, 0.35, 0.35).lerp(Color(0.35, 0.85, 0.45), ratio)
	_recolor_hp_bar(bar, fill)
	hp.text = "%d/%d" % [maxi(0, cur), mx]
	hp.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))


func _recolor_hp_bar(bar: ProgressBar, fill: Color) -> void:
	var fg: StyleBox = bar.get_theme_stylebox("fill")
	if fg is StyleBoxFlat:
		(fg as StyleBoxFlat).bg_color = fill
		(fg as StyleBoxFlat).border_color = fill.lightened(0.25)
