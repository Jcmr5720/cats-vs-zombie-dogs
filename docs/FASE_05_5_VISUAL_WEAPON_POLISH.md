# FASE 05.5 - Pulido visual, lectura de armas y enemigos

Pulido corto encima de FASE 05. No agrega sistemas nuevos: mejora lectura,
animacion y estilo de lo que ya existe.

## Armas y acumulacion

El gato acumula armas desde `WeaponManager`:

- empieza siempre con `Pistola Gatuna`
- puede tener hasta 4 armas activas
- las cartas de subida de nivel pueden ofrecer `Arma nueva` si queda ranura libre
- si ya tiene un arma, las cartas pueden ofrecer `Mejora de arma`
- cada arma llega hasta su `max_level`

El HUD ahora muestra 4 ranuras fijas con tipo, nivel actual/maximo y pips de progreso.
Esto evita que la acumulacion quede escondida como una lista de texto.

## Pulido visual aplicado

- Proyectiles modulares con silueta distinta por tipo:
  - bala: nucleo rapido y rastro corto
  - explosivo: forma irregular, halo mas grande y rastro pesado
  - boomerang/sardina: silueta curva y rastro fino
- Laser con linea mas gruesa que se apaga y destello en el origen.
- Catnip con anillo, nucleo y pulso para marcar zona de dano.
- Orbital con rastro y chispa central.
- Gato con sombra, collar/panuelo, parpadeo y movimiento de panuelo/cola.
- Perros zombis con sombra, parche, costillas, mandibula y orientacion hacia movimiento.
- Mini-jefe y jefe con mas masa visual, sombras, detalles de corrupcion y orientacion.

## Riesgos a revisar en playtest

- La rotacion de enemigos mejora lectura direccional, pero puede cambiar el feel visual
  de hordas densas.
- Los efectos nuevos son ligeros, pero conviene revisar FPS si se sube el maximo de
  enemigos por encima del tope actual.
- El HUD de armas ahora ocupa un poco mas de ancho para que no corte nombres.
