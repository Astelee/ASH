class_name Combatant
extends Node

## Health, stamina, poise, and hitstop for anything that fights. Composed into both the player and
## every enemy so the two share one implementation of the rules rather than two that drift.
##
## Holds no scene knowledge — it is driven by its owner's [method tick] call and reports outcomes
## through signals.

signal health_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)
signal poise_changed(current: float, maximum: float)

## Poise pool emptied. The owner should enter its stagger state.
signal poise_broken

## Health reached zero.
signal died

## Stamina emptied by a block. Distinct from [signal poise_broken] — different cause, same look.
signal guard_broken

## A build-up meter filled and its effect went live.
signal status_triggered(effect: StatusEffect)

## A build-up meter moved. Drives the HUD bar; carries the fraction so the HUD needs no lookup.
signal status_buildup_changed(effect: StatusEffect, fraction: float)

## An effect ran out or was cleansed.
signal status_expired(effect: StatusEffect)

## Stat block driving the derived pools. The player's is a live run copy; an enemy's comes from its
## [EnemyData].
@export var stats: StatBlock

## Shared combat constants.
@export var tuning: CombatTuning

## Poise pool. Not stat-derived — it is an armour and enemy-class property.
@export var max_poise: float = 40.0

## Flat damage reduction feeding the mitigation curve.
@export var defense: float = 0.0

## Use the enemy poise-regen profile rather than the player's faster one.
@export var use_enemy_poise_profile: bool = false

var health: float = 100.0
var stamina: float = 100.0
var poise: float = 40.0
var is_dead: bool = false
var is_staggered: bool = false

var _stamina_idle: float = 0.0
var _poise_idle: float = 0.0
var _hitstop: float = 0.0

# Trackers are allocated on application, never in tick(). CLAUDE.md §3 forbids per-frame
# allocation, and an enemy pack applying rot every swing is exactly the busy case that matters.
var _statuses: Array[StatusTracker] = []


func _ready() -> void:
	# Self-initialise only when authored in the scene, as the player's is. An enemy's comes from its
	# EnemyData, and a child is ready *before* its parent, so the owner calls [method configure]
	# instead. Erroring here would fire on every correctly-built enemy in the level.
	if stats != null:
		if tuning == null:
			tuning = CombatTuning.new()
		reset()


## Install a stat block and pools from an owner that holds them as data. Resets every pool.
func configure(
	block: StatBlock, rules: CombatTuning, poise_pool: float, armour: float, enemy_profile: bool
) -> void:
	stats = block if block != null else StatBlock.new()
	tuning = rules if rules != null else CombatTuning.new()
	max_poise = poise_pool
	defense = armour
	use_enemy_poise_profile = enemy_profile
	reset()


## Restore every pool to full. Wayshrine rest, and initial setup.
func reset() -> void:
	health = stats.max_health()
	stamina = stats.max_stamina()
	poise = max_poise
	is_dead = false
	is_staggered = false
	health_changed.emit(health, stats.max_health())
	stamina_changed.emit(stamina, stats.max_stamina())
	poise_changed.emit(poise, max_poise)
	# A respawned player must not still be rotting from the hit that killed them.
	clear_statuses()


## Advance timers. The owner calls this from its own physics step so freeze ordering stays explicit.
## Returns false while frozen by hitstop, which is the owner's cue to skip its state update.
func tick(delta: float) -> bool:
	if _hitstop > 0.0:
		_hitstop -= delta
		return false

	_stamina_idle += delta
	if _stamina_idle >= stats.stamina_regen_delay and stamina < stats.max_stamina():
		stamina = minf(stats.max_stamina(), stamina + stats.stamina_regen() * delta)
		stamina_changed.emit(stamina, stats.max_stamina())

	_poise_idle += delta
	var delay := tuning.enemy_poise_delay if use_enemy_poise_profile else tuning.player_poise_delay
	if _poise_idle >= delay and poise < max_poise:
		var rate := (
			tuning.enemy_poise_regen if use_enemy_poise_profile else tuning.player_poise_regen
		)
		poise = minf(max_poise, poise + rate * delta)
		poise_changed.emit(poise, max_poise)

	_tick_statuses(delta)
	return true


## Advance every active status and drop the finished ones.
##
## Iterated backwards so removal cannot skip an element, and damage is applied after the loop so an
## effect that kills the target cannot mutate the array mid-iteration.
func _tick_statuses(delta: float) -> void:
	if _statuses.is_empty():
		return

	var total := 0.0
	for i in range(_statuses.size() - 1, -1, -1):
		var tracker := _statuses[i]
		total += tracker.tick(delta)
		if tracker.is_finished():
			tracker.effect.on_expire(self)
			status_expired.emit(tracker.effect)
			_statuses.remove_at(i)

	if total > 0.0:
		apply_damage(total)


## Add [param amount] of build-up for [param effect]. Returns true if this application triggered it.
##
## The damage school is [i]not[/i] checked here — resistance is applied to the build-up amount by
## the caller, because a target with high rot resistance should fill the meter more slowly rather
## than take a weaker effect once it fills.
func apply_status(effect: StatusEffect, amount: float = 1.0) -> bool:
	if effect == null or is_dead:
		return false

	var tracker := _find_status(effect.id)
	if tracker == null:
		tracker = StatusTracker.create(effect)
		_statuses.append(tracker)

	var triggered := tracker.apply(amount)
	status_buildup_changed.emit(effect, tracker.buildup_fraction())
	if triggered:
		effect.on_apply(self)
		status_triggered.emit(effect)
		# A zero-duration effect is instantaneous: it fires and is gone in the same call, so it
		# never reaches _tick_statuses and would otherwise linger at full build-up forever.
		if tracker.is_finished():
			effect.on_expire(self)
			status_expired.emit(effect)
			_statuses.erase(tracker)
	return triggered


## The tracker for [param id], or null.
func _find_status(id: StringName) -> StatusTracker:
	for tracker: StatusTracker in _statuses:
		if tracker.effect.id == id:
			return tracker
	return null


## True while [param id] is triggered and running.
func has_status(id: StringName) -> bool:
	var tracker := _find_status(id)
	return tracker != null and tracker.is_active


## Build-up on [param id], 0–1. Zero when nothing has been applied.
func status_fraction(id: StringName) -> float:
	var tracker := _find_status(id)
	return 0.0 if tracker == null else tracker.buildup_fraction()


## Drop every status without running its expiry. Used by [method reset] and by cleanses.
func clear_statuses() -> void:
	for tracker: StatusTracker in _statuses:
		if tracker.is_active:
			tracker.effect.on_expire(self)
			status_expired.emit(tracker.effect)
	_statuses.clear()


## Apply HP damage. Emits [signal died] exactly once.
func apply_damage(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, stats.max_health())
	if health <= 0.0:
		is_dead = true
		died.emit()


## Apply poise damage. [code]INF[/code] is a guaranteed break. Emits [signal poise_broken] on empty.
func apply_poise_damage(amount: float) -> void:
	if is_dead:
		return
	_poise_idle = 0.0
	if Damage.breaks_poise(poise, amount):
		poise = 0.0
		is_staggered = true
		poise_changed.emit(poise, max_poise)
		poise_broken.emit()
		return
	poise = maxf(0.0, poise - amount)
	poise_changed.emit(poise, max_poise)


## Spend stamina. Returns false and spends nothing when the pool is too low.
func spend_stamina(amount: float) -> bool:
	if amount > stamina:
		return false
	stamina -= amount
	_stamina_idle = 0.0
	stamina_changed.emit(stamina, stats.max_stamina())
	return true


## Drain stamina without a sufficiency check, for blocks. Emits [signal guard_broken] on empty —
## a block always goes through, the question is what it costs.
func drain_stamina(amount: float) -> void:
	stamina = maxf(0.0, stamina - amount)
	_stamina_idle = 0.0
	stamina_changed.emit(stamina, stats.max_stamina())
	if stamina <= 0.0:
		is_staggered = true
		guard_broken.emit()


## Restore HP, capped at maximum. The flask's payload.
func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	health = minf(stats.max_health(), health + amount)
	health_changed.emit(health, stats.max_health())


## Refund stamina, as a successful parry does.
func gain_stamina(amount: float) -> void:
	stamina = minf(stats.max_stamina(), stamina + amount)
	stamina_changed.emit(stamina, stats.max_stamina())


## Restore poise and clear the stagger flag once the owner's stagger state ends.
func recover_stagger() -> void:
	is_staggered = false
	poise = max_poise
	poise_changed.emit(poise, max_poise)


## Freeze this actor for [param duration] seconds.
##
## Per-actor, never [member Engine.time_scale] — global time scaling desynchronises touch input and
## makes the whole game feel drunk ([code]CLAUDE.md §4.7[/code]).
func apply_hitstop(duration: float) -> void:
	_hitstop = maxf(_hitstop, duration)


## True while frozen by hitstop.
func is_frozen() -> bool:
	return _hitstop > 0.0


## Fraction of health remaining, 0–1. For HP bars and boss phase thresholds.
func health_fraction() -> float:
	var maximum := stats.max_health()
	return health / maximum if maximum > 0.0 else 0.0


## Fraction of stamina remaining, 0–1.
func stamina_fraction() -> float:
	var maximum := stats.max_stamina()
	return stamina / maximum if maximum > 0.0 else 0.0
