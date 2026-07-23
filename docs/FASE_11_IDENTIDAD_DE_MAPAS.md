# FASE 11 — Identidad real de mapas: guion por semilla, mutaciones y mecánicas exclusivas

> **ESTADO: IMPLEMENTADA (primera iteración).** Ver §10 al final: qué quedó
> construido, archivos tocados y pendientes. Los bloques A–D y F están operativos
> en los 6 mapas; del bloque E (luz/oscuridad real) solo entró el evento de
> apagón — el sistema de luz por farolas sigue pendiente de su spike.

> **Filosofía:** cada mapa debe obligar al jugador a moverse, priorizar enemigos y
> construir su personaje de una manera diferente. Cambiar vida/velocidad/cantidad no
> crea identidad.
>
> **Regla de producción:** 70 % sistemas compartidos, 20 % combinaciones exclusivas,
> 10 % mecánicas totalmente únicas. Sin romper guardado, coop, armas, compañeros,
> rendimiento (caps de FASE 08.75) ni el flujo de fases existente.
>
> **Orden de entrega:** Bloque A → B → C → D → E → F. Cada bloque deja el juego
> jugable y validado en headless antes de empezar el siguiente.

---

## 0. Diagnóstico (estado actual)

Lo que ya existe y se reutiliza tal cual:

- **Cronología de fases**: `RunPhaseConfig` ya implementa la estructura objetivo
  (COMMON 20 s, SPECIAL 60 s, HEAVY 110 s, MINIBOSS 155 s, BOSS 200 s, ELITE 255 s,
  FURIA 300 s, LÍMITE 330 s). **No se tocan los tiempos.**
- **Roster de comportamientos**: los 12 enemigos + 3 esbirros ya cubren la tabla de
  "preguntas" (flanker, howler, spitter, carrier, pack, armored, charger, splitter,
  hunter, guardian, healer, exploder).
- **Semilla por partida**: `GameFlow.get_run_seed()` → `MapManager._resolve_world_seed()`.
  Hoy solo alimenta geometría/obstáculos/decoración.
- **Distritos**: `CityPlan.district()` ya varía distritos por bloques de 4×4 chunks.
- **Zona de daño**: `hazard_zone.gd` (charco de infección) es el embrión del sistema
  compartido de zonas.
- **Identidad de jefe por datos**: `BossData.minion_classes` y `elite_leaves_hazard`.

El problema: la única identidad que llega al gameplay es `phase_weight_overrides`
(multiplicadores de peso), el jefe asignado y los colores. Los elites son genéricos
(`veloz`/`blindado`/`gigante` al azar en `enemy_spawner.gd`), el WaveEventManager está
suspendido por el PhaseDirector, y la semilla no decide nada mecánico.

---

## Bloque A — Identidad inmediata: mutaciones por bioma + guion por semilla

**Objetivo:** que dos partidas del mismo mapa se sientan distintas y que cada mapa
tenga elites propios. Todo data-driven, sin sistemas nuevos de gameplay.

### A1. Mutaciones élite por bioma

- `MapData` nuevo campo (grupo "Identidad de combate"):
  - `@export var biome_mutations: Array[StringName] = []` — pool de mutaciones élite
    del mapa. Vacío = pool genérico actual.
- `enemy_spawner.gd` (~línea 609): en vez de `[veloz, blindado, gigante].pick_random()`,
  pedir el pool al mapa activo (vía grupo `map_manager` o setter en
  `_apply_spawner_modifiers()`). La **mutación dominante** del guion (A2) pesa doble
  en el pick.
- `enemy.gd::_apply_elite()`: nuevas ramas de mutación. Primera tanda (2 por bioma,
  las de menor riesgo; el resto en D cuando existan zonas/interactables):
  - **Barrio** — `lider_manada`: aura que da +15 % velocidad a perros en 220 px;
    `carronero`: se cura 4 HP por cadáver cercano (usa timestamps de kills, sin nodos).
  - **Parque** — `esporoso`: al morir deja un `hazard_zone` pequeño (reusa el del
    carrier, respeta `MAX_HAZARD_ZONES`); `paras ito`: al morir suelta 2 `pup_zombie_dog`
    (respeta caps del spawner).
  - **Industrial** — `volatil`: si recibe ≥ 30 % de su vida en < 1 s, explota (daña a
    AMBOS bandos, radio 120 px, telegraph 0.5 s); `chatarra`: 3 placas de armadura
    direccional que se rompen por etapas (extiende la lógica del blindado actual).
  - **Oscuros** — `sabueso`: reengancha al jugador aunque pierda línea de visión
    (ignora `_avoid` de obstáculos parcialmente); `nocturno`: +streaks visuales y
    +20 % velocidad (versión completa cuando exista luz/oscuridad en E).
  - **Fábrica** — `sobrecargado`: alterna 2 s rápido / 1.2 s aturdido y vulnerable
    (+50 % daño recibido); `prototipo`: combina el comportamiento de su `behavior`
    con uno segundo aleatorio del roster (solo pares seguros, tabla blanca).
- Los `.tres` de los 6 mapas rellenan su pool (los mapas de historia oscuros usan el
  pool "oscuros" + el de su bioma base).

### A2. Guion procedural por semilla (`RunScript`)

- Nuevo `scripts/systems/run_script.gd` (`RefCounted`, estilo `WorldSeedManager`):
  derivación **estática y determinista** desde `(world_seed, map_id)` con los mismos
  hashes salteados. Campos:
  - `central_event: StringName` — elegido del `dynamic_event_pool` del mapa (C1).
  - `dominant_mutation: StringName` — elegida de `biome_mutations`.
  - `boss_modifier: StringName` — elegida de `boss_modifier_pool` del mapa (F).
  - `district_bias: StringName` — distrito favorecido; `CityPlan.district()` recibe
    un bias opcional (sube el peso de ese distrito, no elimina los demás).
  - `opening_variant: int` — 0..N variantes de apertura del mapa (A3).
- `MapManager` lo construye en `_apply_active_map()` y lo expone
  (`get_run_script()`); PhaseDirector, EnemySpawner y BossSpawner lo consultan.
- El panel de pausa (que ya muestra la seed) añade una línea con el guion:
  "Evento: apagón · Mutación: sabueso · Jefe: destructor".

### A3. Apertura con identidad (0–30 s)

- `MapData`: `@export var opening_pack_id: StringName = &"zombie_dog"` y
  `@export var opening_variety_id: StringName = &"runner_zombie_dog"`.
- `PhaseDirector._start_run()` y el spawn del segundo 8 leen del mapa en vez de
  hardcodear. Ej.: Barrio abre con `pack_zombie_dog`, Parque con `zombie_dog` +
  `infection_carrier_dog` a los 8 s, Industrial con `zombie_dog` + `charger` a los 8 s.
- `opening_variant` del guion elige entre 2 combinaciones por mapa.

**Criterios de aceptación (A):**

- Dos seeds distintas del mismo mapa producen guiones distintos visibles en pausa;
  la misma seed reproduce el mismo guion (test unitario de `RunScript`).
- En Barrio nunca aparece un elite `esporoso`; en Parque nunca un `lider_manada`
  (test de pool).
- Soak headless de 2600 frames por mapa sin ERROR (procedimiento de validación §7).
- Los caps de FASE 08.75 se respetan: `parasito`/`esporoso` no superan
  `MAX_HAZARD_ZONES` ni los topes de enemigos.

---

## Bloque B — Escalado por comportamiento: niveles 1/2/3

**Objetivo:** que la dificultad crezca por conducta, no por estadística. Las subidas
de stats por dificultad se mantienen, pero el "salto" perceptible viene de aquí.

### B1. Infraestructura

- `EnemyData`: `@export var behavior_levels: int = 1` (cuántos niveles implementa).
- `enemy.gd`: `var behavior_level: int = 1` + setter. Las ramas de comportamiento
  consultan el nivel; nivel no implementado = comportamiento del nivel anterior.
- `enemy_spawner.gd`: al spawnear asigna nivel según fase del director:
  - INTRO/COMMON → 1; SPECIAL/HEAVY → 2; MINIBOSS en adelante → 3.
  - El director ya expone `get_phase()`; el spawner ya recibe `set_phase_profile` —
    añadir el nivel al perfil (`"behavior_level"`) para no crear otro canal.

### B2. Primera tanda de niveles (3 enemigos, los del documento)

- **Perro de Manada** — N1: bono cerca de otros perros (actual). N2: busca formar
  semicírculo (offset angular por instancia alrededor del jugador, reusa la
  separación existente). N3: cada ~9 s un perro del grupo se marca líder 3 s
  (tinte + aura) y ordena carga radial (los del semicírculo aceleran 1.5 s).
- **Escupidor** — N1: dispara al jugador (actual). N2: predice usando la velocidad
  del jugador (lead simple). N3: si hay ≥ 2 escupidores vivos, sincronizan y abren
  el ángulo para cerrar la escapatoria (barrera). Respetar `MAX_ENEMY_PROJECTILES`.
- **Embestidor** — N1: embestida recta (actual). N2: prefiere alinearse con
  corredores largos (raycast en 4 direcciones, elige la más despejada que cruce al
  jugador). N3: la embestida rompe obstáculos `destructible` (activa por fin los
  datos `destructible/health` de `ObstacleData`, dormidos desde FASE 08.75) y
  empuja a otros enemigos a su paso.

Los demás enemigos declaran `behavior_levels = 1` y quedan para iteraciones futuras
(un enemigo nuevo por tanda; no bloquear la fase por esto).

**Criterios de aceptación (B):**

- Test headless con `debug_set_time()`: a los 30 s los pack son N1, a los 120 s N2,
  a los 200 s N3 (inspección de `behavior_level` de vivos).
- El semicírculo N2 no produce atascos O(n²) nuevos: FPS del soak ≥ el baseline de
  la rama antes del bloque (comparar `Performance.get_debug_line()`).
- Un embestidor N3 destruye una valla y no destruye una casa (peso/vida de obstáculo).

---

## Bloque C — Evento central por mapa + sistema de zonas compartido

**Objetivo:** el hueco 110–155 s del guion ("evento de mapa") y la pieza 70 %
compartida que sostiene todas las mecánicas exclusivas.

### C1. Eventos centrales (`dynamic_event_pool`)

- `MapData`: `@export var dynamic_event_pool: Array[StringName] = []`.
- `WaveEventManager` revive como ejecutor de eventos de mapa **bajo el director**
  (nuevo método `trigger_map_event(id)`; el calendario clásico sigue suspendido).
  El PhaseDirector dispara `run_script.central_event` a los ~115 s con anuncio HUD.
- Primera tanda de eventos (2 por mapa base, elegidos por semilla):
  - **Barrio** — `street_block`: 2–3 avenidas se cierran con barricadas (obstáculos
    temporales colisionables, 40 s); `stray_horde`: manada grande entra por un solo
    arco (reusa `spawn_pack` con bias direccional de horda).
  - **Parque** — `lake_fog`: el lago emite niebla + 3 zonas de infección en su
    orilla; `carrier_bloom`: +peso de carriers 30 s y sus charcos duran el doble.
  - **Industrial** — `freight_train`: un tren cruza la vía (telegraph 2 s, daña a
    AMBOS bandos en el carril, 8 s); `steam_burst`: 4 bocas de vapor fijas se
    activan intermitentes 45 s (zonas de daño dual pulsantes).
- Los mapas de historia heredan el pool de su bioma hasta E/F.

### C2. Generalización de `hazard_zone` → `zone.gd`

- Renombrar internamente a "zona" con parámetros (mantener la escena/uso actual del
  charco como preset):
  - `faction`: `players` (charco actual) / `enemies` / `both` (industrial).
  - `persistent: bool` — no expira por tiempo; solo por límite/limpieza/interacción.
  - `spread: float` — crecimiento de radio por segundo (contaminación del Parque).
  - `visual_kind`: infección / vapor / fuego químico / oscuridad / territorio
    (mismo `_draw` con paletas y patrones por tipo; nada de assets nuevos).
- **Presupuesto**: `MAX_HAZARD_ZONES` sube a un presupuesto por tipo
  (`RunPhaseConfig.ZONE_BUDGET = {infection: 6, industrial: 4, territory: 3, ...}`).
  Zonas persistentes que se tocan **se fusionan** (una absorbe a la otra y suma
  radio con tope), igual que la fusión de orbes de XP: n acotado por diseño.
- Daño a enemigos: tick barato iterando el grupo `enemies` solo para zonas con
  `faction != players` (mismo patrón de tick de 0.5 s del charco actual).

### C3. Contaminación persistente del Parque (primera mecánica exclusiva)

- Con C2 lista, el Parque activa su regla: los charcos de carriers/esporosos son
  `persistent` con `spread` lento. El HUD ya no necesita nada nuevo: la lectura es
  espacial.
- Válvula de escape (decisión del jugador, no castigo): una zona se limpia si el
  jugador permanece 3 s en su borde sin recibir daño de ella… **no** — demasiado
  raro. Regla simple: las zonas persistentes decaen solo cuando el jefe del mapa
  muere o cuando se fusionan sobre el tope del presupuesto (la más vieja se libera).
  El jugador gestiona DÓNDE mata, que es exactamente la pregunta del carrier.

**Criterios de aceptación (C):**

- Cada partida dispara exactamente un evento central entre 110–155 s (test con
  `debug_set_time`), con anuncio en HUD y fin limpio (obstáculos temporales se
  liberan, vapor se apaga).
- El tren/vapor matan enemigos y dañan al jugador (test de facción dual).
- Con 50 carriers muertos encima del jugador, el número de zonas vivas nunca supera
  el presupuesto y el FPS del soak no baja del baseline (fusión funcionando).
- La misma seed dispara el mismo evento; seeds distintas alternan el pool.

---

## Bloque D — Interactables de mapa + objetivos de sabotaje

**Objetivo:** objetos del mundo con los que se combate (territorio del Barrio, nidos
del Corazón, líneas de la Fábrica) y el tipo de objetivo "destruir N".

### D1. Sistema de interactables (`scripts/maps/map_interactable.gd`)

- Generaliza el patrón de `rescue_point` + `obstacle`: `StaticBody2D` con vida,
  registrado en grupo `map_interactables`, **apuntable por las armas** (se añade al
  grupo `enemies` de targeting o las armas aprenden un grupo secundario — decidir en
  implementación; la opción targeting-secundario evita tocar la IA de compañeros).
- Data-driven: `interactable_data.gd` (id, vida, radio, aura, efecto al morir,
  efecto pasivo mientras vive). Aparece en minimapa como marcador propio (el
  `minimap_entity_registry` ya soporta tipos de marcador).
- `MapData`: `@export var interactable_spawns: Array[Dictionary]` (id, cuándo, cuántos)
  y objetivo nuevo `@export var destroy_required: int = 0` +
  `destroy_target_id: StringName` (se integra al resumen de objetivos del
  MapManager como los rescates).

### D2. Territorio de manada (Barrio)

- Interactable `howl_post` (marca de aullido): mientras vive, proyecta una **zona
  territorio** (C2, `visual_kind = territory`, sin daño): dentro, perros +12 %
  velocidad y los flanqueadores spawnean directamente en el borde de la zona.
- Aparecen 1 en SPECIAL, +1 en HEAVY, +1 con el jefe (el Alfa la planta él — F).
- Destruir la marca libera la zona con un pulso de knockback (premio inmediato).

### D3. Nidos conectados (Corazón del Parque)

- 3 nidos con roles distintos (spawner / sanador de enemigos / contaminador), del
  mismo sistema D1 con `interactable_data` distinto. El guion (A2) elige qué 3 roles
  de un pool de 5. Mientras vivan ≥ 2, se "conectan": línea visual y +10 % de efecto.
- El objetivo del mapa pasa a: destruir 2 nidos + derrotar al jefe.

### D4. Líneas de producción (Fábrica)

- 3 interactables `production_line`: cada uno, cada 20 s, aplica su efecto global:
  produce un pack de corredores / blinda un enemigo vivo al azar (le añade la
  mutación `chatarra`) / repara al jefe 3 % (solo si el jefe está vivo).
- Objetivo: sabotear 2 líneas antes del jefe; si llegan vivas al BOSS, el jefe entra
  con su ventaja correspondiente (más vida inicial / escolta blindada).

**Criterios de aceptación (D):**

- Las armas y compañeros pueden dañar interactables sin dejar de priorizar enemigos
  cercanos (test de targeting).
- Con las 3 líneas vivas la Fábrica se siente distinta a con 0 (telemetría del test
  de balance: tiempo-de-kill del jefe difiere ≥ 15 %).
- Minimapa muestra los interactables y el HUD cuenta el objetivo "Sabotea 2/3".
- Soak por mapa sin ERROR; caps intactos.

---

## Bloque E — Tinieblas: luz contra oscuridad (spike primero)

**Objetivo:** la única mecánica que necesita tecnología nueva. Se hace DESPUÉS de que
A–D den identidad al resto, y empieza con un spike técnico de riesgo acotado.

### E1. Spike técnico (timebox: 1 sesión)

- Restricción: renderer `gl_compatibility` (decisión firme del proyecto) y ambiente
  actual por CanvasModulate/overlays custom, no Light2D.
- Probar DOS enfoques en una escena de prueba y medir FPS con 150 enemigos:
  1. **Overlay con agujeros**: un `CanvasLayer` oscuro dibujado con `_draw` y
     agujeros radiales (blend subtractivo) en farolas/jugador — mismo estilo que
     `camera_overlay.gd`.
  2. **CanvasModulate oscuro + sprites aditivos** de luz (texturas radiales
     generadas, `CanvasItemMaterial.BLEND_MODE_ADD`).
- Elegir el que dé mejor legibilidad/FPS. Salida del spike: decisión + preset de
  "zona de luz" (una zona C2 `visual_kind = light`, sin daño, radio fijo).

### E2. Mecánica

- Farolas = interactables D1 con zona de luz: los enemigos fuera de zonas de luz
  se dibujan como silueta + ojos (el `character_visual_controller` ya separa capas);
  dentro, normales.
- Minimapa imperfecto: fuera de luz, los marcadores de enemigos se muestran con
  retardo de 1.5 s y posición cuantizada (el `minimap_entity_registry` filtra).
- Apagones: evento central `blackout` (C1) — 8 s todas las farolas off.
- Elites `sabueso`/`nocturno` (A1) completan su versión final: nocturno +25 % de
  velocidad solo fuera de la luz.
- Generadores (fase avanzada, 200 s+): 2 interactables que al "repararse"
  (permanecer cerca 3 s, mecánica de rescate ya existente) reencienden farolas.

**Criterios de aceptación (E):**

- FPS del soak en Tinieblas ≥ 90 % del soak del Barrio (la oscuridad no puede
  costar más que eso).
- Con todas las farolas apagadas el juego sigue siendo legible (jugador, ojos de
  enemigos y proyectiles siempre visibles — revisión manual con screenshot test).
- El minimapa en zonas oscuras nunca muestra posición exacta en tiempo real.

---

## Bloque F — Jefes ambientales: el examen final

**Objetivo:** que cada jefe use la mecánica de su mapa. Va al final porque depende
de A–E. Un jefe por tarea, empezando por los 3 mapas base.

- `BossData` nuevos campos: `environment_rules: Array[StringName]` y
  `boss_modifier_pool: Array[StringName]` en `MapData` (el guion A2 elige uno:
  p. ej. `pack_escort` / `street_breaker` para el Alfa del Barrio).
- **Rottweiler Alfa (Barrio)**: planta una marca de territorio al entrar y otra al
  60 % de vida (D2); su llamada de refuerzos entra por las calles del territorio.
  Élite: convierte 2 calles en corredores de cacería (zonas territorio alargadas).
- **Mastín del Pantano (Parque)**: ya deja hazard en élite (`elite_leaves_hazard`);
  añade: se cura 5 %/s parado dentro de una zona de infección **consumiéndola**
  (la zona decae al curarle — el jugador puede negarle la curación limpiando dónde
  mata). Salta entre zonas si hay ≥ 2.
- **Alfa de la Chatarra (Industrial)**: 3 placas de armadura (mutación `chatarra`
  a escala jefe); los `boss_guardian` que invoca le RECONSTRUYEN una placa si le
  llegan (matarlos antes = ventana de daño). Élite: activa `steam_burst` (C1).
- **Jefes de historia** (rott. oscuro, corazón, Alfa Primigenio): una regla cada
  uno sobre los sistemas D3/D4/E2 (apagar farolas / regenerar un nido / activar una
  línea de producción por fase de vida). El Primigenio alterna módulos por umbral
  de `phase_thresholds`, no todo a la vez.

**Criterios de aceptación (F):**

- `test_boss_scaling.gd` extendido: cada jefe con sus reglas muere dentro de la
  ventana de balance actual (la matriz de soaks de balance no se degrada más de
  ±10 % en tiempo-de-kill).
- Negarle la curación al Mastín es posible y medible (test: sin zonas, no se cura).
- El Alfa de Chatarra sin guardianes vivos nunca recupera placas.

---

## 7. Validación (cada bloque)

- **Compilar/importar**: `Godot_v4.7 --headless --path . --import` sin errores.
- **Soak**: `--quit-after 2600` por cada mapa tocado, grep de `ERROR|SCRIPT ERROR`;
  comparar FPS/conteos con `Performance.get_debug_line()` contra el baseline de la
  rama. Cambios de física en callbacks → `call_deferred` (regla del proyecto).
- **Tests**: nuevos `tests/test_run_script.gd` (determinismo A2),
  `tests/test_zones.gd` (facciones/fusión/presupuesto C2),
  `tests/test_interactables.gd` (targeting/objetivos D1) y extensión de
  `test_boss_scaling.gd` (F). Recordar los gotchas de `--script`: sin autoloads,
  esperas por segundos reales, quit a prueba de errores.
- **Balance**: correr la matriz de soaks de balance existente al cerrar B, D y F.

## 8. Fuera de alcance (explícito)

- Nuevos assets de arte (todo con `_draw`, paletas y sprites existentes).
- Cambiar tiempos de `RunPhaseConfig` o el flujo victoria/derrota.
- Niveles 2/3 para los 12 enemigos (solo los 3 del bloque B en esta fase).
- Clima/día-noche global, mapas nuevos, y cualquier cosa de Steam/multijugador online.
- Bloqueo de proyectiles por obstáculos (sigue documentado como mejora futura).

## 10. Registro de implementación (primera iteración)

### Sistemas nuevos

- `scripts/systems/run_script.gd` — **RunScript**: guion procedural por semilla
  (evento central, mutación dominante, modificador de jefe, variante de
  apertura). Determinista con hashes salteados; lo construye MapManager en
  `_apply_active_map()` y lo consultan PhaseDirector, EnemySpawner y BossSpawner.
- `scripts/maps/map_interactable.gd` — interactable destruible compartido con
  roles: `howl_post` (marca de aullido del Barrio), `nest_*` (nidos del Corazón:
  generador/curador/contaminador) y `production_*` (líneas de la Fábrica:
  corredores/blindaje/reparar jefe). Vive en el grupo `enemies` (las armas lo
  dañan sin tocar el targeting) + `map_interactables` (excluido de limpieza de
  emergencia y zonas anti-enemigo).
- `hazard_zone.gd` generalizado — facción (`players`/`enemies`/`both`), tipo
  (`infection`/`industrial`), telegrafo `arm_delay`, `consume()` para el Mastín,
  y `try_spawn()` con presupuesto por tipo + fusión de zonas superpuestas
  (incluye las pendientes del mismo frame).
- `WaveEventManager.trigger_map_event()` — 7 eventos centrales: `street_block`,
  `stray_horde`, `lake_fog`, `carrier_bloom`, `freight_train`, `steam_burst`,
  `blackout` (este último vía `AmbientController.pulse_darkness`).

### Sistemas extendidos

- `MapData` — grupo "Identidad de combate": `biome_mutations`,
  `dynamic_event_pool`, `opening_*_id`/`_alt_id`, `boss_modifier_pool`,
  `interactable_kind` + `interactable_times`.
- `PhaseDirector` — apertura característica por mapa (variante por semilla),
  evento central a los 115 s, spawns de interactables programados y
  `behavior_level` (1/2/3) inyectado en el perfil de fase.
- `enemy.gd` — `behavior_level` (Manada: semicírculo N2 + carga coordinada N3;
  Escupidor: tiro liderado N2 + barrera N3; Embestidor: alcance/carga N2 +
  rompe obstáculos destructibles N3 vía `absorb_projectile`), y 9 mutaciones
  élite por bioma: `lider_manada`, `carronero`, `esporoso`, `parasito`,
  `volatil`, `chatarra`, `sabueso`, `nocturno`, `sobrecargado`.
- `enemy_spawner.gd` — `set_mutation_pool()` (genéricas + bioma, dominante x2
  papeletas), `behavior_level` a cada spawn, limpieza de emergencia excluye
  interactables.
- `boss.gd` — `apply_run_modifier()` (`veloz_alfa`/`invocador`/`marcador`/
  `pantanoso`/`acorazado`) y reglas ambientales de BossData:
  `territory_marks` (Rottweiler/Primigenio), `consume_zones` (Mastín, curación
  negable), `scrap_plates` (Chatarra/Primigenio, placas que caen por fase).

### Identidad final por mapa (datos)

| Mapa | Mutaciones | Eventos | Interactable | Jefe |
|---|---|---|---|---|
| Barrio Gatuno | lider_manada, carronero | street_block, stray_horde | howl_post (60/110 s) | territory_marks |
| Parque Abandonado | esporoso, parasito | lake_fog, carrier_bloom | — | consume_zones |
| Callejón Industrial | volatil, chatarra | freight_train, steam_burst | — | scrap_plates |
| Barrio en Tinieblas | sabueso, nocturno, lider_manada | blackout, stray_horde | howl_post (55/105 s) | (rottweiler) |
| Corazón del Parque | esporoso, parasito, sabueso | lake_fog, carrier_bloom, blackout | nest (45/90/135 s) | (mastín) |
| La Fábrica | sobrecargado, chatarra, volatil | steam_burst, freight_train, blackout | production_line (40/80/120 s) | territory_marks + scrap_plates |

### Balance

Los eventos e invocaciones extra inyectan XP; la primera versión hizo que el
soak "flow" (jugador estático) MATARA al jefe (victoria imposible antes). Se
moderó: manada callejera 6 (no 8) e intensidad 2.0, `invocador` +1 (no +2), XP
de interactables 8/14/20. Regla: los eventos añaden PRESIÓN, no una fuente de
XP que abarate el examen final.

### Pendiente (fuera de esta iteración)

- Bloque E completo: luz por farolas/generadores con spike de rendimiento en
  `gl_compatibility`; minimapa con información imperfecta en zonas oscuras.
- Niveles 2/3 del resto del roster (aullador coordinador, flanqueador que
  cierra rutas por nivel).
- Línea de guion en el menú de pausa (`RunScript.describe()` ya existe).
- Objetivo formal "destruir N interactables" en el HUD (hoy son opcionales:
  presión/recompensa, no objetivo).
- Nidos conectados (bonus por red) y puertas/prensas industriales.

## 9. Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Zonas persistentes degradan FPS | Fusión + presupuesto por tipo (C2); soak obligatorio con 50+ zonas provocadas |
| Interactables rompen el targeting de armas/compañeros | Grupo secundario de targeting con prioridad menor; test dedicado antes de D2–D4 |
| Oscuridad ilegible o cara en gl_compatibility | Spike E1 con timebox y criterio numérico (≥ 90 % FPS) antes de comprometer diseño |
| El guion por semilla hace partidas injustas (evento duro + mutación dura) | Tabla de exclusiones en `RunScript` (pares vetados), igual que la tabla blanca de `prototipo` |
| Elites nuevos rompen coop | Los efectos de aura/muerte iteran grupos ya coop-safe (`players`); soak coop de `test_coop_soak.gd` al cerrar A |
