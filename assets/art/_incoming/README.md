# _incoming — carpeta de recepción de arte

Dejar aquí los paquetes de sprites SIN procesar, organizados así:

```
_incoming/characters/players/leader_cat/      <- PNGs u hojas del gato líder
_incoming/characters/companions/police_cat/
_incoming/characters/enemies/zombie_dog_normal/
_incoming/characters/bosses/rottweiler_alpha/
```

**PROHIBIDO cargar nada de esta carpeta desde el juego** (el validador lo
detecta y lo marca como error). Flujo correcto:

```
_incoming → puerta de aceptación (docs/ART_ASSET_ACCEPTANCE_CHECKLIST.md)
  → limpieza/renombrado → assets/art/characters/... (definitiva)
  → SpriteFrames → VisualProfile (enabled=false) → validador → QA → enabled=true
```

Cada paquete recibido se registra en `docs/ART_IMPORT_MANIFEST.md`
(aceptado o rechazado, con motivos).
