class_name TouchControls
extends Control

## Root of the on-screen control layer. Owns two things the individual widgets cannot know about:
## the safe area, and the spacing between buttons.
##
## Buttons are positioned in code rather than by anchors because the ≥ 9 mm size and ≥ 2 mm gap from
## [code]docs/TECH.md §6[/code] are physical measurements. Anchors would satisfy them on the panel
## they were authored against and quietly break on every other one.

## Distance from the bottom-right safe-area corner to the first button centre, in millimetres.
@export var arc_inset_mm: float = 14.0

## Angular spread of the button arc, degrees, measured up from the bottom edge.
@export var arc_spread_deg: float = 62.0

## Hide the whole layer when the player is on a keyboard or gamepad.
@export var hide_on_non_touch: bool = true

var _safe_insets: Vector4 = Vector4.ZERO
var _buttons: Array[TouchButton] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Collected from the tree rather than exported. Godot cannot serialize a typed node array into
	# a .tscn, and tree order is the arc order anyway, so an inspector list would only be a second
	# place to keep in sync.
	for child: Node in get_children():
		var button := child as TouchButton
		if button != null:
			_buttons.append(button)

	InputRouter.device_changed.connect(_on_device_changed)
	get_viewport().size_changed.connect(_relayout)
	_on_device_changed(InputRouter.device())
	_relayout()


## Recompute safe-area insets and button placement. Called on rotation and window resize.
func _relayout() -> void:
	_apply_safe_area()
	_layout_buttons()


func _apply_safe_area() -> void:
	var window := DisplayServer.window_get_size()
	if window.x <= 0 or window.y <= 0:
		return

	var safe := InputRouter.safe_area()
	# The safe area is reported in screen pixels, but with stretch mode "viewport" the GUI lives in
	# 1920x1080 logical space. Converting is not optional -- on a 2400-wide panel the two differ by
	# 25 %, and the notch inset would land in the wrong place.
	var viewport_size := get_viewport_rect().size
	var scale := Vector2(viewport_size.x / float(window.x), viewport_size.y / float(window.y))

	_safe_insets = Vector4(
		float(safe.position.x) * scale.x,
		float(safe.position.y) * scale.y,
		float(window.x - (safe.position.x + safe.size.x)) * scale.x,
		float(window.y - (safe.position.y + safe.size.y)) * scale.y
	)

	offset_left = _safe_insets.x
	offset_top = _safe_insets.y
	offset_right = -_safe_insets.z
	offset_bottom = -_safe_insets.w


func _layout_buttons() -> void:
	if _buttons.is_empty():
		return

	var px_per_mm := InputRouter.pixels_per_mm()
	var gap := InputRouter.min_touch_gap_px()
	var corner := size - Vector2.ONE * arc_inset_mm * px_per_mm
	var step := deg_to_rad(arc_spread_deg) / float(maxi(_buttons.size() - 1, 1))

	var reach := 0.0
	for index: int in _buttons.size():
		var button := _buttons[index]
		var radius := button.size.x * 0.5
		# Walk outward by each button's own diameter plus the minimum gap, so mixed sizes still
		# cannot end up closer than the physical minimum.
		if index > 0:
			reach += radius + gap
		var angle := PI + step * float(index)
		button.position = corner + Vector2(cos(angle), sin(angle)) * reach - Vector2.ONE * radius
		reach += radius


func _on_device_changed(device: InputRouter.Device) -> void:
	visible = not hide_on_non_touch or device == InputRouter.Device.TOUCH
