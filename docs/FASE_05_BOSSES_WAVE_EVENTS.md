# FASE 05 — Jefes, mini-jefes y eventos especiales de oleada

Agrega **estructura temporal** a la partida: hordas, manadas de runners, mini-jefes
y un jefe principal con barra de vida, fases y patrones. Todo montado **encima** del
sistema actual de forma modular; no se rehízo armas, compañeros, revive ni reinicio.

> Motor: Godot 4.7 · GDScript · Escena principal: `scenes/levels/MainLevel.tscn`
> No incluye: Steam, menú, guardado, logros, audio, arte final, tienda, multijugador.

---

## 1. Qué se implementó

- **WaveEventManager**: reloj de partida que dispara eventos por tiempo.
- **Eventos**: Horda de zombis, Manada de runners, Mini-jefe, Jefe principal.
- **BossData**: recurso data-driven para jefes/mini-jefes (como EnemyData).
- **BossSpawner**: instancia y escala jefes; conecta la barra de vida del HUD.
- **Mini-jefe** "Bulldog Bruto Zombi": grande, lento, pega fuerte, empuja, mucha XP.
- **Jefe principal** "Rottweiler Alfa Zombi": barra grande, 3 fases, 3 patrones.
- **Barra de vida de jefe** en el HUD + barra pequeña sobre el mini-jefe.
- **Empuje al jugador** (`apply_knockback`) para embestidas/contactos.
- **Recompensas**: ráfaga de orbes de XP al morir + mensajes de evento.

---

## 2. WaveEventManager (`scripts/systems/wave_event_manager.gd`)

Nodo en MainLevel. Lleva su **propio reloj** (`_elapsed`) que avanza solo cuando el
juego no está en pausa (las cartas de upgrade también pausan los eventos).

En `_ready` construye una lista de `WaveEventData` desde sus `@export` y, cada frame,
dispara los eventos cuyo `time` ya llegó. Los eventos con `repeat_interval > 0` se
reprograman solos.

No spawnea nada directamente: delega en **EnemySpawner** (hordas/runners) y en
**BossSpawner** (jefes). `WaveEventData` (`scripts/systems/wave_event_data.gd`) es un
Resource simple con `type`, `time`, `duration`, `intensity`, `label`, `repeat_interval`.

Tipos: `horde`, `runner_pack`, `miniboss`, `boss`, `xp_bonus` (reservado/expandible).

### Línea temporal por defecto (editable)

| Evento | Tiempo | Repite | Efecto |
|--------|--------|--------|--------|
| Horda | 60 s | cada 90 s | +spawn 20 s, "¡Horda entrante!" |
| Manada de runners | 120 s | cada 120 s | +runners 15 s, "¡Manada rápida!" |
| Mini-jefe #1 | 180 s | — | Bulldog Bruto |
| Mini-jefe #2 | 420 s | — | Bulldog Bruto |
| Jefe principal | 600 s | — | Rottweiler Alfa |

---

## 3. BossData (`scripts/bosses/boss_data.gd`)

Resource con: `id`, `display_name`, `boss_type` (`boss`/`miniboss`), `max_health`,
`move_speed`, `contact_damage`, `attack_damage`, `attack_cooldown`, `attack_range`,
`knockback`, `xp_reward`, `visual_color`, `accent_color`, `visual_scale`,
`phase_thresholds`, `spawn_time`, `difficulty_multiplier`.

Recursos creados:
- `data/bosses/bulldog_brute.tres` (mini-jefe, completo).
- `data/bosses/rottweiler_charger.tres` (jefe principal, completo).

---

## 4. BossSpawner (`scripts/bosses/boss_spawner.gd`)

Nodo en MainLevel. Métodos `spawn_miniboss(data=null)` y `spawn_boss(data=null)`
(usan `default_*_data` si no se pasa nada). Escala la vida con la dificultad actual
(lee `EnemySpawner.get_difficulty_score()`), evita **jefe duplicado** con
`_active_boss`, conecta la vida del jefe a la barra del HUD y muestra mensajes de
aparición/derrota con shake y destello.

---

## 5. Mini-jefes (`scripts/bosses/mini_boss.gd` + `scenes/bosses/MiniBoss.tscn`)

"Bulldog Bruto Zombi". Persigue al jugador, **pega fuerte por contacto y lo empuja**
(`apply_knockback`). Tiene **barra de vida pequeña propia** encima, flash y número de
daño al recibir golpes, y al morir suelta **mucha XP** (4 orbes) con destello/shake y
mensaje "… derrotado". Está en los grupos `enemies` (para recibir daño de todas las
armas) y `miniboss` (para limpieza). No tiene fases: su rol es ser un elite que se nota.

Aparece ~min 3 y ~min 7 (ajustable). Su vida se integra con `difficulty_score`.

---

## 6. Jefe principal (`scripts/bosses/boss.gd` + `scenes/bosses/Boss.tscn`)

"Rottweiler Alfa Zombi". Silueta grande y clara (cuerpo y cabeza grandes, ojos
brillantes que se intensifican por fase, **aura** de color, colmillos). Barra de vida
**grande** en el HUD con su nombre.

### Patrones (máquina de estados)

1. **Persecución** (CHASE): avanza lento hacia el jugador, daño por contacto.
2. **Embestida** (WINDUP → CHARGE → RECOVER): muestra un **telégrafo** (flecha
   pulsante) apuntando la dirección durante `windup_time`, luego **carga rápido**
   (`charge_speed`) un instante; si golpea hace `attack_damage` + knockback. Tiene
   recuperación y cooldown.
3. **Invocación** (SUMMON): cada cierto tiempo invoca un grupo pequeño de perros
   (con destello/shake), con **tope** de invocados vivos (`MAX_SUMMONED = 14`).

### Fases (por `phase_thresholds = [0.6, 0.3]`)

- **Fase 1** (>60% vida): persecución + contacto, embestida ocasional.
- **Fase 2** (≤60%): embestida **más frecuente** (cooldown ×0.7).
- **Fase 3** (≤30%): alterna embestida e **invocación** (cooldown ×0.5).

El cambio de fase dispara destello + shake.

---

## 7. Integración con dificultad

`boss.configure(data, difficulty_score)`:

```text
boss_health = clamp(base_health * (1 + max(0, difficulty_score) * difficulty_multiplier),
                    base_health, MAX_HEALTH_CAP)
```

- Jefe: `difficulty_multiplier = 0.08`, tope `MAX_HEALTH_CAP = 9000`.
- Mini-jefe: `0.06`, tope `4000`.

Así, si el jugador es fuerte el jefe aguanta y presiona; si es débil, nunca se vuelve
imposible (tope + base como mínimo). El `difficulty_score` ya considera tiempo, nivel,
kills, upgrades, compañeros **y armas/niveles de arma** (Fase 04.5).

---

## 8. Integración con armas

Los jefes viven en el grupo `enemies` con `collision_layer = 2`, igual que los
enemigos, así que **todas las armas los dañan sin código especial**: proyectiles y
explosiones (mask 2 → body_entered), láser, orbitales, áreas temporales y los
proyectiles de compañeros (todos iteran el grupo `enemies`). Reaccionan con flash,
número de daño y actualización de barra. El daño de área no se multiplica de forma
absurda: el orbital ya tiene cooldown por enemigo y las zonas dañan por tics.

---

## 9. Integración con compañeros

- Los compañeros **atacan al jefe** (lo buscan por el grupo `enemies`).
- El jefe **prioriza al jugador** para moverse, pero **daña compañeros** que estén en
  su rango de contacto/embestida.
- El médico sigue curando; el revive, RescueSpawner y CompanionManager no se tocaron.
- Compañeros derribados no aportan sinergias (igual que antes).

---

## 10. Debug / prueba rápida

En el nodo **WaveEventManager** (inspector) o editando los `@export`:

- `debug_spawn_boss_early = true` → el jefe aparece en `debug_boss_spawn_time`
  (por defecto **20 s**) en vez de a los 600 s.
- `debug_spawn_miniboss_early = true` → aparece un mini-jefe a `debug_miniboss_spawn_time`
  (por defecto **12 s**).

Por defecto ambos están en `false`.

---

## 11. Parámetros editables

**Eventos** (`WaveEventManager`): `horde_first_time`, `horde_repeat`,
`horde_duration`, `horde_intensity`, `runner_first_time`, `runner_repeat`,
`runner_duration`, `miniboss_first_time`, `miniboss_second_time`, `boss_time`.

**EnemySpawner** (nuevos): `horde_max_enemies_bonus` y, en runtime,
`start_horde(duration, intensity)` / `start_runner_pack(duration, weight_bonus)`.

**Mini-jefe** (`BossData` `bulldog_brute.tres`): `max_health`, `move_speed`,
`contact_damage`, `knockback`, `xp_reward`, `visual_scale`, `difficulty_multiplier`.

**Jefe** (`BossData` `rottweiler_charger.tres` + `boss.gd`): `max_health`,
`move_speed`, `contact_damage`, `attack_damage`, `attack_cooldown`, `knockback`,
`xp_reward`, `phase_thresholds`, `difficulty_multiplier`; y en `boss.gd`:
`windup_time`, `charge_time`, `charge_speed`, `recover_time`, `contact_range`,
`summon_count`, `MAX_SUMMONED`, `MAX_HEALTH_CAP`.

---

## 12. Limpieza y reinicio (R)

Todos los jefes, mini-jefes, enemigos invocados, orbes y efectos son hijos del
nodo `MainLevel`; la barra de jefe vive en el HUD (también hijo del nivel). Al pulsar
**R** se llama `reload_current_scene()`, que **libera toda la escena**: no quedan
jefes duplicados, ni barra de jefe vieja, ni eventos activos (el WaveEventManager
reconstruye su agenda en `_ready` y la barra del HUD vuelve oculta). El BossSpawner
arranca con `_active_boss` nulo.

---

## 13. Riesgos conocidos

- El balance de jefes se validó por estructura y un **harness headless** (spawn,
  fases, embestida, invocación, muerte, recompensa, limpieza), **no** por un playtest
  jugado largo. Conviene afinar daño/vida jugando.
- Los enemigos invocados por el jefe no se cuentan en el `_alive_count` del
  EnemySpawner (son extra controlados por el tope `MAX_SUMMONED`). No afecta a la
  estabilidad, pero la presión total puede subir más de lo previsto en fase 3.
- El empuje al jugador (`apply_knockback`) es intencionalmente corto; con mucho
  knockback acumulado podría sentirse brusco. Ajustable en `boss_data.knockback`.
- No hay pantalla de victoria: al matar al jefe se muestra "Zona asegurada" y la
  partida continúa (queda preparado para Fase 06).

---

## 14. Pendiente para Fase 06

- Segundo jefe completo con patrón distinto (recurso ya preparable como BossData).
- Carta especial de recompensa al matar al jefe (hoy es XP grande + mensaje).
- Pantalla de victoria / fin de run y posible bucle de "pisos".
- Audio de eventos/jefes (puntos de conexión ya marcados con Feedback).
- Zona de peligro telegrafiada en el suelo (patrón opcional 4, no incluido).
