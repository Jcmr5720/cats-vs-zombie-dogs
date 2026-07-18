# Tipografía de Cats vs Zombie Dogs

Sistema tipográfico central del juego. Las fuentes se cargan y combinan en
`scripts/ui/ui_fonts.gd` (pesos, fallbacks, escala de accesibilidad) y el Theme
global vive en `scripts/ui/ui_theme.gd` (autoload `UITheme`).

## Familias

| Fuente | Archivo | Autor | Licencia | Rol |
| --- | --- | --- | --- | --- |
| Fredoka | `Fredoka-VariableFont.ttf` (variable: `wght` 300–700, `wdth`) | Milena Brandão, Hafontia | SIL OFL 1.1 (`licenses/OFL-Fredoka.txt`) | **Principal**: HUD, botones, títulos, pestañas, tarjetas, contadores |
| Nunito Sans | `NunitoSans-VariableFont.ttf` (variable: `wght` 200–1000, `opsz`, `wdth`, `YTLC`) | Vernon Adams, Jacques Le Bailly, TypeMade | SIL OFL 1.1 (`licenses/OFL-NunitoSans.txt`) | **Lectura**: descripciones, ajustes, diálogos, créditos, textos largos |
| Lilita One | `LilitaOne-Regular.ttf` (un solo peso, 400) | Juan Montoreano | SIL OFL 1.1 (`licenses/OFL-LilitaOne.txt`) | **Impacto**: logo, BOSS/VICTORIA/DERROTA, avisos especiales. Uso limitado |

Las tres licencias OFL permiten uso y distribución comercial embebida en un
videojuego. Los pesos concretos (Medium/SemiBold/Bold…) se instancian en
runtime desde el eje `wght` de las fuentes variables mediante `FontVariation`
(un solo archivo por familia: sin duplicados ni variantes muertas).

## Pesos usados

- Fredoka: 500 (Medium, HUD/textos medios), 600 (SemiBold, botones/tarjetas), 700 (Bold, títulos/avisos).
- Nunito Sans: 400 (Regular, lectura), 600 (SemiBold, etiquetas/subtítulos), 700 (Bold, datos destacados).
- Lilita One: 400 (único).

## Orden de fallback (glifos que falten)

1. Lilita One → 2. Fredoka → 3. Nunito Sans → 4. Fuente sans-serif del sistema
(`SystemFont`, cubre símbolos de mandos, nombres de jugador y traducciones
futuras). Configurado en `UIFonts._setup()`.

Todas las familias cubren el español completo (á é í ó ú ü ñ Ñ ¿ ¡), dígitos y
signos (%, +, −, ×, :). Verificado por `tests/test_typography.gd`.
