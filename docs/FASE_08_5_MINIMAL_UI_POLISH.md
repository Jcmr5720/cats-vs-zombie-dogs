# FASE 08.5 — Pulido general minimalista de UI, UX, HUD y flujo

> **Objetivo:** reducir texto, limpiar la interfaz, mejorar la jerarquía visual y
> hacer que el juego se sienta minimalista, claro y profesional **sin** añadir
> mecánicas, audio, arte final ni Steam, y **sin** romper guardado, gameplay,
> menús, armas, compañeros, mapas ni jefes.
>
> Regla guía: **HUD = información mínima · Pausa = información detallada.**

---

## 1. Problemas detectados

- El **HUD de combate** mostraba ~7 datos en texto (Vida, Nivel, XP, Tiempo,
  Eliminados, Intensidad, Gatos) + un panel de 4 armas con nombre largo, nivel y
  pips + lista de Sinergias + un panel completo de compañeros con nombres, estados
  y barras + panel de objetivo con mapa. Demasiada información permanente.
- Las **cartas de upgrade** añadían líneas extra de tipo y `[Afecta: ...]`.
- El **resumen de partida** (victoria/derrota) mostraba ~15 líneas incluido el
  desglose completo de Sardinas siempre visible.
- El **selector de mapas** mostraba descripción larga, presión enemiga con tres
  multiplicadores, recompensa, objetivo y mejor tiempo en cada tarjeta + un panel
  lateral de estado con un párrafo de "regla".
- El **menú principal** tenía panel de intro con párrafo, badges de "facts" y un
  panel de perfil con grid de stats y texto de mejora destacada.
- Las **mejoras permanentes** mostraban efecto actual y siguiente siempre, con
  subtítulo y textos largos de costo/estado.
- **Mensajes temporales** largos ("Gato sobreviviente detectado", "se unió al
  equipo", "Mapa bloqueado: asegura la zona anterior") y de hasta 3.4 s.

## 2. Qué quedó visible durante el gameplay (HUD mínimo)

`scenes/ui/HUD.tscn` + `scripts/ui/hud.gd` reescritos:

- **Arriba izquierda:** `Nv. N`, barra de **Vida** (con `actual/max` pequeño) y
  barra de **XP**.
- **Arriba centro:** **Tiempo** `MM:SS`.
- **Arriba derecha:** **objetivo corto** (máx. ~4 palabras) y `Gatos x/y`.
- **Abajo izquierda:** mini-iconos de **armas** generados dinámicamente
  (icono de tipo + nivel). El nombre completo y nivel van en el **tooltip**.
- **Abajo derecha:** mini-iconos de **compañeros** (punto de color + barra de vida
  fina; se oscurece si está caído). Nombre y estado en el **tooltip**.
- Se conservan intactos: barra de jefe, intro de mapa, flash de daño, flecha de
  rescate, mensajes temporales, cartas de mejora y paneles de fin de partida.

## 3. Qué información se movió a la pausa (ESC = centro de información)

`scripts/menus/pause_menu.gd` ahora, al abrir, lee `HUD.get_run_info()` y muestra
un panel con el detalle que el HUD ya no enseña:

- Mapa actual + objetivo.
- Tiempo, Nivel, **Eliminados**.
- **Gatos rescatados** x/y + **Intensidad** (tier por dificultad).
- **Armas** con nivel.
- **Sinergias activas**.
- **Compañeros** del roster.

Debajo siguen los botones **Continuar**, **Opciones** (ajustes rápidos) y
**Volver al menú** (con doble confirmación). El HUD expone `get_run_info()` como
única vía de lectura; no se duplican sistemas.

## 4. Cartas de upgrade más limpias

`hud.gd::show_upgrade_selection()`:

- Solo **rareza** (color), **nombre corto** y **descripción de 1 línea**.
- Se eliminaron de la cara de la carta la línea `[Afecta: ...]` y el `type_label`;
  ahora viven en el **tooltip** de la carta.
- Tarjetas un poco más bajas (168 px) para respirar.

## 5. Resumen de partida más elegante (+ Detalles)

`hud.gd::show_victory()/show_defeat()`:

- Título (**ZONA ASEGURADA** / **COLONIA PERDIDA**), subtítulo (mapa) y un
  **resumen clave**: Sardinas, Tiempo, Enemigos, Gatos, Nivel, Jefes.
- El **desglose de Sardinas** y el arsenal usado quedan ocultos tras el botón
  **Detalles** (toggle). Los paneles usan `PROCESS_MODE_WHEN_PAUSED` para que el
  botón funcione con el árbol pausado.
- Atajos finales: `R Reintentar · M Mejoras · ESC Menu`.

## 6. Selector de mapas minimalista

`scripts/menus/map_select_menu.gd`:

- Cada tarjeta: **nombre**, badge de estado, **dificultad en puntos** (`●●○`),
  **duración**, **objetivo corto** y, según estado, requisito o mejor tiempo.
- Se eliminaron por defecto: descripción larga (ahora en **tooltip** de la tarjeta),
  presión enemiga, recompensa y el panel lateral de estado (resumido a una línea
  "Sardinas N · Zonas x/y" arriba a la derecha).

## 7. Menú principal más elegante

`scripts/menus/main_menu.gd`:

- Solo **título**, **subtítulo corto** ("Rescata la colonia.") y los 5 botones:
  **Jugar · Mejoras · Progreso · Opciones · Salir**.
- Se quitaron los paneles de intro, "facts" y perfil (esos datos viven en
  **Progreso**). El fondo decorativo (luna, gato, huellas, skyline) se mantiene.

## 8. Mejoras permanentes y Progreso

- **Meta** (`scripts/ui/meta_upgrade_panel.gd`): cada tarjeta muestra nombre,
  categoría, nivel, **efecto actual**, costo y botón. El **efecto del siguiente
  nivel** pasó al **tooltip** (hover). Subtítulo y textos acortados, tarjetas más
  compactas.
- **Progreso** (`scripts/menus/stats_menu.gd`): los datos clave (Partidas,
  Victorias, Sardinas, Enemigos, Gatos, Jefes, Mejor nivel, Mini-jefes) ahora son
  **tarjetas grandes** en grid; el detalle por mapa queda como sección secundaria.

## 9. Mensajes temporales cortos

Acortados y con duración 1.6–2.0 s:

| Antes | Ahora |
|-------|-------|
| "Gato sobreviviente detectado!" | "Gato cercano" |
| "%s se unió al equipo" | "%s unido" |
| "%s fue derribado" | "%s caido" |
| "%s volvió al combate" | "%s vuelve" |
| "Nueva arma: %s" | "Arma: %s" |
| "%s subió a Nv. %d" | "%s Nv. %d" |
| "Mapa bloqueado: asegura la zona anterior" | "Zona bloqueada" |
| "Rescate cancelado" (1.6 s) | (sin cambio de texto) |

Se eliminó el mensaje largo de aprendizaje de armas del HUD.

## 10. Consistencia de idioma

Todo en español y unificado: **Jugar, Mejoras, Progreso, Opciones, Salir**,
**Zona Asegurada / Colonia Perdida**, **Sardinas**, **Reintentar**, **Detalles**,
**Continuar**. El botón antes llamado "Estadísticas" pasó a **Progreso**.

## 11. Limpieza técnica

- Funciones muertas eliminadas: `map_select_menu._difficulty_text/_pressure_text/`
  `_reward_mult` y `_build_status_panel`; `main_menu._build_profile_panel/`
  `_get_save_value/_top_upgrade_summary/_spacer`; en HUD se quitaron
  `on_game_over/_level_pips/_pulse_weapon_label/_intensity_tier` y los paneles fijos
  de armas/compañeros/objetivo (ahora dinámicos).
- Iconos geométricos simples (puntos de compañero, chips de arma, puntos de
  dificultad) sin assets externos.
- Se preservaron **todas** las firmas públicas del HUD que usan señales y managers
  (`on_health_changed`, `on_experience_changed`, `on_level_changed`,
  `on_time_updated`, `on_stats_updated`, `on_companions_changed`,
  `update_companion_roster`, `on_weapons_changed`, `on_synergies_changed`,
  `set_rescue_status`, `set_rescue_target`, `show_event_message`, `show_map_intro`,
  `show_run_end`, `show_boss_bar/update_boss_bar/hide_boss_bar`, `set_map_name`,
  `set_objective_text`, `set_game_over_title`, `show_upgrade_selection`,
  `hide_upgrade_selection`, `is_selecting_upgrade`, `toggle_meta_panel`).

## 12. Controles finales

| Acción | Teclas |
|--------|--------|
| Mover | `W A S D` / flechas |
| **Pausa / información** | `ESC` durante la partida |
| Menú / volver | `ESC` en menús y tras la run |
| Reiniciar | `R` (tras victoria/derrota) |
| Mejoras permanentes | `M` (tras victoria/derrota) |
| Detalles de Sardinas | botón **Detalles** en el resumen |
| Cambiar mapa (debug) | `F1 / F2 / F3` |

Disparo automático.

## 13. Archivos

**Creado**
- `docs/FASE_08_5_MINIMAL_UI_POLISH.md`

**Modificados**
- `scenes/ui/HUD.tscn` — árbol minimalista (chips de armas/compañeros dinámicos,
  resumen con Detalles).
- `scripts/ui/hud.gd` — HUD mínimo + `get_run_info()` + toggles de detalle.
- `scripts/menus/pause_menu.gd` — panel de información de la run.
- `scripts/menus/map_select_menu.gd` — tarjetas y estado minimalistas.
- `scripts/menus/main_menu.gd` — menú a título + subtítulo + 5 botones.
- `scripts/menus/stats_menu.gd` — "Progreso" con tarjetas clave.
- `scripts/ui/meta_upgrade_panel.gd` — tarjetas compactas, siguiente nivel en hover.
- `scripts/maps/map_manager.gd` — objetivo corto en HUD (`_objective_short`) y
  mensaje "Zona bloqueada".
- `scripts/weapons/weapon_manager.gd`, `scripts/companions/companion_manager.gd`,
  `scripts/companions/rescue_spawner.gd`, `scripts/bosses/boss_spawner.gd` —
  mensajes temporales cortos.
- `README.md` — estado, controles, HUD y nombres de menú.

## 14. Pruebas manuales

- **A — Menú principal:** abre el juego; debe verse título + subtítulo + 5 botones,
  limpio.
- **B — Selector de mapas:** `Jugar`; cada mapa muestra poco texto (nombre, puntos
  de dificultad, duración, objetivo corto, estado). Hover sobre la tarjeta = más info.
- **C — Mejoras:** `Mejoras`; tarjeta con nombre/nivel/efecto actual/costo/comprar;
  hover sobre la tarjeta = efecto del siguiente nivel.
- **D — HUD:** inicia partida; confirma HUD mínimo (vida/xp/nivel, tiempo,
  objetivo+gatos, iconos de armas/compañeros). Nada tapa el combate.
- **E — Pausa:** pulsa `ESC` en partida; aparece el panel con la info detallada de
  la run. `ESC` de nuevo reanuda.
- **F — Cartas:** sube de nivel; las cartas muestran rareza + nombre + 1 línea.
- **G — Derrota:** muere; resumen mínimo. Pulsa **Detalles** para ver el desglose.
- **H — Victoria:** gana (o `debug_spawn_boss_early`); pantalla de victoria limpia.
- **I — Sardinas:** confirma en el resumen que las Sardinas ganadas son las mismas
  y que al reintentar/volver no se duplican (la recompensa se reclama una sola vez
  en `map_manager`, sin cambios en esta fase).
- **J — Navegación:** recorre Menú → Mapas → Mejoras → Progreso → Opciones → volver;
  todo navega con botón y con `ESC`.

## 15. Validación headless

- `godot --headless --import` → sin errores.
- `godot --headless res://scenes/levels/MainLevel.tscn --quit-after 2200` → sin
  errores rojos (ejercita spawns, subidas de nivel/cartas, armas, roster de
  compañeros y HUD dinámico).

## 16. Riesgos conocidos

- El **panel de pausa** lee el estado del HUD vía `get_run_info()`; si se añade más
  detalle de run habrá que ampliar ese dict (punto único, fácil de extender).
- Los **tooltips** (armas, compañeros, cartas, mapas, mejoras) son la vía de
  "detalle bajo demanda"; dependen de mouse (no hay equivalente con teclado/gamepad).
- El objetivo del HUD es **corto**; el progreso con contadores se ve en la pausa,
  no en el HUD.
- No se tocó la **economía** ni el guardado: el riesgo de duplicar Sardinas es el
  mismo de Fase 07/08 (recompensa reclamada una sola vez).

## 17. ¿Listo para Fase 09?

**Sí.** La interfaz quedó minimalista y coherente, sin romper guardado, gameplay,
armas, compañeros, mapas ni jefes, y la validación headless pasa sin errores. La
Fase 09 puede partir de esta base limpia (p.ej. audio, arte o Steam) sabiendo que
el detalle de la run ya vive ordenado en la pausa y en los tooltips.
