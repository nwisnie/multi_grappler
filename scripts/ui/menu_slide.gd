extends Node
## Shared, interruptible menu motion. Layout and parallax live on parent controls.

const ENTER_DURATION := 0.32
const EXIT_DURATION := 0.26
static var duration_scale := 1.0

var _target: Node
var _tween: Tween
var _rest := Vector2.ZERO
var _closing := false
var _after_close := Callable()

static func _effect(target: Node):
	var effect = target.get_node_or_null("MenuSlide")
	if effect == null:
		effect = load("res://scripts/ui/menu_slide.gd").new()
		effect.name = "MenuSlide"
		effect._target = target
		target.add_child(effect)
	return effect

static func enter(control: Control) -> void:
	_effect(control)._enter(Vector2.ZERO)

static func dismiss(target: Node, after: Callable = Callable()) -> void:
	_effect(target)._leave(after)

static func hide_now(target: Node) -> void:
	var effect = target.get_node_or_null("MenuSlide")
	if effect != null:
		effect._stop()
		effect._set_position(effect._rest)
	target.hide()

static func install_popup(dialog: ConfirmationDialog) -> void:
	if dialog.has_node("MenuSlide"):
		return
	var effect = _effect(dialog)
	# AcceptDialog normally hides before emitting canceled. Route dismissal
	# through the animation, then emit canceled with the same hidden state.
	dialog.dialog_close_on_escape = false
	var cancel := dialog.get_cancel_button()
	for connection in cancel.pressed.get_connections():
		cancel.pressed.disconnect(connection.callable)
	cancel.pressed.connect(effect._cancel_popup)
	for connection in dialog.close_requested.get_connections():
		dialog.close_requested.disconnect(connection.callable)
	dialog.close_requested.connect(effect._cancel_popup)
	dialog.window_input.connect(effect._window_input)
	dialog.visibility_changed.connect(effect._popup_visibility_changed)

static func popup(dialog: ConfirmationDialog, minimum_size: Vector2i) -> void:
	var effect = _effect(dialog)
	effect._stop()
	dialog.popup_centered(minimum_size)
	# Start after popup() validates and places the embedded window.
	effect._enter(Vector2(dialog.position))

static func recenter(dialog: Window) -> void:
	var effect = dialog.get_node_or_null("MenuSlide")
	if effect == null or not effect._is_animating():
		dialog.move_to_center()
		return
	if effect._closing:
		return
	var current := dialog.position
	dialog.move_to_center()
	effect._rest = Vector2(dialog.position)
	dialog.position = current
	effect._animate(effect._rest, ENTER_DURATION, Tween.EASE_OUT)

func _is_animating() -> bool:
	return _tween != null and _tween.is_running()

func _stop() -> void:
	if _tween != null:
		_tween.kill()
	_closing = false
	_after_close = Callable()

func _set_position(value: Vector2) -> void:
	if _target is Window:
		_target.position = Vector2i(value.round())
	else:
		_target.position = value

func _above_screen() -> Vector2:
	if _target is Window:
		return Vector2(_rest.x, -float(_target.size.y) - 64.0)
	var control := _target as Control
	return Vector2(_rest.x, _rest.y - control.get_global_rect().end.y - 24.0)

func _animate(destination: Vector2, duration: float, easing: Tween.EaseType) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	# A stronger curve makes exits accelerate and entrances brake into place.
	_tween.tween_method(_set_position, Vector2(_target.position), destination, duration * duration_scale).set_trans(Tween.TRANS_QUART).set_ease(easing)

func _enter(rest: Vector2) -> void:
	_stop()
	_rest = rest
	_target.show()
	_set_position(_rest)
	if duration_scale <= 0.0:
		return
	_set_position(_above_screen())
	_animate(_rest, ENTER_DURATION, Tween.EASE_OUT)

func _leave(after: Callable) -> void:
	if _closing:
		return
	if not _target.visible or duration_scale <= 0.0:
		hide_now(_target)
		if after.is_valid():
			after.call()
		return
	_closing = true
	_after_close = after
	# Compute the exit from the resting layout, even if entrance was interrupted.
	var current := Vector2(_target.position)
	_set_position(_rest)
	var destination := _above_screen()
	_set_position(current)
	_animate(destination, EXIT_DURATION, Tween.EASE_IN)
	_tween.tween_callback(_finish_close)

func _finish_close() -> void:
	var after := _after_close
	_after_close = Callable()
	_closing = false
	_target.hide()
	_set_position(_rest)
	if after.is_valid():
		after.call()

func _popup_visibility_changed() -> void:
	if not _target.visible:
		_stop()

func _cancel_popup() -> void:
	_leave(func() -> void: _target.canceled.emit())

func _window_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_target.set_input_as_handled()
		_cancel_popup()
