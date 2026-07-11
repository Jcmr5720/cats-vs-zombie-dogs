class_name ArtPipelineValidator
extends RefCounted
## Validador del pipeline de sprites (ETAPA ARTISTICA 1). Recorre todos los
## CharacterVisualProfile de res://data/visual_profiles/ y reporta problemas
## tipicos antes de que lleguen al juego. Se puede ejecutar desde el editor,
## desde un test o headless:
##   Godot --headless --path . --script res://scripts/visual/run_art_validator.gd

const PROFILES_ROOT := "res://data/visual_profiles"
## Lado maximo recomendado para un atlas (px). Mas grande = aviso.
const MAX_ATLAS_SIDE: int = 2048

## Animaciones recomendadas por categoria (carpeta bajo visual_profiles/).
const RECOMMENDED_BY_CATEGORY: Dictionary = {
	"players": [&"idle", &"run", &"attack", &"hurt", &"downed", &"revive", &"death"],
	"companions": [&"idle", &"run", &"attack", &"ability", &"hurt", &"downed", &"revive"],
	"enemies": [&"idle", &"run", &"attack", &"hurt", &"death"],
	"bosses": [&"idle", &"run", &"basic_attack", &"special_attack", &"charge_windup", &"charge", &"summon", &"hurt", &"phase_change", &"death"],
}


## Valida todos los perfiles. Devuelve {"errors": [...], "warnings": [...],
## "profiles": n}. Los errores rompen el uso del perfil; los avisos no.
static func validate_all() -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var seen_ids: Dictionary = {}
	var profiles: int = 0

	for path in _find_profiles(PROFILES_ROOT):
		var res: Resource = load(path)
		if res == null:
			errors.append("%s: no carga" % path)
			continue
		if not (res is CharacterVisualProfile):
			warnings.append("%s: no es CharacterVisualProfile (ignorado)" % path)
			continue
		profiles += 1
		var profile := res as CharacterVisualProfile

		# Errores duros del perfil (los mismos que usa el controlador).
		for err in profile.validation_errors():
			errors.append("%s: %s" % [path, err])

		# ID duplicado.
		if profile.visual_id != &"":
			if seen_ids.has(profile.visual_id):
				errors.append("%s: visual_id '%s' duplicado (tambien en %s)" % [path, profile.visual_id, seen_ids[profile.visual_id]])
			seen_ids[profile.visual_id] = path

		# ETAPA ARTISTICA 2: un perfil ACTIVADO no puede usar arte TEST_ONLY.
		if profile.enabled and profile.is_test_only():
			errors.append("%s: perfil ACTIVADO con asset TEST_ONLY (id o textura de prueba)" % path)

		# ETAPA ARTISTICA 3: el estado artistico gobierna la activacion.
		if profile.enabled:
			match profile.asset_status:
				"TEST_ONLY", "PLACEHOLDER", "PILOT_ART":
					errors.append("%s: perfil ACTIVADO con asset_status=%s (solo Preview/debug)" % [path, profile.asset_status])
				"FINAL_CANDIDATE":
					warnings.append("%s: FINAL_CANDIDATE activado — solo se vera en builds de DESARROLLO; el export de produccion usara procedural" % path)
				"APPROVED_FINAL":
					pass
				_:
					errors.append("%s: asset_status desconocido '%s'" % [path, profile.asset_status])

		# Oeste real exigido: si el perfil esta activado y requiere frames
		# oeste propios, deben existir (al menos run_w / idle_w).
		if profile.enabled and profile.require_unique_west_frames and profile.sprite_frames != null:
			var has_west: bool = false
			for anim_w in profile.sprite_frames.get_animation_names():
				if String(anim_w).ends_with("_w") or String(anim_w).ends_with("_nw") or String(anim_w).ends_with("_sw"):
					has_west = true
					break
			if not has_west:
				errors.append("%s: exige oeste real (require_unique_west_frames) pero no hay animaciones *_w/*_nw/*_sw" % path)

		# Luz pintada direccional + espejo permitido: aviso de QA (el espejo
		# invertira la iluminacion pintada).
		if profile.enabled and profile.preserve_painted_light_direction and profile.mirror_allowed():
			warnings.append("%s: espejo permitido con luz pintada direccional (preserve_painted_light_direction): revisar en Preview que el flip no rompa la iluminacion" % path)

		# Config contradictoria de espejo: se permite flip pero el diseno es
		# asimetrico -> mirror_allowed() ya lo bloquea; avisar para que el
		# artista sepa que se esperan frames oeste propios.
		if profile.flip_horizontal_allowed and (profile.has_asymmetric_design or profile.require_unique_west_frames):
			warnings.append("%s: flip permitido pero diseno asimetrico: el espejo queda BLOQUEADO; se requieren frames oeste propios" % path)

		if profile.sprite_frames == null:
			continue

		# Texturas servidas directamente desde la carpeta de recepcion.
		for anim_name_in in profile.sprite_frames.get_animation_names():
			if profile.sprite_frames.get_frame_count(anim_name_in) > 0:
				var t0: Texture2D = profile.sprite_frames.get_frame_texture(anim_name_in, 0)
				var b0: Texture2D = t0.atlas if t0 is AtlasTexture else t0
				if b0 != null and b0.resource_path.contains("/_incoming/"):
					errors.append("%s: usa texturas directamente de _incoming (mover a carpeta definitiva)" % path)
					break

		# Animaciones recomendadas por categoria. Perfil DESACTIVADO: aviso.
		# Perfil ACTIVADO: error (no se activa un personaje con set incompleto).
		var category: String = _category_of(path)
		for anim in RECOMMENDED_BY_CATEGORY.get(category, []):
			if not profile.has_animation_any_direction(anim):
				if profile.enabled:
					errors.append("%s: perfil ACTIVADO sin animacion obligatoria '%s' (%s)" % [path, anim, category])
				else:
					warnings.append("%s: falta animacion recomendada '%s' (%s)" % [path, anim, category])

		# Texturas: existencia y tamano de atlas.
		for anim_name in profile.sprite_frames.get_animation_names():
			for i in profile.sprite_frames.get_frame_count(anim_name):
				var tex: Texture2D = profile.sprite_frames.get_frame_texture(anim_name, i)
				if tex == null:
					errors.append("%s: frame %d de '%s' sin textura" % [path, i, anim_name])
					continue
				var base: Texture2D = tex.atlas if tex is AtlasTexture else tex
				if base != null and (base.get_width() > MAX_ATLAS_SIDE or base.get_height() > MAX_ATLAS_SIDE):
					warnings.append("%s: atlas de '%s' mide %dx%d (> %d recomendado)" % [path, anim_name, base.get_width(), base.get_height(), MAX_ATLAS_SIDE])
					break  # basta un aviso por animacion

	return {"errors": errors, "warnings": warnings, "profiles": profiles}


## Ejecuta y escribe el resultado en consola. Devuelve true si no hay errores.
static func run_and_print() -> bool:
	var result: Dictionary = validate_all()
	print("[ArtPipelineValidator] perfiles revisados: %d" % result["profiles"])
	for w in result["warnings"]:
		print("  AVISO: %s" % w)
	for e in result["errors"]:
		printerr("  ERROR: %s" % e)
	if (result["errors"] as Array).is_empty():
		print("[ArtPipelineValidator] OK — sin errores")
		return true
	printerr("[ArtPipelineValidator] %d errores" % (result["errors"] as Array).size())
	return false


static func _find_profiles(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full: String = root.path_join(entry)
		if dir.current_is_dir() and not entry.begins_with("."):
			found.append_array(_find_profiles(full))
		elif entry.ends_with(".tres") or entry.ends_with(".res"):
			found.append(full)
		entry = dir.get_next()
	return found


static func _category_of(path: String) -> String:
	for category in RECOMMENDED_BY_CATEGORY:
		if path.contains("/%s/" % category):
			return category
	return ""
