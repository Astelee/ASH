class_name PlayerHud
extends Control

## Health, stamina, Embers, and flask charges.
##
## Drawn rather than assembled from Control nodes: four bars and a counter is less code as immediate
## drawing than as a tree of `ProgressBar`s with theme overrides, and it keeps the whole readout in
## one place where the arm's-length legibility rules can actually be enforced.
##
## **Sizing is physical, not pixel.** Bar height and text size come from screen DPI, so the HUD is
## the same real-world size on a 400 dpi phone and a 500 dpi one — a pixel-sized HUD shrinks on
## exactly the dense panels where it is already hardest to read.

## Bar height in millimetres.
@export var bar_height_mm: float = 3.2

## Bar width as a fraction of the safe area.
@export_range(0.1, 1.0, 0.01) var bar_width_fraction: float = 0.33

## Gap between bars, millimetres.
@export var gap_mm: float = 1.4

@export_group("Colours")
@export var health_color: Color = Color(0.72, 0.18, 0.16)
@export var stamina_color: Color = Color(0.55, 0.66, 0.34)
@export var flask_color: Color = Color(1.0, 0.72, 0.35)
@export var backing_color: Color = Color(0.0, 0.0, 0.0, 0.55)
@export var ember_color: Color = Color(1.0, 0.86, 0.55)

var _player: Player
var _health: float = 1.0
var _stamina: float = 1.0
var _embers: int = 0
var _flask: int = 3
var _flask_max: int = 3


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	EventBus.embers_changed.connect(_on_embers_changed)
	GameState.flask_changed.connect(_on_flask_changed)
	_embers = GameState.embers
	_flask = GameState.flask_charges
	_flask_max = GameState.flask_max_charges


func _process(_delta: float) -> void:
	var player := _resolve_player()
	if player == null or player.combatant == null:
		return
	var health := player.combatant.health_fraction()
	var stamina := player.combatant.stamina_fraction()
	if not is_equal_approx(health, _health) or not is_equal_approx(stamina, _stamina):
		_health = health
		_stamina = stamina
		queue_redraw()


func _draw() -> void:
	var px_per_mm := InputRouter.pixels_per_mm()
	var safe := InputRouter.safe_area()
	var scale := _viewport_scale()

	var margin := 6.0 * px_per_mm * scale.x
	var origin := Vector2(
		float(safe.position.x) * scale.x + margin, float(safe.position.y) * scale.y + margin
	)

	var bar_w := size.x * bar_width_fraction
	var bar_h := bar_height_mm * px_per_mm * scale.y
	var gap := gap_mm * px_per_mm * scale.y

	_bar(Rect2(origin, Vector2(bar_w, bar_h)), _health, health_color)
	_bar(
		Rect2(origin + Vector2(0.0, bar_h + gap), Vector2(bar_w * 0.82, bar_h * 0.7)),
		_stamina,
		stamina_color
	)

	# Flask pips rather than a bar: a discrete resource has to be countable at a glance, and a
	# two-thirds-full bar does not tell you whether that is one drink or two.
	var pip := bar_h * 0.8
	var pip_y := origin.y + (bar_h + gap) * 2.0
	for index: int in _flask_max:
		var rect := Rect2(Vector2(origin.x + float(index) * (pip * 1.3), pip_y), Vector2(pip, pip))
		draw_rect(rect, backing_color)
		if index < _flask:
			draw_rect(rect.grow(-pip * 0.18), flask_color)

	# Right-hand safe inset: the notch and gesture bar eat different amounts on each edge, and the
	# Embers readout hangs off the right one.
	var window := DisplayServer.window_get_size()
	var right_inset := 0.0
	if window.x > 0:
		right_inset = float(window.x - (safe.position.x + safe.size.x)) * scale.x

	var font := get_theme_default_font()
	var font_size := int(4.0 * px_per_mm * scale.y)
	var text := "%s  %d" % [tr("UI_EMBERS"), _embers]
	var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(
		font,
		Vector2(size.x - right_inset - extent.x - margin, origin.y + extent.y),
		text,
		HORIZONTAL_ALIGNMENT_RIGHT,
		-1.0,
		font_size,
		ember_color
	)


## Fraction currently shown on the health bar. For tests.
func health_fraction() -> float:
	return _health


## Flask pips currently lit. For tests.
func flask_charges() -> int:
	return _flask


func _bar(rect: Rect2, fraction: float, colour: Color) -> void:
	draw_rect(rect, backing_color)
	var filled := rect
	filled.size.x *= clampf(fraction, 0.0, 1.0)
	draw_rect(filled, colour)
	draw_rect(rect, Color(1.0, 1.0, 1.0, 0.18), false, 1.0)


func _viewport_scale() -> Vector2:
	var window := DisplayServer.window_get_size()
	if window.x <= 0 or window.y <= 0:
		return Vector2.ONE
	return Vector2(size.x / float(window.x), size.y / float(window.y))


func _resolve_player() -> Player:
	if is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group(&"player") as Player
	return _player


func _on_embers_changed(current: int) -> void:
	_embers = current
	queue_redraw()


func _on_flask_changed(charges: int, maximum: int) -> void:
	_flask = charges
	_flask_max = maximum
	queue_redraw()
