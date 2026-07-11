# ETAPA ARTÍSTICA 1 — Identidad visual y pipeline de sprites

Objetivo cumplido: base profesional para que sprites y animaciones definitivas
reemplacen el arte procedural **progresivamente, sin rehacer programación ni
romper el juego**. No se generó arte final ni se eliminó nada.

## Arquitectura visual previa (inspeccionada)

- Cada personaje dibuja su arte con composiciones de **Polygon2D dentro de un
  nodo `Visual`**; los scripts animan piezas por nombre (`@onready $Visual/...`).
- **Nodos que NO deben renombrarse** (referenciados por scripts):
  - Player: `Visual`, `Visual/Tail`, `Visual/Scarf`, `Visual/EyeLeft/Right`,
    `FacingIndicator`, `RescueArrow`, `PickupArea`, `WeaponManager`.
  - Enemy: `Visual` + 16 piezas nombradas (Body, Snout, Ears, Legs, Tail,
    Jaw, Collar, Spikes, Eye*/Pupil*, Drool, Scar, Stud, Outline).
  - Companion: ~20 piezas + barras/labels. Boss/MiniBoss: `Visual`,
    `Visual/Body`, `Visual/Head`, `Visual/Eye*`, `Aura`, `Telegraph`, `HealthBar`.
- Dirección: Player guarda `_last_facing` (los ojos/indicador la siguen);
  Enemy/Boss rotan el `Visual` completo con volteo vertical al mirar oeste.
- Sombras: dobles (SoftShadow + Shadow), fuera del `Visual` en enemigos/jefes.
- Estados por señales: `damaged`, `died`, `downed(pid)`, `revived(pid)`.
- Colisiones circulares (Player r16, Enemy r16, MiniBoss r24, Boss r48) —
  **intocables**.

## Riesgos identificados y estrategia elegida

Riesgos: scripts acoplados a nombres de nodos; recolor por datos (.tres) sobre
piezas procedurales; volteo vertical del Visual en enemigos; coop (2 players);
efectos que asumen `Visual` visible (flash de daño usa `_visual.modulate`).

**Estrategia: componente observador aditivo.** `SpriteVisual`
(CharacterVisualController) se cuelga como hijo del personaje y OBSERVA
(velocity + señales) sin tocar lógica. Sin perfil asignado, duerme y el juego
es byte-a-byte el de antes. Con perfil válido y `enabled`, monta un
AnimatedSprite2D y oculta el `Visual` procedural (que queda como fallback
intacto).

## Qué se construyó

| Pieza | Archivo |
|---|---|
| Perfil visual (Resource) | `scripts/visual/character_visual_profile.gd` |
| Controlador visual | `scripts/visual/character_visual_controller.gd` |
| Resolver de direcciones | `scripts/visual/sprite_direction_resolver.gd` |
| Validador | `scripts/visual/art_pipeline_validator.gd` + `run_art_validator.gd` |
| Plantilla de personaje | `scenes/visual/characters/SpriteCharacterVisual.tscn` |
| Generadores de la prueba | `scripts/visual/tools/make_test_sprite.gd` / `make_test_frames.gd` |
| Hoja y frames de PRUEBA | `assets/art/characters/players/test/` (marcas magenta = NO arte final) |
| Perfil de prueba | `data/visual_profiles/players/test_cat.tres` (`enabled=false`) |
| Integración dormida | nodo `SpriteVisual` en Player.tscn y Enemy.tscn |

Documentación: `ART_DIRECTION_BIBLE.md`, `SPRITE_TECHNICAL_SPEC.md`,
`ART_PIPELINE.md`, `ART_ASSET_INVENTORY.md`, `AI_ART_PROMPT_GUIDE.md`.

## Reglas de fallback implementadas

- Perfil nulo / `enabled=false` / inválido → arte procedural (el de siempre).
- El procedural solo se oculta DESPUÉS de validar y montar los SpriteFrames.
- Nunca ambas representaciones a la vez; nunca personajes invisibles.
- Depuración: `debug_mode` (AUTO / FORCE_PROCEDURAL / FORCE_SPRITE) y
  `show_visual_bounds` en el inspector del nodo `SpriteVisual`.

## Prueba técnica realizada (headless, 11/11 OK)

Player real + perfil de prueba: arranque procedural → perfil disabled sigue
procedural → FORCE_SPRITE activa sprite y oculta procedural (nunca ambos) →
velocity cambia idle↔run → `play_action("attack")` suena y vuelve a idle →
FORCE_PROCEDURAL restaura el arte original. Regresión: import + menú +
MainLevel 2000 frames sin errores; validador sin errores (2 avisos esperados
del perfil de prueba).

## Limitaciones conocidas

- El flash de daño y el squash procedural viven en los scripts del personaje
  y apuntan al `Visual` procedural: en modo sprite el "hurt" se ve por la
  animación, no por el flash. En Etapa 2, redirigir el flash al sprite activo
  (cambio pequeño y opcional en `_flash_hurt`).
- El controlador cubre idle/run/attack/hurt/downed/revive/death; los estados
  específicos de boss (charge/summon/phase) requieren llamadas `play_action`
  desde `boss.gd` cuando el boss tenga perfil (3 líneas por estado, Etapa 2+).
- Companion/Boss/MiniBoss aún no llevan el nodo `SpriteVisual` (se añade al
  llegar su arte, igual que en Player/Enemy).

## Qué hacer en la Etapa Artística 2

1. Producir `chr_player_cat` y `chr_enemy_normal` (P0 del inventario) al
   estándar de la spec (128 px, 5 direcciones + espejo).
2. SpriteFrames + perfiles reales (`enabled=false` hasta QA).
3. QA visual in-game con `debug_mode` y `show_visual_bounds`.
4. Redirigir flash de daño al sprite activo.
5. Activar (`enabled=true`), jugar solo y coop, medir FPS.
6. Continuar por prioridad del inventario (logo, cápsulas de zona, rescates,
   retratos, resto de enemigos...).
