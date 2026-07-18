# Sistema tipográfico (renovación Steam)

Identidad tipográfica del juego: divertida, arcade y de calidad comercial, con
una sola fuente de verdad y sin fuentes asignadas a mano por nodo.

## Familias y roles

| Familia | Rol | Dónde |
| --- | --- | --- |
| **Fredoka** (variable) | Principal | HUD, botones, pestañas, títulos de menú, nombres de tarjetas, contadores, etiquetas de jugador |
| **Nunito Sans** (variable) | Lectura | Descripciones de tarjetas, ajustes, diálogos/cinemáticas, tooltips, textos largos |
| **Lilita One** | Impacto | Logo, VICTORIA/DERROTA, MINI-JEFE/BOSS/élite, FURIA FINAL, DERRIBADO, racha |

Pesos instanciados desde el eje variable (`FontVariation`): Fredoka 500/600/700,
Nunito Sans 400/600/700, Lilita One único. Archivos y licencias OFL en
`assets/fonts/` (ver su README.md).

## Arquitectura

- `scripts/ui/ui_fonts.gd` (**UIFonts**, estático): carga cada familia UNA vez,
  crea/cachea los pesos, encadena fallbacks (Lilita → Fredoka → Nunito →
  sans-serif del sistema) y aplica la escala de accesibilidad (`scaled()`, con
  mínimo legible `MIN_FONT_SIZE = 10`).
- `scripts/ui/ui_theme.gd` (autoload **UITheme**): construye el Theme global,
  lo asigna a la ventana raíz y define las **variaciones** (usar con
  `theme_type_variation`): GameTitle, ImpactTitle, BossAnnouncement, MenuTitle,
  PanelTitle, Subheading, SectionTitle, BossName, PhaseAnnouncement,
  HudEmphasis, HudPrimary, HudSecondary, BarValue, NumericCounter (cifras
  tabulares), PlayerLabel, MinimapLabel, CardTitle, CardDescription, CardValue,
  CardMeta, DialogText, AccessibilityText, SmallLabel, PrimaryButton,
  SecondaryButton.
- `MenuTheme` expone fábricas ya integradas: `make_title` (Fredoka Bold),
  `make_impact_title` (Lilita), `make_text` (Nunito lectura), `make_label`,
  `make_button` (Fredoka SemiBold).

## Reglas para código nuevo

1. Nada de `SystemFont`/TTF sueltos: usa una variación del Theme
   (`label.theme_type_variation = &"HudPrimary"`) o `UIFonts.fredoka(600)` etc.
2. Tamaños SIEMPRE con `UIFonts.scaled(n)` para que respondan al ajuste
   "Tamaño de texto" (Opciones → Juego): pequeño 0.9 / normal 1.0 /
   grande 1.15 / muy grande 1.3. El logo y elementos decorativos no escalan.
3. Lilita One solo en textos cortos y memorables; nunca en párrafos, botones
   pequeños ni HUD permanente.
4. Avisos: `hud.show_announcement()` = impacto (Lilita, animación breve);
   `hud.show_event_message()` = informativo (Fredoka).

## Trampas de Godot 4.7 (aprendidas aquí)

- `FontVariation.variation_opentype` necesita la clave **"weight"**; con
  `"wght"` la coordenada se ignora en silencio (y el Fredoka variable tiene
  default 300 Light → todo se ve fino).
- El `Window.theme` **no atraviesa nodos no-Control** (CanvasLayer, Node2D).
  UITheme lo compensa asignando el Theme a todo Control cuyo padre no sea
  Control/Window (señal `node_added` + barrido inicial).
- Las cachés estáticas de fuentes deben vaciarse al salir (UITheme
  `_exit_tree`) o el TextServer reporta RIDs filtrados.

## Validación

- `godot --headless --path . res://tests/TestTypography.tscn` — 151 checks:
  archivos, fallbacks, variaciones y familia por rol, cobertura de español
  (á é í ó ú ü ñ ¿ ¡ × % + −), pesos reales del eje variable, escala de
  accesibilidad y persistencia, variaciones en el HUD real.
- `godot --path . --resolution 1280x720 res://tests/TypographyScreenshot.tscn`
  (render real) — capturas de HUD combate/boss/cartas/victoria/derrota,
  variante "Muy grande" y cartas coop en `user://ui_shots/`.
- `tests/UIScreenshot.tscn` y `tests/CoopScreenshot.tscn` siguen cubriendo
  menús y pantalla dividida.
