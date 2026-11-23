extends Node

## Owns the Low/Mid/High tier table, applies it, and runs dynamic resolution.
##
## Tier values are the table in [code]docs/TECH.md §5[/code]. The dynamic-resolution rule and its
## one exception — never adjust during a boss telegraph — are why this is a system rather than a
## settings screen.

## Emitted after a tier change has been applied.
signal tier_changed(tier: Tier)

## Emitted when dynamic resolution moves the render scale.
signal scale_changed(scale: float)

enum Tier { LOW, MID, HIGH }

## Frames averaged before acting. At 60 Hz this is half a second of evidence.
const SAMPLE_WINDOW: int = 30

## Seconds over budget before the scale drops.
const DROP_AFTER: float = 2.0

## Seconds of headroom before the scale recovers. Slower than the drop, so the resolution does not
## oscillate around the threshold.
const RECOVER_AFTER: float = 4.0

## Step taken on a drop.
const DROP_STEP: float = 0.05

## Step taken on a recovery. Half the drop, for the same reason.
const RECOVER_STEP: float = 0.02

## Hard floor. Below this the image falls apart faster than the frame rate improves.
const SCALE_FLOOR: float = 0.60

## Per-tier settings. One table, read by everything.
const TIERS: Dictionary[Tier, Dictionary] = {
	Tier.LOW:
	{
		"target_fps": 30,
		"render_scale": 0.65,
		"msaa": Viewport.MSAA_DISABLED,
		"shadows_enabled": false,
		"shadow_size": 0,
		"shadow_splits": 0,
		"fog_card_fraction": 0.25,
		"glow_enabled": false,
		"glow_levels": 0,
		"screen_texture_fx": false,
	},
	Tier.MID:
	{
		"target_fps": 60,
		"render_scale": 0.80,
		"msaa": Viewport.MSAA_2X,
		"shadows_enabled": true,
		"shadow_size": 1024,
		"shadow_splits": 1,
		"fog_card_fraction": 0.60,
		# Off, deliberately. Enabling glow allocates a mip chain of the whole framebuffer, measured
		# at 16 MB against a 60 MB texture budget on the Ashfall Village scene. MID is the tier the
		# budget is defined on, and bloom is not worth a quarter of it.
		"glow_enabled": false,
		"glow_levels": 0,
		"screen_texture_fx": false,
	},
	Tier.HIGH:
	{
		"target_fps": 60,
		"render_scale": 1.00,
		"msaa": Viewport.MSAA_4X,
		"shadows_enabled": true,
		"shadow_size": 2048,
		"shadow_splits": 2,
		"fog_card_fraction": 1.00,
		"glow_enabled": true,
		"glow_levels": 5,
		"screen_texture_fx": true,
	},
}

## Current dynamic render scale, before the tier's base is applied.
var render_scale: float = 1.0

## While true, dynamic resolution holds still. Bosses raise this for the length of a wind-up: a
## resolution pop mid-telegraph reads as a dropped frame and gets the player killed.
var hold_resolution: bool = false

var _tier: Tier = Tier.MID
var _samples: PackedFloat32Array = PackedFloat32Array()
var _sample_index: int = 0
var _over_budget_for: float = 0.0
var _under_budget_for: float = 0.0


func _ready() -> void:
	_samples.resize(SAMPLE_WINDOW)
	apply(_tier)


func _process(delta: float) -> void:
	_record(delta)
	if hold_resolution:
		return
	_adjust(delta)


## Switch to [param to] and apply everything it governs.
func apply(to: Tier) -> void:
	_tier = to
	var settings := TIERS[to]

	Engine.max_fps = settings["target_fps"]
	render_scale = settings["render_scale"]

	var viewport := get_viewport()
	if viewport != null:
		viewport.scaling_3d_scale = render_scale
		viewport.msaa_3d = settings["msaa"]

	ProjectSettings.set_setting(
		"rendering/lights_and_shadows/directional_shadow/size", settings["shadow_size"]
	)

	_over_budget_for = 0.0
	_under_budget_for = 0.0
	Log.info(
		"QualityManager",
		"tier %s, %d fps, scale %.2f" % [tier_name(), Engine.max_fps, render_scale]
	)
	tier_changed.emit(_tier)


## The active tier.
func tier() -> Tier:
	return _tier


## Active tier as a display string.
func tier_name() -> String:
	return Tier.find_key(_tier) as String


## A single setting from the active tier's row.
func setting(key: String) -> Variant:
	return TIERS[_tier].get(key)


## Frame budget for the active tier, milliseconds. 16.6 at 60 FPS, 33.3 at 30.
func frame_budget_ms() -> float:
	return 1000.0 / float(TIERS[_tier]["target_fps"])


## Fraction of authored fog cards this tier draws.
func fog_card_fraction() -> float:
	return TIERS[_tier]["fog_card_fraction"]


## True when this tier may use effects that force a screen copy — water refraction, chiefly.
func allows_screen_texture() -> bool:
	return TIERS[_tier]["screen_texture_fx"]


## Rolling average frame time over the sample window, milliseconds.
func average_frame_ms() -> float:
	var total := 0.0
	for value: float in _samples:
		total += value
	return total / float(_samples.size()) if _samples.size() > 0 else 0.0


## Pick a tier from a measured average frame time. Used by the Phase 4 benchmark scene and by the
## settings screen's "re-detect" button.
##
## Deliberately conservative: a device that only just manages Mid on a stress scene will not manage
## it in a real fight with a boss and adds.
static func tier_for_frame_ms(measured_ms: float) -> Tier:
	if measured_ms <= 10.0:
		return Tier.HIGH
	if measured_ms <= 18.0:
		return Tier.MID
	return Tier.LOW


func _record(delta: float) -> void:
	_samples[_sample_index] = delta * 1000.0
	_sample_index = (_sample_index + 1) % _samples.size()


func _adjust(delta: float) -> void:
	var budget := frame_budget_ms()
	var average := average_frame_ms()
	var base: float = TIERS[_tier]["render_scale"]

	if average > budget:
		_under_budget_for = 0.0
		_over_budget_for += delta
		if _over_budget_for >= DROP_AFTER and render_scale > SCALE_FLOOR:
			_set_scale(maxf(SCALE_FLOOR, render_scale - DROP_STEP))
			_over_budget_for = 0.0
		return

	_over_budget_for = 0.0
	_under_budget_for += delta
	if _under_budget_for >= RECOVER_AFTER and render_scale < base:
		_set_scale(minf(base, render_scale + RECOVER_STEP))
		_under_budget_for = 0.0


func _set_scale(value: float) -> void:
	if is_equal_approx(value, render_scale):
		return
	render_scale = value
	var viewport := get_viewport()
	if viewport != null:
		viewport.scaling_3d_scale = render_scale
	scale_changed.emit(render_scale)
