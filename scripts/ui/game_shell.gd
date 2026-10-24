extends Node
## Keeps the draft alive while replacing demo/playtest worlds with fresh instances.

const DemoScene := preload("res://base_level.tscn")
const EditorScene := preload("res://scenes/level_editor.tscn")
const CustomScene := preload("res://scenes/custom_level.tscn")

var world: Node
var editor: GridLevelEditor
var navigation: PanelContainer
var editor_button: Button
var restart_button: Button
var mode_label: Label

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	navigation = PanelContainer.new()
	navigation.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	navigation.offset_left = -432
	navigation.offset_top = 12
	navigation.offset_right = -12
	navigation.offset_bottom = 76
	root.add_child(navigation)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	navigation.add_child(row)
	mode_label = Label.new()
	row.add_child(mode_label)
	restart_button = Button.new()
	restart_button.text = "Restart"
	restart_button.focus_mode = Control.FOCUS_NONE
	restart_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	restart_button.pressed.connect(func() -> void:
		if world is CustomLevel:
			world.restart()
	)
	row.add_child(restart_button)
	editor_button = Button.new()
	editor_button.focus_mode = Control.FOCUS_NONE
	editor_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	editor_button.theme_type_variation = &"PrimaryButton"
	editor_button.pressed.connect(show_editor)
	row.add_child(editor_button)
	show_demo()

func _dispose_world() -> void:
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	world = null

func show_demo() -> void:
	if is_instance_valid(editor):
		editor.suspend()
	_dispose_world()
	world = DemoScene.instantiate()
	add_child(world)
	navigation.visible = true
	mode_label.text = ""
	restart_button.visible = false
	editor_button.text = "Level Editor"

func show_editor() -> void:
	_dispose_world()
	navigation.visible = false
	if not is_instance_valid(editor):
		editor = EditorScene.instantiate()
		editor.exit_requested.connect(show_demo)
		editor.playtest_requested.connect(playtest)
		add_child(editor)
	else:
		editor.resume()

func playtest(document: LevelDocument) -> void:
	var custom: CustomLevel = CustomScene.instantiate()
	var error := custom.prepare(document)
	if not error.is_empty():
		custom.free()
		editor._set_status(error, true)
		return
	editor.suspend()
	_dispose_world()
	world = custom
	add_child(world)
	navigation.visible = true
	mode_label.text = "Playtesting  "
	restart_button.visible = true
	editor_button.text = "Back to editor"
