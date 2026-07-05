# FASE 03 - Sistema de Companeros Rescatables

## Que se implemento

- Sistema de gatos companeros rescatables durante la partida.
- Tres tipos iniciales: `Gato Policia`, `Gato Medico` y `Gato Ingeniero`.
- `CompanionManager` para instanciar, registrar y ordenar la formacion.
- `RescueSpawner` con ventanas de aparicion progresivas y maximo de 4 companeros.
- `RescuePoint` con canalizacion de 1 segundo, cancelable al salir del area.
- Integracion con HUD, upgrades y dificultad dinamica.

## CompanionData

Archivo base: [scripts/companions/companion_data.gd](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/scripts/companions/companion_data.gd)

Recursos iniciales:

- [data/companions/police_cat.tres](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/data/companions/police_cat.tres)
- [data/companions/medic_cat.tres](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/data/companions/medic_cat.tres)
- [data/companions/engineer_cat.tres](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/data/companions/engineer_cat.tres)

Parametros disponibles:

- `id`
- `display_name`
- `role`
- `max_health`
- `move_speed`
- `follow_distance`
- `attack_damage`
- `attack_cooldown`
- `attack_range`
- `projectile_speed`
- `heal_amount`
- `heal_cooldown`
- `visual_color`
- `accent_color`
- `detail_color`
- `spawn_weight`

## CompanionManager

Archivo: [scripts/companions/companion_manager.gd](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/scripts/companions/companion_manager.gd)

Responsabilidades:

- Mantener el conteo de companeros.
- Limitar el maximo a `4`.
- Instanciar `Companion.tscn`.
- Aplicar bonuses de upgrades existentes y futuros.
- Recalcular la formacion alrededor del jugador cada frame.
- Emitir `companions_changed` para sincronizar el HUD.

Parametros clave:

- `max_companions = 4`
- `formation_radius = 70.0`
- `follow_smoothness = 5.0`
- `companion_spacing = 22.0`

## RescuePoint

Archivos:

- [scenes/companions/RescuePoint.tscn](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/scenes/companions/RescuePoint.tscn)
- [scripts/companions/rescue_point.gd](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/scripts/companions/rescue_point.gd)

Funcionamiento:

- Tiene un `Area2D` de activacion.
- Al entrar el jugador empieza una canalizacion de `1.0` segundo.
- Si el jugador sale del area antes de terminar, el progreso se cancela.
- Al completarse, emite `rescue_completed` con el `CompanionData` y desaparece.

## RescueSpawner

Archivo: [scripts/companions/rescue_spawner.gd](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/scripts/companions/rescue_spawner.gd)

Reglas actuales:

- Primer rescate: `25-35s`
- Segundo rescate: `75-95s`
- Tercer rescate: `140-170s`
- Repeticion posterior: `90-120s` desde el ultimo rescate completado
- Distancia de spawn: `340-520 px` respecto al jugador
- Radio de seguridad simple frente a enemigos: `130 px`

Si el jugador ya tiene `4/4`, no aparecen mas puntos de rescate.

## Integracion con dificultad

Archivo tocado: [scripts/enemies/enemy_spawner.gd](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/scripts/enemies/enemy_spawner.gd)

El `difficulty_score` ahora suma:

```gdscript
+ _get_companion_count() * companion_weight
```

Valor actual:

- `companion_weight = 0.85`

Esto aumenta indirectamente:

- frecuencia de spawn
- maximo de enemigos vivos
- vida enemiga
- velocidad enemiga
- dano enemigo
- probabilidad de spawns al borde
- probabilidad de mini-oleadas

## Integracion con upgrades

Archivo tocado: [scripts/systems/upgrade_manager.gd](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/scripts/systems/upgrade_manager.gd)

Upgrades nuevos:

- `Garras coordinadas`: `+10% dano de companeros`
- `Formacion agresiva`: `companeros atacan 10% mas rapido`
- `Botiquin felino`: `Gato Medico cura +2`

## Como agregar nuevos gatos companeros

1. Crea un nuevo `.tres` en `data/companions/` usando `companion_data.gd`.
2. Ajusta `role` a un comportamiento soportado o amplia `scripts/companions/companion.gd`.
3. Agrega el recurso al array `companion_pool` del nodo `RescueSpawner` en [scenes/levels/MainLevel.tscn](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/scenes/levels/MainLevel.tscn).
4. Si hace falta una silueta distinta, modifica el tint o la geometria de [scenes/companions/Companion.tscn](/C:/Users/ad/Desktop/1_PROYECTOS/2026/cats-vs-zombie-dogs/scenes/companions/Companion.tscn).

## Como ajustar balance

Companeros:

- Dano y cadencia: recursos `*.tres`
- Curacion: `heal_amount`, `heal_cooldown`
- Movimiento/formacion: `CompanionManager`

Rescates:

- Tiempos: `RescueSpawner`
- Distancias seguras: `RescueSpawner`
- Maximo: `CompanionManager.max_companions`

Dificultad:

- Impacto de companeros: `EnemySpawner.companion_weight`

## Como probar la fase

Partida A:

- Inicia `MainLevel.tscn`.
- Sobrevive `25-35s`.
- Verifica que el HUD muestre `Rescate disponible`.
- Encuentra el punto y completa el canalizado.

Partida B:

- Rescata `2` o `3` gatos.
- Revisa que la formacion se redistribuya sin montarse encima del jugador.

Partida C:

- Deja al jugador con vida incompleta.
- Espera al `Gato Medico`.
- Confirma que cura por pulsos y no cura si la vida ya esta llena.

Partida D:

- Rescata `Gato Policia` y `Gato Ingeniero`.
- Observa proyectiles contra el enemigo mas cercano.
- Verifica que el ingeniero dispare mas lento pero pegue mas fuerte.

Partida E:

- Llega a `4/4`.
- Confirma que no vuelve a aparecer otro rescate.

Partida F:

- Muere.
- Pulsa `R`.
- Verifica que el conteo vuelve a `0/4` y no quedan rescue points ni companeros.

Partida G:

- Compara los primeros minutos sin rescates vs con `3` companeros.
- Confirma que la intensidad sube antes con companeros.

## Riesgos conocidos

- La formacion es deliberadamente liviana: sigue slots alrededor del jugador, sin pathfinding.
- El rescue point evita enemigos cercanos con una comprobacion simple, no con navegacion.
- Los companeros no tienen vida propia todavia; en esta fase funcionan como apoyo estable.

## Pendiente para Fase 04

- Roles mas avanzados o habilidades activas.
- Indicador direccional hacia el rescue point.
- Tipos de rescue point con mas identidad visual.
- Progresion mas profunda de colonia, sin romper el survivor base.
