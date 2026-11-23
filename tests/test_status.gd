extends GutTest

## Status build-up: the threshold, the tick, expiry, and the resistance rule.
##
## `StatusEffect` shipped in Phase 2 with a full contract — `tick_damage`, `on_apply`, `on_expire`,
## stacking, refresh — and no consumer anywhere in the project. Its own doc comment claimed
## `DamagePacket` had to be able to name one; `DamagePacket` had no such field. Wired 2026-08-15.

const ROT: StatusEffect = preload("res://data/status/status_rot.tres")


func _effect(
	trigger: int = 3, duration: float = 4.0, dps: float = 10.0, refreshes: bool = true
) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.id = &"test_rot"
	effect.duration = duration
	effect.damage_per_second = dps
	effect.stacks_to_trigger = trigger
	effect.refreshes = refreshes
	return effect


func _combatant() -> Combatant:
	var c := Combatant.new()
	c.stats = StatBlock.new()
	c.tuning = CombatTuning.new()
	c.max_poise = 40.0
	add_child_autofree(c)
	c.reset()
	return c


# ----------------------------------------------------------------- the threshold


func test_buildup_does_nothing_until_the_meter_fills() -> void:
	var tracker := StatusTracker.create(_effect(3))
	assert_false(tracker.apply(1.0), "one application is not enough")
	assert_false(tracker.apply(1.0), "nor two")
	assert_false(tracker.is_active, "still building")
	assert_almost_eq(tracker.buildup_fraction(), 0.666, 0.01, "and the meter reports two thirds")

	assert_true(tracker.apply(1.0), "the third triggers it")
	assert_true(tracker.is_active)
	assert_eq(tracker.buildup_fraction(), 1.0, "a triggered meter reads full")


func test_an_inactive_effect_deals_no_damage() -> void:
	# The whole point of a threshold: retreating before it fills costs the player nothing.
	var tracker := StatusTracker.create(_effect(3))
	tracker.apply(2.0)
	assert_eq(tracker.tick(1.0), 0.0, "building up is not the same as burning")


func test_a_triggered_effect_deals_damage_per_second() -> void:
	var tracker := StatusTracker.create(_effect(1, 4.0, 10.0))
	tracker.apply(1.0)
	assert_almost_eq(tracker.tick(0.5), 5.0, 0.001, "half a second of a 10 dps effect")


# ----------------------------------------------------------------- refresh and expiry


func test_reapplying_refreshes_rather_than_extending() -> void:
	var tracker := StatusTracker.create(_effect(1, 4.0))
	tracker.apply(1.0)
	tracker.tick(3.0)
	assert_almost_eq(tracker.remaining, 1.0, 0.001, "three of four seconds burned")

	assert_false(tracker.apply(1.0), "a re-application does not re-trigger")
	assert_almost_eq(tracker.remaining, 4.0, 0.001, "it resets the clock")


func test_a_non_refreshing_effect_runs_out_on_schedule() -> void:
	# Without this rule, standing in a rot cloud stacks duration forever and it never ends.
	var tracker := StatusTracker.create(_effect(1, 4.0, 10.0, false))
	tracker.apply(1.0)
	tracker.tick(3.0)
	tracker.apply(1.0)
	assert_almost_eq(tracker.remaining, 1.0, 0.001, "the clock keeps running")
	tracker.tick(1.0)
	assert_true(tracker.is_finished(), "and it expires on time")


# ----------------------------------------------------------------- combatant integration


func test_the_combatant_burns_only_after_the_threshold() -> void:
	var c := _combatant()
	var effect := _effect(3, 4.0, 10.0)
	var start := c.health

	c.apply_status(effect, 1.0)
	c.tick(1.0)
	assert_eq(c.health, start, "two thirds of a meter costs nothing")

	c.apply_status(effect, 2.0)
	assert_true(c.has_status(&"test_rot"), "the third application triggers it")
	c.tick(1.0)
	assert_almost_eq(c.health, start - 10.0, 0.01, "and now it burns")


func test_the_effect_expires_and_stops_burning() -> void:
	var c := _combatant()
	var effect := _effect(1, 2.0, 10.0)
	c.apply_status(effect, 1.0)

	watch_signals(c)
	c.tick(2.0)
	assert_signal_emitted(c, "status_expired", "expiry is announced")
	assert_false(c.has_status(&"test_rot"), "and it is gone")

	var settled := c.health
	c.tick(5.0)
	assert_almost_eq(c.health, settled, 0.01, "an expired effect must not keep ticking")


func test_a_zero_duration_effect_does_not_linger() -> void:
	# An instantaneous effect never reaches _tick_statuses, so it has to clean itself up on apply
	# or it sits at full build-up forever and can never be re-applied.
	var c := _combatant()
	c.apply_status(_effect(1, 0.0, 0.0), 1.0)
	assert_false(c.has_status(&"test_rot"), "it fired and finished in the same call")
	assert_eq(c.status_fraction(&"test_rot"), 0.0, "leaving no residue")


func test_reset_clears_status() -> void:
	# A respawned player must not still be rotting from the hit that killed them.
	var c := _combatant()
	c.apply_status(_effect(1, 8.0, 10.0), 1.0)
	assert_true(c.has_status(&"test_rot"))
	c.reset()
	assert_false(c.has_status(&"test_rot"), "respawning cleanses")


func test_status_never_applies_to_the_dead() -> void:
	var c := _combatant()
	c.apply_damage(99999.0)
	assert_true(c.is_dead)
	assert_false(c.apply_status(_effect(1), 1.0), "a corpse does not rot on the HUD")


# ----------------------------------------------------------------- the shipped resource


func test_the_rot_resource_is_authored_as_a_buildup() -> void:
	assert_eq(ROT.id, &"rot")
	assert_eq(ROT.damage_type, DamagePacket.Type.ROT, "rot damage, so rot resistance applies")
	assert_gt(ROT.stacks_to_trigger, 1, "a threshold, not an instant proc")
	assert_gt(ROT.damage_per_second, 0.0, "and it actually hurts once it lands")


func test_a_packet_can_name_a_status() -> void:
	# The claim StatusEffect's doc comment made for three phases before it was true.
	var packet := DamagePacket.create(10.0, 10.0, DamagePacket.Type.ROT, null, Vector3.ZERO)
	packet.status = ROT
	packet.status_buildup = 1.0
	assert_eq(packet.status.id, &"rot", "the packet carries it, so a Hurtbox never has to ask")
