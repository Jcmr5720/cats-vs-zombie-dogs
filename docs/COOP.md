# Cooperativo local — arquitectura y balance

## Arquitectura (resumen)
- `GameFlow.is_coop()` es el único interruptor: en solo NO se crea nada del sistema coop.
- `PlayerManager` (nodo de MainLevel): spawnea al P2, monta la pantalla dividida,
  gestiona revive por proximidad, bonus de cercanía, desconexión de mando y game over de equipo.
- `CoopSplitScreen` (scripts/systems/coop_split_screen.gd): dos `SubViewport` que
  COMPARTEN `world_2d` (una sola física/lógica, dos renders), cada uno con su `SplitCamera`.
  La cámara del viewport raíz queda "aparcada" con zoom extremo (`ROOT_CAMERA_PARK_ZOOM`)
  para que el render tapado del raíz cueste ~nada.
- **Botín compartido (FASE 12):** ya no hay cartas ni panel coop. El poder se
  recoge del suelo y rige "primero que llega, se lo lleva": `GroundPickup.claim()`
  garantiza que un power-up lo cobre un solo jugador aunque ambos entren el mismo
  frame. Los power-ups de compañero pegan al `CompanionManager` compartido; el
  resto solo al recolector. Presupuesto de drops `× LOOT_MULTIPLIER` (1.7), no 2×.
  Un jugador derribado no cobra botín (ni XP).

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
| `LOOT_MULTIPLIER` | 1.7 | cantidad de botín en coop (FASE 12; un presupuesto compartido, no 2×) |
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
Además del color (J1 naranja / J2 azul): icono por jugador (`▲J1` / `●J2`) en placas
y cabeceras del split; anillo CONTINUO para J1 y SEGMENTADO para J2.

## Puntería (`scripts/player/player_aim_controller.gd`)
El **autodisparo no cambia**: nunca se pulsa un botón para disparar. Lo único que
decide el jugador es la DIRECCIÓN. Cada jugador tiene su propio controlador, su
modo, su dispositivo y su retícula. **Nada está atado al número de jugador.**

### Tres modos, por jugador
| Modo | Quién decide | Consulta enemigos |
|---|---|---|
| **Manual** (defecto) | solo el jugador | no (las armas disparan a la mira) |
| **Asistido** | el jugador, con corrección dentro de un cono | 1 consulta / 20 Hz en el controlador |
| **Automático** | el `Targeting` clásico | igual que siempre, por arma |

Ajustes (`SettingsManager`, uno por jugador, nunca global):
`player_N_aim_mode` (`manual`|`assist`|`auto`), `player_N_aim_assist`
(`off`|`baja`|`media`|`alta` → medio ángulo del cono, en `ASSIST_CONE_DEGREES`) y
`player_N_aim_device` (`auto`|`mouse`|`gamepad`|`keyboard`). Se cambian en
Opciones → Controles y en la pausa, con efecto inmediato (`settings_changed`).

### Dispositivos
Con `device = auto` cada jugador **reclama** el dispositivo que usa: ratón (solo uno
puede tenerlo), mando (por `device id`, así dos mandos apuntan por separado) o
teclado (acciones `pN_aim_*`, remapeables e independientes del movimiento). El stick
derecho se lee con `Input.get_joy_axis(device, JOY_AXIS_RIGHT_X/Y)` — no por acción
compartida — con zona muerta que **conserva la última dirección** (`stick_direction`).

Teclas de apuntado por defecto: J1 = numpad 8/4/6/2, J2 = flechas. En teclado
compartido las flechas son además el binding secundario de mover J1: remapear en
Opciones → Controles.

### Ratón y pantalla dividida
El cursor **no se bloquea** (los menús lo necesitan libre). Lo acotado es su
*interpretación*: `CoopSplitScreen.screen_to_world(index, pos)` traduce con la cámara
de esa mitad, y si el cursor está en la otra mitad (`contains_point`) el controlador
simplemente **conserva la última dirección válida**.

### Retículas
Una por jugador, dibujada en el mundo con el color del jugador. En split ambas
mitades comparten `world_2d`, así que cada retícula usa su propia
`visibility_layer` y cada `SubViewport` apaga la del compañero vía `canvas_cull_mask`:
nunca se duplica ni aparece en la pantalla equivocada. Con asistencia enganchada se
cierra y añade un anillo interior; en automático no se dibuja.

### Armas
- **Direccionales** (`projectile`, `explosive`, `boomerang`, `laser`): usan la mira.
  El láser es hitscan, así que en manual golpea al primero que cruza el corredor del
  haz (`Targeting.pick_first_in_beam`, ancho físico — no es asistencia).
- **Colocadas** (`area`, catnip): caen en el punto de mira, recortado al alcance.
- **No direccionales** (`orbital`): no consultan la mira en absoluto.
- **Guiadas**: categoría prevista, **hoy sin ninguna arma** (ningún proyectil tiene
  homing). Una futura debería salir con la dirección del jugador y adquirir objetivo
  después.
- **Compañeros y torreta**: conservan su propio auto-apuntado, sin tocar.

## Tests
- `tests/TestCoop.tscn` — integración (estructura, bonus de nivel independiente,
  botín compartido con guarda anti-doble-cobro, XP 35 %, simultáneo, revive +
  recompensa, un derribado no cobra botín).
- `tests/TestCoopSoak.tscn` — estrés 2400 frames con informe: fps min/avg,
  máximos de enemigos/proyectiles/orbes/nodos, memoria y nodos huérfanos.
- `tests/TestAim.tscn` — puntería: los tres modos, modos/dispositivos independientes
  por jugador, zona muerta del stick, histéresis de la asistencia, ida y vuelta
  pantalla↔mundo del split, armas no direccionales y compañeros.
- Ejecutar: `godot --headless --path . res://tests/TestCoop.tscn`

### Pruebas MANUALES pendientes (headless no tiene ratón ni mandos)
Ninguna de estas está verificada automáticamente:
1. Solo con ratón · 2. Solo con mando · 3. Coop ratón + mando · 4. Coop dos mandos ·
5. J1 mando + J2 teclado · 6. Manual → Asistido → Automático desde la pausa ·
7. Cursor cruzando entre las dos mitades · 8. Pausa con el cursor en la mitad
contraria · 9. Micromovimientos del stick (ruido) · 10. Desconectar y reconectar
mando · 11. Disparo recto · 12. Escopeta (proyectiles múltiples) · 13. Láser ·
14. Arma con penetración · 15. Arma de área · 16. Misil guiado (no existe hoy) ·
17. Compañeros · 18. Jugadores separados con split activo.
