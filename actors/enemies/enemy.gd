class_name Enemy
extends CharacterBody3D

## One enemy scene driving every variant. Behaviour comes from [member data]; adding a Husk elite
## means adding a [code].tres[/code], never a script ([code]CLAUDE.md §1[/code]).
##
## Speaks the same combat vocabulary as the player — [Hitbox], [Hurtbox], [DamagePacket] — and knows
## nothing else about it. The target is resolved by group lookup, so an enemy dropped into an empty
## scene idles instead of crashing.

const STATE_IDLE: StringName = &"Idle"
const STATE_ALERT: StringName = &"Alert"
const STATE_APPROACH: StringName = &"Approach"
const STATE_ATTACK: StringName = &"Attack"
const STATE_RECOVER: StringName = &"Recover"
const STATE_REPOSITION: StringName = &"Reposition"
const STATE_STAGGER: StringName = &"Stagger"
const STATE_DEAD: StringName = &"Dead"
const STATE_RANGED: StringName = &"Ranged"
const STATE_RETREAT: StringName = &"Retreat"
const STATE_LUNGE: StringName = &"Lunge"

## Everything this enemy is.
@export var data: EnemyData

## Shared combat constants.
@export var combat_tuning: CombatTuning

@export var state_machine: StateMachine
@export var combatant: Combatant
@export var hitbox: Hitbox
@export var hurtbox: Hurtbox
@export var body: Node3D

## +1 facing screen-right, −1 left.
var facing: int = -1

## The player, resolved lazily. Null in a scene without one, which must not crash.
var target: Node3D

## Move being swung, read by [method build_damage_packet].
var active_move: AttackMove

## Set while a parry has left this enemy open. The player's riposte reads it.
var riposte_vulnerable: float = 0.0

## Extra damage granted by a nearby Bell-Bearer. Recomputed each frame by the aura.
var aura_bonus: float = 0.0

## While true the shield is up and frontal hits are absorbed. Dropped during the attack windup, so
## a Warden is only safe when it is not committing.
var guard_up: bool = true

var _scheduler: AttackScheduler


func _ready() -> void:
	add_to_group(&"enemy")
	if data == null:
		Log.error("Enemy", "%s has no EnemyData; idling" % name)
		data = EnemyData.new()
	if combat_tuning == null:
		combat_tuning = CombatTuning.new()

	if combatant != null:
		combatant.configure(data.stats, combat_tuning, data.max_poise, data.defense, true)
		combatant.died.connect(_on_died)
		combatant.poise_broken.connect(_on_poise_broken)

	# An encounter volume injects its own scheduler on spawn; a hand-placed enemy falls back to the
	# level-wide director. With neither it attacks freely, which keeps a lone enemy runnable on F6.
	if _scheduler == null:
		var director := get_tree().get_first_node_in_group(&"encounter") as EncounterDirector
		if director != null:
			_scheduler = director.scheduler


func _physics_process(delta: float) -> void:
	var running := combatant == null or combatant.tick(delta)
	riposte_vulnerable = maxf(0.0, riposte_vulnerable - delta)

	if not is_on_floor():
		velocity.y -= data_gravity() * delta
	else:
		velocity.y = -2.0

	if state_machine != null and running:
		state_machine.update(delta)

	move_and_slide()
	global_position.z = 0.0
	velocity.z = 0.0


## Gravity for enemies. Shares the project default rather than a per-enemy tuning value — nothing in
## the design asks for enemies that fall differently.
func data_gravity() -> float:
	return ProjectSettings.get_setting("physics/3d/default_gravity", 22.0)


## The player, or null. Cached once found.
func resolve_target() -> Node3D:
	if is_instance_valid(target):
		return target
	target = get_tree().get_first_node_in_group(&"player") as Node3D
	return target


## Horizontal distance to the target, or INF when there is none.
func distance_to_target() -> float:
	var node := resolve_target()
	if node == null:
		return INF
	return absf(node.global_position.x - global_position.x)


## Turn to face the target.
func face_target() -> void:
	var node := resolve_target()
	if node == null:
		return
	set_facing(-1 if node.global_position.x < global_position.x else 1)


## Face [param direction] and mirror the visual root.
func set_facing(direction: int) -> void:
	if direction == 0 or direction == facing:
		return
	facing = direction
	if body != null:
		body.rotation.y = 0.0 if facing > 0 else PI


## Walk toward [param goal_x] at the tuned speed. Returns true once within [param tolerance].
func walk_toward(goal_x: float, tolerance: float, delta: float) -> bool:
	var gap := goal_x - global_position.x
	if absf(gap) <= tolerance:
		velocity.x = move_toward(velocity.x, 0.0, data.move_speed * 6.0 * delta)
		return true
	velocity.x = signf(gap) * data.move_speed
	set_facing(1 if gap > 0.0 else -1)
	return false


# --------------------------------------------------------------------------- attack tokens


## Attach this enemy to a specific scheduler. Called by [EncounterVolume] before the enemy is ready,
## so a group shares one token pool independent of any level-wide director.
func bind_scheduler(scheduler: AttackScheduler) -> void:
	_scheduler = scheduler


## Ask the encounter for permission to attack.
##
## The score is the approach angle, not the distance: the nearest enemy is frequently the one behind
## the player, and giving it the token produces the off-screen hits that make a fight feel unfair.
func request_attack_token() -> bool:
	if _scheduler == null:
		return true
	return _scheduler.request(get_instance_id(), approach_score())


## Give the token back. Safe to call when none is held.
func release_attack_token() -> void:
	if _scheduler != null:
		_scheduler.release(get_instance_id())


## True while this enemy holds a token.
func has_attack_token() -> bool:
	return _scheduler == null or _scheduler.has_token(get_instance_id())


## Higher is a better attacker: standing in front of the player and close, rather than merely close.
func approach_score() -> float:
	var node := resolve_target()
	if node == null:
		return 0.0
	var player := node as Player
	var offset := global_position.x - node.global_position.x
	var in_front := player == null or signf(offset) == signf(float(player.facing))
	var proximity := 1.0 / maxf(1.0, absf(offset))
	return proximity + (1.0 if in_front else 0.0)


# --------------------------------------------------------------------------- combat contract


## Resolve an incoming hit. Enemies do not block; a parry against them is the player's business.
func receive_hit(packet: DamagePacket) -> DamagePacket.Result:
	if combatant == null or combatant.is_dead:
		return DamagePacket.Result.IMMUNE

	# A staggered or parried enemy takes riposte-tier damage. This is the payoff for both mechanics
	# and the reason breaking poise is worth building around.
	var multiplier := 1.0
	if combatant.is_staggered or riposte_vulnerable > 0.0:
		multiplier = combat_tuning.riposte_multiplier

	var resolved := Damage.after_defense(
		packet.raw_amount * multiplier, data.defense, data.resist_for(packet.type)
	)

	# A raised shield only helps against blows arriving from the front. Flanking a Warden is the
	# alternative to parrying it, and both have to actually work or the enemy is a wall.
	if (
		data.shield_absorption > 0.0
		and guard_up
		and multiplier <= 1.0
		and _struck_from_front(packet)
	):
		resolved = maxf(Damage.MINIMUM_DAMAGE, resolved * (1.0 - data.shield_absorption))
		packet.amount = resolved
		combatant.apply_damage(resolved)
		EventBus.damage_dealt.emit(self, packet, DamagePacket.Result.BLOCKED)
		return DamagePacket.Result.BLOCKED
	combatant.apply_damage(resolved)
	combatant.apply_poise_damage(packet.poise_damage)
	_apply_status(packet)
	combatant.apply_hitstop(
		combat_tuning.hitstop_for(packet.poise_damage >= 30.0, multiplier > 1.0)
	)

	packet.amount = resolved
	packet.is_riposte = multiplier > 1.0
	EventBus.damage_dealt.emit(self, packet, DamagePacket.Result.HIT)
	return DamagePacket.Result.HIT


## Feed the packet's status build-up into the combatant, scaled by this enemy's resistance.
##
## Resistance slows the METER rather than weakening the effect. A rot-resistant enemy should take
## longer to succumb, not succumb to a milder rot -- otherwise high resistance would silently change
## what the effect does instead of how hard it is to land.
func _apply_status(packet: DamagePacket) -> void:
	if packet.status == null or combatant == null:
		return
	var resist := data.resist_for(packet.status.damage_type)
	combatant.apply_status(packet.status, packet.status_buildup * (1.0 - resist))


## Build the packet for the swing in progress.
func build_damage_packet() -> DamagePacket:
	if active_move == null or data.weapon == null:
		return null
	var raw := Damage.raw_damage(
		data.weapon, data.stats, active_move.damage_multiplier * damage_multiplier(), 1.0, 1.0
	)
	var packet := DamagePacket.create(raw, raw, data.weapon.damage_type, self, global_position)
	packet.poise_damage = active_move.poise_damage
	packet.hitstop = combat_tuning.hitstop_light
	packet.status = data.inflicts
	packet.status_buildup = data.inflict_buildup
	return packet


## True when [param packet] came from the side this enemy is facing.
func _struck_from_front(packet: DamagePacket) -> bool:
	var source := packet.source as Node3D
	if source == null:
		return true
	return signf(source.global_position.x - global_position.x) == signf(float(facing))


## The state this enemy commits from, given its archetype. One routing decision in one place
## rather than the same three-way branch copied into Approach and Reposition.
func commit_state() -> StringName:
	if data.is_ranged:
		return STATE_RANGED
	if data.lunges_from_offscreen:
		return STATE_LUNGE
	return STATE_ATTACK


## Distance at which this enemy commits.
##
## Ranged and lunging archetypes already carry a much larger [member EnemyData.attack_range] in
## their data -- the Cultist throws from 9 m, the Husk swings from 1.9 -- so this is one lookup
## rather than a branch. It stays a method because a future archetype may want to scale it.
func commit_range() -> float:
	return data.attack_range


## True when the player has closed inside a ranged enemy's comfort zone.
func should_retreat() -> bool:
	return data.is_ranged and distance_to_target() < data.retreat_range


## Damage multiplier this enemy currently swings with, including any Bell-Bearer aura.
func damage_multiplier() -> float:
	return 1.0 + aura_bonus


## Called when the player parries this enemy's swing. Opens the riposte window.
func on_parried() -> void:
	riposte_vulnerable = combat_tuning.riposte_window
	release_attack_token()
	state_machine.transition_to(STATE_STAGGER)


func _on_died() -> void:
	release_attack_token()
	EventBus.enemy_died.emit(self, data.ember_drop)
	state_machine.transition_to(STATE_DEAD)


func _on_poise_broken() -> void:
	if combatant.is_dead:
		return
	# Dropping the token on a break is what stops staggering an attacker from quietly lowering the
	# pressure below the intended two.
	release_attack_token()
	EventBus.poise_broken.emit(self)
	state_machine.transition_to(STATE_STAGGER)
