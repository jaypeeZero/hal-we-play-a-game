class_name SpatialGridSystem
extends RefCounted

## Pure functional uniform spatial grid for range queries.
##
## A grid is a Dictionary {cell_size: float, cells: Dictionary[Vector2i -> Array]}.
## Built fresh each frame from current positions and dropped after queries —
## the grid is a value, not a long-lived structure. Queries return a candidate
## superset; callers do the exact distance check.

# ============================================================================
# BUILD
# ============================================================================

## Bucket entities by cell coordinate. Entities without a `position` Vector2
## are skipped silently — callers shouldn't pass them in.
static func build(entities: Array, cell_size: float) -> Dictionary:
	var cells: Dictionary = {}
	if cell_size <= 0.0:
		return {"cell_size": cell_size, "cells": cells}

	for entity in entities:
		if entity == null:
			continue
		var pos: Vector2 = entity.position
		var cell := Vector2i(
			int(floor(pos.x / cell_size)),
			int(floor(pos.y / cell_size))
		)
		if not cells.has(cell):
			cells[cell] = []
		cells[cell].append(entity)

	return {"cell_size": cell_size, "cells": cells}

# ============================================================================
# QUERY
# ============================================================================

## Return all entities in cells overlapping the query circle.
## Result is a superset — callers must apply the exact distance test.
static func query_radius(grid: Dictionary, position: Vector2, radius: float) -> Array:
	var result: Array = []
	var cell_size: float = grid.get("cell_size", 0.0)
	if cell_size <= 0.0:
		return result

	var cells: Dictionary = grid.get("cells", {})
	if cells.is_empty():
		return result

	var cell_radius: int = int(ceil(radius / cell_size))
	var center := Vector2i(
		int(floor(position.x / cell_size)),
		int(floor(position.y / cell_size))
	)

	for dx in range(-cell_radius, cell_radius + 1):
		for dy in range(-cell_radius, cell_radius + 1):
			var cell := Vector2i(center.x + dx, center.y + dy)
			if cells.has(cell):
				result.append_array(cells[cell])

	return result
