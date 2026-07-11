extends SceneTree
## Herramienta del pipeline (paso 2 de 2): construye los SpriteFrames y el
## CharacterVisualProfile de PRUEBA a partir de la hoja generada por
## make_test_sprite.gd (requiere haber corrido --import antes para que la PNG
## este importada).
##
##   Godot --headless --path . --script res://scripts/visual/tools/make_test_frames.gd
##
## Es tambien la REFERENCIA de como montar SpriteFrames por codigo para
## cualquier personaje futuro (la via manual por editor tambien vale).

const SHEET := "res://assets/art/characters/players/test/test_cat_sheet.png"
const FRAMES_OUT := "res://assets/art/characters/players/test/test_cat_frames.tres"
const PROFILE_OUT := "res://data/visual_profiles/players/test_cat.tres"
const CELL := 128


func _initialize() -> void:
	var sheet: Texture2D = load(SHEET)
	if sheet == null:
		printerr("Hoja no importada aun: correr --import primero")
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FRAMES_OUT.get_base_dir()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROFILE_OUT.get_base_dir()))

	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	# Fila 0 = idle (loop 6 fps). Fila 1 = run (loop 10 fps).
	_add_row(frames, sheet, &"idle", 0, 6.0, true)
	_add_row(frames, sheet, &"run", 1, 10.0, true)
	# Acciones de prueba: reutilizan frames existentes con otro ritmo/loop.
	_add_row(frames, sheet, &"attack", 1, 14.0, false)
	_add_row(frames, sheet, &"hurt", 0, 12.0, false)
	_add_row(frames, sheet, &"death", 0, 4.0, false)
	var err: int = ResourceSaver.save(frames, FRAMES_OUT)
	print("SpriteFrames -> %s (err=%d)" % [FRAMES_OUT, err])

	var profile := CharacterVisualProfile.new()
	profile.visual_id = &"test_cat"
	profile.display_name = "Gato de prueba tecnica (NO arte final)"
	# enabled=false + TEST_ONLY: el perfil NUNCA se activa solo en el juego
	# real; la prueba tecnica lo fuerza via set_debug_mode(FORCE_SPRITE).
	profile.enabled = false
	profile.asset_status = "TEST_ONLY"
	profile.sprite_frames = frames
	profile.default_animation = &"idle"
	profile.direction_count = 1
	profile.flip_horizontal_allowed = true
	profile.visual_scale = Vector2(0.5, 0.5)
	# Pivote: la linea de suelo del arte esta en y=112 de la celda (centro 64):
	# offset = pies_del_gameplay(22) - (112-64)*0.5 = -2.
	profile.visual_offset = Vector2(0, -2)
	var err2: int = ResourceSaver.save(profile, PROFILE_OUT)
	print("VisualProfile -> %s (err=%d)" % [PROFILE_OUT, err2])
	quit(0 if err == OK and err2 == OK else 1)


func _add_row(frames: SpriteFrames, sheet: Texture2D, anim: StringName, row: int, fps: float, loop: bool) -> void:
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, loop)
	for col in 4:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(col * CELL, row * CELL, CELL, CELL)
		frames.add_frame(anim, atlas)
