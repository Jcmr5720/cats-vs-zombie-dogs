# ETAPA ARTÍSTICA 3 — Producción, recepción e integración del primer arte

Estado honesto: **`_incoming` seguía vacío** (0 PNG; solo la hoja TEST_ONLY
de la Etapa 1). Por la regla absoluta de arte, NO se creó "arte definitivo"
por código ni se activó ningún sprite. Esta etapa completó **todas las
correcciones técnicas pendientes**, el sistema de estados artísticos, el
paquete de prompts P0, el flujo raw/clean/aligned con chequeo automático y
la ampliación del Preview. Gate B queda en B0, esperando la primera entrega.

## Correcciones técnicas (sección 3 del encargo — COMPLETADAS)

### 3.1 Ataque por contacto del enemigo
`enemy.gd` gana `_trigger_attack_anim()`: al intentar un ataque real en rango
(sobre jugador o compañero) dispara `play_attack()` con cadencia propia de
0.6 s (≈ el cooldown de invulnerabilidad del objetivo, 0.5 s) — nunca cada
frame. La animación SOLO representa; el daño sigue siendo el contacto
continuo de siempre. Sin perfil de sprite no hace nada.

### 3.2 Squash/bob/rotaciones procedurales separados
Los 5 actores saltan su animación procedural cuando el sprite está activo
(`is_sprite_active()` con nodo cacheado): el squash/lean del player, el
bob/trote/volteo del enemigo, el sway del compañero y la respiración/rotación
de jefes ya no ensucian transforms en modo sprite. Las auras (élite, jefes)
viven fuera del `Visual` y siguen pulsando en ambos modos. El controlador
gana `reset_visual_transform()`: captura el transform base del procedural al
entrar y lo restaura en cada cambio de modo (y resetea offset/escala/flip del
sprite). Nunca se acumulan transformaciones; colisiones intactas.

### 3.3 Downed/revive sin doble transformación
En modo sprite el derribo del player NO aplica la rotación/tinte procedural
(lo representa la anim `downed` vía señal); al revivir se restaura SIEMPRE el
procedural aunque esté oculto, para que un cambio de modo posterior no
herede la pose tumbada. Compañeros: mismo mecanismo por señales + guard.

### 3.4 Luz pintada y mirroring
Validador: error si un perfil ACTIVADO exige oeste real
(`require_unique_west_frames`) y no existen animaciones `*_w/*_nw/*_sw`;
aviso si el espejo está permitido con `preserve_painted_light_direction`.
Ambos personajes P0 se declaran ASIMÉTRICOS en los prompts (bufanda del gato
a la izquierda, oreja mordida y herida del perro a la izquierda): por defecto
exigirán oeste real o rediseño centrado (decisión en B2, registrada en el
manifiesto: qué direcciones son reales y cuáles espejadas).

### 3.5 Presupuesto de memoria revisado
Dos presupuestos en `ART_P0_PERFORMANCE_REPORT.md`: PILOTO ~30 frames /
~5.6 MB VRAM (validar estilo sin coste) y FINAL ~42 MB (confirma la
estimación de E2; +60 % si se exige oeste real). Línea base de CPU medida:
2600 frames de MainLevel headless en ~20.4 s.

## Estados artísticos (sección 17)

`CharacterVisualProfile.asset_status`: TEST_ONLY / PLACEHOLDER / PILOT_ART /
FINAL_CANDIDATE / APPROVED_FINAL. `can_activate_in_game()`:
- APPROVED_FINAL → activable en producción.
- FINAL_CANDIDATE → solo builds de desarrollo (`OS.is_debug_build()`).
- Resto → jamás en juego (solo Preview/FORCE_SPRITE).
El controlador (modo AUTO) y el validador aplican la misma regla; el
validador además marca error si un perfil activado tiene estado no
publicable y avisa cuando un FINAL_CANDIDATE quedaría procedural en el
export de producción. El perfil de prueba quedó marcado `TEST_ONLY`.

## Recepción y chequeo automático

- `_incoming/characters/{players/leader_cat, enemies/zombie_dog_normal}/`
  con README y flujo `raw/ → clean/ → aligned/`.
- `scripts/visual/tools/incoming_check.gd` (headless): valida extensión,
  carga, alfa real, esquinas opacas (fondo sin limpiar), halo blanco
  aproximado, convención de nombres (`<id>_<anim>_<dir>_v##_f##.png`),
  carpeta de estado y dimensiones (múltiplos de celda, ≤2048, estricto en
  `aligned/`). La consistencia de diseño sigue siendo revisión humana.

## Preview ampliado

Tinte ambiental real por bioma (simula el CanvasModulate del mapa sobre el
personaje), zooms x3 (inspección) / x1.0 (juego) / x1.35 (coop), botón
"Flash daño" y checkbox "Procedural" que instancia la escena real del
personaje congelada al lado (comparación PROCEDURAL | SPRITE por categoría).

## Estado del Gate B

**B0 en espera de la primera entrega.** Prompts completos por subgate en
`AI_ART_P0_PROMPTS.md` (hojas maestras → 5 poses piloto por personaje →
mini animación de ~30 frames → paquete completo). El procedural sigue siendo
el arte del juego, sin cambios de gameplay, colisiones ni rendimiento.

## Pendiente al recibir arte

1. `incoming_check` + checklist manual → manifiesto (RECEIVED → ...).
2. B0/B1: aprobar diseño en Preview (3 biomas, 2 zooms, flash, comparación).
3. B2: mini animación, medir memoria piloto, decidir oeste real vs espejo.
4. B3-B6: paquete completo, perfiles reales (PILOT_ART → FINAL_CANDIDATE →
   APPROVED_FINAL), QA solo/coop/hordas MANUAL y reporte de rendimiento.
