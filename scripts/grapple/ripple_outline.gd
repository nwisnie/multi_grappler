extends RefCounted
## Shared traveling wave for grapple orbs, race hoops, and HUD arrows.

const POINT_COUNT := 96

static func wave(phase: float, seed: float, time: float) -> float:
	return sin(phase * 4.0 - time * 2.0 + seed) * 0.7 + sin(phase * 7.0 + time + seed * 1.7) * 0.3

static func points(radius: float, stroke_width: float, irregularity: float, seed: float, time: float) -> PackedVector2Array:
	var outline := PackedVector2Array()
	var amplitude := minf(radius * irregularity, stroke_width * 0.4)
	for index in range(POINT_COUNT):
		var angle := TAU * float(index) / float(POINT_COUNT)
		outline.append(Vector2.RIGHT.rotated(angle) * (radius + amplitude * wave(angle, seed, time)))
	return outline
