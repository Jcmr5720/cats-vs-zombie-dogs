# Mapas, semillas y enemigos actuales

Documento de referencia del estado actual del juego. Las fuentes principales son:

- `scripts/maps/map_data.gd`
- `scripts/maps/world_seed_manager.gd`
- `scripts/maps/biome_layout_generator.gd`
- `scripts/maps/city_plan.gd`
- `scripts/systems/run_phase_config.gd`
- `scripts/enemies/enemy_data.gd`
- `scripts/enemies/enemy.gd`
- `scripts/bosses/boss_data.gd`
- `data/maps/**/*.tres`
- `data/enemies/**/*.tres`
- `data/bosses/*.tres`

## 1. Tipos de mapa

El juego usa `MapData` como recurso data-driven. Cada mapa define identidad visual, bioma procedural, modificadores de dificultad, obstaculos, pesos de enemigos por fase, jefe principal y objetivo.

Actualmente hay 6 mapas definidos:

| Mapa | ID | Modo / uso | Bioma | Objetivo actual | Jefe asignado |
|---|---|---|---|---|---|
| Barrio Gatuno | `neighborhood` | Partida libre / base | `neighborhood` | Resistir fases y derrotar al Rottweiler Alfa | `rottweiler_charger` por defecto |
| Parque Abandonado | `park` | Partida libre / base | `park` | Resistir fases y derrotar al Mastin del Pantano | `swamp_mastiff` |
| Callejon Industrial | `industrial_alley` | Partida libre / base | `industrial` | Resistir fases y derrotar al Alfa de la Chatarra | `junkyard_alpha` |
| Barrio en Tinieblas | `neighborhood_dark` | Historia | `neighborhood` | Resistir el asedio y derrotar al jefe de la ola | `rottweiler_charger` por defecto |
| Corazon del Parque | `park_dark` | Historia | `park` | Limpiar el nido y derrotar al jefe de la plaga | `rottweiler_charger` por defecto |
| La Fabrica | `factory` | Historia | `industrial` | Sobrevivir y destruir al Alfa Primigenio | `alpha_prime` |

## 2. Biomas de mapa

Los mapas no son solo fondos: cada uno usa un bioma que cambia la estructura procedural del mundo.

### `neighborhood`

Bioma urbano. Genera calles, avenidas, intersecciones, pasos de cebra, semaforos, manzanas, plazas, estacionamientos, parques pequenos, esquinas de basura, coches aparcados y paradas de bus.

La red vial se calcula con una reticula global cada `512 px`. Cada 4 lineas hay una avenida garantizada, lo que crea continuidad entre chunks. Los distritos cambian por bloques de `4x4` chunks.

Mapas que lo usan:

- `neighborhood`
- `neighborhood_dark`

### `park`

Bioma abierto de parque. Genera senderos curvos, conectores verticales, claros, arboledas, bancos, zonas de picnic, kioskos, cercas rotas y lagos por regiones.

Los senderos y lagos son continuos entre chunks porque se calculan en coordenadas globales. Los lagos usan regiones de `3x3` chunks.

Mapas que lo usan:

- `park`
- `park_dark`

### `industrial`

Bioma industrial. Genera corredores de carga, calles de servicio, vias de tren, carriles de contenedores, naves, patios de carga, gruas, zonas de barriles, maquinaria y muros de tuberias.

Las avenidas garantizadas se convierten en `cargo_corridor`. Tambien puede aparecer una via de tren horizontal cada 3 filas de chunks.

Mapas que lo usan:

- `industrial_alley`
- `factory`

## 3. Tipos de semilla

El sistema procedural usa `WorldSeedManager`. La semilla controla la estructura del mapa y permite que el mundo sea estable mientras el jugador se mueve.

### Semilla global del mapa

Funcion: `WorldSeedManager.resolve_seed(map_data, override_seed = 0)`

Si `override_seed` es distinto de `0`, se usa esa semilla manual. Si no, se genera una semilla estable a partir del ID del mapa:

```gdscript
hash("cats-vs-zombie-dogs:%s" % map_id)
```

Uso practico:

- Misma semilla + mismo mapa = mismo layout.
- Cambiar el ID del mapa cambia el layout base.
- Usar `override_seed` permite probar o compartir una variante concreta.

### Semilla por chunk

Funcion: `WorldSeedManager.chunk_seed(world_seed, biome, coord, salt = 0)`

Combina:

- semilla global
- bioma
- coordenada de chunk `Vector2i`
- `salt`

Esto hace que cada chunk tenga decisiones propias, pero que sigan siendo reproducibles.

### Semilla por capa

Funcion: `WorldSeedManager.layer_rng(world_seed, biome, coord, layer)`

Crea un `RandomNumberGenerator` por capa logica. Sirve para separar decisiones dentro del mismo chunk, por ejemplo decoracion, detalles, anchors o capas visuales.

### Hash global por coordenada

Funcion: `WorldSeedManager.global_noise01(world_seed, biome, x, y, salt)`

Devuelve un valor `0..1` estable para una coordenada global. Se usa cuando una decision debe ser continua o coherente entre chunks.

### Salts

El `salt` es un numero extra para separar decisiones que usan los mismos datos base. Por ejemplo, un chunk puede necesitar tirar dados para caminos, props, lagos o detalles sin que una decision contamine otra.

## 4. Modificadores por mapa

| Mapa | Dificultad | Vida enemiga | Velocidad enemiga | Rescates | Identidad de enemigos |
|---|---:|---:|---:|---:|---|
| `neighborhood` | `1.0` | `1.0` | `1.0` | normal | mas `pack_zombie_dog`, `pup_zombie_dog`, `flanker_zombie_dog` |
| `park` | `1.1` | `1.0` | `1.05` | mas frecuentes (`0.8`) | mas `infection_carrier_dog`, `spitter_zombie_dog`, `howler_zombie_dog` |
| `industrial_alley` | `1.25` | `1.2` | `1.0` | menos frecuentes/lejanos (`1.3`, +120 px) | mas `tank_zombie_dog`, `charger_zombie_dog`, `splitter_zombie_dog` |
| `neighborhood_dark` | `1.45` | `1.25` | `1.1` | normal | mas `pack_zombie_dog`, `flanker_zombie_dog` |
| `park_dark` | `1.5` | `1.25` | `1.05` | mas frecuentes (`0.75`) | mas `infection_carrier_dog`, `howler_zombie_dog` |
| `factory` | `1.6` | `1.3` | `1.05` | menos frecuentes/lejanos (`1.3`, +120 px) | mas `tank_zombie_dog`, `charger_zombie_dog` |

Nota: `rescue_spawn_modifier` multiplica el intervalo. Menor que `1.0` significa rescates mas frecuentes; mayor que `1.0`, menos frecuentes.

## 5. Fases de aparicion de enemigos

Las partidas rapidas usan `RunPhaseConfig` y duran alrededor de 5 minutos, con limite absoluto cercano a 5:30.

| Tiempo | Fase | Enemigos principales |
|---:|---|---|
| `0s` | Intro | `zombie_dog`, `runner_zombie_dog` |
| `20s` | Horda comun | `zombie_dog`, `runner_zombie_dog`, `pack_zombie_dog`, `pup_zombie_dog` |
| `60s` | Especiales | comunes + `flanker_zombie_dog`, `howler_zombie_dog`, `spitter_zombie_dog`, `infection_carrier_dog` |
| `110s` | Pesados | especiales + `tank_zombie_dog`, `charger_zombie_dog`, `splitter_zombie_dog`, `hunter_zombie_dog` |
| `155s` | Mini-boss | aparece mini-boss y horda reducida |
| `200s` | Boss | aparece jefe principal y horda ligera |
| `255s` | Boss elite | el jefe se transforma si sigue vivo |
| `300s` | Furia final | se detienen spawns comunes y el jefe se enfurece |
| `330s` | Limite absoluto | derrota si el jefe sigue vivo |

Al inicio tambien aparece una manada inmediata de `12-16` mordedores y, cerca del segundo `6`, entran `5` corredores.

## 6. Enemigos comunes

| Enemigo | ID | Vida | Velocidad | Dano | XP | Coste amenaza | Comportamiento |
|---|---|---:|---:|---:|---:|---:|---|
| Mordedor | `zombie_dog` | 20 | 90 | 10 | 2 | 1.0 | Persecucion clasica |
| Corredor Rabioso | `runner_zombie_dog` | 12 | 150 | 8 | 2 | 1.0 | Persecucion rapida |
| Cachorro Infectado | `pup_zombie_dog` | 6 | 175 | 5 | 1 | 1.0 | Pequeno y muy rapido |
| Perro de Manada | `pack_zombie_dog` | 14 | 100 | 8 | 2 | 1.5 | Gana bonus cerca de otros perros de manada |

## 7. Enemigos especiales

| Enemigo | ID | Vida | Velocidad | Dano | XP | Coste amenaza | Comportamiento |
|---|---|---:|---:|---:|---:|---:|---|
| Flanqueador | `flanker_zombie_dog` | 18 | 130 | 9 | 4 | 2.0 | Rodea al jugador antes de cerrar distancia |
| Aullador | `howler_zombie_dog` | 26 | 70 | 6 | 8 | 3.0 | Potencia enemigos cercanos cada cierto tiempo |
| Escupidor | `spitter_zombie_dog` | 20 | 85 | 6 | 8 | 3.0 | Mantiene distancia y dispara proyectiles |
| Portador de Infeccion | `infection_carrier_dog` | 24 | 95 | 8 | 8 | 3.0 | Deja zona peligrosa al morir |

## 8. Enemigos pesados

| Enemigo | ID | Vida | Velocidad | Dano | XP | Coste amenaza | Comportamiento |
|---|---|---:|---:|---:|---:|---:|---|
| Mastin Blindado | `tank_zombie_dog` | 85 | 55 | 18 | 10 | 5.0 | Blindado, recibe menos empuje |
| Embestidor | `charger_zombie_dog` | 70 | 70 | 16 | 14 | 6.0 | Telegrafia una linea, embiste y queda vulnerable si falla o choca |
| Mutante Divisor | `splitter_zombie_dog` | 60 | 75 | 12 | 12 | 5.0 | Al morir se divide en dos cachorros |
| Cazador | `hunter_zombie_dog` | 55 | 120 | 14 | 14 | 6.0 | Prioriza al jugador mas vulnerable y salta hacia el objetivo |

## 9. Esbirros de jefe

Estos enemigos no forman parte de la horda normal. Los invocan los jefes segun sus fases de vida.

| Esbirro | ID | Vida | Velocidad | Dano | XP | Comportamiento |
|---|---|---:|---:|---:|---:|---|
| Guardian | `boss_guardian` | 90 | 90 | 10 | 6 | Se interpone entre jefe y jugador; al morir puede abrir vulnerabilidad |
| Sanador | `boss_healer` | 30 | 110 | 4 | 6 | Va hacia el jefe y canaliza curacion |
| Explosivo | `boss_exploder` | 16 | 140 | 0 | 4 | Enciende mecha cerca del jugador y explota, danando tambien enemigos |

## 10. Jefes actuales

| Jefe | ID | Tipo | Vida | Velocidad | Contacto | Ataque | XP | Esbirros | Uso actual |
|---|---|---|---:|---:|---:|---:|---:|---|---|
| Bulldog Bruto Zombi | `bulldog_brute` | `miniboss` | 320 | 58 | 16 | 0 | 90 | ninguno | Mini-boss |
| Rottweiler Alfa Zombi | `rottweiler_charger` | `boss` | 1400 | 66 | 16 | 34 | 200 | `boss_exploder` | Jefe por defecto / Barrio |
| Mastin del Pantano | `swamp_mastiff` | `boss` | 1500 | 62 | 16 | 32 | 200 | `boss_healer` | Parque |
| Alfa de la Chatarra | `junkyard_alpha` | `boss` | 1600 | 60 | 18 | 34 | 220 | `boss_guardian`, `boss_healer` | Callejon Industrial |
| Alfa Primigenio | `alpha_prime` | `boss` | 2600 | 74 | 20 | 42 | 320 | `boss_healer`, `boss_exploder` | Fabrica |

Los jefes principales tienen umbrales de fase `0.75`, `0.5` y `0.25`. En fase elite pueden cambiar de nombre y comportamiento. Por ejemplo, `swamp_mastiff` tiene `elite_leaves_hazard = true`.

## 11. Variantes elite de enemigos comunes

El `EnemySpawner` puede convertir enemigos comunes en elites segun el tiempo y la dificultad. Solo aplica a enemigos de tier `common`.

Tipos actuales:

- `veloz`
- `blindado`
- `gigante`

Estas variantes dan mas XP que el comun y cambian sus estadisticas/lectura visual desde `enemy.gd`.

## 12. Resumen rapido

- Mapas actuales: 6.
- Biomas procedurales: 3 (`neighborhood`, `park`, `industrial`).
- Sistema de semillas: determinista por mapa, chunk, capa y coordenada global.
- Enemigos normales de horda: 12 tipos.
- Esbirros de jefe: 3 tipos.
- Jefes/mini-jefes: 5 recursos.
- La aparicion de enemigos ya no depende solo de `spawn_weight`; en partidas rapidas manda el perfil de fase y luego cada mapa multiplica pesos concretos.
