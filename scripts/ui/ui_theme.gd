extends Node
## Autoload "UITheme": Theme global del juego. Único punto donde se definen las
## variaciones tipográficas (fuente + tamaño + outline + sombra por rol). Se
## asigna a la ventana raíz, así CUALQUIER Control lo hereda sin overrides
## repetidos; los nodos eligen rol con `theme_type_variation` (o en .tscn).
##
## Escala de accesibilidad: el ajuste "text_size" de Settings (pequeño / normal /
## grande / muy_grande) multiplica los tamaños de todas las variaciones y del
## default. Al cambiar, se reescriben los valores del MISMO Theme y todos los
## controles vivos se refrescan solos (no se agranda el logo del menú).

## Niveles del ajuste "Tamaño de texto" (Opciones → Accesibilidad).
const TEXT_SIZE_LEVELS: Dictionary = {
	"pequeno": 0.9,
	"normal": 1.0,
	"grande": 1.15,
	"muy_grande": 1.3,
}
## Orden y etiqueta visibles en Opciones.
const TEXT_SIZE_OPTIONS: Array = [
	["pequeno", "Pequeño"],
	["normal", "Normal"],
	["grande", "Grande"],
	["muy_grande", "Muy grande"],
]

## Outline oscuro estándar: separa el texto de fondos variables sin deformarlo.
const OUTLINE_DARK := Color(0.03, 0.04, 0.07, 0.92)
const SHADOW_SOFT := Color(0, 0, 0, 0.5)

var theme: Theme = Theme.new()


func _enter_tree() -> void:
	_refresh_scale()
	_build()
	get_window().theme = theme
	# El Theme de la ventana solo se hereda por cadenas de Controls: un
	# CanvasLayer o Node2D intermedio la CORTA (HUD, overlays, rótulos del
	# mundo). Se asigna el mismo Theme a cada Control "raíz" que cuelgue de un
	# nodo no-Control, presente o futuro.
	get_tree().node_added.connect(_on_node_added)
	_apply_to_orphan_controls(get_tree().root)


func _on_node_added(node: Node) -> void:
	if node is Control and (node as Control).theme == null:
		var parent := node.get_parent()
		if parent != null and not (parent is Control) and not (parent is Window):
			(node as Control).theme = theme


## Barrido inicial: Controls ya presentes cuando UITheme entra (p.ej. overlays
## de autoloads previos como el contador de FPS de Settings).
func _apply_to_orphan_controls(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_apply_to_orphan_controls(child)


func _exit_tree() -> void:
	# Al cerrar el juego: soltar el Theme de la ventana y vaciar las cachés
	# estáticas de UIFonts para que el TextServer libere sus RID sin avisos
	# de fugas al salir (los estáticos sobreviven al teardown del árbol).
	var window := get_window()
	if window != null and window.theme == theme:
		window.theme = null
	UIFonts._bases.clear()
	UIFonts._cache.clear()


func _ready() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings != null and settings.has_signal("settings_changed"):
		settings.settings_changed.connect(_on_settings_changed)


func _on_settings_changed() -> void:
	var previous: float = UIFonts.text_scale
	_refresh_scale()
	if not is_equal_approx(previous, UIFonts.text_scale):
		_build()


func _refresh_scale() -> void:
	var settings := get_node_or_null("/root/Settings")
	var key := "normal"
	if settings != null and settings.has_method("get_value"):
		key = str(settings.get_value("text_size", "normal"))
	UIFonts.text_scale = float(TEXT_SIZE_LEVELS.get(key, 1.0))


# --- Construcción del Theme ------------------------------------------------------

func _build() -> void:
	# Defaults: Fredoka Medium en todo Control sin rol explícito.
	theme.default_font = UIFonts.fredoka(500)
	theme.default_font_size = UIFonts.scaled(15)

	# Botones: Fredoka SemiBold (los estilos de caja los pone MenuTheme).
	theme.set_font(&"font", &"Button", UIFonts.fredoka(600))
	theme.set_font_size(&"font_size", &"Button", UIFonts.scaled(18))

	# Tooltips: fuente de lectura.
	theme.set_font(&"font", &"TooltipLabel", UIFonts.nunito(400))
	theme.set_font_size(&"font_size", &"TooltipLabel", UIFonts.scaled(13))

	# --- Impacto (Lilita One; solo textos cortos y memorables) ---
	# El logo NO escala con accesibilidad (ya ocupa toda la cabecera).
	_label(&"GameTitle", UIFonts.lilita(), 60, {"outline": 10, "shadow": true, "no_scale": true})
	_label(&"ImpactTitle", UIFonts.lilita(), 44, {"outline": 9, "shadow": true})
	_label(&"BossAnnouncement", UIFonts.lilita(), 40, {"outline": 8, "shadow": true})

	# --- Títulos y estructura (Fredoka Bold) ---
	_label(&"MenuTitle", UIFonts.fredoka(700), 32, {"outline": 4, "shadow": true})
	_label(&"PanelTitle", UIFonts.fredoka(700), 26, {"outline": 4})
	_label(&"Subheading", UIFonts.fredoka(600), 22, {"outline": 3})
	_label(&"SectionTitle", UIFonts.fredoka(700), 20)
	_label(&"BossName", UIFonts.fredoka(700), 21, {"outline": 4, "shadow": true})
	_label(&"PhaseAnnouncement", UIFonts.fredoka(700), 18, {"outline": 4})

	# --- HUD (Fredoka Medium/SemiBold, outline para fondos variables) ---
	_label(&"HudEmphasis", UIFonts.fredoka(600), 18, {"outline": 3})
	_label(&"HudPrimary", UIFonts.fredoka(600), 16, {"outline": 3})
	_label(&"HudSecondary", UIFonts.fredoka(500), 14, {"outline": 3})
	_label(&"BarValue", UIFonts.fredoka(600), 12, {"outline": 2})
	_label(&"NumericCounter", UIFonts.fredoka_numeric(600), 30, {"outline": 4, "shadow": true})
	_label(&"PlayerLabel", UIFonts.fredoka(600), 14, {"outline": 3})
	_label(&"MinimapLabel", UIFonts.fredoka(500), 11, {"outline": 2})

	# --- Tarjetas de mejora ---
	_label(&"CardTitle", UIFonts.fredoka(600), 18)
	_label(&"CardDescription", UIFonts.nunito(400), 14, {"line_spacing": 3})
	_label(&"CardValue", UIFonts.fredoka(700), 16)
	_label(&"CardMeta", UIFonts.fredoka(500), 11)

	# --- Lectura (Nunito Sans) ---
	_label(&"DialogText", UIFonts.nunito(400), 16, {"line_spacing": 4, "outline": 3})
	_label(&"AccessibilityText", UIFonts.nunito(400), 16, {"line_spacing": 4})
	_label(&"SmallLabel", UIFonts.nunito(600), 12)

	# --- Variantes de botón ---
	_button(&"PrimaryButton", UIFonts.fredoka(600), 20)
	_button(&"SecondaryButton", UIFonts.fredoka(600), 16)


## Da de alta (o reescribe) una variación de Label.
## opts: outline (int), shadow (bool), line_spacing (int), no_scale (bool).
func _label(variation: StringName, font: Font, size: int, opts: Dictionary = {}) -> void:
	theme.set_type_variation(variation, &"Label")
	theme.set_font(&"font", variation, font)
	var final_size: int = size if opts.get("no_scale", false) else UIFonts.scaled(size)
	theme.set_font_size(&"font_size", variation, final_size)
	var outline: int = int(opts.get("outline", 0))
	if outline > 0:
		theme.set_color(&"font_outline_color", variation, OUTLINE_DARK)
		theme.set_constant(&"outline_size", variation, outline)
	if bool(opts.get("shadow", false)):
		theme.set_color(&"font_shadow_color", variation, SHADOW_SOFT)
		theme.set_constant(&"shadow_offset_x", variation, 0)
		theme.set_constant(&"shadow_offset_y", variation, 2)
	if opts.has("line_spacing"):
		theme.set_constant(&"line_spacing", variation, int(opts["line_spacing"]))


func _button(variation: StringName, font: Font, size: int) -> void:
	theme.set_type_variation(variation, &"Button")
	theme.set_font(&"font", variation, font)
	theme.set_font_size(&"font_size", variation, UIFonts.scaled(size))
