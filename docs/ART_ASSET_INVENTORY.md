# ART ASSET INVENTORY — Etapa Artística 2

> **Actualización E2**: el pipeline receptor está listo (los 5 actores llevan
> `SpriteVisual`, hooks de acciones conectados, puerta de aceptación e
> `_incoming` operativos). El estado por personaje vive en
> `SPRITE_MIGRATION_REPORT.md`; este inventario define QUÉ producir. Entregar
> paquetes en `assets/art/_incoming/characters/<categoría>/<id>/`.

Inventario completo de assets pendientes. Prioridad: P0 = primero (máximo
impacto), P3 = último. Estado: PENDIENTE / EN CURSO / QA / INTEGRADO.
Direcciones "5+flip" = dibujar s, se, e, ne, n y espejar el lado oeste.
Tamaños = celda de autoría a 2× (ver SPRITE_TECHNICAL_SPEC).

## Jugadores

| ID | Nombre | Escena | Prio | Celda | Dirs | Animaciones | Frames est. | Variantes | Estado | Notas |
|---|---|---|---|---|---|---|---|---|---|---|
| chr_player_cat | Gato líder (P1) | Player.tscn | **P0** | 128 | 5+flip | idle, run, attack, hurt, downed, revive, death | ~170 | — | PENDIENTE | Bufanda azul; asimetría aceptada al espejar |
| chr_player_cat_p2 | Variante P2 | Player.tscn (player_id 2) | P1 | 128 | reusa P1 | reusa P1 | 0 (recolor) | tinte frío #9EC7F2 | PENDIENTE | `palette_variant` o hoja recoloreada |

## Compañeros

| ID | Nombre | Escena | Prio | Celda | Dirs | Animaciones | Frames est. | Estado | Notas |
|---|---|---|---|---|---|---|---|---|---|
| chr_comp_police | Gato Policía | Companion.tscn | P1 | 128 | 5+flip | idle, run, attack, ability, hurt, downed, revive | ~150 | PENDIENTE | gorra + placa |
| chr_comp_medic | Gato Médico | Companion.tscn | P1 | 128 | 5+flip | ídem | ~150 | PENDIENTE | ability = pulso de curación |
| chr_comp_engineer | Gato Ingeniero | Companion.tscn | P1 | 128 | 5+flip | ídem | ~150 | PENDIENTE | casco + tuerca |

## Enemigos

| ID | Nombre | Escena | Prio | Celda | Dirs | Animaciones | Frames est. | Estado | Notas |
|---|---|---|---|---|---|---|---|---|---|
| chr_enemy_normal | Zombie Dog | Enemy.tscn | **P0** | 128 | 5+flip | idle, run, attack, hurt, death | ~110 | PENDIENTE | el más visible del juego |
| chr_enemy_runner | Runner | Enemy.tscn | P1 | 128 | 5+flip | ídem | ~110 | PENDIENTE | flaco, ojos muy brillantes |
| chr_enemy_pup | Cachorro Rabioso | Enemy.tscn | P2 | 128 (pequeño) | 5+flip | ídem | ~110 | PENDIENTE | o reusar normal a escala 0.62 en P2 |
| chr_enemy_tank | Mastín Podrido | Enemy.tscn | P1 | 192 | 5+flip | ídem | ~110 | PENDIENTE | púas y collar |
| chr_enemy_elite_fx | Auras élite (veloz/blindado/gigante) | enemy.gd | P3 | 128 | 1 | loop aura | 4×3 | PENDIENTE | hoy procedural, puede quedarse |

## Jefes

| ID | Nombre | Escena | Prio | Celda | Dirs | Animaciones | Frames est. | Estado | Notas |
|---|---|---|---|---|---|---|---|---|---|
| chr_boss_rottweiler | Rottweiler Alfa | Boss.tscn | P1 | 384 | 5+flip | idle, run, basic_attack, special_attack, charge_windup, charge, summon, hurt, phase_change, death | ~300 | PENDIENTE | hoja propia; fases 2/3 por recolor/overlay |
| chr_boss_bulldog | Bulldog Brute (mini) | MiniBoss.tscn | P2 | 192 | 5+flip | idle, run, attack, hurt, death | ~110 | PENDIENTE | |
| chr_boss_alpha_prime | Alpha Prime | Boss.tscn (data) | P2 | 384 | 5+flip | como boss | ~300 | PENDIENTE | |

## Mundo (por bioma; se integran vía TileMap/Sprite2D en etapa 2+)

| ID | Nombre | Prio | Tamaño | Estado | Notas |
|---|---|---|---|---|---|
| env_nb_ground | Suelo Barrio (asfalto/acera/losetas) | P2 | tiles 256 | PENDIENTE | hoy procedural (ChunkGroundRenderer) |
| env_nb_props | Coche, muro, casa, dumpster, caja, barricada | P2 | 256–512 | PENDIENTE | reemplazan Obstacle procedural |
| env_pk_ground | Suelo Parque (pasto/sendero/lago) | P2 | tiles 256 | PENDIENTE | |
| env_pk_props | Árbol, banca, roca, arbusto, cerca | P2 | 256–512 | PENDIENTE | |
| env_in_ground | Suelo Industrial (placas/vía/aceite) | P2 | tiles 256 | PENDIENTE | |
| env_in_props | Contenedor, barril, tubería, muro, bloque | P2 | 256–512 | PENDIENTE | |
| env_shelter_bg | Fondo del Refugio + slots | P2 | escena 2048 | PENDIENTE | |
| env_decor_micro | Hojas, garras, chatarra, setas | P3 | 64 | PENDIENTE | hoy procedural, bajo valor de reemplazo |

## Combate

| ID | Nombre | Prio | Tamaño | Estado | Notas |
|---|---|---|---|---|---|
| fx_projectiles | Proyectiles (base/explosivo/boomerang) | P2 | 64 | PENDIENTE | hoy Polygon2D + trail |
| fx_orbital | Orbital + estela | P2 | 64 | PENDIENTE | |
| fx_catnip_area | Área de catnip | P2 | 256 | PENDIENTE | |
| fx_impacts | Impactos/chispas (4-6 frames) | P2 | 128 | PENDIENTE | |
| fx_explosion | Explosión (6-8 frames) | P2 | 256 | PENDIENTE | |
| fx_xp_orb | Orbe de XP | P3 | 64 | PENDIENTE | el actual lee bien |
| fx_rescue_point | Jaula/caja de rescate | P1 | 256 | PENDIENTE | objetivo clave, muy visible |

## UI

| ID | Nombre | Prio | Tamaño | Estado | Notas |
|---|---|---|---|---|---|
| ui_portraits | Retratos P1/P2/compañeros (6) | P1 | 256 | PENDIENTE | HUD coop, cartas, refugio |
| ui_card_icons | Iconos de cartas de mejora (~20) | P2 | 128 | PENDIENTE | hoy IconDrawer procedural |
| ui_shelter_items | Objetos del refugio (12) | P2 | 128 | PENDIENTE | |
| ui_map_capsules | Ilustración por zona (3) | P1 | 512×288 | PENDIENTE | selector de mapas + Steam |
| ui_logo | Logo del juego | P1 | 1024×512 | PENDIENTE | menú + capsule Steam |
| ui_boss_portraits | Retratos de jefes (3) | P3 | 256 | PENDIENTE | boss bar |

## Orden recomendado de producción (Etapa 2)

1. **chr_player_cat** + **chr_enemy_normal** (P0: define el estándar de calidad).
2. ui_logo + ui_map_capsules + fx_rescue_point + ui_portraits (P1 de alto impacto).
3. Resto de enemigos y compañeros (P1).
4. Jefes (P1-P2). 5. Mundo y combate (P2). 6. Micro-decoración e iconos (P3).
