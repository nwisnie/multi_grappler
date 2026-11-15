extends Control
## One continuous sky and mouse offset shared by the title and level browser.

const SKY := preload("res://assets/images/levels/bg_sky.png")
const PARALLAX_DISTANCE := Vector2(8.0, 5.0)
const SKY_MARGIN := 12.0
const PARALLAX_SPEED := 7.0

var sky: TextureRect
var parallax_offset := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky = TextureRect.new()
	sky.name = "ParallaxSky"
	sky.texture = SKY
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Overscan keeps the viewport covered throughout the motion.
	sky.offset_left = -SKY_MARGIN
	sky.offset_top = -SKY_MARGIN
	sky.offset_right = SKY_MARGIN
	sky.offset_bottom = SKY_MARGIN
	var wash := ColorRect.new()
	wash.color = Color(0.85, 0.95, 1.0, 0.12)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var half_size := size * 0.5
	if half_size.x <= 0.0 or half_size.y <= 0.0:
		return
	var target := ((get_local_mouse_position() - half_size) / half_size).clamp(-Vector2.ONE, Vector2.ONE)
	parallax_offset = parallax_offset.lerp(target, 1.0 - exp(-PARALLAX_SPEED * delta))
	sky.position = -Vector2.ONE * SKY_MARGIN - parallax_offset * PARALLAX_DISTANCE
