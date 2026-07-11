# SPRITE TECHNICAL SPEC — Cats vs Zombie Dogs

Estándar técnico para todo sprite que entre al juego. Medidas derivadas de la
escala REAL del juego (medida en esta etapa, no inventada).

## Escala del juego (medida)

- Resolución base: 1152×648 (stretch `canvas_items`, aspect `expand`).
- Zoom de cámara: 1.0 en solo; coop entre 1.35 (juntos) y 1.0 (separados).
- Player: colisión r=16 px; arte procedural actual ≈ 66×59 px.
- Compañero: r=14; ≈ 64×50 px.
- Enemigo normal: r=16, escala 1.08; ≈ 72×52 px. Runner ×(0.92,0.74).
  Cachorro ×0.62. Mastín ×(1.55,1.45).
- Mini-jefe: r=24; ≈ 128×70 px. Jefe: r=48; ≈ 230×160 px.

**Regla: el sprite se adapta al gameplay, jamás se tocan colisiones.**

## Tamaños de lienzo (autoría a 2×, mostrado a escala 0.5)

El arte se dibuja al DOBLE del tamaño en pantalla y el perfil usa
`visual_scale = 0.5`: nítido con el zoom coop 1.35 y a prueba de futuro.

| Asset | Celda (px) | Tamaño en juego aprox. |
|---|---|---|
| Jugador / compañero | 128×128 | ~64 px |
| Enemigo normal / runner | 128×128 | ~64-72 px de ancho |
| Cachorro | 128×128 (dibujado pequeño) o escala 0.62 | ~40 px |
| Enemigo pesado (mastín) | 192×192 | ~100 px |
| Mini-jefe | 192×192 | ~96-128 px |
| Jefe | 384×384 (hoja propia) | ~230 px |
| Proyectiles | 64×64 | ~32 px |
| Props pequeños (basura, setas) | 64–128 | 32-64 px |
| Props medianos (banca, barril, coche) | 256 | ~128 px |
| Props grandes (casa, contenedor) | 512 | ~256 px |

## Formato y bordes

- PNG con canal alfa, fondo 100 % transparente.
- Sin halos blancos: pintar sobre fondo transparente o hacer *defringe*/alpha
  bleed al exportar (nunca aplanar sobre blanco).
- Márgenes: ≥ 8 px libres alrededor de la pose extrema (orejas, cola, armas y
  espacio para VFX). El personaje centrado HORIZONTALMENTE en la celda de
  forma idéntica en todos los frames.

## Pivote

- **Pivote = punto de contacto con el suelo**, en una línea fija de la celda
  (recomendado: y = 87.5 % de la celda; en 128 px → y = 112).
- `AnimatedSprite2D` queda centrado; el `CharacterVisualProfile.visual_offset`
  compensa: `offset.y = pies_gameplay − (linea_suelo − centro_celda) × visual_scale`.
  Ej. player: 22 − (112−64)×0.5 = **−2**.

## Direcciones (contrato de nombres)

Sufijos: `s, se, e, ne, n, nw, w, sw`. Animación = `<accion>_<sufijo>`
(`run_se`). Sin sufijo = vista única.

- Presupuesto completo: 8 direcciones.
- Presupuesto reducido: dibujar **s, se, e, ne, n** (5) y activar
  `flip_horizontal_allowed` — el resolver espeja e→w, se→sw, ne→nw.
- Mínimo: **s, e, n** (3) con `direction_count = 4` + espejo.
- ¡Ojo con el espejo!: elementos asimétricos (bufanda, herida, placa) cambian
  de lado al espejarse; mantener los distintivos centrados o aceptarlo.
- **Etapa 2**: el perfil declara las asimetrías — `has_asymmetric_design` /
  `require_unique_west_frames` BLOQUEAN el espejo aunque
  `flip_horizontal_allowed` esté activo (`mirror_allowed()` es la única
  fuente de verdad). Personaje asimétrico ⇒ entregar frames oeste propios.
  `preserve_painted_light_direction` documenta si la luz pintada tolera espejo.

## Animaciones (nombres, FPS y loop)

| Animación | FPS | Loop | Al terminar |
|---|---|---|---|
| idle | 6 | sí | — |
| run | 10–12 | sí | — |
| attack / basic_attack | 12–14 | no | vuelve a idle/run |
| ability (compañeros) | 10 | no | vuelve a idle/run |
| hurt | 12 | no | vuelve a idle/run |
| downed | 8 | no | se queda en último frame |
| revive | 10 | no | vuelve a idle/run |
| death | 8 | no | se queda en último frame |
| special_attack / summon (boss) | 10 | no | vuelve a idle/run |
| charge_windup | 10 | no | encadena charge |
| charge | 14 | sí | hasta fin del estado |
| phase_change | 10 | no | vuelve a idle/run |

Frames típicos: idle 4-6, run 6-8, acciones 4-8, death 6-10.

## Importación en Godot

- Filtro **lineal** (arte pictórico). `nearest` SOLO si algún asset fuese
  pixel art (no es el estilo del juego).
- **Mipmaps ON** en personajes y props (ayudan con zoom out coop).
- Compresión: *Lossless* para personajes; VRAM comprimida aceptable en fondos
  grandes.
- Atlas: preferir hojas ≤ **2048×2048** (el validador avisa por encima).
  Jefes y props grandes pueden ir en hoja propia.

## Checklist por asset (antes de integrar)

1. Fondo transparente sin halos. 2. Todos los frames alineados al pivote.
3. Luz desde NO. 4. Paleta de la Biblia. 5. Silueta legible a escala real
   (probar al 50 %). 6. Nombres de animación del contrato.
7. `ArtPipelineValidator` sin errores.
