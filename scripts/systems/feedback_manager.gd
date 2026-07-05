extends Node
## Autoload "Feedback": punto único para efectos de game feel (números de daño,
## destellos de impacto/muerte y screen shake). Centralizarlo evita acoplar el
## enemigo/jugador a escenas concretas y permite LIMITAR la cantidad de efectos
## activos para que no haya lag cuando hay muchos enemigos en pantalla.
##
## Es autoload: persiste entre partidas. Los efectos se cuelgan de la escena
## actual, así se liberan solos al reiniciar (R / reload_current_scene).
##
## Los SFX viven en AudioManager; este autoload conserva solo feedback visual.

const DAMAGE_NUMBER_SCENE := preload("res://scenes/effects/DamageNumber.tscn")
const HIT_EFFECT_SCENE := preload("res://scenes/effects/HitEffect.tscn")

## Tope de efectos visuales vivos a la vez. Por encima se descartan los nuevos
## (los números/destellos son cosméticos; mejor perder alguno que tirar FPS).
@export var max_active_effects: int = 70
## Interruptor global para desactivar todos los efectos de un tirón.
@export var effects_enabled: bool = true
## Ajustes globales que controla el autoload Settings (Fase 08).
## shake_scale 0 = sin shake; damage_numbers_enabled false = sin numeros de dano.
var shake_scale: float = 1.0
var damage_numbers_enabled: bool = true
var visual_quality: StringName = &"media"
var effects_intensity: bool = true
var shadows_enabled: bool = true

var _active_effects: int = 0

## Racha de bajas (combo): se reinicia si pasan COMBO_WINDOW segundos sin matar.
const COMBO_WINDOW: float = 2.2
var _combo: int = 0
var _combo_timer: float = 0.0
var _hitstop_active: bool = false


func _process(delta: float) -> void:
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo = 0
			_notify_combo(0)


## Registra una baja para la racha. Cada 15 bajas encadenadas hay un hito:
## micro hit-stop + shake + BONUS de XP creciente para el jugador. La racha
## no solo se ve: recompensa jugar agresivo.
func register_kill() -> void:
	_combo += 1
	_combo_timer = COMBO_WINDOW
	_notify_combo(_combo)
	# Misiones persistentes: bajas totales y mejor racha.
	var missions: Node = get_node_or_null("/root/Missions")
	if missions != null:
		missions.add(&"kills")
		missions.report_peak(&"combo_peak", _combo)
	if _combo > 0 and _combo % 15 == 0:
		hitstop(0.07, 0.08)
		shake(0.25)
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null and player.has_method("add_experience"):
			player.add_experience(2 + _combo / 15)
			hit_effect(player.global_position, Color(0.45, 0.86, 1.0, 0.85), 0.3, 2.0)


## Congelado de tiempo brevisimo (juice de impacto). Se restaura solo con un
## timer que ignora el time_scale; nunca se apilan dos a la vez.
func hitstop(duration: float = 0.06, time_scale: float = 0.08) -> void:
	if _hitstop_active or not effects_enabled:
		return
	_hitstop_active = true
	Engine.time_scale = time_scale
	var timer := get_tree().create_timer(duration, true, false, true)
	timer.timeout.connect(func() -> void:
		Engine.time_scale = 1.0
		_hitstop_active = false)


func _notify_combo(count: int) -> void:
	for hud in get_tree().get_nodes_in_group("hud"):
		if is_instance_valid(hud) and hud.has_method("show_combo"):
			hud.show_combo(count)


## Estallido de "pedazos" al morir un enemigo: 4-6 fragmentos del color del cuerpo
## salen despedidos, giran y se desvanecen. Mucho mas satisfactorio que encogerse.
func death_burst(world_position: Vector2, color: Color, count: int = 5) -> void:
	if not effects_enabled or _active_effects >= max_active_effects:
		return
	var root := Node2D.new()
	_attach(root)
	root.global_position = world_position
	for i in count:
		var chunk := Polygon2D.new()
		var size: float = randf_range(3.0, 6.5)
		chunk.polygon = PackedVector2Array([
			Vector2(-size, -size * 0.7), Vector2(size * 0.8, -size),
			Vector2(size, size * 0.6), Vector2(-size * 0.6, size),
		])
		chunk.color = color.darkened(randf_range(0.0, 0.25))
		root.add_child(chunk)
		var target: Vector2 = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(18.0, 54.0)
		var tween := root.create_tween()
		tween.set_parallel(true)
		tween.tween_property(chunk, "position", target, 0.38).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		tween.tween_property(chunk, "rotation", randf_range(-3.0, 3.0), 0.38)
		tween.tween_property(chunk, "modulate:a", 0.0, 0.34).set_delay(0.10)
	var cleanup := root.create_tween()
	cleanup.tween_interval(0.55)
	cleanup.tween_callback(root.queue_free)


## Nubecita de polvo bajo las patas (correr, derrapes). Barata: reusa HitEffect.
func dust_puff(world_position: Vector2) -> void:
	hit_effect(world_position, Color(0.55, 0.52, 0.47, 0.30), 0.22, 0.62)


## Número de daño flotante sobre una posición del mundo.
func damage_number(world_position: Vector2, amount: int, color: Color = Color(1, 0.95, 0.7)) -> void:
	if not effects_enabled or not damage_numbers_enabled or _active_effects >= max_active_effects:
		return
	var node := DAMAGE_NUMBER_SCENE.instantiate()
	if node == null:
		return
	node.global_position = world_position
	_attach(node)
	node.call("setup", amount, color)


## Destello de impacto/muerte en una posición del mundo.
func hit_effect(world_position: Vector2, color: Color = Color(1, 1, 1), start_scale: float = 0.4, end_scale: float = 1.6) -> void:
	if not effects_enabled or _active_effects >= max_active_effects:
		return
	if not effects_intensity:
		start_scale *= 0.85
		end_scale *= 0.72
	var node := HIT_EFFECT_SCENE.instantiate()
	if node == null:
		return
	node.global_position = world_position
	_attach(node)
	node.call("setup", color, start_scale, end_scale)


## Sacude la cámara. `amount` ~ 0.2 (suave) .. 1.0 (fuerte).
func shake(amount: float) -> void:
	var scaled: float = amount * shake_scale
	if scaled <= 0.0:
		return
	for cam in get_tree().get_nodes_in_group("screen_shake"):
		if is_instance_valid(cam) and cam.has_method("add_trauma"):
			cam.add_trauma(scaled)


func _attach(node: Node) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		node.free()
		return
	scene.add_child(node)
	_active_effects += 1
	# Cuando el efecto se libere, libera el cupo.
	node.tree_exited.connect(_on_effect_freed)


func _on_effect_freed() -> void:
	_active_effects = max(_active_effects - 1, 0)


func apply_visual_quality(quality: StringName, intense_effects: bool, show_shadows: bool) -> void:
	visual_quality = quality
	effects_intensity = intense_effects
	shadows_enabled = show_shadows
	match visual_quality:
		&"baja":
			max_active_effects = 36
			effects_enabled = intense_effects
		&"alta":
			max_active_effects = 90
			effects_enabled = true
		_:
			max_active_effects = 70
			effects_enabled = true
