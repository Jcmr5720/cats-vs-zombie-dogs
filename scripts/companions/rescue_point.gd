extends Node2D
## Punto de rescate con mejor lectura visual, pulso y feedback de cancelacion.

const CompanionData = preload("res://scripts/companions/companion_data.gd")

signal rescue_completed(data: CompanionData)
signal rescue_progress_started
signal rescue_progress_cancelled

@export var rescue_duration: float = 1.0

var companion_data: CompanionData

var _rescuer_inside: bool = false
var _progress: float = 0.0
var _pulse_time: float = 0.0

@onready var _area: Area2D = $Area2D
@onready var _prompt: Label = $Prompt
@onready var _name_label: Label = $NameLabel
@onready var _progress_bar: ProgressBar = $ProgressBar
@onready var _crate: Polygon2D = $Visual/Crate
@onready var _cat: Polygon2D = $Visual/Cat
@onready var _icon: Polygon2D = $Visual/Icon
@onready var _glow: Polygon2D = $Visual/Glow
@onready var _pulse_ring: Polygon2D = $Visual/PulseRing
@onready var _float_label: Label = $FloatLabel


var _light: GlowLight


func _ready() -> void:
	add_to_group("rescue_points")
	_progress_bar.visible = false
	_prompt.visible = false
	_area.body_entered.connect(_on_area_body_entered)
	_area.body_exited.connect(_on_area_body_exited)
	# FASE VISUAL 2: aro de luz pulsante; el rescate se ve desde lejos incluso
	# con el ambiente oscurecido. Null si las luces estan desactivadas.
	_light = GlowLight.attach(self, Color(0.75, 1.0, 0.85), 130.0, 0.65, 1.6, 0.0, true)
	_update_visuals()


func setup(data: CompanionData) -> void:
	companion_data = data
	if is_node_ready():
		_update_visuals()


func _process(delta: float) -> void:
	_pulse_time += delta
	_animate_idle()
	if not _rescuer_inside:
		return
	_progress = min(rescue_duration, _progress + delta)
	_progress_bar.value = (_progress / rescue_duration) * 100.0
	if _progress >= rescue_duration:
		_complete_rescue()


func _animate_idle() -> void:
	var t: float = _pulse_time
	# Gato: bob vertical suave + leve balanceo, como saludando para que lo rescaten.
	_cat.position.y = -2.0 + sin(t * 2.4) * 2.6
	_cat.rotation = sin(t * 1.8) * 0.12
	# Halo: respiracion lenta (mucho mas calmado que antes).
	_glow.scale = Vector2.ONE * (1.0 + sin(t * 1.6) * 0.06)
	_glow.modulate.a = 0.30 + sin(t * 1.6) * 0.06
	# Anillo tipo "sonar": se expande y se desvanece en bucle, marcando el punto.
	var phase: float = fmod(t * 0.8, 1.0)
	_pulse_ring.scale = Vector2.ONE * (0.7 + phase * 0.7)
	_pulse_ring.modulate.a = (1.0 - phase) * 0.40
	_float_label.position.y = -74.0 + sin(t * 2.2) * 2.0


func _on_area_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_rescuer_inside = true
	_prompt.visible = true
	_progress_bar.visible = true
	_prompt.text = "Rescatando..."
	_progress_bar.value = 0.0
	rescue_progress_started.emit()


func _on_area_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_cancel_progress()


func _cancel_progress() -> void:
	if _progress > 0.0:
		rescue_progress_cancelled.emit()
	_prompt.text = "Rescate cancelado"
	_rescuer_inside = false
	_progress = 0.0
	_progress_bar.value = 0.0
	_progress_bar.visible = false
	_prompt.visible = false


func _complete_rescue() -> void:
	_rescuer_inside = false
	_progress_bar.visible = false
	_prompt.visible = false
	Feedback.hit_effect(global_position, Color(1.0, 0.96, 0.7, 1.0), 0.52, 2.15)
	Feedback.hit_effect(global_position, companion_data.visual_color.lightened(0.10), 0.30, 1.35)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(&"rescue_cat")
	rescue_completed.emit(companion_data)
	queue_free()


func _update_visuals() -> void:
	if companion_data == null:
		return
	_name_label.text = companion_data.display_name
	_float_label.text = "Rescate!"
	_cat.color = companion_data.visual_color
	_icon.color = companion_data.accent_color
	_crate.color = companion_data.visual_color.darkened(0.5)
	_glow.color = companion_data.visual_color.lightened(0.12)
	_pulse_ring.color = companion_data.projectile_color
	if is_instance_valid(_light):
		_light.color = companion_data.projectile_color
