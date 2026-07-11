# ART PIPELINE — de concepto a personaje jugable

Flujo completo para incorporar arte definitivo sin tocar gameplay.

```
Concepto → Ilustración/Generación → Limpieza → Frames → SpriteSheet
   → _incoming → PUERTA DE ACEPTACIÓN → carpeta definitiva
   → Importación → SpriteFrames → VisualProfile → Validación → Integración → QA
```

**Etapa 2**: todo paquete entra por `assets/art/_incoming/` y pasa la
`ART_ASSET_ACCEPTANCE_CHECKLIST.md` antes de tocar el juego; se registra en
`ART_IMPORT_MANIFEST.md`. El validador rechaza perfiles que carguen texturas
desde `_incoming` o activen assets TEST_ONLY. QA visual rápido con
`scenes/visual/tools/CharacterArtPreview.tscn`.

## 1. Concepto
Definir el asset contra `ART_DIRECTION_BIBLE.md` (formas, paleta, lectura) y
`ART_ASSET_INVENTORY.md` (prioridad, tamaño, animaciones, direcciones).

## 2. Ilustración o generación
Dibujar (Krita/Photoshop/Procreate) o generar con IA usando
`AI_ART_PROMPT_GUIDE.md`. **Archivos fuente (PSD/KRA/blend): guardarlos FUERA
de `res://` — recomendado `art_source/` en la raíz del repo (añadido a
.gitignore si pesa) o almacenamiento externo del equipo. Al export final de
Godot solo entran los PNG de `res://assets/`.**

## 3. Limpieza
Fondo transparente real, sin halos (defringe), recorte a la celda estándar,
pivote en la línea de suelo (ver SPRITE_TECHNICAL_SPEC), luz desde NO,
paleta corregida.

## 4. Separación de frames y SpriteSheet
Una fila por animación (o por dirección de una animación), celdas del tamaño
estándar, personaje idéntico de frame a frame. Nombrar la hoja:
`<personaje>_sheet.png` (o `<personaje>_<anim>.png` si va suelta).

## 5. Importación
Copiar a `res://assets/art/<categoria>/...`. Godot la importa al abrir el
editor o con `--headless --import`. Verificar filtro lineal + mipmaps
(preset del proyecto o por asset).

## 6. SpriteFrames
Dos vías:
- **Editor**: crear `SpriteFrames`, añadir animaciones con el contrato de
  nombres (`run`, `run_se`, ...), asignar frames desde la hoja (Add frames
  from sprite sheet), fijar FPS y loop según la spec.
- **Por código** (referencia funcional):
  `scripts/visual/tools/make_test_frames.gd` construye AtlasTextures por celda
  y guarda el `.tres`. Copiarlo y adaptarlo para hojas reales.

Guardar como `res://assets/art/<categoria>/<personaje>/<personaje>_frames.tres`.

## 7. CharacterVisualProfile
Crear `.tres` en `res://data/visual_profiles/<categoria>/<personaje>.tres`
(clic derecho → New Resource → CharacterVisualProfile):
- `visual_id` único, `sprite_frames`, `direction_count`, `visual_scale`
  (0.5 si se dibujó a 2×), `visual_offset` (fórmula del pivote en la spec),
  `flip_horizontal_allowed`, `enabled = false` hasta aprobar QA.

## 8. Validación
```
Godot_console --headless --path . --script res://scripts/visual/run_art_validator.gd
```
Cero errores obligatorio; revisar avisos (animaciones recomendadas faltantes,
atlas > 2048).

## 9. Integración
Asignar el perfil al nodo `SpriteVisual` de la escena del personaje
(Player.tscn y Enemy.tscn ya lo tienen; para Companion/Boss/MiniBoss,
instanciar `scenes/visual/characters/SpriteCharacterVisual.tscn` como hijo).
Con `enabled = false` no cambia nada; para probar en vivo poner
`debug_mode = FORCE_SPRITE` en el inspector o `enabled = true` en el perfil.

## 10. QA
- Comparar procedural vs sprite con `debug_mode` (FORCE_PROCEDURAL ↔ FORCE_SPRITE).
- `show_visual_bounds = true` para verificar escala y pivote contra la sombra.
- Jugar: mover en 8 direcciones, recibir daño, morir, reiniciar con R.
- Coop: P1 y P2 a la vez.
- Al aprobar: `enabled = true` en el perfil. El procedural queda como fallback
  (NO borrar los Polygon2D en esta etapa).

## Estructura de carpetas

```
res://assets/art/            ← PNG y SpriteFrames finales
    characters/{players,companions,enemies,bosses}/
    environments/{neighborhood,park,industrial,shelter}/
    props/  weapons/  projectiles/  vfx/
    ui/{icons,cards,hud,menus}/
res://data/visual_profiles/{players,companions,enemies,bosses}/
res://scenes/visual/characters/   ← plantillas visuales
res://scripts/visual/             ← controlador, perfil, resolver, validador
art_source/ (fuera de res://)     ← PSD/KRA/blend
```
Las carpetas se crean cuando llega su primer asset (no hay carpetas vacías).
