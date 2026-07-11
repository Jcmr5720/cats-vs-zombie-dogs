# SPRITE MIGRATION REPORT — estado por personaje

## Subgates del LOTE P0 (Etapa 3)

| Subgate | leader_cat | zombie_dog_normal |
|---|---|---|
| B0 hoja maestra | PENDIENTE (prompts listos en AI_ART_P0_PROMPTS.md) | PENDIENTE |
| B1 poses piloto | PENDIENTE | PENDIENTE |
| B2 mini animación | PENDIENTE | PENDIENTE |
| B3 paquete completo | BLOQUEADO por B2 | BLOQUEADO por B2 |
| B4 perfiles validados | BLOQUEADO | BLOQUEADO |
| B5 QA Preview + 3 biomas | BLOQUEADO | BLOQUEADO |
| B6 solo/coop/hordas/rendimiento | BLOQUEADO | BLOQUEADO |

Estados del manifiesto: RECEIVED → AUTOMATIC_CHECK_FAILED / MANUAL_REVIEW →
REJECTED / PILOT_APPROVED → FINAL_APPROVED → INTEGRATED → REGRESSION_APPROVED.
Estados de perfil (`asset_status`): TEST_ONLY / PLACEHOLDER / PILOT_ART /
FINAL_CANDIDATE (solo builds dev) / APPROVED_FINAL (producción).

Leyenda: ✔ = sí · ✖ = no · — = no aplica todavía.

| Personaje | Procedural activo | Sprite temporal | Sprite definitivo | Perfil válido | Anims completas | Solo probado | Coop probado | Aprobado visual | Estado |
|---|---|---|---|---|---|---|---|---|---|
| Gato líder (P1) | ✔ | ✔ (TEST_ONLY, solo QA técnico) | ✖ | ✔ (test, `enabled=false`) | ✖ (faltan downed/revive en test) | ✔ técnico | ✖ | ✖ | **BLOQUEADO EN PUERTA DE ASSETS** — falta paquete artístico |
| Variante P2 | ✔ (tinte frío + etiqueta) | ✖ | ✖ | ✖ | ✖ | — | — | ✖ | PENDIENTE (depende de P1) |
| Gato Policía | ✔ | ✖ | ✖ | ✖ | ✖ | — | — | ✖ | PENDIENTE (SpriteVisual integrado) |
| Gato Médico | ✔ | ✖ | ✖ | ✖ | ✖ | — | — | ✖ | PENDIENTE (hook `ability` conectado) |
| Gato Ingeniero | ✔ | ✖ | ✖ | ✖ | ✖ | — | — | ✖ | PENDIENTE (hook `attack` conectado) |
| Zombie normal | ✔ | ✖ | ✖ | ✖ | ✖ | — | — | ✖ | **BLOQUEADO EN PUERTA DE ASSETS** |
| Runner | ✔ | ✖ | ✖ | ✖ | ✖ | — | — | ✖ | PENDIENTE |
| Cachorro | ✔ | ✖ | ✖ | ✖ | ✖ | — | — | ✖ | PENDIENTE |
| Mastín (pesado) | ✔ | ✖ | ✖ | ✖ | ✖ | — | — | ✖ | PENDIENTE |
| Mini-jefe | ✔ | ✖ | ✖ | ✖ | ✖ | — | — | ✖ | PENDIENTE (SpriteVisual integrado) |
| Jefe principal | ✔ | ✖ | ✖ | ✖ | ✖ | — | — | ✖ | PENDIENTE (hooks charge/summon/fase conectados) |

## Assets faltantes para desbloquear el LOTE P0

Depositar en `assets/art/_incoming/characters/`:

1. **players/leader_cat/** — hoja(s) 128 px/celda, direcciones s+se+e+ne+n
   (mín. s/e/n), animaciones: idle(4-6), run(6-8), attack(4-6), hurt(2-4),
   downed(4-6), revive(4-6), death(6-10). ~170 frames con 5 direcciones.
2. **enemies/zombie_dog_normal/** — ídem con idle, run, attack, hurt, death
   (~110 frames).

Tras la puerta de aceptación (`ART_ASSET_ACCEPTANCE_CHECKLIST.md`) se crean
SpriteFrames + perfiles `leader_cat.tres` / `zombie_dog_normal.tres` con
`enabled=false`, QA en `CharacterArtPreview.tscn` y en juego, y solo entonces
`enabled=true`.
