# ETAPA ARTÍSTICA 2 — Migración progresiva a sprites definitivos

Estado honesto: **no existían paquetes de arte definitivo** en el proyecto ni
en `_incoming` (solo la hoja TEST_ONLY de la Etapa 1). Por la regla de assets
(sección 1 del encargo), NO se sustituyó ningún arte procedural ni se declaró
ningún personaje "terminado". Esta etapa completó el **GATE A entero**
(correcciones del pipeline), la infraestructura de recepción/aceptación, la
herramienta de preview y dejó el LOTE P0 **bloqueado en la puerta de assets**
con la lista exacta de lo que falta.

## GATE A — Correcciones técnicas (COMPLETADO)

### 3.1 Flash de daño unificado
`CharacterVisualController` expone:
- `get_active_visual_canvas_item()` — sprite si está activo, si no el `Visual` procedural.
- `flash_damage(color, duration)` — aplica al visual ACTIVO; captura el
  modulate previo SOLO si no hay flash en curso (retrigger seguro, sin
  capturar el rojo) y restaura a ese valor → **respeta el tinte de P2, los
  tintes de estado y los recolores por datos** (de paso arregla que el flash
  de P2 lo devolviera a blanco).
- `set_visual_modulate()` / `reset_visual_modulate()` — fijan el tinte BASE
  al que vuelve el flash.

Enrutado con fallback al código clásico en: `player.gd`, `companion.gd`,
`boss.gd`, `mini_boss.gd`. `enemy.gd` NO se tocó: su flash usa el modulate del
nodo raíz, que ya afecta por igual a procedural y sprite.

### 3.2 SpriteVisual en todos los actores
Nodo dormido (sin perfil) añadido a `Companion.tscn`, `MiniBoss.tscn` y
`Boss.tscn` (Player y Enemy ya lo tenían). Cero cambios de colisión, grupos,
señales o stats; sin perfil el juego es idéntico (regresión verificada).

### 3.3 Acciones visuales explícitas
Wrappers `play_idle/run/attack/hurt/death/downed/revive/ability/
charge_windup/charge/summon/phase_change` en el controlador. Conectadas desde
gameplay (solo representación, guardadas con `get_node_or_null`):
- `boss.gd`: windup → `charge_windup`; carga → `charge`; invocación →
  `summon`; cambio de fase → `phase_change` (muerte/daño ya llegan por señal).
- `companion.gd`: disparo → `play_attack`; curación del médico → `play_ability`.
- Player/Enemy: idle/run/hurt/death/downed/revive por velocity + señales
  (el ataque del player son armas automáticas; el del enemigo es contacto —
  se definirá cuando exista arte con anim de mordisco).

### 3.4 Prioridades de animación
`PRIORITY` en el controlador: death 100 > downed 95 > revive 90 >
phase_change 85 > special_attack 80 > charge 75 > charge_windup 74 >
summon 72 > hurt 60 > ability 55 > attack 50 > run 10 > idle 0.
Reglas: una acción solo cede ante prioridad mayor; `death` no se reemplaza
jamás; `downed` solo lo saca `revive`; al terminar una one-shot se vuelve a
idle/run según movimiento; death/downed persisten en su último frame.

### 3.5 Mirroring y asimetrías
`CharacterVisualProfile` ganó `has_asymmetric_design`,
`require_unique_west_frames` y `preserve_painted_light_direction`.
`mirror_allowed()` = flip permitido Y sin asimetrías — controlador y
validador usan SIEMPRE esa función. Diseño asimétrico ⇒ espejo bloqueado
aunque `flip_horizontal_allowed` esté en true (y el validador avisa que se
esperan frames oeste propios).

### Validador ampliado
Nuevos checks: perfil ACTIVADO con asset TEST_ONLY (error), texturas servidas
desde `_incoming` (error), perfil ACTIVADO sin animaciones obligatorias de su
categoría (error; desactivado sigue siendo aviso), conflicto flip+asimetría
(aviso). Además el controlador ignora perfiles TEST_ONLY en modo AUTO aunque
alguien los active a mano.

## Infraestructura de recepción

- `assets/art/_incoming/` con README del flujo (prohibido cargar desde ahí).
- `docs/ART_ASSET_ACCEPTANCE_CHECKLIST.md` — puerta de aceptación.
- `docs/ART_IMPORT_MANIFEST.md` — registro por paquete (incluye el TEST de E1).
- `docs/SPRITE_MIGRATION_REPORT.md` — estado por personaje.

## Herramienta de preview

`scenes/visual/tools/CharacterArtPreview.tscn` (F6 o
`Godot --path . res://scenes/visual/tools/CharacterArtPreview.tscn`):
selector de perfil (escanea `data/visual_profiles/`), animación base,
8 direcciones (con espejo según el perfil), pausa, avance frame a frame,
fondos Claro/Oscuro/Barrio/Parque/Industrial, sombra on/off, pivote + línea
de pies + bounds, y estado de validez/TEST_ONLY del perfil en pantalla.

## LOTE P0 — resultado

**BLOQUEADO EN LA PUERTA DE ASSETS** (correcto según las reglas): no hay
PNG definitivos de `leader_cat` ni `zombie_dog_normal`. El pipeline quedó
listo de extremo a extremo y verificado con el asset TEST_ONLY vía
FORCE_SPRITE (12/12 checks del GATE A aprobados). Assets exactos que faltan:
ver `SPRITE_MIGRATION_REPORT.md`.

## Pruebas ejecutadas

- GATE A headless 12/12: AUTO ignora TEST_ONLY; FORCE_SPRITE activa; flash en
  sprite restaura tinte base (no blanco); death irreemplazable; hurt>attack;
  attack no interrumpe hurt; downed persiste ante run; revive sale de downed;
  preview instancia sin errores.
- Validador: 1 perfil, 0 errores (2 avisos esperados del TEST).
- Regresión: import limpio, menú 600 frames, MainLevel 2600 frames sin errores
  (con SpriteVisual dormido en los 5 actores).

## Presupuesto de memoria (estimado para cuando lleguen los lotes)

- Hoja 2048×2048 RGBA sin comprimir ≈ 16 MB VRAM (con mipmaps ×1.33).
- LOTE P0 (player ~170 frames + zombi ~110 frames a 128 px): 2 hojas 2048 ≈
  **~43 MB** con mipmaps — trivial. SpriteFrames COMPARTIDOS por instancias
  (un `.tres` por tipo; las hordas reutilizan la misma textura → sin costo por
  enemigo). Boss en hoja propia (384 px/celda).

## Riesgos restantes

- El squash/lean procedural del player y el bob del enemigo no aplican al
  sprite (la animación dibujada los sustituirá; evaluar en QA del P0 real).
- El volteo vertical del `Visual` procedural del enemigo no aplica al sprite
  (el resolver de direcciones lo reemplaza) — verificar con arte real.
- La anim `attack` del enemigo por contacto no tiene trigger todavía.
- El downed del player rota el `Visual` procedural; en sprite lo hará la anim
  `downed` — revisar que no queden dos señales visuales al alternar modos.

## Etapa Artística 3 (tras recibir y aprobar arte)

1. Recibir paquetes P0 por `_incoming`, pasar la puerta y migrar de verdad.
2. QA visual en los 3 biomas con CanvasModulate + luces.
3. LOTE P1 (P2/compañeros/variantes) y P2 (pesado/mini-jefe/jefe) por gates.
4. Entonces sí: retratos en HUD/cartas, anim de ataque de enemigo por
   contacto, y evaluar normal maps/iluminación avanzada sobre sprites.
