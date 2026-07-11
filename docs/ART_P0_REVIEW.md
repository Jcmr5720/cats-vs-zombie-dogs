# ART P0 REVIEW — revisión visual del primer lote

Plantilla de revisión. Se rellena en cada subgate con arte real; queda
PENDIENTE hasta recibir paquetes en `_incoming` (a fecha de la Etapa 3 no se
ha recibido ninguno).

## leader_cat

- Hoja maestra (B0): **PENDIENTE DE RECEPCIÓN**
- Poses piloto (B1): PENDIENTE
- Mini animación (B2): PENDIENTE
- Comparación procedural vs sprite (Preview, checkbox "Procedural"): PENDIENTE
- Fortalezas: —
- Defectos: —
- Errores de consistencia (frames que mutan, accesorios, extremidades): —
- Animaciones pendientes: todas
- Rendimiento (ver ART_P0_PERFORMANCE_REPORT): línea base registrada
- Veredicto: **SIN ARTE QUE REVISAR** — procedural sigue activo
- Archivos a regenerar: n/a

## zombie_dog_normal

- Hoja maestra (B0): **PENDIENTE DE RECEPCIÓN**
- Poses piloto (B1): PENDIENTE
- Mini animación (B2): PENDIENTE
- Comparación procedural vs sprite: PENDIENTE
- Fortalezas / Defectos / Consistencia: —
- Veredicto: **SIN ARTE QUE REVISAR** — procedural sigue activo

## Protocolo de revisión (cuando llegue arte)

1. `incoming_check.gd` (automático) → corregir fallos objetivos.
2. Checklist manual (ART_ASSET_ACCEPTANCE_CHECKLIST.md).
3. Preview: 3 fondos de bioma con tinte ambiental, zoom x1.0 y x1.35,
   flash de daño, sombra, pivote, comparación procedural.
4. MainLevel con FORCE_SPRITE (perfil PILOT_ART) en los 3 mapas.
5. Solo + coop manual (P1/P2, derribo, revive, reinicio).
6. Registrar aquí veredicto y elevar asset_status según gates.
