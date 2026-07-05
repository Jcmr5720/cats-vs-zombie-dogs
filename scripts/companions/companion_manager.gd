extends Node2D
## Registra gatos rescatados, distribuye formacion y coordina HUD/balance.

const CompanionData = preload("res://scripts/companions/companion_data.gd")

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


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_node_or_null(player_path)
		if not is_instance_valid(_player):
			return
	_prune_invalid_companions()
	_update_formation()


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

	var facing: Vector2 = Vector2.DOWN
	if _player.has_method("get_last_facing_direction"):
		facing = _player.get_last_facing_direction()
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
		var target: Vector2 = _player.global_position + Vector2.RIGHT.rotated(base_angle + angle_offset) * radius
		companion.call("set_formation_target", target, follow_smoothness)


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
	if not is_instance_valid(_player) or not _player.has_method("set_external_damage_multiplier"):
		return
	var multiplier: float = 1.0
	if _colony_bond_bonus > 0.0 and get_active_companion_count() >= 2:
		multiplier += _colony_bond_bonus
	_player.set_external_damage_multiplier(multiplier)
