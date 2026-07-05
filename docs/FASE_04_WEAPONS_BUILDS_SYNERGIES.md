# FASE 04 — Sistema modular de armas, builds y sinergias

Convierte al gato de "una pistola automática" en un **constructor de builds**: varias
armas activas (máx. 4), cada una con comportamiento propio, niveles, y sinergias con
los compañeros rescatados. Todo data-driven, sin assets externos, sin romper Fases 01–03.5.

> Validado en Godot 4.7 headless: import limpio + corridas de runtime sin errores de
> script ejercitando los 6 tipos de arma, el tope de 4 armas, subir a nivel máximo, las
> sinergias con compañeros, la selección de cartas y la limpieza al reiniciar.

---

## 1. Qué se implementó

- **WeaponManager** en el jugador (sustituye a `AutoWeapon`): arranca con la Pistola
  Gatuna y admite hasta **4 armas** activas, cada una un `WeaponBase` hijo.
- **WeaponBase** data-driven: una sola clase resuelve 6 tipos de arma por `weapon_type`.
- **6 armas**: Pistola Gatuna, Ovillo Explosivo, Sardina Boomerang, Puntero Láser,
  Rascador Giratorio (orbital) y Granada de Catnip (área).
- **Niveles 1–5** por arma con mejoras crecientes (daño/cooldown/proyectiles/área/pierce/orbitales).
- **Cartas dinámicas** en el UpgradeManager: arma nueva, mejora de arma, stat general y
  compañero, según el estado real (respeta tope de 4 armas y nivel máximo).
- **Sinergias con compañeros** (leen compañeros activos, ignoran derribados).
- **HUD de armas** (nombre + nivel, hasta 4) y etiqueta de **tipo** en cada carta.
- **Limpieza total** al reiniciar (las armas/orbitales cuelgan del jugador; los
  proyectiles/áreas del nivel → se liberan con `reload_current_scene`).

## 2. WeaponData (`scripts/weapons/weapon_data.gd`)

Recurso con los valores de **nivel 1**. Campos clave: `id`, `display_name`,
`description`, `weapon_type`, `damage`, `cooldown`, `range`, `projectile_speed`,
`projectile_count`, `spread_degrees`, `area_radius`, `duration`, `pierce`, `knockback`,
`tick_interval`, `visual_color`, `rarity`, `rarity_weight`, `max_level`,
`scales_with_global_stats`.

`weapon_type` soportados: `projectile`, `explosive`, `boomerang`, `laser`, `orbital`, `area`.

## 3. WeaponBase (`scripts/weapons/weapon_base.gd`)

Instancia viva de un arma. Cada frame:
- **Orbital**: mantiene N "rascadores" girando (nodos `Orbital.tscn`) y los reconfigura.
- **Resto**: descuenta cooldown y dispara al vencerse (proyectiles / láser / área).

Stats efectivos = base · escala por nivel · **modificadores globales** del jugador ·
**sinergias**. Reglas de nivel (resumen):

| Arma                | Nv2        | Nv3            | Nv4            | Nv5               |
|---------------------|------------|----------------|----------------|-------------------|
| Pistola (projectile)| +daño/cad. | +daño/cad.     | **+1 proyectil**| +daño/cad./rango |
| Ovillo (explosive)  | +área/daño | +área/daño     | +área/daño     | **explosión mayor**|
| Sardina (boomerang) | +daño/vel. | **+1 pierce**  | +daño/vel.     | **+1 pierce, +proy.**|
| Láser (laser)       | +daño/cad. | **+rango**     | +daño/cad.     | +daño/cad.        |
| Rascador (orbital)  | +daño/radio| +daño/radio    | **+1 rascador**| +daño/giro        |
| Catnip (area)       | +zona/daño | +zona/daño     | +zona/daño     | +zona/daño        |

(Daño +15%/nivel, cooldown −6%/nivel, rango +5%/nivel, área +18%/nivel como base genérica.)

## 4. WeaponManager (`scripts/weapons/weapon_manager.gd`)

- `add_weapon(WeaponData)`, `level_up_weapon(id)`, `has_weapon(id)`, `get_weapon(id)`.
- `can_add_weapon()` (tope `max_weapons = 4`), `get_available_new_weapons()`,
  `get_upgradable_weapons()`, `get_weapon_snapshots()` (HUD).
- **Modificadores globales** (de las cartas de stat clásicas): `multiply_damage`,
  `multiply_cooldown`, `multiply_range`, `add_projectiles`, `set_external_damage_multiplier`.
- Recalcula las **sinergias** una vez por frame leyendo el grupo `companions`.
- Emite `weapons_changed(snapshots)` → HUD (lo encuentra por el grupo `hud`).

El registro de armas (`WEAPON_REGISTRY`) lista los `.tres`; para añadir un arma nueva
basta crear el recurso y sumar su ruta ahí.

## 5. Integración con las cartas (`upgrade_manager.gd`)

Cada subida de nivel arma un pool dinámico de candidatos:
1. **Arma nueva** — una por arma que no tienes (solo si `can_add_weapon()`).
2. **Mejora de arma** — una por arma tuya por debajo de nivel máximo (peso ×1.3).
3. **Stat general** — `STAT_POOL` (afectan a todas las armas o al jugador).
4. **Compañero** — `COMPANION_POOL` (solo si ya rescataste alguno).

Se sortean 3 cartas distintas ponderadas por rareza. La carta muestra **tipo · rareza**,
nombre, descripción y (en mejoras) el nivel destino. No se ofrecen armas nuevas con 4
armas, ni mejoras de un arma al máximo.

## 6. Sinergias con compañeros

Leen compañeros **activos** (los derribados no cuentan):

| Compañero activo      | Efecto                                                |
|-----------------------|-------------------------------------------------------|
| Gato Policía          | Pistola Gatuna **+10% daño**.                         |
| Gato Ingeniero        | Ovillo y Catnip **+10% daño y +10% área**.            |
| Gato Médico           | Rascador Giratorio **+10% daño**.                     |
| 3+ compañeros activos | **−5% cooldown** en todas las armas.                  |

Editable en `weapon_manager.gd` (`synergy_damage_mult`, `synergy_cooldown_mult`,
`synergy_area_mult`). Pueden ampliarse sin tocar las armas.

## 7. Mejoras de compañeros incluidas en esta fase

- **Médico con utilidad continua**: ahora tiene **regeneración pasiva** (aura que cura un
  poco a aliados/jugador cercanos cada 2 s), además de su cura reactiva. Parámetros en
  `companion_data.gd` (`passive_regen`, `passive_regen_interval`, `passive_regen_range`)
  y en `data/companions/medic_cat.tres`.
- **Dificultad por compañero suavizada**: `companion_weight 1.1 → 0.7`,
  `downed_companion_weight −0.3 → −0.25` (con armas la presión ya crece por otros lados).
- **Rescate rediseñado**: animación del punto más calmada (bob del gato + halo que respira
  + anillo "sonar") y **flecha sutil** que orbita al jugador apuntando al rescate activo
  (`scripts/companions/rescue_arrow.gd`, nodo `RescueArrow` en `Player.tscn`).

## 8. Balance (valores nivel 1)

| Arma      | Daño | Cooldown | Rango | Extra                         | Rareza |
|-----------|------|----------|-------|-------------------------------|--------|
| Pistola   | 8    | 0.55     | 500   | 1 proyectil                   | común  |
| Ovillo    | 12   | 1.4      | 480   | área 80                       | raro   |
| Sardina   | 7    | 1.1      | 520   | pierce 3                      | raro   |
| Láser     | 20   | 2.2      | 620   | rayo instantáneo              | épico  |
| Rascador  | 5    | 0.4*     | —     | radio 90, 1 orbital           | raro   |
| Catnip    | 4    | 3.0      | 420   | área 110, dura 3 s, tick 0.5  | épico  |

(*Rascador: `cooldown` se usa como cooldown de daño por enemigo.)

Los topes globales de stats viven en `weapon_manager.gd` (clamps de los multiplicadores).
La dificultad escala con el nivel del jugador y las mejoras elegidas (las cartas de arma
también cuentan), así que más armas → más presión enemiga.

## 9. Cómo probar (PARTIDAS)

- **A — segunda arma**: sube de nivel; elige una carta "Arma nueva: …".
- **B — subir a Nv. 3**: elige dos veces la mejora de una misma arma.
- **C — tope de 4**: consigue 4 armas; al subir de nivel ya **no** aparecen armas nuevas,
  solo mejoras/stats/compañeros.
- **D — cada arma**: comprueba visual/comportamiento (bala, ovillo+explosión, sardina que
  atraviesa, rayo láser, rascador orbital, zona de catnip).
- **E — sinergia**: rescata el Gato Policía y observa que la Pistola pega más fuerte.
- **F — reinicio**: muere, pulsa R; el HUD de armas vuelve a "Pistola Nv. 1" y no quedan
  proyectiles/orbitales/áreas viejos.
- **G — poder vs presión**: arma una build fuerte; los enemigos siguen escalando.

## 10. Cómo agregar una nueva arma

1. Crea `data/weapons/mi_arma.tres` con `weapon_data.gd`.
2. Elige un `weapon_type` soportado (o amplía el `match` de `weapon_base.gd`).
3. Añade su ruta a `WEAPON_REGISTRY` en `weapon_manager.gd`.
4. (Opcional) Sinergias en `weapon_manager.gd` y descripción de nivel en
   `weapon_base.next_level_description()`.

## 11. Parámetros editables

- **Armas**: los `.tres` en `data/weapons/`.
- **Escala por nivel**: `weapon_base.gd` (`_effective_*`).
- **Tope de armas / clamps globales**: `weapon_manager.gd`.
- **Sinergias**: `weapon_manager.gd` (`synergy_*`).
- **Cartas / rarezas**: `upgrade_manager.gd` (`STAT_POOL`, `COMPANION_POOL`, `RARITY_WEIGHTS`).

## 12. Riesgos conocidos

- El "boomerang" es la versión **simple con pierce** (no hay regreso real), como permite el brief.
- `WeaponBase` busca el enemigo más cercano iterando el grupo `enemies`; con 4 armas son
  varias búsquedas por frame, baratas con el tope de 90 enemigos pero a vigilar si sube.
- `auto_weapon.gd` queda como código migrado/huérfano (ya no se referencia); se puede
  borrar en una limpieza futura.
- Las sinergias se recalculan por frame en el WeaponManager; es O(compañeros), trivial.

## 13. Pendiente para FASE 05

- **Evoluciones finales** de arma (combinando arma a máx. nivel + cierto compañero/stat).
- Más sinergias y armas; sacar las descripciones de nivel a datos.
- Iconos reales de arma en el HUD (hoy texto).
- Élites/jefes que pongan a prueba cada build.
