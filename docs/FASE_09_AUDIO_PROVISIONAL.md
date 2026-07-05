# FASE 09 - Audio provisional

Proyecto: Cats vs Zombie Dogs  
Motor: Godot 4.7  
Assets externos: ninguno

## Que se implemento

Se agrego una capa de audio provisional, funcional y reemplazable:

- Autoload `AudioManager` en `scripts/audio/audio_manager.gd`.
- Buses runtime: `Master`, `Music`, `SFX` y `UI`.
- Sonidos cortos generados por codigo con `AudioStreamWAV`.
- Los SFX de UI usan archivos reales desde `res://assets/audio/ui/` cuando existen.
- Loops musicales simples generados por codigo para menu, gameplay y jefe.
- Controles de volumen y mute en Opciones y Pausa.
- Persistencia de volumen en `Settings`.
- Integracion con UI, disparos, XP, nivel, dano, enemigos, rescates, companeros,
  eventos, jefe, victoria y derrota.

No se descargaron sonidos ni musica. No hay audio con copyright.

## AudioManager

`AudioManager` es un autoload y expone:

- `play_sfx(name)`
- `play_ui(name)`
- `play_music(name)`
- `stop_music()`
- `set_master_volume(value)`
- `set_music_volume(value)`
- `set_sfx_volume(value)`
- `set_ui_volume(value)`
- `mute_all(enabled)`
- `reset_for_scene_change()`

Si un nombre no existe, la llamada no crashea. Esto permite integrar audio desde
gameplay sin preloads repartidos por muchos scripts.

## Buses

El manager crea en runtime los buses `Music`, `SFX` y `UI` si no existen, todos
enviados a `Master`.

`Settings` aplica volumen lineal `0.0..1.0` convirtiendolo a dB con `linear_to_db`.
`audio_mute` silencia el bus `Master`.

## Sonidos provisionales

UI:

- `ui_hover`
- `ui_click`
- `ui_buy`
- `ui_error`
- `ui_open`
- `ui_close`
- `ui_select`
- `ui_button_click`
- `ui_notification`

Estos nombres intentan cargar, segun corresponda:

- `UI Hover.wav`
- `UI Click.wav`
- `Button Select.wav`
- `Button Click.wav`
- `Menu Open.mp3`
- `Menu Close.mp3`
- `Purchase.wav`
- `Error.mp3`
- `Notification.wav`

Tambien se soportan las variantes con guion bajo del pedido original, por ejemplo
`UI_Hover.wav`. Si un archivo no existe o no carga, queda activo el fallback
procedural del mismo nombre.

Gameplay:

- `shoot_basic`
- `shoot_strong`
- `explosion`
- `laser`
- `enemy_hit`
- `enemy_die`
- `xp_collect`
- `level_up`
- `player_damage`
- `low_health`
- `rescue_cat`
- `medic_heal`
- `companion_downed`
- `companion_revived`
- `orbital_hit`
- `boss_appear`
- `boss_hit`
- `boss_die`
- `victory`
- `defeat`
- `event_alert`

## Musica provisional

Loops generados:

- `menu`
- `gameplay`
- `boss`

`MainMenu` inicia musica de menu. `MapManager` inicia gameplay. `BossSpawner`
cambia a musica de jefe cuando aparece el jefe y vuelve a gameplay al morir.
`GameFlow` limpia SFX y reinicia la musica correcta al cambiar de escena.

## Opciones y guardado

`Settings` guarda:

- `audio_master`
- `audio_music`
- `audio_sfx`
- `audio_ui`
- `audio_mute`

El archivo sigue siendo:

`user://cats_vs_zombie_dogs_settings.json`

Opciones y Pausa muestran sliders de Master, Musica, Efectos, UI y el toggle de
Silenciar todo.

## Anti-saturacion

`AudioManager` aplica dos limites por sonido:

- Cooldown en milisegundos por nombre.
- Maximo de instancias simultaneas por nombre.

Ejemplos:

- `xp_collect` tiene cooldown corto para que recoger muchos orbes no cree pared de sonido.
- `enemy_hit` y `enemy_die` limitan repeticion cuando muchas balas o muertes ocurren juntas.
- Disparos y laser tienen cooldown por nombre.
- Explosiones tienen volumen moderado y limite simultaneo.

El pool de SFX tiene 18 `AudioStreamPlayer`; si todos estan ocupados, el nuevo SFX
se ignora en vez de crear nodos infinitos.

## Como agregar sonidos nuevos

1. En `AudioManager._build_streams()`, agrega una llamada a `_add_tone`.
2. Usa un nombre estable, por ejemplo `&"new_event"`.
3. Define frecuencia, duracion, volumen, forma, cooldown y limite.
4. Llama `AudioManager.play_sfx(&"new_event")` o `AudioManager.play_ui(&"new_event")`
   desde el punto central del evento.

Para audio final, se puede reemplazar el stream generado por un recurso cargado en
el diccionario `_sfx` o `_music` sin cambiar las llamadas del resto del juego. Para
UI, agrega candidatos en `UI_REAL_STREAMS`; el fallback procedural queda intacto.

## Comportamiento al pausar y reiniciar

La musica continua durante pausa a volumen normal de Music. Los SFX usan nodos con
`PROCESS_MODE_ALWAYS`, por lo que clicks y opciones suenan mientras el arbol esta
pausado.

Al cambiar de escena o reiniciar con `R`, `GameFlow` y `MapManager` llaman limpieza
de SFX y musica para evitar duplicados.

## Riesgos conocidos

- Los loops son muy simples y pueden sentirse repetitivos.
- Los sonidos son placeholders sinteticos; no buscan calidad final.
- Los buses se crean en runtime. Si luego se configura un layout de buses desde el
  editor, conviene revisar nombres y volumen por defecto.
- La musica no hace crossfade; cambia de forma directa.

## Pendiente para audio final

- Reemplazar placeholders por SFX propios finales.
- Musica original o licenciada correctamente.
- Crossfades entre gameplay y jefe.
- Mezcla mas fina por arma y bioma.
- Opciones avanzadas como bajar musica automaticamente al pausar.
