extends Node

## Normalizes touch, keyboard, and gamepad into one intent stream.
##
## Gameplay never calls [method Input.is_action_pressed] directly — it asks the router. That is what
## lets the dynamic virtual joystick, the customizable touch layout, hold-vs-toggle block, and
## desktop testing coexist without branching inside the player controller.
##
## Touch buttons feed synthetic [InputEventAction]s through [method Input.parse_input_event], so
## press/just-pressed/just-released semantics come from the engine and behave identically across
## devices. The analog stick is the exception: it is read as a value, because re-parsing an action
## every frame would make [code]just_pressed[/code] fire continuously.

## Emitted when the player switches input method, so the HUD can swap button prompts and show or
## hide the touch layer.
signal device_changed(device: Device)

## Which physical input the player last used.
enum Device { KEYBOARD, GAMEPAD, TOUCH }

## Minimum comfortable touch target, millimetres. Below this, thumbs miss.
const MIN_TOUCH_TARGET_MM: float = 9.0

## Minimum gap between adjacent touch targets, millimetres.
const MIN_TOUCH_GAP_MM: float = 2.0

## Fallback DPI when the platform will not report one (desktop, some emulators).
const FALLBACK_DPI: int = 96

## Hold time separating a roll from a sprint, seconds. Set from [MovementTuning] on ready.
var sprint_hold_threshold: float = 0.18

var _device: Device = Device.KEYBOARD
var _touch_move_axis: float = 0.0
var _dodge_held_for: float = 0.0
var _dodge_was_pressed: bool = false
var _dodge_tap_pending: bool = false


func _ready() -> void:
	process_priority = -100


func _process(delta: float) -> void:
	# Tracked here rather than in the player so that every consumer of "is sprinting" agrees, and so
	# the timer keeps running across a state transition.
	var pressed := Input.is_action_pressed(&"dodge")
	if pressed:
		_dodge_held_for += delta
	elif _dodge_was_pressed:
		# Released. A short hold was a roll; a long one was a sprint that has now ended. Rolling on
		# release rather than on press is what lets one button mean both.
		if _dodge_held_for < sprint_hold_threshold:
			_dodge_tap_pending = true
		_dodge_held_for = 0.0
	_dodge_was_pressed = pressed


func _input(event: InputEvent) -> void:
	var next := _device
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		next = Device.TOUCH
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		next = Device.GAMEPAD
	elif event is InputEventKey or event is InputEventMouseButton:
		next = Device.KEYBOARD

	if next != _device:
		_device = next
		device_changed.emit(_device)


## Horizontal movement intent, −1 (left) to +1 (right). Hardware input wins when present so that a
## controller plugged in mid-session takes over immediately.
func move_axis() -> float:
	var hardware := Input.get_axis(&"move_left", &"move_right")
	return hardware if not is_zero_approx(hardware) else _touch_move_axis


## True while the dodge button has been held past the sprint threshold. A shorter hold is a roll,
## which Phase 2 will claim.
func is_sprinting(threshold: float) -> bool:
	return _dodge_held_for >= threshold


## True once after the dodge button is released inside the tap window, then cleared. A roll fires on
## release so the same button can mean sprint when held.
func consume_dodge_tap() -> bool:
	if not _dodge_tap_pending:
		return false
	_dodge_tap_pending = false
	return true


## Seconds the dodge button has been held, 0 when released.
func dodge_hold_time() -> float:
	return _dodge_held_for


## The input device last used.
func device() -> Device:
	return _device


## True when the player is on touch and the on-screen controls should be visible.
func is_touch_active() -> bool:
	return _device == Device.TOUCH


## Called by [VirtualJoystick] every frame it is engaged, and with 0.0 when released.
func set_touch_move_axis(value: float) -> void:
	_touch_move_axis = clampf(value, -1.0, 1.0)


## Called by touch buttons on press and release. Produces a real engine action event, so
## [method Input.is_action_just_pressed] works for touch exactly as it does for a key.
func set_touch_action(action: StringName, pressed: bool) -> void:
	if not InputMap.has_action(action):
		Log.error("InputRouter", "no such action '%s'" % action)
		return
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


## Usable screen rectangle, excluding the notch and the gesture bar. Android 15+ enforces
## edge-to-edge, so anything pinned to a raw screen edge is either hidden or unreachable.
func safe_area() -> Rect2i:
	var area := DisplayServer.get_display_safe_area()
	if area.size.x > 0 and area.size.y > 0:
		return area
	return Rect2i(Vector2i.ZERO, DisplayServer.window_get_size())


## Screen pixels per physical millimetre, for sizing touch targets in real-world units.
func pixels_per_mm() -> float:
	var dpi := DisplayServer.screen_get_dpi()
	if dpi <= 0:
		dpi = FALLBACK_DPI
	return float(dpi) / 25.4


## Minimum touch target edge length in pixels — 142 px on a 400 dpi panel.
func min_touch_target_px() -> float:
	return MIN_TOUCH_TARGET_MM * pixels_per_mm()


## Minimum spacing between touch targets, pixels.
func min_touch_gap_px() -> float:
	return MIN_TOUCH_GAP_MM * pixels_per_mm()
