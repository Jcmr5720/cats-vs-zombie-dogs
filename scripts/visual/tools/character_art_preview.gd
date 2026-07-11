extends Control
## QA artistico sin partida (ETAPA ARTISTICA 2). Abre la escena
## scenes/visual/tools/CharacterArtPreview.tscn (F6 en el editor o
## `Godot --path . res://scenes/visual/tools/CharacterArtPreview.tscn`).
## Permite elegir perfil, animacion, direccion, pausar, avanzar frame,
## cambiar fondo por bioma, ver sombra, pivote y bounds.

const BlobShadowScene := preload("res://scenes/visual/BlobShadow.tscn")

## Fondos con su tinte ambiental (el CanvasModulate real de cada mapa) para
## juzgar el sprite bajo la luz del bioma, no solo sobre color plano.
const BACKGROUNDS: Array[Dictionary] = [
	{"name": "Oscuro", "color": Color(0.09, 0.10, 0.14), "ambient": Color(1, 1, 1)},
	{"name": "Claro", "color": Color(0.72, 0.72, 0.70), "ambient": Color(1, 1, 1)},
	{"name": "Barrio", "color": Color(0.11, 0.12, 0.15), "ambient": Color(0.84, 0.87, 1.08)},
	{"name": "Parque", "color": Color(0.09, 0.14, 0.10), "ambient": Color(0.82, 0.98, 0.86)},
	{"name": "Industrial", "color": Color(0.13, 0.12, 0.10), "ambient": Color(1.04, 0.92, 0.84)},
]
## Escalas de inspeccion: x3 detalle, x1.0 zoom de juego, x1.35 coop juntos.
const ZOOMS: Array[Dictionary] = [
	{"name": "Zoom x3", "scale": 3.0},
	{"name": "Zoom juego x1.0", "scale": 1.0},
	{"name": "Zoom coop x1.35", "scale": 1.35},
]
## Escena procedural de comparacion por categoria de perfil.
const COMPARE_SCENES: Dictionary = {
	"players": "res://scenes/player/Player.tscn",
	"companions": "res://scenes/companions/Companion.tscn",
	"enemies": "res://scenes/enemies/Enemy.tscn",
	"bosses": "res://scenes/bosses/MiniBoss.tscn",
}
const DIRECTIONS: Array[Dictionary] = [
	{"name": "S", "vec": Vector2(0, 1)}, {"name": "SE", "vec": Vector2(1, 1)},
	{"name": "E", "vec": Vector2(1, 0)}, {"name": "NE", "vec": Vector2(1, -1)},
	{"name": "N", "vec": Vector2(0, -1)}, {"name": "NW", "vec": Vector2(-1, -1)},
	{"name": "W", "vec": Vector2(-1, 0)}, {"name": "SW", "vec": Vector2(-1, 1)},
]

var _profiles: Array[String] = []
var _profile: CharacterVisualProfile
var _bg: ColorRect
var _stage: Node2D
var _sprite: AnimatedSprite2D
var _shadow: Node2D
var _markers: Node2D
var _profile_pick: OptionButton
var _anim_pick: OptionButton
var _dir_pick: OptionButton
var _pause_btn: Button
var _info: Label
var _show_markers: bool = true
## Instancia procedural de comparacion (PROCEDURAL | SPRITE), lado izquierdo.
var _compare_node: Node2D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_scan_profiles()


func _build_ui() -> void:
	_bg = ColorRect.new()
	_bg.color = BACKGROUNDS[0]["color"]
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	# Escenario centrado, escala 3x para inspeccion comoda.
	_stage = Node2D.new()
	_stage.position = Vector2(576, 380)
	_stage.scale = Vector2(3, 3)
	add_child(_stage)
	_shadow = BlobShadowScene.instantiate()
	_stage.add_child(_shadow)
	_sprite = AnimatedSprite2D.new()
	_stage.add_child(_sprite)
	_markers = Node2D.new()
	_markers.z_index = 10
	_markers.draw.connect(_draw_markers)
	_stage.add_child(_markers)

	var bar := HBoxContainer.new()
	bar.position = Vector2(12, 10)
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)

	_profile_pick = OptionButton.new()
	_profile_pick.custom_minimum_size = Vector2(260, 34)
	_profile_pick.item_selected.connect(func(i: int) -> void: _load_profile(_profiles[i]))
	bar.add_child(_profile_pick)

	_anim_pick = OptionButton.new()
	_anim_pick.custom_minimum_size = Vector2(150, 34)
	_anim_pick.item_selected.connect(func(_i: int) -> void: _refresh_animation())
	bar.add_child(_anim_pick)

	_dir_pick = OptionButton.new()
	_dir_pick.custom_minimum_size = Vector2(80, 34)
	for d in DIRECTIONS:
		_dir_pick.add_item(d["name"])
	_dir_pick.item_selected.connect(func(_i: int) -> void: _refresh_animation())
	bar.add_child(_dir_pick)

	_pause_btn = Button.new()
	_pause_btn.text = "Pausa"
	_pause_btn.pressed.connect(_toggle_pause)
	bar.add_child(_pause_btn)

	var step := Button.new()
	step.text = "Frame +1"
	step.pressed.connect(func() -> void:
		_sprite.pause()
		_pause_btn.text = "Reanudar"
		if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(_sprite.animation):
			_sprite.frame = (_sprite.frame + 1) % _sprite.sprite_frames.get_frame_count(_sprite.animation)
		_update_info())
	bar.add_child(step)

	var bg_pick := OptionButton.new()
	for b in BACKGROUNDS:
		bg_pick.add_item(b["name"])
	bg_pick.item_selected.connect(func(i: int) -> void:
		_bg.color = BACKGROUNDS[i]["color"]
		# Tinte ambiental del bioma sobre el personaje (simula el CanvasModulate).
		_stage.modulate = BACKGROUNDS[i]["ambient"])
	bar.add_child(bg_pick)

	var zoom_pick := OptionButton.new()
	for z in ZOOMS:
		zoom_pick.add_item(z["name"])
	zoom_pick.item_selected.connect(func(i: int) -> void:
		_stage.scale = Vector2.ONE * float(ZOOMS[i]["scale"]))
	bar.add_child(zoom_pick)

	var flash_btn := Button.new()
	flash_btn.text = "Flash daño"
	flash_btn.pressed.connect(func() -> void:
		var restore: Color = _sprite.modulate
		_sprite.modulate = Color(1.8, 0.4, 0.4)
		var t := _sprite.create_tween()
		t.tween_property(_sprite, "modulate", restore, 0.3))
	bar.add_child(flash_btn)

	var compare_check := CheckBox.new()
	compare_check.text = "Procedural"
	compare_check.toggled.connect(_toggle_compare)
	bar.add_child(compare_check)

	var shadow_check := CheckBox.new()
	shadow_check.text = "Sombra"
	shadow_check.button_pressed = true
	shadow_check.toggled.connect(func(on: bool) -> void: _shadow.visible = on)
	bar.add_child(shadow_check)

	var marks_check := CheckBox.new()
	marks_check.text = "Pivote/Bounds"
	marks_check.button_pressed = true
	marks_check.toggled.connect(func(on: bool) -> void:
		_show_markers = on
		_markers.queue_redraw())
	bar.add_child(marks_check)

	_info = Label.new()
	_info.position = Vector2(12, 54)
	_info.add_theme_font_size_override("font_size", 13)
	_info.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
	_info.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_info.add_theme_constant_override("outline_size", 4)
	add_child(_info)


func _scan_profiles() -> void:
	_profiles.assign(ArtPipelineValidator._find_profiles("res://data/visual_profiles"))
	_profile_pick.clear()
	for p in _profiles:
		_profile_pick.add_item(p.get_file())
	if not _profiles.is_empty():
		_load_profile(_profiles[0])
	else:
		_info.text = "No hay perfiles en res://data/visual_profiles/"


func _load_profile(path: String) -> void:
	var res: Resource = load(path)
	if not (res is CharacterVisualProfile):
		_info.text = "%s no es CharacterVisualProfile" % path
		return
	_profile = res
	_sprite.sprite_frames = _profile.sprite_frames
	_sprite.scale = _profile.visual_scale
	_sprite.position = _profile.visual_offset
	_shadow.position = _profile.shadow_offset - Vector2(0, 16)
	_shadow.scale = _profile.shadow_scale
	# Lista de animaciones BASE (sin sufijo de direccion).
	_anim_pick.clear()
	var bases: Array[String] = []
	if _profile.sprite_frames != null:
		for anim in _profile.sprite_frames.get_animation_names():
			var base: String = String(anim)
			for suffix in CharacterVisualProfile.DIR_SUFFIXES_8:
				if base.ends_with("_%s" % suffix):
					base = base.trim_suffix("_%s" % suffix)
					break
			if base not in bases:
				bases.append(base)
	for b in bases:
		_anim_pick.add_item(b)
	_refresh_animation()


func _refresh_animation() -> void:
	if _profile == null or _profile.sprite_frames == null or _anim_pick.item_count == 0:
		_update_info()
		return
	var base := StringName(_anim_pick.get_item_text(max(0, _anim_pick.selected)))
	var dir_vec: Vector2 = DIRECTIONS[max(0, _dir_pick.selected)]["vec"]
	var dir_info: Dictionary = SpriteDirectionResolver.resolve(dir_vec.normalized(), _profile.direction_count, _profile.mirror_allowed())
	var anim: StringName = SpriteDirectionResolver.animation_name(_profile.sprite_frames, base, dir_info["suffix"])
	if _profile.sprite_frames.has_animation(anim):
		_sprite.flip_h = dir_info["flip"]
		_sprite.play(anim)
		_pause_btn.text = "Pausa"
	_markers.queue_redraw()
	_update_info()


## Comparacion PROCEDURAL | SPRITE: instancia la escena real del personaje
## (segun la categoria del perfil) congelada a la izquierda del sprite.
func _toggle_compare(on: bool) -> void:
	if is_instance_valid(_compare_node):
		_compare_node.queue_free()
		_compare_node = null
	if not on or _profile == null:
		return
	var category: String = ""
	if not _profiles.is_empty() and _profile_pick.selected >= 0:
		var path: String = _profiles[_profile_pick.selected]
		for cat in COMPARE_SCENES:
			if path.contains("/%s/" % cat):
				category = cat
				break
	if category == "":
		return
	var packed: PackedScene = load(COMPARE_SCENES[category])
	if packed == null:
		return
	_compare_node = packed.instantiate() as Node2D
	_compare_node.position = Vector2(-120, 0)
	_stage.add_child(_compare_node)
	# Congelado: solo queremos ver su arte procedural, no su gameplay.
	_compare_node.set_physics_process(false)
	_compare_node.set_process(false)


func _toggle_pause() -> void:
	if _sprite.is_playing():
		_sprite.pause()
		_pause_btn.text = "Reanudar"
	else:
		_sprite.play()
		_pause_btn.text = "Pausa"
	_update_info()


func _update_info() -> void:
	if _profile == null:
		return
	var validity: String = "VALIDO" if _profile.is_valid() else ("INVALIDO: " + ", ".join(_profile.validation_errors()))
	var test_tag: String = "  [TEST_ONLY]" if _profile.is_test_only() else ""
	_info.text = "%s%s\nanim=%s frame=%d flip=%s escala=%s offset=%s\n%s" % [
		_profile.visual_id, test_tag, _sprite.animation, _sprite.frame,
		str(_sprite.flip_h), str(_profile.visual_scale), str(_profile.visual_offset), validity]


func _draw_markers() -> void:
	if not _show_markers:
		return
	# Origen logico del personaje (cruz roja) = donde estaria el centro de la
	# colision. Punto de pies (linea magenta) = origen + 22 px tipicos.
	_markers.draw_line(Vector2(-10, 0), Vector2(10, 0), Color(1, 0.3, 0.3, 0.9), 1.5)
	_markers.draw_line(Vector2(0, -10), Vector2(0, 10), Color(1, 0.3, 0.3, 0.9), 1.5)
	_markers.draw_line(Vector2(-16, 22), Vector2(16, 22), Color(1, 0.2, 1, 0.7), 1.5)
	# Bounds del frame actual.
	if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(_sprite.animation):
		var tex: Texture2D = _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
		if tex != null:
			var size: Vector2 = tex.get_size() * _sprite.scale
			_markers.draw_rect(Rect2(_sprite.position - size * 0.5, size), Color(0.3, 1, 0.6, 0.8), false, 1.0)
