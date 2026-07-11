class_name CharacterVisualProfile
extends Resource
## Perfil visual de un personaje (ETAPA ARTISTICA 1). Describe COMO se ve un
## personaje con sprites (SpriteFrames, escala, offset, direcciones...) sin
## tocar su logica. Si el perfil falta o es invalido, el personaje conserva su
## arte procedural actual (fallback). Un perfil = un .tres en
## res://data/visual_profiles/<categoria>/.

## Identificador unico (para validacion y depuracion). Ej: &"player_cat".
@export var visual_id: StringName = &""
@export var display_name: String = ""

## Interruptor maestro: en false el personaje usa SIEMPRE el arte procedural
## aunque el perfil tenga SpriteFrames validos (util para preparar arte sin
## activarlo todavia).
@export var enabled: bool = true

## Estado del arte (ETAPA ARTISTICA 3). Gobierna donde puede verse el sprite:
## - TEST_ONLY / PLACEHOLDER: nunca en juego (solo Preview/FORCE_SPRITE).
## - PILOT_ART: solo Preview/debug (validar estilo y animacion).
## - FINAL_CANDIDATE: puede probarse en MainLevel SOLO en builds de desarrollo.
## - APPROVED_FINAL: unico estado que permite activacion normal en produccion.
@export_enum("TEST_ONLY", "PLACEHOLDER", "PILOT_ART", "FINAL_CANDIDATE", "APPROVED_FINAL")
var asset_status: String = "PLACEHOLDER"

@export_group("Sprites")
## Frames del personaje. Contrato de nombres: <animacion> o <animacion>_<dir>
## con dir en {s, se, e, ne, n, nw, w, sw} segun direction_count.
@export var sprite_frames: SpriteFrames
## Animacion por defecto (se reproduce si falta la pedida).
@export var default_animation: StringName = &"idle"
## 1 = sin direcciones (una sola vista), 4 = s/e/n (+espejo O si se permite),
## 8 = las ocho (o 5 dibujadas + espejo si flip_horizontal_allowed).
@export_enum("1", "4", "8") var direction_count: int = 4
## Permite espejar horizontalmente las vistas este->oeste (ahorra frames).
@export var flip_horizontal_allowed: bool = true
@export var animation_speed_multiplier: float = 1.0

@export_group("Asimetrias (ETAPA ARTISTICA 2)")
## El diseno tiene elementos asimetricos (bufanda, placa, herida, protesis...):
## el espejo E->O los cambiaria de lado. Si es true, NO se espeja aunque
## flip_horizontal_allowed lo permita.
@export var has_asymmetric_design: bool = false
## Exige frames oeste propios (nw/w/sw dibujados): bloquea el espejo.
@export var require_unique_west_frames: bool = false
## La luz pintada (NO) se invertiria al espejar. Informativo para QA; no
## bloquea por si solo (la mayoria de estilos lo tolera a esta escala).
@export var preserve_painted_light_direction: bool = true

@export_group("Transformacion")
## Escala del sprite en el mundo (el arte se dibuja a 2x; tipicamente 0.5).
@export var visual_scale: Vector2 = Vector2(0.5, 0.5)
## Desplazamiento del sprite respecto al origen del personaje (el pivote del
## arte va en el punto de contacto con el suelo; el origen logico suele estar
## en el centro de la colision).
@export var visual_offset: Vector2 = Vector2.ZERO

@export_group("Sombra")
@export var shadow_scale: Vector2 = Vector2.ONE
@export var shadow_offset: Vector2 = Vector2(0, 16)

@export_group("Fallback y extras")
## Si el sprite falla (frames faltantes, textura rota), volver al procedural.
## En false, un perfil invalido deja al personaje SIN arte: solo para debug.
@export var use_procedural_fallback: bool = true
## Variante de paleta (para recolores futuros; 0 = base).
@export var palette_variant: int = 0
@export var portrait_texture: Texture2D
@export var icon_texture: Texture2D

## Animaciones minimas que debe contener sprite_frames (en al menos una
## direccion) para que el perfil se considere usable.
const REQUIRED_ANIMATIONS: Array[StringName] = [&"idle", &"run"]

const DIR_SUFFIXES_8: Array[String] = ["s", "se", "e", "ne", "n", "nw", "w", "sw"]


## True si este perfil puede activarse en gameplay normal. FINAL_CANDIDATE
## solo pasa en builds de desarrollo (editor/debug); APPROVED_FINAL siempre.
func can_activate_in_game() -> bool:
	if not enabled or is_test_only():
		return false
	match asset_status:
		"APPROVED_FINAL":
			return true
		"FINAL_CANDIDATE":
			return OS.is_debug_build()
		_:
			return false


## Espejo E->O efectivo: lo que el flag permite MENOS lo que la asimetria
## prohibe. El controlador y el validador usan SIEMPRE esta funcion.
func mirror_allowed() -> bool:
	return flip_horizontal_allowed and not has_asymmetric_design and not require_unique_west_frames


## True si el perfil apunta a arte de prueba (TEST_ONLY): id o rutas de
## textura marcados. Un perfil de prueba jamas debe activarse (enabled=true).
func is_test_only() -> bool:
	var id := String(visual_id).to_lower()
	if id.begins_with("test") or id.contains("test_only"):
		return true
	if sprite_frames != null:
		for anim in sprite_frames.get_animation_names():
			if sprite_frames.get_frame_count(anim) > 0:
				var tex: Texture2D = sprite_frames.get_frame_texture(anim, 0)
				var base: Texture2D = tex.atlas if tex is AtlasTexture else tex
				if base != null and (base.resource_path.to_lower().contains("/test/") or base.resource_path.to_lower().contains("test_only")):
					return true
	return false


## True si el perfil puede usarse para mostrar sprites.
func is_valid() -> bool:
	return validation_errors().is_empty()


## Lista de problemas ("" = ninguno). La usa el validador y el controlador.
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if visual_id == &"":
		errors.append("visual_id vacio")
	if sprite_frames == null:
		errors.append("sprite_frames nulo")
		return errors
	if visual_scale.x <= 0.0 or visual_scale.y <= 0.0:
		errors.append("visual_scale invalida (%s)" % visual_scale)
	for anim in REQUIRED_ANIMATIONS:
		if not has_animation_any_direction(anim):
			errors.append("falta animacion obligatoria '%s'" % anim)
	# Animaciones declaradas pero vacias (0 frames): error de exportacion tipico.
	for anim_name in sprite_frames.get_animation_names():
		if sprite_frames.get_frame_count(anim_name) == 0:
			errors.append("animacion '%s' sin frames" % anim_name)
	return errors


## True si existe la animacion, sea sin sufijo ("run") o con cualquier sufijo
## de direccion ("run_s", "run_ne"...).
func has_animation_any_direction(anim: StringName) -> bool:
	if sprite_frames == null:
		return false
	if sprite_frames.has_animation(anim):
		return true
	for suffix in DIR_SUFFIXES_8:
		if sprite_frames.has_animation(StringName("%s_%s" % [anim, suffix])):
			return true
	return false
