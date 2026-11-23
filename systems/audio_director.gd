extends Node

## Owns the bus layout, the pooled players, music stem mixing, ducking, and zone reverb.
##
## Three ideas hold this together:
##
## [b]The pool never grows and never allocates.[/b] Players are created once at ready and reused.
## When every voice is busy the loudest-priority claim steals the *quietest*, oldest,
## lowest-priority voice — a fixed policy, so a chaotic fight degrades predictably instead of
## stuttering.
##
## [b]Gameplay signals are not set dressing.[/b] Banks flagged `is_gameplay_signal` are exempt from
## distance falloff and occlusion, and sit at the top of the stealing order. The Gravewretch's
## rattle and the Bell-Bearer's bell are the mechanic, not the garnish; a wall must not make either
## inaudible.
##
## [b]Ducking is a target, not an event.[/b] Combat pushes ambience and music down toward a target
## gain and they recover on a slow curve. Duck-on-trigger with a fixed release produces pumping the
## moment two hits land close together.

## Emitted when the music layer set changes, for the debug overlay.
signal music_changed(set_id: StringName)

## Concurrent positional voices. Sized for a boss plus adds plus footsteps, and never exceeded.
const POOL_SIZE: int = 24

## Concurrent non-positional voices — UI, music stems, global stings.
const FLAT_POOL_SIZE: int = 8

## Music stems mixed in parallel. `BiomeMood.music_stem_mask` selects which are audible.
const STEM_COUNT: int = 5

## Bus names. Matched against `audio/buses/default_bus_layout.tres`.
const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"SFX"
const BUS_AMBIENCE: StringName = &"Ambience"
const BUS_UI: StringName = &"UI"
const BUS_REVERB: StringName = &"Reverb"

## dB the ambience and music are pushed down to while combat is loud.
const DUCK_TARGET_DB: float = -9.0

## Seconds to reach the duck target. Fast, but not instant — an instant duck is audible as a click.
const DUCK_ATTACK: float = 0.08

## Seconds to recover. Slow enough that two hits in quick succession do not pump.
const DUCK_RELEASE: float = 1.2

## Seconds of quiet before ducking releases at all.
const DUCK_HOLD: float = 0.35

## Reverb send while fully wet, dB.
const REVERB_MAX_DB: float = -3.0

var _rng := RandomNumberGenerator.new()
var _banks: Dictionary[StringName, SoundBank] = {}
var _last_played: Dictionary[StringName, float] = {}

var _pool: Array[AudioStreamPlayer3D] = []
var _flat_pool: Array[AudioStreamPlayer] = []
var _voice_priority: PackedInt32Array = PackedInt32Array()
var _voice_started: PackedFloat32Array = PackedFloat32Array()

var _stems: Array[AudioStreamPlayer] = []
var _stem_targets: PackedFloat32Array = PackedFloat32Array()

var _duck_amount: float = 0.0
var _duck_hold_left: float = 0.0
var _reverb_wet: float = 0.0
var _listener: AudioListener3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()

	_install_bus_layout()
	_build_pools()
	_build_stems()

	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.enemy_telegraphed.connect(_on_telegraph)
	EventBus.boss_engaged.connect(_on_boss_engaged)
	MoodDirector.mood_changed.connect(_on_mood_changed)


func _process(delta: float) -> void:
	_advance_duck(delta)
	_advance_stems(delta)


# --------------------------------------------------------------------------- registration


## Register a bank so it can be played by id.
func register_bank(bank: SoundBank) -> void:
	if bank == null or bank.id == &"none":
		return
	_banks[bank.id] = bank


## Register several at once, as a level or actor would on ready.
func register_banks(banks: Array[SoundBank]) -> void:
	for bank: SoundBank in banks:
		register_bank(bank)


## True when [param id] has been registered.
func has_bank(id: StringName) -> bool:
	return _banks.has(id)


## The scene's audio listener, so 3D panning is computed from the player rather than the camera.
##
## This matters more here than in most games: the camera sits 8 m back on Z, so listening from it
## would compress the left/right field and flatten exactly the directional cue the Gravewretch tell
## depends on.
func set_listener(node: Node3D) -> void:
	if _listener != null and is_instance_valid(_listener):
		_listener.queue_free()
	_listener = AudioListener3D.new()
	node.add_child(_listener)
	_listener.make_current()


# --------------------------------------------------------------------------- playback


## Play [param id] at [param position]. Returns the voice used, or null if the bank is unknown or
## rate-limited.
func play_3d(id: StringName, position: Vector3) -> AudioStreamPlayer3D:
	var bank := _banks.get(id) as SoundBank
	if bank == null:
		return null
	if not _rate_allows(bank):
		return null

	var stream := bank.pick(_rng)
	if stream == null:
		return null

	var index := _claim_voice(bank.priority)
	if index < 0:
		return null

	var voice := _pool[index]
	voice.stream = stream
	voice.global_position = position
	voice.bus = String(bank.bus)
	voice.volume_db = bank.roll_volume(_rng)
	voice.pitch_scale = bank.roll_pitch(_rng)
	voice.unit_size = bank.unit_size
	voice.max_distance = 0.0 if bank.is_gameplay_signal else bank.max_distance
	voice.attenuation_model = (
		AudioStreamPlayer3D.ATTENUATION_DISABLED if bank.is_gameplay_signal else bank.attenuation
		as AudioStreamPlayer3D.AttenuationModel
	)
	voice.play()

	_voice_priority[index] = bank.priority
	_voice_started[index] = float(Time.get_ticks_msec()) * 0.001
	return voice


## Play [param id] without position — UI, stings, global cues.
func play_flat(id: StringName) -> AudioStreamPlayer:
	var bank := _banks.get(id) as SoundBank
	if bank == null or not _rate_allows(bank):
		return null
	var stream := bank.pick(_rng)
	if stream == null:
		return null

	for voice: AudioStreamPlayer in _flat_pool:
		if voice.playing:
			continue
		voice.stream = stream
		voice.bus = String(bank.bus)
		voice.volume_db = bank.roll_volume(_rng)
		voice.pitch_scale = bank.roll_pitch(_rng)
		voice.play()
		return voice
	return null


## Stop every voice and clear the rate limiter.
##
## Called on scene transitions, where a footstep from the level you just left has no business
## finishing in the level you just entered.
func stop_all() -> void:
	for voice: AudioStreamPlayer3D in _pool:
		voice.stop()
	for flat: AudioStreamPlayer in _flat_pool:
		flat.stop()
	for index: int in _voice_priority.size():
		_voice_priority[index] = -1
		_voice_started[index] = 0.0
	_last_played.clear()
	_duck_amount = 0.0
	_duck_hold_left = 0.0


## Voices currently sounding.
func active_voices() -> int:
	var count := 0
	for voice: AudioStreamPlayer3D in _pool:
		if voice.playing:
			count += 1
	return count


# --------------------------------------------------------------------------- music


## Cross-fade the stem mix toward [param mask]. Bit N enables stem N.
##
## Stems run continuously and are mixed by gain rather than started and stopped, so they stay
## sample-locked to each other. Starting a stem on demand would drift it out of phase with the rest
## within a bar and turn a layered score into a smear.
func set_stem_mask(mask: int) -> void:
	for index: int in _stems.size():
		var enabled := (mask & (1 << index)) != 0
		_stem_targets[index] = 0.0 if enabled else -60.0


## Gain currently applied to [param index], dB. For tests.
func stem_volume_db(index: int) -> float:
	return _stems[index].volume_db if index < _stems.size() else -80.0


# --------------------------------------------------------------------------- mix


## Push the mix down. Called on every combat hit; the release curve does the rest.
func duck(amount: float = 1.0) -> void:
	_duck_amount = maxf(_duck_amount, clampf(amount, 0.0, 1.0))
	_duck_hold_left = DUCK_HOLD


## Current duck depth, 0 to 1. For tests and the debug overlay.
func duck_amount() -> float:
	return _duck_amount


## Set the zone reverb send, 0 to 1. Driven by [code]BiomeMood.reverb_wet[/code].
func set_reverb_wet(wet: float) -> void:
	_reverb_wet = clampf(wet, 0.0, 1.0)
	var index := AudioServer.get_bus_index(BUS_REVERB)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, lerpf(-80.0, REVERB_MAX_DB, _reverb_wet))


## Reverb send currently applied, 0 to 1.
func reverb_wet() -> float:
	return _reverb_wet


# --------------------------------------------------------------------------- internals


func _install_bus_layout() -> void:
	var layout := load("res://audio/buses/default_bus_layout.tres") as AudioBusLayout
	if layout != null:
		AudioServer.set_bus_layout(layout)
	else:
		Log.warn("AudioDirector", "no bus layout; falling back to Master only")


func _build_pools() -> void:
	_voice_priority.resize(POOL_SIZE)
	_voice_started.resize(POOL_SIZE)
	for index: int in POOL_SIZE:
		var voice := AudioStreamPlayer3D.new()
		voice.bus = String(BUS_SFX)
		add_child(voice)
		_pool.append(voice)
		_voice_priority[index] = -1
		_voice_started[index] = 0.0

	for _index: int in FLAT_POOL_SIZE:
		var flat := AudioStreamPlayer.new()
		flat.bus = String(BUS_UI)
		add_child(flat)
		_flat_pool.append(flat)


func _build_stems() -> void:
	_stem_targets.resize(STEM_COUNT)
	for index: int in STEM_COUNT:
		var stem := AudioStreamPlayer.new()
		stem.bus = String(BUS_MUSIC)
		stem.volume_db = -60.0
		add_child(stem)
		_stems.append(stem)
		_stem_targets[index] = -60.0


## Find a free voice, or steal the worst one.
##
## Stealing order: lowest priority first, then oldest. Never steals a voice of higher priority than
## the incoming sound, so a footstep can never silence a boss telegraph — it simply does not play,
## which is the right failure.
func _claim_voice(priority: int) -> int:
	for index: int in _pool.size():
		if not _pool[index].playing:
			return index

	var worst := -1
	var worst_priority := priority
	var worst_age := INF
	for index: int in _pool.size():
		var candidate := _voice_priority[index]
		if candidate > worst_priority:
			continue
		if candidate < worst_priority or _voice_started[index] < worst_age:
			worst = index
			worst_priority = candidate
			worst_age = _voice_started[index]
	return worst


func _rate_allows(bank: SoundBank) -> bool:
	if bank.min_interval <= 0.0:
		return true
	var now := float(Time.get_ticks_msec()) * 0.001
	var last: float = _last_played.get(bank.id, -999.0)
	if now - last < bank.min_interval:
		return false
	_last_played[bank.id] = now
	return true


func _advance_duck(delta: float) -> void:
	if _duck_hold_left > 0.0:
		_duck_hold_left -= delta
	elif _duck_amount > 0.0:
		_duck_amount = maxf(0.0, _duck_amount - delta / DUCK_RELEASE)

	var reduction := DUCK_TARGET_DB * _duck_amount
	for bus: StringName in [BUS_AMBIENCE, BUS_MUSIC]:
		var index := AudioServer.get_bus_index(bus)
		if index < 0:
			continue
		var base := -4.0 if bus == BUS_AMBIENCE else -2.0
		var target := base + reduction
		var current := AudioServer.get_bus_volume_db(index)
		var rate := DUCK_ATTACK if target < current else DUCK_RELEASE
		AudioServer.set_bus_volume_db(index, _approach(current, target, rate, delta))


func _advance_stems(delta: float) -> void:
	for index: int in _stems.size():
		var stem := _stems[index]
		var target := _stem_targets[index]
		if is_equal_approx(stem.volume_db, target):
			continue
		# Stems fade over roughly two seconds. Faster reads as a switch; slower and the player has
		# walked into the next room before the score notices.
		stem.volume_db = _approach(stem.volume_db, target, 2.0, delta)


## Frame-rate independent exponential approach, in dB.
func _approach(current: float, target: float, tau: float, delta: float) -> float:
	if tau <= 0.0:
		return target
	return lerpf(current, target, 1.0 - exp(-delta / tau))


func _on_damage_dealt(target: Node, packet: DamagePacket, result: DamagePacket.Result) -> void:
	if result == DamagePacket.Result.IMMUNE:
		return
	var node := target as Node3D
	var at := node.global_position if node != null else packet.impact_point

	var id := &"hit_flesh"
	if result == DamagePacket.Result.BLOCKED:
		id = &"hit_shield"
	elif result == DamagePacket.Result.PARRIED:
		id = &"parry"
	elif packet.is_riposte:
		id = &"hit_riposte"
	play_3d(id, at)

	# A riposte or parry ducks harder: those are the moments the mix should get out of the way of.
	duck(0.8 if packet.is_riposte or result == DamagePacket.Result.PARRIED else 0.45)


func _on_telegraph(enemy: Node, tell: StringName, _lead_time: float) -> void:
	var node := enemy as Node3D
	if node == null:
		return
	# Telegraphs are gameplay signals: they play through walls and at full volume, because the
	# Gravewretch lunge is meant to be survivable on audio alone.
	play_3d(tell, node.global_position)


func _on_boss_engaged(_boss: Node, _display_name: String) -> void:
	play_flat(&"boss_sting")
	duck(1.0)


func _on_mood_changed(mood: BiomeMood, _progress: float) -> void:
	if mood == null:
		return
	set_reverb_wet(mood.reverb_wet)
	set_stem_mask(mood.music_stem_mask)
