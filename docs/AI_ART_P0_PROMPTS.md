# AI ART P0 PROMPTS — paquetes leader_cat y zombie_dog_normal

Prompts listos para producir el LOTE P0 por subgates (B0 hoja maestra →
B1 poses piloto → B2 mini animación → B3 paquete completo). Todo resultado
pasa por `_incoming/raw → clean → aligned` y la puerta de aceptación.
**Ningún generador garantiza consistencia entre imágenes: revisar y corregir
a mano cada entrega** (AI_ART_PROMPT_GUIDE.md).

## Bloque base (pegar en TODOS los prompts)

> stylized dark fantasy cartoon digital painting for a top-down survivor
> game, top-down 3/4 view (camera ~55° above horizon, top and front of body
> visible), single character centered with ≥8 px margin (ears, tail and gear
> fully inside), key light from upper-left, soft dark integrated outlines,
> painterly simplified materials (2-3 values per material + rim light),
> fully transparent background, NO ground shadow painted, no text, no
> watermark, no frame, no border, nothing cropped

**Negativos (todos los prompts):**
> side view, isometric, photorealism, realistic gore, pixel art, flat
> vector, white background, checkered background, painted drop shadow,
> extra legs, duplicated tail, missing limbs, different outfit between
> images, floating weapon, changed lighting direction, text, watermark,
> signature, frame, cropped ears or tail

## Identidad fija de los personajes (pegar según personaje)

**LEADER_CAT** (usar íntegro en cada prompt del gato):
> heroic orange tabby leader cat, agile triangular shapes, upright confident
> stance, readable ears and long expressive tail, cream belly and muzzle
> (#FDEBC7), warm orange fur (#F5B361) with darker tabby stripes (#D68A42),
> cheek fur tufts, green eyes, blue scarf around the neck (#33A6F2) with a
> short trailing end on the character's LEFT side, small blue collar,
> no other clothing, four legs, one tail

**ZOMBIE_DOG_NORMAL** (usar íntegro en cada prompt del perro):
> grotesque cartoon zombie dog, medium mongrel build, heavy broken
> asymmetric silhouette with arched back and lowered head, exaggerated
> loose jaw with one visible fang, putrid desaturated green fur (#527D4A)
> with darker patches (#33502E), one BITTEN LEFT ear with a clean notch,
> stylized flank wound on its LEFT side as a dark red patch (#8A2A22, no
> realistic gore), pale exposed rib hints, glowing sickly yellow eyes
> (#F5DC33) as the only bright point, worn red collar with one stud,
> four legs, one tail

## GATE B0 — Hojas maestras

**1. leader_cat_master_v01** (lienzo 1024×1024, hoja de referencia):
> character reference sheet of [LEADER_CAT], three views arranged
> horizontally: front 3/4 top-down, back 3/4 top-down, side profile
> (reference only), plus a face close-up and a scarf/collar detail inset,
> flat color palette swatches strip, consistent proportions across views,
> + BLOQUE BASE (sin la parte de "single character centered")

**2. zombie_dog_normal_master_v01** (1024×1024):
> character reference sheet of [ZOMBIE_DOG_NORMAL], three views arranged
> horizontally: front 3/4 top-down, back 3/4 top-down, side profile
> (reference only), plus jaw close-up, infection/wound detail inset and
> scale comparison silhouette next to a 64 px cat silhouette, palette
> swatches strip, + BLOQUE BASE

Criterio B0: el personaje NO cambia entre vistas (proporciones, accesorios,
paleta). Si muta, regenerar antes de seguir.

## GATE B1 — Poses piloto (celda 128×128, pies en y=112)

Gato (5 imágenes):
1. `leader_cat_idle_s_v01_f01` — > [LEADER_CAT] standing relaxed idle pose,
   facing SOUTH (toward camera), tail curled beside body, + BLOQUE BASE
2. `leader_cat_run_se_v01_f01` — > running pose mid-stride facing
   SOUTH-EAST, body leaning into movement, tail whipping behind, scarf
   trailing, + BLOQUE BASE
3. `leader_cat_attack_e_v01_f01` — > quick claw swipe attack pose facing
   EAST, one front paw extended with motion arc hint, + BLOQUE BASE
4. `leader_cat_hurt_s_v01_f01` — > flinching hurt pose facing SOUTH, ears
   back, body recoiling slightly, + BLOQUE BASE
5. `leader_cat_downed_s_v01_f01` — > lying on side, defeated but alive,
   facing SOUTH, shallow breathing pose, + BLOQUE BASE

Perro (5 imágenes): mismas plantillas con [ZOMBIE_DOG_NORMAL]:
`idle_s` (hunched swaying), `run_se` (heavy loping run), `attack_s` (lunging
bite, jaw wide), `hurt_s` (recoil), `death_s` (collapsing sideways).

Criterio B1: perspectiva/escala/luz/pivote correctos EN EL JUEGO (Preview
con fondo de los tres biomas y zoom x1.0/x1.35) antes de animar.

## GATE B2 — Mini animación piloto

Producir como variaciones de la pose aprobada (img2img de baja variación o
dibujo directo), UNA animación por prompt, frames numerados:

- `leader_cat_idle_s_v01_f01..f04` — > 4-frame idle breathing cycle,
  IDENTICAL character and outfit in every frame, only chest/tail move subtly
- `leader_cat_run_se_v01_f01..f06` — > 6-frame run cycle facing south-east,
  4-beat feline gait, scarf and tail follow-through, same design every frame
- `leader_cat_attack_e_v01_f01..f04` — > 4-frame claw swipe: anticipation,
  swipe, contact, recovery
- Perro: `run_se f01..f06` (heavy lope), `attack_s f01..f04` (lunge bite),
  `death_s f01..f06` (collapse and settle)

Criterio B2: continuidad frame a frame (sin mutaciones), pivote estable,
lectura en movimiento, memoria trivial (<2 MB por personaje piloto).

## GATE B3 — Paquete completo (tras aprobar B2)

Completar por animación×dirección con las mismas plantillas cambiando
`facing SOUTH/SOUTH-EAST/EAST/NORTH-EAST/NORTH` (5 direcciones; el oeste se
espeja SOLO si QA aprueba el flip de bufanda/herida — ambos personajes son
ASIMÉTRICOS: por defecto exigir oeste real o centrar el accesorio):

- Gato: idle×4, run×6, attack×5, hurt×3, downed×5, revive×5, death×7 → ~35
  frames × 5 direcciones ≈ 175 (o ×8 ≈ 280 si se decide oeste real).
- Perro: idle×4, run×6, attack×5, hurt×3, death×7 → ~25 × 5 ≈ 125.
