extends Sprite2D

@export var camera_offset := Vector2.ZERO
@export_range(0.1, 1.0, 0.01) var minimum_camera_zoom := 0.45

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null or texture == null:
		return
	# Match grappler's camera-following world sprite: translation follows the
	# camera, while zoom still changes the apparent size of the clouds.
	global_position = camera.get_screen_center_position() + camera_offset
	# Reserve enough sky for the widest zoom instead of resizing it to fit
	# each frame's zoom. Also cover taller browser windows without stretching.
	var cover_zoom := minf(minimum_camera_zoom, minf(camera.zoom.x, camera.zoom.y))
	var required_size := get_viewport_rect().size / maxf(cover_zoom, 0.01) + camera_offset.abs() * 2.0
	var texture_size := texture.get_size()
	var cover_scale := maxf(required_size.x / texture_size.x, required_size.y / texture_size.y)
	global_scale = Vector2.ONE * cover_scale
