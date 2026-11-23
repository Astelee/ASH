class_name Log
extends RefCounted

## Build-flag-gated logging. Replaces bare [code]print()[/code] everywhere in the project.
##
## Debug and info are stripped in release builds via [method OS.is_debug_build]; warn and error
## always emit so that store-build crash reports stay useful. Never call [code]print()[/code]
## directly in project code — see [code]CLAUDE.md[/code].

## Minimum severity that will be emitted. Set from [code]QualityManager[/code] or a launch arg.
enum Level { DEBUG, INFO, WARN, ERROR, SILENT }

static var min_level: Level = Level.DEBUG if OS.is_debug_build() else Level.WARN


## Verbose per-frame-ish diagnostics. Stripped in release builds.
static func debug(tag: String, message: String) -> void:
	if min_level <= Level.DEBUG:
		print("[D][%s] %s" % [tag, message])


## Lifecycle events: scene loads, save writes, quality tier changes.
static func info(tag: String, message: String) -> void:
	if min_level <= Level.INFO:
		print("[I][%s] %s" % [tag, message])


## Recoverable problems: missing optional resource, clamped tuning value.
static func warn(tag: String, message: String) -> void:
	if min_level <= Level.WARN:
		push_warning("[%s] %s" % [tag, message])


## Contract violations: a system is now in a state the code does not handle.
static func error(tag: String, message: String) -> void:
	if min_level <= Level.ERROR:
		push_error("[%s] %s" % [tag, message])
