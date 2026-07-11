# ART IMPORT MANIFEST — registro de paquetes recibidos

Un registro por paquete que entre por `assets/art/_incoming/`. Copiar la
plantilla, rellenarla y conservar el historial (también de los rechazados).

**Estados del ciclo (Etapa 3)**: RECEIVED → AUTOMATIC_CHECK_FAILED /
MANUAL_REVIEW → REJECTED / PILOT_APPROVED → FINAL_APPROVED → INTEGRATED →
REGRESSION_APPROVED. Registrar además qué direcciones son frames REALES y
cuáles ESPEJADAS (crítico en personajes asimétricos: bufanda del gato y
oreja/herida del perro van al lado IZQUIERDO del personaje).

---

## Plantilla

```
### <ID del personaje> — <fecha>
- Nombre: 
- Archivos recibidos: (lista con rutas de _incoming)
- Dimensiones: (px por frame / hoja)
- Direcciones: (1 / 4 / 5+flip / 8)
- Animaciones incluidas: (idle, run, ...)
- Frames por animación: 
- Transparencia: (alfa real sí/no, halos sí/no)
- Pivote / línea de suelo: (y en px, consistente sí/no)
- Escala respecto al elenco: 
- Errores encontrados: 
- Correcciones realizadas: 
- Perfil creado: (ruta .tres / no)
- Resultado: APROBADO / RECHAZADO (motivos)
```

---

## Registros

### TEST_ONLY_test_cat — Etapa Artística 1
- Nombre: Gato de prueba técnica (TEMPORARY / NOT_FINAL_ART)
- Archivos recibidos: generado por código (`make_test_sprite.gd`), no entró
  por _incoming.
- Dimensiones: celda 128×128, hoja 512×256.
- Direcciones: 1.
- Animaciones: idle, run, attack, hurt, death (reutilizan 8 frames de prueba).
- Frames por animación: 4.
- Transparencia: alfa real, sin halos (generado).
- Pivote: línea de suelo y=112, consistente.
- Escala: 0.5 (autoría 2×).
- Errores: no aplica (asset de validación de pipeline).
- Perfil creado: `data/visual_profiles/players/test_cat.tres` (`enabled=false`).
- Resultado: **APROBADO SOLO COMO TEST TÉCNICO** — el validador bloquea su
  activación (`enabled=true` con TEST_ONLY = error) y el controlador lo ignora
  en modo AUTO.

*(Sin paquetes de arte definitivo recibidos hasta la fecha.)*
