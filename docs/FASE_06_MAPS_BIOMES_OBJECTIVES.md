# FASE 06 — Mapas, biomas y objetivos de partida

Agrega un sistema de **mapas/biomas** con identidad visual, modificadores de
dificultad, eventos propios y **objetivos de partida** con condición de victoria.
Todo montado **encima** de lo existente, de forma modular y data-driven; no se rehízo
combate, armas, compañeros ni jefes.

> Motor: Godot 4.7 · GDScript · Escena principal: `scenes/levels/MainLevel.tscn`
> No incluye: Steam, guardado, logros, tienda, multijugador, menú completo, arte/audio final.

---

## 1. Qué se implementó

- **MapData**: recurso data-driven con identidad visual, modificadores, eventos y objetivos.
- **MapManager**: carga el mapa activo y lo reparte a todos los sistemas; controla objetivos y victoria.
- **MapDecoration**: decoración procedural por bioma (sin assets externos).
- **3 mapas**: Barrio Gatuno, Parque Abandonado, Callejón Industrial.
- **Objetivos** (combinables): sobrevivir, derrotar jefe, rescatar gatos, derrotar mini-jefes.
- **Victoria** "Zona asegurada" con resumen + reinicio con R.
- **Selector debug** F1/F2/F3 para cambiar de mapa con reinicio limpio.
- Integración con dificultad, rescates, eventos/jefes vía modificadores del mapa.

---

## 2. MapData (`scripts/maps/map_data.gd`)

Resource con: `id`, `display_name`, `description`, identidad visual
(`background_color`, `grid_color`, `accent_color`, `biome`), modificadores
(`difficulty_modifier`, `runner_probability_modifier`, `enemy_health_modifier`,
`enemy_speed_modifier`, `rescue_spawn_modifier`, `rescue_distance_bonus`), eventos
(`boss_spawn_time`, `miniboss_times`, `boss_data` opcional) y objetivos
(`duration_seconds`, `survive_seconds`, `require_defeat_boss`, `rescue_cats_required`,
`defeat_minibosses_required`, `objective_description`).

Recursos creados en `data/maps/`: `neighborhood_map.tres`, `park_map.tres`,
`industrial_alley_map.tres`.

---

## 3. MapManager (`scripts/maps/map_manager.gd`)

Nodo en MainLevel. En `_ready` resuelve el mapa activo y, **de forma diferida** (para
que todos los sistemas hayan corrido su `_ready`), aplica:

- **Fondo**: empuja la paleta del mapa al `WorldGrid` (base + líneas) y configura
  `MapDecoration` con el bioma.
- **EnemySpawner**: `set_map_modifiers(difficulty, runner, health, speed)`.
- **RescueSpawner**: `set_map_modifiers(interval_mult, distance_bonus)`.
- **WaveEventManager**: `apply_map_schedule(boss_time, miniboss_times)`.
- **BossSpawner**: si el mapa define `boss_data`, lo usa como jefe por defecto.
- **HUD**: nombre del mapa + objetivo con progreso.

Luego controla los **objetivos** (tiempo propio, contadores de jefes/mini-jefes vía
señales del BossSpawner, gatos vía CompanionManager) y dispara la **victoria**.

---

## 4. Cómo agregar un nuevo mapa

1. Duplica un `.tres` de `data/maps/` y ajusta sus campos (visual, modificadores,
   eventos, objetivos).
2. Asígnalo a `current_map_data` del nodo **MapManager** (o agrégalo a `map_pool`
   para que sea seleccionable con F1/F2/F3).
3. Si quieres una decoración nueva, añade un `match` en `map_decoration.gd` con un
   nuevo valor de `biome`. No hace falta tocar nada más.

---

## 5. Cómo editar duración / objetivos / colores

- **Duración / objetivos**: campos `survive_seconds`, `require_defeat_boss`,
  `rescue_cats_required`, `defeat_minibosses_required` del `.tres`.
- **Colores / fondo**: `background_color`, `grid_color`, `accent_color`, `biome`.
- **Texto del objetivo**: se arma solo desde los campos; `objective_description`
  permite añadir una línea extra.

---

## 6. Decoración por bioma (`scripts/maps/map_decoration.gd`)

Nodo `MapDecoration` que dibuja props **procedurales** (Polygon2D/draw_*) por celda,
deterministas (un hash de la celda decide presencia/offset/tamaño), por lo que son
estables al moverse y **no bloquean el movimiento**:

- **neighborhood**: cajas/basura urbana + marcas de calle.
- **park**: arbustos (círculos verdes) + manchas de pasto/sendero.
- **industrial**: contenedores con franja de peligro + tuberías.

El fondo de cuadrícula (`WorldGrid`/`background_grid.gd`) se reutiliza y solo se le
cambia la paleta desde el MapManager (refactor cuidadoso, sin romper el existente).

---

## 7. Objetivos y victoria

Tipos soportados (combinables por mapa): **SURVIVE_TIME**, **DEFEAT_BOSS**,
**RESCUE_CATS**, **DEFEAT_MINIBOSSES**. El HUD muestra el objetivo con progreso:

```
Barrio Gatuno
Sobrevive 03:21
Derrota al jefe
```

Al cumplirse todos: se **pausa** la partida y aparece el panel **"ZONA ASEGURADA"**
con resumen (tiempo, enemigos, gatos, armas, jefes, mini-jefes). **R** reinicia.

| Mapa | Objetivos |
|------|-----------|
| Barrio Gatuno | Sobrevivir 10:00 + derrotar al jefe (Rottweiler Alfa, 600s) |
| Parque Abandonado | Sobrevivir 12:00 + rescatar 2 gatos |
| Callejón Industrial | Sobrevivir 15:00 + derrotar 2 mini-jefes |

---

## 8. Integración con dificultad / rescates / eventos

- **Dificultad**: el mapa multiplica el `difficulty_score` y la vida/velocidad de
  enemigos, y pondera la aparición de runners.
- **Rescates**: el mapa ajusta la frecuencia (`rescue_spawn_modifier`) y la distancia
  (`rescue_distance_bonus`). Parque = más frecuentes; Industrial = más lejos/menos.
- **Eventos/jefes**: el WaveEventManager usa los `miniboss_times` y `boss_spawn_time`
  del mapa. Las hordas/runners periódicas siguen siendo globales (ajustables en el
  WaveEventManager).

### Jefes futuros (preparado, no implementado)

- Parque → **Dóberman Salvaje** (rápido). Hoy el objetivo del parque no exige jefe.
- Industrial → **Bulldog Blindado** (tanque). Hoy exige 2 mini-jefes, no jefe.

Para añadirlos: crear un `BossData`, asignarlo a `boss_data` del mapa y poner
`require_defeat_boss = true` + `boss_spawn_time` deseado.

---

## 9. Cómo cambiar el mapa activo

- **Opción A (por defecto)**: campo `current_map_data` del nodo **MapManager** en
  `MainLevel.tscn`.
- **Opción B (debug en juego)**: teclas **F1** (Barrio), **F2** (Parque), **F3**
  (Industrial). Guardan el índice en una `static var` que sobrevive al reinicio y
  recargan la escena, dejando todo limpio.

---

## 10. Limpieza y reinicio (R)

Todo (decoración, objetivos, eventos, jefes, enemigos, compañeros, armas, HUD) vive
en `MainLevel` o se reconstruye en `_ready`. R llama `reload_current_scene()`, que
libera la escena completa: no queda decoración duplicada, ni objetivo viejo, ni panel
de victoria anterior. La victoria también despausa antes de recargar. El cambio de
mapa (F1/F2/F3) usa el mismo reinicio limpio.

---

## 11. Cómo probar cada mapa

Ejecuta `MainLevel.tscn` y pulsa **F1/F2/F3**, o para acelerar activa
`debug_spawn_boss_early` / `debug_spawn_miniboss_early` en el **WaveEventManager**:

- **F1 Barrio Gatuno**: fondo gris-azulado, cajas urbanas, objetivo jefe.
- **F2 Parque Abandonado**: fondo verde, arbustos, más runners y rescates, objetivo 2 gatos.
- **F3 Callejón Industrial**: fondo gris-amarillo, contenedores/tuberías, enemigos con
  más vida, objetivo 2 mini-jefes.

---

## 12. Riesgos conocidos

- Validado por estructura + **harness headless** (carga de mapa, modificadores,
  bioma, victoria, cambio de mapa). Falta playtest jugado para afinar el *feel*.
- Las hordas/runners periódicas no se leen del MapData todavía (son globales del
  WaveEventManager); el `event_schedule` del mapa quedó como `miniboss_times` +
  `boss_spawn_time`. Ampliable.
- La decoración procedural usa un `RandomNumberGenerator` por celda en `_draw`; con
  vistas muy grandes podría notarse coste. Hoy es despreciable (decenas de celdas).
- No hay menú de selección de mapa (intencional): solo `current_map_data` + F1/F2/F3.
- Los dos jefes nuevos (Dóberman, Bulldog Blindado) están **preparados pero no
  implementados**; los mapas Parque/Industrial no los exigen para ganar.

---

## 13. Pendiente para Fase 06.5 / Fase 07

- Jefes propios de Parque e Industrial (BossData + activarlos en el MapData).
- Carta especial de recompensa al ganar / progresión entre mapas (bucle de zonas).
- `event_schedule` completo por mapa (hordas/runners propios de cada bioma).
- Decoración con colisión opcional (cobertura) y props más variados.
- Pantalla/menú de selección de mapa real (hoy es debug).
- Guardado del mapa desbloqueado (cuando llegue persistencia).
