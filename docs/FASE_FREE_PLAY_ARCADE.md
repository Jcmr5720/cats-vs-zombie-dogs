# Fase Partida libre arcade — Separación Historia/Libre + Puntuación y récords

Separa la **progresión** del **reto**: las mejoras permanentes y el Refugio ahora
afectan **solo al Modo Historia**. Partida libre pasa a ser un modo **arcade puro y
competitivo** (estilo "jugar con amigos" de Crash): mismas condiciones para todos, **sin
Sardinas** como recompensa, y con **puntuación + récords locales** por mapa y dificultad
como motivación.

Regla de detección (ya existente): `GameFlow.is_story_run()` = `story_chapter != null`.
Partida libre = no historia (incluye el lanzamiento directo de MainLevel con F6/tests).

---

## Parte A — Mejoras permanentes y Refugio: solo en Historia

Cada consumidor de bonos aplica un patrón simple: si **no** es Historia, no lee
`MetaProgression`/`Shelter` (equivale a que no existan). Se añadió un helper local
`_is_story_run()` en cada archivo. **No** se tocaron los providers ni los menús de
Mejoras/Refugio (siguen mostrando y permitiendo comprar; la economía sigue viva).

Puntos gateados:

| Bono | Archivo | Qué se salta en Partida libre |
|---|---|---|
| Vida/velocidad/XP/daño/cooldown/pickup/armadura del jugador | `scripts/player/player.gd` `_apply_permanent_upgrades()` | `return` temprano (todo queda en su valor base) |
| Corazón de León + vida/daño/médico del Refugio (compañeros) | `scripts/companions/companion_manager.gd` `_ready()` | bloque bajo `if _is_story_run()` |
| Reducción del primer rescate (meta + Refugio) | `scripts/companions/rescue_spawner.gd` `_ready()` | bloque bajo `if _is_story_run()` |
| Presión extra por poder de meta/refugio | `scripts/enemies/enemy_spawner.gd` `_ready()` | `_permanent_power`/`_shelter_power` quedan 0 |
| +rareza de cartas del Refugio | `scripts/systems/upgrade_manager.gd` `_shelter_rarity_bonus()` | devuelve 0.0 |
| Sardinas (base + Mochila + Almacén del Refugio) | `scripts/maps/map_manager.gd` `_finish_run()` | rama libre no calcula Sardinas (ver Parte B) |

**Decisión:** las **misiones** (`mission_manager.gd`) siguen dando Sardinas aunque se
completen en libre — son logros únicos, no farmeables por run, y varias solo pueden
lograrse en libre (Plaga 3+/5). Los **desbloqueos** de libre (mapas y Plagas) y el
registro de estadísticas/mejor tiempo (`record_run`) siguen igual.

## Parte B — Puntuación y récords en Partida libre

### Cálculo (`scripts/systems/free_play_score.gd`, nuevo)
`RefCounted` con estáticos (estilo `StoryCampaign`). Constantes editables arriba:

```
puntos = kills*10 + nivel*50 + gatos*100 + mini_jefes*150 + jefes*400
       + floor(tiempo)*2 + (victoria ? 500 : 0)
total  = round(puntos * reward_dificultad * (1 + 0.5*(plaga-1)))
```

`reward_dificultad` = 1.0/1.3/1.7/2.2 (Fácil..Extremo, misma tabla que Historia).
Récord por **mapa + dificultad**: `best_score_<map>_d<tier>` vía el `get_value/set_value`
genérico del SaveManager (sin cambios de esquema del save).

### Fin de partida (`map_manager.gd` `_finish_run()`)
- **Historia:** sin cambios (Sardinas, tiers, first-clear, desbloqueos).
- **Libre:** `sardines_earned = 0`; calcula `score`, compara con el récord guardado,
  lo persiste si lo supera y marca `is_new_record`. Se añaden a `RunSummary`
  (`run_summary.gd`) los campos `score` (-1 = no aplica/Historia), `score_breakdown`,
  `best_score`, `is_new_record`.

### UI
- **Resumen (`hud.gd`):** en libre la primera tarjeta es **"Puntuación"** (con ★ si es
  récord), el subtítulo añade **"¡NUEVO RÉCORD!"**, y "Detalles" muestra la **semilla**
  (para rejugar/competir en igualdad), el desglose de puntuación y el mejor histórico.
- **Selector de mapas (`map_select_menu.gd`):** cada tarjeta muestra **"Récord (dif): X"**
  de la dificultad seleccionada (se refresca al cambiar el segmentado). Bajo la barra de
  ajustes, una línea aclara la identidad: *"Partida libre: sin bonos de mejoras ni
  refugio — puntuación pura para competir"*.
- **Estadísticas (`stats_menu.gd`):** cada mapa muestra su **mejor puntuación** (máximo
  entre las 4 dificultades, con el nombre del tier).

---

## Cómo probar

1. **Separación:** en Partida libre, el jugador arranca con stats base aunque tengas
   mejoras permanentes/refugio comprados; en Historia esos bonos SÍ aplican.
2. **Sin Sardinas en libre:** al terminar una partida libre, el resumen muestra
   Puntuación (no Sardinas) y tu total de Sardinas no cambia por jugar libre.
3. **Récord:** gana/pierde en un mapa+dificultad; si superas tu marca aparece
   "¡NUEVO RÉCORD!" y queda guardado (visible en el selector y en Estadísticas).
4. **Competir:** comparte la **semilla** que aparece en Detalles para que otro juegue el
   mismo mundo en la misma dificultad y comparen puntuación.

### Validación headless (Godot 4.7)
- Partida libre: `is_story_run=false`, `player.max_health=100`, `_xp_multiplier=1.0`,
  `enemy_spawner._permanent_power=0`/`_shelter_power=0`; `_finish_run(true)` →
  `sardines_earned=0`, puntuación calculada (p.ej. 938) y récord persistido.
- `test_gameplay_smoke`, `test_shelter` y `test_story` pasan; MainLevel solo y los menús
  (MapSelect/Stats) cargan sin errores.

---

## Equilibrio de motivación

- **Historia** = progresión: gana Sardinas, mejora tu colonia (mejoras permanentes +
  Refugio), avanza la campaña. Los bonos hacen las runs cada vez más fuertes.
- **Partida libre** = maestría/competición: sin bonos, todos parten igual; el objetivo
  es **maximizar tu puntuación** y batir récords (tuyos o de un amigo) en el mismo mapa,
  dificultad y —si quieren— la misma semilla. El regulador de dificultad
  (Fácil..Extremo) y el Nivel de Plaga multiplican la puntuación, premiando el reto.
