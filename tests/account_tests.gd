extends SceneTree

const LibraryClient := preload("res://scripts/levels/level_library_client.gd")
var account_session: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	account_session = root.get_node("AccountSession")
	ProjectSettings.set_setting("network/level_library_url", "http://localhost:9080/levels")
	check(LibraryClient.base_url() == "http://127.0.0.1:9080/levels", "Local account requests use Wrangler's IPv4 loopback address")
	check(LibraryClient.local_url("https://localhost:9443/levels") == "https://localhost:9443/levels", "HTTPS hostnames retain their certificate identity")
	check(LibraryClient.local_url("http://localhost.example/levels") == "http://localhost.example/levels", "Nonlocal hostnames are not rewritten")
	var error := LibraryClient.connection_error(HTTPRequest.RESULT_CANT_CONNECT, "http://127.0.0.1:9080/auth/register", "Account service")
	check(error.contains("could not connect") and error.contains("127.0.0.1:9080/auth/register"), "Connection errors identify the failing account URL and reason")
	var private_error := LibraryClient.connection_error(HTTPRequest.RESULT_TIMEOUT, "https://name:secret@example.com/auth/login?token=private", "Account service")
	check(not private_error.contains("secret") and not private_error.contains("private"), "Connection diagnostics never expose URL credentials or query values")
	ProjectSettings.set_setting("network/level_library_url", "https://accounts.example/levels")
	account_session.invalidate()
	var shell = load("res://scenes/game_shell.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	await process_frame
	shell.show_settings()
	check(shell.account_sign_in.visible and not shell.account_sign_out.visible, "Settings offers sign in when signed out")
	shell.account_sign_in.pressed.emit()
	var dialog = shell.account_dialog
	check(dialog.visible and not shell.settings_dialog.visible, "Settings opens account choices")
	check(dialog.sign_in_button.visible and dialog.create_button.visible, "Account prompt offers sign in and creation")
	dialog._show_form(true)
	for frame in range(4):
		await process_frame
	check(dialog.password_input.secret and dialog.confirm_password.secret, "Password inputs are masked")
	check(dialog.size.y < root.get_visible_rect().size.y, "Registration form fits on screen")
	dialog.username_input.text = "ValidUser"
	dialog.password_input.text = "abc"
	dialog._submit()
	check(dialog.message.text.contains("4–32"), "Creation explains password length")
	dialog.password_input.text = "A long test password."
	dialog.confirm_password.text = "A different password."
	dialog._submit()
	check(dialog.message.text.contains("match"), "Creation checks password confirmation")
	dialog.switch_button.pressed.emit()
	check(dialog.password_input.text.is_empty() and not dialog.confirm_password.visible, "Switching to sign in clears passwords and hides confirmation")
	dialog.password_input.text = "A long test password."
	dialog.dismiss()
	shell._return_account_settings()
	check(shell.settings_dialog.visible and dialog.password_input.text.is_empty(), "Cancel clears the password and returns to Settings")
	account_session._apply_session({"user": {"id": "test-user", "username": "ValidUser"}, "token": "b".repeat(64), "expires_at": (Time.get_unix_time_from_system() + 3600) * 1000})
	check(shell.account_sign_out.visible and not shell.account_sign_in.visible and shell.account_status.text.contains("ValidUser"), "Settings reflects signed-in account")
	check(account_session.authorization_header().begins_with("Authorization: Bearer "), "Signed-in upload has authorization")
	ProjectSettings.set_setting("network/level_library_url", "https://different.example/levels")
	check(account_session.authorization_header().is_empty(), "Session token is never sent to a different library URL")
	ProjectSettings.set_setting("network/level_library_url", "https://accounts.example/levels")
	account_session._expires_at = 0
	check(not account_session.is_signed_in(), "Expired client sessions cannot upload")
	account_session.invalidate()
	check(shell.account_sign_in.visible and not shell.account_sign_out.visible, "Clearing the session restores Settings sign-in")
	for url in ["http://localhost:9080/levels", "http://127.0.0.1:9080/levels", "https://rooms.example/levels"]:
		check(account_session.secure_endpoint(url), "Allow HTTPS or local account transport")
	for url in ["http://rooms.example/levels", "http://localhost:80@attacker.example/levels", "http://localhost.attacker.example/levels"]:
		check(not account_session.secure_endpoint(url), "Reject unsafe account transport")
	shell.show_main_menu()
	shell.show_demo()
	shell.pause_game()
	shell.show_settings()
	shell.account_sign_in.pressed.emit()
	dialog.dismiss()
	shell._return_account_settings()
	check(paused and shell.settings_dialog.visible, "Account navigation preserves paused gameplay")
	shell.free()
	await process_frame
	print("ACCOUNTS: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
