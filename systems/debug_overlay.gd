extends Node

## On-device performance HUD: FPS, frame time, draw calls, primitives, video memory, quality tier,
## and the player's live locomotion state.
##
## Toggled with F3 on desktop and a three-finger tap on Android. The gesture is deliberately awkward
## — it must not be reachable during normal two-thumb play.
##
## This is a debug tool, not a settings feature: in a release build it never builds its UI and never
## processes.

## How often the readout refreshes, seconds. Text is only formatted on these ticks; running it every
## frame would make the overlay itself a measurable cost, which rather defeats the point.
const REFRESH_INTERVAL: float = 0.2

## Fingers that must be down simultaneously to toggle.
const TOGGLE_TOUCH_COUNT: int = 3

## Draw-call budget from [code]CLAUDE.md §3[/code]. Over budget renders in the warning colour.
const BUDGET_DRAW_CALLS: int = 130

## Triangle budget from [code]CLAUDE.md §3[/code].
const BUDGET_PRIMITIVES: int = 250_000

## Texture VRAM budget, bytes.
const BUDGET_TEXTURE_BYTES: float = 60.0 * 1024.0 * 1024.0

## Divisor for byte-to-megabyte display.
const BYTES_PER_MB: float = 1048576.0

var _layer: CanvasLayer
var _label: Label
var _elapsed: float = 0.0
var _active_touches: Dictionary[int, bool] = {}
var _player: Player


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.is_debug_build():
		set_process(false)
		set_process_input(false)
		return
	_build_ui()
	set_process(false)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_overlay"):
		toggle()
		return

	var touch := event as InputEventScreenTouch
	if touch == null:
		return
	if touch.pressed:
		_active_touches[touch.index] = true
		if _active_touches.size() >= TOGGLE_TOUCH_COUNT:
			_active_touches.clear()
			toggle()
	else:
		_active_touches.erase(touch.index)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < REFRESH_INTERVAL:
		return
	_elapsed = 0.0
	_label.text = _compose()


## Show or hide the overlay.
func toggle() -> void:
	if _layer == null:
		return
	set_visible(not _layer.visible)


## Set overlay visibility directly.
func set_visible(value: bool) -> void:
	if _layer == null:
		return
	_layer.visible = value
	set_process(value)
	if value:
		_elapsed = REFRESH_INTERVAL
		_process(0.0)


func _compose() -> String:
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var primitives := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var texture_bytes := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	var video_bytes := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	# Each line is built into a local before appending. Inlining the format calls sends gdformat
	# into a nested-parenthesis spiral that is technically valid and completely unreadable.
	var timing := (
		"FPS %d   frame %.2f ms   (proc %.2f / phys %.2f)"
		% [Engine.get_frames_per_second(), process_ms + physics_ms, process_ms, physics_ms]
	)
	var budgets := (
		"draw %s   tris %s   tex %.1f MB   vram %.1f MB"
		% [
			_budget(draw_calls, BUDGET_DRAW_CALLS),
			_budget(primitives, BUDGET_PRIMITIVES),
			texture_bytes / BYTES_PER_MB,
			video_bytes / BYTES_PER_MB,
		]
	)
	var quality := (
		"tier %s   scale %.2f   max_fps %d"
		% [QualityManager.tier_name(), get_viewport().scaling_3d_scale, Engine.max_fps]
	)

	var lines := PackedStringArray([timing, budgets, quality])

	_player = _resolve_player()
	if _player == null:
		return "\n".join(lines)

	var machine := _player.state_machine
	var fighter := _player.combatant
	var motion := (
		"state %s   vel (%.2f, %.2f)   floor %s   hp %.0f/%.0f   sta %.0f   poise %.0f"
		% [
			machine.current_state_name() if machine != null else &"-",
			_player.velocity.x,
			_player.velocity.y,
			_flag(_player.is_on_floor()),
			_player.health(),
			_player.max_health(),
			fighter.stamina if fighter != null else 0.0,
			fighter.poise if fighter != null else 0.0,
		]
	)
	var forgiveness := (
		"coyote %s   buffer %s   facing %+d   fell %.2f m"
		% [
			_flag(_player.has_coyote()),
			_flag(_player.has_buffered_jump()),
			_player.facing,
			_player.fall_distance,
		]
	)
	lines.append(motion)
	lines.append(forgiveness)
	return "\n".join(lines)


func _flag(value: bool) -> String:
	return "Y" if value else "n"


func _budget(value: int, limit: int) -> String:
	return "%d/%d%s" % [value, limit, "!" if value > limit else ""]


func _resolve_player() -> Player:
	if is_instance_valid(_player):
		return _player
	return get_tree().get_first_node_in_group(&"player") as Player


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 128
	_layer.visible = false
	add_child(_layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(24.0, 24.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.modulate = Color(1.0, 1.0, 1.0, 0.85)
	_layer.add_child(panel)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 18)
	margin.add_child(_label)
