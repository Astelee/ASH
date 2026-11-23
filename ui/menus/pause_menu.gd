class_name PauseMenu
extends Control

## Pause, settings, and quit. Also the Android predictive-back target.
##
## `NOTIFICATION_WM_GO_BACK_REQUEST` opens this rather than killing the activity — Android 13+
## predictive back would otherwise close the game mid-fight, which loses the run.
##
## Pausing also triggers an autosave. Android can kill a backgrounded process without warning, and
## the moment the player opens a menu is the cheapest possible time to write.

## Emitted when the menu is dismissed.
signal resumed

## Emitted when the player asks to return to the main menu.
signal quit_to_menu

var _root: VBoxContainer
var _open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"menu"):
		toggle()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# Predictive back opens the menu. Never let it close the activity.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _open:
			close()
		else:
			open()


## Show the menu and pause the tree.
func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	get_tree().paused = true
	SaveSystem.autosave("paused")


## Hide the menu and resume.
func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	get_tree().paused = false
	resumed.emit()


## Flip between open and closed.
func toggle() -> void:
	if _open:
		close()
	else:
		open()


## True while the menu is showing.
func is_open() -> bool:
	return _open


func _build() -> void:
	var backing := ColorRect.new()
	backing.color = Color(0.03, 0.03, 0.05, 0.85)
	backing.set_anchors_preset(Control.PRESET_FULL_RECT)
	backing.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backing)

	_root = VBoxContainer.new()
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_theme_constant_override("separation", 18)
	add_child(_root)

	_add_button("UI_RESUME", close)
	_add_button("UI_SETTINGS", _open_settings)
	_add_button("UI_QUIT", func() -> void: quit_to_menu.emit())


func _add_button(key: String, action: Callable) -> void:
	var button := Button.new()
	button.text = tr(key)
	# Menu buttons obey the same 9 mm minimum as the combat layer. A pause menu you cannot hit is
	# still a pause menu you cannot hit.
	button.custom_minimum_size = Vector2(360.0, InputRouter.min_touch_target_px())
	button.pressed.connect(action)
	_root.add_child(button)


func _open_settings() -> void:
	var settings := get_tree().get_first_node_in_group(&"settings_menu") as Control
	if settings != null and settings.has_method(&"open"):
		settings.call(&"open")
	else:
		Log.warn("PauseMenu", "no settings menu in the scene")
