# STOP de pulido — Balance, dificultad dinámica y estética

Fase intermedia de pulido entre FASE 02 y FASE 03. **No** agrega armas nuevas,
jefes ni contenido: ajusta dificultad, balance y estética del prototipo actual
manteniendo la arquitectura (señales, grupos, `EnemyData`, upgrades, spawner).

---

## 1. Problemas detectados

1. **Demasiado fácil.** Los upgrades escalaban muy rápido (multiplicadores grandes
   y sin topes), el gato se volvía casi invencible hacia el nivel 5.
2. **Escalado insuficiente.** La dificultad solo subía por tiempo, en escalones de
   60s, e ignoraba el nivel del jugador y su rendimiento.
3. **Poca presión.** Los enemigos aparecían dispersos en un anillo lejano y se movían
   todos igual; no obligaban a moverse ni a decidir.
4. **Estética plana.** Fondo gris liso, gato y perros poco reconocibles, cartas de
   upgrade sin jerarquía visual, HUD sin información de progreso/intensidad.

## 2. Qué se cambió

### Dificultad y balance
- **Dificultad dinámica continua** en `EnemySpawner` mediante un `difficulty_score`
  (ver fórmula abajo). Sustituye al antiguo timer de escalones de 60s.
- El score ahora afecta: intervalo de aparición, máximo de enemigos vivos, vida,
  velocidad y **daño** de enemigos, proporción de **runners** y probabilidad de
  aparecer en el **borde visible de la cámara** (cerca → más presión).
- **Métrica de kills** añadida al spawner (`_kills`), usada en la fórmula y mostrada en HUD.
- **Upgrades rebalanceados** con magnitudes menores y **topes sanos** (ver sección 4).
- **Rarezas** (`comun`, `raro`, `epico`) con peso de aparición: las mejoras fuertes
  (p.ej. `+1 proyectil`, épico) salen mucho menos. Cada nivel ofrece **3 cartas distintas**.

### Jugabilidad / presión
- **Spawn en el borde de cámara** (probabilidad creciente) hace que los enemigos
  "entren en escena" rodeando al jugador desde los cuatro lados.
- **Variación de movimiento por enemigo**: jitter de velocidad (±~10%) y un zigzag
  suave con fase/fuerza propias, para que no se amontonen idénticos.
- Más **runners** a medida que sube la intensidad (peso que crece con la dificultad).

### Estética (sin assets externos, solo formas y código)
- **Fondo**: cuadrícula urbana sutil dibujada por código (`background_grid.gd`) que
  sigue a la cámara y se desplaza al moverse → sensación de velocidad, manteniendo legibilidad.
- **Gato**: placeholder mejorado (contorno, orejas con interior rosado, panza, ojos,
  nariz, cola) y un **indicador de dirección** que apunta hacia el último movimiento.
- **Perros zombis**: silueta con orejas, patas, cola y contorno; el `normal` es más
  robusto y verdoso, el `runner` más delgado (escala) y de color distinto (rojizo).
- **Proyectiles**: núcleo brillante + halo + estela, orientados a su trayectoria.
- **Orbes de XP**: núcleo + halo + destello con **pulso y rotación** animados.
- **Impacto de bala**: "punch" de escala + destello breve en el enemigo (sin partículas).
- **Muerte de enemigo**: desaparición animada (encoge + se desvanece) en ~0.16s.
- **Cartas de upgrade**: borde y etiqueta de color según rareza, títulos temáticos,
  mayor tamaño de fuente.
- **HUD**: panel de fondo para legibilidad, fuentes más grandes y dos métricas nuevas:
  **Eliminados** e **Intensidad** (nombre + valor numérico del score).

## 3. Fórmula de dificultad

Calculada cada frame en `EnemySpawner._recalculate_difficulty()`:

```
difficulty_score = minutos_sobrevividos
                 + nivel_jugador * level_weight      (level_weight = 0.75)
                 + enemigos_eliminados / kills_divisor (kills_divisor = 40)
```

El score alimenta (todo con tope máximo):

| Efecto                | Fórmula                                            | Tope            |
|-----------------------|----------------------------------------------------|-----------------|
| Intervalo de spawn    | `base 1.1 - score*0.05`                            | min `0.30 s`    |
| Máx. enemigos vivos   | `base 22 + score*3`                                | `90`            |
| Vida enemiga (x)      | `1 + score*0.06`                                   | `2.6`           |
| Velocidad enemiga (x) | `1 + score*0.025`                                  | `1.7`           |
| Daño enemigo (x)      | `1 + score*0.04`                                   | `2.2`           |
| Prob. borde de cámara | `0.10 + score*0.03`                               | `0.70`          |
| Peso de runner        | `spawn_weight + weight_growth*score` (runner 0.05) | —               |

**Curva esperada** (referencia): ~30s → score ≈ 4 (fácil), ~90s → ≈ 10 (medio),
~180s → ≈ 18 (peligroso). Los topes evitan que sea imposible demasiado pronto.

## 4. Límites de upgrades (anti-acumulación rota)

Magnitudes actuales y topes:

| Upgrade            | Rareza | Efecto        | Tope                                  |
|--------------------|--------|---------------|---------------------------------------|
| `weapon_damage`    | común  | +13% daño     | sin tope duro (gating por rareza/%)   |
| `player_speed`     | común  | +8% velocidad | `MAX_SPEED = 430` (player.gd)         |
| `max_health`       | común  | +18 vida      | `MAX_HEALTH_CAP = 360` (player.gd)    |
| `weapon_range`     | común  | +12% rango    | `MAX_RANGE = 900` (auto_weapon.gd)    |
| `weapon_cooldown`  | raro   | -10% cooldown | `MIN_COOLDOWN = 0.12` (auto_weapon.gd)|
| `pickup_range`     | raro   | +25% radio XP | `MAX_PICKUP_SCALE = 2.4` (player.gd)  |
| `extra_projectile` | épico  | +1 proyectil  | `MAX_PROJECTILES = 7` (auto_weapon.gd)|

Pesos por rareza (en `upgrade_manager.gd`): `common=1.0`, `rare=0.42`, `epic=0.16`.

## 5. Cómo ajustar el balance en el futuro

- **Curva de dificultad**: edita los `@export` de `EnemySpawner` (grupos
  "Fórmula de dificultad", "Aparición", "Escalado de enemigos", "Presión") desde el
  Inspector del nodo `EnemySpawner` en `MainLevel.tscn`. No hace falta tocar código.
- **Sensación de presión**: sube `base_edge_chance`/`edge_chance_per_point` o
  `enemies_per_point`; baja `min_spawn_interval`.
- **Fuerza de los upgrades**: cambia las magnitudes en `Player.apply_upgrade()` y los
  topes (constantes en `player.gd` y `auto_weapon.gd`).
- **Frecuencia por rareza**: ajusta `RARITY_WEIGHTS` y el campo `rarity` de cada
  entrada de `UPGRADE_POOL` en `upgrade_manager.gd`.
- **Variantes de enemigo**: edita los `.tres` en `data/enemies/` (incluido el nuevo
  campo `weight_growth` que controla cuánto crece su aparición con la dificultad).

## 6. Cómo probar que ya no es tan fácil

1. Ejecuta `MainLevel.tscn` (F5).
2. Observa el HUD: **Intensidad** sube de "Tranquilo" → "Medio" → "Peligroso" con el
   tiempo y el nivel; **Eliminados** crece.
3. ~30 s: manejable. ~90 s: hay que moverse. ~180 s: enjambre denso, muchos runners y
   enemigos apareciendo pegados al borde de la pantalla.
4. Sube varios niveles eligiendo siempre daño/proyectiles: notarás que **ya no te
   vuelves invencible** porque los enemigos también escalan (vida/daño/cantidad) y los
   upgrades fuertes (épicos) salen poco.
5. Déjate rodear: el daño por contacto escalado te mata si te quedas quieto.

> Verificado en Godot 4.7 headless: el proyecto importa y corre ~43 s de partida
> simulada sin errores ni warnings (muertes, drops de XP, escalado y subidas de nivel).

## 7. Pendiente para FASE 03

- Armas y upgrades adicionales sin hardcodear el pool (data-driven con `Resource`).
- Élites / mini-jefes y eventos de oleada.
- Feedback de audio (sigue sin implementarse) e impacto con partículas ligeras opcionales.
- Curva de dificultad afinada con métricas reales de playtesting.
- Posible separación del cálculo de dificultad en su propio sistema si más nodos lo necesitan.
