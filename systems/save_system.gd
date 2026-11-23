extends Node

## Slot-based persistence: [code]user://saves/slot_%d.save[/code], JSON body, gzip-compressed,
## with a versioned header carrying a SHA-256 of the payload.
##
## Four rules, all of them hard requirements from [code]docs/TECH.md §7[/code]:
## [br]1. Write to a temp file, then rename over the live save. **Never in place.**
## [br]2. Migrate through an explicit chain — see [SaveMigrations].
## [br]3. A save newer than this build fails with a message, never a crash and never a wipe.
## [br]4. Autosave on rest, level-up, boss defeat, and application pause.

## Emitted after a successful write.
signal saved(slot: int)

## Emitted after a successful load.
signal loaded(slot: int)

## Emitted when a load fails, with a message fit to show the player.
signal load_failed(slot: int, reason: String)

## Directory holding every slot.
const SAVE_DIR: String = "user://saves"

## Slots offered.
const SLOT_COUNT: int = 3

## Extension for the live file.
const EXTENSION: String = ".save"

## Extension for the rotated previous write.
const BACKUP_EXTENSION: String = ".save.bak"

## Extension for the in-progress write.
const TEMP_EXTENSION: String = ".save.tmp"

## Slot autosaves target.
var active_slot: int = 0

var _saving: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func _notification(what: int) -> void:
	# Mandatory, not optional: Android kills backgrounded processes without warning, and this is the
	# last moment the run still exists.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		autosave("application_paused")


## Absolute path of [param slot]'s live file.
func slot_path(slot: int) -> String:
	return "%s/slot_%d%s" % [SAVE_DIR, slot, EXTENSION]


## Write the current [code]GameState[/code] to [param slot].
##
## Serialises to a temp file and renames over the live save only once the bytes are down. A process
## killed mid-write loses the temp file, never the run.
func save_to_slot(slot: int) -> bool:
	if _saving:
		Log.warn("SaveSystem", "save already in progress; skipping")
		return false
	_saving = true
	var ok := _write(slot, GameState.to_dict())
	_saving = false
	if ok:
		saved.emit(slot)
	return ok


## Save to [member active_slot], tagging [param reason] in the log. Called on rest, level-up, boss
## defeat, and pause.
func autosave(reason: String) -> bool:
	Log.info("SaveSystem", "autosave (%s)" % reason)
	return save_to_slot(active_slot)


## Load [param slot] into [code]GameState[/code].
##
## Falls back to the rotated backup when the live file is missing or its checksum does not match,
## which is the case a half-written file from an older build would produce.
func load_from_slot(slot: int) -> bool:
	var payload := _read(slot_path(slot))
	if payload.is_empty():
		payload = _read(slot_path(slot).replace(EXTENSION, BACKUP_EXTENSION))
		if not payload.is_empty():
			Log.warn("SaveSystem", "slot %d fell back to its backup" % slot)

	if payload.is_empty():
		load_failed.emit(slot, "No save data in slot %d." % slot)
		return false

	var version := int(payload.get("version", 0))
	if not SaveMigrations.can_load(version):
		var reason := SaveMigrations.rejection_reason(version)
		Log.error("SaveSystem", reason)
		load_failed.emit(slot, reason)
		return false

	var body := envelope_body(payload)
	if version < SaveMigrations.CURRENT_VERSION:
		Log.info("SaveSystem", "migrating slot %d from v%d" % [slot, version])
		body = SaveMigrations.migrate(body, version)

	GameState.from_dict(body)
	active_slot = slot
	loaded.emit(slot)
	return true


## True when [param slot] holds readable data.
func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


## Delete [param slot] and its backup.
func delete_slot(slot: int) -> void:
	for suffix: String in [EXTENSION, BACKUP_EXTENSION, TEMP_EXTENSION]:
		var path := slot_path(slot).replace(EXTENSION, suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## Wrap [param body] in the versioned, checksummed header. Exposed for the round-trip test.
##
## The payload is stored as an [b]embedded JSON string[/b], not a nested object, and the checksum
## covers those exact bytes. Checksumming a nested object cannot work: JSON has one number type, so
## an integer 7 returns as 7.0 and re-serialising the parsed payload never reproduces the original
## text. Every load would fail its own checksum.
func build_envelope(body: Dictionary) -> Dictionary:
	var json := JSON.stringify(body)
	return {
		"version": SaveMigrations.CURRENT_VERSION,
		"checksum": "sha256:%s" % _digest(json),
		"written_at": Time.get_datetime_string_from_system(true, true),
		"build": ProjectSettings.get_setting("application/config/version", "0.0.0"),
		"payload": json,
	}


## True when [param envelope]'s checksum matches its payload bytes.
func verify_envelope(envelope: Dictionary) -> bool:
	var stored := str(envelope.get("checksum", ""))
	if stored.is_empty():
		return false
	return stored == "sha256:%s" % _digest(str(envelope.get("payload", "")))


## Decode an envelope's payload back into a Dictionary.
func envelope_body(envelope: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(str(envelope.get("payload", "")))
	return parsed if parsed is Dictionary else {}


func _write(slot: int, body: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	var live := slot_path(slot)
	var temp := live.replace(EXTENSION, TEMP_EXTENSION)
	var backup := live.replace(EXTENSION, BACKUP_EXTENSION)

	var file := FileAccess.open_compressed(temp, FileAccess.WRITE, FileAccess.COMPRESSION_GZIP)
	if file == null:
		Log.error(
			"SaveSystem", "cannot open %s: %s" % [temp, error_string(FileAccess.get_open_error())]
		)
		return false
	file.store_string(JSON.stringify(build_envelope(body)))
	file.close()

	# Rotate the previous write before the rename, so a failure here still leaves two readable files.
	if FileAccess.file_exists(live):
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(backup)
		DirAccess.rename_absolute(live, backup)

	var status := DirAccess.rename_absolute(temp, live)
	if status != OK:
		Log.error("SaveSystem", "rename failed: %s" % error_string(status))
		return false
	return true


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_GZIP)
	if file == null:
		Log.warn("SaveSystem", "cannot open %s" % path)
		return {}
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		Log.warn("SaveSystem", "%s is not valid save JSON" % path)
		return {}

	var envelope: Dictionary = parsed
	if not verify_envelope(envelope):
		Log.warn("SaveSystem", "%s failed its checksum" % path)
		return {}
	return envelope


func _digest(text: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(text.to_utf8_buffer())
	return context.finish().hex_encode()
