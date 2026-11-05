extends RefCounted
## Shared traveling-wave outline for grapple orbs and race hoops.

const POINT_COUNT := 96

static func points(radius: float, stroke_width: float, irregularity: float, seed: float, time: float) -> PackedVector2Array:
	var outline := PackedVector2Array()
	var amplitude := minf(radius * irregularity, stroke_width * 0.4)
	for index in range(POINT_COUNT):
		var angle := TAU * float(index) / float(POINT_COUNT)
		var wave := sin(angle * 4.0 - time * 2.0 + seed) * 0.7 + sin(angle * 7.0 + time + seed * 1.7) * 0.3
		outline.append(Vector2.RIGHT.rotated(angle) * (radius + amplitude * wave))
	return outline
