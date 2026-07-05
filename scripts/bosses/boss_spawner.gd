extends Node2D
## Instancia jefes y mini-jefes a peticion del WaveEventManager, los escala con la
## dificultad actual (leida del EnemySpawner) y conecta el jefe principal a la barra
## de vida del HUD. Mantiene una referencia al jefe activo para evitar duplicados.
##
## Los jefes se cuelgan del nivel (get_parent()), asi al reiniciar con R
## (reload_current_scene) se liberan junto con sus invocaciones y la barra del HUD.

const BossData = preload("res://scripts/bosses/boss_data.gd")

## Avisan al MapManager para los objetivos de partida (Fase 06).
signal boss_defeated(data: BossData)
signal miniboss_defeated(data: BossData)

@export var boss_scene: PackedScene
@export var miniboss_scene: PackedScene
@export var player_path: NodePath
@export var hud_path: NodePath
@export var enemy_spawner_path: NodePath
## Datos por defecto (se pueden pasar otros desde WaveEventManager).
@export var default_boss_data: BossData
@export var default_miniboss_data: BossData

var _player: Node2D
var _hud: Node
var _enemy_spawner: Node
var _active_boss: Node2D


func _ready() -> void:
	add_to_group("boss_spawner")
	_player = get_node_or_null(player_path)
	_hud = get_node_or_null(hud_path)
	_enemy_spawner = get_node_or_null(enemy_spawner_path)


func has_active_boss() -> bool:
	return is_instance_valid(_active_boss)


## Aparece un mini-jefe. `data` opcional; si es null usa `default_miniboss_data`.
func spawn_miniboss(data: BossData = null) -> Node2D:
	var resolved: BossData = data if data != null else default_miniboss_data
	if resolved == null or miniboss_scene == null:
		return null
	var miniboss := miniboss_scene.instantiate() as Node2D
	if miniboss == null:
		return null
	miniboss.global_position = _spawn_position(560.0)
	get_parent().add_child(miniboss)
	miniboss.call("configure", resolved, _difficulty())
	if miniboss.has_signal("died"):
		miniboss.connect("died", Callable(self, "_on_miniboss_died"))
	_announce("Mini-jefe: %s" % resolved.display_name)
	Feedback.shake(0.3)
	Feedback.hit_effect(miniboss.global_position, resolved.accent_color, 0.8, 4.0)
	_play_audio(&"event_alert")
	return miniboss


## Aparece el jefe principal (uno a la vez). Conecta su vida a la barra del HUD.
func spawn_boss(data: BossData = null) -> Node2D:
	if has_active_boss():
		return _active_boss
	var resolved: BossData = data if data != null else default_boss_data
	if resolved == null or boss_scene == null:
		return null
	var boss := boss_scene.instantiate() as Node2D
	if boss == null:
		return null
	boss.global_position = _spawn_position(620.0)
	get_parent().add_child(boss)
	boss.call("configure", resolved, _difficulty())
	if boss.has_signal("health_changed"):
		boss.connect("health_changed", Callable(self, "_on_boss_health_changed"))
	if boss.has_signal("died"):
		boss.connect("died", Callable(self, "_on_boss_died"))
	_active_boss = boss

	if _hud != null and _hud.has_method("show_boss_bar"):
		_hud.show_boss_bar(resolved.display_name, boss.get("max_health"))
	_announce("¡%s aparece!" % resolved.display_name)
	Feedback.shake(0.5)
	Feedback.hit_effect(boss.global_position, resolved.accent_color, 1.0, 5.0)
	_play_audio(&"boss_appear")
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_music"):
		audio.play_music(&"boss")
	return boss


# --- Señales -----------------------------------------------------------------

func _on_boss_health_changed(current: int, maximum: int, _display_name: String) -> void:
	if _hud != null and _hud.has_method("update_boss_bar"):
		_hud.update_boss_bar(current, maximum)


func _on_boss_died(data: BossData) -> void:
	_active_boss = null
	if _hud != null:
		if _hud.has_method("hide_boss_bar"):
			_hud.hide_boss_bar()
		if _hud.has_method("show_event_message"):
			_hud.show_event_message("%s derrotado" % data.display_name, 2.0)
	Feedback.shake(0.5)
	_play_audio(&"boss_die")
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_music"):
		audio.play_music(&"gameplay")
	boss_defeated.emit(data)


func _on_miniboss_died(data: BossData) -> void:
	if _hud != null and _hud.has_method("show_event_message"):
		_hud.show_event_message("%s derrotado" % data.display_name, 2.0)
	miniboss_defeated.emit(data)


func _play_audio(name: StringName) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(name)


# --- Utilidades --------------------------------------------------------------

func _difficulty() -> float:
	if is_instance_valid(_enemy_spawner) and _enemy_spawner.has_method("get_difficulty_score"):
		return float(_enemy_spawner.get_difficulty_score())
	return 0.0


## Punto de aparicion en un anillo alrededor del jugador (entra "en escena").
func _spawn_position(distance: float) -> Vector2:
	if not is_instance_valid(_player):
		_player = get_node_or_null(player_path)
	var origin: Vector2 = _player.global_position if is_instance_valid(_player) else Vector2.ZERO
	return origin + Vector2.RIGHT.rotated(randf() * TAU) * distance


func _announce(text: String) -> void:
	if _hud != null and _hud.has_method("show_event_message"):
		_hud.show_event_message(text, 2.0)
