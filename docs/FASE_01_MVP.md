# FASE 01 — MVP (Prototipo mínimo jugable)

Documento técnico de la primera fase de **Cats vs Zombie Dogs**.

---

## 1. Qué se implementó

Un loop de juego survivor completo y jugable con placeholders:

1. El gato jugador aparece en el centro y se mueve con WASD / flechas.
2. Un spawner genera perros zombis en un anillo alrededor del jugador.
3. Los perros persiguen constantemente al gato.
4. El gato dispara **automáticamente** al enemigo más cercano dentro de rango.
5. Las balas dañan y matan a los enemigos.
6. Los enemigos sueltan orbes de experiencia al morir.
7. El gato recoge la experiencia con un área de recolección.
8. Al acumular suficiente XP, el jugador sube de nivel (la XP necesaria crece).
9. El HUD muestra vida, nivel, XP y tiempo de supervivencia.
10. Al contacto con perros el gato pierde vida (con cooldown anti-spam de daño).
11. Al llegar a 0 de vida aparece **GAME OVER**.
12. Con `R` se reinicia la escena.

Todo con formas geométricas (`Polygon2D` / `ColorRect`). Sin assets, audio ni arte final.

## 2. Archivos creados

### Scripts (`scripts/`)
| Archivo | Rol |
|---|---|
| `player/player.gd` | Movimiento, vida, XP, niveles, daño con cooldown, señales. |
| `enemies/enemy.gd` | Persecución, vida, daño por contacto, muerte y drop de XP. |
| `enemies/enemy_spawner.gd` | Genera enemigos en anillo, límite de vivos, conteo. |
| `weapons/auto_weapon.gd` | Busca al enemigo más cercano y dispara con cooldown. |
| `weapons/projectile.gd` | Bala recta, daño al impactar, autodestrucción por tiempo. |
| `loot/xp_orb.gd` | Orbe de experiencia recogible. |
| `systems/game_manager.gd` | Estado de partida, tiempo, game over y reinicio. |
| `ui/hud.gd` | Pinta vida / nivel / XP / tiempo y panel de game over. |

### Escenas (`scenes/`)
| Archivo | Contenido |
|---|---|
| `player/Player.tscn` | CharacterBody2D + placeholder gato, PickupArea, AutoWeapon, Camera2D. |
| `enemies/Enemy.tscn` | CharacterBody2D + placeholder perro zombi (en grupo `enemies`). |
| `weapons/Projectile.tscn` | Area2D + forma de bala. |
| `loot/XPOrb.tscn` | Area2D + orbe. |
| `ui/HUD.tscn` | CanvasLayer con labels y panel Game Over. |
| `levels/MainLevel.tscn` | Ensambla todo y cablea señales. Escena principal. |

### Otros
- `README.md` — guía de uso.
- `docs/FASE_01_MVP.md` — este documento.
- `project.godot` — se **añadió** el InputMap (move_*, restart) y `run/main_scene`.

## 3. Cómo funciona cada sistema

### Movimiento del jugador
`Input.get_vector("move_left","move_right","move_up","move_down")` da un vector
normalizado; `velocity = dir * speed` + `move_and_slide()`.

### Vida y daño con cooldown
`take_damage()` ignora golpes mientras `_damage_timer > 0`. Esto evita perder vida
cada frame cuando un perro está encima; el ritmo de daño lo marca `damage_cooldown` (~0.5s).

### Experiencia y niveles
`add_experience()` acumula XP; al alcanzar `experience_to_level` sube de nivel y la
meta crece ~40% (`experience_growth = 1.4`). Cada cambio emite señales para el HUD.

### Spawner
Un `Timer` interno dispara cada `spawn_interval`. Calcula un punto aleatorio en el
anillo `[min_radius, max_radius]` alrededor del jugador (nunca encima) y respeta
`max_enemies`. Mantiene un contador de vivos y lo decrementa al recibir la señal
`died` de cada enemigo.

### Arma automática
Cada `fire_cooldown`, recorre el grupo `enemies`, elige el más cercano dentro de
`attack_range` y dispara un `Projectile` configurado con dirección, velocidad y daño.

### Proyectil
Se mueve recto en `_physics_process`. `body_entered` (Area2D → cuerpo enemigo en la
máscara) aplica daño y se autodestruye. Un `SceneTreeTimer` lo elimina tras `lifetime`
si no impacta. `is_instance_valid` evita errores si el enemigo ya desapareció.

### Orbe de XP
`Area2D` en el grupo `xp_orbs`. El `PickupArea` del jugador lo detecta por
`area_entered`; el jugador llama a `collect()`, recibe la XP y el orbe se libera.

### Game Manager
Máquina de estados simple `PLAYING / GAME_OVER`. Lleva el tiempo en `_process`,
escucha `Player.died`, avisa al HUD y, en `GAME_OVER`, reinicia con la acción `restart`.

### Comunicación (bajo acoplamiento)
- El jugador y los enemigos se localizan por **grupos** (`player`, `enemies`), no por rutas.
- El HUD se actualiza solo por **señales**; no consulta el estado del juego.
- El GameManager recibe `player_path` / `hud_path` por `@export` desde la escena.

### Capas de colisión usadas
| Capa | Uso |
|---|---|
| 1 | Player (cuerpo) |
| 2 | Enemy (cuerpo, detectado por balas) |
| 4 | (reservada para proyectiles) |
| 8 | XPOrb (detectado por el PickupArea) |

Los cuerpos no se empujan físicamente (máscaras a 0): el daño es por proximidad,
lo que mantiene el movimiento de enjambre fluido.

## 4. Pendiente para la FASE 02

- **Selección de mejoras al subir de nivel** (elegir 1 de 3 upgrades).
- **Más armas y patrones de disparo**; sistema de armas extensible.
- **Más tipos de enemigos** y escalado de dificultad por tiempo (oleadas crecientes).
- **Menú principal y pausa**.
- Pulido visual del fondo (grid/parallax) y feedback de impacto (flash, knockback).

## 5. Recomendaciones para la siguiente fase

- Convertir el HUD y el GameManager en piezas reutilizables; valorar un **autoload**
  ligero solo si varios sistemas necesitan estado global (no antes de necesitarlo).
- Definir un **recurso de datos de enemigo** (`Resource` con vida/velocidad/daño/XP)
  para crear variantes sin duplicar escenas.
- Introducir un sistema de **armas como nodos hijos intercambiables** del AutoWeapon
  actual, manteniendo la interfaz `setup()` del proyectil.
- Sustituir el daño por proximidad por hurtbox/hitbox dedicadas solo si se necesita
  precisión por forma; para enjambres, la proximidad es suficiente y barata.
- Mantener la separación por señales: facilita añadir guardado y métricas más adelante.
