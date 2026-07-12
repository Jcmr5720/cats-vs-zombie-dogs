# Rework de Jugabilidad de Compañeros

## Problema original

Los compañeros morían en segundos (daño de contacto frecuente, 2–4 % de
reducción, vida fija de 50–60 mientras los enemigos escalan), aportaban poco
daño, no escalaban con la partida, no tenían habilidades diferenciadas y no
existía razón fuerte para rescatarlos o protegerlos. Si nadie los revivía,
quedaban caídos para siempre. No tenían correa de seguridad: podían quedar
atrapados tras un obstáculo o lejísimos del jugador.

## Arquitectura encontrada

- `scripts/companions/companion.gd` — CharacterBody2D; seguía la formación del
  manager, disparaba desde su posición (no persigue), ya tenía downed + revive
  por canalización del jugador (ReviveArea).
- `scripts/companions/companion_manager.gd` — registro, formación en abanico
  detrás del líder activo, bonos de upgrades/Refugio, snapshots al HUD.
- `scripts/enemies/enemy.gd` — prefería atacar compañeros a <180 px; escaneaba
  el grupo `companions` DOS veces por frame y por enemigo (persecución +
  contacto).
- `scripts/systems/coop_camera.gd` — encuadre y zoom solo con el grupo
  `players`: los compañeros nunca afectaron la cámara (se conserva así).
- Upgrades de compañeros en `upgrade_manager.gd` (multiplicadores que llegan
  vía `set_bonuses`), Refugio y mejoras permanentes vía `companion_manager`.

## Archivos creados

- `scripts/companions/companion_balance.gd` — TODO el balance centralizado +
  fórmulas de escalado (`health_bonus`, `damage_scale`).
- `scripts/companions/police_barricade.gd` — zona de control del Policía.
- `scripts/companions/companion_turret.gd` — torreta temporal del Ingeniero.
- `tests/test_companions.gd` + `tests/TestCompanions.tscn` — suite del rework
  (corre como escena para tener autoloads reales).
- Este documento.

## Archivos modificados

- `scripts/companions/companion.gd` — supervivencia, correa, habilidades,
  escalado, reagrupamiento, snapshot ampliado.
- `scripts/companions/companion_manager.gd` — líder estable (`get_leader`),
  escalado central cada 2 s, `command_regroup`, `has_active_role`, aviso de
  compañero lejano.
- `scripts/enemies/enemy.gd` — `apply_slow`, amplificación de daño al enemigo
  marcado, caché del escaneo de compañeros (0.25 s en vez de cada frame).
- `scripts/player/player.gd` — `apply_companion_shield` (escudo temporal del
  Médico, integrado multiplicativamente en `take_damage`, tope 0.8).
- `scripts/loot/xp_orb.gd` — `nudge_toward` (pasiva del Ingeniero; no roba XP,
  solo acerca el orbe para que el imán normal lo capture).
- `scripts/ui/hud.gd` — mini-barra de habilidad bajo cada dot de compañero
  (lista/verde, recargando/amarilla, bloqueada/roja) + tooltip con el estado.
- `project.godot` — acción `companion_regroup` (tecla Q, botón Y del mando).

## Supervivencia

- Reciben el **50 %** del daño (`INCOMING_DAMAGE_FACTOR`), además de su
  reducción propia y los upgrades.
- Invulnerabilidad tras daño: **0.8 s** (`HURT_INVULN_TIME`) — el contacto
  masivo y zonas persistentes no pueden aplicar daño cada frame.
- Al llegar a 0: estado `downed` (no desaparece, no ataca, no recibe daño
  normal, señal visual "CAIDO" existente).
- Revive: 1.5 s base; cualquier jugador (P1 o P2) puede canalizarlo; el Médico
  suma un ritmo externo de 0.6× (acelera el rescate o lo hace solo).
- Al revivir: **1.5 s de protección** total (no puede ser destruido al
  levantarse rodeado).
- Si nadie lo revive en **22 s**: auto-respawn junto al líder en posición
  segura, con 35 % de vida y su habilidad bloqueada 10 s. No hay muerte
  definitiva en modo normal.

## IA segura y correa

- Los compañeros no persiguen: disparan desde la formación (sin cambios).
- Distancia blanda **600 px** del líder: deja de atacar, entra en modo regreso
  con +28 % de velocidad. Aviso en HUD ("X esta lejos", antirrebote de 6 s).
- Distancia de emergencia **850 px**, o atrapado >2.5 s mientras regresa:
  reposición segura junto al líder (`_find_safe_spot`: 8 candidatos a 84 px,
  descarta colisión con obstáculos vía `test_move` y enemigos a <70 px;
  fallback: posición del líder). Transición discreta (destello barato).
- En coop el punto de referencia es el líder del manager (prefiere P1 mientras
  esté activo): sin saltos constantes entre jugadores.
- **Cámara**: la CoopCamera solo mira el grupo `players`; los compañeros no
  participan del encuadre ni del zoom (verificado, sin cambios).

## Roles

### Gato Policía — control y protección
- **Pasiva "Objetivo prioritario"**: cada 2.5 s marca al elite más relevante
  (o al enemigo más cercano al líder si no hay especiales) a ≤520 px. El
  marcado recibe **+20 % de daño de todo el equipo** (jugadores, compañeros y
  torretas; aplicado en `enemy.take_damage`). Anillo dorado visible (hijo del
  enemigo: muere con él). Una sola marca a la vez.
- **Habilidad "Barricada policial"** (auto: ≥5 enemigos a <260 px del líder;
  cooldown 20 s, duración 4 s): zona circular entre el líder y el centro de
  masa enemiga; ralentiza al 45 % y da un empujón de entrada (interrumpe
  cargas). Sin colisión física: no bloquea al jugador ni proyectiles aliados.
- **Protector**: si un jugador baja del 40 %, empujón de emergencia radial +
  ralentización a los enemigos pegados a él (cooldown interno 8 s). Además su
  targeting normal ya prioriza enemigos cercanos al líder.

### Gato Médico — supervivencia
- Pasivas existentes conservadas (regen de aura + cura reactiva).
- **Asistencia de revive**: canaliza el revive de compañeros caídos a ≤170 px
  al 60 % del ritmo (se suma al del jugador).
- **Habilidad "Emergencia de nueve vidas"** (auto: un jugador bajo el 35 %;
  cooldown 24 s): cura ×3 + **escudo del 50 %** durante 3 s
  (`apply_companion_shield`, tope 0.8: nunca inmortal).

### Gato Ingeniero — control territorial
- **Pasiva "Mantenimiento de campo"**: cada 0.6 s empuja orbes de XP a ≤150 px
  hacia el líder (no los recoge: la recolección sigue siendo del jugador; la
  XP compartida no cambia).
- **Habilidad "Zona fortificada"** (auto: ≥4 enemigos a <420 px; cooldown 24 s,
  duración 10 s): torreta en la posición actual del ingeniero (siempre
  navegable, nunca dentro de una pared). Selección de objetivo cada 0.3 s con
  prioridad marcado > elite > cercano; dispara cada 0.55 s con el 80 % del daño
  efectivo del ingeniero. Máximo una torreta por ingeniero. Parpadea sus
  últimos 2 s y se libera sola.

## Escalado (fórmulas reales)

Aplicado por `CompanionManager` cada 2 s (`_update_scaling`), leyendo al líder:

```
vida_bonus  = minutos_de_partida * 4 + max(0, vida_max_jugador - 100) * 0.35
daño_escala = clamp(1 + 0.05 * (nivel_jugador - 1), 1.0, 2.0)
daño_final  = base * mult_upgrades_refugio * daño_escala
```

- Factores separados: los upgrades (`_damage_multiplier`) y el escalado
  (`_scaling_damage_multiplier`) nunca se multiplican entre sí dos veces, y el
  escalado tiene tope 2.0 (sin infinito).
- Al subir el bonus de vida se cura la diferencia (no queda "más herido" en %).
- El recién rescatado recibe el escalado al instante.
- Cooldown de habilidades: se beneficia del multiplicador de cooldown de los
  upgrades de compañeros (mínimo 4 s).

## Sinergias

1. **Policía + Médico**: con un médico activo, la barricada cura 2 HP por tick
   a los jugadores dentro (pequeña zona segura).
2. **Médico + Ingeniero**: con un médico activo, la torreta emite un pulso de
   curación (2 HP, radio 130 px) cada 2.5 s.
3. **Policía + Ingeniero**: la torreta prioriza al enemigo marcado (meta
   `companion_mark`), sin referencia directa entre scripts.

La detección es por consulta (`manager.has_active_role`) al momento de crear la
zona/torreta: si el participante está derribado no se activa, y no hay
dependencias rígidas ni ciclos de señales.

## Orden "Reagruparse"

- Acción `companion_regroup`: **tecla Q** (P1) y **botón Y** del mando (P2).
  Cualquiera de los dos puede activarla; el manager la escucha en
  `_unhandled_input` y llama `command_regroup()`.
- Efecto 3 s: abandonan el objetivo, no atacan, +35 % de velocidad hacia la
  formación. No consume la habilidad especial. Mensaje en HUD.

## HUD

- Dot existente por compañero + barra de vida (sin cambios) + nueva mini-barra
  de habilidad: verde llena = lista, amarilla vaciándose = recargando, roja =
  bloqueada por penalización. Tooltip con nombre y estado de la habilidad.
- Mensajes de evento reutilizados: caído, vuelve, lejos, reagrupando.
- Snapshot con antirrebote (1 s) mientras recarga: el HUD no se reconstruye
  cada frame.
- Telegráficas provisionales (formas planas, sin arte definitivo): anillo azul
  de la barricada, torreta amarilla de obra, anillo dorado de la marca,
  destellos de cura/escudo.

## Rendimiento

- Enemigos: el escaneo del grupo `companions` pasó de 2×/frame/enemigo a un
  caché de 0.25 s (mejora neta con hordas).
- Barricada: tick de 0.4 s (no cada frame); torreta: retarget 0.3 s; marca:
  2.5 s; triggers de habilidades: 0.5 s; orbes: 0.6 s; escalado: 2 s.
- Zonas/torretas se añaden a `current_scene` (se liberan al cambiar de escena)
  y se auto-liberan al expirar. El anillo de marca es hijo del enemigo.
- Sin nodos por enemigo, sin partículas nuevas, sin recursos duplicados por
  instancia.

## Balance inicial (ajustable en `companion_balance.gd`)

| Valor | Inicial |
|---|---|
| Daño recibido | 50 % |
| Invulnerabilidad tras daño | 0.8 s |
| Revive | 1.5 s (medico asiste al 60 %) |
| Protección al revivir | 1.5 s |
| Auto-respawn | 22 s, 35 % vida, habilidad −10 s |
| Correa blanda / emergencia | 600 / 850 px |
| Marca del Policía | +20 % daño, re-evalúa 2.5 s |
| Barricada | slow 45 %, 4 s, CD 20 s |
| Emergencia del Médico | cura ×3, escudo 50 %/3 s, CD 24 s |
| Torreta | 80 % del daño, 10 s, CD 24 s |
| Escalado daño | +5 %/nivel, tope ×2 |
| Escalado vida | +4/min + 35 % de la vida extra del jugador |

## Pruebas ejecutadas

- `godot --headless --path . --import` (compilación).
- `godot --headless --path . res://tests/TestCompanions.tscn` — suite del
  rework (daño/invuln, downed/revive/protección, auto-respawn, correa y
  teletransporte, marca, barricada, médico, torreta, escalado, regroup,
  limpieza).
- `godot --headless --path . --script tests/test_gameplay_smoke.gd` — smoke de
  regresión de MainLevel.
- Ver el resumen de la entrega para los resultados reales; no se realizaron
  pruebas manuales con humanos.

## Riesgos y pendientes

- Balance no validado con juego humano (valores de la tabla = punto de
  partida).
- La marca del Policía usa `enemy.get("_elite_kind")` (campo privado del
  enemigo) para detectar elites; si se renombra, la priorización degrada a
  "más cercano" sin romper.
- La detección de "zona peligrosa" se limita a lo detectable hoy (obstáculos y
  enemigos); no hay zonas de daño ambiental tipadas en el proyecto todavía.
- La orden de reagrupar usa Q/botón Y: revisar que no colisione con futuros
  controles.
- Métricas de utilidad (daño evitado, enemigos interrumpidos) no se registran
  aún en el resumen de partida: candidato para la siguiente etapa.
