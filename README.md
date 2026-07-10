# Cats vs Zombie Dogs

Juego 2D top-down tipo **bullet heaven / survivor** para PC. Un gato lider
rescata otros gatos sobrevivientes mientras combate oleadas de perros zombis
mutantes en una ciudad abandonada. Tono arcade, caricaturesco y no realista.

> **Estado: FASE VISUAL 3 — UI premium.** Auditoría completa del stack de UI
> contra estándar Steam: logo compuesto de tres tonos con marca de garra en el
> menú principal, foco de gamepad visible en todas las variantes de botón,
> pestaña **Controles** en Opciones (referencia P1/P2/atajos) y foco inicial
> en selector de mapas y opciones. Cartas, HUD, resumen, refugio y selector ya
> cumplían el estándar (verificado). Detalle en
> [`docs/FASE_VISUAL_3_UI_PREMIUM.md`](docs/FASE_VISUAL_3_UI_PREMIUM.md).
>
> **FASE VISUAL 2.5 — QA visual, rendimiento y opciones.** Las opciones
> visuales ya se controlan desde **Opciones → Vídeo**: calidad (Baja/Media/Alta),
> luces dinámicas, viñeta, niebla, sombras y efectos, con aplicación en vivo.
> **Baja** apaga luces/viñeta/niebla y reduce efectos (36); **Media** usa tope
> de 16 luces de decoración y 70 efectos; **Alta** habilita neones con luz,
> 28 luces y 90 efectos. Números de daño e indicadores siempre por encima de
> niebla y viñeta; verificado reinicio sin efectos duplicados. Detalle en
> [`docs/FASE_VISUAL_2_5_QA_PERFORMANCE.md`](docs/FASE_VISUAL_2_5_QA_PERFORMANCE.md).
>
> **FASE VISUAL 2 — Iluminación, sombras y VFX.** Ambiente global por
> mapa (noche azul del Barrio, verdín con niebla del Parque, óxido con vapor
> del Callejón), luces dinámicas reales en jefes, rescates y farolas (textura
> radial generada por código, sin assets), vignette dramática con estados
> (poca vida, jefe vivo), sombra blob reutilizable y UI de compañeros pulida.
> Nuevos ajustes `dynamic_lights` y `vignette` en settings.json; en calidad
> baja todo se apaga solo. Detalle en
> [`docs/FASE_VISUAL_2_LIGHTING_VFX.md`](docs/FASE_VISUAL_2_LIGHTING_VFX.md).
>
> **FASE VISUAL 1 — Base artística y mundo.** Rediseño visual profundo
> sin tocar gameplay: volumen aparente en todos los personajes (rim light,
> sombreado direccional y sombras en dos capas), siluetas más fuertes (golilla
> y mechones del gato, púas dorsales en jefes, heridas/mordiscos en zombis),
> chalecos de rol en compañeros y suelos con identidad por bioma (hojarasca,
> marcas de garra felina, chatarra industrial). Detalle en
> [`docs/FASE_VISUAL_1_BASE_ARTISTICA.md`](docs/FASE_VISUAL_1_BASE_ARTISTICA.md).
>
> **FASE 10 — Refugio Felino (tienda + colocación + bonificaciones).**
> Nuevo botón **Refugio** en el menú principal: compra objetos con **Sardinas**
> en la **tienda** (12 objetos en 5 categorías, mejorables a nivel 5), colócalos
> en los **slots** del refugio y obtén **bonificaciones permanentes** al iniciar
> cada partida (daño, velocidad, vida, compañeros, sardinas, rescates, defensa).
> Regla clave: **solo los objetos colocados otorgan bonus** — comprar no basta.
> El panel "Bonificaciones activas" muestra el total en vivo y todo se guarda en
> el save. Pulido: gato interactivo, feedback al colocar/quitar, musica propia y
> desbloqueos de objetos por capitulos de Historia. Detalle en
> [`docs/FASE_SHELTER_SHOP_BASE.md`](docs/FASE_SHELTER_SHOP_BASE.md).
>
> También incluye el **Modo Historia** (6 capítulos con cinemáticas, dificultad
> Fácil/Intermedio/Difícil/Extremo y mejoras desbloqueables) y **Partida libre**
> con Niveles de Plaga 1-5 por mapa.
> La dificultad de Historia se confirma justo antes de jugar, las cinemáticas
> automáticas pueden omitirse, y Partida libre solo muestra zonas desbloqueadas
> por el avance de Historia.

> **Estado: FASE 08.9 - cierre de etapa (obstaculos con sentido, destructibles, UI) + 08.75/09/08.5.**
> La Fase 08.9 cierra la etapa: **composicion de mapas por zonas** (los obstaculos se
> agrupan con sentido: arboledas, filas de contenedores, carros en aceras, casas en
> bloques), **destructibles** (cajas/barriles que se rompen y sueltan XP; barril
> explosivo), **interaccion proyectil↔obstaculo** (las balas chocan; el boomerang
> atraviesa; los arbustos dejan pasar), y **UI** con navegacion completa (botones Volver
> en todas las pantallas, botones Reintentar/Mejoras/Menu en victoria/derrota) y la zona
> de **Mejoras de la Colonia** rediseñada a lista+detalle. Detalle en
> [`docs/FASE_08_9_FINAL_POLISH_CLOSEOUT.md`](docs/FASE_08_9_FINAL_POLISH_CLOSEOUT.md).
>
> La Fase 08.75 reparo el rendimiento (control de hordas, backpressure, limpieza de
> emergencia via el autoload `Performance`, topes de XP/proyectiles/efectos) y añadio el
> sistema de obstaculos. Detalle en
> [`docs/FASE_08_75_PERFORMANCE_SURVIVOR_UI_OBSTACLES.md`](docs/FASE_08_75_PERFORMANCE_SURVIVOR_UI_OBSTACLES.md).
>
> Incluye Fases 01-06.5 (game feel, companeros, armas, jefes, mapas/biomas) +
> roguelite basico: ganas **Sardinas** al terminar (ganando o perdiendo), las gastas en
> **mejoras permanentes**, el progreso se **guarda en disco** (user://) y el juego
> entra por **menu principal**, **selector real de mapas**, **Progreso**, **opciones**
> y **meta progresion**.
> La Fase 08.5 reduce texto y limpia la interfaz: HUD minimalista en combate y la
> **pausa (ESC) como centro de informacion** con el detalle de la run.
> La Fase 09 suma audio provisional generado por codigo: musica simple, SFX de UI,
> combate, XP, rescates, jefes, victoria/derrota y controles de volumen persistentes.
> Solo placeholders geometricos y audio procedural. Sin assets externos, tienda real,
> Steam ni arte final.
>
> Detalle: [`docs/FASE_09_AUDIO_PROVISIONAL.md`](docs/FASE_09_AUDIO_PROVISIONAL.md),
> [`docs/FASE_08_5_MINIMAL_UI_POLISH.md`](docs/FASE_08_5_MINIMAL_UI_POLISH.md),
> [`docs/FASE_07_5_META_PROGRESSION_POLISH.md`](docs/FASE_07_5_META_PROGRESSION_POLISH.md),
> [`docs/FASE_08_MAIN_MENU_FLOW_UI.md`](docs/FASE_08_MAIN_MENU_FLOW_UI.md),
> [`docs/FASE_07_META_PROGRESSION_SAVE.md`](docs/FASE_07_META_PROGRESSION_SAVE.md),
> [`docs/FASE_06_5_VISUAL_MAP_POLISH.md`](docs/FASE_06_5_VISUAL_MAP_POLISH.md),
> [`docs/FASE_06_MAPS_BIOMES_OBJECTIVES.md`](docs/FASE_06_MAPS_BIOMES_OBJECTIVES.md)
> y [`docs/FASE_05_BOSSES_WAVE_EVENTS.md`](docs/FASE_05_BOSSES_WAVE_EVENTS.md).

---

## Requisitos

- **Godot 4.7 stable** (rama Forward+).
- No requiere plugins, assets externos ni dependencias.
- El audio provisional se genera en memoria desde GDScript; no hay archivos de sonido.

## Como abrir el proyecto en Godot

1. Abre Godot 4.7.
2. En el **Project Manager**, pulsa **Import**.
3. Selecciona el archivo `project.godot` de esta carpeta y abre el proyecto.
4. La primera vez Godot reimporta recursos y regenera la carpeta `.godot/` (es normal).

## Que escena ejecutar

La escena principal ya esta configurada (`run/main_scene`):

```text
scenes/menus/MainMenu.tscn
```

Pulsa **F5** (Run Project) o el boton de *Play*. Tambien puedes abrir
`MainLevel.tscn` y pulsar **F6** (Run Current Scene) si quieres saltarte el menu
para debug.

## Controles

| Accion    | Teclas                       |
|-----------|------------------------------|
| Mover     | `W` `A` `S` `D` y flechas    |
| Pausa / informacion | `ESC` (durante la partida) |
| Menu / volver | `ESC` (en menus / tras la run) |
| Reiniciar | `R` (tras victoria o derrota)|
| Mejoras permanentes | `M` (tras victoria o derrota) |
| Cambiar mapa (debug) | `F1` / `F2` / `F3` |
| Overlay de rendimiento (debug) | `F8` (FPS, estado, enemigos/proyectiles/XP/obstáculos/efectos, spawn) |

El disparo es **automatico**: el gato dispara solo al enemigo mas cercano dentro de rango.

## Modo Cooperativo local (2 jugadores en la misma pantalla)

Nuevo modo **cooperativo local** (sin red, sin Steam). En el selector de zonas elige
**Modo: Cooperativo local** antes de pulsar *Jugar*. El **Modo Solo funciona igual que
siempre**; todo lo coop se activa solo cuando eliges ese modo.

- **Jugador 1 (teclado):** `WASD` / flechas. Pausa: `ESC`.
- **Jugador 2 (gamepad):** stick izquierdo. Respaldo de teclado: `I` `J` `K` `L`.
  Pausa: **Start/Options**. Elegir carta de nivel: dpad/stick + **A**.
- Requisito: **un control conectado** para el P2 (el menú avisa si falta; hay respaldo IJKL).
- **XP, nivel y armas compartidos**: las cartas de arma mejoran a **ambos** jugadores;
  cualquiera puede elegir la carta del equipo (P1 con ratón, P2 con gamepad).
- **Revive:** si un jugador cae, queda *DERRIBADO*; el otro se le acerca **2 s** y lo
  revive al 40% de vida. Si **ambos** caen → **Game Over**.
- **Cámara** cooperativa con **correa (leash)**: sigue el punto medio, avisa si se
  separan (~700 px) y los frena suavemente al límite (~950 px). Si un jugador queda
  fuera de cámara, aparece una **flecha con su color** en el borde.
- **Balance coop:** daño por jugador ×0.85 (no se duplica), enemigos/jefes con más vida
  y presión. Las **Sardinas no se duplican** (save único).

Guía completa en [`docs/FASE_COOP_LOCAL.md`](docs/FASE_COOP_LOCAL.md) y el pulido en
[`docs/FASE_COOP_1_5_POLISH.md`](docs/FASE_COOP_1_5_POLISH.md).

### Partida libre: modo arcade competitivo (sin bonos, con puntuación)

**Historia y Partida libre están separadas por diseño.** Las **mejoras permanentes** y el
**Refugio** afectan **solo al Modo Historia** (progresión). **Partida libre** es un modo
**arcade puro**: todos parten en igualdad de condiciones, **no da Sardinas**, y en su
lugar produce una **Puntuación** por partida y **récords locales** por mapa y dificultad
— para superarte o competir con un amigo en la misma máquina (comparte la **semilla** que
aparece en el resumen para jugar el mismo mundo).

Partida libre (Solo o Coop) tiene además un **regulador de dificultad** en el menú de
mapas, igual que Historia: **Fácil / Intermedio / Difícil / Extremo** (ajusta vida, daño,
presión y velocidad de los enemigos, y multiplica la puntuación). Es independiente del
**Nivel de Plaga** (que sigue desbloqueando y escalando por rejugar). Tu récord y tu
última dificultad se guardan; los ves en el selector de mapas y en Estadísticas.

Detalle en [`docs/FASE_FREE_PLAY_ARCADE.md`](docs/FASE_FREE_PLAY_ARCADE.md).

## Que muestra el HUD (minimalista, Fase 08.5)

Durante el combate el HUD solo muestra lo esencial:

- **Arriba izquierda:** Nivel, barra de **Vida** y barra de **XP**.
- **Arriba centro:** **Tiempo**.
- **Arriba derecha:** **objetivo corto** (p.ej. "Sobrevive", "Rescata 2 gatos") y
  conteo de **Gatos**.
- **Abajo izquierda:** mini-iconos de **armas** (icono + nivel; nombre completo al hover).
- **Abajo derecha:** mini-iconos de **companeros** con su barra de vida.

La informacion detallada (eliminados, intensidad, sinergias, armas con nivel,
estado de companeros, mapa y objetivo completo) ya **no satura la pantalla**: se
consulta en el **panel de pausa (ESC)**, que actua como centro de informacion.
Ver [`docs/FASE_08_5_MINIMAL_UI_POLISH.md`](docs/FASE_08_5_MINIMAL_UI_POLISH.md),
[`docs/FASE_05_5_VISUAL_WEAPON_POLISH.md`](docs/FASE_05_5_VISUAL_WEAPON_POLISH.md) y
[`docs/FASE_04_5_POLISH_WEAPONS_BUILDS_BALANCE.md`](docs/FASE_04_5_POLISH_WEAPONS_BUILDS_BALANCE.md).

## FASE 03.5: Companeros rescatables redisenados

Durante la partida pueden aparecer puntos de rescate. Si el jugador se acerca y
permanece 1 segundo en el area, rescata un gato que se une a la formacion.

Ahora los companeros:

- tienen vida propia
- pueden quedar derribados
- se pueden revivir con canalizacion
- muestran estado y barra de vida en HUD
- tienen rescate mas visible con flecha e indicador

Roles iniciales:

- `Gato Policia`: disparo medio, cadencia media.
- `Gato Medico`: cura periodicamente si el jugador no esta al maximo.
- `Gato Ingeniero`: disparo mas lento, pero mas fuerte y con algo mas de rango.

Los rescates tambien aumentan la dificultad dinamica para que la partida no se
vuelva trivial, y perder companeros temporalmente reduce parte de esa ventaja.

Detalle tecnico en
[`docs/FASE_03_COMPANIONS_RESCUE.md`](docs/FASE_03_COMPANIONS_RESCUE.md) y
[`docs/FASE_03_5_COMPANIONS_REDESIGN.md`](docs/FASE_03_5_COMPANIONS_REDESIGN.md).

## FASE 07.5: Meta-progresion pulida

Cada partida, ganes o pierdas, otorga **Sardinas** segun tiempo, enemigos, gatos
rescatados, companeros vivos, mini-jefes/jefes derrotados, objetivos, bonus de victoria
y multiplicador de mapa. Las Sardinas se gastan en **mejoras permanentes** que se
aplican al iniciar cada partida.

- Al terminar, el resumen muestra el **desglose completo de Sardinas**.
- El resumen tambien enseÃ±a el **arsenal usado** para que se lea mejor como el gato
  fue acumulando armas durante la run.
- Pulsa **M** para abrir/cerrar el panel de mejoras permanentes.
- Cada tarjeta muestra categoria, nivel, costo, efecto actual, efecto siguiente y estado.
- Pulsa **R** para reiniciar (no borra el progreso).

Mejoras: Garras Afiladas (+daño), Patas Ligeras (+velocidad), Nueve Vidas (+vida),
Instinto Felino (+XP), Mochila de Sardinas (+Sardinas), Llamado de la Colonia
(primer rescate antes), Mecanica Gatuna (−cooldown de armas).

El progreso se guarda en disco automaticamente:
`%APPDATA%/Godot/app_userdata/CatsVsZombieDogs/cats_vs_zombie_dogs_save.json`
(Windows). Si el JSON esta corrupto, se crea
`cats_vs_zombie_dogs_save_corrupt_backup.json`. Para empezar de cero en desarrollo,
activa `debug_enable_save_reset` y llama `SaveManager.reset_save()`, o usa
`force_reset_save_for_tests()` en harnesses controlados.

Asegurar un mapa **desbloquea el siguiente** (Barrio → Parque → Industrial). Detalle
en [`docs/FASE_07_5_META_PROGRESSION_POLISH.md`](docs/FASE_07_5_META_PROGRESSION_POLISH.md).

## FASE 08: Menu principal, seleccion de mapa y flujo meta

El proyecto ahora abre en **MainMenu** y el bucle completo queda:

`Menu principal -> Seleccion de mapa -> Run -> Resumen final -> Mejoras / Reintento / Menu`

- **Jugar** abre un selector real de mapas con estados `Disponible`, `Bloqueado` y `Completado`.
- **Mejoras** reutiliza el mismo panel meta, pero desde menu.
- **Progreso** muestra estadisticas acumuladas del save en tarjetas.
- **Opciones** y **Pausa** cuelgan del flujo principal.
- Tras terminar una run: `R` reinicia, `M` abre mejoras, `ESC` vuelve al menu.

Detalle en [`docs/FASE_08_MAIN_MENU_FLOW_UI.md`](docs/FASE_08_MAIN_MENU_FLOW_UI.md).

## FASE 09: Audio provisional

El proyecto incluye el autoload `AudioManager` (`scripts/audio/audio_manager.gd`),
que genera SFX y loops simples sin usar assets externos.

- Buses: `Master`, `Music`, `SFX`, `UI`.
- Opciones: Master, Musica, Efectos, UI y Silenciar todo.
- Los valores se guardan en `user://cats_vs_zombie_dogs_settings.json`.
- Hay musica de menu, gameplay y jefe.
- Hay SFX reales de UI desde `assets/audio/ui/` con fallback procedural, y SFX
  procedurales para disparos, laser, explosiones, XP, level up, dano, rescates,
  companeros, jefe, victoria y derrota.
- El manager aplica cooldowns y limites simultaneos para evitar saturacion.

Para probar rapido: abre el menu, mueve el mouse sobre botones, entra a una partida,
recoge XP, dispara varias armas, pausa con `ESC`, cambia volumen y reinicia con `R`
tras terminar una run. Detalle en
[`docs/FASE_09_AUDIO_PROVISIONAL.md`](docs/FASE_09_AUDIO_PROVISIONAL.md).

## FASE 06: Mapas, biomas y objetivos

El juego ya no ocurre siempre en el mismo fondo. Hay 3 zonas con identidad propia,
modificadores de dificultad, eventos y **objetivos de partida**:

- **Barrio Gatuno**: calles oscuras, cajas urbanas. Sobrevive 10:00 y derrota al jefe.
- **Parque Abandonado**: verde, arbustos, mas runners/rescates. Sobrevive 12:00 y rescata 2 gatos.
- **Callejón Industrial**: contenedores y tuberias, enemigos con mas vida. Sobrevive 15:00 y derrota 2 mini-jefes.

El HUD muestra el **nombre del mapa** y el **objetivo** con progreso. Al cumplirlo
aparece **"ZONA ASEGURADA"** con un resumen y se reinicia con **R**.

Para cambiar de mapa: campo `current_map_data` del nodo **MapManager**, o en juego con
**F1** (Barrio), **F2** (Parque), **F3** (Industrial). Detalle en
[`docs/FASE_06_MAPS_BIOMES_OBJECTIVES.md`](docs/FASE_06_MAPS_BIOMES_OBJECTIVES.md).

## FASE 06.5: Pulido visual de mapas

Los tres mapas ahora tienen patrones de fondo y decoracion mas diferenciados:
calles nocturnas, senderos de parque y placas industriales. El HUD muestra una intro
de mapa, objetivos mas claros, victoria con resumen ampliado y Game Over con datos de
la partida. Todo sigue sin assets externos. Detalle en
[`docs/FASE_06_5_VISUAL_MAP_POLISH.md`](docs/FASE_06_5_VISUAL_MAP_POLISH.md).

## FASE 05: Jefes y eventos de oleada

La partida ahora tiene picos de tension programados por tiempo (WaveEventManager):

- **Horda** (~1:00): aumenta el spawn por 20 s. Aviso "¡Horda entrante!".
- **Manada de runners** (~2:00): suben mucho los runners por 15 s.
- **Mini-jefe** (~3:00 y ~7:00): "Bulldog Bruto Zombi", grande, lento, pega fuerte
  y empuja; mucha XP al morir.
- **Jefe principal** (~10:00): "Rottweiler Alfa Zombi" con barra de vida grande,
  3 fases y patrones: persecucion, embestida con aviso visual e invocacion de perros.

Todas las armas y los companeros pueden danar a los jefes. Para probar sin esperar,
en el nodo **WaveEventManager** activa `debug_spawn_boss_early` (jefe a los 20 s) o
`debug_spawn_miniboss_early` (mini-jefe a los 12 s).

Detalle en [`docs/FASE_05_BOSSES_WAVE_EVENTS.md`](docs/FASE_05_BOSSES_WAVE_EVENTS.md).

## FASE 05.5: Pulido visual y lectura de armas

Esta pasada mejora el estilo sin assets externos: gato con sombra/collar/panuelo,
perros con parches/costillas/mandibula animada, jefes con mas presencia, proyectiles
distintos por tipo, laser mas contundente, catnip con pulso y orbitales con rastro.

Detalle en [`docs/FASE_05_5_VISUAL_WEAPON_POLISH.md`](docs/FASE_05_5_VISUAL_WEAPON_POLISH.md).

## FASE 10: Identidad visual procedural

La Fase 10 define direccion de arte, paleta compartida, iconos geometricos propios
y una opcion de calidad visual. La UI de combate usa iconos dibujados por codigo
para armas, companeros y cartas; los efectos siguen limitados por `Feedback` para
proteger hordas y jefes.

Documentos:

- [`docs/FASE_10_ART_DIRECTION.md`](docs/FASE_10_ART_DIRECTION.md)
- [`docs/FASE_10_VISUAL_IDENTITY_ART_VFX.md`](docs/FASE_10_VISUAL_IDENTITY_ART_VFX.md)

## Game feel

Numeros de dano, destellos de impacto/muerte, knockback, iman de XP, flash rojo y
screen shake al recibir dano, cartas de mejora con entrada animada y hover, ademas
de feedback visual al rescatar, curar y disparar con companeros.

En **Opciones** se puede ajustar screen shake, numeros de dano, calidad visual,
efectos intensos, sombras, FPS y audio. `F8` muestra el overlay de rendimiento.
Mas detalle en:

- [`docs/FASE_2_8_GAME_FEEL_DIFICULTAD_VISUAL.md`](docs/FASE_2_8_GAME_FEEL_DIFICULTAD_VISUAL.md)
- [`docs/FASE_03_COMPANIONS_RESCUE.md`](docs/FASE_03_COMPANIONS_RESCUE.md)

## Como probar cada cosa

- **Movimiento:** muevete con WASD o flechas; los perros zombis aparecen alrededor y te persiguen.
- **Combate:** el gato dispara automaticamente; las balas matan a los perros.
- **Rescates:** sobrevive unos segundos hasta que aparezca el aviso de rescate, sigue la flecha, completa la canalizacion y confirma que el HUD cambie a `1 / 4`.
- **Derribo / revive:** deja que un companero reciba varios contactos, confirma estado `CAIDO`, acercate y manten la canalizacion de revive.
- **Subida de nivel:** mata perros, recogelos al acercarte y elige cartas cuando subas de nivel.
- **Muerte / Game Over:** deja que varios perros te alcancen. Cada contacto resta vida con cooldown. Al llegar a 0 aparece la pantalla **GAME OVER**.
- **Reinicio:** con el Game Over en pantalla, pulsa **R** para reiniciar la partida.

## Que hacer si Godot no reconoce una escena

1. **Project -> Reload Current Project**.
2. Si persiste: cierra Godot, borra la carpeta `.godot/` y vuelve a abrir el proyecto.
3. En el panel **FileSystem**, clic derecho sobre la carpeta -> **Reimport** / **Scan**.
4. Verifica que las rutas de scripts en las escenas existan en `scripts/`.

## Estructura del proyecto

```text
scenes/   player, enemies, weapons, loot, ui, levels, companions
scripts/  audio, player, enemies, weapons, loot, systems, ui, companions
scripts/ui/theme_colors.gd  paleta visual compartida
scripts/ui/icon_drawer.gd   iconos geometricos procedurales
data/     enemies, companions
docs/     documentacion de fase
```

Mas detalle tecnico en [`docs/FASE_01_MVP.md`](docs/FASE_01_MVP.md).
