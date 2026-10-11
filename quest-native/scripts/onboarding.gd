extends Node

# This file records UI choices only. Passwords, identity credentials and session
# tickets never enter it. Skipping is a supported way to enjoy offline play.
const PREFERENCE_PATH := "user://primal_monke_onboarding.cfg"
var game: Node3D
var completed := false
var registered := false
var _prompting := false
var _returning_prompt := false

func _preference_path() -> String:
	return PREFERENCE_PATH

func _ready() -> void:
	var preferences := ConfigFile.new()
	if preferences.load(_preference_path()) == OK:
		completed = bool(preferences.get_value("welcome", "completed", false))
		registered = bool(preferences.get_value("welcome", "registered", false))
	if is_instance_valid(game):
		var account: Node = game.get("account") as Node
		if account != null and account.has_signal("state_changed"):
			account.state_changed.connect(_on_account_state_changed)

func should_skip_auto_device_login() -> bool:
	# Account creation is explicit: returning guests keep their offline profile,
	# and registered players sign in with credentials. Device account remains
	# available as an intentional choice in Account, never a startup side effect.
	return true

func _can_present() -> bool:
	return DisplayServer.get_name() != "headless"

func begin_if_needed() -> void:
	if _prompting or _returning_prompt or not is_instance_valid(game) or not _can_present(): return
	var account: Node = game.get("account") as Node
	if account != null and bool(account.get("has_credentials")) and account.has_method("is_signed_in") and account.call("is_signed_in"):
		_finish(true)
		return
	var menu: Node = game.get("account_menu") as Node
	if menu == null or not menu.has_method("set_first_time") or not game.has_method("open_account_menu"): return
	if completed:
		if registered:
			_returning_prompt = true
			menu.call("set_first_time", false)
			game.call("open_account_menu")
			if menu.has_method("select_mode"): menu.call("select_mode", "login")
		return
	_prompting = true
	menu.call("set_first_time", true)
	game.call("open_account_menu")

func continue_as_guest(show_tutorial: bool = true) -> void:
	if _returning_prompt:
		_returning_prompt = false
		# Keep the registered preference so the next launch still offers sign-in.
		return
	if not _prompting: return
	_finish(false)
	# The tutorial is optional, remains replayable in the menu and never starts
	# device registration in the background when the player chooses guest play.
	if show_tutorial and game.has_method("open_tutorial_menu"):
		game.call_deferred("open_tutorial_menu")

func _on_account_state_changed() -> void:
	if not is_instance_valid(game): return
	var account: Node = game.get("account") as Node
	if account != null and not bool(account.get("busy")) and bool(account.get("has_credentials")) and account.has_method("is_signed_in") and account.call("is_signed_in"):
		var first_completion := _prompting
		if completed and registered and not _returning_prompt: return
		_finish(true)
		# Let the successful registration status remain visible. Its Close action
		# returns to the main menu, where the tutorial is available to replay.
		if first_completion: game.set("frontend_status", "Account ready. Try the tutorial before your first match.")

func _finish(used_registration: bool) -> void:
	completed = true
	registered = used_registration
	_prompting = false
	_returning_prompt = false
	var preferences := ConfigFile.new()
	preferences.load(_preference_path())
	preferences.set_value("welcome", "completed", completed)
	preferences.set_value("welcome", "registered", registered)
	preferences.save(_preference_path())
	if is_instance_valid(game):
		var menu: Node = game.get("account_menu") as Node
		if menu != null and menu.has_method("set_first_time"):
			menu.call("set_first_time", false)
