# Cooperativo local — arquitectura y balance

## Arquitectura (resumen)
- `GameFlow.is_coop()` es el único interruptor: en solo NO se crea nada del sistema coop.
- `PlayerManager` (nodo de MainLevel): spawnea al P2, monta la pantalla dividida,
  gestiona revive por proximidad, bonus de cercanía, desconexión de mando y game over de equipo.
- `CoopSplitScreen` (scripts/systems/coop_split_screen.gd): dos `SubViewport` que
  COMPARTEN `world_2d` (una sola física/lógica, dos renders), cada uno con su `SplitCamera`.
  La cámara del viewport raíz queda "aparcada" con zoom extremo (`ROOT_CAMERA_PARK_ZOOM`)
  para que el render tapado del raíz cueste ~nada.
- `CoopUpgradePanel`: cartas independientes y simultáneas; J1 teclado/ratón (su lado),
  J2 gamepad/teclado derecho; el ratón no puede tocar el lado de J2.
- `UpgradeManager` (flujo coop): cola de pendientes por jugador; un jugador derribado
  NO abre cartas (se difieren y se reabren al revivir); la pausa depende SOLO de
  paneles abiertos.

## Configuración central: `scripts/systems/coop_config.gd`
Todos los números de balance coop viven en `CoopConfig`:

| Valor | Default | Qué controla |
|---|---|---|
| `XP_COLLECTOR_SHARE` | 0.75 | XP para quien recoge el orbe (antes 1.0) |
| `XP_PARTNER_SHARE` | 0.35 | XP para el compañero (antes 0.5) |
| `XP_SHARE_FULL_DIST` / `ZERO_DIST` | 900 / 2600 px | decaimiento lineal del share por distancia |
| `PROXIMITY_RADIUS` | 340 px | radio del bonus de "juntos" |
| `PROXIMITY_REGEN_INTERVAL` / `AMOUNT` | 4 s / 1 HP | regen lenta al estar juntos |
| `RESCUER_XP_REWARD` | 8 XP | premio directo al completar un rescate |
| `REVIVE_INVULN_SECONDS` | 1.5 s | invulnerabilidad al levantarse |
| `CARD_AUTO_PICK_SECONDS` | 25 s | auto-selección por inactividad (0 = off) |
| `CARD_SLOWDOWN_ENABLED` / `SCALE` | false / 0.25 | cámara lenta en vez de pausa durante cartas |
| `SPLIT_BASE_ZOOM` | 0.95 | zoom de cada mitad (lo usa también el spawner) |
| `ROOT_CAMERA_PARK_ZOOM` | 16 | zoom de aparcado de la cámara raíz en coop |

Fórmula de XP coop: `recolector = round(XP * 0.75)`,
`compañero = ceil(XP * share(d))` con `share(d) = 0.35` hasta 900 px y decayendo
lineal a 0 en 2600 px. Total del equipo: ~110 % (antes 150 %).

Dificultad coop (en `EnemySpawner`): `set_coop_players(2)` suma
`GameBalance.COOP_SCORE_BONUS` al score de dificultad y amplía los topes
(`coop_max_enemies_bonus`, `coop_cap_bonus`). Fase corrección: la presión coop
entra SOLO por ese bono (antes además se multiplicaba todo el score por 1.25) y
vida/daño coop bajaron a x1.30/x1.10 (`GameBalance.COOP_ENEMY_*`).
Daño por jugador: ×0.9 (`coop_player_damage_multiplier` en PlayerManager).

## Identidad de jugadores (daltonismo)
Además del color (J1 naranja / J2 azul): icono por jugador (`▲J1` / `●J2`) en placas,
cabeceras del split y títulos de cartas; anillo CONTINUO para J1 y SEGMENTADO para J2.

## Tests
- `tests/TestCoop.tscn` — integración (estructura, cartas, XP 35 %, simultáneo,
  revive + recompensa, diferido por derribo). 45 checks.
- `tests/TestCoopSoak.tscn` — estrés 2400 frames con informe: fps min/avg,
  máximos de enemigos/proyectiles/orbes/nodos, memoria y nodos huérfanos.
- Ejecutar: `godot --headless --path . res://tests/TestCoop.tscn`
