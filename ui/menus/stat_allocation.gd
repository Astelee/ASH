class_name StatAllocation
extends Control

## The Wayshrine level-up screen. Deferred from Phase 3 because Phase 7 owns UI.
##
## Two separate actions, deliberately not merged: **buying a level** spends Embers and banks a
## point; **allocating** spends the point. Souls-likes conflate them into one confirm, which means a
## misclick costs the level as well as the point. Here you can bank three levels and then decide.
##
## Everything is confirmed before it commits, because [code]GameState.level_up()[/code] writes
## straight through to the save on close and there is no undo.

## Emitted when the player closes the screen.
signal closed

## Stat rows, in display order.
const STATS: Array[StatBlock.Stat] = [
	StatBlock.Stat.VIGOR,
	StatBlock.Stat.ENDURANCE,
	StatBlock.Stat.MIGHT,
	StatBlock.Stat.FINESSE,
	StatBlock.Stat.EMBER_BOUND,
]

const LABELS: Dictionary[StatBlock.Stat, String] = {
	StatBlock.Stat.VIGOR: "UI_STAT_VIGOR",
	StatBlock.Stat.ENDURANCE: "UI_STAT_ENDURANCE",
	StatBlock.Stat.MIGHT: "UI_STAT_MIGHT",
	StatBlock.Stat.FINESSE: "UI_STAT_FINESSE",
	StatBlock.Stat.EMBER_BOUND: "UI_STAT_EMBER_BOUND",
}

var _summary: Label
var _level_button: Button
var _rows: Dictionary[StatBlock.Stat, Label] = {}


func _ready() -> void:
	# It pauses the tree itself, so it has to keep processing once paused -- otherwise its own
	# buttons go dead and the player is stuck at the Wayshrine with no way to close it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()
	GameState.level_changed.connect(_on_state_changed)
	GameState.embers_changed.connect(_on_embers_changed)

	# Resting is a fact on the bus, so this screen needs no wiring in any level and the Wayshrine
	# never has to know a level-up screen exists (CLAUDE.md §2).
	EventBus.rested_at_wayshrine.connect(_on_rested)


func _on_rested(_shrine_id: String) -> void:
	open()


## Show the screen and pause the world behind it.
func open() -> void:
	visible = true
	get_tree().paused = true
	_refresh()


## Close, unpause, and persist. The autosave is here rather than on every button press so a player
## browsing options does not write the save file a dozen times.
func close() -> void:
	visible = false
	get_tree().paused = false
	SaveSystem.autosave("wayshrine_levelup")
	closed.emit()


## Buy one level. Returns false when unaffordable.
func buy_level() -> bool:
	var bought := GameState.level_up()
	_refresh()
	return bought


## Spend a banked point on [param stat].
func allocate(stat: StatBlock.Stat) -> bool:
	var spent := GameState.allocate_point(stat)
	_refresh()
	return spent


func _build() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	var backing := ColorRect.new()
	backing.color = Color(0.04, 0.04, 0.06, 0.92)
	backing.set_anchors_preset(Control.PRESET_FULL_RECT)
	backing.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backing)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.add_theme_constant_override("separation", 14)
	add_child(column)

	_summary = Label.new()
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_summary)

	_level_button = Button.new()
	_level_button.text = tr("UI_LEVEL_UP")
	_level_button.pressed.connect(func() -> void: buy_level())
	column.add_child(_level_button)

	for stat: StatBlock.Stat in STATS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		column.add_child(row)

		var label := Label.new()
		label.custom_minimum_size.x = 420.0
		row.add_child(label)
		_rows[stat] = label

		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(72.0, 72.0)
		plus.pressed.connect(allocate.bind(stat))
		row.add_child(plus)

	var back := Button.new()
	back.text = tr("UI_BACK")
	back.pressed.connect(close)
	column.add_child(back)


func _refresh() -> void:
	if _summary == null:
		return
	_summary.text = (
		"%s %d   —   %s %d   —   %s %d"
		% [
			tr("UI_LEVEL"),
			GameState.level,
			tr("UI_EMBERS"),
			GameState.embers,
			tr("UI_POINTS_UNSPENT"),
			GameState.unspent_points,
		]
	)

	var cost := GameState.next_level_cost()
	_level_button.text = "%s  (%d)" % [tr("UI_LEVEL_UP"), cost]
	_level_button.disabled = GameState.embers < cost

	for stat: StatBlock.Stat in STATS:
		var value := GameState.stats.get_stat(stat)
		_rows[stat].text = "%s  %d" % [tr(LABELS[stat]), value]


func _on_state_changed(_level: int, _points: int) -> void:
	_refresh()


func _on_embers_changed(_current: int) -> void:
	_refresh()
