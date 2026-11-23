class_name DynamicJoystick
extends Control

## Dynamic virtual joystick. The origin spawns wherever the thumb lands inside its region, rather
## than sitting at a fixed spot — on a phone a fixed stick drifts out from under the thumb within a
## minute, and the player spends the fight looking at their hand instead of the screen.
##
## Raw [InputEventScreenTouch] is handled directly, tracking the finger by index, because Godot's
## touch-to-mouse emulation collapses multi-touch and would make steering while attacking
## impossible.

## Not tracking a finger.
const NO_TOUCH: int = -1

## Fraction of screen width, from the left, in which a touch grabs the stick.
@export_range(0.1, 1.0, 0.01) var region_width: float = 0.40

## Stick radius in millimetres. The spec quotes 140 px, which is ~8.9 mm on the 400 dpi target
## panel; expressing it physically keeps the stick thumb-sized across DPIs instead of shrinking on
## dense screens.
@export var radius_mm: float = 8.9

## Deflection below this fraction of the radius reads as zero. Absorbs thumb tremor.
@export_range(0.0, 0.9, 0.01) var dead_zone: float = 0.12

## Deflection at or beyond this fraction of the radius reads as full tilt.
@export_range(0.1, 1.0, 0.01) var full_deflection: float = 0.45

@export_group("Appearance")

## Ring drawn at the touch origin.
@export var base_color: Color = Color(1.0, 1.0, 1.0, 0.18)

## Filled knob drawn at the current deflection.
@export var knob_color: Color = Color(1.0, 1.0, 1.0, 0.35)

var _touch_index: int = NO_TOUCH
var _origin: Vector2 = Vector2.ZERO
var _current: Vector2 = Vector2.ZERO
var _radius_px: float = 140.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radius_px = radius_mm * InputRouter.pixels_per_mm()


func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch != null:
		_handle_touch(touch)
		return

	var drag := event as InputEventScreenDrag
	if drag != null and drag.index == _touch_index:
		_current = drag.position
		_publish()
		queue_redraw()


func _draw() -> void:
	if _touch_index == NO_TOUCH:
		return
	var origin := _origin - global_position
	draw_arc(origin, _radius_px * full_deflection, 0.0, TAU, 48, base_color, 2.0, true)
	draw_circle(origin, _radius_px * dead_zone, base_color)
	draw_circle(_knob_position() - global_position, _radius_px * 0.22, knob_color)


## Current horizontal output, −1 to +1. Also pushed to [code]InputRouter[/code] every frame the
## stick is engaged.
func axis() -> float:
	if _touch_index == NO_TOUCH:
		return 0.0
	var offset := _current - _origin
	var distance := offset.length()
	if distance <= 0.0:
		return 0.0
	var span := maxf(full_deflection - dead_zone, 0.001)
	var scaled := clampf((distance / _radius_px - dead_zone) / span, 0.0, 1.0)
	return offset.normalized().x * scaled


func _handle_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		if _touch_index != NO_TOUCH or not _in_region(touch.position):
			return
		_touch_index = touch.index
		_origin = touch.position
		_current = touch.position
	elif touch.index == _touch_index:
		_touch_index = NO_TOUCH
	else:
		return

	_publish()
	queue_redraw()


func _in_region(position: Vector2) -> bool:
	return position.x <= get_viewport_rect().size.x * region_width


func _knob_position() -> Vector2:
	var offset := _current - _origin
	var limit := _radius_px * full_deflection
	return _origin + (offset.limit_length(limit) if offset.length() > limit else offset)


func _publish() -> void:
	InputRouter.set_touch_move_axis(axis())
