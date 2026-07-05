# FASE 02 - Upgrades, dificultad y segundo enemigo

## Que se implemento

- Sistema modular de upgrades con `UpgradeManager`.
- Pausa de partida al subir de nivel y reanudacion al elegir una carta.
- UI de 3 cartas placeholder integrada en el HUD existente.
- Stats modificables y acumulativas en `Player` y `AutoWeapon`.
- Disparo de proyectiles extra con separacion angular.
- Escalado de dificultad por tiempo en `EnemySpawner`.
- Segundo tipo de enemigo rapido reutilizando `Enemy.tscn`.
- Configuracion de enemigos mediante `EnemyData` resources.

## Como funciona el sistema de upgrades

- `Player` sigue controlando XP y nivel, pero ahora emite `level_up_requested`.
- `UpgradeManager` escucha esa señal, pausa `SceneTree` y pide al HUD mostrar 3 cartas.
- Las cartas se eligen al azar desde un pool fijo y pueden repetirse.
- El HUD solo muestra la UI y emite `upgrade_card_selected`.
- `UpgradeManager` aplica la mejora llamando `player.apply_upgrade(...)`.
- Si un mismo pickup causara varios niveles, el manager encola las selecciones y las muestra una tras otra.

## Mejoras incluidas

- `weapon_damage`: +20% daño del arma.
- `weapon_cooldown`: -15% cooldown del arma.
- `player_speed`: +15% velocidad del jugador.
- `max_health`: +20 vida maxima y curacion inmediata por ese mismo valor.
- `extra_projectile`: +1 proyectil.
- `weapon_range`: +20% rango del arma.

## Como funciona el escalado

- `EnemySpawner` tiene un timer de dificultad aparte del timer de spawn.
- Cada 60 segundos:
  - baja un poco el intervalo de aparicion;
  - sube el multiplicador de vida enemiga;
  - sube el multiplicador de velocidad enemiga.
- Todos esos valores tienen limites (`min_spawn_interval`, `max_health_multiplier`, `max_speed_multiplier`) para evitar una curva imposible demasiado pronto.

## Como agregar nuevas mejoras

1. Abrir `scripts/systems/upgrade_manager.gd`.
2. Añadir una nueva entrada al arreglo `UPGRADE_POOL` con:
   - `id`
   - `name`
   - `description`
3. Abrir `scripts/player/player.gd`.
4. Extender `apply_upgrade(upgrade_id)` con el nuevo caso.
5. Si la mejora afecta otro sistema, exponer un metodo pequeño en ese sistema y llamarlo desde `Player`.

## Como agregar nuevos tipos de enemigos

1. Duplicar uno de los `.tres` en `data/enemies/`.
2. Ajustar stats y colores del nuevo `EnemyData`.
3. Añadir ese resource a `enemy_types` en `scenes/levels/MainLevel.tscn` o desde el inspector.
4. Ajustar `spawn_weight` para controlar su frecuencia de aparicion.

## Que queda pendiente para Fase 03

- Variedad mayor de armas y upgrades sin hardcodear el pool.
- Balance fino de valores y curvas de dificultad.
- Feedback visual/audio al elegir upgrades.
- Mas tipos de enemigos y patrones de spawn.
- Posibles elites, mini-jefes o eventos de oleada.
