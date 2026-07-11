# ART ASSET ACCEPTANCE CHECKLIST — puerta de aceptación

Todo paquete que llegue a `assets/art/_incoming/` pasa esta lista ANTES de
tocar el juego. Si falla un criterio marcado ★, se RECHAZA (se mantiene el
procedural y se registra el motivo en `ART_IMPORT_MANIFEST.md`).

## Archivo
- [ ] ★ PNG con canal alfa real (no JPG, no fondo blanco/cuadriculado pintado).
- [ ] ★ Sin halos blancos en el borde (inspeccionar sobre fondo oscuro).
- [ ] ★ Nada cortado: orejas, cola, armas y efectos dentro del lienzo con margen ≥ 8 px.
- [ ] ★ Sin texto, firmas ni marcas de agua.
- [ ] Dimensiones = celda estándar de su categoría (SPRITE_TECHNICAL_SPEC).

## Consistencia entre frames
- [ ] ★ Mismo personaje en todos los frames (proporciones, cara).
- [ ] ★ Misma ropa y accesorios en todos los frames y direcciones.
- [ ] ★ Número correcto de extremidades en todos los frames.
- [ ] ★ Punto de apoyo (línea de suelo) idéntico entre frames.
- [ ] Escala idéntica entre frames y coherente con el resto del elenco.

## Dirección artística
- [ ] ★ Perspectiva top-down 3/4 (se ve lomo Y frente; no perfil puro).
- [ ] ★ Luz pintada desde arriba-izquierda, coherente en todo el set.
- [ ] Paleta dentro de la Biblia (ART_DIRECTION_BIBLE).
- [ ] Silueta legible al 50 % del tamaño (zoom out coop).
- [ ] SIN sombra de suelo pintada (Godot pone la BlobShadow; sombra pintada = doble sombra → corregir o rechazar).

## Asimetrías
- [ ] Registrar si el diseño es asimétrico (bufanda, placa, herida...).
- [ ] Si es asimétrico: exigir frames oeste propios O aceptar el cambio de
      lado y marcar `has_asymmetric_design=false` conscientemente.

## Resultado
- APROBADO → mover a carpeta definitiva, crear SpriteFrames + perfil
  (`enabled=false`), correr validador, QA en preview y en juego.
- RECHAZADO → anotar en el manifiesto qué regenerar/corregir.
