class_name TouchButton
extends Control

## A round on-screen action button. Feeds [code]InputRouter[/code], which turns the press into a
## real engine action — so gameplay code never learns that touch exists.
##
## Sizes itself to at least the 9 mm physical minimum from [code]docs/TECH.md §6[/code]. Anything
## smaller gets missed under pressure, and combat is exactly when the player stops aiming carefully.
##
## Tracks its finger by index rather than using [method Control._gui_input], so it works while the
## other thumb is on the joystick.

## Not tracking a finger.
const NO_TOUCH: int = -1

## Action emitted on press and release. Must exist in the input map.
@export var action: StringName = &""

## Label drawn in the centre. Placeholder until Phase 7 supplies real iconography.
@export var glyph: String = ""

## Size as a multiple of the 9 mm minimum. The primary attack button is deliberately larger.
@export_range(1.0, 3.0, 0.05) var size_scale: float = 1.0

@export_group("Appearance")

@export var idle_color: Color = Color(1.0, 1.0, 1.0, 0.16)
@export var pressed_color: Color = Color(1.0, 0.85, 0.55, 0.42)
@export var glyph_color: Color = Color(1.0, 1.0, 1.0, 0.75)

var _touch_index: int = NO_TOUCH
var _radius: float = 64.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radius = InputRouter.min_touch_target_px() * 0.5 * size_scale
	custom_minimum_size = Vector2.ONE * _radius * 2.0
	size = custom_minimum_size
	pivot_offset = custom_minimum_size * 0.5

	if action == &"" or not InputMap.has_action(action):
		Log.error("TouchButton", "%s has no valid action ('%s')" % [name, action])


func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null:
		return

	if touch.pressed:
		if _touch_index == NO_TOUCH and _contains(touch.position):
			_touch_index = touch.index
			_set_action(true)
			queue_redraw()
	elif touch.index == _touch_index:
		_touch_index = NO_TOUCH
		_set_action(false)
		queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	draw_circle(centre, _radius, pressed_color if is_pressed() else idle_color)
	draw_arc(centre, _radius, 0.0, TAU, 40, glyph_color, 1.5, true)

	if glyph.is_empty():
		return
	var font := get_theme_default_font()
	var font_size := int(_radius * 0.7)
	var extent := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_CENTER, -1.0, font_size)
	draw_string(
		font,
		centre + Vector2(-extent.x * 0.5, extent.y * 0.32),
		glyph,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1.0,
		font_size,
		glyph_color
	)


## True while a finger is down on this button.
func is_pressed() -> bool:
	return _touch_index != NO_TOUCH


func _contains(point: Vector2) -> bool:
	return point.distance_to(global_position + size * 0.5) <= _radius


func _set_action(pressed: bool) -> void:
	if action != &"":
		InputRouter.set_touch_action(action, pressed)
