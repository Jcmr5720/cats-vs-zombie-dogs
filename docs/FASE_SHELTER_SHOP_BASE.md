# FASE 10 — Refugio Felino: tienda, colocación y bonificaciones permanentes

## Qué se implementó

Una modalidad fuera de partida: el **Refugio Felino**, accesible desde el menú
principal (botón "Refugio"). El jugador compra objetos con Sardinas, los coloca
en slots fijos del refugio y **solo los objetos colocados otorgan bonificaciones**
al iniciar cada partida. Incluye tienda con 5 categorías y 12 objetos mejorables
(nivel 1-5), panel de bonificaciones activas, tutorial de primera visita,
guardado compatible con saves antiguos y balance con topes.

Pulido posterior: el refugio ahora incluye feedback visual al colocar/quitar
objetos, un gato interactivo sobre la alfombra, musica ambiental propia y
desbloqueos opcionales por Historia mediante `unlock_condition`.

## Arquitectura

| Pieza | Archivo | Rol |
|---|---|---|
| Datos de objeto | `scripts/shelter/shelter_item_data.gd` + `data/shelter_items/*.tres` | Resource data-driven por objeto |
| Manager (autoload `Shelter`) | `scripts/shelter/shelter_manager.gd` | compra/mejora/colocación/estado/señales |
| Calculador de bonus | `scripts/shelter/shelter_bonus_calculator.gd` | funciones puras + topes de balance |
| Escena del refugio | `scenes/shelter/ShelterMenu.tscn` + `scripts/shelter/shelter_menu.gd` | habitación, slots, panel de bonus, tutorial |
| Tienda | `scenes/shelter/ShelterShopPanel.tscn` + `scripts/shelter/shelter_shop_panel.gd` | categorías, estados, comprar/mejorar/colocar |
| Slot | `scripts/shelter/shelter_slot.gd` | botón con estado visual y dibujo del objeto |

### ShelterItemData
`id, display_name, description, category, price, max_level (5),
upgrade_base_cost, upgrade_cost_growth, effect_type, effect_value_per_level,
visual_color, accent_color, size, allowed_slots, unlock_condition, sort_order`.
La compra deja el objeto en **nivel 1**; cada mejora cuesta
`upgrade_base_cost * growth^(nivel-1)`.

### ShelterManager (autoload "Shelter")
- Carga `ITEM_PATHS` (12 objetos) y define `SLOTS` (8 slots fijos con categorías
  permitidas; `free_1` acepta todo).
- API: `get_items/get_item/get_slots`, `is_purchased/get_level`,
  `can_purchase/purchase`, `get_upgrade_cost/can_upgrade/upgrade`,
  `slot_accepts/place_item/remove_from_slot`, `get_bonuses/get_bonus`,
  `get_power_score`, `has_seen_tutorial/mark_tutorial_seen`.
- Señales: `shelter_items_changed`, `shelter_item_purchased`,
  `shelter_item_upgraded`, `shelter_item_placed`, `shelter_bonus_changed`.
- Reglas que garantiza: no comprar dos veces, no comprar/mejorar sin Sardinas,
  no pasar del nivel máximo, no colocar objetos no comprados, no colocar dos
  objetos en el mismo slot (hay que quitar primero), un objeto nunca está en
  dos slots (colocarlo lo muda).

### Cálculo de bonus
`ShelterBonusCalculator.compute(items_by_id, levels, placed_slots)` suma
`effect_value_per_level * nivel` **solo de los objetos colocados** y aplica los
topes de `CAPS`. Claves: `player_damage_bonus, player_speed_bonus,
player_max_health_bonus, companion_health_bonus, companion_police_damage_bonus,
companion_engineer_damage_bonus, medic_heal_bonus, sardines_reward_bonus,
rescue_first_spawn_reduction, rescue_distance_modifier, damage_reduction_bonus,
upgrade_rarity_bonus`.

## Los 12 objetos

| Objeto | Categoría | Efecto por nivel | Tope (nivel 5) |
|---|---|---|---|
| Rascador de Combate | entrenamiento | +3% daño | +15% |
| Cinta de Agilidad | entrenamiento | +2% velocidad | +10% |
| Saco de Pelea Gatuno | entrenamiento | +5 vida | +25 |
| Camas de Colonia | companeros | +5 vida compañeros | +25 |
| Estación Médica | companeros | +1 cura médico | +5 |
| Mesa de Herramientas | companeros | +5% daño ingeniero | +25% |
| Puesto de Vigilancia | companeros | +5% daño policía | +25% |
| Almacén de Sardinas | economia | +5% sardinas | +25% |
| Caja de Suministros | economia | +2% rareza cartas | +10% |
| Radio de Maullidos | rescate | primer rescate -3s | -15s (piso: seg. 15) |
| Mapa de Refugios | rescate | rescates -3% distancia | -15% |
| Barricada de Cartón | defensa | -2% daño recibido | -10% |

## Integración con gameplay (dónde se aplican)

- **Player** (`player.gd::_apply_permanent_upgrades`): vida (+cap 220), velocidad
  (+cap 420), daño (multiplica el `set_permanent_damage_mult` de armas junto a
  las mejoras permanentes — fuentes distintas, se suman sin duplicar), y la
  reducción de daño se suma a la de "Pelaje Erizado" con tope global 35%.
- **Compañeros** (`companion_manager.gd::_ready` + `_apply_bonuses_to`): vida
  plana vía `companion.set_shelter_health_bonus` (companion.gd usa el helper
  `_max_health()`), cura del médico vía `increase_medic_heal`, y el daño de
  policía/ingeniero se multiplica POR TIPO al repartir `set_bonuses`.
- **Rescates** (`rescue_spawner.gd::_ready`): la reducción del primer rescate se
  suma a "Llamado de la Colonia"; el piso de 15 s ya existe en
  `_schedule_next_spawn`. La distancia multiplica min/max con piso de 220 px.
- **Sardinas** (`map_manager.gd::_finish_run`): línea "refugio" en el desglose,
  aplicada sobre lo ganado antes de los multiplicadores de Plaga/Historia.
- **Rareza de cartas** (`upgrade_manager.gd::_rarity_weight`): peso de raras y
  épicas × (1 + bonus), cacheado por run.
- **Dificultad** (`enemy_spawner.gd`): `_difficulty_score += shelter_power * 0.10`,
  donde el poder es la suma ponderada de niveles COLOCADOS (economía/rescate
  pesan 0.5; comprar sin colocar no sube la presión).

## Guardado

Bloque anidado `"shelter"` en el save (SaveManager `get_value/set_value`):

```json
"shelter": {
  "purchased_items": ["combat_scratcher"],
  "item_levels": {"combat_scratcher": 2},
  "placed_slots": {"training_1": "combat_scratcher"},
  "seen_tutorial": true,
  "total_spent": 130
}
```

`SaveData.defaults()` incluye la estructura vacía y `sanitize()` la valida campo
a campo (tipos forzados, niveles ≥1, gasto ≥0, campos desconocidos descartados).
**Saves antiguos sin el bloque reciben los defaults sin crashear** (cubierto por
`tests/test_shelter.gd`).

## Cómo agregar un objeto nuevo

1. Crear `data/shelter_items/mi_objeto.tres` (duplicar uno existente).
2. Elegir `effect_type` existente o añadir uno nuevo a
   `ShelterBonusCalculator.EFFECT_TO_KEY` + `CAPS` + `KEY_LABELS` y leerlo en el
   sistema correspondiente.
3. Añadir la ruta a `ShelterManager.ITEM_PATHS`.
4. Si necesita slot propio, añadirlo a `ShelterManager.SLOTS`.

## Balance

Todos los topes viven en `ShelterBonusCalculator.CAPS` (un solo lugar). El
refugio a tope completo da ~+15% daño / +10% velocidad / +25 vida — ayuda
notable pero menor que una build de cartas de una run. La dificultad compensa
con `shelter_power * 0.10` solo por lo colocado.

## Riesgos conocidos / pendiente

Nota: `unlock_condition` ya tiene logica basica; la linea historica de abajo
queda como contexto de la primera entrega de la fase.

- Los slots son fijos (8); si se agregan muchos objetos por categoría habrá que
  añadir slots o crear rotación de "loadouts".
- `unlock_condition` está reservado pero sin lógica (todos los objetos
  disponibles desde el inicio).
- El botón opcional "Jugar" desde el refugio no se implementó (sale por Volver).
- La colocación usa modo "elegir slot resaltado" (sin drag & drop): simple a
  propósito.
- El bonus de rareza multiplica pesos de raras/épicas; con pools futuros muy
  grandes conviene revisar la curva.
