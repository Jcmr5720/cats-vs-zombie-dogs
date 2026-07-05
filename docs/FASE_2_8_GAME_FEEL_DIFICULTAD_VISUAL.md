# FASE 2.8 — Game feel, juiciness, dificultad y pulido visual

Fase de **pulido** sobre lo ya construido (FASE 01 + FASE 02 + STOP de pulido).
**No** agrega compañeros, jefes, Steam, menú, guardado ni audio: hace que el juego
se *sienta* mejor, se vea más bonito y sea más difícil, manteniendo la arquitectura
(señales, grupos, `EnemyData`, `UpgradeManager`, HUD, spawner).

> Validado en Godot 4.7 headless: import sin errores y ~2200 frames de partida
> simulada sin errores ni warnings (spawns, muertes, drops/imán de XP, knockback,
> separación, subidas de nivel con pausa/tweens, feedback de daño y shake).

---

## 1. Problemas detectados

1. **Demasiado fácil** y el jugador escalaba casi a invencible: los topes de upgrades
   eran generosos (cooldown 0.12, 7 proyectiles, vida 360, etc.).
2. La dificultad ignoraba **cuántas mejoras** llevaba el jugador (una build fuerte no
   subía la presión).
3. Faltaba **feedback de impacto**: no había números de daño, knockback ni destello.
4. La **muerte** del enemigo y la **recolección de XP** se sentían secas (sin imán,
   sin rebote, sin mini-animación).
5. El **daño al jugador** no se comunicaba (sin flash rojo, sin parpadeo, sin shake).
6. La **subida de nivel** aparecía sin énfasis (sin entrada de cartas ni hover).
7. El gato era estático (sin respiración/cola/bounce).

## 2. Qué se cambió

### Dificultad
- **Nuevo término en la fórmula**: `upgrades_elegidos * upgrade_weight`. El jugador
  ahora rastrea `upgrades_chosen` y el spawner lo lee.
- Fórmula **más agresiva**: `time_weight = 1.2`, `level_weight 0.75 → 0.9`,
  `kills_divisor 40 → 35`.
- **Mini-oleadas**: con probabilidad creciente, un spawn genera varios enemigos de
  golpe (`base_wave_chance`, `wave_chance_per_point`, `wave_extra_enemies`).

### Balance de upgrades (topes más estrictos, alineados al objetivo de Fase 2.8)
- Cooldown mínimo `0.12 → 0.15` · Proyectiles máx `7 → 5` · Velocidad máx `430 → 420`
  · Rango máx `900 → 850` · Vida máx `360 → 220`.
- Magnitudes **comunes** ligeramente reducidas: daño `+13% → +10%`, velocidad
  `+8% → +6%`, vida `+18 → +15`, rango `+12% → +10%`. Raras/épicas intactas (salen menos).

### Game feel (todo con formas, tweens y código; sin assets externos)
- **Números de daño** flotantes (`DamageNumber.tscn`).
- **Destello de impacto/muerte** (`HitEffect.tscn`, anillo que se expande y desvanece).
- **Knockback** del enemigo en la dirección de la bala (decae exponencialmente).
- **Separación** entre enemigos (steering simple) para que no se apilen.
- **Imán de XP** con dos rangos: atracción (derivada del radio de recolección del
  jugador) y recolección; **rebote** al soltarse y **mini-animación** al recogerse.
- **Daño al jugador**: parpadeo rojo del gato + flash rojo de pantalla (HUD) + shake.
- **Screen shake** por trauma (`camera_effects.gd`), suave y desactivable.
- **Subida de nivel**: shake breve + **entrada escalonada** de cartas + **hover** + pop
  del título (la cámara y el panel procesan en pausa).
- **Gato animado**: respiración, squash-and-stretch al caminar y meneo de cola.
- **Perro zombi**: se añadió un **colmillo** al placeholder para reforzar el tono zombi.

### Optimización
- `FeedbackManager` (autoload **Feedback**) centraliza efectos y los **limita**
  (`max_active_effects = 70`); por encima descarta efectos nuevos. Todos los efectos
  se cuelgan de la escena actual y se liberan solos (incluido al reiniciar con R).

## 3. Fórmula de dificultad

Calculada cada frame en `EnemySpawner._recalculate_difficulty()`:

```
difficulty_score = minutos_sobrevividos * time_weight      (time_weight  = 1.2)
                 + nivel_jugador        * level_weight      (level_weight = 0.9)
                 + enemigos_eliminados  / kills_divisor     (kills_divisor= 35)
                 + upgrades_elegidos    * upgrade_weight    (upgrade_weight=0.35)
```

El score alimenta (todo con tope): intervalo de spawn, máx. enemigos vivos, vida,
velocidad y daño enemigos, prob. de aparición en el borde de cámara, peso de runners
y **prob. de mini-oleada**.

| Efecto                | Fórmula                              | Tope         |
|-----------------------|--------------------------------------|--------------|
| Intervalo de spawn    | `1.1 - score*0.05`                   | min `0.30 s` |
| Máx. enemigos vivos   | `22 + score*3`                       | `90`         |
| Vida enemiga (x)      | `1 + score*0.06`                     | `2.6`        |
| Velocidad enemiga (x) | `1 + score*0.025`                    | `1.7`        |
| Daño enemigo (x)      | `1 + score*0.04`                     | `2.2`        |
| Prob. borde de cámara | `0.10 + score*0.03`                  | `0.70`       |
| Prob. mini-oleada     | `0.05 + score*0.02`                  | `0.45`       |

**Curva esperada**: ~30s manejable pero con varios enemigos; ~90s obliga a moverse;
~180s peligroso (oleadas densas + runners + spawns en el borde); ~300s difícil si la
build no fue buena. Los topes evitan que sea imposible demasiado pronto.

## 4. Parámetros que puedes tocar

### Dificultad (Inspector del nodo `EnemySpawner` en `MainLevel.tscn`)
Grupos: *Fórmula de dificultad* (`time_weight`, `level_weight`, `kills_divisor`,
`upgrade_weight`), *Aparición*, *Escalado de enemigos*, *Presión* (incluye
`base_wave_chance`, `wave_chance_per_point`, `max_wave_chance`, `wave_extra_enemies`).

### Balance de upgrades
- Magnitudes: `Player.apply_upgrade()` en `scripts/player/player.gd`.
- Topes: constantes en `player.gd` (`MAX_SPEED`, `MAX_HEALTH_CAP`, `MAX_PICKUP_SCALE`)
  y `auto_weapon.gd` (`MIN_COOLDOWN`, `MAX_RANGE`, `MAX_PROJECTILES`).
- Frecuencia por rareza: `RARITY_WEIGHTS` y el campo `rarity` en `upgrade_manager.gd`.

### Visuales / game feel
- **Shake**: `camera_effects.gd` (`shake_enabled`, `max_offset`, `max_roll`, `decay`)
  en el nodo `Player/Camera2D`. Pon `shake_enabled = false` para desactivarlo.
- **Cantidad de efectos**: `feedback_manager.gd` (`max_active_effects`,
  `effects_enabled`) — autoload **Feedback**.
- **Knockback/separación enemigo**: `enemy.gd` (`knockback_strength`, `knockback_decay`,
  `separation_radius`, `separation_strength`).
- **Imán de XP**: `xp_orb.gd` (`attract_multiplier`, `collect_radius`, `attract_accel`,
  `max_attract_speed`, `pop_friction`).
- **Animación del gato**: `Player._animate_visual()`.
- **Colores/tamaños de enemigos**: los `.tres` en `data/enemies/`.

## 5. Cómo probar el game feel

1. Ejecuta `MainLevel.tscn` (F5).
2. **Impactos**: al disparar verás números de daño, un destello y el enemigo retrocede.
3. **Muerte**: el perro encoge/desvanece, suelta un orbe que *rebota* y luego *vuela*
   hacia ti (imán) y se recoge con un brillo.
4. **Daño**: déjate tocar; el gato parpadea en rojo, la pantalla destella y la cámara
   tiembla suave.
5. **Subida de nivel**: las cartas entran escaladas/animadas y crecen al pasar el ratón.
6. **Gato**: en reposo respira y mueve la cola; al caminar hace un leve bounce.

## 6. Cómo probar la dificultad

Observa el HUD: **Intensidad** (Tranquilo → Calentando → Medio → Peligroso → Caótico) y
**Eliminados** suben con tiempo, nivel, kills y mejoras elegidas. ~30s manejable, ~90s
hay que moverse, ~180s enjambre denso con oleadas y spawns pegados al borde. Quedarse
quieto te mata por el daño de contacto escalado.

## 7. Las 5 partidas de prueba

- **A — Normal hasta nivel 3**: recoge XP, sube de nivel, elige cartas. Verifica pausa,
  animación de cartas y que el juego continúa al elegir.
- **B — Quedarse quieto**: no te muevas. El imán recoge algo de XP, pero el daño de
  contacto y las oleadas deben matarte → el juego castiga la pasividad.
- **C — Solo ofensivas** (daño/cooldown/proyectiles): notarás más limpieza, pero los
  topes (5 proyectiles, cooldown 0.15) y el escalado enemigo evitan invencibilidad.
- **D — Solo vida/velocidad**: sobrevives más, pero sin daño suficiente te rodean; sigue
  habiendo peligro real.
- **E — Sobrevivir 180s+**: comprueba oleadas densas, muchos runners, spawns en el borde
  y que la Intensidad llega a "Peligroso/Caótico".

## 8. Errores que podrían aparecer / riesgos técnicos

- Si Godot no reconoce el autoload **Feedback**, reabre el proyecto (regenera `.godot/`).
- Las llamadas a `Feedback.*` dependen del autoload registrado en `project.godot`.
- Los tweens de las cartas se vinculan a `UpgradePanel` (PROCESS_MODE_WHEN_PAUSED) y la
  cámara a `PROCESS_MODE_ALWAYS` para animar durante la pausa de subida de nivel.
- `_separation()` es O(n²) sobre el grupo de enemigos; con el tope de 90 vivos es barato,
  pero si subes `hard_cap_enemies` mucho, conviene espaciarlo o usar una rejilla.
- El imán de XP mueve el orbe por posición (no física); es intencional y barato.

## 9. Pendiente para FASE 03

- Audio final (Fase 09 agrego placeholders procedurales; falta mezcla y assets finales).
- Compañeros, élites/mini-jefes y eventos de oleada con telegrafiado.
- Upgrades/armas data-driven (sacar el pool hardcodeado de `upgrade_manager.gd`).
- Afinar la curva con métricas reales de playtesting.
- Posible separación del cálculo de dificultad a su propio sistema/autoload.
