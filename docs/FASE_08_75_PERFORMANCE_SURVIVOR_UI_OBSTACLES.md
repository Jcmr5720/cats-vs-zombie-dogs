# FASE 08.75 — Reparación de estabilidad + survivor-like + UI de cartas + obstáculos

> **Prioridad:** 1) estabilidad, 2) mapas con obstáculos, 3) UI de cartas, 4) ajuste
> survivor-like. Sin Steam, arte final, multijugador ni assets externos. Sin romper
> guardado, armas, compañeros, jefes ni menús.

---

## 1. Causa probable del crash

Cuando el jugador no limpiaba enemigos, el `EnemySpawner` seguía generando y el número
de perros crecía. El coste real no era solo dibujar: cada enemigo, **cada frame de
física**, ejecutaba `get_tree().get_nodes_in_group("enemies")` para su separación
(comportamiento **O(n²)** con asignación de arrays por enemigo). Con cientos de perros
eso dispara el uso de CPU/GC y termina en lag extremo o cierre. A eso se sumaban orbes
de XP, números de daño y proyectiles sin un tope global claro.

La solución no es solo un cap: es **acotar `n`** con topes duros + backpressure +
limpieza de emergencia, y limitar XP/proyectiles/efectos.

## 2. PerformanceManager (`scripts/systems/performance_manager.gd`, autoload `Performance`)

Vigila la salud del juego y publica un estado que otros sistemas consultan:

- Mide **FPS suavizado** (cada frame) y, cada `sample_interval` (0.25 s), cuenta por
  grupo: `enemies`, `projectiles`, `xp_orbs`, `vfx` (efectos) y si hay `boss`/`miniboss`.
- `performance_state`:
  - **normal**: FPS ≥ 49 y enemigos ≤ 120.
  - **warning**: FPS 35–49 o enemigos 121–180.
  - **critical**: FPS < 35, o enemigos > 180, o FPS < 25 sostenido ≥ 3 s.
- Todos los umbrales son `@export` (ajustables desde el editor).
- `fps_sustained_critical()` y `get_debug_line()` (overlay F8).

Es barato: no recorre toda la escena, solo cuenta grupos cada 0.25 s.

## 3. Límites duros de enemigos + backpressure (`enemy_spawner.gd`)

Nuevos `@export` (grupo "Control de hordas"):

- `soft_enemy_cap = 120`, `hard_enemy_cap = 180`, `absolute_enemy_cap = 220`.
- `expected_kill_rate = 40` (kills/min de referencia).
- `backpressure_min_multiplier = 0.25`, `enable_emergency_cleanup`, `emergency_cleanup_distance`.

Reglas:

- El **techo dinámico** por defecto es `soft_enemy_cap`; una horda lo sube hacia
  `hard_enemy_cap`; en estado **critical** se recorta a un 60 %.
- No se genera nada si los enemigos vivos ≥ `hard_enemy_cap` (se lee del grupo, así
  cuenta también jefes/mini-jefes y spawns externos).
- **Backpressure**: si hay saturación (≥ soft cap) y el jugador mata menos que
  `expected_kill_rate`, o el `Performance` está warning/critical, el multiplicador de
  spawn baja suave hasta `backpressure_min_multiplier` (menos spawns, sin quitar la
  dificultad). Las mini-oleadas se suprimen bajo backpressure fuerte.
- El **kill-rate** se estima con los timestamps de kills de los últimos 60 s.

## 4. Limpieza de emergencia (último recurso)

`_maybe_emergency_cleanup()` se dispara solo si `enable_emergency_cleanup` y:
`enemigos > absolute_enemy_cap` **o** FPS bajo el piso duro sostenido y hay saturación.

Elimina únicamente enemigos **muy lejanos** (≥ `emergency_cleanup_distance`), ordenados
del más lejano al más cercano, hasta volver bajo el soft cap. **Nunca** toca jefes,
mini-jefes, enemigos cercanos, compañeros ni rescates. Tiene cooldown de 2 s.

## 5. Control de XP, proyectiles y efectos

- **XP** (`xp_orb.gd`): `max_xp_orbs = 120`. Al superarlo, el orbe nuevo **se fusiona**
  con el más cercano (suma su XP y se libera): no se pierde XP ni se acumulan nodos.
- **Proyectiles** (`weapon_projectile.gd`, `projectile.gd`): grupo `projectiles`,
  `MAX_PROJECTILES = 250`. Al superarlo se libera el proyectil **más lejano** al
  jugador (viejo/fuera de rango). Además cada bala ya tenía `lifetime`.
- **Efectos** (`feedback_manager.gd`): ya limitados a `max_active_effects` (números de
  daño + destellos combinados). Los efectos ahora están en el grupo `vfx` para que
  `Performance` los cuente.

## 6. Mecánicas survivor-like

Pulido de lo existente, sin sistemas nuevos:

- **Presión y respiro**: el backpressure crea valles de intensidad cuando hay
  saturación y deja subir la presión de nuevo al limpiar; las hordas siguen siendo
  picos programados.
- **Hordas dirigidas**: al empezar una horda se elige una dirección; una fracción
  (`horde_bias_strength = 0.6`) de los spawns llega desde ese lado (lectura de mapa y
  de movimiento).
- **Spawns alrededor, no encima**: se mantiene el anillo/borde de cámara y ahora los
  spawns se **empujan fuera de obstáculos** (`_resolve_spawn_position`).
- **Recompensa por riesgo**: los rescates aparecen a media/larga distancia y validan
  que **no** caigan sobre obstáculos, obligando a moverse por el mapa.
- **Curva de poder**: más armas/compañeros siguen subiendo la dificultad, pero los
  topes de rendimiento evitan que se dispare hasta romper el juego.

## 7. Sistema de obstáculos

Archivos nuevos:

- `scripts/maps/obstacle_data.gd` — Resource data-driven (categoría, tamaño, colores,
  colisión, peso, z-index, destructible opcional).
- `scenes/maps/Obstacle.tscn` + `scripts/maps/obstacle.gd` — `StaticBody2D` en la
  **capa 5** (valor 16) que dibuja su identidad con `_draw` según la categoría
  (carro, muro, casa, contenedor, barril, árbol, banca, roca, caja, valla, tubería,
  arbusto, señal): cuerpo + detalle + sombra + borde.
- `scripts/maps/obstacle_spawner.gd` — reparte obstáculos alrededor del inicio del
  jugador con **muestreo por rechazo**: respeta `min_obstacle_distance`,
  `safe_radius_around_player`, `max_obstacles` y, si `road_layout_type = "cross"`,
  deja **avenidas centrales** libres. Los obstáculos cuelgan del spawner, así que se
  limpian solos al reiniciar (R) — no se duplican.
- `data/obstacles/*.tres` — 16 tipos (6 barrio, 5 parque, 5 industrial).

**Colisión**: jugador, enemigos y compañeros añaden en `_ready`
`set_collision_mask_value(5, true)` → no atraviesan los obstáculos. Los enemigos usan
`move_and_slide` (deslizan solos) **más** un steering lateral cuando chocan
(`_avoid`), para rodear sin quedarse atascados en masa.

**Pathing de proyectiles**: por ahora **no** se bloquean con obstáculos (queda
documentado como mejora futura para no arriesgar rendimiento/estabilidad).

**Destructibles**: los datos existen (`destructible`, `health`, `xp_reward`) pero no
están activos: los obstáculos son estáticos y nada los daña todavía. Queda preparado
para una fase futura (requiere que las armas puedan apuntarlos).

## 8. Configuración por mapa (`MapData` + `.tres`)

`MapData` gana: `obstacle_types`, `obstacle_density`, `max_obstacles`,
`min_obstacle_distance`, `safe_radius_around_player`, `safe_radius_around_rescue`,
`obstacle_field_radius`, `allow_large_blocks`, `road_layout_type`, `road_half_width`.

- **Barrio Gatuno**: densidad 0.55, calles en cruz (`cross`), carros, muros, casas,
  contenedores, cajas, barricadas. Bloques grandes permitidos.
- **Parque Abandonado**: densidad 0.5, sin calles, árboles, bancas, rocas, arbustos,
  cercas. `allow_large_blocks = false` (más abierto).
- **Callejón Industrial**: densidad 0.75, más estrecho, contenedores, barriles,
  tuberías, muros metálicos, bloques de concreto.

## 9. Rediseño de cartas de upgrade

`HUD.tscn` + `hud.gd`: cada carta muestra ahora **icono geométrico grande** (glifo por
tipo: ✦ arma, ▲ stat/mejora, ✚ compañero, ◆ sinergia, ● otro), **nombre corto**,
**efecto en 1 línea** y una línea **TIPO · RAREZA**. El **borde** colorea la rareza
(gris/común, cyan/raro, morado/épico). Animación de entrada escalonada, hover con
crecimiento + SFX y el detalle largo en tooltip. Poco texto, más recompensa visual.

## 10. Overlay de depuración (F8)

`HUD` crea un overlay oculto que, con **F8**, muestra la línea de `Performance`:
`FPS 60 | NORMAL | E:42 P:12 XP:5 FX:3` (+ BOSS). Sirve para las pruebas de estabilidad.

## 11. Cómo probar estabilidad

- **F8** para ver FPS/estado/conteos.
- Quédate quieto sin disparar y deja que se acumulen perros: el conteo se estabiliza
  ~120 (soft) y no crashea; en horda sube hacia 180 y vuelve a bajar.
- Fuerza jefe temprano (`WaveEventManager.debug_spawn_boss_early`) y confirma que el
  jefe nunca se elimina por la limpieza.
- Si el estado llega a **critical**, el spawn se frena y el techo baja; al matar
  enemigos, se recupera.

## 12. Cómo probar las cartas

Sube de nivel (mata perros y recoge XP): aparecen 3 cartas con icono grande, borde de
rareza, nombre corto y efecto de 1 línea; hover crece y suena; al elegir se aplica y
vuelve el juego.

## 13. Cómo ajustar densidad de obstáculos

En cada `data/maps/*_map.tres`: `obstacle_density` (0..1) y `max_obstacles` controlan
cuántos hay; `min_obstacle_distance` la separación; `safe_radius_around_player` el
claro inicial; `road_layout_type = &"cross"` + `road_half_width` deja avenidas.
Para un tipo nuevo: crea un `ObstacleData` en `data/obstacles/` (elige `category` para
el dibujo) y agrégalo al array `obstacle_types` del mapa. Tope de rendimiento: mantén
`max_obstacles` ≲ 50 colisionables.

## 14. Archivos

**Creados**
- `scripts/systems/performance_manager.gd`
- `scripts/maps/obstacle_data.gd`, `scripts/maps/obstacle_spawner.gd`, `scripts/maps/obstacle.gd`
- `scenes/maps/Obstacle.tscn`
- `data/obstacles/` (16 `.tres`)
- `docs/FASE_08_75_PERFORMANCE_SURVIVOR_UI_OBSTACLES.md`

**Modificados**
- `project.godot` (autoload `Performance`).
- `scripts/enemies/enemy_spawner.gd` (caps, backpressure, limpieza, validación de spawn,
  hordas dirigidas).
- `scripts/enemies/enemy.gd` (colisión con obstáculos + steering; grupo).
- `scripts/player/player.gd`, `scripts/companions/companion.gd` (colisión con obstáculos).
- `scripts/loot/xp_orb.gd` (cap + fusión).
- `scripts/weapons/weapon_projectile.gd`, `scripts/weapons/projectile.gd` (grupo + cap).
- `scripts/effects/damage_number.gd`, `scripts/effects/hit_effect.gd` (grupo `vfx`).
- `scripts/companions/rescue_spawner.gd` (rescates fuera de obstáculos).
- `scripts/maps/map_data.gd`, `scripts/maps/map_manager.gd` (config + generación).
- `data/maps/*_map.tres` (config de obstáculos por bioma).
- `scenes/levels/MainLevel.tscn` (nodo `ObstacleSpawner`).
- `scenes/ui/HUD.tscn`, `scripts/ui/hud.gd` (cartas + overlay F8).
- `README.md`.

## 15. Riesgos conocidos

- La separación de enemigos sigue siendo O(n²), pero ahora `n` está acotado (≤ ~120
  normal / 180 en horda), que es el rango manejable. Si en el futuro se sube el cap,
  convendría un grid espacial para la separación.
- Los **proyectiles no chocan** con obstáculos (por diseño, para no arriesgar). El
  jugador puede disparar "a través" de un muro.
- Los **obstáculos destructibles** están definidos pero inactivos (nada los daña aún).
- La **limpieza de emergencia** puede hacer desaparecer perros lejanos de golpe si el
  FPS ya está por el suelo; es intencional (último recurso) y solo afecta a lo que está
  fuera de la vista.
- Con densidad muy alta + `allow_large_blocks`, en teoría podrían formarse pasillos
  estrechos; los radios seguros y el trazado en cruz lo mitigan, pero conviene revisar
  visualmente al subir mucho `obstacle_density`.

## 16. Recomendación para la siguiente fase

La base es estable y más táctica. La Fase 09 podría: (a) activar **destructibles**
(que las explosiones dañen barriles/cajas y suelten XP), (b) **bloquear proyectiles**
selectivamente con obstáculos según arma, (c) sustituir la separación por un **grid
espacial** si se quiere subir el cap de enemigos, y (d) pulir arte/audio ya sobre un
gameplay que no se rompe con hordas grandes.
