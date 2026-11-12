extends ConfirmationDialog

signal authenticated

const DialogStyle := preload("res://scripts/ui/menu_dialog_style.gd")
var account_session: Node
var light := false
var choices: VBoxContainer
var form: VBoxContainer
var message: Label
var username_input: LineEdit
var password_input: LineEdit
var confirm_password: LineEdit
var confirm_label: Label
var switch_button: Button
var sign_in_button: Button
var create_button: Button
var creating := false
var submitting := false
var choice_reason := ""
var _fit_pending := false

func _ready() -> void:
	account_session = get_node("/root/AccountSession")
	DialogStyle.apply(self, light)
	title = "Account"
	exclusive = true
	cancel_button_text = "Cancel"
	dialog_hide_on_ok = false
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 420
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	message = _label("")
	column.add_child(message)
	choices = VBoxContainer.new()
	choices.add_theme_constant_override("separation", 12)
	column.add_child(choices)
	sign_in_button = _button("Sign in", func() -> void: _show_form(false))
	create_button = _button("Create account", func() -> void: _show_form(true))
	choices.add_child(sign_in_button)
	choices.add_child(create_button)
	form = VBoxContainer.new()
	form.add_theme_constant_override("separation", 10)
	column.add_child(form)
	form.add_child(_label("Username"))
	username_input = LineEdit.new()
	username_input.max_length = 24
	username_input.placeholder_text = "3–24 letters, numbers, or underscores"
	form.add_child(username_input)
	form.add_child(_label("Password"))
	password_input = LineEdit.new()
	password_input.secret = true
	password_input.max_length = 32
	password_input.placeholder_text = "4–32 characters"
	password_input.text_submitted.connect(func(_text: String) -> void: _submit())
	form.add_child(password_input)
	confirm_label = _label("Confirm password")
	form.add_child(confirm_label)
	confirm_password = LineEdit.new()
	confirm_password.secret = true
	confirm_password.max_length = 32
	confirm_password.text_submitted.connect(func(_text: String) -> void: _submit())
	form.add_child(confirm_password)
	switch_button = add_button("Create account", false, "switch_mode")
	DialogStyle.ButtonPulse.install(switch_button, false, light)
	custom_action.connect(func(action: StringName) -> void:
		if action == &"switch_mode":
			_show_form(not creating)
	)
	# Keep both forms' footer in primary action / alternate action / Cancel order.
	var footer := get_ok_button().get_parent()
	footer.move_child(get_ok_button(), 0)
	footer.move_child(switch_button, 1)
	footer.move_child(get_cancel_button(), 2)
	confirmed.connect(_submit)
	canceled.connect(_cancel)
	account_session.completed.connect(_completed)

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	DialogStyle.ButtonPulse.install(button, false, light)
	return button

func prompt(reason: String = "Sign in or create an account.") -> void:
	title = "Account"
	choice_reason = reason
	message.text = reason
	choices.show()
	form.hide()
	get_ok_button().hide()
	switch_button.hide()
	_set_busy(false)
	popup_centered(Vector2i(460, 0))
	_fit.call_deferred()
	sign_in_button.grab_focus.call_deferred()

func _show_form(create: bool) -> void:
	creating = create
	title = "Create account" if create else "Sign in"
	choices.hide()
	form.show()
	get_ok_button().show()
	switch_button.show()
	ok_button_text = "Create account" if create else "Sign in"
	confirm_label.visible = create
	confirm_password.visible = create
	password_input.clear()
	confirm_password.clear()
	switch_button.text = "Sign in" if create else "Create account"
	message.text = "Choose a username and a password with 4–32 characters." if create else "Sign in with your username and password."
	_fit.call_deferred()
	username_input.grab_focus.call_deferred()

func _set_busy(value: bool) -> void:
	submitting = value
	get_ok_button().disabled = value
	username_input.editable = not value
	password_input.editable = not value
	confirm_password.editable = not value
	switch_button.disabled = value
	sign_in_button.disabled = value
	create_button.disabled = value

func _submit() -> void:
	if submitting or not form.visible:
		return
	var valid_username := RegEx.new()
	valid_username.compile("^[A-Za-z0-9_]{3,24}$")
	if valid_username.search(username_input.text.strip_edges()) == null:
		message.text = "Use 3–24 letters, numbers, or underscores for your username."
	elif password_input.text.length() < 4 or password_input.text.length() > 32:
		message.text = "Use a password with 4–32 characters."
	elif creating and password_input.text != confirm_password.text:
		message.text = "The passwords do not match."
	else:
		_set_busy(true)
		message.text = "Creating account..." if creating else "Signing in..."
		if creating:
			account_session.create_account(username_input.text, password_input.text)
		else:
			account_session.sign_in(username_input.text, password_input.text)
	_fit.call_deferred()

func _completed(action: String, error: String) -> void:
	if not submitting or action not in ["login", "register"]:
		return
	_set_busy(false)
	password_input.clear()
	confirm_password.clear()
	if not error.is_empty():
		message.text = error
		_fit.call_deferred()
		return
	hide()
	authenticated.emit()

func _cancel() -> void:
	if submitting:
		account_session.cancel_authentication()
	_set_busy(false)
	password_input.clear()
	confirm_password.clear()

func dismiss() -> void:
	_cancel()
	hide()

func _fit() -> void:
	if _fit_pending:
		return
	_fit_pending = true
	get_tree().process_frame.connect(_fit_next_frame, CONNECT_ONE_SHOT)

func _fit_next_frame() -> void:
	get_tree().process_frame.connect(_finish_fit, CONNECT_ONE_SHOT)

func _finish_fit() -> void:
	_fit_pending = false
	if visible:
		reset_size()
		move_to_center()
