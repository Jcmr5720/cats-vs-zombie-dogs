# AI ART PROMPT GUIDE — Cats vs Zombie Dogs

Plantillas para generar arte consistente con IA. **Ningún generador mantiene
consistencia perfecta entre imágenes ni entre frames: todo resultado requiere
revisión y corrección manual** (repintado de detalles, alineación de frames,
limpieza de alfa). Usar la IA para concepts, poses base y variaciones; la
coherencia final la da el artista/editor.

## Bloque base (añadir a TODO prompt)

> stylized dark fantasy cartoon digital painting, top-down 3/4 view (camera
> ~55° above horizon, showing top and front of the body), single character
> centered, neutral pose, key light from upper-left, soft dark integrated
> outlines, simplified painterly materials, strong readable silhouette,
> transparent background, no text, no watermark, no frame, no border, nothing
> cropped, full body visible with margin around ears/tail

Negativos recomendados:
> realistic gore, photorealism, pixel art, flat vector, isometric grid, side
> view, white background, drop shadow on ground, multiple characters, text

## Personajes (gatos)

> heroic stylized cat character for a dark fantasy cartoon survivor game,
> triangular agile shapes, expressive face, clearly readable ears and tail,
> [DESCRIPCIÓN: orange tabby leader cat with a blue scarf], warm clean
> colors (#F5B361 fur, #FDEBC7 belly, #33A6F2 scarf), functional small gear,
> + BLOQUE BASE

Para compañeros sustituir descripción: policía (navy uniform cap, golden
badge, sturdy build), médico (soft shapes, off-white fur, green cross cap),
ingeniero (angular shapes, orange hard hat, tool harness).

## Enemigos (perros zombis)

> grotesque cartoon zombie dog, heavy broken asymmetric shapes, arched back,
> exaggerated jaw and paws, clearly canine silhouette, putrid desaturated
> [#527D4A green] fur, stylized wounds as color patches (no realistic gore),
> glowing [#F5DC33 yellow] eyes as the only bright point, + BLOQUE BASE

Variantes: runner (lean, sinewy, exposed muscle #944D4D, brighter eyes),
mastín (massive, armored collar with spikes, cold grey #525C70, ember eyes),
cachorro (small, jaundiced #807540, oversized head).

## Jefes

> massive alpha zombie rottweiler boss, dominant WIDE silhouette with unique
> proportions (not a scaled-up normal dog), double row of back spikes, glowing
> scars, broken harness, dramatic rim light, purple-black palette (#52356B
> body, #FFC733 ember eyes), details readable from far away, + BLOQUE BASE

## Props

> stylized dark fantasy cartoon game prop, [OBJETO: abandoned car / park
> bench / industrial container], seen from top-down 3/4, simplified painterly
> materials, 2-3 values per material plus rim light from upper-left,
> post-apocalyptic wear (subtle), bioma palette [ver Biblia], + BLOQUE BASE

## Escenarios / suelos

> seamless tileable ground texture, top-down view, stylized painterly [dark
> night asphalt with cracks / overgrown grass with dirt path / stained
> industrial concrete], desaturated dark palette [#1C1F26 / #17241A /
> #211F1A], low contrast (characters must pop over it), no objects, no text

## Iconos UI

> flat stylized game icon of [OBJETO], bold readable shape, dark panel-ready,
> single accent color [#FF9933], subtle inner glow, centered, transparent
> background, no text, no frame

## Retratos

> stylized bust portrait of [PERSONAJE], 3/4 face angle, dark fantasy cartoon
> painting, dramatic upper-left light, dark vignette background allowed
> (square), expressive eyes, + identidad del personaje

## Problemas frecuentes y cómo tratarlos

| Problema | Mitigación |
|---|---|
| Patas/manos deformes, extremidades de más | Pedir "four legs, anatomically consistent"; corregir a mano siempre |
| Diseño cambia entre frames/imágenes | Generar UNA pose maestra y derivar frames a mano o con img2img de baja variación; los accesorios (bufanda, placa) casi siempre mutan: repintarlos |
| Luz inconsistente | Fijar "key light from upper-left" y corregir en edición; descartar tomas con luz frontal |
| Perspectiva lateral o isométrica | Insistir "top-down 3/4, showing top and front"; descartar vistas de perfil |
| Fondo no transparente / tramado | Pedir transparente pero ASUMIR recorte manual; usar removedores de fondo + limpiar borde |
| Halos blancos | Defringe/alpha bleed tras el recorte; nunca aplanar sobre blanco |
| Escala inconsistente entre assets | Normalizar en el lienzo estándar (spec) midiendo contra el player |
| Texto/marcas de agua incrustados | Negativos + recorte; descartar si toca al personaje |

## Flujo recomendado

1. Generar 4-8 candidatos de CONCEPT por personaje → elegir 1.
2. Congelar el diseño en una hoja de referencia (frente/lado/detalles).
3. Producir frames: a mano sobre el concept, o img2img/pose-control con
   revisión frame a frame.
4. Limpieza, celda estándar, pivote, paleta → pipeline normal
   (`ART_PIPELINE.md`).
