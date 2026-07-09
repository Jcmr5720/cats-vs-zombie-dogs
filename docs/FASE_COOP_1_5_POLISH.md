# Fase Coop 1.5 — Pulido del cooperativo local

Pulido del modo **cooperativo local** (2 jugadores, misma pantalla, sin red) sobre la
base de [`FASE_COOP_LOCAL.md`](FASE_COOP_LOCAL.md). Objetivo: que sea **jugable, claro,
balanceado y estable**, sin romper el modo Solo.

Regla mantenida: **todo lo coop se activa solo si `GameFlow.is_coop()`** o a través de
grupos compatibles (`"players"` incluye al P1). En Solo no cambia el comportamiento.

---

## Problemas que había y cómo se resolvieron

| Problema | Solución |
|---|---|
| Las cartas de arma solo mejoraban a P1 | Las cartas de arma se aplican al **equipo** (`PlayerManager.add_weapon_to_team` / `apply_weapon_upgrade_to_team`): ambos WeaponManagers quedan sincronizados. |
| P2 no progresaba de verdad | P2 recibe las mismas armas y niveles que P1; las cartas de **stat** propias también se replican a P2 sin duplicar bonos de compañeros. |
| Daño total se disparaba con 2 jugadores | Multiplicador de daño por jugador **0.85** (`coop_player_damage_multiplier`). |
| Cámara podía perder a un jugador | **Correa (leash)** + **indicadores fuera de cámara** + aviso de separación. |
| No se podía pausar con control | Acción `p2_pause` (Start/Options del gamepad). |
| P2 no podía elegir cartas | Foco nativo de Godot: el P2 navega con dpad/stick y confirma con A. |
| Boss/mini perseguían a un P1 derribado | Targeting al **jugador activo más cercano**; ignoran derribados. |
| Boss/mini no escalaban en coop | Vida ×1.55 (boss) y ×1.45 (mini) en coop. |
| Médico solo curaba a P1 | Cura al **jugador activo más herido**. |
| P2 no podía revivir compañeros | El área de revive de compañeros acepta el grupo `"players"`. |
| Compañeros se pegaban al P1 derribado | Siguen al **líder activo** del equipo. |

---

## Cámara y correa (leash)

`coop_camera.gd` sigue el punto medio y ajusta el zoom con **límites de legibilidad**:
`min_zoom = 1.0` (nunca se ve diminuto) y `max_zoom = 1.35` (nunca zoom excesivo).
La separación no se resuelve alejando la cámara sin fin, sino con la **correa**, en
`PlayerManager._update_leash`:

- `soft_distance_limit = 700` px → aviso **"¡No se separen!"** + marco de alerta pulsante.
- `hard_distance_limit = 950` px → empuje **suave** de ambos jugadores hacia el centro
  (`leash_correction = 0.14` por frame, con `lerp`, sin teletransportes ni tirones).

Validado headless: dos jugadores a 2000 px se corrigen hasta ~950 px (límite duro).

## Indicadores de jugador fuera de cámara

`PlayerManager._update_offscreen_indicators`: una **flecha + etiqueta por jugador**,
creadas UNA vez y **reutilizadas** cada frame (sin crear nodos por frame). Si un
jugador sale del área visible, su flecha se fija en el borde apuntando hacia él, con el
color del jugador (P1 naranja, P2 azul) y su etiqueta. Se ocultan cuando está visible o
derribado. La proyección usa `camera.get_screen_center_position()` y `camera.zoom`, así
que funciona con el zoom cambiante.

## Progreso de armas para P2

XP, nivel y cartas siguen **compartidos**. Al elegir una carta de arma, `UpgradeManager`
detecta coop (`_player_manager_if_coop()`) y la enruta al equipo:
- **Arma nueva** → la reciben todos los jugadores.
- **Subir de nivel** → sube en todos los WeaponManagers.
- Cartas de **stat** propias (daño, velocidad, vida, rango, cooldown, proyectil,
  recogida) → se replican al P2 con `Player.apply_upgrade(id, include_shared = false)`,
  que aplica solo el efecto propio y **no** vuelve a tocar al CompanionManager (evita
  duplicar los bonos de compañeros, que son de equipo).

Validado headless: `add_weapon_to_team` sube armas de P1 y P2 de 1→2, y el nivel de la
pistola sube en ambos por igual.

## Selección de cartas con P2 (gamepad)

Al mostrar las cartas en coop, el HUD da **foco** a la primera carta. El P2 navega con
`ui_left`/`ui_right` (dpad/stick) y confirma con `ui_accept` (**A**). El P1 sigue usando
el ratón. Cualquiera elige **una** carta para el equipo; `UpgradeManager` ya evita la
doble aplicación (`_selection_active` se apaga tras elegir), así que no hay cartas
aplicadas dos veces ni cierres a medias. En Solo no se toca el foco.

## Balance coop (parámetros editables)

- **PlayerManager** (`@export`): `coop_player_damage_multiplier = 0.85`,
  `soft_distance_limit = 700`, `hard_distance_limit = 950`, `leash_correction = 0.14`,
  `offscreen_margin = 54`, `revive_radius/time/health_percent`.
- **MapManager** (`@export`, grupo *Balance coop*): `coop_pressure_multiplier = 1.25`,
  `coop_enemy_health_multiplier = 1.45`, `coop_enemy_damage_multiplier = 1.15`.
- **EnemySpawner** (`@export`, grupo *Balance coop*): `coop_score_bonus = 3.0`,
  `coop_max_enemies_bonus = 25`, `coop_cap_bonus = 30`.
- **Boss** / **MiniBoss** (`@export`): `coop_health_mult = 1.55` / `1.45`.

## HUD coop

Overlay ligero de `PlayerManager` (no toca `hud.gd`): estado de P1 y P2 (vida /
DERRIBADO), aviso + barra de revive, aviso de separación y flechas fuera de cámara. El
resumen de fin de partida muestra **"· Coop local"**.

## Pausa desde control

`p2_pause` (Start/Options, botón 6). `pause_menu.gd` abre/cierra la pausa con ESC (P1) o
`p2_pause` (P2). No interfiere con la selección de cartas ni con el fin de partida.

## Compañeros y jefes en coop

- Compañeros: pertenecen al equipo, siguen al **líder activo**, el médico cura al más
  herido, y **cualquier** jugador puede revivir compañeros. El *Vínculo felino* (bono de
  colonia) se aplica a **todos** los jugadores.
- Jefes/mini-jefes: persiguen al **jugador activo más cercano** (ignoran derribados), su
  embestida apunta a un jugador vivo, escalan de vida en coop, y todas las armas de
  ambos jugadores + compañeros les hacen daño. Si ambos caen → Game Over.

---

## Regulador de dificultad de Partida libre

Partida libre tiene ahora un **regulador de dificultad** análogo al de Historia
(**Fácil / Intermedio / Difícil / Extremo**), además del Nivel de Plaga (que sigue
siendo el eje de rejugabilidad/desbloqueo). Usa la misma tabla que Historia
(`StoryCampaign.DIFFICULTIES`): multiplica presión, vida, velocidad y daño de los
enemigos, y la recompensa de sardinas.

- Se elige en el selector de mapas (barra de ajustes, segmentado) y **persiste** en el
  save (`free_play_difficulty`, vía `GameFlow.set_free_play_difficulty`).
- Se aplica en `MapManager` para partida libre: multiplica los modificadores del spawner
  y, en victoria, la recompensa (desglose "Bonus de dificultad").
- Se combina de forma multiplicativa con la Plaga y con los multiplicadores coop.
- Por defecto **Intermedio**: el combate queda idéntico al clásico (mults 1.0) y la
  recompensa x1.3. *Fácil* baja la presión; *Difícil/Extremo* la suben.

Validado headless: en coop + Extremo, el multiplicador de vida de enemigos resultó 2.175
(coop 1.45 × Extremo 1.50).

## UI coop rediseñada

- **Roster de equipo** (abajo a la izquierda): un panel estilizado con una fila por
  jugador — icono de color, etiqueta P1/P2 y **barra de vida** (verde→ámbar→rojo según
  la vida, texto `x/y`). En DERRIBADO la barra se vacía en rojo y muestra "DERRIBADO".
  Se actualiza cada frame sin crear nodos (nodos preasignados una vez).
- **Barra de ajustes del menú de mapas** (Modo + Dificultad): controles segmentados con
  estilo propio (el seleccionado se resalta con borde/relleno), aviso de gamepad y una
  línea que describe los multiplicadores de la dificultad elegida.

## Navegación de menús con gamepad (P2)

Al abrir la **pausa** y los paneles de **victoria/derrota**, el primer botón recibe el
**foco**, de modo que el P2 puede navegar con el dpad/stick (`ui_up/down`) y confirmar
con **A** (`ui_accept`). El P1 sigue usando el ratón. Junto con `p2_pause` (Start), el P2
ya controla pausa, reanudar, reintentar, mejoras y volver al menú.

---

## Cómo probar

**Solo (no debe romperse):** Jugar → *Solo* → elige dificultad → jugar. Movimiento,
armas, cartas, compañeros, jefes, mapas, R para reiniciar. Igual que antes (Intermedio
mantiene el combate clásico).

**Coop:**
1. Jugar → *Cooperativo local* → jugar. Aparecen P1 y P2.
2. **Cámara/leash:** sepárense; a ~700 px aparece "¡No se separen!"; a ~950 px la correa
   los frena suavemente.
3. **Indicador fuera de cámara:** que un jugador se quede muy atrás; aparece su flecha en
   el borde con su color.
4. **Cartas con P2:** al subir de nivel, el P2 mueve la selección con el dpad/stick y
   confirma con A.
5. **Armas de P2:** elige una carta de arma nueva y confirma que P2 también dispara con
   ella.
6. **Pausa con P2:** pulsa Start/Options en el gamepad.
7. **Revive:** deja caer a un jugador y revive con el otro (2 s de proximidad).
8. **Game Over:** deja caer a ambos.

**Validación headless (Godot 4.7):** se ejercitó spawn de 2 jugadores, grupos correctos,
daño coop (0.85) en ambos, espejado de armas (P1/P2 1→2 y niveles iguales), leash
(2000→950 px), jefe coop (vida 1400→3038, targeting, se detiene al caer el equipo) y
team-wipe → Game Over. Solo: `MainLevel` 2400 frames sin errores ni fugas.

---

## Estado: pulido y estable

Los puntos que en la primera pasada quedaron como riesgo/limitación ya están resueltos:

- **P2 navega los menús** (pausa y fin de partida) con el gamepad — foco inicial + `A`.
- **HUD coop ordenado**: barras de vida estilizadas por jugador (P2 incluido).
- **Regulador de dificultad** también en Partida libre (Fácil..Extremo).
- **Cámara legible**: zoom acotado (1.0–1.35) + correa suave (`lerp`) + indicadores
  fuera de cámara reutilizados (sin crear nodos por frame).
- **Rendimiento**: overlay coop con nodos preasignados; sin tweens sin limpiar; una sola
  cámara `current` en coop (`CoopCamera.make_current()`).

**Decisiones de diseño (no bugs):** XP/nivel/cartas y armas son **compartidos** por
diseño coop (P1 y P2 espejados); cualquier jugador elige la carta del equipo (sin
votación ni doble cursor, y el `UpgradeManager` evita la doble aplicación).

### Camino hacia COOP 2.0 (fuera de alcance de esta fase)
- *Builds* separadas por jugador (contradice XP/cartas compartidas; sería un modo aparte).
- Coop **online**/Steam/lobbies: la separación por `player_id`, el grupo `"players"` y el
  `PlayerManager` como autoridad dejan el terreno preparado.
