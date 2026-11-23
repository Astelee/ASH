class_name SaveMigrations
extends RefCounted

## The save schema version and the chain that walks an old payload up to it.
##
## Every migration is a pure [Dictionary] → [Dictionary] function with no file access, so the whole
## chain is unit-testable and a failed migration can never corrupt a file on disk. The walker
## applies them strictly in order; there are no conditional or skipping paths, because those are
## how save systems develop unreproducible bugs.
##
## Adding a schema change means: bump [constant CURRENT_VERSION], add a
## [code]_migrate_vN_to_vN+1[/code], register it in [method _chain], and add a test.

## Schema version this build writes.
##
## [b]v1[/b] — the original Phase 0 schema: player, world, bloodstain.
## [b]v2[/b] — adds the Ashen Flask and the gear block. Both were designed in Phase 0a, after the
## first schema was published, which is exactly the situation the chain exists for.
const CURRENT_VERSION: int = 2

## Lowest version this build can still read.
const OLDEST_SUPPORTED: int = 1


## Walk [param payload] from [param from_version] up to [constant CURRENT_VERSION].
##
## Returns the migrated payload. Callers must check [method can_load] first — a version newer
## than this build cannot be guessed at and is returned untouched.
static func migrate(payload: Dictionary, from_version: int) -> Dictionary:
	var working := payload.duplicate(true)
	var version := from_version
	while version < CURRENT_VERSION:
		var step := _chain().get(version) as Callable
		if step == null:
			Log.error("SaveMigrations", "no migration from v%d; stopping" % version)
			break
		working = step.call(working) as Dictionary
		version += 1
	return working


## True when this build can read a save written at [param version].
##
## A save from the future fails deliberately and visibly. Loading it on a guess is how a player
## loses a run to a version downgrade.
static func can_load(version: int) -> bool:
	return version >= OLDEST_SUPPORTED and version <= CURRENT_VERSION


## Human-readable reason a save cannot be loaded, for the UI.
static func rejection_reason(version: int) -> String:
	if version > CURRENT_VERSION:
		return (
			(
				"This save was written by a newer version of Ashfall (save v%d, this build reads"
				+ " v%d). Update the game to continue this run."
			)
			% [version, CURRENT_VERSION]
		)
	if version < OLDEST_SUPPORTED:
		return "This save is too old to be read by this build (save v%d)." % version
	return ""


## Version → the function that raises it by one.
static func _chain() -> Dictionary[int, Callable]:
	return {
		1: _migrate_v1_to_v2,
	}


## v1 → v2: the Ashen Flask and the gear block did not exist when v1 was written.
##
## Fills in the starting flask rather than an empty one — a returning player must not reload into a
## run with no healing, which would be a silent, unwinnable state rather than an obvious bug.
static func _migrate_v1_to_v2(payload: Dictionary) -> Dictionary:
	var working := payload.duplicate(true)
	if not working.has("flask"):
		working["flask"] = {
			"charges": 3,
			"max_charges": 3,
			"base_heal": 90.0,
			"ash_shards": [],
		}
	if not working.has("gear"):
		working["gear"] = {
			"weapon": "ashen_longsword",
			"shield": "wooden_kite",
			"lantern_level": 1,
		}
	return working
