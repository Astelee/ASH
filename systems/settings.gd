class_name Settings
extends RefCounted

## Every player-facing option, and the file it persists to.
##
## Deliberately **not** a tenth autoload — `CLAUDE.md §2` sets the bar for global state at "two
## unrelated systems need it and nothing in the tree can own it", and a settings blob is neither. It
## is a plain class with a lazily-loaded singleton accessor, which gives global reach without adding
## a node that processes every frame forever.
##
## Stored as a `ConfigFile` rather than through `SaveSystem`: settings must survive deleting a save,
## and a player who wipes their run should not lose their control layout with it.

## Emitted whenever any value changes, so live UI can react without polling.
signal changed(key: StringName)

## Colourblind palettes. These re-map hue while preserving the **saturation** arc that carries the
## mood from Village to Ossuary — a palette that flattens saturation destroys the one thing the art
## direction is built on.
enum Palette { DEFAULT, DEUTERANOPIA, PROTANOPIA, TRITANOPIA }

## Whether sprint and block are held or toggled. Holding a button through a long traversal is a real
## accessibility problem, not a preference.
enum HoldMode { HOLD, TOGGLE }

const PATH: String = "user://settings.cfg"

static var _instance: Settings

# ---------------------------------------------------------------- display
var quality_tier: int = QualityManager.Tier.MID
var brightness: float = 1.0
var palette: Palette = Palette.DEFAULT
var damage_numbers: bool = true
var camera_shake: float = 1.0
var subtitle_size: int = 32
var show_debug_overlay: bool = false

# ---------------------------------------------------------------- audio
var master_volume: float = 1.0
var music_volume: float = 0.8
var sfx_volume: float = 1.0
var ambience_volume: float = 0.7
var ui_volume: float = 0.9

# ---------------------------------------------------------------- input
var sprint_mode: HoldMode = HoldMode.HOLD
var block_mode: HoldMode = HoldMode.HOLD
var haptics: bool = true
var touch_opacity: float = 0.85
var touch_scale: float = 1.0

## Per-button layout overrides, keyed by action name. Written by the layout editor.
var button_offsets: Dictionary[StringName, Vector2] = {}

# ---------------------------------------------------------------- language
var locale: String = "en"


## The live settings, loaded from disk on first access.
static func current() -> Settings:
	if _instance == null:
		_instance = Settings.new()
		_instance.load_from_disk()
	return _instance


## Replace the singleton. Tests use this to work on a throwaway instance.
static func override_for_test(replacement: Settings) -> void:
	_instance = replacement


## Reset every value to its default without touching the file on disk.
func restore_defaults() -> void:
	var fresh := Settings.new()
	for property: Dictionary in get_property_list():
		var name: String = property["name"]
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and not name.begins_with("_"):
			set(name, fresh.get(name))
	changed.emit(&"all")


## Apply a value and persist. One entry point, so nothing can change a setting without saving it.
func set_value(key: StringName, value: Variant) -> void:
	if not _has_property(key):
		Log.warn("Settings", "unknown setting '%s'" % key)
		return
	set(key, value)
	changed.emit(key)
	save_to_disk()


## Push everything that has a runtime effect into the systems that own it.
##
## Called on load and after the settings screen closes. Options that only matter when read
## (subtitle size, damage numbers) are not pushed — their owners read them directly.
func apply() -> void:
	QualityManager.apply(quality_tier as QualityManager.Tier)

	for pair: Array in [
		["Master", master_volume],
		["Music", music_volume],
		["SFX", sfx_volume],
		["Ambience", ambience_volume],
		["UI", ui_volume],
	]:
		var index := AudioServer.get_bus_index(pair[0])
		if index >= 0:
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(pair[1], 0.0001)))

	if not locale.is_empty():
		TranslationServer.set_locale(locale)


## Write to disk. Fails silently on a read-only filesystem rather than crashing a settings screen.
func save_to_disk() -> void:
	var config := ConfigFile.new()
	for section: String in ["display", "audio", "input", "language"]:
		for key: String in _keys_in(section):
			config.set_value(section, key, get(key))

	var layout := {}
	for action: StringName in button_offsets:
		layout[String(action)] = button_offsets[action]
	config.set_value("input", "button_offsets", layout)

	var status := config.save(PATH)
	if status != OK:
		Log.warn("Settings", "could not write %s: %s" % [PATH, error_string(status)])


## Read from disk. A missing or corrupt file leaves the defaults in place, which is always playable.
func load_from_disk() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return

	for section: String in ["display", "audio", "input", "language"]:
		for key: String in _keys_in(section):
			if config.has_section_key(section, key):
				set(key, config.get_value(section, key))

	button_offsets.clear()
	var layout: Dictionary = config.get_value("input", "button_offsets", {})
	for action: String in layout:
		button_offsets[StringName(action)] = layout[action]


## Stored offset for [param action], or zero.
func offset_for(action: StringName) -> Vector2:
	return button_offsets.get(action, Vector2.ZERO)


## Record a dragged button position.
func set_offset(action: StringName, offset: Vector2) -> void:
	button_offsets[action] = offset
	changed.emit(&"button_offsets")
	save_to_disk()


## True when [param mode] means the player holds the button rather than toggling it.
func is_hold(mode: HoldMode) -> bool:
	return mode == HoldMode.HOLD


func _has_property(key: StringName) -> bool:
	for property: Dictionary in get_property_list():
		if property["name"] == String(key):
			return true
	return false


func _keys_in(section: String) -> PackedStringArray:
	match section:
		"display":
			return PackedStringArray(
				[
					"quality_tier",
					"brightness",
					"palette",
					"damage_numbers",
					"camera_shake",
					"subtitle_size",
					"show_debug_overlay",
				]
			)
		"audio":
			return PackedStringArray(
				["master_volume", "music_volume", "sfx_volume", "ambience_volume", "ui_volume"]
			)
		"input":
			return PackedStringArray(
				["sprint_mode", "block_mode", "haptics", "touch_opacity", "touch_scale"]
			)
		"language":
			return PackedStringArray(["locale"])
	return PackedStringArray()
