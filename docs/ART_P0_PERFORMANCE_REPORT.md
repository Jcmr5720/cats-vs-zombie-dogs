# ART P0 PERFORMANCE REPORT

Presupuesto y mediciones del LOTE P0. Se completará con cifras reales de GPU
cuando exista arte activable; por ahora contiene la línea base y el plan.

## Línea base (sin sprites, arte procedural — medida en esta etapa)

- Headless, MainLevel, 2600 frames de gameplay (spawns, muertes, XP):
  **~20.4 s** en la máquina de desarrollo (≈127 fps de lógica). Es la
  referencia para detectar regresiones de CPU al activar sprites.
- FPS de render: medir manualmente con `show_fps` (Opciones → Vídeo) y el
  overlay F8 (PerformanceManager) — el headless no ejercita GPU.

## Presupuesto PILOTO (GATE B2)

| Concepto | Gato | Perro | Total |
|---|---|---|---|
| Frames | ~14 (idle 4 + run 6 + attack 4) | ~16 (run 6 + attack 4 + death 6) | 30 |
| Hoja | 1×1024×512 | 1×1024×512 | 2 |
| Disco (PNG) | < 1 MB | < 1 MB | < 2 MB |
| VRAM (RGBA8 + mipmaps) | ~2.8 MB | ~2.8 MB | **~5.6 MB** |

Trivial: el piloto NO requiere optimización; sirve para validar estilo antes
de producir cientos de frames.

## Presupuesto FINAL estimado (GATE B3, 5 direcciones + espejo)

| Concepto | Gato (~175 frames) | Perro (~125 frames) |
|---|---|---|
| Atlas 2048×2048 (celdas 128) | 1 (256 celdas) | 1 |
| Disco | ~3-6 MB | ~2-5 MB |
| VRAM c/mipmaps | ~21 MB | ~21 MB |
| **Total P0** | | **~42 MB** (confirma la estimación de E2) |

Si se exige oeste real (personajes asimétricos): +60 % de frames del lado
oeste → puede requerir 2 atlas por personaje (~+21 MB c/u). Decisión en B2.

## Reglas de medición al activar (GATE B6)

Medir y anotar aquí: FPS sin sprites / con Player sprite / 20 / 50 enemigos
sprite / horda máxima / coop, en calidad baja-media-alta y en los 3 mapas;
memoria de video antes/después (`Performance.RENDER_VIDEO_MEM_USED` vía F8);
tiempo de entrada a MainLevel. **Un solo SpriteFrames compartido por tipo**
(el `.tres` del perfil se comparte entre instancias — Godot no duplica la
textura por enemigo). Si algo excede el presupuesto: reducir frames, separar
atlas, revisar compresión/mipmaps antes de tocar arte.

## Estado

- [x] Línea base registrada.
- [ ] Piloto medido (esperando arte B2).
- [ ] Final medido (esperando arte B3).
