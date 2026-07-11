# leader_cat — paquete P0-A (pendiente de recepción)

Depositar los PNG en subcarpetas por estado:

```
raw/      <- salida original (IA o ilustración), sin tocar
clean/    <- fondo limpiado, sin halos, personaje íntegro
aligned/  <- lienzo 128×128, pies en y=112, centrado consistente
```

Nombres: `leader_cat_<anim>_<dir>_v01_f01.png` (ej. `leader_cat_run_se_v01_f03.png`)
y `leader_cat_master_v01.png` para la hoja maestra.

Orden de producción (subgates): master → poses piloto (idle_s, run_se,
attack_e, hurt, downed) → mini animación (idle_s×4, run_se×6, attack_e×4-6)
→ paquete completo. Ver `docs/AI_ART_P0_PROMPTS.md` y
`docs/ART_ASSET_ACCEPTANCE_CHECKLIST.md`.

Chequeo automático: `Godot_console --headless --path . --script res://scripts/visual/tools/incoming_check.gd`
