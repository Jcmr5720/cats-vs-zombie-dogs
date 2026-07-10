# FASE VISUAL 2 — Iluminación, sombras, VFX y dramatismo

Objetivo: acercar el juego a la atmósfera de Ravenswatch con iluminación global
por mapa, luces locales reales, vignette dramática y más presencia de jefes,
sin 3D, sin assets externos y sin tocar gameplay.

## 1. Correcciones de FASE VISUAL 1

- **Escenas editadas a mano revisadas**: import headless limpio, 2600 frames de
  gameplay sin errores y smoke test de instanciación de las 7 escenas clave.
  Los `load_steps` de los .tscn editados quedaron consistentes.
- **UI de compañeros pulida**: `HealthBar` y `ReviveBar` con StyleBoxFlat
  propios (fondo oscuro, borde umbra, esquinas redondeadas; el fill se sigue
  tintando por rol vía `modulate`), labels de estado/revive con outline oscuro
  y colores de la paleta. Mismo tratamiento para la barra del mini-jefe y para
  los labels/barra del RescuePoint.
- **Legibilidad**: los tintes ambientales son suaves (canales 0.82–1.08) y los
  personajes saturados de F1 quedan por encima; el runner ganó glow de ojos ×2
  para leerse en los tres mapas.
- **Performance**: cero efectos nuevos por frame en enemigos comunes; la niebla
  son 3 polígonos con un `_process` trivial; el vignette revisa estados cada
  0.4 s; las luces comparten UNA textura radial cacheada.

## 2. Iluminación global (`scripts/visual/ambient_controller.gd`)

Nodo `AmbientController` en MainLevel (grupo `ambient_controller`). El
MapManager lo configura al aplicar el mapa:

- **CanvasModulate** con `MapData.ambient_color` (fade-in de ~1 s). El HUD vive
  en CanvasLayers y no se tiñe. Blanco puro = no se crea el nodo.
- **Niebla baja** (`fog_color` + `fog_strength`): bancos translúcidos enormes
  que derivan lentísimo siguiendo la cámara (z_index 30, sobre actores). Se
  desactiva en calidad baja o con efectos apagados.

Ambientes por mapa (en los `.tres`):

| Mapa | ambient_color | Niebla | Lectura |
|---|---|---|---|
| Barrio Gatuno | (0.84, 0.87, 1.08) | no | noche azul fría |
| Parque Abandonado | (0.82, 0.98, 0.86) | 0.55 verde-gris | verdín húmedo lunar |
| Callejón Industrial | (1.04, 0.92, 0.84) | 0.30 gris cálido | óxido y vapor |

## 3. Luces locales (`scripts/visual/glow_light.gd`)

`GlowLight` (extends PointLight2D, blend ADD) genera su textura radial por
código con `GradientTexture2D` y la **cachea en una static**: todas las luces
comparten una única textura de 256 px. Soporta pulso y parpadeo eléctrico.

Se crea SIEMPRE vía `GlowLight.attach(parent, color, radio, energia, pulso,
parpadeo)`, que devuelve `null` si las luces dinámicas están apagadas
(ajuste `dynamic_lights` o calidad baja) — los llamadores solo guardan la
referencia y comprueban `is_instance_valid`.

Dónde hay luz real:
- **Jefe principal**: luz de 250 px con pulso; nace apagada y sube en 0.8 s;
  vira de color y sube de energía por fase; estalla y se apaga al morir.
- **Mini-jefes**: luz ambarina de 150 px.
- **RescuePoint**: luz pulsante de 130 px del color del compañero.
- **Farolas del barrio**: charco cálido de 120 px con parpadeo eléctrico.
- **Neones**: luz de acento SOLO en calidad alta (acota luces por chunk).
- **Enemigos comunes: NUNCA** — su glow de ojos es Polygon2D fake (EyeGlow).

## 4. Sombras (`scripts/visual/blob_shadow.gd` + `scenes/visual/BlobShadow.tscn`)

Sombra blob reutilizable: dos elipses (halo suave + núcleo denso, el mismo
doble nivel de F1) dibujadas UNA vez. Exports: `radius`, `squash`, `opacity`,
`soft_opacity_ratio`, `shadow_offset`, `color`; método `configure()` para
cambios en runtime. Respeta `Feedback.shadows_enabled`. Ya usada por el
RescuePoint; las SoftShadow/Shadow de F1 en personajes se conservan intactas
(no se rompió nada; unificar es opcional y seguro de hacer pieza a pieza).

## 5. Ojos y auras

- Runner: `EyeGlow` ×2.2 de alfa y ×1.35 de escala (self_modulate, cero costo).
- Jefe: aura vira hacia rojo agresivo por fase, ojos estallan en blanco y
  decaen a naranja/rojo, micro hit-stop al cambiar de fase.
- RescuePoint: además del halo/anillo sonar de F1, luz real pulsante.
- Setas del parque: halo bioluminiscente + puntos de luz en los sombreros.
- Charco industrial: borde de brillo tóxico verdoso.

## 6. VFX de combate

Ya existían de fases anteriores (trails/halos/cores por arma, death burst,
hit sparks, números de daño, hit-stop, combos). Esta fase añadió: doble onda
de revive de jugador (verde + blanca) y el dramatismo de cámara (abajo). No se
saturó más la pantalla: el tope global `max_active_effects` sigue mandando.

## 7. VFX de jefes

- Aparición: hit-stop de "el mundo traga aire" (0.09 s a 12 %) + doble onda +
  shake + fade-in de su luz.
- Cambio de fase: hit-stop corto, aura y luz más agresivas, ojos en blanco.
- Telegrafiado de embestida: ya existía (flecha pulsante + onda roja).
- Muerte: cadena de explosiones + onda final (de F1/F5) + la luz estalla a
  ×2.4 y se apaga con el cuerpo.

## 8. Vignette y cámara (`scripts/visual/camera_overlay.gd`)

CanvasLayer `CameraOverlay` (layer 0: sobre el mundo, bajo el HUD) con un
ColorRect y un shader radial mínimo (3 uniforms). Estados por prioridad:

1. **Poca vida** (≤30 %): borde rojo pulsante cerrado.
2. **Jefe vivo**: vignette cálida más cerrada con pulso lento.
3. **Base**: color/intensidad del MapData (`vignette_strength`, `vignette_color`).

Las transiciones se interpolan; los estados se muestrean cada 0.4 s. Se apaga
con el ajuste `vignette=false` o en calidad baja.

## 9. Parámetros de calidad

Ajustes persistidos en `settings.json` (Settings → Feedback):

- `visual_quality` (baja/media/alta) — baja: sin luces, sin vignette, sin
  niebla, menos efectos; alta: neones con luz, tope de efectos 90.
- `visual_effects`, `shadows`, `damage_numbers`, `shake_*` (existentes).
- **Nuevos**: `dynamic_lights` (bool), `vignette` (bool).

No hay UI nueva de opciones todavía: los valores se leen/escriben por
`Settings.set_value("dynamic_lights", false)` y quedan documentados aquí para
la futura pantalla de opciones (y Steam Deck).

## 10. Rendimiento y limpieza

- Una sola textura de luz compartida; luces solo en jefes/rescates/props.
- Niebla: 3 polígonos; vignette: 1 ColorRect; ambiente: 1 CanvasModulate.
- Todo vive dentro de MainLevel: **R (reinicio) y volver al menú liberan la
  escena completa** — no quedan luces, modulaciones ni overlays duplicados
  (verificado: los sistemas se recrean con la escena).
- Enemigos comunes: cero nodos nuevos en esta fase.

## 11. Riesgos conocidos

- El shader del vignette es el primer shader del proyecto: en GPUs muy viejas
  con el driver de compatibilidad debería seguir siendo trivial, pero si diera
  problemas se apaga con `vignette=false`.
- `dynamic_lights`/`vignette` aún no tienen control en el menú de opciones
  (editable por settings.json); pendiente para la fase de UI.
- La niebla usa un salto de wrap (fmod) al reciclar bancos: puede notarse un
  "teletransporte" de un banco fuera de cámara en partidas largas (alfa muy
  bajo, casi imperceptible).

## 12. Qué queda para FASE VISUAL 3

- Menú de opciones visuales (calidad, luces, vignette) con la UI existente.
- Occluders 2D + sombras proyectadas reales de obstáculos grandes (LightOccluder2D).
- Glow real HDR (WorldEnvironment 2D) para proyectiles y ojos de jefes.
- Luces parpadeantes rojas dedicadas del Callejón (prop nuevo `hazard_beacon`).
- Estela (trail) del runner y de orbitales con Line2D pooled.
- Transiciones de mapa (fundido de ambiente entre menú y partida).
