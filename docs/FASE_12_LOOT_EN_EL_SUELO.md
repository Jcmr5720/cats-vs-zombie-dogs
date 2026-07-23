# FASE 12 — Loot en el suelo: reemplazo total del sistema de cartas

> **ESTADO: IMPLEMENTADA.** Ver §7 (archivos tocados). Validada en headless: suite
> completa en verde y los dos soaks (`build` → VICTORIA, `flow` → DERROTA) se
> mantienen. **El juego ya no se pausa en toda la run.**

> **Filosofía:** el poder de una partida deja de repartirse pausando el juego con un
> menú de cartas y pasa a RECOGERSE del suelo, dentro del combate. La decisión ya no
> es "¿cuál de estas 3?" sino "¿voy a por esa caja con la horda encima?" — espacial y
> arriesgada, no de menú.

---

## 0. Qué había antes

- `scripts/systems/upgrade_manager.gd` (748 líneas): al subir de nivel pausaba el
  árbol (`get_tree().paused = true`) y el HUD mostraba 3 cartas (arma nueva / mejora
  de arma / stat / compañero), con reroll y veto. El mini-jefe concedía una "mutación"
  por el mismo panel. En coop, un panel por jugador (`coop_upgrade_panel.gd`).
- El poder = elección de menú. Interrumpía el ritmo y ocurría fuera del mundo del juego.

## 1. Qué hay ahora

| Antes | Después |
|---|---|
| `upgrade_manager.gd` (pausa + cartas) | `scripts/systems/loot_director.gd` — sin UI, sin pausa: solo tablas de drop |
| `hud.show_upgrade_selection()` + `UpgradePanel` | nada en el HUD; prompt en el mundo, hijo del pickup |
| Mutación por menú al caer el mini-jefe | el mini-jefe suelta un **núcleo de evolución**; el jefe, mutación + núcleo |
| Carta de evolución | evolución **automática** al recoger un núcleo de jefe |
| `_chosen_stat_ids` en el UpgradeManager | `player.owned_powerups: Array[StringName]` |
| Subir de nivel abre cartas | bonus pasivo pequeño (~40 % de una carta) + curación + mensaje |

## 2. Capa de datos

- **`scripts/loot/power_up_data.gd`** (`class_name PowerUpData extends Resource`).
  NO implementa efectos: `effect_id()` es el `StringName` que se pasa a
  `player.apply_upgrade()`, así que el `match` de `player.gd` sigue siendo la única
  fuente de verdad. Añadir un power-up = crear un `.tres`.
- 18 `.tres`: `data/powerups/` (7 stats + 6 de compañero) y `data/powerups/mutations/`
  (5 mutaciones, `max_stacks = 1`). Registro explícito en
  `scripts/loot/power_up_registry.gd` (patrón de `WeaponManager.WEAPON_REGISTRY`).

## 3. Pickups en el suelo

`scripts/loot/ground_pickup.gd` (base, `Area2D`, grupo `"pickups"`) generaliza el
contrato del orbe de XP: `collect(player)` duck-typed, imán opcional hacia el jugador
activo más cercano, `claim()` como guarda anti-doble-cobro en coop, tope de nodos
(`MAX_PICKUPS = 24`). El orbe de XP **no** se refactorizó a subclase (está muy afinado
y lo tocan varios tests): se comparte el patrón, no el código.

- **`power_up_pickup.gd`**: imán corto, caduca a los 45 s (las mutaciones no).
  Auto-recoge por contacto. En coop el efecto es solo del recolector, salvo los de
  categoría compañero, que `apply_upgrade` ya redirige al `CompanionManager`.
- **`weapon_pickup.gd`** (grupo `"weapon_pickups"`, aparte a propósito): **sin imán**.
  Hueco libre → se recoge sola al tocarla; ya la tienes → prompt *"Mantén E para
  MEJORAR"*; inventario lleno (4) → prompt *"Mantén E para cambiar por X"* con barra
  de hold (0.55 s). El prompt vive **en el mundo**, hijo del pickup (evita tocar
  `HUD.tscn` y resuelve el "¿el HUD de quién?" en coop). **El arma descartada vuelve
  al suelo**: el intercambio es reversible.
- **`evolution_core.gd`**: premio de jefe. Al recogerse llama a
  `WeaponManager.evolve_best_weapon()`; si no hay arma elegible, el director lo cambió
  por una mutación antes de soltarlo, así que el premio nunca se desperdicia.

Acciones nuevas en `project.godot`: `interact` (E / botón X) y `p2_interact` (H / X).

## 4. Fuentes de drop

- **Cajas destructibles** (`map_interactable.gd`, roles `weapon_crate` / `supply_crate`):
  reutilizan el `StaticBody2D` en grupos `"enemies"` + `"map_interactables"` ya excluido
  del spawner, las zonas de daño y el targeting. XP deliberadamente baja (6 / 4): la
  recompensa es el contenido, no la experiencia (mismo motivo que la marca de aullido).
  Las planta `PhaseDirector._spawn_due_crates()` en TODOS los mapas, en paralelo a los
  interactables de identidad, con horario en `RunPhaseConfig.WEAPON_CRATE_TIMES` /
  `SUPPLY_CRATE_TIMES`. Determinismo por semilla con salt propio (`"crate:"`): misma
  semilla = mismas armas en las mismas cajas.
- **Enemigos** (`enemy.gd::_drop_powerup`): comunes al 1.2 %, élites garantizado.
- **Jefes**: `mini_boss.gd` suelta un núcleo; `boss.gd`, mutación + núcleo. Máximo 2
  núcleos por run = `WeaponManager.MAX_EVOLUTIONS_PER_RUN`.
- **`LootDirector`**: sortea (`roll_weapon` / `roll_powerup` / `roll_mutation`),
  conserva el bono de rareza del Refugio (solo Modo Historia) y el filtro de compañero,
  y añade un **pity timer** (45 s sin recoger → siguiente drop garantizado) que recorta
  la varianza sin subir la media. En coop, cantidad × `CoopConfig.LOOT_MULTIPLIER` (1.7).

## 5. Subir de nivel

Ya no abre nada. `player._apply_level_reward()` cura un 8 % y aplica un bonus del ciclo
`lvl_damage / lvl_speed / lvl_health / lvl_cooldown / lvl_range / lvl_pickup` (~40 % de
la magnitud de un power-up), con ids **propios** que no cuentan para `owned_powerups`
(regalarían los requisitos de evolución). Con ~11 niveles/run: +8 % daño, +5 %
velocidad, +12 HP, −8 % cooldown. Perceptible, no dominante.

## 6. Balance

El presupuesto bruto (≈19-23 recogibles) parece mayor que las 8-12 cartas de antes,
pero: (a) recoger no está garantizado con la horda encima (~65-75 % efectivo); (b) ya
no hay elección de la mejor de 3 con reroll/veto, así que el valor esperado por unidad
cae ~25-35 %. Palancas de ajuste, en orden: bajar `LootDirector.COMMON_DROP_CHANCE`
(0.012 → 0.008); quitar `SUPPLY_CRATE_TIMES`. Las dos invariantes del soak
(`test_quick_run_soak`) se mantienen: `build` → VICTORIA, `flow` (estático) → DERROTA.

## 7. Archivos tocados

**Nuevos:** `scripts/loot/{power_up_data,power_up_registry,ground_pickup,power_up_pickup,weapon_pickup,evolution_core}.gd`,
`scripts/systems/loot_director.gd`, 18 `.tres` en `data/powerups/`,
`tests/{test_ground_loot,test_loot_drops}.gd` (+ `.tscn`).

**Modificados:** `player.gd` (`owned_powerups`, `_apply_level_reward`, ids `lvl_*`, la
línea de `_on_pickup_area_area_entered`), `weapon_manager.gd`
(`remove_weapon` / `replace_weapon` / `_swap_slot` / `evolve_best_weapon` / `get_swap_candidate`,
tope de evoluciones migrado), `map_interactable.gd` (roles de caja + `_drop_loot`),
`phase_director.gd` (scheduler de cajas, fuera `grant_mutation` / `set_first_card_gate`),
`run_phase_config.gd`, `coop_config.gd` (`LOOT_MULTIPLIER`), `enemy.gd`,
`mini_boss.gd`, `boss.gd`, `hud.gd` (recorte del panel de cartas), `HUD.tscn`
(subárbol `UpgradePanel` fuera), `pause_menu.gd`, `minimap_controller.gd`,
`options_menu.gd`, `project.godot` (acciones), `MainLevel.tscn` (nodo `LootDirector`).

**Borrados:** `scripts/systems/upgrade_manager.gd`, `scripts/ui/coop_upgrade_panel.gd`,
`data/permanent_upgrades/{lucky_paw,picky_eater}.tres` (reroll/veto sin sentido sin
cartas), `tests/test_cards_no_skip.gd` (+ `.tscn`).

## 8. Verificación

```bash
godot --headless --path . --import
godot --headless --path . res://tests/TestGroundLoot.tscn
godot --headless --path . res://tests/TestLootDrops.tscn
SOAK_POWER=build godot --headless --path . res://tests/TestQuickRunSoak.tscn
SOAK_POWER=flow  godot --headless --path . res://tests/TestQuickRunSoak.tscn
```

Manual (lo que ninguna suite cubre): confirmar que el juego **nunca se pausa**; romper
una caja y que el arma entre sola con hueco libre; con 4 armas, mantener E para cambiar
y ver la vieja caer al suelo; matar al mini-jefe y recoger el núcleo (juice de
evolución); subir de nivel sin panel; en coop, dos jugadores al mismo pickup → solo uno.
