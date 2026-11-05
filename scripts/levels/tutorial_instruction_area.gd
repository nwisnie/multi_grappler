extends Area2D
## Resize the child CollisionPolygon2D to change where this instruction appears.

@export_multiline var instruction := ""
## Higher priority wins when the player overlaps multiple instruction areas.
@export var instruction_priority := 0

func contains_point(world_point: Vector2) -> bool:
	for child in get_children():
		if child is CollisionPolygon2D and not child.disabled:
			if Geometry2D.is_point_in_polygon(child.to_local(world_point), child.polygon):
				return true
	return false
