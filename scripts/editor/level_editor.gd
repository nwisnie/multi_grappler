class_name GridLevelEditor
extends Node2D

signal exit_requested
signal playtest_requested(document: LevelDocument)

const ToolbarButtonScript := preload("res://scripts/editor/editor_toolbar_button.gd")

enum Tool { SELECT, LINE, CURVE, SPAWN, ORB, ERASE }
const TOOL_NAMES := ["Select / move", "Line", "Curve", "Spawn", "Grapple orb", "Erase"]
const INSTRUCTIONS := [
	"Drag endpoints to move a shared joint; drag the curve's diamond to reshape it. Delete removes the selection.",
	"Click two grid intersections. Nearby endpoints snap together. Escape cancels.",
	"Click start, end, then a third grid intersection that the curve passes through. Escape cancels.",
	"Click a cell to place the player start. The spawn must be clear of terrain to playtest.",
	"Click a cell to place a grapple orb. Use Select to move it, or Erase to remove it.",
	"Click a terrain segment, spawn, or orb to remove it. Undo restores it."
]

class Gizmos extends Node2D:
	var editor: GridLevelEditor
	func _draw() -> void:
		editor.draw_gizmos(self)

class MenuPanel extends PanelContainer:
	var at_top := false
	func _draw() -> void:
		var points := PackedVector2Array()
		var baseline := 2.0 if at_top else size.y - 2.0
		for index in range(int(ceil(size.x / 28.0)) + 1):
			var x := minf(index * 28.0, size.x)
			var wobble := sin(index * 1.7) * 0.8 + sin(index * 0.63) * 0.6
			points.append(Vector2(x, baseline + wobble))
		draw_polyline(points, Color("6b8595"), 2.0, true)

var document := LevelDocument.new()
var tool: int = Tool.LINE
var pending: Array[Vector2i] = []
var hover_vertex := Vector2i.ZERO
var hover_cell := Vector2i.ZERO
var mouse_on_board := false
var hovered_handle := {}
var hovered_object := {}
var selection := {}
var drag := {}
var drag_original: LevelDocument
var drag_valid := true
var last_drag_grid := Vector2i(-999, -999)
var panning := false
var undo_stack: Array[LevelDocument] = []
var redo_stack: Array[LevelDocument] = []
var camera: Camera2D
var terrain: LevelTerrainVisual
var gizmos: Gizmos
var ui: CanvasLayer
var background_layer: CanvasLayer
var status: RichTextLabel
var counts: RichTextLabel
var undo_button: Button
var redo_button: Button
var tool_buttons: Array[Button] = []
var code_dialog: ConfirmationDialog
var code_text: TextEdit
var code_count: Label
var code_error: Label
var copy_button: Button
var importing := false
var clear_dialog: ConfirmationDialog
var top_panel: PanelContainer
var bottom_panel: PanelContainer

func _ready() -> void:
	camera = Camera2D.new()
	camera.position = Vector2.ONE * LevelDocument.BOARD_SIZE * 0.5
	camera.zoom = Vector2.ONE * 0.04
	add_child(camera)
	camera.make_current()
	terrain = LevelTerrainVisual.new()
	add_child(terrain)
	gizmos = Gizmos.new()
	gizmos.editor = self
	gizmos.z_index = 2
	add_child(gizmos)
	_build_ui()
	_refresh()
	get_viewport().size_changed.connect(_viewport_changed)
	_fit_after_layout.call_deferred()

func _button(text: String, callback: Callable) -> Button:
	var button := ToolbarButtonScript.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if text == "Playtest":
		button.theme_type_variation = &"PrimaryButton"
	elif text == "Clear":
		button.theme_type_variation = &"DangerButton"
	button.pressed.connect(callback)
	return button

func _strip(buttons: Array[Button]) -> PanelContainer:
	var strip := PanelContainer.new()
	var track := StyleBoxEmpty.new()
	track.set_content_margin_all(2.0)
	strip.add_theme_stylebox_override("panel", track)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	strip.add_child(row)
	for index in range(buttons.size()):
		var position := ToolbarButtonScript.Segment.MIDDLE
		if index == 0:
			position = ToolbarButtonScript.Segment.FIRST
		elif index == buttons.size() - 1:
			position = ToolbarButtonScript.Segment.LAST
		buttons[index].set("segment", position)
		row.add_child(buttons[index])
	return strip

func _menu_title(text: String) -> Label:
	var title := Label.new()
	title.text = text
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_vertical = Control.SIZE_FILL
	title.custom_minimum_size.x = 104
	title.add_theme_color_override("font_color", Color("9fb4c5"))
	title.add_theme_font_size_override("font_size", 14)
	return title

func _style_menu(panel: MenuPanel, divider_at_top: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101a25")
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 16.0 if divider_at_top else 10.0
	style.content_margin_bottom = 10.0 if divider_at_top else 16.0
	panel.add_theme_stylebox_override("panel", style)
	panel.at_top = divider_at_top
	panel.resized.connect(panel.queue_redraw)

func _style_dialog(dialog: ConfirmationDialog) -> void:
	var theme := preload("res://assets/themes/game_theme.tres")
	dialog.theme = theme
	# Godot 4.3 caches embedded title-bar items separately from dialog contents.
	# A zero-size icon removes both the title-bar X and its clickable area.
	var empty_icon := ImageTexture.new()
	for icon in ["close", "close_pressed"]:
		dialog.add_theme_icon_override(icon, empty_icon)
	dialog.add_theme_constant_override("close_h_offset", 0)
	dialog.add_theme_constant_override("close_v_offset", 0)
	for style in ["embedded_border", "embedded_unfocused_border"]:
		dialog.add_theme_stylebox_override(style, theme.get_stylebox(style, "Window"))

func _style_dialog_panel(dialog: ConfirmationDialog) -> void:
	var panel := dialog.theme.get_stylebox("panel", "AcceptDialog").duplicate() as StyleBoxFlat
	panel.corner_radius_top_left = 10
	panel.corner_radius_top_right = 10
	panel.corner_radius_bottom_left = 10
	panel.corner_radius_bottom_right = 10
	dialog.add_theme_stylebox_override("panel", panel)
	dialog.transparent_bg = true
	for key in ["embedded_border", "embedded_unfocused_border"]:
		var border := dialog.theme.get_stylebox(key, "Window").duplicate() as StyleBoxFlat
		border.corner_radius_bottom_left = 12
		border.corner_radius_bottom_right = 12
		border.border_width_left = 2
		border.border_width_right = 2
		border.border_width_bottom = 2
		border.expand_margin_left = 2.0
		border.expand_margin_right = 2.0
		border.expand_margin_bottom = 2.0
		border.border_color = Color("4c7187")
		border.bg_color = border.border_color
		dialog.add_theme_stylebox_override(key, border)

func _build_ui() -> void:
	background_layer = CanvasLayer.new()
	background_layer.layer = -10
	add_child(background_layer)
	var backdrop := ColorRect.new()
	backdrop.color = Color("101a25")
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_layer.add_child(backdrop)
	ui = CanvasLayer.new()
	ui.layer = 20
	add_child(ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	var top := MenuPanel.new()
	top_panel = top
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	root.add_child(top)
	_style_menu(top, false)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	top.add_child(margin)
	var rows := VBoxContainer.new()
	margin.add_child(rows)
	var actions := HFlowContainer.new()
	rows.add_child(actions)
	actions.add_child(_menu_title("Editor Actions"))
	var show_level := _button("Show whole level", fit_grid)
	show_level.tooltip_text = "Zoom and center the camera to show the entire level (F)."
	actions.add_child(_strip([
		_button("Playtest", _request_playtest),
		_button("Back to game", func() -> void: exit_requested.emit()),
		show_level,
	]))
	undo_button = _button("Undo", undo)
	redo_button = _button("Redo", redo)
	actions.add_child(_strip([undo_button, redo_button, _button("Clear", func() -> void: clear_dialog.popup_centered())]))
	actions.add_child(_strip([
		_button("Export code", func() -> void: _open_code(false)),
		_button("Import code", func() -> void: _open_code(true)),
	]))
	var tools := HFlowContainer.new()
	rows.add_child(tools)
	tools.add_child(_menu_title("Build Options"))
	var group := ButtonGroup.new()
	for index in range(TOOL_NAMES.size()):
		var button := _button(TOOL_NAMES[index], _set_tool.bind(index))
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = index == tool
		button.tooltip_text = INSTRUCTIONS[index]
		if index == Tool.ERASE:
			button.theme_type_variation = &"DangerButton"
		tool_buttons.append(button)
	tools.add_child(_strip(tool_buttons))
	counts = RichTextLabel.new()
	counts.bbcode_enabled = true
	counts.fit_content = true
	counts.scroll_active = false
	counts.autowrap_mode = TextServer.AUTOWRAP_OFF
	counts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	counts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	counts.add_theme_font_size_override("normal_font_size", 14)
	counts.add_theme_color_override("default_color", counts.get_theme_color("font_color", "Label"))
	tools.add_child(counts)
	var bottom := MenuPanel.new()
	bottom_panel = bottom
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -72
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(bottom)
	_style_menu(bottom, true)
	var footer := VBoxContainer.new()
	bottom.add_child(footer)
	status = RichTextLabel.new()
	status.bbcode_enabled = true
	status.fit_content = true
	status.scroll_active = false
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_theme_color_override("default_color", status.get_theme_color("font_color", "Label"))
	status.text = "Grid: 100 × 100 cells [color=#69bfff]|[/color] Cell size: 120 world units [color=#69bfff]|[/color] Export a code to keep your level."
	footer.add_child(status)
	var help := RichTextLabel.new()
	help.bbcode_enabled = true
	help.fit_content = true
	help.scroll_active = false
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help.add_theme_font_size_override("normal_font_size", 13)
	help.add_theme_color_override("default_color", help.get_theme_color("font_color", "Label"))
	var shortcuts := [
		["Scroll", "zoom out/in"],
		["Right Mouse", "Pan"],
		["Ctrl+Z", "Undo"],
		["Ctrl+Shift+Z", "Redo"],
		["F", "Show whole level"],
		["Esc", "Cancel placement"],
	]
	var hints := PackedStringArray()
	for shortcut in shortcuts:
		hints.append("%s: %s" % shortcut)
	help.text = "  [color=#69bfff]|[/color]  ".join(hints)
	footer.add_child(help)
	_build_code_dialog()
	clear_dialog = ConfirmationDialog.new()
	_style_dialog(clear_dialog)
	_style_dialog_panel(clear_dialog)
	clear_dialog.title = "Clear this level?"
	clear_dialog.dialog_text = "Remove all terrain, orbs, and the spawn? You can undo this."
	clear_dialog.confirmed.connect(clear_level)
	ui.add_child(clear_dialog)
	clear_dialog.get_ok_button().theme_type_variation = &"DangerButton"
	for button in [clear_dialog.get_ok_button(), clear_dialog.get_cancel_button()]:
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _build_code_dialog() -> void:
	code_dialog = ConfirmationDialog.new()
	_style_dialog(code_dialog)
	_style_dialog_panel(code_dialog)
	code_dialog.title = "Level code"
	code_dialog.min_size = Vector2i(560, 340)
	ui.add_child(code_dialog)
	# Keep early autowrap measurements from expanding the popup off-screen.
	# The scroll container also keeps the buttons reachable on small windows.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 280)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	code_dialog.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var label := Label.new()
	label.text = "Share the entire MG1- code. No upload or level file is needed."
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(label)
	code_text = TextEdit.new()
	var input_style := code_dialog.theme.get_stylebox("normal", "TextEdit").duplicate() as StyleBoxFlat
	code_text.add_theme_stylebox_override("normal", input_style)
	code_text.add_theme_stylebox_override("read_only", input_style)
	# Keep the focus border on the same rounded path as the input background.
	var input_focus := input_style.duplicate() as StyleBoxFlat
	input_focus.draw_center = false
	input_focus.border_color = input_style.border_color
	code_text.add_theme_stylebox_override("focus", input_focus)
	code_text.custom_minimum_size = Vector2(520, 210)
	code_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	code_text.text_changed.connect(func() -> void: code_count.text = "%s characters" % code_text.text.length())
	column.add_child(code_text)
	code_count = Label.new()
	column.add_child(code_count)
	code_error = Label.new()
	code_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	code_error.add_theme_color_override("font_color", Color("fda397"))
	column.add_child(code_error)
	copy_button = code_dialog.add_button("Copy code", false, "copy")
	copy_button.theme_type_variation = &"PrimaryButton"
	for button in [copy_button, code_dialog.get_ok_button(), code_dialog.get_cancel_button()]:
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	code_dialog.custom_action.connect(func(_action: StringName) -> void:
		DisplayServer.clipboard_set(code_text.text)
		code_text.grab_focus()
		code_text.select_all()
		code_error.text = "Code selected. If copying was blocked, press Ctrl+C (or Cmd+C)."
	)
	code_dialog.dialog_hide_on_ok = false
	code_dialog.confirmed.connect(_confirm_code)

func _open_code(is_import: bool) -> void:
	_cancel_action()
	importing = is_import
	code_dialog.title = "Import level code" if importing else "Export level code"
	code_dialog.ok_button_text = "Replace draft" if importing else "Done"
	code_dialog.cancel_button_text = "Cancel" if importing else "Close"
	copy_button.visible = not importing
	code_text.editable = importing
	code_text.text = "" if importing else LevelCodec.encode_level(document)
	code_count.text = "%s characters" % code_text.text.length()
	code_error.text = "Import replaces this draft; Undo restores it." if importing else "Keep this code before closing the game. Drafts are not saved automatically."
	code_dialog.popup_centered_ratio(0.65)
	code_text.grab_focus()
	if not importing:
		code_text.select_all()

func import_code(code: String) -> String:
	var result := LevelCodec.decode_level(code)
	if not result["error"].is_empty():
		return result["error"]
	_commit(result["document"])
	selection.clear()
	fit_grid()
	_set_status("Level imported. You can edit it or playtest it.")
	return ""

func _confirm_code() -> void:
	if importing:
		var error := import_code(code_text.text)
		if not error.is_empty():
			code_error.text = error
			return
	code_dialog.hide()

func _set_tool(value: int) -> void:
	_cancel_action()
	tool = value
	selection.clear()
	for index in range(tool_buttons.size()):
		tool_buttons[index].button_pressed = index == tool
	_refresh()

func _request_playtest() -> void:
	_cancel_action()
	var error := document.playtest_error()
	if not error.is_empty():
		_set_status(error, true)
		return
	playtest_requested.emit(document.copy())

func _set_status(message: String, error: bool = false) -> void:
	status.text = message
	status.modulate = Color("fda397") if error else Color.WHITE

func _remember(before: LevelDocument) -> void:
	undo_stack.append(before)
	if undo_stack.size() > 100:
		undo_stack.pop_front()
	redo_stack.clear()

func _commit(next: LevelDocument) -> void:
	_remember(document.copy())
	document = next
	_refresh()

func clear_level() -> void:
	_cancel_action()
	selection.clear()
	_commit(LevelDocument.new())
	_set_status("Level cleared. Undo restores it.")

func undo() -> void:
	_cancel_action()
	if undo_stack.is_empty():
		return
	redo_stack.append(document.copy())
	document = undo_stack.pop_back()
	selection.clear()
	_refresh()

func redo() -> void:
	_cancel_action()
	if redo_stack.is_empty():
		return
	undo_stack.append(document.copy())
	document = redo_stack.pop_back()
	selection.clear()
	_refresh()

func _refresh() -> void:
	if terrain == null:
		return
	hovered_handle.clear()
	hovered_object.clear()
	terrain.set_document(document)
	undo_button.disabled = undo_stack.is_empty()
	redo_button.disabled = redo_stack.is_empty()
	counts.text = "  %s/1024 segments [color=#69bfff]|[/color] %s/128 orbs" % [document.segments.size(), document.orbs.size()]
	_update_canvas_cursor()
	queue_redraw()
	gizmos.queue_redraw()

func resume() -> void:
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	ui.visible = true
	background_layer.visible = true
	camera.enabled = true
	camera.make_current()
	queue_redraw()

func suspend() -> void:
	_cancel_action()
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	ui.visible = false
	background_layer.visible = false
	camera.enabled = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _fit_after_layout() -> void:
	# Autowrapped labels briefly report tall minimum sizes before containers
	# assign their widths. Fit only after the toolbar/footer have settled.
	await get_tree().process_frame
	await get_tree().process_frame
	if visible and camera.enabled:
		_frame_grid(true)

func fit_grid() -> void:
	_frame_grid(false)

func _frame_grid(fill_workspace: bool) -> void:
	var size := get_viewport_rect().size
	var top_space := top_panel.size.y + 26.0
	var bottom_space := bottom_panel.size.y + 18.0
	var zoom := clampf(minf((size.x - 96.0) / LevelDocument.BOARD_SIZE, (size.y - top_space - bottom_space) / LevelDocument.BOARD_SIZE), 0.015, 2.5)
	if fill_workspace:
		zoom = clampf(maxf(size.x, size.y - top_panel.size.y - bottom_panel.size.y) * 1.06 / LevelDocument.BOARD_SIZE, 0.015, 2.5)
	camera.zoom = Vector2.ONE * zoom
	camera.position = Vector2.ONE * LevelDocument.BOARD_SIZE * 0.5 - Vector2(0, (top_space - bottom_space) * 0.5 / zoom)
	queue_redraw()
	gizmos.queue_redraw()

func _viewport_changed() -> void:
	queue_redraw()
	if gizmos != null:
		gizmos.queue_redraw()

func screen_to_world(screen: Vector2) -> Vector2:
	return camera.position + (screen - get_viewport_rect().size * 0.5) / camera.zoom.x

func zoom_at(screen: Vector2, factor: float) -> void:
	var before := screen_to_world(screen)
	camera.zoom = Vector2.ONE * clampf(camera.zoom.x * factor, 0.015, 2.5)
	camera.position += before - screen_to_world(screen)
	queue_redraw()
	gizmos.queue_redraw()

func _input(event: InputEvent) -> void:
	# Releases over toolbar controls must still finish a canvas drag.
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not drag.is_empty():
			_finish_drag()
		if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			panning = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and terrain != null:
		_cancel_action()

func _exit_tree() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _update_canvas_cursor() -> void:
	var shape := Input.CURSOR_ARROW
	if not drag.is_empty() or panning:
		shape = Input.CURSOR_DRAG
	elif not hovered_handle.is_empty() or not hovered_object.is_empty():
		shape = Input.CURSOR_POINTING_HAND
	elif tool != Tool.SELECT:
		shape = Input.CURSOR_CROSS
	Input.set_default_cursor_shape(shape)

func _unhandled_input(event: InputEvent) -> void:
	if code_dialog.visible or clear_dialog.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_cancel_action()
		elif event.keycode == KEY_Z and (event.ctrl_pressed or event.meta_pressed):
			if event.shift_pressed:
				redo()
			else:
				undo()
		elif event.keycode == KEY_Y and (event.ctrl_pressed or event.meta_pressed):
			redo()
		elif event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			_delete_selection()
		elif event.keycode == KEY_F:
			fit_grid()
		else:
			return
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			panning = event.pressed
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_at(event.position, 1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2)
			_update_hover(event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_update_hover(event.position)
			if event.pressed:
				_click(screen_to_world(event.position))
			else:
				_finish_drag()
			get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion:
		if panning:
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
				panning = false
			else:
				camera.position -= event.relative / camera.zoom.x
				queue_redraw()
		_update_hover(event.position)
		if not drag.is_empty():
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_finish_drag()
			else:
				_update_drag(screen_to_world(event.position))
		gizmos.queue_redraw()

func _update_hover(screen: Vector2) -> void:
	var world := screen_to_world(screen)
	mouse_on_board = Rect2(Vector2.ZERO, Vector2.ONE * LevelDocument.BOARD_SIZE).has_point(world)
	hover_vertex = document.snap_vertex(world)
	hover_cell = LevelDocument.snap_cell(world)
	hovered_handle.clear()
	hovered_object.clear()
	if mouse_on_board and tool in [Tool.SELECT, Tool.ERASE] and drag.is_empty():
		if tool == Tool.SELECT:
			hovered_handle = _pick_handle(world)
		if hovered_handle.is_empty():
			hovered_object = _pick_object(world)
	_update_canvas_cursor()
	gizmos.queue_redraw()

func _click(world: Vector2) -> void:
	if not mouse_on_board:
		return
	if tool == Tool.SELECT:
		_select_at(world)
		return
	if tool == Tool.ERASE:
		selection = _pick_object(world)
		_delete_selection()
		return
	if tool in [Tool.SPAWN, Tool.ORB]:
		var next := document.copy()
		if tool == Tool.SPAWN:
			next.spawn = hover_cell
		else:
			if next.orbs.has(hover_cell):
				_set_status("There is already an orb in that cell.")
				return
			if next.orbs.size() >= LevelDocument.MAX_ORBS:
				_set_status("Maximum 128 grapple orbs reached.", true)
				return
			next.orbs.append(hover_cell)
		_commit(next)
		_set_status("Spawn placed." if tool == Tool.SPAWN else "Grapple orb placed.")
		return
	if document.segments.size() >= LevelDocument.MAX_SEGMENTS:
		_set_status("Maximum 1,024 terrain segments reached.", true)
		return
	if pending.size() == 1 and hover_vertex == pending[0]:
		_set_status("Choose two different endpoints.", true)
		return
	if pending.size() == 2 and hover_vertex in pending:
		_set_status("Choose a third point different from both endpoints.", true)
		return
	pending.append(hover_vertex)
	var needed := 2 if tool == Tool.LINE else 3
	if pending.size() == needed:
		var segment := _pending_segment(hover_vertex)
		var error := LevelDocument.segment_error(segment)
		if not error.is_empty():
			pending.pop_back()
			_set_status(error, true)
			return
		var next := document.copy()
		next.segments.append(segment)
		pending.clear()
		_commit(next)
		_set_status("Terrain placed. Shared endpoints form continuous terrain.")
	else:
		_set_status("Choose the end point." if pending.size() == 1 else "Choose the point the curve passes through.")

func _pending_segment(point: Vector2i) -> Dictionary:
	var segment := {"kind": LevelDocument.SegmentKind.LINE, "a": pending[0], "b": point if pending.size() == 1 else pending[1]}
	if tool == Tool.CURVE and pending.size() >= 2:
		segment["kind"] = LevelDocument.SegmentKind.CURVE
		segment["m"] = point if pending.size() == 2 else pending[2]
	return segment

func _pick_object(world: Vector2) -> Dictionary:
	var spawn_tolerance := maxf(LevelDocument.PLAYER_RADIUS, 12.0 / camera.zoom.x)
	if LevelDocument.valid_cell(document.spawn) and world.distance_to(LevelDocument.cell_position(document.spawn)) <= spawn_tolerance:
		return {"kind": "spawn"}
	for index in range(document.orbs.size() - 1, -1, -1):
		if world.distance_to(LevelDocument.cell_position(document.orbs[index])) <= maxf(36.0, 12.0 / camera.zoom.x):
			return {"kind": "orb", "index": index}
	var closest := LevelDocument.HALF_WIDTH + 8.0 / camera.zoom.x
	var selected := {}
	for index in range(document.segments.size() - 1, -1, -1):
		var points := LevelDocument.sample_segment(document.segments[index])
		for step in range(points.size() - 1):
			var distance := world.distance_to(Geometry2D.get_closest_point_to_segment(world, points[step], points[step + 1]))
			if distance < closest:
				closest = distance
				selected = {"kind": "segment", "index": index}
	return selected

func _pick_handle(world: Vector2) -> Dictionary:
	var nearest := 12.0 / camera.zoom.x
	var handle := {}
	for index in range(document.segments.size()):
		var segment := document.segments[index]
		var keys := ["a", "b", "m"] if segment["kind"] == LevelDocument.SegmentKind.CURVE else ["a", "b"]
		for key in keys:
			var distance := world.distance_to(LevelDocument.vertex_position(segment[key]))
			if distance < nearest:
				nearest = distance
				handle = {"kind": "middle" if key == "m" else "vertex", "index": index, "old": segment[key]}
	return handle

func _select_at(world: Vector2) -> void:
	var handle := _pick_handle(world)
	if not handle.is_empty():
		selection = {"kind": "segment", "index": handle["index"]}
		drag = handle
	else:
		selection = _pick_object(world)
		if selection.get("kind", "") in ["spawn", "orb"]:
			drag = selection.duplicate()
	if not drag.is_empty():
		drag_original = document.copy()
		drag_valid = true
		last_drag_grid = Vector2i(-999, -999)
	_update_canvas_cursor()
	gizmos.queue_redraw()

func _update_drag(world: Vector2) -> void:
	var grid := drag_original.snap_vertex(world) if drag["kind"] in ["vertex", "middle"] else LevelDocument.snap_cell(world)
	if grid == last_drag_grid:
		return
	last_drag_grid = grid
	var next := drag_original.copy()
	match drag["kind"]:
		"vertex": next.move_vertex(drag["old"], grid)
		"middle": next.segments[drag["index"]]["m"] = grid
		"spawn": next.spawn = grid
		"orb": next.orbs[drag["index"]] = grid
	var error := next.validate()
	if drag["kind"] == "orb" and next.orbs.count(grid) > 1:
		error = "There is already an orb in that cell."
	drag_valid = error.is_empty()
	if not drag_valid:
		_set_status(error, true)
		return
	document = next
	_refresh()

func _finish_drag() -> void:
	if drag.is_empty():
		return
	if not drag_valid:
		document = drag_original
		_set_status("Move cancelled because the resulting geometry was invalid.", true)
	elif LevelCodec.encode_level(document) != LevelCodec.encode_level(drag_original):
		_remember(drag_original)
		_set_status("Moved on the grid. All endpoints sharing the joint move together.")
	drag.clear()
	drag_original = null
	_refresh()

func _cancel_action() -> void:
	if not drag.is_empty():
		document = drag_original
		drag.clear()
		drag_original = null
	pending.clear()
	panning = false
	_refresh()

func _delete_selection() -> void:
	_finish_drag()
	if selection.is_empty():
		return
	var next := document.copy()
	match selection["kind"]:
		"segment": next.segments.remove_at(selection["index"])
		"spawn": next.spawn = Vector2i(-1, -1)
		"orb": next.orbs.remove_at(selection["index"])
	selection.clear()
	_commit(next)
	_set_status("Removed. Undo restores it.")

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2.ONE * LevelDocument.BOARD_SIZE), Color("1b2938"))
	if camera == null:
		return
	var scale_factor := 1.0 / camera.zoom.x
	for index in range(LevelDocument.GRID_SIZE + 1):
		var coordinate := index * LevelDocument.CELL_SIZE
		var major := index % 10 == 0
		var color := Color("455d70") if major else Color("2a3a49")
		draw_line(Vector2(coordinate, 0), Vector2(coordinate, LevelDocument.BOARD_SIZE), color, scale_factor * (1.3 if major else 0.6))
		draw_line(Vector2(0, coordinate), Vector2(LevelDocument.BOARD_SIZE, coordinate), color, scale_factor * (1.3 if major else 0.6))
	draw_rect(Rect2(Vector2.ZERO, Vector2.ONE * LevelDocument.BOARD_SIZE), Color("9db7cb"), false, 2.0 * scale_factor)

func draw_gizmos(canvas: Node2D) -> void:
	var scale_factor := 1.0 / camera.zoom.x
	var accent := Color("71e3d0")
	var hover_color := Color("ff9c95") if tool == Tool.ERASE else Color("d7fff5")
	if hovered_object.get("kind", "") == "segment":
		var points := LevelDocument.sample_segment(document.segments[hovered_object["index"]])
		canvas.draw_polyline(points, Color("09131f"), 7.0 * scale_factor, true)
		canvas.draw_polyline(points, hover_color, 3.0 * scale_factor, true)
	if not selection.is_empty() and selection["kind"] == "segment":
		var points := LevelDocument.sample_segment(document.segments[selection["index"]])
		canvas.draw_polyline(points, Color("09131f"), 7.0 * scale_factor, true)
		canvas.draw_polyline(points, accent, 3.0 * scale_factor, true)
	if tool == Tool.SELECT:
		var drawn := {}
		for segment in document.segments:
			for key in ["a", "b"]:
				var point: Vector2i = segment[key]
				if not drawn.has(point):
					var hovered: bool = hovered_handle.get("kind", "") == "vertex" and hovered_handle["old"] == point
					var position := LevelDocument.vertex_position(point)
					var radius := (9.0 if hovered else 7.0) * scale_factor
					canvas.draw_circle(position, radius, Color("0c1825"))
					canvas.draw_arc(position, radius, 0, TAU, 32, Color.WHITE if hovered else accent, 2.0 * scale_factor, true)
					canvas.draw_circle(position, 2.0 * scale_factor, accent)
					drawn[point] = true
			if segment["kind"] == LevelDocument.SegmentKind.CURVE:
				var middle := LevelDocument.vertex_position(segment["m"])
				var hovered: bool = hovered_handle.get("kind", "") == "middle" and document.segments[hovered_handle["index"]] == segment
				var radius := (11.0 if hovered else 9.0) * scale_factor
				var diamond := PackedVector2Array([middle + Vector2(0, -radius), middle + Vector2(radius, 0), middle + Vector2(0, radius), middle + Vector2(-radius, 0)])
				canvas.draw_colored_polygon(diamond, Color("ffe8ae") if hovered else Color("ffd27e"))
				diamond.append(diamond[0])
				canvas.draw_polyline(diamond, Color("0c1825"), 2.0 * scale_factor, true)
	for index in range(document.orbs.size()):
		var position := LevelDocument.cell_position(document.orbs[index])
		var radius := maxf(36.0, 7.0 * scale_factor)
		canvas.draw_circle(position, radius, Color("6ecfc6"))
		canvas.draw_arc(position, radius, 0, TAU, 32, Color("0c1825"), 2.0 * scale_factor, true)
		var hovered: bool = hovered_object.get("kind", "") == "orb" and hovered_object["index"] == index
		if hovered or (selection.get("kind", "") == "orb" and selection["index"] == index):
			canvas.draw_arc(position, radius + 4.0 * scale_factor, 0, TAU, 32, hover_color if hovered else accent, 2.0 * scale_factor, true)
	if LevelDocument.valid_cell(document.spawn):
		var spawn_position := LevelDocument.cell_position(document.spawn)
		var radius := maxf(LevelDocument.PLAYER_RADIUS, 8.0 * scale_factor)
		var hovered: bool = hovered_object.get("kind", "") == "spawn"
		canvas.draw_circle(spawn_position, radius, Color("183b3c"))
		canvas.draw_arc(spawn_position, radius, 0, TAU, 32, hover_color if hovered else accent, 2.0 * scale_factor, true)
		if hovered or selection.get("kind", "") == "spawn":
			canvas.draw_arc(spawn_position, radius + 4.0 * scale_factor, 0, TAU, 32, hover_color if hovered else accent, 2.0 * scale_factor, true)
		var cross_size := maxf(30.0, 3.5 * scale_factor)
		canvas.draw_line(spawn_position + Vector2(-cross_size, 0), spawn_position + Vector2(cross_size, 0), accent, 1.5 * scale_factor)
		canvas.draw_line(spawn_position + Vector2(0, -cross_size), spawn_position + Vector2(0, cross_size), accent, 1.5 * scale_factor)
	if not pending.is_empty():
		var preview := _pending_segment(hover_vertex)
		var valid := LevelDocument.segment_error(preview).is_empty()
		var points := LevelDocument.sample_segment(preview)
		canvas.draw_polyline(points, Color(0.45, 0.9, 0.8, 0.6) if valid else Color(1.0, 0.4, 0.4, 0.7), LevelDocument.CELL_SIZE, true)
		for point in pending:
			canvas.draw_circle(LevelDocument.vertex_position(point), 6.0 * scale_factor, accent)
	if mouse_on_board:
		if tool in [Tool.SPAWN, Tool.ORB]:
			canvas.draw_rect(Rect2(Vector2(hover_cell) * LevelDocument.CELL_SIZE, Vector2.ONE * LevelDocument.CELL_SIZE), Color(0.45, 0.9, 0.8, 0.25))
		elif tool in [Tool.LINE, Tool.CURVE]:
			canvas.draw_circle(LevelDocument.vertex_position(hover_vertex), 5.0 * scale_factor, accent)
