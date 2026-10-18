@tool
extends EditorPlugin

const LevelSketchScript := preload("res://scripts/level_sketch.gd")
const ICON := preload("res://icon.svg")

var sketch: LevelSketch
var drawing := false
var toolbar: HBoxContainer
var dock: VBoxContainer
var dock_status: Label
var bake_button: Button
var undo_button: Button
var clear_button: Button
var dock_bake_button: Button
var dock_undo_button: Button
var dock_clear_button: Button
var toolbar_line_button: Button
var toolbar_ground_button: Button
var dock_line_button: Button
var dock_ground_button: Button
var thickness_label: Label
var toolbar_thickness_label: Label
var thickness_slider: HSlider
var thickness_spin_box: SpinBox
var toolbar_thickness_slider: HSlider
var toolbar_thickness_spin_box: SpinBox
var edge_roundness_slider: HSlider
var edge_roundness_spin_box: SpinBox
var toolbar_edge_roundness_slider: HSlider
var toolbar_edge_roundness_spin_box: SpinBox
var grass_height_label: Label
var grass_height_row: HBoxContainer
var grass_height_slider: HSlider
var grass_height_spin_box: SpinBox
var updating_thickness_controls := false
var updating_roundness_controls := false
var updating_grass_height_controls := false
var updating_mode_controls := false
var fill_color_button: ColorPickerButton
var shading_color_button: ColorPickerButton
var highlight_color_button: ColorPickerButton
var outline_color_button: ColorPickerButton
var color_labels: Dictionary = {}
var updating_color_controls := false
var shading_check_box: CheckBox
var highlight_check_box: CheckBox
var updating_shading_control := false
var last_canvas_point := Vector2.ZERO
var has_last_canvas_point := false

func _enter_tree() -> void:
	add_custom_type("LevelSketch", "Node2D", LevelSketchScript, ICON)
	set_input_event_forwarding_always_enabled()
	set_force_draw_over_forwarding_enabled()
	_build_toolbar()
	_build_dock()
	get_editor_interface().get_selection().selection_changed.connect(_on_selection_changed)
	_on_selection_changed()

func _exit_tree() -> void:
	var selection := get_editor_interface().get_selection()
	if selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.disconnect(_on_selection_changed)
	if toolbar != null:
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, toolbar)
		toolbar.queue_free()
		toolbar = null
	if dock != null:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null
	remove_custom_type("LevelSketch")

func _handles(object: Object) -> bool:
	return object is LevelSketch

func _edit(object: Object) -> void:
	sketch = object as LevelSketch
	drawing = false
	_update_toolbar()

func _make_visible(visible: bool) -> void:
	if visible:
		_on_selection_changed()
	elif toolbar != null:
		toolbar.visible = false

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if sketch == null or not is_instance_valid(sketch):
		return false

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			drawing = true
			last_canvas_point = _event_to_sketch_position(event.position)
			has_last_canvas_point = true
			sketch.begin_stroke(last_canvas_point)
			update_overlays()
			return true
		if drawing:
			drawing = false
			sketch.finish_stroke()
			_mark_scene_changed()
			_update_toolbar()
			update_overlays()
			return true

	if event is InputEventMouseMotion and drawing:
		last_canvas_point = _event_to_sketch_position(event.position)
		has_last_canvas_point = true
		sketch.add_stroke_point(last_canvas_point)
		update_overlays()
		return true

	return false

func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if sketch == null or not is_instance_valid(sketch):
		return
	for index in range(sketch.strokes.size()):
		_draw_overlay_stroke(overlay, sketch.strokes[index], 0.9, sketch.get_stroke_mode(index))
	_draw_overlay_stroke(overlay, sketch.active_stroke, 0.55, sketch.active_stroke_mode)
	if has_last_canvas_point:
		var marker_position := _sketch_space_to_viewport(last_canvas_point)
		overlay.draw_circle(marker_position, 6.0, Color(1.0, 0.1, 0.1, 0.9))
		overlay.draw_arc(marker_position, 11.0, 0.0, TAU, 32, Color(0.0, 0.0, 0.0, 0.9), 2.0)

func _build_toolbar() -> void:
	toolbar = HBoxContainer.new()
	toolbar.visible = false

	var mode_label := Label.new()
	mode_label.text = "Mode"
	toolbar.add_child(mode_label)

	var toolbar_mode_group := ButtonGroup.new()
	toolbar_line_button = _make_mode_button("Line", LevelSketch.DrawMode.LINE, toolbar_mode_group)
	toolbar_ground_button = _make_mode_button("Ground", LevelSketch.DrawMode.GROUND, toolbar_mode_group)
	toolbar.add_child(toolbar_line_button)
	toolbar.add_child(toolbar_ground_button)

	toolbar_thickness_label = Label.new()
	toolbar_thickness_label.text = "Thickness"
	toolbar.add_child(toolbar_thickness_label)

	toolbar_thickness_slider = HSlider.new()
	toolbar_thickness_slider.min_value = 8.0
	toolbar_thickness_slider.max_value = 256.0
	toolbar_thickness_slider.step = 1.0
	toolbar_thickness_slider.custom_minimum_size = Vector2(140, 0)
	toolbar_thickness_slider.value_changed.connect(_on_thickness_changed)
	toolbar.add_child(toolbar_thickness_slider)

	toolbar_thickness_spin_box = SpinBox.new()
	toolbar_thickness_spin_box.min_value = 8.0
	toolbar_thickness_spin_box.max_value = 256.0
	toolbar_thickness_spin_box.step = 1.0
	toolbar_thickness_spin_box.custom_minimum_size = Vector2(84, 0)
	toolbar_thickness_spin_box.value_changed.connect(_on_thickness_changed)
	toolbar.add_child(toolbar_thickness_spin_box)

	var roundness_label := Label.new()
	roundness_label.text = "Roundness"
	toolbar.add_child(roundness_label)

	toolbar_edge_roundness_slider = HSlider.new()
	toolbar_edge_roundness_slider.min_value = 0.0
	toolbar_edge_roundness_slider.max_value = 100.0
	toolbar_edge_roundness_slider.step = 1.0
	toolbar_edge_roundness_slider.custom_minimum_size = Vector2(90, 0)
	toolbar_edge_roundness_slider.value_changed.connect(_on_roundness_changed)
	toolbar.add_child(toolbar_edge_roundness_slider)

	toolbar_edge_roundness_spin_box = SpinBox.new()
	toolbar_edge_roundness_spin_box.min_value = 0.0
	toolbar_edge_roundness_spin_box.max_value = 100.0
	toolbar_edge_roundness_spin_box.step = 1.0
	toolbar_edge_roundness_spin_box.suffix = "%"
	toolbar_edge_roundness_spin_box.custom_minimum_size = Vector2(76, 0)
	toolbar_edge_roundness_spin_box.value_changed.connect(_on_roundness_changed)
	toolbar.add_child(toolbar_edge_roundness_spin_box)

	bake_button = Button.new()
	bake_button.text = "Bake"
	bake_button.tooltip_text = "Bake the selected LevelSketch into fixed terrain nodes."
	bake_button.pressed.connect(_on_bake_pressed)
	toolbar.add_child(bake_button)

	undo_button = Button.new()
	undo_button.text = "Undo"
	undo_button.tooltip_text = "Remove the last sketch stroke."
	undo_button.pressed.connect(_on_undo_pressed)
	toolbar.add_child(undo_button)

	clear_button = Button.new()
	clear_button.text = "Clear"
	clear_button.tooltip_text = "Remove all sketch strokes."
	clear_button.pressed.connect(_on_clear_pressed)
	toolbar.add_child(clear_button)

	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, toolbar)

func _build_dock() -> void:
	dock = VBoxContainer.new()
	dock.name = "LevelSketch"
	dock_status = Label.new()
	dock_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(dock_status)

	var mode_label := Label.new()
	mode_label.text = "Draw Mode"
	dock.add_child(mode_label)

	var mode_row := HBoxContainer.new()
	mode_row.custom_minimum_size = Vector2(240, 0)
	dock.add_child(mode_row)
	var dock_mode_group := ButtonGroup.new()
	dock_line_button = _make_mode_button("Line", LevelSketch.DrawMode.LINE, dock_mode_group)
	dock_ground_button = _make_mode_button("Ground", LevelSketch.DrawMode.GROUND, dock_mode_group)
	dock_line_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock_ground_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_child(dock_line_button)
	mode_row.add_child(dock_ground_button)

	thickness_label = Label.new()
	thickness_label.text = "Line Thickness"
	dock.add_child(thickness_label)

	var thickness_row := HBoxContainer.new()
	thickness_row.custom_minimum_size = Vector2(240, 0)
	dock.add_child(thickness_row)

	thickness_slider = HSlider.new()
	thickness_slider.min_value = 8.0
	thickness_slider.max_value = 256.0
	thickness_slider.step = 1.0
	thickness_slider.custom_minimum_size = Vector2(140, 0)
	thickness_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thickness_slider.value_changed.connect(_on_thickness_changed)
	thickness_row.add_child(thickness_slider)

	thickness_spin_box = SpinBox.new()
	thickness_spin_box.min_value = 8.0
	thickness_spin_box.max_value = 256.0
	thickness_spin_box.step = 1.0
	thickness_spin_box.custom_minimum_size = Vector2(84, 0)
	thickness_spin_box.value_changed.connect(_on_thickness_changed)
	thickness_row.add_child(thickness_spin_box)

	var roundness_label := Label.new()
	roundness_label.text = "Edge Roundness"
	dock.add_child(roundness_label)

	var roundness_row := HBoxContainer.new()
	roundness_row.custom_minimum_size = Vector2(240, 0)
	dock.add_child(roundness_row)

	edge_roundness_slider = HSlider.new()
	edge_roundness_slider.min_value = 0.0
	edge_roundness_slider.max_value = 100.0
	edge_roundness_slider.step = 1.0
	edge_roundness_slider.custom_minimum_size = Vector2(140, 0)
	edge_roundness_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edge_roundness_slider.value_changed.connect(_on_roundness_changed)
	roundness_row.add_child(edge_roundness_slider)

	edge_roundness_spin_box = SpinBox.new()
	edge_roundness_spin_box.min_value = 0.0
	edge_roundness_spin_box.max_value = 100.0
	edge_roundness_spin_box.step = 1.0
	edge_roundness_spin_box.suffix = "%"
	edge_roundness_spin_box.custom_minimum_size = Vector2(84, 0)
	edge_roundness_spin_box.value_changed.connect(_on_roundness_changed)
	roundness_row.add_child(edge_roundness_spin_box)

	grass_height_label = Label.new()
	grass_height_label.text = "Grass Height"
	dock.add_child(grass_height_label)

	grass_height_row = HBoxContainer.new()
	grass_height_row.custom_minimum_size = Vector2(240, 0)
	dock.add_child(grass_height_row)

	grass_height_slider = HSlider.new()
	grass_height_slider.min_value = 4.0
	grass_height_slider.max_value = 512.0
	grass_height_slider.step = 1.0
	grass_height_slider.custom_minimum_size = Vector2(140, 0)
	grass_height_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grass_height_slider.value_changed.connect(_on_grass_height_changed)
	grass_height_row.add_child(grass_height_slider)

	grass_height_spin_box = SpinBox.new()
	grass_height_spin_box.min_value = 4.0
	grass_height_spin_box.max_value = 512.0
	grass_height_spin_box.step = 1.0
	grass_height_spin_box.custom_minimum_size = Vector2(84, 0)
	grass_height_spin_box.value_changed.connect(_on_grass_height_changed)
	grass_height_row.add_child(grass_height_spin_box)

	var colors_label := Label.new()
	colors_label.text = "Colors"
	dock.add_child(colors_label)

	outline_color_button = _add_color_row("Outline", "outline")
	fill_color_button = _add_color_row("Fill", "fill")
	shading_color_button = _add_color_row("Shading", "shading")
	highlight_color_button = _add_color_row("Highlight", "highlight")

	shading_check_box = CheckBox.new()
	shading_check_box.text = "Show Shading"
	shading_check_box.tooltip_text = "Preview and bake the smaller hand-drawn shading stroke."
	shading_check_box.toggled.connect(_on_shading_toggled)
	dock.add_child(shading_check_box)

	highlight_check_box = CheckBox.new()
	highlight_check_box.text = "Show Highlight"
	highlight_check_box.tooltip_text = "Preview and bake the thin broken shiny highlight stroke."
	highlight_check_box.toggled.connect(_on_highlight_toggled)
	dock.add_child(highlight_check_box)

	dock_bake_button = Button.new()
	dock_bake_button.text = "Bake"
	dock_bake_button.tooltip_text = "Bake the selected LevelSketch into fixed terrain nodes."
	dock_bake_button.pressed.connect(_on_bake_pressed)
	dock.add_child(dock_bake_button)

	dock_undo_button = Button.new()
	dock_undo_button.text = "Undo"
	dock_undo_button.tooltip_text = "Remove the last sketch stroke."
	dock_undo_button.pressed.connect(_on_undo_pressed)
	dock.add_child(dock_undo_button)

	dock_clear_button = Button.new()
	dock_clear_button.text = "Clear"
	dock_clear_button.tooltip_text = "Remove all sketch strokes."
	dock_clear_button.pressed.connect(_on_clear_pressed)
	dock.add_child(dock_clear_button)

	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)

func _make_mode_button(label_text: String, mode: int, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.text = label_text
	button.toggle_mode = true
	button.button_group = group
	button.pressed.connect(_on_mode_selected.bind(mode))
	return button

func _add_color_row(label_text: String, color_role: String) -> ColorPickerButton:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(240, 0)
	dock.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(72, 0)
	row.add_child(label)
	color_labels[color_role] = label

	var button := ColorPickerButton.new()
	button.edit_alpha = true
	button.custom_minimum_size = Vector2(140, 0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = "Pick a color or enter an HTML hex value."
	button.color_changed.connect(_on_color_changed.bind(color_role))
	row.add_child(button)
	return button

func _on_selection_changed() -> void:
	var selected := get_editor_interface().get_selection().get_selected_nodes()
	sketch = null
	drawing = false
	for node in selected:
		if node is LevelSketch:
			sketch = node
			break
	_update_toolbar()

func _event_to_sketch_position(viewport_position: Vector2) -> Vector2:
	var editor_viewport := get_editor_interface().get_editor_viewport_2d()
	if editor_viewport != null:
		return editor_viewport.get_final_transform().affine_inverse() * viewport_position
	return viewport_position

func _sketch_space_to_viewport(point: Vector2) -> Vector2:
	var editor_viewport := get_editor_interface().get_editor_viewport_2d()
	if editor_viewport != null:
		return editor_viewport.get_final_transform() * point
	return point

func _draw_overlay_stroke(overlay: Control, stroke: PackedVector2Array, alpha: float, mode: int) -> void:
	if stroke.is_empty():
		return
	if mode == LevelSketch.DrawMode.GROUND:
		_draw_overlay_ground(overlay, stroke, alpha)
		return
	var display_stroke := sketch.make_outline_points(stroke)
	var points := PackedVector2Array()
	for point in display_stroke:
		points.append(_sketch_space_to_viewport(point))
	var outline_color := sketch.outline_color
	outline_color.a *= alpha
	var fill_color := sketch.fill_color
	fill_color.a *= alpha
	var shading_color := sketch.shading_color
	shading_color.a *= alpha
	var highlight_color := sketch.highlight_color
	highlight_color.a *= alpha
	if points.size() < 2:
		overlay.draw_circle(points[0], sketch.terrain_half_width * 0.35 * _canvas_scale(), outline_color)
		return
	var scale := _canvas_scale()
	var cap_roundness := sketch.edge_roundness / 100.0
	_draw_overlay_rounded_polyline(overlay, points, outline_color, (sketch.terrain_half_width * 2.0 + 12.0) * scale, cap_roundness)
	_draw_overlay_rounded_polyline(overlay, points, fill_color, sketch.terrain_half_width * 2.0 * scale, cap_roundness)
	if sketch.show_shading:
		_draw_overlay_rounded_polyline(
			overlay,
			_points_to_viewport(sketch.make_shading_points(stroke)),
			shading_color,
			sketch.terrain_half_width * 2.0 * 0.42 * scale,
			cap_roundness
		)
	if sketch.show_highlight:
		for highlight_segment in sketch.make_highlight_segments(stroke):
			_draw_overlay_rounded_polyline(
				overlay,
				_points_to_viewport(highlight_segment),
				highlight_color,
				sketch.terrain_half_width * 2.0 * 0.14 * scale,
				cap_roundness
			)
	_draw_overlay_rounded_polyline(overlay, points, outline_color, 4.0 * scale, cap_roundness)

func _draw_overlay_ground(overlay: Control, stroke: PackedVector2Array, alpha: float) -> void:
	if stroke.size() < 2:
		return
	var ground_polygon := sketch.make_ground_visual_polygon(stroke)
	var grass_polygon := sketch.make_ground_grass_polygon(stroke)
	var body_color := sketch.ground_shading_color if sketch.ground_show_shading else sketch.ground_fill_color
	body_color.a *= alpha
	var grass_color := sketch.ground_fill_color
	grass_color.a *= alpha
	var outline := sketch.ground_outline_color
	outline.a *= alpha
	var viewport_ground := _points_to_viewport(ground_polygon)
	var viewport_grass := _points_to_viewport(grass_polygon)
	overlay.draw_colored_polygon(viewport_ground, body_color)
	overlay.draw_colored_polygon(viewport_grass, grass_color)
	if sketch.ground_show_highlight:
		var speckles := sketch.make_ground_speckles(stroke)
		var speckle_points: PackedVector2Array = speckles.get("points", PackedVector2Array())
		var speckle_radii: PackedFloat32Array = speckles.get("radii", PackedFloat32Array())
		var speckle_color := sketch.ground_highlight_color
		speckle_color.a *= alpha
		var scale := _canvas_scale()
		for index in range(speckle_points.size()):
			var radius := speckle_radii[index] if index < speckle_radii.size() else 2.0
			overlay.draw_circle(_sketch_space_to_viewport(speckle_points[index]), radius * scale, speckle_color)
	if not viewport_ground.is_empty():
		viewport_ground.append(viewport_ground[0])
		overlay.draw_polyline(viewport_ground, outline, 4.0 * _canvas_scale(), true)

func _draw_overlay_rounded_polyline(overlay: Control, points: PackedVector2Array, color: Color, width: float, cap_roundness: float = 1.0) -> void:
	if points.size() < 2:
		return
	overlay.draw_polyline(points, color, width, true)
	var extension := width * 0.5 * clampf(cap_roundness, 0.0, 1.0)
	if extension > 0.0:
		_draw_overlay_elliptical_cap(overlay, points[0], points[1] - points[0], width * 0.5, extension, color)
		_draw_overlay_elliptical_cap(overlay, points[-1], points[-1] - points[-2], width * 0.5, extension, color)

func _draw_overlay_elliptical_cap(overlay: Control, center: Vector2, tangent: Vector2, half_width: float, extension: float, color: Color) -> void:
	if tangent.length_squared() <= 0.001:
		return
	var forward := tangent.normalized()
	var normal := forward.orthogonal()
	var cap := PackedVector2Array()
	for index in range(24):
		var angle := TAU * float(index) / 24.0
		cap.append(center + forward * cos(angle) * extension + normal * sin(angle) * half_width)
	overlay.draw_colored_polygon(cap, color)

func _points_to_viewport(source_points: PackedVector2Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in source_points:
		points.append(_sketch_space_to_viewport(point))
	return points

func _canvas_scale() -> float:
	var editor_viewport := get_editor_interface().get_editor_viewport_2d()
	if editor_viewport == null:
		return 1.0
	var transform := editor_viewport.get_final_transform()
	return (transform.x.length() + transform.y.length()) * 0.5

func _on_bake_pressed() -> void:
	if sketch == null or not is_instance_valid(sketch):
		return
	sketch.bake_to_scene()
	_mark_scene_changed()
	_update_toolbar()

func _on_undo_pressed() -> void:
	if sketch == null or not is_instance_valid(sketch):
		return
	sketch.undo_stroke()
	_mark_scene_changed()
	_update_toolbar()

func _on_clear_pressed() -> void:
	if sketch == null or not is_instance_valid(sketch):
		return
	sketch.clear_strokes()
	_mark_scene_changed()
	_update_toolbar()

func _on_mode_selected(mode: int) -> void:
	if updating_mode_controls or sketch == null or not is_instance_valid(sketch):
		return
	sketch.draw_mode = mode
	_sync_mode_controls()
	_sync_thickness_controls()
	_sync_color_controls()
	_sync_shading_control()
	update_overlays()
	_mark_scene_changed()

func _on_thickness_changed(value: float) -> void:
	if updating_thickness_controls or sketch == null or not is_instance_valid(sketch):
		return
	if sketch.draw_mode == LevelSketch.DrawMode.GROUND:
		sketch.ground_depth = value
	else:
		sketch.terrain_half_width = value
	_sync_thickness_controls()
	update_overlays()
	_mark_scene_changed()

func _on_roundness_changed(value: float) -> void:
	if updating_roundness_controls or sketch == null or not is_instance_valid(sketch):
		return
	sketch.edge_roundness = value
	_sync_roundness_controls()
	update_overlays()
	_mark_scene_changed()

func _on_grass_height_changed(value: float) -> void:
	if updating_grass_height_controls or sketch == null or not is_instance_valid(sketch):
		return
	sketch.ground_grass_height = value
	_sync_grass_height_controls()
	update_overlays()
	_mark_scene_changed()

func _on_color_changed(color: Color, color_role: String) -> void:
	if updating_color_controls or sketch == null or not is_instance_valid(sketch):
		return
	sketch.set(_color_property_for_mode(color_role), color)
	_sync_color_controls()
	update_overlays()
	_mark_scene_changed()

func _on_shading_toggled(enabled: bool) -> void:
	if updating_shading_control or sketch == null or not is_instance_valid(sketch):
		return
	if sketch.draw_mode == LevelSketch.DrawMode.GROUND:
		sketch.ground_show_shading = enabled
	else:
		sketch.show_shading = enabled
	_sync_shading_control()
	update_overlays()
	_mark_scene_changed()

func _on_highlight_toggled(enabled: bool) -> void:
	if updating_shading_control or sketch == null or not is_instance_valid(sketch):
		return
	if sketch.draw_mode == LevelSketch.DrawMode.GROUND:
		sketch.ground_show_highlight = enabled
	else:
		sketch.show_highlight = enabled
	_sync_shading_control()
	update_overlays()
	_mark_scene_changed()

func _update_toolbar() -> void:
	if toolbar == null:
		return
	var has_sketch := sketch != null and is_instance_valid(sketch)
	toolbar.visible = has_sketch
	if has_sketch:
		bake_button.disabled = not sketch.has_bakeable_strokes()
		undo_button.disabled = not sketch.has_strokes()
		clear_button.disabled = not sketch.has_strokes()
		_sync_mode_controls()
		_sync_thickness_controls()
		_sync_roundness_controls()
		_sync_grass_height_controls()
		_sync_color_controls()
		_sync_shading_control()
	elif thickness_slider != null and thickness_spin_box != null:
		thickness_slider.editable = false
		thickness_spin_box.editable = false
		if toolbar_thickness_slider != null:
			toolbar_thickness_slider.editable = false
		if toolbar_thickness_spin_box != null:
			toolbar_thickness_spin_box.editable = false
		_set_roundness_controls_enabled(false)
		_set_grass_height_controls_enabled(false)
		_set_mode_controls_disabled(true)
		_set_color_controls_disabled(true)
		_set_shading_control_disabled(true)
	if dock_status != null:
		dock_status.text = "Draw with left-drag in the 2D editor viewport." if has_sketch else "Select a LevelSketch node to draw or bake terrain."
	if dock_bake_button != null:
		dock_bake_button.disabled = not has_sketch or not sketch.has_bakeable_strokes()
	if dock_undo_button != null:
		dock_undo_button.disabled = not has_sketch or not sketch.has_strokes()
	if dock_clear_button != null:
		dock_clear_button.disabled = not has_sketch or not sketch.has_strokes()

func _sync_thickness_controls() -> void:
	if thickness_slider == null or thickness_spin_box == null:
		return
	if sketch == null or not is_instance_valid(sketch):
		return
	var is_ground := sketch.draw_mode == LevelSketch.DrawMode.GROUND
	var value: float = sketch.ground_depth if is_ground else sketch.terrain_half_width
	var minimum := 64.0 if is_ground else 8.0
	var maximum := 4096.0 if is_ground else 256.0
	var label_text := "Ground Depth" if is_ground else "Line Thickness"
	updating_thickness_controls = true
	thickness_label.text = label_text
	toolbar_thickness_label.text = label_text
	thickness_slider.editable = true
	thickness_spin_box.editable = true
	thickness_slider.min_value = minimum
	thickness_slider.max_value = maximum
	thickness_spin_box.min_value = minimum
	thickness_spin_box.max_value = maximum
	thickness_slider.value = value
	thickness_spin_box.value = value
	if toolbar_thickness_slider != null:
		toolbar_thickness_slider.editable = true
		toolbar_thickness_slider.min_value = minimum
		toolbar_thickness_slider.max_value = maximum
		toolbar_thickness_slider.value = value
	if toolbar_thickness_spin_box != null:
		toolbar_thickness_spin_box.editable = true
		toolbar_thickness_spin_box.min_value = minimum
		toolbar_thickness_spin_box.max_value = maximum
		toolbar_thickness_spin_box.value = value
	updating_thickness_controls = false

func _sync_roundness_controls() -> void:
	if sketch == null or not is_instance_valid(sketch):
		_set_roundness_controls_enabled(false)
		return
	updating_roundness_controls = true
	_set_roundness_controls_enabled(true)
	edge_roundness_slider.value = sketch.edge_roundness
	edge_roundness_spin_box.value = sketch.edge_roundness
	toolbar_edge_roundness_slider.value = sketch.edge_roundness
	toolbar_edge_roundness_spin_box.value = sketch.edge_roundness
	updating_roundness_controls = false

func _set_roundness_controls_enabled(enabled: bool) -> void:
	if edge_roundness_slider != null:
		edge_roundness_slider.editable = enabled
	if edge_roundness_spin_box != null:
		edge_roundness_spin_box.editable = enabled
	if toolbar_edge_roundness_slider != null:
		toolbar_edge_roundness_slider.editable = enabled
	if toolbar_edge_roundness_spin_box != null:
		toolbar_edge_roundness_spin_box.editable = enabled

func _sync_grass_height_controls() -> void:
	if sketch == null or not is_instance_valid(sketch):
		_set_grass_height_controls_enabled(false)
		return
	var is_ground := sketch.draw_mode == LevelSketch.DrawMode.GROUND
	updating_grass_height_controls = true
	grass_height_label.visible = is_ground
	grass_height_row.visible = is_ground
	_set_grass_height_controls_enabled(is_ground)
	grass_height_slider.value = sketch.ground_grass_height
	grass_height_spin_box.value = sketch.ground_grass_height
	updating_grass_height_controls = false

func _set_grass_height_controls_enabled(enabled: bool) -> void:
	if grass_height_slider != null:
		grass_height_slider.editable = enabled
	if grass_height_spin_box != null:
		grass_height_spin_box.editable = enabled

func _sync_mode_controls() -> void:
	if sketch == null or not is_instance_valid(sketch):
		_set_mode_controls_disabled(true)
		return
	updating_mode_controls = true
	_set_mode_controls_disabled(false)
	var is_ground := sketch.draw_mode == LevelSketch.DrawMode.GROUND
	toolbar_line_button.button_pressed = not is_ground
	toolbar_ground_button.button_pressed = is_ground
	dock_line_button.button_pressed = not is_ground
	dock_ground_button.button_pressed = is_ground
	updating_mode_controls = false
	_sync_grass_height_controls()

func _set_mode_controls_disabled(disabled: bool) -> void:
	for button in [toolbar_line_button, toolbar_ground_button, dock_line_button, dock_ground_button]:
		if button != null:
			button.disabled = disabled

func _sync_color_controls() -> void:
	if outline_color_button == null or fill_color_button == null or shading_color_button == null or highlight_color_button == null:
		return
	if sketch == null or not is_instance_valid(sketch):
		_set_color_controls_disabled(true)
		return
	updating_color_controls = true
	_set_color_controls_disabled(false)
	outline_color_button.color = sketch.get(_color_property_for_mode("outline"))
	fill_color_button.color = sketch.get(_color_property_for_mode("fill"))
	shading_color_button.color = sketch.get(_color_property_for_mode("shading"))
	highlight_color_button.color = sketch.get(_color_property_for_mode("highlight"))
	var is_ground := sketch.draw_mode == LevelSketch.DrawMode.GROUND
	_set_color_label("outline", "Outline")
	_set_color_label("fill", "Grass" if is_ground else "Fill")
	_set_color_label("shading", "Dirt" if is_ground else "Shading")
	_set_color_label("highlight", "Speckles" if is_ground else "Highlight")
	updating_color_controls = false

func _color_property_for_mode(color_role: String) -> String:
	var prefix := "ground_" if sketch != null and sketch.draw_mode == LevelSketch.DrawMode.GROUND else ""
	return prefix + color_role + "_color"

func _set_color_label(color_role: String, text: String) -> void:
	var label := color_labels.get(color_role) as Label
	if label != null:
		label.text = text

func _set_color_controls_disabled(disabled: bool) -> void:
	if outline_color_button != null:
		outline_color_button.disabled = disabled
	if fill_color_button != null:
		fill_color_button.disabled = disabled
	if shading_color_button != null:
		shading_color_button.disabled = disabled or (sketch != null and is_instance_valid(sketch) and not sketch.show_shading)
	if highlight_color_button != null:
		highlight_color_button.disabled = disabled or (sketch != null and is_instance_valid(sketch) and not sketch.show_highlight)

func _sync_shading_control() -> void:
	if shading_check_box == null or highlight_check_box == null:
		return
	if sketch == null or not is_instance_valid(sketch):
		_set_shading_control_disabled(true)
		return
	updating_shading_control = true
	var is_ground := sketch.draw_mode == LevelSketch.DrawMode.GROUND
	shading_check_box.disabled = false
	shading_check_box.text = "Use Dirt Color" if is_ground else "Show Shading"
	shading_check_box.tooltip_text = "Use the Dirt color for the ground body." if is_ground else "Preview and bake the smaller hand-drawn shading stroke."
	shading_check_box.button_pressed = sketch.ground_show_shading if is_ground else sketch.show_shading
	highlight_check_box.disabled = false
	highlight_check_box.text = "Show Speckles" if is_ground else "Show Highlight"
	highlight_check_box.tooltip_text = "Preview and bake speckles throughout the dirt." if is_ground else "Preview and bake the thin broken shiny highlight stroke."
	highlight_check_box.button_pressed = sketch.ground_show_highlight if is_ground else sketch.show_highlight
	if shading_color_button != null:
		shading_color_button.disabled = false if is_ground else not sketch.show_shading
	if highlight_color_button != null:
		highlight_color_button.disabled = not (sketch.ground_show_highlight if is_ground else sketch.show_highlight)
	updating_shading_control = false

func _set_shading_control_disabled(disabled: bool) -> void:
	if shading_check_box != null:
		shading_check_box.disabled = disabled
	if highlight_check_box != null:
		highlight_check_box.disabled = disabled

func _mark_scene_changed() -> void:
	var edited_scene := get_editor_interface().get_edited_scene_root()
	if edited_scene != null:
		EditorInterface.mark_scene_as_unsaved()
