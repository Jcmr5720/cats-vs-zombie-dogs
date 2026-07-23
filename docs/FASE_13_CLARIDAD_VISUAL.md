# FASE 13 — Claridad visual de armas, cajas y mejoras

> **ESTADO: IMPLEMENTADA.** No toca la logica ni el balance de la FASE 12: solo
> presentacion, explicacion y legibilidad. El juego sigue sin pausarse nunca.

**Objetivo:** un jugador nuevo debe entender, mirando el juego, que caja encontro,
que salio de ella, de que categoria es, que hace, si mejora algo que ya tiene y
que cambio despues de recogerlo.

---

## 1. Fuente unica: `scripts/loot/loot_catalog.gd` (`LootCatalog`)

Todo lo de cara al jugador vive en UN sitio y lo consumen HUD, minimapa, pickups,
cajas, opciones y tests:

- **Categorias oficiales** (etiqueta + color + icono + cabecera de toast + SFX):
  `Arma`, `Mejora`, `Mejora de compañero`, `Mutación`, `Núcleo de evolución`.
  Nunca se muestra "objeto"/"power-up".
- **Rarezas**: común / poco común / épica / legendaria (etiqueta + color).
- **`EFFECT_LINES`**: efecto numerico principal por id, en llano ("+10 % de daño
  con todas las armas"). Es un ESPEJO de `player.apply_upgrade()`: si cambia una
  magnitud alli, actualizar aqui (hay test que exige cobertura completa).
- **Rasgos de arma** (`weapon_traits`): "Daño alto · Alcance corto · Explota en
  área", derivados del WeaponData (sin duplicar datos).
- **Cajas** (`CRATE_INFO`): nombre, color, icono y prompt por rol.
- **Consejos de tutorial** (`TIPS`).

## 2. Cajas (map_interactable.gd)

- Cada tipo tiene **silueta propia** (no solo color): caja de armas = cofre
  rectangular con tablones y cerradura; caja de suministros = bidon redondo con
  cruz; caja especial = rombo facetado. Icono flotante (IconDrawer) con vaiven +
  brillo moderado.
- Al acercarse (< 170 px): **"Caja de armas — Golpéala para abrirla"**.
- Abrirlas suena a caja (`crate_open`), no a enemigo muriendo.
- **`special_crate`**: rol completo (visual, botin = mutacion o mejora, minimapa),
  pero NINGUN horario la planta aun — asi la fase no toca el balance. Activarla
  = añadirla a un horario de `RunPhaseConfig` cuando se decida.

## 3. Tarjetas de informacion antes de recoger (ground_pickup.gd)

Todo pickup muestra al acercarse (< 170 px) una tarjeta en el mundo con: nombre,
categoria + rareza (con color de rareza), descripcion de una frase (del .tres),
efecto numerico (del catalogo) y estado cuando aplica ("Vida máxima: 100 → 115",
"Solo puede conseguirse una vez", "Nivel actual: 2 → 3").

- **Arma**: rasgos + "Esta arma puede evolucionar" + caso:
  - Hueco libre → "Recoger arma" (entra sola al tocarla).
  - Ya la tienes → "Nivel actual: N → N+1 · Mantén E para MEJORAR".
  - **Inventario lleno → comparacion compacta**: arma encontrada (rasgos) vs
    "Reemplazará: X (Nv. N)" (rasgos), "Mantén E para cambiar" y "La descartada
    quedará en el suelo". Sin pausar, sin ocupar media pantalla.
- En coop el prompt lleva la etiqueta del jugador a rango ("J1 · Mantén E…").

## 4. Confirmacion despues de recoger (hud.show_loot_toast)

Toast de ~2 s cerca del centro, con animacion, sonido por categoria y
auto-desaparicion (no pausa nada):

- `MEJORA OBTENIDA` / `MEJORA DE COMPAÑERO` — nombre + efecto numerico.
- `NUEVA ARMA` — "X añadida al espacio 2" + rasgos.
- `ARMA MEJORADA` — "X · Nv. 3" + que gano.
- `ARMA CAMBIADA` — "vieja → nueva · la vieja quedó en el suelo".
- `MUTACIÓN ACTIVADA` — nombre + efecto.
- `ARMA EVOLUCIONADA` — "Pistola Gatuna → Ametralladora Maulladora" + que hace.

En coop el toast sale **en la mitad del recolector** (un hueco por mitad; no se
superponen).

## 5. HUD

- **Chips de arma**: icono + nombre corto + nivel; evolucionada = borde dorado y
  ★. Al subir de nivel se anima **solo** el chip que cambio.
- **Panel de build (tecla B, mando Select)**: sin pausar, separa Armas / Mejoras /
  Mejoras de compañero / Mutaciones con textos en llano ("Garras afiladas ×3 —
  +10 % de daño…"). En coop, una columna por jugador.

## 6. Minimapa

- Iconos por FORMA + color: caja de armas (cuadrado con cruz), suministros
  (circulo con cruz), especial (rombo facetado), arma en el suelo (cuadrado
  hueco), mutacion (estrella), nucleo (anillo con punto), mejora comun
  (triangulo, **solo si esta a < 750 px del jugador** — el radar no chiva todo).
- **Leyenda**: aparece con el radar ampliado (Tab), bajo el panel, usando los
  MinimapMarker reales (la forma de la leyenda es exactamente la del radar).
- Grupos nuevos en el registry (`pickups`, `weapon_pickups`, `map_interactables`)
  con cadencias relajadas y tope de 14 marcadores de botin.

## 7. Tutorial integrado (una vez por perfil)

`hud.show_tip(id)` — banda inferior, ~4.5 s, sin pausar. Persistido como
`tip_seen_*` en el guardado; **reiniciable desde Opciones → Juego** ("Volver a
mostrar consejos de tutorial"). Disparadores: primera caja, primera arma en el
suelo, primera mejora, primera mutacion, primer nucleo, primer inventario lleno,
segunda arma (anuncia el panel de build).

## 8. Sonido

Nuevos en AudioManager: `crate_open`, `weapon_found`, `powerup_collect`,
`mutation_activate`, `evolution_complete` (mismo pool con limites anti-spam; sin
nodos nuevos).

## 9. Lenguaje

`.tres` reescritos en llano y sin prefijos tecnicos ("MUTACION:" fuera: la
categoria ya la muestra la tarjeta). El test prohibe jerga (cooldown, stack,
modifier…) en nombres y descripciones.

## 10. Archivos tocados

**Nuevos:** `scripts/loot/loot_catalog.gd`, `tests/test_loot_clarity.gd` (+
`.tscn`), este doc.

**Modificados:** `ground_pickup.gd` (tarjetas + tips), `power_up_pickup.gd`,
`weapon_pickup.gd` (comparacion), `evolution_core.gd`, `map_interactable.gd`
(cajas), `loot_director… (sin cambios de logica)`, `weapon_manager.gd` (toasts +
SFX), `weapon_base.gd` (snapshot con `evolved`/`description`), `player.gd`
(`powerup_counts`), `hud.gd` (toasts, tips, chips, panel de build),
`minimap_{config,marker,controller,entity_registry}.gd`, `audio_manager.gd`,
`options_menu.gd` (reset de consejos + atajos), `project.godot` (accion
`build_panel` = B / Select), 18 `.tres` de `data/powerups/`.

## 11. Verificacion

```bash
godot --headless --path . --import
godot --headless --path . res://tests/TestLootClarity.tscn
godot --headless --path . res://tests/TestCoopClarity.tscn   # coop: toasts por mitad, panel de build, 2 leyendas, huerfanos=0
godot --headless --path . res://tests/TestGroundLoot.tscn
godot --headless --path . res://tests/TestLootDrops.tscn
godot --headless --path . res://tests/TestCoop.tscn
godot --headless --path . res://tests/TestCoopSoak.tscn      # coop: 2400 frames sin crash, huerfanos=0
godot --headless --path . res://tests/TestMinimap.tscn
SOAK_POWER=build godot --headless --path . res://tests/TestQuickRunSoak.tscn
SOAK_POWER=flow  godot --headless --path . res://tests/TestQuickRunSoak.tscn
```

**Notas de coop verificadas** (`TestCoopClarity`, 19 comprobaciones): el toast de
botín del J2 sale en su mitad (lado 2, `vp.x*0.75`); el panel de build no pausa y
muestra una columna por jugador; hay 2 minimapas, cada uno con su propia leyenda
que se enciende/apaga al ampliar; cero fuga de nodos. El toast del J2 lo dispara
el WeaponManager del propio J2, que localiza el HUD por grupo (no por `_hud`, que
solo conecta el del J1).

## 12. Prueba de comprension obligatoria (validacion manual guiada)

Sentar a una persona que nunca jugo un roguelite, partida rapida de ~5 min en el
Barrio, SIN explicarle nada. Despues debe poder responder observando el juego:

1. **¿Qué diferencia hay entre un arma y una mejora?** — Debe citar la tarjeta
   ("Arma" añade forma de atacar y ocupa espacio; "Mejora" sube numeros).
2. **¿Qué contiene cada tipo de caja?** — Cofre dorado = arma; bidon celeste =
   mejora (lo dice el prompt al acercarse).
3. **¿Qué hace una mutación?** — Cambia una regla de la build; cita el toast
   "MUTACIÓN ACTIVADA" o la tarjeta morada con estrella.
4. **¿Cómo se cambia un arma con el inventario lleno?** — Mantener E sobre el
   arma del suelo; la descartada queda en el suelo (lo dice el panel de
   comparacion y el consejo de tutorial).
5. **¿Qué arma evolucionó y por qué?** — Cita el toast "ARMA EVOLUCIONADA:
   X → Y" tras recoger el nucleo del jefe, y la ★ del chip del HUD.
6. **¿Dónde consulta su build actual?** — Tecla B (lo anuncia un consejo al
   conseguir la segunda arma).

**Si alguna respuesta no puede obtenerse observando el juego, la fase NO esta
terminada:** anotar cual fallo y reforzar ese canal (tarjeta, toast, tip o HUD).
