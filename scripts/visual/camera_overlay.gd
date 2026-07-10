extends CanvasLayer
## Vignette y dramatismo de camara (FASE VISUAL 2). Un unico ColorRect a pantalla
## completa con un shader radial minusculo. Estados (prioridad de mayor a menor):
## - Jugador con poca vida  -> borde rojo pulsante.
## - Jefe principal vivo    -> vignette calida mas cerrada, pulso lento.
## - Base                   -> vignette del mapa (color/intensidad por MapData).
## Las transiciones se interpolan; los estados se revisan cada 0.4 s (cero costo
## por frame mas alla de un lerp). Se desactiva con Ajustes (vignette=false) o
## en calidad baja, y vive en MainLevel: R / cambio de escena lo limpia solo.

const CHECK_INTERVAL: float = 0.4
const LOW_HEALTH_RATIO: float = 0.3

const SHADER_CODE := "
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.3;
uniform float inner : hint_range(0.0, 1.0) = 0.5;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float dist = length(d) * 1.4142;
	float v = smoothstep(inner, 1.05, dist);
	COLOR = vec4(tint.rgb, v * strength * tint.a);
}
"

## Intensidad base (la ajusta el MapData al configurar el mapa).
@export var base_strength: float = 0.30
@export var base_color: Color = Color(0.01, 0.01, 0.03)

var _rect: ColorRect
var _material: ShaderMaterial
var _check_timer: float = 0.0
var _pulse_time: float = 0.0

# Estado objetivo actual (hacia el que se interpola).
var _target_strength: float = 0.30
var _target_color: Color = Color(0.01, 0.01, 0.03)
var _target_inner: float = 0.55
var _boss_alive: bool = false
var _low_health: bool = false


func _ready() -> void:
	add_to_group("camera_overlay")
	# Layer 0: por encima del canvas base (mundo) y por debajo del HUD (layer 1).
	layer = 0
	_build_rect()
	_target_strength = base_strength
	_target_color = base_color


func _build_rect() -> void:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = shader
	_rect = ColorRect.new()
	_rect.material = _material
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	_apply_uniforms(base_strength, base_color, 0.55)


func _apply_uniforms(strength: float, tint: Color, inner: float) -> void:
	_material.set_shader_parameter("strength", strength)
	_material.set_shader_parameter("tint", tint)
	_material.set_shader_parameter("inner", inner)


## La llama el MapManager al aplicar el mapa activo.
func configure(map_data) -> void:
	base_strength = clampf(map_data.vignette_strength, 0.0, 0.6)
	base_color = map_data.vignette_color
	_target_strength = base_strength
	_target_color = base_color


func _process(delta: float) -> void:
	if not _overlay_enabled():
		if is_instance_valid(_rect) and _rect.visible:
			_rect.visible = false
		return
	if is_instance_valid(_rect) and not _rect.visible:
		_rect.visible = true

	_pulse_time += delta
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = CHECK_INTERVAL
		_refresh_state()

	# Estado -> objetivo con pulso propio.
	var strength: float = _target_strength
	var inner: float = _target_inner
	if _low_health:
		strength += sin(_pulse_time * 5.0) * 0.05
		inner = 0.38
	elif _boss_alive:
		strength += sin(_pulse_time * 1.8) * 0.035
		inner = 0.46

	# Interpolacion suave de los uniforms (sin allocs).
	var cur_strength: float = float(_material.get_shader_parameter("strength"))
	var cur_inner: float = float(_material.get_shader_parameter("inner"))
	var cur_tint: Color = _material.get_shader_parameter("tint")
	_apply_uniforms(
		lerpf(cur_strength, strength, 4.0 * delta),
		cur_tint.lerp(_target_color, 4.0 * delta),
		lerpf(cur_inner, inner, 3.0 * delta)
	)


func _refresh_state() -> void:
	# Poca vida del jugador principal (prioritario).
	_low_health = false
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and "current_health" in player and "max_health" in player:
		var max_hp: int = int(player.get("max_health"))
		if max_hp > 0 and float(player.get("current_health")) / float(max_hp) <= LOW_HEALTH_RATIO:
			_low_health = true
	_boss_alive = get_tree().get_first_node_in_group("boss") != null

	if _low_health:
		_target_color = Color(0.45, 0.02, 0.02)
		_target_strength = maxf(base_strength, 0.42)
		_target_inner = 0.38
	elif _boss_alive:
		_target_color = base_color.lerp(Color(0.32, 0.05, 0.03), 0.55)
		_target_strength = base_strength + 0.10
		_target_inner = 0.46
	else:
		_target_color = base_color
		_target_strength = base_strength
		_target_inner = 0.55


func _overlay_enabled() -> bool:
	var fb: Node = get_node_or_null("/root/Feedback")
	if fb == null:
		return true
	return bool(fb.get("vignette_enabled")) and fb.get("visual_quality") != &"baja"
