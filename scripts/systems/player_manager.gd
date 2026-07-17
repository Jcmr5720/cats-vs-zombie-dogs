extends Node2D
## PlayerManager (Rework Coop: pantalla dividida). Nodo de MainLevel que coordina
## a los jugadores.
##
## - SOLO: registra al unico jugador y no hace nada mas (comportamiento clasico).
## - LOCAL_COOP: instancia al Jugador 2, monta la PANTALLA DIVIDIDA (dos camaras
##   independientes, sin correa ni limites de separacion), gestiona el revive por
##   proximidad y decide el Game Over del equipo.
##
## Diseño defensivo: todo lo coop se activa SOLO si GameFlow.is_coop(). El jugador 1
## sigue siendo el nodo Player de la escena (grupo "player"), asi que ningun sistema
## clasico cambia de comportamiento en solo.

const SPLIT_SCREEN_SCRIPT := preload("res://scripts/systems/coop_split_screen.gd")

signal player_downed(player_id: int)
signal player_revived(player_id: int)
signal team_wiped

## Escena del jugador (Player.tscn) para instanciar al P2 en coop.
@export var player_scene: PackedScene
## Jugador 1 ya presente en la escena.
@export var player_path: NodePath
@export var hud_path: NodePath

## Parametros de revive (proximidad + tiempo sostenido).
@export var revive_radius: float = 74.0
@export var revive_time: float = 2.0
@export var revive_health_percent: float = 0.4
## Separacion inicial del P2 respecto al P1 al spawnear.
@export var p2_spawn_offset: Vector2 = Vector2(64, 0)

@export_group("Balance coop")
## Dano por jugador en coop. Con builds INDEPENDIENTES (cada uno con sus cartas)
## el equipo escala menos que cuando las armas eran compartidas: 0.9 en vez del
## antiguo 0.85.
@export_range(0.5, 1.0, 0.01) var coop_player_damage_multiplier: float = 0.9

var _coop: bool = false
var _player1: Node2D
var _player2: Node2D
var _hud: Node
var _map_manager: Node
var _split_screen: Control
var _ended: bool = false

## Progreso de revive por jugador derribado (segundos acumulados con un rescatador cerca).
var _revive_progress: Dictionary = {}
## Acumulador del bonus de cercania (Fase 5): regen lenta cuando van juntos.
var _proximity_timer: float = 0.0
## Aviso de mando desconectado (Fase 7): overlay + pausa segura.
var _disconnect_layer: CanvasLayer
var _paused_by_disconnect: bool = false


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
	# add_child (P2, pantalla dividida). Al diferirlo corre cuando el arbol esta listo.
	call_deferred("_start_coop")


func _start_coop() -> void:
	_spawn_player_two()
	_setup_split_screen()
	_apply_coop_difficulty()
	_apply_coop_damage()
	_park_root_camera()
	# Fase 7: si un mando se desconecta a mitad de partida, pausa segura + aviso.
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


## El viewport raiz queda TAPADO por el split, pero Godot lo sigue dibujando con la
## camara embebida del P1 (un render extra del mundo). Con un zoom extremo su vista
## cubre ~nada del mundo y ese render se vuelve despreciable. El spawner ya no
## depende de esta camara en coop (usa el zoom real de las mitades).
func _park_root_camera() -> void:
	var cam := _player1.get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.zoom = Vector2.ONE * CoopConfig.ROOT_CAMERA_PARK_ZOOM
		cam.position_smoothing_enabled = false


## Reduce el dano por jugador para que 2 builds no dupliquen el dano total.
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
		return

	var active := get_active_players()
	var downed := get_downed_players()

	# Game Over del equipo: todos derribados.
	if active.is_empty() and not downed.is_empty():
		_trigger_team_wipe()
		return

	_update_revive(delta, active, downed)
	_update_proximity_bonus(delta, active)


## Bonus suave de cercania (Fase 5): jugar juntos regenera un poco de vida a ambos.
## No es una correa: separarse solo pierde el bonus, no penaliza.
func _update_proximity_bonus(delta: float, active: Array) -> void:
	if active.size() < 2:
		_proximity_timer = 0.0
		return
	var a: Node2D = active[0] as Node2D
	var b: Node2D = active[1] as Node2D
	if a.global_position.distance_to(b.global_position) > CoopConfig.PROXIMITY_RADIUS:
		_proximity_timer = 0.0
		return
	_proximity_timer += delta
	if _proximity_timer >= CoopConfig.PROXIMITY_REGEN_INTERVAL:
		_proximity_timer -= CoopConfig.PROXIMITY_REGEN_INTERVAL
		for p in active:
			if p.has_method("heal"):
				p.heal(CoopConfig.PROXIMITY_REGEN_AMOUNT)


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
	# La camara embebida del P2 se desactiva: en split cada jugador usa la camara
	# de SU SubViewport, y el viewport raiz (tapado por el split) sigue con la de P1.
	var p2_cam := p2.get_node_or_null("Camera2D") as Camera2D
	if p2_cam != null:
		p2_cam.enabled = false
	_player2 = p2
	_register_player(p2)


## Monta la pantalla dividida como primer hijo del HUD (CanvasLayer): por encima
## del mundo del viewport raiz y por debajo de todos los paneles del HUD.
func _setup_split_screen() -> void:
	if not is_instance_valid(_player1) or not is_instance_valid(_player2):
		return
	if _hud == null:
		push_warning("PlayerManager: sin HUD para montar la pantalla dividida")
		return
	var split := Control.new()
	split.set_script(SPLIT_SCREEN_SCRIPT)
	split.name = "CoopSplitScreen"
	_hud.add_child(split)
	_hud.move_child(split, 0)
	split.call("setup", [_player1, _player2], self)
	_split_screen = split
	# El bloque de stats del P1 del HUD clasico se oculta: cada mitad ya muestra
	# vida/XP/nivel de su jugador.
	var top_left := (_hud as Node).get_node_or_null("TopLeft") as Control
	if top_left != null:
		top_left.visible = false


# --- Consultas de estado (API para spawner/HUD/split) -------------------------

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


## Punto central del equipo (jugadores activos). Lo puede usar el spawner.
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
					# Recompensa al rescatador (Fase 5): XP directa, sin reparto.
					if rescuer.has_method("add_experience"):
						rescuer.add_experience(CoopConfig.RESCUER_XP_REWARD, true)
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


# --- Desconexion de mando (Fase 7) --------------------------------------------
# Si un mando se va a mitad de partida, pausa segura + aviso persistente. Al
# reconectar CUALQUIER mando se reanuda (Godot conserva el device id al reconectar,
# asi que la asignacion J2 = gamepad sigue valiendo). No se pierde progreso.

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if _ended or _run_ended():
		return
	if not connected:
		_show_disconnect_notice(device)
	elif _paused_by_disconnect:
		_hide_disconnect_notice()


func _show_disconnect_notice(device: int) -> void:
	if _disconnect_layer == null:
		_disconnect_layer = CanvasLayer.new()
		_disconnect_layer.layer = 90
		_disconnect_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		var dim := ColorRect.new()
		dim.color = Color(0.02, 0.03, 0.05, 0.72)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_disconnect_layer.add_child(dim)
		var label := Label.new()
		label.name = "Notice"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.set_anchors_preset(Control.PRESET_CENTER)
		label.position = Vector2(-260, -30)
		label.custom_minimum_size = Vector2(520, 0)
		label.add_theme_font_size_override("font_size", 24)
		label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		label.add_theme_constant_override("outline_size", 6)
		_disconnect_layer.add_child(label)
		add_child(_disconnect_layer)
	var notice := _disconnect_layer.get_node("Notice") as Label
	notice.text = "Mando %d desconectado\nReconectalo para continuar" % device
	_disconnect_layer.visible = true
	# Solo pausa si la partida no estaba ya pausada por otra cosa (cartas/menu):
	# asi al reanudar no pisamos esa otra pausa.
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_disconnect = true


func _hide_disconnect_notice() -> void:
	if _disconnect_layer != null:
		_disconnect_layer.visible = false
	if _paused_by_disconnect:
		_paused_by_disconnect = false
		get_tree().paused = false


# --- Dificultad coop ---------------------------------------------------------

func _apply_coop_difficulty() -> void:
	var spawner: Node = get_tree().get_first_node_in_group("enemy_spawner")
	if spawner == null:
		# El spawner no esta en grupo; se busca por la escena.
		var root := _player1.get_parent()
		spawner = root.get_node_or_null("EnemySpawner")
	if spawner != null and spawner.has_method("set_coop_players"):
		spawner.set_coop_players(get_players().size())
