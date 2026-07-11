class_name CharacterVisualController
extends Node2D
## Componente visual desacoplado (ETAPA ARTISTICA 1). Se cuelga como hijo de un
## personaje (Player/Enemy/Companion/Boss) y decide si mostrar SPRITES
## (AnimatedSprite2D + CharacterVisualProfile) o dejar el ARTE PROCEDURAL
## actual (el nodo "Visual" de Polygon2D). NUNCA toca logica, colisiones,
## armas ni senales del personaje: solo OBSERVA.
##
## Como observa al padre (sin acoplarse):
## - velocity (si es CharacterBody2D) -> idle/run + direccion.
## - senales opcionales: damaged -> hurt; died -> death; downed -> downed;
##   revived -> revive. Se conectan solo si existen.
##
## Reglas de fallback:
## - Perfil nulo / disabled / invalido -> procedural (este componente duerme).
## - Nunca personajes invisibles: el procedural solo se oculta DESPUES de
##   validar y asignar los SpriteFrames.
## - Nunca ambas representaciones a la vez.

enum Mode { AUTO, FORCE_PROCEDURAL, FORCE_SPRITE }

## Perfil visual. Vacio = el personaje conserva su arte procedural.
@export var profile: CharacterVisualProfile
## Ruta al nodo de arte procedural del personaje (se oculta en modo sprite).
@export var procedural_visual_path: NodePath = NodePath("../Visual")
## Depuracion: AUTO respeta el perfil; los FORCE permiten comparar antes/despues.
@export var debug_mode: Mode = Mode.AUTO
## Dibuja un marco alrededor del sprite activo (verificar escala/pivote).
@export var show_visual_bounds: bool = false

var _sprite: AnimatedSprite2D
var _procedural: Node2D
var _parent: Node2D
var _sprite_active: bool = false
var _facing: Vector2 = Vector2.DOWN
## Animacion one-shot en curso (attack/hurt...): bloquea idle/run hasta terminar.
var _locked: StringName = &""
## Flash de dano unificado (ETAPA ARTISTICA 2): tween y modulate de retorno.
var _flash_tween: Tween
var _flash_restore: Color = Color.WHITE
## Estados terminales/persistentes: no se desbloquean al terminar la animacion.
const PERSISTENT_ANIMS: Array[StringName] = [&"death", &"downed"]
## Prioridad de animaciones (mayor = mas importante). Una accion solo
## reemplaza a otra de prioridad MENOR; excepciones: revive puede reemplazar
## a downed (su salida natural) y nada reemplaza a death.
const PRIORITY: Dictionary = {
	&"death": 100, &"downed": 95, &"revive": 90, &"phase_change": 85,
	&"special_attack": 80, &"charge": 75, &"charge_windup": 74, &"summon": 72,
	&"hurt": 60, &"ability": 55, &"attack": 50, &"run": 10, &"idle": 0,
}


## Transform base del nodo procedural (capturado al entrar): el squash/bob/
## rotacion de downed procedurales se restauran a esto al cambiar de modo.
var _procedural_base_transform: Transform2D = Transform2D.IDENTITY


func _ready() -> void:
	_parent = get_parent() as Node2D
	_procedural = get_node_or_null(procedural_visual_path) as Node2D
	if is_instance_valid(_procedural):
		_procedural_base_transform = _procedural.transform
	_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	_connect_parent_signals()
	_evaluate_mode()


## Restablece las transformaciones visuales de AMBAS representaciones
## (ETAPA ARTISTICA 3): el procedural vuelve a su transform original (sin
## squash/bob/rotacion acumulados) y el sprite a su offset/escala del perfil.
## El modulate NO se toca aqui: lo gobiernan set_visual_modulate/flash_damage.
func reset_visual_transform() -> void:
	if is_instance_valid(_procedural):
		_procedural.transform = _procedural_base_transform
	if is_instance_valid(_sprite):
		if profile != null:
			_sprite.position = profile.visual_offset
			_sprite.scale = profile.visual_scale
		_sprite.rotation = 0.0
		_sprite.flip_h = false


## Cambia el perfil en runtime (tests, variantes) y reevalua el modo.
func set_profile(new_profile: CharacterVisualProfile) -> void:
	profile = new_profile
	if is_node_ready():
		_evaluate_mode()


func set_debug_mode(mode: Mode) -> void:
	debug_mode = mode
	if is_node_ready():
		_evaluate_mode()


func is_sprite_active() -> bool:
	return _sprite_active


## Reproduce una animacion de accion one-shot (attack, hurt, ability...)
## respetando las prioridades. Ignorada en modo procedural (el arte
## procedural ya tiene su propio feedback).
func play_action(anim: StringName) -> void:
	if not _sprite_active or profile == null:
		return
	# death nunca se reemplaza; downed solo lo reemplaza revive.
	if _locked == &"death":
		return
	if _locked == &"downed" and anim != &"revive":
		return
	# Prioridad: una accion en curso solo cede ante prioridad estrictamente mayor.
	if _locked != &"" and int(PRIORITY.get(anim, 0)) < int(PRIORITY.get(_locked, 0)):
		return
	_locked = anim
	_play_directional(anim)


# Acciones visuales explicitas (3.3): los scripts de gameplay llaman a estas
# funciones en el momento del evento; el controlador SOLO representa.
func play_idle() -> void:
	if _sprite_active and _locked not in PERSISTENT_ANIMS:
		_locked = &""
		_play_directional(&"idle")


func play_run() -> void:
	if _sprite_active and _locked not in PERSISTENT_ANIMS:
		_locked = &""
		_play_directional(&"run")


func play_attack() -> void: play_action(&"attack")
func play_hurt() -> void: play_action(&"hurt")
func play_death() -> void: play_action(&"death")
func play_downed() -> void: play_action(&"downed")
func play_revive() -> void: play_action(&"revive")
func play_ability() -> void: play_action(&"ability")
func play_charge_windup() -> void: play_action(&"charge_windup")
func play_charge() -> void: play_action(&"charge")
func play_summon() -> void: play_action(&"summon")
func play_phase_change() -> void: play_action(&"phase_change")


# --- Flash de dano unificado (3.1) ------------------------------------------------
# Regla: se aplica al visual ACTIVO (sprite o procedural), se restaura al
# modulate previo (respeta tinte P2/estados/datos) y nunca duplica tweens.

## CanvasItem que esta representando al personaje ahora mismo.
func get_active_visual_canvas_item() -> CanvasItem:
	if _sprite_active and is_instance_valid(_sprite):
		return _sprite
	return _procedural if is_instance_valid(_procedural) else null


## Flash breve de dano sobre el visual activo. Retrigger seguro: si ya hay un
## flash en curso reutiliza el color de retorno capturado (no captura el rojo).
func flash_damage(color: Color = Color(1.8, 0.4, 0.4, 1.0), duration: float = 0.30) -> void:
	var target := get_active_visual_canvas_item()
	if target == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	else:
		_flash_restore = target.modulate
	target.modulate = color
	_flash_tween = create_tween()
	_flash_tween.tween_property(target, "modulate", _flash_restore, duration)


## Fija el tinte BASE del visual activo (P2, derribado...). El flash volvera
## a este valor, no a blanco.
func set_visual_modulate(color: Color) -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_restore = color
	var target := get_active_visual_canvas_item()
	if target != null:
		target.modulate = color


func reset_visual_modulate() -> void:
	set_visual_modulate(Color.WHITE)


# --- Activacion / fallback -----------------------------------------------------

func _evaluate_mode() -> void:
	var want_sprite: bool = false
	match debug_mode:
		Mode.FORCE_SPRITE:
			want_sprite = profile != null
		Mode.FORCE_PROCEDURAL:
			want_sprite = false
		_:
			# En AUTO manda el estado artistico (ETAPA ARTISTICA 3): solo
			# APPROVED_FINAL (o FINAL_CANDIDATE en build de desarrollo) se
			# activa en juego. TEST_ONLY/PLACEHOLDER/PILOT_ART: nunca.
			want_sprite = profile != null and profile.can_activate_in_game()
	# Regla de oro: solo se activa el sprite si el perfil VALIDA. Si no valida
	# y hay fallback, procedural; sin fallback (solo debug) se avisa por consola.
	if want_sprite and not profile.is_valid():
		if profile.use_procedural_fallback:
			want_sprite = false
		else:
			push_warning("VisualProfile '%s' invalido sin fallback: %s" % [profile.visual_id, ", ".join(profile.validation_errors())])
			want_sprite = false
	if want_sprite:
		_activate_sprite()
	else:
		_activate_procedural()
	set_process(_sprite_active)
	queue_redraw()


func _activate_sprite() -> void:
	if _sprite == null:
		_sprite = AnimatedSprite2D.new()
		add_child(_sprite)
	# El procedural pudo quedar con squash/rotacion a medias: limpiarlo antes
	# de ocultarlo para que un futuro regreso no arrastre transformaciones.
	reset_visual_transform()
	_sprite.sprite_frames = profile.sprite_frames
	_sprite.scale = profile.visual_scale
	_sprite.position = profile.visual_offset
	_sprite.speed_scale = profile.animation_speed_multiplier
	_sprite.visible = true
	_sprite_active = true
	_locked = &""
	_play_directional(profile.default_animation)
	if not _sprite.animation_finished.is_connected(_on_animation_finished):
		_sprite.animation_finished.connect(_on_animation_finished)
	# El procedural se oculta SOLO ahora, con el sprite ya montado y validado.
	if is_instance_valid(_procedural):
		_procedural.visible = false


func _activate_procedural() -> void:
	_sprite_active = false
	_locked = &""
	reset_visual_transform()
	if is_instance_valid(_sprite):
		_sprite.visible = false
	if is_instance_valid(_procedural):
		_procedural.visible = true


# --- Seguimiento del personaje ---------------------------------------------------

func _process(_delta: float) -> void:
	if not _sprite_active or _parent == null:
		return
	var velocity: Vector2 = Vector2.ZERO
	if _parent is CharacterBody2D:
		velocity = (_parent as CharacterBody2D).velocity
	var moving: bool = velocity.length_squared() > 25.0
	if moving:
		_facing = velocity.normalized()
	if _locked != &"":
		return
	_play_directional(&"run" if moving else &"idle")


## Resuelve <base>_<direccion> + flip y la reproduce (sin reiniciarla si ya suena).
func _play_directional(base: StringName) -> void:
	if _sprite == null or profile == null or profile.sprite_frames == null:
		return
	var dir_info: Dictionary = SpriteDirectionResolver.resolve(_facing, profile.direction_count, profile.mirror_allowed())
	var anim: StringName = SpriteDirectionResolver.animation_name(profile.sprite_frames, base, dir_info["suffix"])
	if not profile.sprite_frames.has_animation(anim):
		# Animacion inexistente: default_animation antes que dejarlo congelado.
		anim = profile.default_animation
		if not profile.sprite_frames.has_animation(anim):
			return
	_sprite.flip_h = dir_info["flip"]
	if _sprite.animation != anim or not _sprite.is_playing():
		_sprite.play(anim)


func _on_animation_finished() -> void:
	# Fin de una accion one-shot: volver al ciclo idle/run. Los estados
	# persistentes (death/downed) se quedan en su ultimo frame.
	if _locked != &"" and _locked not in PERSISTENT_ANIMS:
		_locked = &""
		_play_directional(&"idle")


# --- Senales del personaje (todas opcionales) ------------------------------------

func _connect_parent_signals() -> void:
	if _parent == null:
		return
	for entry in [["damaged", "_on_parent_damaged"], ["died", "_on_parent_died"], ["downed", "_on_parent_downed"], ["revived", "_on_parent_revived"]]:
		if _parent.has_signal(entry[0]):
			_parent.connect(entry[0], Callable(self, entry[1]))


func _on_parent_damaged(_a: Variant = null, _b: Variant = null) -> void:
	if _locked == &"":  # hurt no interrumpe attack/death
		play_action(&"hurt")


func _on_parent_died(_a: Variant = null, _b: Variant = null) -> void:
	play_action(&"death")


func _on_parent_downed(_a: Variant = null) -> void:
	play_action(&"downed")


func _on_parent_revived(_a: Variant = null) -> void:
	_locked = &""
	play_action(&"revive")


func _draw() -> void:
	if not show_visual_bounds or not _sprite_active or _sprite == null:
		return
	var frames := _sprite.sprite_frames
	if frames == null or not frames.has_animation(_sprite.animation):
		return
	var tex: Texture2D = frames.get_frame_texture(_sprite.animation, _sprite.frame)
	if tex == null:
		return
	var size: Vector2 = tex.get_size() * _sprite.scale
	draw_rect(Rect2(_sprite.position - size * 0.5, size), Color(0.3, 1.0, 0.6, 0.8), false, 1.5)
	draw_circle(Vector2.ZERO, 3.0, Color(1.0, 0.4, 0.3, 0.9))
