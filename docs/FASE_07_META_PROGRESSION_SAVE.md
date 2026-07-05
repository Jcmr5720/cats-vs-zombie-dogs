# FASE 07 — Meta-progresión, monedas, desbloqueos y guardado local

Convierte el juego en un **roguelite básico**: cada partida (ganada o perdida) otorga
**Sardinas** que se gastan en **mejoras permanentes** guardadas en disco. Todo montado
**encima** de lo existente; no se rehízo combate, armas, compañeros, jefes ni mapas.

> Motor: Godot 4.7 · GDScript · Escena principal: `scenes/levels/MainLevel.tscn`
> No incluye: Steam, Cloud Save, logros, tienda real, microtransacciones, multijugador.

---

## 1. Qué se implementó

- **Sardinas**: moneda que se gana al terminar cualquier partida.
- **SaveManager** (autoload): guardado local en JSON, robusto ante corrupción.
- **RunSummary**: estructura de resumen de partida (victoria o derrota).
- **MetaProgression** (autoload): 7 mejoras permanentes comprables y aplicables.
- **Panel de mejoras** (tecla **M** al terminar la partida).
- **Resumen de fin de partida** con Sardinas ganadas/totales (victoria y derrota).
- **Desbloqueo simple de mapas** (asegurar uno desbloquea el siguiente).
- Integración con dificultad (las mejoras permanentes suben un poco la presión).

---

## 2. SaveManager (`scripts/save/save_manager.gd`, autoload)

Autoload **`SaveManager`**. Carga al iniciar, crea save nuevo si no existe y es
**robusto**: si el archivo está corrupto, lo respalda en `.bak` y arranca uno limpio
sin crashear; cualquier campo faltante se rellena con su valor por defecto
(`SaveData.sanitize`).

- **Dónde se guarda**: `user://cats_vs_zombie_dogs_save.json`
  - Windows: `%APPDATA%/Godot/app_userdata/CatsVsZombieDogs/cats_vs_zombie_dogs_save.json`
- **Qué guarda**: `total_sardines`, `total_runs`, `total_victories`,
  `best_time_by_map`, `unlocked_maps`, `permanent_upgrades`, `unlocked_features`,
  `first_time_played`, `last_played_at`, `version`.
- **Cuándo guarda**: al terminar partida (`record_run`) y al comprar una mejora.

### Resetear el save en desarrollo

- Código: `SaveManager.reset_save()` (borra progreso y crea uno limpio).
- Manual: borra el archivo `cats_vs_zombie_dogs_save.json` de la carpeta de arriba.
- No hay tecla de reset accidental: es deliberado para no perder progreso por error.

---

## 3. Sardinas — fórmula

Calculada en `MetaProgression.compute_sardines(summary)`:

```text
sardinas = tiempo_segundos / 10
         + enemigos * 0.2
         + gatos_rescatados * 8
         + mini_jefes * 15
         + jefes * 40
         + bonus_victoria        (solo si se asegura la zona)

bonus_victoria: Barrio 50 · Parque 70 · Callejón 90
sardinas *= (1 + mochila_de_sardinas)   ← mejora permanente
resultado = max(1, round(...))          ← nunca cero
```

Morir rápido da poco (mínimo 1); sobrevivir y derrotar jefes da mucho más.

---

## 4. Mejoras permanentes

`PermanentUpgradeData` (`scripts/meta/permanent_upgrade_data.gd`) + recursos en
`data/permanent_upgrades/`. Gestionadas por **`MetaProgression`** (autoload).

| Mejora | Efecto / nivel | Máx | Tipo |
|--------|----------------|-----|------|
| Garras Afiladas | +3% daño inicial | 10 | `player_damage_pct` |
| Patas Ligeras | +2% velocidad inicial | 8 | `player_speed_pct` |
| Nueve Vidas | +5 vida máxima inicial | 10 | `max_health_flat` |
| Instinto Felino | +3% XP ganada | 8 | `xp_pct` |
| Mochila de Sardinas | +5% Sardinas finales | 10 | `sardine_pct` |
| Llamado de la Colonia | primer rescate antes | 5 | `first_rescue_seconds` |
| Mecánica Gatuna | −2% cooldown inicial de armas | 5 | `weapon_cooldown_pct` |

Costo del siguiente nivel: `round(base_cost * cost_growth ^ nivel_actual)`.

### Cómo agregar una nueva mejora

1. Duplica un `.tres` de `data/permanent_upgrades/` y ajusta `id`, textos, `max_level`,
   `base_cost`, `cost_growth`, `effect_type`, `effect_value_per_level`, color.
2. Añade su ruta a `UPGRADE_PATHS` en `permanent_upgrade_manager.gd`.
3. Si el `effect_type` es nuevo, léelo donde corresponda (Player / WeaponManager /
   RescueSpawner / cálculo de recompensa). Los 7 tipos actuales ya están conectados.

---

## 5. Aplicación de mejoras al iniciar partida

Al cargar la escena, cada sistema lee del autoload `MetaProgression`:

- **Player** (`_apply_permanent_upgrades` en `_ready`): +vida máxima, +velocidad,
  +daño inicial (vía WeaponManager), +XP, −cooldown inicial de armas.
- **WeaponManager**: `set_permanent_damage_mult` / `set_permanent_cooldown_mult`.
- **RescueSpawner**: reduce el tiempo del **primer** rescate (Llamado de la Colonia).
- **Recompensa**: Mochila de Sardinas multiplica las Sardinas finales.

Están acotadas (caps de vida/velocidad del jugador, cooldown mínimo de armas) para
ayudar sin romper el juego.

---

## 6. Integración con dificultad

El poder permanente añade presión para que las mejoras no trivialicen el reto:

```text
permanent_power_score = suma de niveles de todas las mejoras
difficulty_score += permanent_power_score * 0.15
```

(en `enemy_spawner.gd`, leído una vez al iniciar).

---

## 7. Desbloqueo de mapas

`unlocked_maps` en el save. Reglas:

- **Barrio Gatuno**: desbloqueado desde el inicio.
- **Parque Abandonado**: al asegurar Barrio Gatuno una vez.
- **Callejón Industrial**: al asegurar Parque Abandonado una vez.

El selector debug **F1/F2/F3** respeta el bloqueo (si el mapa no está desbloqueado,
muestra "Mapa bloqueado" y no cambia). El selector real con menú queda para Fase 08.

---

## 8. Fin de partida y panel de mejoras

El **MapManager** orquesta el fin de partida (victoria **y** derrota): construye el
`RunSummary`, calcula y registra las Sardinas, desbloquea el siguiente mapa si ganó,
pausa y muestra el panel:

- **Victoria**: panel "ZONA ASEGURADA" + resumen + Sardinas.
- **Derrota**: panel "COLONIA PERDIDA" + resumen + Sardinas.

Controles tras terminar:
- **R**: reinicia la partida (no borra progreso ni Sardinas).
- **M**: abre/cierra el **panel de mejoras permanentes**
  (`scenes/ui/MetaUpgradePanel.tscn`): muestra Sardinas, nivel, costo y botón Comprar.

---

## 9. Cómo probar (resumen)

| Prueba | Cómo |
|--------|------|
| Pocas Sardinas | Morir rápido → resumen con +1..pocas. |
| Más Sardinas | Sobrevivir/derrotar jefes → más Sardinas. |
| Bonus victoria | Asegurar un mapa → +50/70/90 según mapa. |
| Comprar mejora | Tras terminar, **M**, comprar si alcanza. |
| Aplica al reiniciar | **R**, ver más vida/daño/velocidad inicial. |
| Persistencia | Cerrar y abrir Godot → Sardinas/mejoras siguen. |
| Sin alcanzar | Intentar comprar sin Sardinas → bloqueado. |
| R sin borrar | **R** no borra el save. |
| Reset debug | `SaveManager.reset_save()` o borrar el .json. |

---

## 10. Errores y seguridad

- Save inexistente → se crea uno nuevo.
- Save corrupto → backup `.bak` + save nuevo, sin crashear.
- Campo/mejora faltante → se asume nivel 0 / valor por defecto.
- Compra con guardado fallido → se **revierte** (no se pierden Sardinas).

---

## 11. Riesgos conocidos

- Validado por estructura + **harness headless** (compra, aplicación tras reload,
  persistencia entre procesos, victoria y derrota). Falta playtest jugado para afinar
  costos/curva económica.
- La economía es lineal y simple a propósito; con muchos niveles podría hacerse fácil.
  La presión por `permanent_power_score` lo compensa parcialmente.
- No hay menú principal: el panel de mejoras solo se abre al terminar la partida (M).
- El selector de mapas sigue siendo debug (F1/F2/F3) respetando el desbloqueo.

---

## 12. Pendiente para Fase 07.5 / Fase 08

- **Menú principal / selección de mapa** real (hoy es debug) con mapas bloqueados.
- Tienda/economía más rica (rerolls, mejoras de armas permanentes, categorías).
- Más mejoras permanentes y un árbol/categorías visibles en el panel.
- Estadísticas de perfil (mejores tiempos por mapa ya se guardan, falta mostrarlas).
- Preparar (aún sin implementar) Steam/Cloud cuando llegue la fase de publicación.
