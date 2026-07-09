# Fase Coop Local — 2 jugadores en la misma pantalla

Modo cooperativo **local** (sin red, sin Steam, sin lobbies) para *Cats vs Zombie Dogs*.
Añade una segunda modalidad de juego manteniendo el **modo Solo intacto**.

- **Solo:** un jugador, exactamente como siempre.
- **Cooperativo local:** dos jugadores en la misma pantalla. P1 con teclado, P2 con
  gamepad (o IJKL de respaldo). Comparten XP y nivel, se reviven mutuamente y la
  dificultad escala para compensar.

Diseño clave: **todo lo coop se activa solo si `GameFlow.is_coop()`**. En Solo no
cambia ningún comportamiento. El Jugador 1 sigue siendo el nodo `Player` de la escena
y sigue en el grupo `"player"`; los sistemas clásicos no notan la diferencia.

---

## Cómo activar el modo coop

1. Menú principal → **Jugar** → selector de zonas (`MapSelectMenu`).
2. Arriba aparece **Modo: [ Solo ] [ Cooperativo local ]**.
3. Elige *Cooperativo local*. Si no hay gamepad conectado, se muestra el aviso
   *"Conecta un control para el Jugador 2 (o usa IJKL)"*.
4. Pulsa **Jugar** en la zona deseada. El modo se envía a `GameFlow.set_game_mode()`
   antes de `start_run()`. El P2 se instancia automáticamente al cargar el nivel.

El **Modo Historia siempre es Solo** (se fuerza en `GameFlow.start_story_chapter`).

---

## Controles

### Jugador 1 (teclado) — sin cambios
- Movimiento: **WASD** o **flechas**.
- Reiniciar tras terminar: **R**. Pausa/volver: **Esc**.

### Jugador 2 (gamepad, recomendado)
- Movimiento: **stick izquierdo**.
- Respaldo de teclado si no hay control: **I / J / K / L**.
- Acciones (`p2_join`, `p2_action`): botón **A / Cross**.

El revive **no** necesita botón: se hace por proximidad (ver abajo).

Las acciones nuevas viven en `project.godot`: `p2_move_left/right/up/down`,
`p2_join`, `p2_action`. Las acciones de P1 no se tocaron.

---

## Arquitectura

### `PlayerManager` (`scripts/systems/player_manager.gd`)
Nodo de `MainLevel` que coordina a los jugadores.
- **Solo:** registra al único jugador y no hace nada más.
- **Coop:** instancia al P2 (misma `Player.tscn`, `player_id = 2`), monta la cámara
  cooperativa, crea el overlay de HUD coop, aplica la dificultad coop y gestiona el
  revive por proximidad.
- Expone: `get_active_players()`, `get_downed_players()`, `all_downed()`,
  `team_center()`, `revive_fraction(player)`.
- **Game Over del equipo:** cuando todos están derribados llama a
  `Player.force_team_death()` del P1, que emite la señal `died` clásica. Así reutiliza
  el Game Over existente (`GameManager` + `MapManager`) sin cablear nada nuevo.
- El arranque coop se **difiere** (`call_deferred`) porque `MainLevel` aún está
  instanciando hijos en `_ready` y no admite `add_child`.

### `Player` (`scripts/player/player.gd`) — parametrizable
- `player_id` (1 = teclado/principal, 2 = gamepad). Elige el perfil de input.
- Grupos: **todos** los jugadores entran en `"players"`; **solo el P1** entra en
  `"player"` (singular), para no romper los sistemas clásicos que esperan un jugador.
- Estados: activo / **derribado** (`_is_downed`) / muerto. `is_active()`, `is_downed()`.
- `_go_downed()` (coop): 0 de vida → derribado en vez de morir. Detiene movimiento,
  **apaga el WeaponManager** (`process_mode`), bloquea recogida de XP.
- `revive_player(percent)`: reactiva con % de vida (40% por defecto) + breve invuln.
- P2 tiene **look distinto**: tinte frío + etiqueta flotante "P2".

### XP y nivel compartidos
La XP es **compartida**: cuando el P2 recoge un orbe, `Player.add_experience` la
reenvía al portador de nivel del equipo (el P1, único que está en el grupo `"player"`
y emite las cartas de mejora). Así **nivel y cartas nunca se duplican**. La subida de
nivel, la pausa y la selección de 3 cartas funcionan igual que en Solo; **la selección
la hace el P1** (ratón/teclado) — ver *Limitaciones*.

### Cámara coop (`scripts/systems/coop_camera.gd`)
Solo se instancia en coop. Extiende `camera_effects.gd`, así que **hereda el screen
shake** (`Feedback.shake` sigue funcionando). Sigue el **punto medio** de los jugadores
activos y ajusta el zoom suavemente: se separan → zoom out; se juntan → zoom in.
Valores: `max_zoom 1.35`, `min_zoom 1.0`, `zoom_smoothness 4.0`, `follow_smoothness 5.0`,
`max_allowed_distance 900`. En Solo se sigue usando la cámara hija del `Player`.

### Revive de jugadores
Gestionado por `PlayerManager._update_revive`:
- Un jugador derribado muestra el aviso *"Px derribado — acércate para revivir"*.
- Si el otro jugador (vivo) permanece dentro de `revive_radius` (74 px), el progreso
  sube; al llegar a `revive_time` (2.0 s) revive con `revive_health_percent` (40%).
- Si el rescatador se aleja, el progreso se cancela.
- No revive si: ambos derribados, la partida terminó, o ya fue revivido.
- El overlay muestra una **barra de progreso** y *"Reviviendo Px..."*.

### Enemigos y targeting (`scripts/enemies/enemy.gd`)
Cada enemigo persigue al **jugador ACTIVO más cercano** (grupo `"players"`, ignorando
derribados/muertos). Si no hay ninguno, cae al grupo `"player"` (compat. Solo). El
daño por contacto y la persecución de compañeros no cambian.

### Dificultad coop (sección 13)
- `EnemySpawner.set_coop_players(2)`: suma un bono constante al `difficulty_score`
  (`+2.5`) y sube los techos de enemigos (`base_max_enemies +20`, caps `+30`).
- `MapManager` (partida libre) multiplica al pasar los modificadores al spawner:
  vida `×1.35`, daño `×1.10`, presión/spawn `×1.20`. Se combina con Nivel de Plaga.

### HUD coop
Overlay ligero creado en runtime por `PlayerManager` (no se tocó `hud.gd`, para no
arriesgar el Solo). Muestra estado de P1 y P2 (vida / DERRIBADO) y el aviso+barra de
revive. El HUD principal (objetivos, armas, boss bar, compañeros, resumen) sigue igual.

### Reinicio y limpieza
El reinicio (**R**) recarga la escena vía `GameFlow.restart_run()` → todo se reconstruye
limpio: P1, P2 (instanciado de nuevo), cámara coop, overlay, armas, enemigos, señales.
No quedan duplicados porque el P2/cámara/overlay son hijos de la escena (o de nodos de
la escena) y se liberan con ella. El `game_mode` se conserva entre reinicios.

### Armas y compañeros
- **Armas:** cada jugador tiene su propio `WeaponManager` (hijo de su `Player`) y ambos
  disparan solos. **Solo el manager del P1 se conecta al HUD** (para no pisar la barra
  de armas). Las cartas de arma se aplican al arma del P1 (ver *Limitaciones*).
- **Compañeros:** `CompanionManager` sigue siendo del equipo, sin cambios. Persiguen
  al jugador principal, y el sistema de rescate/revive de compañeros no se tocó.

---

## Cómo probar

### Modo Solo (no debe romperse)
1. Jugar → dejar **Solo** → elegir zona → jugar. Debe funcionar exactamente como antes:
   movimiento, armas, compañeros, jefes, mapas, subir de nivel, R para reiniciar.

### Modo Coop
1. Jugar → **Cooperativo local** → jugar. Aparecen dos gatos (P2 con tinte azul y "P2").
2. P1 se mueve con WASD; P2 con el stick del gamepad (o IJKL).
3. La cámara sigue a ambos y hace zoom out al separarse.
4. Ambos disparan solos; la XP sube compartida; al subir de nivel salen 3 cartas.
5. Deja caer a un jugador → queda DERRIBADO. Acerca al otro 2 s → revive al 40%.
6. Deja caer a ambos → **Game Over**.

### Validación automática (headless)
Se validó con Godot 4.7 headless:
- **Solo:** `MainLevel` 2000 frames, sin errores ni fugas.
- **Coop:** spawn de 2 jugadores, derribo, revive por proximidad completado, y
  team-wipe → Game Over (`get_tree().paused` + `MapManager.is_run_ended()`), sin errores.

---

## Riesgos conocidos y limitaciones actuales

- **Selección de cartas de nivel:** la hace el P1 (ratón/teclado). El P2 no puede elegir
  la mejora todavía. Documentado como decisión segura (sección 9 del brief).
- **Cartas de arma:** se aplican al `WeaponManager` del P1. El P2 conserva su arma
  inicial (Pistola Gatuna) y dispara con ella. Las mejoras de stat globales (daño,
  cooldown, etc.) sí afectan al arma de cada jugador si provienen de bonus permanentes
  del refugio (cada `Player` los aplica a sí mismo, **sin duplicar**).
- **Balance:** el multiplicador de daño por jugador (`0.85`) sugerido en el brief **no**
  se aplicó todavía; en su lugar la dificultad sube (vida/daño/presión + bono de score).
  Queda como ajuste de una fase de pulido.
- **Jefes:** persiguen al jugador vivo más cercano (usan el mismo grupo `"players"` vía
  el objetivo del enemigo base cuando aplica), pero **no** se les aplicó multiplicador de
  vida coop específico todavía (sí el escalado global de dificultad). Revisar en pulido.
- **Sardinas / save:** el guardado sigue siendo uno solo; las recompensas **no** se
  duplican por tener dos jugadores.
- **Cámara coop y shake:** el shake se aplica a la cámara coop (hereda el trauma), pero
  ambas cámaras (P1 y coop) están en el grupo `screen_shake`; solo la actual renderiza.

---

## Camino hacia una fase COOP 1.5 (pulido)

1. Permitir que el P2 elija cartas de nivel (foco de UI navegable por gamepad).
2. Cartas de arma por jugador (que el P2 también suba/añada armas).
3. Multiplicador de daño por jugador (`0.85`) + tuning fino del balance coop.
4. Multiplicadores de vida específicos para jefes/mini-jefes en coop.
5. Indicador visual de "jugador fuera de pantalla" y empuje suave al separarse de más.
6. Pausa desde cualquier control; resumen post-partida mostrando "Modo: Coop local".
7. Base para una futura **fase COOP online** (la separación por `player_id`, el grupo
   `"players"` y el `PlayerManager` ya dejan el terreno preparado).
