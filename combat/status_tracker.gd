class_name StatusTracker
extends RefCounted

## One [StatusEffect] in flight on one [Combatant]: build-up, remaining time, stack count.
##
## Plain [RefCounted] with no scene dependency, per [code]CLAUDE.md §2[/code] — build-up thresholds
## and expiry are exactly the kind of thing that must be unit-testable without a tree.
##
## [b]Build-up is not damage-over-time.[/b] A Rot flask does nothing at all until the meter fills,
## then triggers. That threshold is what makes a build-up effect a resource the player can manage by
## retreating, rather than a slow tax they cannot respond to.

## The effect being tracked.
var effect: StatusEffect

## Applications accumulated so far, against [member StatusEffect.stacks_to_trigger].
var stacks: float = 0.0

## Seconds left once triggered. Meaningless before then.
var remaining: float = 0.0

## True once the meter filled and [method StatusEffect.on_apply] ran.
var is_active: bool = false


static func create(for_effect: StatusEffect) -> StatusTracker:
	var tracker := StatusTracker.new()
	tracker.effect = for_effect
	return tracker


## Add [param amount] to the build-up meter. Returns true when this application triggered it.
##
## Re-applying an already-active effect refreshes its timer when [member StatusEffect.refreshes] is
## set, and otherwise does nothing — without that rule, standing in a rot cloud would stack the
## duration indefinitely and the effect would never end.
func apply(amount: float) -> bool:
	if is_active:
		if effect.refreshes:
			remaining = effect.duration
		return false

	stacks += amount
	if stacks < float(effect.stacks_to_trigger):
		return false

	is_active = true
	remaining = effect.duration
	return true


## Advance by [param delta]. Returns the HP damage this effect deals over that slice.
func tick(delta: float) -> float:
	if not is_active:
		return 0.0
	remaining = maxf(0.0, remaining - delta)
	return effect.tick_damage(delta)


## True once the effect has run its course. A zero-duration effect is instantaneous: it fires its
## trigger and is finished in the same frame.
func is_finished() -> bool:
	return is_active and remaining <= 0.0


## Fraction of the build-up meter filled, 0–1. Drives the HUD build-up bar.
func buildup_fraction() -> float:
	if is_active:
		return 1.0
	return clampf(stacks / maxf(float(effect.stacks_to_trigger), 1.0), 0.0, 1.0)
