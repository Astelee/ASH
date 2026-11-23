class_name BossHealthBar
extends Control

## The boss HP bar. Appears on engagement, tracks the pool, and marks the phase thresholds.
##
## Finds its boss through [code]EventBus[/code] rather than an exported reference, so it works in
## any arena with no wiring — including The Hollow Choir, whose three bodies share one pool and
## would otherwise need three bars showing the same number.

## Bar fill colour.
@export var fill_color: Color = Color(0.72, 0.16, 0.14)

## Colour of the phase-threshold ticks.
@export var tick_color: Color = Color(1.0, 0.92, 0.78, 0.85)

## Bar height in pixels.
@export var bar_height: float = 22.0

## Fraction of screen width the bar spans.
@export_range(0.3, 1.0, 0.01) var bar_width_fraction: float = 0.7

var _boss: Boss
var _fraction: float = 1.0
var _label: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	EventBus.boss_engaged.connect(_on_engaged)
	EventBus.enemy_died.connect(_on_enemy_died)


func _process(_delta: float) -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	var next := _boss.health_fraction()
	if not is_equal_approx(next, _fraction):
		_fraction = next
		queue_redraw()


func _draw() -> void:
	if _boss == null:
		return
	var width := size.x * bar_width_fraction
	var origin := Vector2((size.x - width) * 0.5, size.y - bar_height - 24.0)

	draw_rect(Rect2(origin, Vector2(width, bar_height)), Color(0.0, 0.0, 0.0, 0.55))
	draw_rect(Rect2(origin, Vector2(width * _fraction, bar_height)), fill_color)

	# Threshold ticks: the player should see a phase change coming rather than be ambushed by it.
	for threshold: float in _boss.phase_thresholds:
		var x := origin.x + width * threshold
		draw_line(Vector2(x, origin.y), Vector2(x, origin.y + bar_height), tick_color, 2.0)

	draw_rect(Rect2(origin, Vector2(width, bar_height)), Color(1.0, 1.0, 1.0, 0.25), false, 1.5)


## Fraction currently displayed. For tests.
func displayed_fraction() -> float:
	return _fraction


func _on_engaged(boss: Node, display_name: String) -> void:
	_boss = boss as Boss
	if _boss == null:
		return
	visible = true
	_fraction = 1.0
	_label.text = display_name
	_label.position = Vector2(0.0, size.y - bar_height - 52.0)
	_label.size.x = size.x
	queue_redraw()


func _on_enemy_died(enemy: Node, _embers: int) -> void:
	if enemy == _boss:
		visible = false
		_boss = null
