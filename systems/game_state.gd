extends Node

## Authoritative runtime state for the current run.
##
## Owns the in-memory model only. Serialization is [code]SaveSystem[/code]'s job; this node hands it
## a plain [Dictionary] and takes one back. Keeping the two apart is what makes the migration chain
## testable without touching a file.

signal embers_changed(current: int)
signal level_changed(level: int, unspent_points: int)
signal flask_changed(charges: int, maximum: int)

## Emitted when a bloodstain is created, moved, or cleared. Null position means none exists.
signal bloodstain_changed(has_stain: bool, at: Vector3)

## Starting flask charges.
const STARTING_FLASK_CHARGES: int = 3

## Base HP restored by a level-1 flask.
const STARTING_FLASK_HEAL: float = 90.0

## Character level.
var level: int = 1

## Live stats for this run. Always a copy, never the authored template resource.
var stats: StatBlock

## Carried Embers. Dropped in full on death.
var embers: int = 0

## Stat points earned but not yet allocated.
var unspent_points: int = 0

## Flask charges remaining.
var flask_charges: int = STARTING_FLASK_CHARGES

## Flask capacity, raised by Ash Shards.
var flask_max_charges: int = STARTING_FLASK_CHARGES

## Base HP per drink before Ember-Bound scaling.
var flask_base_heal: float = STARTING_FLASK_HEAL

## Ash Shard ids already collected, so a shard cannot be farmed twice.
var ash_shards: Array[String] = []

## Id of the last Wayshrine rested at. Respawn point.
var wayshrine: String = ""

## One-shot world flags: opened shortcuts, triggered events.
var world_flags: Array[String] = []

## Bosses already killed. Persists across death, unlike world enemies.
var bosses_defeated: Array[String] = []

## Level the bloodstain sits in, empty when none exists.
var bloodstain_level: String = ""

## Where the bloodstain sits.
var bloodstain_position: Vector3 = Vector3.ZERO

## Embers waiting to be recovered.
var bloodstain_embers: int = 0

var _progression: Progression


func _ready() -> void:
	_progression = Progression.new()
	if stats == null:
		stats = StatBlock.new()

	# Saved settings only take effect if something applies them. Deferred because apply() reaches
	# into QualityManager, which is a later autoload and not ready while GameState is starting.
	Settings.current().apply.call_deferred()

	# The bus carries facts; GameState is the system that owns what those facts mean for the run.
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.player_died.connect(_on_player_died)


func _on_enemy_died(_enemy: Node, dropped: int) -> void:
	add_embers(dropped)


func _on_player_died(at: Vector3) -> void:
	drop_bloodstain(current_level_id(), at)
	SaveSystem.autosave("player_died")


## Identifier of the level currently loaded, used to place the bloodstain.
func current_level_id() -> String:
	var scene := get_tree().current_scene
	if scene == null:
		return ""
	var root := scene as LevelRoot
	if root != null and not root.level_id.is_empty():
		return root.level_id
	return scene.scene_file_path.get_file().get_basename()


## Wipe to a fresh run. [param template] is the authored starting stat block, which is duplicated so
## the resource on disk is never mutated by play.
func begin_new_run(template: StatBlock) -> void:
	stats = template.duplicate_block() if template != null else StatBlock.new()
	level = Progression.STARTING_LEVEL
	embers = 0
	unspent_points = 0
	flask_charges = STARTING_FLASK_CHARGES
	flask_max_charges = STARTING_FLASK_CHARGES
	flask_base_heal = STARTING_FLASK_HEAL
	ash_shards.clear()
	wayshrine = ""
	world_flags.clear()
	bosses_defeated.clear()
	clear_bloodstain()
	_announce()


# --------------------------------------------------------------------------- embers


## Credit [param amount] Embers.
func add_embers(amount: int) -> void:
	if amount <= 0:
		return
	embers += amount
	embers_changed.emit(embers)
	EventBus.embers_changed.emit(embers)


## Debit [param amount]. Returns false and spends nothing when the purse is short.
func spend_embers(amount: int) -> bool:
	if amount > embers:
		return false
	embers -= amount
	embers_changed.emit(embers)
	EventBus.embers_changed.emit(embers)
	return true


## Embers needed for the next level.
func next_level_cost() -> int:
	return _progression.cost(level)


## Buy one level. Returns false when unaffordable.
func level_up() -> bool:
	var price := _progression.cost(level)
	if not spend_embers(price):
		return false
	unspent_points += _progression.points_for_level_up(level)
	level += 1
	level_changed.emit(level, unspent_points)
	return true


## Put one point into [param stat]. Returns false with no points banked.
func allocate_point(stat: StatBlock.Stat) -> bool:
	if unspent_points <= 0:
		return false
	unspent_points -= 1
	match stat:
		StatBlock.Stat.VIGOR:
			stats.vigor += 1
		StatBlock.Stat.ENDURANCE:
			stats.endurance += 1
		StatBlock.Stat.MIGHT:
			stats.might += 1
		StatBlock.Stat.FINESSE:
			stats.finesse += 1
		StatBlock.Stat.EMBER_BOUND:
			stats.ember_bound += 1
	level_changed.emit(level, unspent_points)
	return true


# --------------------------------------------------------------------------- flask


## HP a single drink restores, scaled by Ember-Bound.
func flask_heal_amount() -> float:
	return flask_base_heal * (1.0 + float(stats.ember_bound) * 0.015)


## Consume one charge. Returns false when empty.
func use_flask() -> bool:
	if flask_charges <= 0:
		return false
	flask_charges -= 1
	flask_changed.emit(flask_charges, flask_max_charges)
	return true


## Bank an Ash Shard, raising capacity. Ignores shards already collected.
func collect_ash_shard(id: String) -> bool:
	if ash_shards.has(id):
		return false
	ash_shards.append(id)
	flask_max_charges += 1
	flask_charges = flask_max_charges
	flask_changed.emit(flask_charges, flask_max_charges)
	return true


# --------------------------------------------------------------------------- death


## Drop the whole purse at [param at]. Any previous bloodstain is lost — dying twice before
## recovering is how Embers leave the economy for good.
func drop_bloodstain(level_id: String, at: Vector3) -> void:
	bloodstain_level = level_id
	bloodstain_position = at
	bloodstain_embers = embers
	embers = 0
	embers_changed.emit(embers)
	bloodstain_changed.emit(true, at)


## Reclaim the bloodstain and clear it.
func recover_bloodstain() -> int:
	var reclaimed := bloodstain_embers
	add_embers(reclaimed)
	clear_bloodstain()
	return reclaimed


## Remove the bloodstain without paying it out.
func clear_bloodstain() -> void:
	bloodstain_level = ""
	bloodstain_position = Vector3.ZERO
	bloodstain_embers = 0
	bloodstain_changed.emit(false, Vector3.ZERO)


## True while a bloodstain is waiting somewhere.
func has_bloodstain() -> bool:
	return not bloodstain_level.is_empty()


# --------------------------------------------------------------------------- world


## Rest: refill the flask, set the respawn point. Enemy respawn is the level's business.
func rest_at(wayshrine_id: String) -> void:
	wayshrine = wayshrine_id
	flask_charges = flask_max_charges
	flask_changed.emit(flask_charges, flask_max_charges)


## Raise a one-shot world flag. Returns false if already set.
func set_flag(flag: String) -> bool:
	if world_flags.has(flag):
		return false
	world_flags.append(flag)
	return true


## True when [param flag] has been raised.
func has_flag(flag: String) -> bool:
	return world_flags.has(flag)


## Record a boss kill. Persists across death, unlike world enemies.
func record_boss_defeat(boss_id: String) -> void:
	if not bosses_defeated.has(boss_id):
		bosses_defeated.append(boss_id)


## True when [param boss_id] is already dead.
func is_boss_defeated(boss_id: String) -> bool:
	return bosses_defeated.has(boss_id)


# --------------------------------------------------------------------------- serialization


## Snapshot as a plain Dictionary for [code]SaveSystem[/code]. No Resources, no node references —
## everything here must survive a JSON round trip unchanged.
func to_dict() -> Dictionary:
	return {
		"player":
		{
			"level": level,
			"embers": embers,
			"unspent_points": unspent_points,
			"stats":
			{
				"vigor": stats.vigor,
				"endurance": stats.endurance,
				"might": stats.might,
				"finesse": stats.finesse,
				"ember_bound": stats.ember_bound,
			},
		},
		"flask":
		{
			"charges": flask_charges,
			"max_charges": flask_max_charges,
			"base_heal": flask_base_heal,
			"ash_shards": ash_shards.duplicate(),
		},
		"world":
		{
			"wayshrine": wayshrine,
			"flags": world_flags.duplicate(),
			"bosses_defeated": bosses_defeated.duplicate(),
		},
		"bloodstain":
		{
			"level_id": bloodstain_level,
			"position": [bloodstain_position.x, bloodstain_position.y, bloodstain_position.z],
			"embers": bloodstain_embers,
		},
	}


## Restore from a migrated payload. Every field defaults, so a partial or hand-edited save loads
## rather than crashing.
func from_dict(payload: Dictionary) -> void:
	var player: Dictionary = payload.get("player", {})
	level = int(player.get("level", 1))
	embers = int(player.get("embers", 0))
	unspent_points = int(player.get("unspent_points", 0))

	var stat_values: Dictionary = player.get("stats", {})
	if stats == null:
		stats = StatBlock.new()
	stats.vigor = int(stat_values.get("vigor", stats.vigor))
	stats.endurance = int(stat_values.get("endurance", stats.endurance))
	stats.might = int(stat_values.get("might", stats.might))
	stats.finesse = int(stat_values.get("finesse", stats.finesse))
	stats.ember_bound = int(stat_values.get("ember_bound", stats.ember_bound))

	var flask: Dictionary = payload.get("flask", {})
	flask_max_charges = int(flask.get("max_charges", STARTING_FLASK_CHARGES))
	flask_charges = int(flask.get("charges", flask_max_charges))
	flask_base_heal = float(flask.get("base_heal", STARTING_FLASK_HEAL))
	ash_shards = _to_string_array(flask.get("ash_shards", []))

	var world: Dictionary = payload.get("world", {})
	wayshrine = str(world.get("wayshrine", ""))
	world_flags = _to_string_array(world.get("flags", []))
	bosses_defeated = _to_string_array(world.get("bosses_defeated", []))

	var stain: Dictionary = payload.get("bloodstain", {})
	bloodstain_level = str(stain.get("level_id", ""))
	bloodstain_embers = int(stain.get("embers", 0))
	var point: Array = stain.get("position", [0.0, 0.0, 0.0])
	if point.size() == 3:
		bloodstain_position = Vector3(float(point[0]), float(point[1]), float(point[2]))

	_announce()


func _announce() -> void:
	embers_changed.emit(embers)
	level_changed.emit(level, unspent_points)
	flask_changed.emit(flask_charges, flask_max_charges)
	bloodstain_changed.emit(has_bloodstain(), bloodstain_position)


## JSON gives back untyped arrays; the model wants typed ones.
func _to_string_array(source: Variant) -> Array[String]:
	var out: Array[String] = []
	for item: Variant in source as Array:
		out.append(str(item))
	return out
