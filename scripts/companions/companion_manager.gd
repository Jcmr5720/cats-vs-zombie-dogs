extends Node2D
## Registra gatos rescatados, distribuye formacion y coordina HUD/balance.
## Rework: ademas empuja el escalado central (vida/daño segun minuto y jugador),
## expone el lider estable para la IA segura y gestiona la orden de reagrupar.

const CompanionData = preload("res://scripts/companions/companion_data.gd")
const CompanionBalance = preload("res://scripts/companions/companion_balance.gd")

signal companions_changed(current: int, maximum: int)
signal companion_rescued(data: CompanionData)
signal companion_states_changed(snapshots: Array)

@export var player_path: NodePath
@export var hud_path: NodePath
@export var companion_scene: PackedScene
@export var projectile_scene: PackedScene
@export var max_companions: int = 4
@export var formation_radius: float = 74.0
@export var follow_smoothness: float = 5.2
@export var companion_spacing: float = 26.0

var _player: Node2D
var _hud: Node
var _companions: Array[Node2D] = []
var _damage_multiplier: float = 1.0
var _cooldown_multiplier: float = 1.0
var _medic_heal_bonus: int = 0
var _incoming_damage_multiplier: float = 1.0
var _revive_time_multiplier: float = 1.0
var _colony_bond_bonus: float = 0.0
## Bonus del Refugio (Fase 10), leidos una vez en _ready.
var _shelter_health_bonus: int = 0
var _shelter_police_mult: float = 1.0
var _shelter_engineer_mult: float = 1.0


func _ready() -> void:
	add_to_group("companion_manager")
	_player = get_node_or_null(player_path)
	_hud = get_node_or_null(hud_path)
	if _hud != null:
		if _hud.has_method("on_companions_changed"):
			companions_changed.connect(_hud.on_companions_changed)
		if _hud.has_method("update_companion_roster"):
			companion_states_changed.connect(_hud.update_companion_roster)
	# Mejoras permanentes y Refugio SOLO en Modo Historia (Partida libre = reto puro).
	if _is_story_run():
		# Mejora permanente "Corazon de Leon" (Fase 09): +daño de compañeros.
		var mp: Node = get_node_or_null("/root/MetaProgression")
		if mp != null and mp.has_method("companion_damage_mult"):
			var mult: float = float(mp.companion_damage_mult())
			if mult > 1.001:
				multiply_damage(mult)
		# Refugio Felino (Fase 10): vida plana, cura del medico y daño por tipo.
		var shelter: Node = get_node_or_null("/root/Shelter")
		if shelter != null and shelter.has_method("get_bonuses"):
			var bonuses: Dictionary = shelter.get_bonuses()
			_shelter_health_bonus = int(round(float(bonuses.get("companion_health_bonus", 0.0))))
			_shelter_police_mult = 1.0 + float(bonuses.get("companion_police_damage_bonus", 0.0))
			_shelter_engineer_mult = 1.0 + float(bonuses.get("companion_engineer_damage_bonus", 0.0))
			var medic_bonus: int = int(round(float(bonuses.get("medic_heal_bonus", 0.0))))
			if medic_bonus > 0:
				increase_medic_heal(medic_bonus)
	companions_changed.emit(_companions.size(), max_companions)
	_emit_roster_changed()


## Reloj de partida propio (para el escalado por minuto) y tick de escalado.
var _elapsed_time: float = 0.0
var _scaling_timer: float = 0.0


func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_node_or_null(player_path)
		if not is_instance_valid(_player):
			return
	_elapsed_time += delta
	_prune_invalid_companions()
	_update_formation()
	_scaling_timer -= delta
	if _scaling_timer <= 0.0:
		_scaling_timer = CompanionBalance.SCALING_UPDATE_INTERVAL
		_update_scaling()


## Orden rapida "Reagruparse" (accion `companion_regroup`, tecla Q / boton Y del
## mando). En coop cualquiera de los dos jugadores puede activarla (la accion
## incluye teclado y mando). Los compañeros no consumen su habilidad.
func _unhandled_input(event: InputEvent) -> void:
	if not InputMap.has_action(&"companion_regroup"):
		return
	if event.is_action_pressed(&"companion_regroup"):
		command_regroup()


func command_regroup() -> void:
	var any: bool = false
	for companion in _companions:
		if is_instance_valid(companion) and companion.has_method("start_regroup"):
			companion.start_regroup()
			any = true
	if any and _hud != null and _hud.has_method("show_event_message"):
		_hud.show_event_message("¡Reagrupando gatos!")


## Escalado central (formulas en CompanionBalance): cada 2 s lee minuto de
## partida, nivel y vida maxima del lider, y empuja los factores a cada
## compañero. Factores separados de los upgrades: sin doble aplicacion.
func _update_scaling() -> void:
	var leader: Node2D = _active_leader()
	if not is_instance_valid(leader):
		return
	var level_value = leader.get("level")
	var max_health_value = leader.get("max_health")
	var player_level: int = int(level_value) if level_value != null else 1
	var player_max_health: int = int(max_health_value) if max_health_value != null else 100
	var health_bonus: int = CompanionBalance.health_bonus(_elapsed_time / 60.0, player_max_health)
	var damage_scale: float = CompanionBalance.damage_scale(player_level)
	for companion in _companions:
		if is_instance_valid(companion) and companion.has_method("set_scaling"):
			companion.set_scaling(health_bonus, damage_scale)


## Lider estable para la IA de los compañeros (prefiere P1 mientras este activo:
## evita saltos constantes de referencia entre P1 y P2 en coop).
func get_leader() -> Node2D:
	return _active_leader()


## ¿Hay algun compañero de este rol activo (no derribado)? Lo usan las sinergias.
func has_active_role(role: StringName) -> bool:
	for companion in _companions:
		if not is_instance_valid(companion):
			continue
		var data = companion.get("companion_data")
		if data == null or data.role != role:
			continue
		if companion.has_method("is_downed") and not companion.is_downed():
			return true
	return false


## Aviso de compañero demasiado lejos (con antirrebote en el propio compañero).
func notify_companion_far(data: CompanionData) -> void:
	if data != null and _hud != null and _hud.has_method("show_event_message"):
		_hud.show_event_message("%s esta lejos" % data.display_name)


func can_add_companion() -> bool:
	return _companions.size() < max_companions


func get_companion_count() -> int:
	return _companions.size()


func get_active_companion_count() -> int:
	var count: int = 0
	for companion in _companions:
		if is_instance_valid(companion) and companion.has_method("is_downed") and not companion.is_downed():
			count += 1
	return count


func get_downed_companion_count() -> int:
	var count: int = 0
	for companion in _companions:
		if is_instance_valid(companion) and companion.has_method("is_downed") and companion.is_downed():
			count += 1
	return count


func get_companion_snapshots() -> Array:
	var result: Array = []
	for companion in _companions:
		if is_instance_valid(companion) and companion.has_method("build_snapshot"):
			result.append(companion.build_snapshot())
	return result


func rescue_companion(data: CompanionData) -> bool:
	if data == null or companion_scene == null or projectile_scene == null:
		return false
	if not can_add_companion() or not is_instance_valid(_player):
		return false

	var companion := companion_scene.instantiate() as Node2D
	if companion == null:
		return false

	companion.global_position = _player.global_position + Vector2.RIGHT.rotated(randf() * TAU) * 42.0
	add_child(companion)
	companion.call("configure", data, _player, self, projectile_scene)
	companion.connect("snapshot_changed", Callable(self, "_on_companion_snapshot_changed"))
	companion.connect("downed", Callable(self, "_on_companion_downed"))
	companion.connect("revived", Callable(self, "_on_companion_revived"))
	_companions.append(companion)
	_apply_bonuses_to(companion)
	# El recien rescatado recibe el escalado de partida al instante (no nace debil).
	_scaling_timer = 0.0
	_update_formation()
	companions_changed.emit(_companions.size(), max_companions)
	companion_rescued.emit(data)
	if _hud != null and _hud.has_method("show_event_message"):
		_hud.show_event_message("%s unido" % data.display_name)
	_emit_roster_changed()
	_update_player_companion_bonus()
	return true


func multiply_damage(multiplier: float) -> void:
	_damage_multiplier = max(0.1, _damage_multiplier * multiplier)
	_apply_bonuses()


func multiply_cooldown(multiplier: float) -> void:
	_cooldown_multiplier = clampf(_cooldown_multiplier * multiplier, 0.35, 3.0)
	_apply_bonuses()


func increase_medic_heal(amount: int) -> void:
	_medic_heal_bonus += amount
	_apply_bonuses()


func multiply_incoming_damage(multiplier: float) -> void:
	_incoming_damage_multiplier = clampf(_incoming_damage_multiplier * multiplier, 0.3, 2.0)
	_apply_bonuses()


func multiply_revive_time(multiplier: float) -> void:
	_revive_time_multiplier = clampf(_revive_time_multiplier * multiplier, 0.3, 2.0)
	_apply_bonuses()


func increase_colony_bond_bonus(amount: float) -> void:
	_colony_bond_bonus += amount
	_update_player_companion_bonus()


func _apply_bonuses() -> void:
	for companion in _companions:
		_apply_bonuses_to(companion)


func _apply_bonuses_to(companion: Node2D) -> void:
	if not is_instance_valid(companion) or not companion.has_method("set_bonuses"):
		return
	# Refugio (Fase 10): el daño extra del refugio es POR TIPO de compañero.
	var type_mult: float = 1.0
	var data = companion.get("companion_data")
	if data != null:
		match data.id:
			&"police_cat":
				type_mult = _shelter_police_mult
			&"engineer_cat":
				type_mult = _shelter_engineer_mult
	companion.call(
		"set_bonuses",
		_damage_multiplier * type_mult,
		_cooldown_multiplier,
		_medic_heal_bonus,
		_incoming_damage_multiplier,
		_revive_time_multiplier
	)
	# Vida extra plana del refugio (Camas de Colonia).
	if _shelter_health_bonus > 0 and companion.has_method("set_shelter_health_bonus"):
		companion.call("set_shelter_health_bonus", _shelter_health_bonus)


func _prune_invalid_companions() -> void:
	var removed_any: bool = false
	for index in range(_companions.size() - 1, -1, -1):
		if not is_instance_valid(_companions[index]):
			_companions.remove_at(index)
			removed_any = true
	if removed_any:
		companions_changed.emit(_companions.size(), max_companions)
		_emit_roster_changed()
		_update_player_companion_bonus()


func _update_formation() -> void:
	var slots: Array[Node2D] = []
	for companion in _companions:
		if is_instance_valid(companion) and companion.has_method("is_downed") and not companion.is_downed():
			slots.append(companion)

	var count: int = slots.size()
	if count == 0:
		return

	# Coop: los companeros siguen al lider ACTIVO (no se quedan pegados a un P1
	# derribado). En solo el lider es siempre el unico jugador.
	var leader: Node2D = _active_leader()
	if not is_instance_valid(leader):
		return

	var facing: Vector2 = Vector2.DOWN
	if leader.has_method("get_last_facing_direction"):
		facing = leader.get_last_facing_direction()
	if facing == Vector2.ZERO:
		facing = Vector2.DOWN

	var behind: Vector2 = -facing.normalized()
	var base_angle: float = behind.angle()
	var spread: float = deg_to_rad(44.0 * max(count - 1, 1))

	for index in count:
		var companion := slots[index]
		var angle_offset: float = 0.0
		if count > 1:
			angle_offset = lerpf(-spread * 0.5, spread * 0.5, float(index) / float(count - 1))
		var radius: float = formation_radius
		if companion.has_method("get_follow_distance"):
			radius = max(radius, float(companion.get_follow_distance()))
		radius += max(0, count - 2) * companion_spacing * 0.25
		var target: Vector2 = leader.global_position + Vector2.RIGHT.rotated(base_angle + angle_offset) * radius
		companion.call("set_formation_target", target, follow_smoothness)


## Lider de formacion: el jugador ACTIVO (prefiere P1). En solo es siempre _player.
func _active_leader() -> Node2D:
	if is_instance_valid(_player) and (not _player.has_method("is_active") or _player.is_active()):
		return _player
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and p.has_method("is_active") and p.is_active():
			return p
	return _player


## True solo en Modo Historia (donde aplican mejoras permanentes y Refugio).
func _is_story_run() -> bool:
	var gf: Node = get_node_or_null("/root/GameFlow")
	return gf != null and gf.has_method("is_story_run") and gf.is_story_run()


func _emit_roster_changed() -> void:
	companion_states_changed.emit(get_companion_snapshots())


func _on_companion_snapshot_changed(_snapshot: Dictionary) -> void:
	_emit_roster_changed()
	_update_player_companion_bonus()


func _on_companion_downed(data: CompanionData) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(&"companion_downed")
	if _hud != null and _hud.has_method("show_event_message"):
		_hud.show_event_message("%s caido" % data.display_name)
	_emit_roster_changed()
	_update_player_companion_bonus()


func _on_companion_revived(data: CompanionData) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(&"companion_revived")
	if _hud != null and _hud.has_method("show_event_message"):
		_hud.show_event_message("%s vuelve" % data.display_name)
	_emit_roster_changed()
	_update_player_companion_bonus()


func _update_player_companion_bonus() -> void:
	var multiplier: float = 1.0
	if _colony_bond_bonus > 0.0 and get_active_companion_count() >= 2:
		multiplier += _colony_bond_bonus
	# Coop: el Vinculo felino es un bono de EQUIPO; se aplica a todos los jugadores
	# (cada uno a su propio arma), no solo al P1. En solo solo existe el P1.
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty() and is_instance_valid(_player):
		players = [_player]
	for p in players:
		if is_instance_valid(p) and p.has_method("set_external_damage_multiplier"):
			p.set_external_damage_multiplier(multiplier)
