extends Node2D
## Pruebas del rework de compañeros. Se ejecuta como ESCENA (no --script) para
## contar con los autoloads reales (Feedback, AudioManager, GameFlow...):
##   godot --headless --path . res://tests/TestCompanions.tscn
## Valida: daño e invulnerabilidad, downed/revive, proteccion post-revive,
## auto-respawn, correa (regreso y teletransporte), marca del policia, barricada,
## emergencia del medico, asistencia de revive, torreta del ingeniero, escalado,
## reagrupamiento y limpieza de nodos temporales.

const CompanionBalance = preload("res://scripts/companions/companion_balance.gd")

var _failures: Array[String] = []
var _checks: int = 0


## Jugador de prueba: cuerpo minimo con la interfaz que usan los compañeros.
class StubPlayer:
	extends CharacterBody2D
	var current_health: int = 100
	var max_health: int = 100
	var level: int = 1
	var shield_calls: Array = []

	func _init() -> void:
		add_to_group("players")
		add_to_group("player")
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 12.0
		shape.shape = circle
		add_child(shape)

	func is_active() -> bool:
		return true

	func is_dead() -> bool:
		return false

	func is_downed() -> bool:
		return false

	func heal(amount: int) -> void:
		current_health = mini(max_health, current_health + amount)

	func take_damage(_amount: int) -> void:
		pass

	func get_last_facing_direction() -> Vector2:
		return Vector2.RIGHT

	func apply_companion_shield(reduction: float, duration: float) -> void:
		shield_calls.append([reduction, duration])


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		print("FALLO: ", label)


func _wait(seconds: float) -> void:
	var frames: int = int(ceil(seconds * 60.0))
	for _i in frames:
		await get_tree().physics_frame


func _spawn_companion(manager: Node, data_path: String) -> Node2D:
	var data = load(data_path)
	var ok: bool = manager.rescue_companion(data)
	_check(ok, "rescue_companion acepta a %s" % data_path)
	var companions: Array = get_tree().get_nodes_in_group("companions")
	if companions.is_empty():
		return null
	var companion: Node2D = companions[companions.size() - 1]
	companion.set("_protection_timer", 0.0)  # las pruebas de daño no esperan 1.5 s
	return companion


func _run() -> void:
	await get_tree().physics_frame

	var player := StubPlayer.new()
	player.global_position = Vector2(400, 300)
	add_child(player)

	var manager := Node2D.new()
	manager.set_script(load("res://scripts/companions/companion_manager.gd"))
	manager.set("companion_scene", load("res://scenes/companions/Companion.tscn"))
	manager.set("projectile_scene", load("res://scenes/weapons/Projectile.tscn"))
	add_child(manager)
	manager.set("player_path", player.get_path())
	manager.set("_player", player)
	await get_tree().physics_frame

	# --- 1) Daño reducido e invulnerabilidad ------------------------------------
	var police: Node2D = _spawn_companion(manager, "res://data/companions/police_cat.tres")
	await get_tree().physics_frame
	var hp0: int = police.current_health
	police.take_damage(20)
	var first_hit: int = hp0 - police.current_health
	_check(first_hit > 0 and first_hit <= 11, "daño reducido ~50%% (recibio %d de 20)" % first_hit)
	police.take_damage(20)
	_check(hp0 - police.current_health == first_hit, "invulnerabilidad tras daño (2do golpe ignorado)")

	# --- 2) Downed: no desaparece, no targetable, no recibe daño -----------------
	police.set("_damage_timer", 0.0)
	police.current_health = 1
	police.take_damage(50)
	_check(police.is_downed(), "entra en estado downed al llegar a 0")
	_check(is_instance_valid(police), "no desaparece al caer")
	_check(not police.can_be_targeted(), "downed no es targetable")
	police.set("_damage_timer", 0.0)
	police.take_damage(50)
	_check(police.is_downed() and police.current_health == 0, "downed no recibe daño normal")

	# --- 3) Revive por jugador + proteccion post-revive --------------------------
	player.global_position = police.global_position
	police._on_revive_area_body_entered(player)
	await _wait(2.2)
	_check(not police.is_downed(), "revive tras canalizacion del jugador")
	_check(float(police.get("_protection_timer")) > 0.0, "proteccion activa al revivir")
	var hp_after_revive: int = police.current_health
	police.set("_damage_timer", 0.0)
	police.take_damage(30)
	_check(police.current_health == hp_after_revive, "proteccion bloquea daño tras revivir")

	# --- 4) Auto-respawn con penalizacion ----------------------------------------
	police.set("_protection_timer", 0.0)
	police.set("_damage_timer", 0.0)
	police.current_health = 1
	police.take_damage(50)
	_check(police.is_downed(), "downed para prueba de auto-respawn")
	player.global_position = police.global_position + Vector2(200, 0)  # lejos del area
	police.set("_downed_timer", CompanionBalance.DOWNED_AUTO_RESPAWN_TIME - 0.1)
	await _wait(0.5)
	_check(not police.is_downed(), "auto-respawn tras el limite de tiempo")
	_check(float(police.get("_ability_lockout")) > 0.0, "habilidad bloqueada tras auto-respawn")

	# --- 5) Correa: regreso y teletransporte de emergencia -----------------------
	police.set("_protection_timer", 0.0)
	police.global_position = player.global_position + Vector2(650, 0)
	await _wait(0.1)
	_check(bool(police.get("_return_mode")), "modo regreso al superar distancia blanda")
	police.global_position = player.global_position + Vector2(900, 0)
	await _wait(0.1)
	_check(police.global_position.distance_to(player.global_position) < 200.0,
		"teletransporte seguro al superar distancia de emergencia")

	# --- 6) Marca del policia y daño amplificado ---------------------------------
	var enemy := _spawn_enemy(player.global_position + Vector2(120, 0))
	await get_tree().physics_frame
	police.set("_mark_timer", 0.0)
	police.set("_ability_lockout", 0.0)
	await _wait(0.2)
	_check(enemy.has_meta(&"companion_mark"), "pasiva del policia marca al enemigo")
	var enemy_hp: int = enemy.current_health
	enemy.take_damage(10)
	_check(enemy_hp - enemy.current_health == 12, "enemigo marcado recibe +20%% de daño (12 de 10)")

	# --- 7) Barricada: ralentiza y se limpia -------------------------------------
	var barricade := Node2D.new()
	barricade.set_script(load("res://scripts/companions/police_barricade.gd"))
	barricade.call("configure", 110.0, 0.8, false)
	barricade.global_position = enemy.global_position
	add_child(barricade)
	await _wait(0.5)
	_check(float(enemy.get("_slow_mult")) < 1.0, "barricada ralentiza enemigos dentro")
	await _wait(1.0)
	_check(not is_instance_valid(barricade), "barricada se libera al expirar")

	# --- 8) Medico: emergencia (cura + escudo) y asistencia de revive ------------
	var medic: Node2D = _spawn_companion(manager, "res://data/companions/medic_cat.tres")
	medic.global_position = player.global_position + Vector2(-60, 0)
	player.current_health = 20
	await _wait(1.2)  # el trigger automatico chequea cada 0.5 s
	_check(player.current_health > 20, "emergencia del medico cura al jugador critico")
	_check(not player.shield_calls.is_empty(), "emergencia del medico aplica escudo")
	_check(float(medic.get("_ability_cooldown_timer")) > 0.0, "cooldown de habilidad del medico activo")

	player.current_health = 100
	police.set("_protection_timer", 0.0)
	police.set("_damage_timer", 0.0)
	police.current_health = 1
	police.take_damage(50)
	# Jugador cerca pero FUERA del area de revive (radio 28): la formacion mantiene
	# al medico dentro de su rango de asistencia sin que el jugador canalice.
	player.global_position = police.global_position + Vector2(0, 60)
	medic.global_position = police.global_position + Vector2(40, 0)
	var revive_time_needed: float = 1.5 / CompanionBalance.MEDIC_ASSIST_REVIVE_RATE
	await _wait(revive_time_needed + 1.5)
	_check(not police.is_downed(), "el medico canaliza el revive de un compañero solo")

	# --- 9) Ingeniero: torreta dispara, prioriza marcados y se limpia ------------
	var engineer: Node2D = _spawn_companion(manager, "res://data/companions/engineer_cat.tres")
	engineer.global_position = enemy.global_position + Vector2(-150, 0)
	engineer.call("_cast_engineer_turret")
	var zones: Array = get_tree().get_nodes_in_group("companion_zones")
	_check(zones.size() > 0, "torreta instalada")
	var turret: Node2D = zones[zones.size() - 1]
	var enemy_hp_before_turret: int = enemy.current_health
	await _wait(1.5)
	_check(not is_instance_valid(enemy) or enemy.current_health < enemy_hp_before_turret,
		"torreta dispara al enemigo (marcado)")
	if is_instance_valid(turret):
		turret.set("_duration", 0.5)
		turret.set("_elapsed", 0.0)
		await _wait(1.2)
	_check(not is_instance_valid(turret), "torreta se libera al expirar")

	# --- 10) Escalado central -----------------------------------------------------
	player.level = 11
	player.max_health = 160
	manager.set("_elapsed_time", 300.0)  # minuto 5
	manager.call("_update_scaling")
	var dmg_scale: float = float(engineer.get("_scaling_damage_multiplier"))
	_check(absf(dmg_scale - 1.5) < 0.01, "escala de daño por nivel (esperado 1.5, fue %.2f)" % dmg_scale)
	var hp_bonus: int = int(engineer.get("_scaling_health_bonus"))
	_check(hp_bonus == 41, "bonus de vida por minuto+jugador (esperado 41, fue %d)" % hp_bonus)

	# --- 11) Reagrupamiento --------------------------------------------------------
	manager.call("command_regroup")
	_check(float(engineer.get("_regroup_timer")) > 0.0, "orden de reagrupar activa a los compañeros")
	_check(InputMap.has_action(&"companion_regroup"), "accion de input companion_regroup registrada")

	# --- 12) Limpieza general -------------------------------------------------------
	if is_instance_valid(enemy):
		enemy.queue_free()
	manager.queue_free()
	await _wait(0.2)
	_check(get_tree().get_nodes_in_group("companions").is_empty(), "compañeros liberados con el manager")

	# --- Resultado -----------------------------------------------------------------
	print("test_companions: %d checks, %d fallos" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("test_companions: OK")
	else:
		for f in _failures:
			print("  - ", f)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("shutdown"):
		audio.shutdown()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _spawn_enemy(pos: Vector2) -> Node2D:
	var enemy := (load("res://scenes/enemies/Enemy.tscn") as PackedScene).instantiate() as Node2D
	enemy.global_position = pos
	var data = load("res://data/enemies/normal_zombie_dog.tres")
	enemy.call("configure", data)
	add_child(enemy)
	enemy.set("speed", 0.0)  # estatico: las pruebas necesitan posiciones estables
	enemy.set("max_health", 500)  # tanque: los disparos del police no deben matarlo
	enemy.set("current_health", 500)
	return enemy
