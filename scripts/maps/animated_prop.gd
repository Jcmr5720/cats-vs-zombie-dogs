class_name AnimatedProp
extends Node2D
## Props visuales sin colision para el mundo procedural. Se dibujan por codigo y
## usan fases derivadas de seed+celda, asi que se ven vivos sin romper determinismo.

const CityPlan = preload("res://scripts/maps/city_plan.gd")

var kind: StringName = &"traffic_light"
var _seed: int = 0
var _key: String = ""
var _phase: float = 0.0
var _state: int = -1
var _accent: Color = Color(0.95, 0.75, 0.28)


func configure(prop_kind: StringName, world_seed: int, cell_key: String, accent: Color = Color(0.95, 0.75, 0.28)) -> void:
	kind = prop_kind
	_seed = world_seed
	_key = cell_key
	_accent = accent
	_phase = CityPlan.hash01(_seed, "prop_phase:%s:%s" % [kind, _key]) * 8.0
	z_index = 2
	set_process(kind in [&"traffic_light", &"neon_sign", &"crane"])
	_update_state(true)


func _process(_delta: float) -> void:
	_update_state(false)


func _update_state(force: bool) -> void:
	var next_state: int = 0
	if kind == &"traffic_light":
		var t: float = fposmod(Time.get_ticks_msec() / 1000.0 + _phase, 8.0)
		next_state = 0 if t < 3.4 else (1 if t < 6.8 else 2)
	elif kind == &"neon_sign":
		next_state = int(floor(Time.get_ticks_msec() / 300.0 + _phase)) % 2
	elif kind == &"crane":
		next_state = int(floor(Time.get_ticks_msec() / 700.0 + _phase)) % 4
	if force or next_state != _state:
		_state = next_state
		queue_redraw()


func _draw() -> void:
	match kind:
		&"traffic_light":
			_draw_traffic_light()
		&"bus_stop":
			_draw_bus_stop()
		&"street_lamp":
			_draw_street_lamp()
		&"crane":
			_draw_crane()
		&"neon_sign":
			_draw_neon_sign()


func _draw_traffic_light() -> void:
	draw_line(Vector2(0, 38), Vector2(0, -36), Color(0.08, 0.09, 0.10), 6.0)
	draw_rect(Rect2(Vector2(-13, -48), Vector2(26, 56)), Color(0.045, 0.05, 0.06), true)
	draw_rect(Rect2(Vector2(-13, -48), Vector2(26, 56)), Color(0.28, 0.30, 0.34), false, 2.0)
	var colors := [Color(1.0, 0.12, 0.10), Color(0.18, 0.95, 0.34), Color(1.0, 0.72, 0.14)]
	var ys := [-36.0, -20.0, -4.0]
	for i in 3:
		var active: bool = i == _state
		if active:
			draw_circle(Vector2(0, ys[i]), 11.0, Color(colors[i].r, colors[i].g, colors[i].b, 0.22))
		draw_circle(Vector2(0, ys[i]), 5.8, colors[i] if active else Color(0.12, 0.13, 0.14))


func _draw_bus_stop() -> void:
	draw_line(Vector2(-24, 34), Vector2(-24, -42), Color(0.18, 0.19, 0.22), 5.0)
	draw_rect(Rect2(Vector2(-38, -44), Vector2(76, 30)), Color(0.09, 0.10, 0.13, 0.88), true)
	draw_rect(Rect2(Vector2(-38, -44), Vector2(76, 30)), _accent, false, 2.0)
	draw_line(Vector2(-46, 34), Vector2(46, 34), Color(0.16, 0.12, 0.08), 6.0)
	draw_line(Vector2(-34, 18), Vector2(34, 18), Color(0.34, 0.24, 0.13), 5.0)
	draw_circle(Vector2(24, -30), 5.0, _accent)


func _draw_street_lamp() -> void:
	draw_line(Vector2(0, 42), Vector2(0, -46), Color(0.13, 0.14, 0.16), 5.0)
	draw_line(Vector2(0, -44), Vector2(26, -44), Color(0.13, 0.14, 0.16), 4.0)
	draw_circle(Vector2(31, -42), 8.0, Color(1.0, 0.78, 0.34, 0.26))
	draw_circle(Vector2(31, -42), 4.5, Color(1.0, 0.86, 0.48, 0.85))


func _draw_crane() -> void:
	var sway: float = float(_state - 1) * 0.03
	draw_line(Vector2(-24, 46), Vector2(-24, -56), Color(0.34, 0.30, 0.18), 7.0)
	draw_line(Vector2(-46, 46), Vector2(-2, 46), Color(0.24, 0.23, 0.20), 7.0)
	draw_line(Vector2(-24, -54), Vector2(78, -70 + sway * 120.0), _accent, 6.0)
	draw_line(Vector2(-8, -50), Vector2(68, -68 + sway * 120.0), Color(0.16, 0.14, 0.10), 2.0)
	var hook := Vector2(58, -28 + sway * 120.0)
	draw_line(Vector2(58, -66 + sway * 120.0), hook, Color(0.08, 0.08, 0.08), 2.0)
	draw_rect(Rect2(hook - Vector2(8, 2), Vector2(16, 14)), Color(0.12, 0.12, 0.13), true)


func _draw_neon_sign() -> void:
	var alpha: float = 0.35 if _state == 0 else 0.85
	draw_rect(Rect2(Vector2(-34, -18), Vector2(68, 36)), Color(0.05, 0.06, 0.08, 0.9), true)
	draw_rect(Rect2(Vector2(-34, -18), Vector2(68, 36)), Color(_accent.r, _accent.g, _accent.b, alpha), false, 3.0)
	draw_line(Vector2(-20, 0), Vector2(20, 0), Color(_accent.r, _accent.g, _accent.b, alpha), 4.0)
