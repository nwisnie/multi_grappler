class_name LevelCodec
extends RefCounted
## MG1- + Base64(DEFLATE(payload)). No resources or executable objects are decoded.
## Payload: version u8, segment count u16 LE, orb count u8, spawn x/y u8,
## segments [kind,a.x,a.y,b.x,b.y,(m.x,m.y)], orbs [x,y]. No spawn = 255,255.

const PREFIX := "MG1-"
const MAX_PAYLOAD := 6 + LevelDocument.MAX_SEGMENTS * 7 + LevelDocument.MAX_ORBS * 2
const MAX_CODE_LENGTH := 16384

static func encode_level(document: LevelDocument) -> String:
	if not document.validate().is_empty():
		return ""
	var payload := PackedByteArray([LevelDocument.VERSION, document.segments.size() & 255, document.segments.size() >> 8, document.orbs.size()])
	if LevelDocument.valid_cell(document.spawn):
		payload.append_array(PackedByteArray([document.spawn.x, document.spawn.y]))
	else:
		payload.append_array(PackedByteArray([255, 255]))
	for segment in document.segments:
		payload.append(segment["kind"])
		for key in ["a", "b"]:
			payload.append(segment[key].x)
			payload.append(segment[key].y)
		if segment["kind"] == LevelDocument.SegmentKind.CURVE:
			payload.append(segment["m"].x)
			payload.append(segment["m"].y)
	for orb in document.orbs:
		payload.append(orb.x)
		payload.append(orb.y)
	return PREFIX + Marshalls.raw_to_base64(payload.compress(FileAccess.COMPRESSION_DEFLATE))

static func decode_level(code: String) -> Dictionary:
	if code.length() > MAX_CODE_LENGTH:
		return {"error": "The level code is too large."}
	var clean := code.strip_edges().replace("\n", "").replace("\r", "").replace(" ", "").replace("\t", "")
	if not clean.begins_with(PREFIX):
		return {"error": "Unsupported level code. Expected MG1-."}
	var encoded := clean.substr(PREFIX.length())
	if encoded.is_empty() or encoded.length() % 4 != 0:
		return {"error": "The level code is incomplete."}
	# Strict Base64 validation before calling the engine decoder.
	var base64 := RegEx.new()
	base64.compile("^[A-Za-z0-9+/]+={0,2}$")
	if base64.search(encoded) == null:
		return {"error": "The level code contains invalid characters."}
	var compressed := Marshalls.base64_to_raw(encoded)
	if Marshalls.raw_to_base64(compressed) != encoded:
		return {"error": "The level code is damaged."}
	var payload := compressed.decompress_dynamic(MAX_PAYLOAD, FileAccess.COMPRESSION_DEFLATE)
	if payload.size() < 6:
		return {"error": "The level code is damaged or exceeds the level limits."}
	if payload[0] != LevelDocument.VERSION:
		return {"error": "Unsupported level version."}
	var segment_count := int(payload[1]) | (int(payload[2]) << 8)
	var orb_count := int(payload[3])
	if segment_count > LevelDocument.MAX_SEGMENTS or orb_count > LevelDocument.MAX_ORBS:
		return {"error": "The level exceeds the segment or orb limit."}
	var document := LevelDocument.new()
	if payload[4] != 255 or payload[5] != 255:
		document.spawn = Vector2i(payload[4], payload[5])
	var cursor := 6
	for index in range(segment_count):
		if cursor + 5 > payload.size():
			return {"error": "The terrain data is truncated."}
		var kind := int(payload[cursor])
		var segment := {"kind": kind, "a": Vector2i(payload[cursor + 1], payload[cursor + 2]), "b": Vector2i(payload[cursor + 3], payload[cursor + 4])}
		cursor += 5
		if kind == LevelDocument.SegmentKind.CURVE:
			if cursor + 2 > payload.size():
				return {"error": "The curve data is truncated."}
			segment["m"] = Vector2i(payload[cursor], payload[cursor + 1])
			cursor += 2
		document.segments.append(segment)
	if cursor + orb_count * 2 != payload.size():
		return {"error": "The level code has missing or unexpected data."}
	for index in range(orb_count):
		document.orbs.append(Vector2i(payload[cursor], payload[cursor + 1]))
		cursor += 2
	var error := document.validate()
	if not error.is_empty():
		return {"error": error}
	return {"error": "", "document": document}
