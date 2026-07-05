# FASE 03.5 - Rediseno y Pulido Profundo del Sistema de Companeros

## Problemas detectados en Fase 03

- Los companeros ayudaban, pero su aporte costaba leerlo.
- El rescate no se sentia suficientemente importante.
- Los tres gatos no estaban lo bastante diferenciados.
- No existia riesgo tactico porque los companeros eran inmortales.
- El HUD de companeros solo mostraba cantidad, no estado.

## Nueva decision de diseno

Los companeros ya no son inmortales.

- Cada gato tiene vida propia.
- Puede recibir dano de los enemigos.
- Al llegar a `0`, entra en estado `derribado`.
- Un gato derribado deja de atacar, curar y seguir la formacion.
- El jugador puede revivirlo permaneciendo cerca.
- El revive usa canalizacion y lo devuelve con `40%` de vida.

No hay permadeath en esta fase.

## Estados de companero

- `active`: sano y operando normal.
- `hurt`: sigue activo, pero con vida baja.
- `downed`: caido, sin apoyo al combate.
- `reviving`: el jugador lo esta levantando.

La logica principal vive en [scripts/companions/companion.gd](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/scripts/companions/companion.gd).

## Vida de companeros

Datos editables en [scripts/companions/companion_data.gd](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/scripts/companions/companion_data.gd):

- `max_health`
- `damage_reduction`
- `revive_time`
- `revive_health_percent`
- `attack_damage`
- `attack_cooldown`
- `attack_range`
- `heal_amount`
- `heal_cooldown`
- `projectile_color`

Valores iniciales:

- Policia: `60` vida, `8` dano, `0.75` cooldown, `450` rango.
- Medico: `50` vida, `5` cura, `7.0` cooldown, `180` rango de soporte.
- Ingeniero: `55` vida, `16` dano, `1.3` cooldown, `560` rango.

## Como funciona el revive

- El companion derribado activa un `ReviveArea`.
- Si el jugador entra, comienza canalizacion.
- Tiempo base: `1.5s`.
- Si sale del area, se cancela.
- Al completar, revive con `40%` de vida.
- El revive puede mejorar con el upgrade `Rescate rapido`.

Manager relacionado: [scripts/companions/companion_manager.gd](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/scripts/companions/companion_manager.gd)

## RescuePoint mejorado

Archivos:

- [scripts/companions/rescue_point.gd](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/scripts/companions/rescue_point.gd)
- [scenes/companions/RescuePoint.tscn](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/scenes/companions/RescuePoint.tscn)

Mejoras:

- pulso visual
- glow y aro
- etiqueta flotante
- mensaje de deteccion
- flecha direccional en HUD
- mensaje breve de cancelacion

## HUD de companeros

Archivos:

- [scripts/ui/hud.gd](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/scripts/ui/hud.gd)
- [scenes/ui/HUD.tscn](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/scenes/ui/HUD.tscn)

Ahora muestra:

- `Gatos rescatados 0/4`
- cuatro slots de roster
- color por gato
- estado `ACTIVO / HERIDO / CAIDO / REVIVIENDO`
- barra de vida por companero
- mensajes de derribo y regreso al combate
- indicador de rescate activo

## Balance de dificultad con companeros

Archivo: [scripts/enemies/enemy_spawner.gd](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/scripts/enemies/enemy_spawner.gd)

Puntos clave:

- `companion_weight = 1.1`
- `downed_companion_weight = -0.3`
- con `2+` companeros sube el maximo de enemigos
- con `3+` companeros aumenta peso del runner
- con `4` companeros sube aun mas el maximo de enemigos

## Nuevos y revisados upgrades

Archivo: [scripts/systems/upgrade_manager.gd](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/scripts/systems/upgrade_manager.gd)

Ya presentes y mantenidos:

- `Garras coordinadas`
- `Formacion agresiva`
- `Botiquin felino`

Nuevos en 03.5:

- `Proteccion de colonia`
- `Rescate rapido`
- `Vinculo felino`

## Como agregar nuevos companeros

1. Crea un nuevo recurso `.tres` en `data/companions/`.
2. Usa [companion_data.gd](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/scripts/companions/companion_data.gd) como base.
3. Ajusta `role`, stats, colores y revive.
4. Agregalo al array `companion_pool` del `RescueSpawner` en [MainLevel.tscn](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/scenes/levels/MainLevel.tscn).
5. Si necesita otra conducta, extiende el `match` de rol en [companion.gd](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/scripts/companions/companion.gd).

## Parametros editables

Companeros:

- vida, dano, cooldown, rango, revive, reduccion de dano, colores

Manager:

- `max_companions`
- `formation_radius`
- `follow_smoothness`
- `companion_spacing`

Rescates:

- tiempos de spawn
- distancias de spawn
- radio seguro de enemigos
- `rescue_duration`

Dificultad:

- `companion_weight`
- `downed_companion_weight`
- maximos y wave chances del `EnemySpawner`

## Riesgos tecnicos

- Los enemigos siguen priorizando al jugador; la redireccion a companeros es simple y no usa IA compleja.
- La formacion sigue siendo ligera, sin pathfinding.
- El HUD de roster asume maximo `4` companeros en esta fase.

## Verificacion de runtime (post-pulido)

- El proyecto se valido en Godot 4.7 headless: import limpio y ciclo completo de
  companeros ejercitado (rescate de 3, derribo, revive al `40%`, maximo `4`, bonos de
  upgrades y limpieza al recrear el nivel) **sin errores de script**.
- **Importante**: el autotest de runtime NO debe registrarse como `[autoload]`. Un
  autoload de validacion acelera el tiempo (`time_scale = 20`), teletransporta al
  jugador y recarga la escena, dejando el juego injugable en una partida normal. Si se
  necesita un autotest, debe gatearse tras un flag de CLI (`--validate`) o ejecutarse
  como escena/`SceneTree` de prueba aparte, nunca en el arranque del juego.

## Como probar

Partida A:

- Espera el primer rescate.
- Confirma aviso, flecha, pulso y efecto de union.

Partida B:

- Rescata al medico.
- Baja vida del jugador y revisa que cure de forma visible.

Partida C:

- Deja que un companero reciba dano hasta caer.
- Revisa estado `CAIDO` y ausencia de apoyo.

Partida D:

- Acercate a un companero derribado.
- Mantente `1.5s`.
- Confirma revive al `40%`.

Partida E:

- Llega a `4/4`.
- Confirma que el juego se siente mas poderoso, pero con mas presion enemiga.

Partida F:

- Muere y reinicia con `R`.
- Verifica limpieza de companeros, rescue points, roster y mensajes.

Partida G:

- Compara visualmente policia, medico e ingeniero.
- Revisa silueta, colores, marcador de rol y color del proyectil.
