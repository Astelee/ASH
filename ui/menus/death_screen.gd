class_name DeathScreen
extends Control

## YOU DIED, and the walk back.
##
## Listens on [code]EventBus.player_died[/code] rather than being called, so it works in any level
## with no wiring. It deliberately does **not** pause the tree: the bloodstain is dropped and the
## autosave written by [code]GameState[/code] before this ever appears, and pausing mid-write is how
## a save gets truncated.

## Emitted when the player accepts and respawns.
signal respawn_requested(wayshrine_id: String)

## Seconds the text fades in over. Long enough to land, short enough not to be a loading screen.
@export var fade_duration: float = 1.6

## Seconds before the respawn prompt appears. The pause is the point.
@export var prompt_delay: float = 2.2

var _label: Label
var _button: Button
var _elapsed: float = 0.0
var _showing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()
	EventBus.player_died.connect(_on_player_died)


func _process(delta: float) -> void:
	if not _showing:
		return
	_elapsed += delta
	_label.modulate.a = clampf(_elapsed / fade_duration, 0.0, 1.0)
	if _elapsed >= prompt_delay and not _button.visible:
		_button.visible = true


## Show the screen. Called from the bus; exposed for tests.
func show_death() -> void:
	_showing = true
	_elapsed = 0.0
	visible = true
	_label.modulate.a = 0.0
	_button.visible = false


## Dismiss and respawn at the last rested Wayshrine.
func respawn() -> void:
	_showing = false
	visible = false
	respawn_requested.emit(GameState.wayshrine)


## True while the screen is up.
func is_showing() -> bool:
	return _showing


func _build() -> void:
	var backing := ColorRect.new()
	backing.color = Color(0.0, 0.0, 0.0, 0.82)
	backing.set_anchors_preset(Control.PRESET_FULL_RECT)
	backing.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backing)

	_label = Label.new()
	_label.text = tr("UI_YOU_DIED")
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_label.add_theme_font_size_override("font_size", 96)
	_label.add_theme_color_override("font_color", Color(0.72, 0.13, 0.11))
	add_child(_label)

	_button = Button.new()
	_button.text = tr("UI_RESPAWN")
	_button.custom_minimum_size = Vector2(420.0, InputRouter.min_touch_target_px())
	_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_button.position.y -= 180.0
	_button.visible = false
	_button.pressed.connect(respawn)
	add_child(_button)


func _on_player_died(_at: Vector3) -> void:
	show_death()
