class_name Boss
extends Enemy

## A multi-phase boss. Ser Cadwyn the Rusted is the first; the structure is shared.
##
## Extends [Enemy] rather than replacing it, so a boss uses the same hitboxes, the same damage
## resolution, and the same state machine vocabulary as a Husk. What it adds is phases, a persistent
## defeat record, and a hold on dynamic resolution during telegraphs.

## Emitted when the boss enters a new phase.
signal phase_changed(phase: int)

## Save identifier, recorded in [code]GameState.bosses_defeated[/code]. That record survives death
## and rest — clearing a boss stays cleared.
@export var boss_id: String = "cadwyn"

## Shown on the HP bar.
@export var display_name: String = "Ser Cadwyn the Rusted"

## Health fractions at which each later phase begins, descending. [code][0.55][/code] gives two.
@export var phase_thresholds: Array[float] = [0.55]

## Moveset per phase. Index 0 is phase 1; a phase with no entry keeps the previous moveset.
@export var phase_movesets: Array[AttackMove] = []

## Adds spawned when a later phase begins.
@export var add_scene: PackedScene

## How many adds each phase transition brings.
@export var adds_per_phase: int = 2

## Seconds the boss is invulnerable and staggered during a phase transition.
@export var transition_duration: float = 2.0

## Current phase, 1-based.
var phase: int = 1

## True while a phase transition is playing.
var transitioning: bool = false


func _ready() -> void:
	super()
	add_to_group(&"boss")

	if GameState.is_boss_defeated(boss_id):
		# Already killed this run. The arena should be empty, not repopulated.
		queue_free()
		return

	combatant.health_changed.connect(_on_health_changed)
	EventBus.boss_engaged.emit(self, display_name)


## Advance to [param next]: a brief invulnerable stagger, a new moveset, and adds.
func enter_phase(next: int) -> void:
	if next <= phase or transitioning:
		return
	phase = next
	transitioning = true

	hurtbox.invulnerable = true
	hitbox.disarm()
	release_attack_token()
	velocity.x = 0.0

	if phase - 1 < phase_movesets.size():
		var move := phase_movesets[phase - 1]
		if move != null:
			var swapped: Array[AttackMove] = [move]
			data.moveset = swapped

	_spawn_adds()

	phase_changed.emit(phase)
	EventBus.boss_phase_changed.emit(self, phase)
	Log.info("Boss", "%s entered phase %d" % [boss_id, phase])

	get_tree().create_timer(transition_duration).timeout.connect(_end_transition)


## Hold dynamic resolution for [param seconds]. Called at the start of every telegraph.
##
## A resolution change mid-wind-up reads as a dropped frame, and against a boss that is the
## difference between reading the tell and dying to it.
func hold_resolution_for(seconds: float) -> void:
	QualityManager.hold_resolution = true
	get_tree().create_timer(seconds).timeout.connect(_release_resolution)


## Fraction of the shared pool remaining, for the HP bar.
func health_fraction() -> float:
	return combatant.health_fraction() if combatant != null else 0.0


func _release_resolution() -> void:
	QualityManager.hold_resolution = false


func _end_transition() -> void:
	transitioning = false
	if hurtbox != null:
		hurtbox.invulnerable = false
	if combatant != null:
		combatant.recover_stagger()


func _spawn_adds() -> void:
	if add_scene == null or adds_per_phase <= 0:
		return
	for index: int in adds_per_phase:
		var add := add_scene.instantiate() as Enemy
		if add == null:
			continue
		get_parent().add_child(add)
		var side := 1.0 if index % 2 == 0 else -1.0
		add.global_position = global_position + Vector3(side * 5.0, 0.5, 0.0)


func _on_health_changed(_current: float, _maximum: float) -> void:
	if transitioning or combatant.is_dead:
		return
	var fraction := combatant.health_fraction()
	for index: int in phase_thresholds.size():
		var threshold: float = phase_thresholds[index]
		if fraction <= threshold and phase <= index + 1:
			enter_phase(index + 2)
			return


func _on_died() -> void:
	# Recorded before the base class frees anything, so a crash during the death sequence still
	# counts the kill. Re-fighting a boss you already beat is the worst bug this genre has.
	GameState.record_boss_defeat(boss_id)
	SaveSystem.autosave("boss_defeated")
	QualityManager.hold_resolution = false
	super()
