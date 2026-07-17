# Hoja de ruta: jugabilidad más adictiva (nivel survivors-like de Steam)

Objetivo: cerrar la brecha con Vampire Survivors / Brotato / HoloCure en los
ganchos que hacen decir "una partida más". Ordenada por impacto/esfuerzo.

| Etapa | Contenido | Estado |
|---|---|---|
| 1 | Agencia en el level-up (reroll/veto/pasar) + 2 armas + 2 mejoras permanentes | ✅ Implementada |
| 2 | 6 evoluciones de armas con carta legendaria | ✅ Implementada |
| 2.5 | Auto-apuntado inteligente (jugador + compañeros + torreta) | ✅ Implementada |
| 3 | Pooling y hordas de 300+ | Pendiente |
| 4 | 4 personajes jugables (estilo Brotato) | Pendiente |
| 5 | +4 enemigos, +2 jefes, +3 eventos de oleada | Pendiente |
| 6 | Juice fino + retención de sesión | Pendiente |

---

## Etapa 1 — Agencia en el level-up ✅ (implementada)

- `scripts/systems/upgrade_manager.gd`: 1 reroll + 1 veto base por partida.
  Los ids vetados no reaparecen el resto de la run. Constantes `BASE_REROLLS`,
  `BASE_BANISHES`. (Fase corrección: el botón «Pasar» y sus recompensas se
  ELIMINARON — subir de nivel siempre exige elegir una carta.)
- `scripts/ui/hud.gd`: fila de acciones bajo las cartas («Otra tirada (n)»,
  «Vetar carta (n)» —modo veto: el siguiente clic en una carta la veta—).
  El panel tolera manos de menos de 3 cartas.
- Mejoras permanentes nuevas (sumidero de Sardinas, solo Modo Historia):
  `data/permanent_upgrades/lucky_paw.tres` (+1 reroll/run, 3 niveles) y
  `picky_eater.tres` (+1 veto/run, 2 niveles). Efectos `reroll_per_run` /
  `banish_per_run` leídos vía `MetaProgression.get_effect_total`.
- Armas nuevas (pool 6 → 8, solo datos): `data/weapons/hairball_launcher.tres`
  (explosivo, dmg 14 / cd 1.6 / radio 90) y `claw_wave.tres` (boomerang,
  dmg 6 / cd 0.9 / pierce 4).

## Etapa 2 — Evoluciones de armas ✅ (implementada)

Arma a nivel máximo + carta de stat requisito elegida en la run → aparece una
carta LEGENDARIA dorada garantizada (peso 60). Tope: **2 evoluciones por run**
(`MAX_EVOLUTIONS_PER_RUN`). La evolución reemplaza el arma conservando el slot,
con hitstop + shake + destello dorado. En coop aplica a ambos jugadores
(`PlayerManager.evolve_weapon_to_team`).

| Base (requisito de stat) | Evolución | Rasgo |
|---|---|---|
| Pistola Gatuna (Furia múltiple) | Ametralladora Maulladora | 3 proyectiles, cd 0.33 |
| Ovillo Explosivo (Garras afiladas) | Ovillo Agujero Negro | zona que ATRAE (knockback negativo) |
| Sardina Boomerang (Vista aguda) | Banco de Sardinas | 3 proyectiles, pierce 8 |
| Rascador Giratorio (Reflejos rápidos) | Ciclón de Garras | 6 orbitales, radio +40% |
| Puntero Láser (Garras afiladas) | Rayo Prisma | cadena hasta 4 enemigos (daño ×0.8/salto) |
| Granada de Catnip (Olfato de tesoros) | Campo de Hierba Salvaje | radio +60%, tick 0.3 |

Datos en `data/weapons/evolved/*.tres`; campos `evolution` /
`evolution_requirement` en `WeaponData`. Código nuevo de comportamiento:
láser en cadena y pull de zona en `weapon_base.gd` / `weapon_area.gd`.
Las evoluciones llegan a nivel 1 con `max_level 3` (~2.2× DPS del Nv5 base).

## Etapa 2.5 — Auto-apuntado inteligente ✅ (implementada)

Sustituye el "disparar al más cercano" por un scoring compartido en
`scripts/weapons/targeting.gd` (helper estático puro, todo el balance en
constantes con nombre):

- **Amenaza real**: enemigos a <180 px del jugador/líder Y acercándose pesan
  ×1.6 — deja de disparar al rezagado de atrás mientras te acorralan.
- **Marca del Policía**: ×1.2 para TODO el equipo (antes solo la torreta);
  en la torreta la marca gana siempre.
- **Tiro liderado (intercept)**: la bala apunta a donde VA a estar el blanco
  (cuadrático exacto, componente lateral del zigzag amortiguada ×0.65, tope
  0.9 s). Sin homing: la bala sigue recta. Aplica a jugador, compañeros y
  torreta.
- **Por tipo de arma** en `weapon_base.gd`: el láser prioriza elites/tanques
  (×(1+HP/100), elites ×2.5); el explosivo apunta al centroide del racimo; el
  boomerang/pierce elige la fila más valiosa (16 bins angulares + corredor de
  ±48 px); la zona de catnip cae en el centroide del cluster.
- **Rendimiento**: una pasada O(n) por disparo recortada a 20 candidatos; el
  trabajo cuadrático (clusters) queda acotado a 20×20.

Valores ajustables: `DANGER_RADIUS=180`, `DANGER_WEIGHT=1.6`, `MARK_BONUS=1.2`,
`ELITE_BONUS_LASER=2.5`, `LEAD_DAMPING=0.65`, `LEAD_MAX_TIME=0.9`,
`PIERCE_CORRIDOR_HALF_WIDTH=48`, `MAX_CANDIDATES=20` — todo en `targeting.gd`.

Archivos: `scripts/weapons/targeting.gd` (nuevo), `weapon_base.gd`
(`_fire_projectiles`/`_fire_laser`/`_fire_area`), `scripts/companions/companion.gd`
(`_find_priority_enemy`, `_fire_at`), `companion_turret.gd` (`_pick_target`,
`_fire`). Test: `tests/TestTargeting.tscn`.

## Etapa 3 — Pooling y hordas grandes (pendiente)

Prerequisito de las etapas 4-5: más masa en pantalla estable.

- Nuevo `scripts/systems/object_pool.gd`: pools por PackedScene con
  `acquire()/release()` y precalentado (enemigos 250, proyectiles 200, orbes
  300, damage numbers 80).
- `enemy_spawner.gd` / `enemy.gd`: `reset(data)` en vez de instanciar/liberar;
  checklist de estado residual (mods elite, tweens, metas `companion_mark`,
  señales). Subir caps 120/180/220 → 200/300/380 tras medir.
- `projectile.gd`, `xp_orb.gd`, `damage_number.gd`: mismo patrón. Fusión de
  orbes en orbes "gordos" al superar 200 vivos.
- Conectar `performance_manager.gd` para escalar caps por frame time.
- Riesgo principal: estado residual en nodos reciclados → test de doble ciclo
  de un enemigo elite.

## Etapa 4 — Personajes jugables (pendiente)

Elegibles en TODOS los modos (decisión del usuario), desbloqueo con Sardinas
(segundo sumidero de moneda).

- Nuevo `scripts/player/character_data.gd` (Resource): stats base, modificadores
  ±% (daño/velocidad/vida/cooldown), arma inicial, perk único, colores del arte
  procedural, coste.
- 4 personajes en `data/characters/`: **Callejero** (actual, gratis, neutro),
  **Gato Gordo** (+40 vida, +15% daño, −20% velocidad, empieza con Ovillo; 300),
  **Siamés Veloz** (+25% velocidad, +15% CDR, −30% vida, máx 3 armas; 500),
  **Gata Bruja** (área/orbital +30%, proyectil −25%, empieza con Rascador; 800).
- `player.gd` lee CharacterData al inicializar; `player_manager.gd` permite
  personaje distinto por jugador en coop; pantalla nueva
  `scenes/menus/CharacterSelect.tscn` en el flujo de `game_flow_manager.gd`;
  persistencia en `save_data.gd`.
- Riesgo: stats dispersos en player.gd → consolidar primero.

## Etapa 5 — Variedad de amenazas (pendiente)

- 4 enemigos nuevos (`enemy_data.gd` + rama `behavior` en `enemy.gd`):
  **spitter** (proyectil lento esquivable — requiere capa de colisión nueva),
  **splitter** (muere → 2 cachorros), **shieldbearer** (inmune de frente),
  **screamer** (buffea velocidad de cercanos; objetivo prioritario natural del
  Gato Policía).
- 2 jefes (`data/bosses/`): **Pastor Espectral** (teleport + niebla, mapas
  oscuros) y **Gran Danés Colosal** (pisotón AoE telegrafiado + muro de pups).
  Dar patrón real al mini-jefe (embestida simple).
- 3 eventos (`wave_event_manager.gd`): **lluvia de sardinas** (activa el
  `xp_bonus` sin uso + drop de Sardinas en Partida Libre — hoy el modo libre no
  da moneda), **convoy de elites** (5 en fila, drop garantizado), **frenesí 30s**
  (spawn ×2 + XP ×2).

## Etapa 6 — Juice y retención (pendiente)

- Slow-mo 0.15s (`Engine.time_scale` 0.3) al evolucionar / matar jefe / combo
  ×10 — cuidado con pausa y coop al restaurar.
- Cofres de elite (drop 10%): animación de apertura con 1-3 cartas del pool
  existente (respetando máx 4 armas / niveles).
- 8 misiones rotativas diarias con Sardinas (razón de volver mañana).
- Resumen de partida con récords personales resaltados y "Reintentar" a 1 clic.
- Tutorial mínimo: 4 tooltips contextuales en la primera partida (flag en save).

---

## Balance inicial elegido (etapas 1-2)

| Valor | Elegido | Dónde |
|---|---|---|
| Rerolls / vetos base por run | 1 / 1 | `upgrade_manager.gd` |
| Compensación de "Pasar" | +20 XP, +5 vida | `upgrade_manager.gd` |
| Peso de carta de evolución | 60 (garantizada en mano de 3) | `_build_candidates` |
| Tope de evoluciones por run | 2 | `MAX_EVOLUTIONS_PER_RUN` |
| DPS de evolución | ~2.2× del Nv5 base | `data/weapons/evolved/` |
| Decaimiento del láser en cadena | ×0.8 por salto, salto máx 260 px | `weapon_base.gd` |
| Coste Pata de la Suerte / Paladar Exigente | 70 / 90 sardinas, crecimiento 1.6 | `data/permanent_upgrades/` |

## Validación ejecutada (etapas 1-2)

- `godot --headless --path . --import` — sin errores.
- `res://tests/TestUpgrades.tscn` — 38 checks, 0 fallos (reroll/veto/pasar,
  filtrado de vetados, 8 armas, carta legendaria con requisitos y tope,
  swap de evolución, láser en cadena, zona con atracción).
- Regresión: TestCompanions (33/33), smoke, test_shelter, test_story,
  test_ui_flow, test_world_gen — todos OK.
- Pendiente: prueba manual jugada (balance real de evoluciones vs jefes).

## Rework Coop Local: pantalla dividida + cartas por jugador

Feedback de la beta: los jugadores se perdian ("no se quien es quien"), la correa
de la camara compartida empujaba y frustraba, y las cartas/XP compartidas hacian
que una sola persona decidiera por ambos. Rediseño completo:

- **Pantalla dividida** (`coop_split_screen.gd` + `split_camera.gd`): dos
  SubViewports que comparten `world_2d`, camara propia por jugador (sin correa,
  sin limite de separacion, sin zoom compartido). Cada mitad tiene marco del
  color del jugador, mini-HUD (vida/XP/nivel), overlay de derribado con barra de
  revive y flecha de borde hacia el companero (pulsa en SOS si esta derribado).
- **Identidad**: J1 naranja / J2 azul en TODO (anillo bajo el gato + placa J1/J2,
  marco de la mitad, panel de cartas). `player.gd::_build_identity_marker`.
- **Progresion independiente**: cada jugador acumula SU XP y sube SU nivel; quien
  recoge el orbe se lleva el 100% y el companero recibe el 50% (`COOP_XP_SHARE`).
- **Cartas por jugador** (`coop_upgrade_panel.gd`): al subir de nivel se pausa y
  cada jugador elige EN SU MITAD con SUS controles (J1: W/S + Espacio/raton;
  J2: stick/I-K + A/H — acciones `p1_card_confirm`/`p2_card_confirm`). Seleccion
  simultanea si ambos suben a la vez. Armas y stats aplican SOLO a quien elige
  (builds propias); las cartas de companero tocan el equipo. Sin reroll/veto en
  coop (rapidez y legibilidad); "Pasar" da +20 XP y cura 5.
- **Bugs sistemicos arreglados**: los orbes magnetizaban SOLO hacia P1
  (`xp_orb.gd` ahora apunta al jugador activo mas cercano); el spawner anclaba
  todos los spawns en P1 (ahora reparte entre jugadores activos y evita nacer a
  la vista de cualquiera de las dos mitades); la limpieza de emergencia podia
  borrar enemigos pegados a P2 (ahora usa la distancia al jugador MAS cercano);
  la dificultad ahora lee nivel maximo + mejoras/armas SUMADAS del equipo.
- Balance: dano por jugador 0.9 (antes 0.85 con armas compartidas).

| Valor | Elegido | Dónde |
|---|---|---|
| XP compartida al companero | 50% | `player.gd::COOP_XP_SHARE` |
| Dano por jugador en coop | 0.9 | `player_manager.gd` |
| Zoom por mitad | 0.95 | `split_camera.gd` |
| Distancia minima de spawn a cualquier jugador | 420 px | `enemy_spawner.gd` |

Validación: `TestCoop.tscn` (37 checks, 0 fallos: estructura del split, cartas
independientes, XP compartida, seleccion simultanea, revive por proximidad),
`TestCoopSoak.tscn` (2400 frames de partida coop real sin errores), suite previa
sin regresiones. Prueba manual pendiente: sensacion de camara y balance de XP.
