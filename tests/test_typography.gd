extends Node2D
## Valida el sistema tipográfico (UIFonts + UITheme): fuentes cargadas, Theme
## global asignado a la ventana, variaciones existentes con la familia correcta
## por rol, cobertura de caracteres del español, tamaño mínimo legible, ajuste
## de accesibilidad "Tamaño de texto" (aplicación + persistencia) y variaciones
## aplicadas en el HUD real.
##   godot --headless --path . res://tests/TestTypography.tscn

const MenuThemeLib = preload("res://scripts/menus/menu_theme.gd")

## Textos reales del juego que deben renderizar sin glifos faltantes.
const SAMPLE_TEXTS: Array[String] = [
	"Configuración", "Difícil", "Máximo", "Mutación", "Compañero", "Daño",
	"Elige una mejora", "Última oportunidad", "¡Boss élite!", "¿Reintentar?",
	"×2 +15% −3 0123456789:", "FURIA FINAL", "VICTORIA", "DERROTA",
]

## Variaciones que el Theme global debe definir, con su familia esperada.
const EXPECTED_VARIATIONS: Dictionary = {
	&"GameTitle": "lilita", &"ImpactTitle": "lilita", &"BossAnnouncement": "lilita",
	&"MenuTitle": "fredoka", &"PanelTitle": "fredoka", &"Subheading": "fredoka",
	&"SectionTitle": "fredoka", &"BossName": "fredoka", &"PhaseAnnouncement": "fredoka",
	&"HudEmphasis": "fredoka", &"HudPrimary": "fredoka", &"HudSecondary": "fredoka",
	&"BarValue": "fredoka", &"NumericCounter": "fredoka", &"PlayerLabel": "fredoka",
	&"MinimapLabel": "fredoka", &"CardTitle": "fredoka", &"CardMeta": "fredoka",
	&"CardValue": "fredoka", &"CardDescription": "nunito", &"DialogText": "nunito",
	&"AccessibilityText": "nunito", &"SmallLabel": "nunito",
}

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	# --- Archivos presentes (fuentes + licencias) ---
	for path in [UIFonts.FREDOKA_PATH, UIFonts.NUNITO_PATH, UIFonts.LILITA_PATH,
			"res://assets/fonts/licenses/OFL-Fredoka.txt",
			"res://assets/fonts/licenses/OFL-NunitoSans.txt",
			"res://assets/fonts/licenses/OFL-LilitaOne.txt"]:
		_expect(ResourceLoader.exists(path) or FileAccess.file_exists(path),
			"existe %s" % path)

	# --- Carga y caché ---
	var fredoka := UIFonts.fredoka(600)
	_expect(fredoka != null, "Fredoka SemiBold carga")
	_expect(UIFonts.fredoka(600) == fredoka, "los pesos se cachean (misma instancia)")
	_expect(UIFonts.nunito(400) != null, "Nunito Sans Regular carga")
	_expect(UIFonts.lilita() != null, "Lilita One carga")

	# Los pesos del eje variable se aplican DE VERDAD (regresión: con la clave
	# "wght" Godot ignoraba la coordenada y todo quedaba en Light).
	var sample := "Elige una mejora"
	var w_light: float = UIFonts.fredoka(300).get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	var w_bold: float = UIFonts.fredoka(700).get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	_expect(absf(w_light - w_bold) > 0.01, "el eje de peso de Fredoka cambia el trazo (300 vs 700)")
	var n_reg: float = UIFonts.nunito(400).get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	var n_bold: float = UIFonts.nunito(700).get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	_expect(absf(n_reg - n_bold) > 0.01, "el eje de peso de Nunito Sans cambia el trazo (400 vs 700)")

	# --- Fallbacks documentados ---
	var lilita_base: Font = load(UIFonts.LILITA_PATH)
	var fredoka_base: Font = load(UIFonts.FREDOKA_PATH)
	var nunito_base: Font = load(UIFonts.NUNITO_PATH)
	_expect(lilita_base.fallbacks.size() == 1 and lilita_base.fallbacks[0] == fredoka_base,
		"fallback: Lilita → Fredoka")
	_expect(fredoka_base.fallbacks.size() == 1 and fredoka_base.fallbacks[0] == nunito_base,
		"fallback: Fredoka → Nunito Sans")
	_expect(nunito_base.fallbacks.size() == 1 and nunito_base.fallbacks[0] is SystemFont,
		"fallback: Nunito Sans → fuente del sistema")

	# --- Theme global en la ventana raíz ---
	var ui_theme: Node = get_node_or_null("/root/UITheme")
	_expect(ui_theme != null, "autoload UITheme presente")
	var theme: Theme = null
	if ui_theme != null:
		theme = ui_theme.get("theme")
		_expect(get_window().theme == theme, "el Theme global está asignado a la ventana raíz")
		_expect(theme.default_font != null, "el Theme define fuente por defecto (Fredoka Medium)")
		_expect(theme.default_font == UIFonts.fredoka(500), "la fuente por defecto es Fredoka 500")
		_expect(theme.get_font(&"font", &"Button") == UIFonts.fredoka(600),
			"los botones usan Fredoka SemiBold")
		_expect(theme.get_font(&"font", &"TooltipLabel") == UIFonts.nunito(400),
			"los tooltips usan Nunito Sans")

	# --- Variaciones: existen, con la familia correcta y tamaño >= mínimo ---
	if theme != null:
		for variation in EXPECTED_VARIATIONS:
			var base := theme.get_type_variation_base(variation)
			_expect(base == &"Label", "variación %s existe (base Label)" % variation)
			var font := theme.get_font(&"font", variation)
			_expect(font != null and _family_of(font) == EXPECTED_VARIATIONS[variation],
				"variación %s usa %s" % [variation, EXPECTED_VARIATIONS[variation]])
			_expect(theme.get_font_size(&"font_size", variation) >= UIFonts.MIN_FONT_SIZE,
				"variación %s respeta el tamaño mínimo" % variation)
		_expect(theme.get_type_variation_base(&"PrimaryButton") == &"Button",
			"variación PrimaryButton existe (base Button)")
		_expect(theme.get_type_variation_base(&"SecondaryButton") == &"Button",
			"variación SecondaryButton existe (base Button)")

	# --- Español completo, dígitos y símbolos en las TRES familias ---
	for text in SAMPLE_TEXTS:
		_expect(_covers(fredoka_base, text), "Fredoka cubre \"%s\"" % text)
		_expect(_covers(nunito_base, text), "Nunito Sans cubre \"%s\"" % text)
		_expect(_covers(lilita_base, text), "Lilita One cubre \"%s\"" % text)

	# --- Escala de accesibilidad + tamaño mínimo ---
	var old_scale: float = UIFonts.text_scale
	UIFonts.text_scale = 0.9
	_expect(UIFonts.scaled(10) >= UIFonts.MIN_FONT_SIZE, "escala pequeña nunca baja del mínimo")
	UIFonts.text_scale = 1.3
	_expect(UIFonts.scaled(16) == 21, "escala muy grande multiplica (16 → 21)")
	UIFonts.text_scale = old_scale

	# --- Ajuste "text_size": aplica al Theme y persiste en Settings ---
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null and theme != null:
		var original: String = str(settings.get_value("text_size", "normal"))
		var base_size: int = theme.get_font_size(&"font_size", &"HudPrimary")
		settings.set_value("text_size", "muy_grande")
		await get_tree().process_frame
		var big_size: int = theme.get_font_size(&"font_size", &"HudPrimary")
		_expect(big_size > base_size, "el ajuste 'muy_grande' agranda el HUD (%d → %d)" % [base_size, big_size])
		_expect(is_equal_approx(UIFonts.text_scale, 1.3), "UIFonts.text_scale sigue al ajuste")
		_expect(str(settings.get_value("text_size", "")) == "muy_grande", "el ajuste persiste en Settings")
		# El logo NO escala con accesibilidad.
		_expect(theme.get_font_size(&"font_size", &"GameTitle") == 60, "GameTitle no escala (logo)")
		settings.set_value("text_size", original)
		await get_tree().process_frame
		_expect(theme.get_font_size(&"font_size", &"HudPrimary") == base_size,
			"restaurar el ajuste devuelve el tamaño original")

	# --- Fábricas de MenuTheme usan las familias correctas ---
	var title := MenuThemeLib.make_title("Título")
	_expect(_family_of(title.get_theme_font(&"font")) == "fredoka", "make_title usa Fredoka")
	var impact := MenuThemeLib.make_impact_title("VICTORIA")
	_expect(_family_of(impact.get_theme_font(&"font")) == "lilita", "make_impact_title usa Lilita One")
	var body := MenuThemeLib.make_text("Descripción de lectura")
	_expect(_family_of(body.get_theme_font(&"font")) == "nunito", "make_text usa Nunito Sans")
	var button := MenuThemeLib.make_button("Jugar")
	_expect(_family_of(button.get_theme_font(&"font")) == "fredoka", "make_button usa Fredoka")

	# --- El HUD real referencia las variaciones (sin overrides obsoletos) ---
	var hud_scene: PackedScene = load("res://scenes/ui/HUD.tscn")
	var hud: Node = hud_scene.instantiate()
	_expect((hud.get_node("TopCenter/TimeLabel") as Label).theme_type_variation == &"NumericCounter",
		"HUD: temporizador con variación NumericCounter")
	_expect((hud.get_node("TopLeft/Stats/LevelLabel") as Label).theme_type_variation == &"HudPrimary",
		"HUD: nivel con variación HudPrimary")
	_expect((hud.get_node("BossBar/BossName") as Label).theme_type_variation == &"BossName",
		"HUD: nombre de boss con variación BossName")
	_expect((hud.get_node("VictoryPanel/Center/Content/Title") as Label).theme_type_variation == &"ImpactTitle",
		"HUD: título de victoria con variación ImpactTitle (Lilita)")
	_expect((hud.get_node("GameOverPanel/Center/Content/Title") as Label).theme_type_variation == &"ImpactTitle",
		"HUD: título de derrota con variación ImpactTitle (Lilita)")
	_expect((hud.get_node("UpgradePanel/Center/Content/Cards/Card1/Margin/Content/Description") as Label).theme_type_variation == &"CardDescription",
		"HUD: descripción de carta con variación CardDescription (Nunito)")
	hud.free()

	print("")
	print("TestTypography: %d checks, %d fallos" % [_checks, _failures.size()])
	for f in _failures:
		printerr(" - " + f)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("shutdown"):
		audio.shutdown()
	get_tree().quit(0 if _failures.is_empty() else 1)


## Familia de una fuente del sistema UIFonts ("fredoka" / "nunito" / "lilita").
func _family_of(font: Font) -> String:
	if font == null:
		return ""
	var name := font.get_font_name().to_lower()
	if name.contains("fredoka"):
		return "fredoka"
	if name.contains("nunito"):
		return "nunito"
	if name.contains("lilita"):
		return "lilita"
	return name


## True si la fuente (con sus fallbacks) tiene glifo para cada carácter no-espacio.
func _covers(font: Font, text: String) -> bool:
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code == 32:
			continue
		if not _chain_has(font, code, 0):
			printerr("    glifo faltante U+%04X ('%s') en %s" % [code, char(code), font.get_font_name()])
			return false
	return true


func _chain_has(font: Font, code: int, depth: int) -> bool:
	if depth > 4 or font == null:
		return false
	if font.has_char(code):
		return true
	for fb in font.fallbacks:
		if _chain_has(fb, code, depth + 1):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  OK  ", message)
	else:
		_failures.append(message)
		printerr("  FALLO  ", message)
