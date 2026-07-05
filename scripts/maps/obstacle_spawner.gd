extends "res://scripts/maps/map_chunk_manager.gd"
## Compatibilidad con la escena existente: el nodo sigue llamandose
## ObstacleSpawner y MapManager sigue llamando generate()/clear()/is_point_clear(),
## pero la implementacion real ahora vive en MapChunkManager y genera por chunks.
