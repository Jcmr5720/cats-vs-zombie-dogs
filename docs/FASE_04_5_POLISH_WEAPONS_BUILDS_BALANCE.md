# FASE 04.5 — Pulido de armas, builds, sinergias y balance

Fase de **pulido** sobre la Fase 04. No agrega jefes, menú, Steam, guardado,
logros ni audio. El objetivo es que el combate con varias armas y compañeros se
sienta divertido, claro y balanceado **antes** de pasar a Fase 05.

> Motor: Godot 4.7 · Lenguaje: GDScript · Escena principal: `scenes/levels/MainLevel.tscn`

---

## 1. Problemas detectados después de Fase 04

- La **dificultad no consideraba el poder real de armas**: solo subía por tiempo,
  nivel, kills, upgrades y compañeros. Con 4 armas muy subidas el jugador se
  volvía demasiado fuerte sin que la presión respondiera.
- Las **sinergias eran invisibles**: existían en código (policía→pistola,
  ingeniero→área, médico→orbital, 3 compañeros→cooldown) pero el jugador no tenía
  forma de saber si estaban activas o qué las activaba.
- Las **cartas no aclaraban a quién afectaban** (arma / jugador / compañeros).
- Faltaba **feedback al conseguir o subir un arma** (no había aviso en pantalla).
- La **zona de catnip era casi opaca**, tapaba enemigos y restaba claridad.
- No había **topes documentados** para orbitales ni radio de área (riesgo de
  acumulación de nodos / limpiar pantalla).

---

## 2. Cambios de balance

- **Dificultad sensible a la build** (ver §4). Más armas y más niveles de arma
  ahora suben el `difficulty_score`.
- **Sinergia Médico + Rascador** reconvertida a un efecto **defensivo sutil**:
  −8% daño recibido por el jugador (antes el médico solo daba +10% daño al
  orbital). Es deliberadamente bajo: ayuda, no vuelve invencible.
- **Topes nuevos** de orbitales, cooldown mínimo y radio de área (ver §6).

Las armas conservan sus valores base de Fase 04 (no se rehízo el tuning); el
pulido se centró en claridad, límites y respuesta de dificultad.

---

## 3. Cambios visuales / claridad

- **Zona de daño (catnip)** ahora es **semitransparente** (`AREA_ALPHA = 0.42` en
  `weapon_area.gd`): se ve dónde daña sin tapar enemigos ni jugador.
- **HUD de sinergias** nuevo dentro del `WeaponsPanel`: lista cada sinergia
  posible, en verde si está **activa** y en gris con el **requisito** si no.
- **Cartas** muestran una línea `[Afecta: Arma / Jugador / Compañeros]`.
- **Mensajes de evento** al conseguir o subir un arma (`"Nueva arma: …"`,
  `"… subió a Nv. N"`).

---

## 4. Fórmula de dificultad actualizada

En `scripts/enemies/enemy_spawner.gd` (`_recalculate_difficulty`):

```text
difficulty_score =
      minutos_sobrevividos      * time_weight          (1.2)
    + nivel_jugador             * level_weight          (0.9)
    + enemigos_eliminados       / kills_divisor         (35.0)
    + upgrades_elegidos         * upgrade_weight         (0.35)
    + companions_rescatados     * companion_weight       (0.7)
    + companions_derribados     * downed_companion_weight (-0.25)
    + armas_activas             * weapon_weight           (0.7)   ← NUEVO
    + niveles_totales_de_armas  * weapon_level_weight     (0.18)  ← NUEVO
```

Todos los pesos son `@export`, ajustables desde el inspector del nodo
`EnemySpawner`. El score afecta (con tope) a: intervalo de spawn, máximo de
enemigos vivos, vida/velocidad/daño enemigo, probabilidad de aparición en el
borde de cámara y probabilidad de mini-oleadas.

> Nota: la Pistola Gatuna inicial aporta un pequeño offset constante (~0.88) desde
> el segundo 0. Es intencional y menor (sigue en intensidad "Tranquilo"). Si se
> quiere neutralizar, bajar `weapon_weight` o restar el arma inicial.

---

## 5. Límites de armas (topes documentados)

Definidos como constantes en `scripts/weapons/weapon_base.gd`:

| Límite                        | Valor      | Dónde |
|-------------------------------|------------|-------|
| Máximo de armas activas       | 4          | `WeaponManager.max_weapons` |
| Nivel máximo por arma         | 5          | `WeaponData.max_level` (por arma) |
| Cooldown mínimo por arma      | 0.12 s     | `MIN_WEAPON_COOLDOWN` |
| Máximo de orbitales           | 4          | `MAX_ORBITALS` |
| Radio máximo de área/explosión| 230 px     | `MAX_AREA_RADIUS` |

Topes de los modificadores globales (en `weapon_manager.gd`):

| Modificador global        | Rango (clamp)   |
|---------------------------|-----------------|
| Daño global               | 0.5 .. 4.0      |
| Cooldown global           | 0.45 .. 2.0     |
| Rango global              | 0.5 .. 1.8      |
| Proyectiles extra global  | 0 .. 3          |

---

## 6. Límites de upgrades

- Las cartas de **arma nueva** solo aparecen si quedan armas por debajo del máximo
  (4). Las de **mejora de arma** desaparecen al llegar el arma a Nv. 5.
- Las cartas de **compañero** solo entran al pool si ya rescataste alguno.
- Topes del jugador (en `player.gd`): velocidad ≤ 420, vida máx ≤ 220, radio de
  pickup ≤ 2.4×.
- Reducción de daño por sinergia tope: 0.5 (`set_synergy_damage_reduction`), hoy
  solo se usa al 0.08.

---

## 7. Cómo funcionan las sinergias

Calculadas cada frame en `WeaponManager._recompute_synergies()`. Solo aplican con
el compañero del rol **activo** (no derribado):

1. **Policía + Pistola** → +10% daño de la Pistola Gatuna.
2. **Ingeniero + Área** → +10% área y daño de explosivos/zonas (ovillo, catnip).
3. **Médico + Rascador** → −8% daño recibido por el jugador (defensivo, sutil).
4. **Colonia unida (3+ compañeros activos)** → −5% cooldown de todas las armas.

`get_synergy_states()` expone la lista al HUD: cada entrada lleva `name`,
`active`, `requirement` y `effect`. La señal `synergies_changed` solo se emite
cuando cambia el conjunto activo (no cada frame), y el HUD las pinta verde
(activa) o gris (requisito pendiente / compañero caído).

---

## 8. Cómo probar cada arma

| Arma              | Qué confirmar |
|-------------------|---------------|
| Pistola Gatuna    | Dispara al más cercano; fiable 1 a 1, no limpia grupos. |
| Ovillo Explosivo  | Explosión circular visible; útil contra grupos, no toda la pantalla. |
| Sardina Boomerang | Atraviesa varios enemigos en línea (pierce); sube pierce a Nv. 3 y 5. |
| Puntero Láser     | Rayo instantáneo con flash; cooldown alto (2.2 s); fuerte pero arriesgado. |
| Rascador Giratorio| Orbital de contacto con cooldown por enemigo; defensa cercana, no quieto eterno. |
| Granada de Catnip | Zona temporal semitransparente que daña por tics; área limitada. |

---

## 9. Cómo probar builds fuertes

- Sube de nivel rápido recogiendo XP, elige siempre **mejoras de arma** para
  llevar una a Nv. 5 y confirmar que deja de ofrecerse.
- Llega a **4 armas** y verifica que no aparecen más cartas de "arma nueva".
- Rescata 3 compañeros para ver la sinergia **Colonia unida** y el efecto en HUD.
- Con 4 armas + 3 compañeros, comprueba que la **intensidad** sube notablemente
  (la dificultad responde) y que sigues siendo fuerte pero no invencible.

---

## 10. Riesgos conocidos

- El offset de dificultad por el arma inicial hace el minuto 0 ligeramente más
  duro que en Fase 04 (efecto menor, comentado en §4).
- El balance fino de cada arma se validó por lectura/estructura, **no** por una
  sesión jugada larga (no hay forma de simular input headless aquí). Conviene un
  playtest manual real antes de Fase 05.
- Boomerang sigue siendo un proyectil recto con pierce (no regresa). Cumple su rol
  de "atraviesa líneas" pero no es un boomerang literal.

---

## 11. ¿Listo para Fase 05?

**Casi.** El sistema de armas/builds/sinergias/dificultad ya es claro, limitado y
expandible, y el proyecto corre sin errores (validación headless). Recomendación:
hacer un **playtest manual** (partidas A–H del plan) para confirmar el feel del
balance; si se siente bien, se puede avanzar a jefes.

---

## Archivos tocados en esta fase

- `scripts/weapons/weapon_manager.gd` — stats de arma para dificultad, sinergias
  expuestas + señal, mensajes de evento, sinergia defensiva del médico.
- `scripts/weapons/weapon_base.gd` — topes (orbitales, cooldown, área).
- `scripts/weapons/weapon_area.gd` — zona semitransparente.
- `scripts/player/player.gd` — reducción de daño por sinergia.
- `scripts/enemies/enemy_spawner.gd` — fórmula de dificultad con armas/niveles.
- `scripts/systems/upgrade_manager.gd` — campo `affects` en las cartas.
- `scripts/ui/hud.gd` — HUD de sinergias y línea "Afecta" en cartas.
- `scenes/ui/HUD.tscn` — nodos de sinergias en `WeaponsPanel`.
- `docs/FASE_04_5_POLISH_WEAPONS_BUILDS_BALANCE.md` — este documento.
