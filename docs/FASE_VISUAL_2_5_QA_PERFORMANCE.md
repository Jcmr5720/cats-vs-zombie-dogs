# FASE VISUAL 2.5 — Corrección, rendimiento y legibilidad

Fase de QA sobre la capa visual de FASE VISUAL 2: opciones en el menú,
límites de VFX, legibilidad en combate y prueba de reinicio sin duplicados.
No añade espectacularidad nueva.

## 1. Opciones visuales en el menú

Pestaña **Vídeo** del menú de opciones (`options_menu.gd`), junto a las que ya
existían (Pantalla completa, Calidad visual, Efectos intensos, Sombras, FPS):

- **Luces dinámicas** (`dynamic_lights`)
- **Viñeta de cámara** (`vignette`)
- **Niebla de ambiente** (`fog`, clave nueva en settings.json)

Y en **Juego** ya estaban: Screen shake, intensidad, números de daño.

Aplicación EN VIVO, sin reiniciar:
- Luces: `Feedback._apply_to_live_nodes()` recorre el grupo `glow_lights` y
  conmuta `enabled` en las luces ya creadas; las nuevas respetan el ajuste al
  crearse (`GlowLight.attach` devuelve null).
- Sombras blob: grupo `blob_shadows`, conmuta `visible`.
- Niebla: el `AmbientController` guarda el último MapData y `refresh_settings()`
  reconstruye o destruye los bancos al momento.
- Viñeta: el overlay consulta `Feedback.vignette_enabled` cada frame.

Nota en el propio menú: la calidad Baja manda sobre los toggles.

## 2. Presets de calidad

| | Baja | Media | Alta |
|---|---|---|---|
| Tope de efectos (`max_active_effects`) | 36 | 70 | 90 |
| Luces dinámicas | apagadas | sí | sí |
| Tope de luces de decoración (`max_active_lights`) | 0 | 16 | 28 |
| Viñeta | apagada | toggle | toggle |
| Niebla | apagada | toggle | toggle |
| Luz de neones | no | no | sí |

## 3. Límites de VFX (centralizados en FeedbackManager)

- `max_active_effects`: ya existía (números de daño, destellos, bursts).
- `max_active_lights` (**nuevo**): tope global de luces de DECORACIÓN
  (farolas, neones) con contador estático en `GlowLight` que se decrementa en
  `_exit_tree`. Las luces **importantes** (jefe, mini-jefe, RescuePoint) usan
  `important=true` y no cuentan: nunca se quedan sin cupo por culpa de las
  farolas. Verificado en test: con calidad alta el nivel satura exactamente en
  28 luces de decoración y no crece más.
- Tweens: todos los tweens de VFX están ligados a su nodo (`create_tween` de
  instancia) y mueren con él; el hit-stop restaura `Engine.time_scale` con un
  timer que ignora el time_scale (sobrevive a cambios de escena).

## 4. Legibilidad en combate

- **Números de daño**: `z_index = 60` — por encima de la niebla (z 30).
- **Hit effects**: `z_index = 55` — ídem.
- **Flecha de rescate del jugador**: `z_index = 40`.
- **HUD**: CanvasLayer 1; overlay coop (roster, leash, "¡No se separen!",
  flechas offscreen P1/P2): CanvasLayer 50. La viñeta vive en CanvasLayer 0 →
  **nunca tapa HUD ni indicadores coop** (verificado por capas).
- Runner: glow de ojos ×2.2 (F2) — se distingue del zombi normal en los 3
  ambientes. P1 naranja sobre ambientes fríos = contraste complementario; P2
  mantiene tinte frío + etiqueta "P2" con outline.
- Setas (verde estático, pegado al suelo) vs XP (cian pulsante con imán):
  colores y comportamiento distintos; el brillo tóxico industrial es verde
  frente al cian del XP.
- La viñeta base está acotada (`vignette_strength` se clampa a 0.6; los mapas
  usan 0.32–0.36) y el estado de poca vida cierra a 0.42 con pulso: nunca
  llega a negro en el centro de la acción.

## 5. Rendimiento

- Enemigos comunes: 0 luces reales, 0 nodos nuevos por frame (glow por
  self_modulate en un Polygon2D existente).
- Niebla: 3 polígonos y un `_process` de 6 senos; se apaga con su toggle, con
  efectos apagados o en calidad baja.
- Viñeta: 1 ColorRect + shader de 3 uniforms; muestreo de estados cada 0.4 s.
- Luces: una única `GradientTexture2D` compartida (static) para todas.
- Suelo/decoración nueva de F1-F2: dibujada una vez por chunk (canvas cacheado).

## 6. Pruebas realizadas (headless, Godot 4.7)

1. Import completo sin errores.
2. Menú principal 600 frames sin errores.
3. MainLevel 2600 frames (spawns, muertes, XP, level-ups) sin errores.
4. **Test de reinicio**: escena de prueba que monta MainLevel, lo libera y lo
   vuelve a montar (equivalente a R / volver al menú y reentrar):
   - run1: 28 luces, 1 ambient, 1 overlay, 1 CanvasModulate.
   - tras liberar: **0, 0, 0, 0** (y 0 efectos activos).
   - run2: 28, 1, 1, 1 → **SIN DUPLICADOS**.
5. Smoke de instanciación de las 7 escenas visuales clave.

Prueba manual recomendada (no automatizable headless): coop local, boss fight
con calidad baja/media/alta y cambiar toggles en caliente desde Opciones.

## 7. Riesgos restantes

- El toggle de sombras en vivo solo afecta a las BlobShadow (grupo); las
  sombras de polígonos de F1 dentro de Player/Enemy/etc. no se apagan en vivo
  (son parte de la escena; coste ínfimo).
- El cap de luces es global, no por distancia: en teoría las 16/28 farolas
  encendidas podrían quedar lejos de la cámara si el jugador recorre mucho
  mapa (las luces de chunks descargados liberan cupo al descargarse).
- Los ajustes en vivo dependen de `call_group`: si un mod/escena externa crea
  luces sin `GlowLight.attach`, no respetará los toggles.

## 8. Qué queda para FASE VISUAL 3

- UI premium (menús, HUD, refugio) con la nueva dirección.
- LightOccluder2D en obstáculos grandes.
- Glow HDR real para proyectiles/ojos de jefes.
- Prop `hazard_beacon` parpadeante del Callejón.
- Trails pooled (runner, orbitales).
- Cap de luces por distancia a cámara si el conteo global se queda corto.
