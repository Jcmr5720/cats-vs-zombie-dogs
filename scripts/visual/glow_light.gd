class_name GlowLight
extends PointLight2D
## Luz local barata (FASE VISUAL 2). Genera su textura radial por codigo (sin
## assets externos) y la CACHEA en una static: todas las luces del juego comparten
## una unica textura. Soporta pulso y parpadeo opcionales con un _process minimo.
##
## Crear siempre via GlowLight.attach(): respeta el ajuste global de luces
## (Feedback.lights_enabled) y devuelve null si estan apagadas, de modo que los
## llamadores no necesitan comprobar nada.

static var _shared_texture: GradientTexture2D
## Contador global de luces de DECORACION vivas (farolas, neones...). Las luces
## importantes (jefes, rescates) no cuentan: nunca se quedan sin cupo.
static var _active_decor_lights: int = 0

## True si esta luz cuenta para el tope global de decoracion.
var _counts_toward_cap: bool = false

## Velocidad del pulso de energia (0 = luz fija, sin _process).
@export var pulse_speed: float = 0.0
## Amplitud del pulso (fraccion de la energia base).
@export var pulse_amount: float = 0.18
## Parpadeo aleatorio sutil (0 = ninguno). Para luces "electricas".
@export var flicker_amount: float = 0.0

var _base_energy: float = 1.0
var _time: float = 0.0


## Fabrica: crea y cuelga una luz de `parent`. Devuelve null si las luces
## dinamicas estan desactivadas (ajustes/calidad baja) o si una luz de
## decoracion supera el tope global (Feedback.max_active_lights). El llamador
## puede guardar la referencia sin comprobarla (siempre con is_instance_valid).
## `important=true` (jefes, rescates) ignora el tope: son pocas y criticas.
static func attach(
	parent: Node,
	color: Color,
	radius: float,
	energy: float = 1.0,
	light_pulse_speed: float = 0.0,
	light_flicker: float = 0.0,
	important: bool = false
) -> GlowLight:
	var fb: Node = parent.get_node_or_null("/root/Feedback")
	if fb != null and not bool(fb.get("lights_enabled")):
		return null
	if not important and fb != null and _active_decor_lights >= int(fb.get("max_active_lights")):
		return null
	var light := GlowLight.new()
	light._counts_toward_cap = not important
	light.texture = _radial_texture()
	light.color = color
	light.energy = energy
	light.blend_mode = Light2D.BLEND_MODE_ADD
	# La textura compartida mide 256 px: la escala fija el radio visual real.
	light.texture_scale = max(0.05, radius / 128.0)
	light.pulse_speed = light_pulse_speed
	light.flicker_amount = light_flicker
	# Solo ilumina el mundo (layer 1 por defecto); el HUD vive en CanvasLayers.
	parent.add_child(light)
	return light


static func _radial_texture() -> GradientTexture2D:
	if _shared_texture != null:
		return _shared_texture
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.18), Color(1, 1, 1, 0.0)
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 256
	texture.height = 256
	_shared_texture = texture
	return _shared_texture


func _ready() -> void:
	_base_energy = energy
	# Fase aleatoria para que las luces no pulsen todas sincronizadas.
	_time = randf() * TAU
	set_process(pulse_speed > 0.0 or flicker_amount > 0.0)
	# Grupo para aplicar los toggles de opciones EN VIVO (Feedback los recorre).
	add_to_group("glow_lights")


func _enter_tree() -> void:
	if _counts_toward_cap:
		_active_decor_lights += 1


func _exit_tree() -> void:
	if _counts_toward_cap:
		_active_decor_lights = max(0, _active_decor_lights - 1)


## Cambia la energia base (la que respetan pulso y parpadeo). Usar esto en vez
## de tocar `energy` directamente cuando la luz tiene pulso activo.
func set_base_energy(value: float) -> void:
	_base_energy = max(0.0, value)
	if not is_processing():
		energy = _base_energy


func _process(delta: float) -> void:
	_time += delta
	var e: float = _base_energy
	if pulse_speed > 0.0:
		e += sin(_time * pulse_speed) * pulse_amount * _base_energy
	if flicker_amount > 0.0 and randf() < 0.12:
		e -= randf() * flicker_amount * _base_energy
	energy = max(0.0, e)
