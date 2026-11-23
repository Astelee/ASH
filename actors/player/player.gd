class_name Player
extends CharacterBody3D

## The player actor. Owns physics, timers, and the shared vocabulary the states act through; the
## states own the decisions.
##
## Gameplay is constrained to the XY plane — Z is depth-lane staging only, so this body pins itself
## to Z = 0 every frame ([code]docs/GDD.md §4[/code]).

## Fired on touchdown with the fall distance in metres and the HP it cost. Damage is 0 for any fall
## at or under [member MovementTuning.fall_damage_threshold].
signal landed(fall_distance: float, damage: float)

## Fired whenever HP changes, so the debug overlay and later the HUD can react without polling.
signal health_changed(current: float, maximum: float)

## Emitted when a parry lands, carrying the attacker that was caught.
signal parried(attacker: Node)

const STATE_IDLE: StringName = &"Idle"
const STATE_RUN: StringName = &"Run"
const STATE_JUMP: StringName = &"Jump"
const STATE_FALL: StringName = &"Fall"
const STATE_LAND: StringName = &"Land"
const STATE_LEDGE_GRAB: StringName = &"LedgeGrab"
const STATE_ATTACK: StringName = &"Attack"
const STATE_HEAVY: StringName = &"Heavy"
const STATE_DODGE: StringName = &"Dodge"
const STATE_BLOCK: StringName = &"Block"
const STATE_STAGGER: StringName = &"Stagger"
const STATE_DEATH: StringName = &"Death"
const STATE_FLASK: StringName = &"Flask"

## Movement numbers. Without one the actor cannot move, so a missing resource is fatal and loud.
@export var tuning: MovementTuning

## Drives locomotion. Its [member StateMachine.actor] must point back at this node.
@export var state_machine: StateMachine

## Cast forward at chest height. A hit means there is a wall worth checking for a lip.
@export var ledge_wall_ray: RayCast3D

## Cast downward from beyond that wall. A hit means the wall has a top within reach.
@export var ledge_floor_ray: RayCast3D

## Visual root, flipped on the Y axis to face the direction of travel.
@export var body: Node3D

@export_group("Combat")

## Health, stamina, poise, and hitstop.
@export var combatant: Combatant

## Combat constants shared with every enemy.
@export var combat_tuning: CombatTuning

## Damageable volume. Its [member Hurtbox.invulnerable] flag is driven by the dodge i-frames.
@export var hurtbox: Hurtbox

## Attack volume, armed only during a move's active frames.
@export var hitbox: Hitbox

## Equipped weapon, supplying base damage and the scaling vector.
@export var weapon: WeaponData

## Equipped shield, supplying block absorption and stability.
@export var shield: ShieldData

## Light-attack chain, in order. Length defines the combo.
@export var light_combo: Array[AttackMove] = []

## Heavy attack, chargeable.
@export var heavy_move: AttackMove

## The move currently being swung, read by [method build_damage_packet].
var active_move: AttackMove

## Charge multiplier for the swing in progress.
var active_charge: float = 1.0

## True while the block state holds a guard up.
var is_blocking: bool = false

## Seconds since the block began, for the parry window.
var block_elapsed: float = 0.0

## +1 facing screen-right, −1 facing screen-left. Never 0.
var facing: int = 1

## Metres fallen since the apex of the current airborne period. Read by [Land] to size the recovery.
var fall_distance: float = 0.0

var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _apex_height: float = 0.0
var _was_on_floor: bool = true


func _ready() -> void:
	add_to_group(&"player")

	if tuning == null:
		Log.error("Player", "no MovementTuning assigned; falling back to defaults")
		tuning = MovementTuning.new()

	if combat_tuning == null:
		combat_tuning = CombatTuning.new()
	InputRouter.sprint_hold_threshold = tuning.sprint_hold_threshold

	if combatant != null:
		combatant.died.connect(_on_died)
		combatant.poise_broken.connect(_on_poise_broken)
		combatant.guard_broken.connect(_on_poise_broken)

	floor_max_angle = deg_to_rad(tuning.max_slope_deg)
	up_direction = Vector3.UP
	_apex_height = global_position.y

	# Both rays start inside our own capsule, so without this every cast hits the player first.
	for ray: RayCast3D in [ledge_wall_ray, ledge_floor_ray]:
		if ray != null:
			ray.add_exception(self)
	_configure_ledge_rays()


func _physics_process(delta: float) -> void:
	# Hitstop freezes this actor and only this actor. Gravity keeps running so a frozen airborne
	# fighter does not hang in the air; the state machine is what pauses.
	var running := combatant == null or combatant.tick(delta)

	_tick_timers(delta)
	_track_fall(delta)

	if state_machine != null and running:
		state_machine.update(delta)

	move_and_slide()

	# The action plane is Z = 0. Slides against angled geometry can nudge us off it.
	global_position.z = 0.0
	velocity.z = 0.0

	_detect_landing()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"jump"):
		_jump_buffer_timer = tuning.jump_buffer
	if state_machine != null:
		state_machine.route_input(event)


# --------------------------------------------------------------------------- intent


## Horizontal movement intent for this frame, −1 to +1.
func move_intent() -> float:
	return InputRouter.move_axis()


## Target horizontal speed given the current intent and whether sprint is held.
func target_speed() -> float:
	if InputRouter.is_sprinting(tuning.sprint_hold_threshold):
		return tuning.sprint_speed
	return tuning.walk_speed


# --------------------------------------------------------------------------- motion


## Accelerate horizontal velocity toward [param intent] × [method target_speed]. Uses the
## deceleration rate when the player is asking to stop, which is what makes stopping feel deliberate
## rather than icy.
func apply_horizontal(delta: float, intent: float) -> void:
	var desired := intent * target_speed()
	var rate := tuning.accel_for(is_on_floor())
	if is_zero_approx(intent):
		rate = tuning.ground_decel if is_on_floor() else tuning.ground_decel * tuning.air_control
	velocity.x = move_toward(velocity.x, desired, rate * delta)

	if not is_zero_approx(intent):
		set_facing(1 if intent > 0.0 else -1)


## Apply gravity for one step, lighter on the way up than on the way down, clamped to terminal
## velocity.
func apply_gravity(delta: float) -> void:
	var rising := velocity.y > 0.0
	velocity.y -= tuning.gravity_for(rising) * delta
	velocity.y = maxf(velocity.y, -tuning.terminal_velocity)


## Launch into a jump at the velocity that reaches the tuned apex height, and consume the buffer so
## one press cannot fire twice.
func do_jump() -> void:
	velocity.y = tuning.jump_velocity()
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	_apex_height = global_position.y


## Face [param direction] and mirror the visual root to match.
func set_facing(direction: int) -> void:
	if direction == 0 or direction == facing:
		return
	facing = direction
	if body != null:
		body.rotation.y = 0.0 if facing > 0 else PI


# --------------------------------------------------------------------------- forgiveness


## True while a jump is still legal after walking off a ledge.
func has_coyote() -> bool:
	return _coyote_timer > 0.0


## True if a jump was pressed recently enough to still count.
func has_buffered_jump() -> bool:
	return _jump_buffer_timer > 0.0


## True if the player may jump right now — grounded, or inside the coyote window.
func can_jump() -> bool:
	return is_on_floor() or has_coyote()


# --------------------------------------------------------------------------- ledges


## Look for a grabbable lip ahead. Only meaningful while falling; grabbing on the way up would let
## the player stick to every wall they brush.
func find_ledge() -> bool:
	if velocity.y > 0.0 or is_on_floor():
		return false
	if ledge_wall_ray == null or ledge_floor_ray == null:
		return false

	_configure_ledge_rays()
	ledge_wall_ray.force_raycast_update()
	ledge_floor_ray.force_raycast_update()

	if not ledge_wall_ray.is_colliding() or not ledge_floor_ray.is_colliding():
		return false

	# The lip has to sit near grab height. A floor found far below is a different platform.
	var lip_y := ledge_floor_ray.get_collision_point().y
	var grab_y := global_position.y + tuning.ledge_grab_height
	return absf(lip_y - grab_y) <= tuning.ledge_reach_down


## World position of the lip found by the last successful [method find_ledge].
func ledge_point() -> Vector3:
	return ledge_floor_ray.get_collision_point()


# --------------------------------------------------------------------------- damage


## Apply [param amount] HP of damage directly, bypassing armour. Fall damage only.
func take_damage(amount: float) -> void:
	if amount <= 0.0 or combatant == null:
		return
	combatant.apply_damage(amount)
	health_changed.emit(combatant.health, combatant.stats.max_health())


## Current HP.
func health() -> float:
	return combatant.health if combatant != null else 0.0


## Maximum HP.
func max_health() -> float:
	return combatant.stats.max_health() if combatant != null else 0.0


# --------------------------------------------------------------------------- combat contract


## Resolve an incoming hit. Called by [Hurtbox]; this is where parry, block, and poise are decided.
##
## Order matters and is not arbitrary: **parry beats block beats armour**. A parry is a strictly
## better outcome than a block on the same input, so checking block first would make the parry
## window unreachable.
func receive_hit(packet: DamagePacket) -> DamagePacket.Result:
	if combatant == null or combatant.is_dead:
		return DamagePacket.Result.IMMUNE

	if is_blocking and _is_facing(packet.source):
		var window := combat_tuning.parry_window_for_touch(InputRouter.is_touch_active())
		if block_elapsed <= window:
			combatant.gain_stamina(combat_tuning.parry_stamina_gain)
			# A direct call, not a bus signal: opening the riposte window is a command to the
			# attacker, and the bus carries facts, never orders (CLAUDE.md §2).
			if packet.source != null and packet.source.has_method(&"on_parried"):
				packet.source.call(&"on_parried")
			parried.emit(packet.source)
			EventBus.attack_parried.emit(self, packet.source)
			return DamagePacket.Result.PARRIED

		var through := Damage.after_block(packet.amount, shield, packet.type)
		var cost := Damage.block_stamina_cost(
			packet.raw_amount, shield, combatant.stats.might, combat_tuning
		)
		combatant.drain_stamina(cost)
		combatant.apply_damage(through)
		return DamagePacket.Result.BLOCKED

	combatant.apply_damage(packet.amount)
	combatant.apply_poise_damage(packet.poise_damage)
	# Rot build-up lands whether or not the blow staggered. Armour resistance is already folded into
	# packet.amount by Damage; the meter takes the raw application.
	if packet.status != null:
		combatant.apply_status(packet.status, packet.status_buildup)
	if packet.hitstop > 0.0:
		combatant.apply_hitstop(packet.hitstop)
	EventBus.damage_dealt.emit(self, packet, DamagePacket.Result.HIT)
	return DamagePacket.Result.HIT


## Build the packet for the swing in progress. Called by [Hitbox] on overlap.
##
## Resolution is deferred to the defender: this fills in raw damage and lets the target apply its
## own defence and resistances, because only it knows them.
func build_damage_packet() -> DamagePacket:
	if active_move == null or weapon == null:
		return null

	var raw := Damage.raw_damage(
		weapon, combatant.stats, active_move.damage_multiplier, active_charge, 1.0
	)
	var packet := DamagePacket.create(raw, raw, weapon.damage_type, self, global_position)
	if active_move.override_damage_type:
		packet.type = active_move.damage_type
	packet.poise_damage = (
		INF
		if active_move.breaks_poise_at(active_move.charge_max) and active_charge > 1.0
		else active_move.poise_damage
	)
	packet.hitstop = combat_tuning.hitstop_for(active_move.stamina_cost >= 25.0, false)
	return packet


## True when [param other] stands on the side this actor faces.
func _is_facing(other: Node) -> bool:
	var node := other as Node3D
	if node == null:
		return true
	return signf(node.global_position.x - global_position.x) == signf(float(facing))


func _on_died() -> void:
	state_machine.transition_to(STATE_DEATH)


func _on_poise_broken() -> void:
	if not combatant.is_dead:
		state_machine.transition_to(STATE_STAGGER)


# --------------------------------------------------------------------------- internals


func _tick_timers(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = tuning.coyote_time
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)
	_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)


func _track_fall(_delta: float) -> void:
	if is_on_floor():
		_apex_height = global_position.y
	else:
		_apex_height = maxf(_apex_height, global_position.y)


func _detect_landing() -> void:
	var grounded := is_on_floor()
	if grounded and not _was_on_floor:
		fall_distance = maxf(0.0, _apex_height - global_position.y)
		var damage := tuning.fall_damage_for(fall_distance)
		take_damage(damage)
		landed.emit(fall_distance, damage)
		_apex_height = global_position.y
	_was_on_floor = grounded


func _configure_ledge_rays() -> void:
	if ledge_wall_ray == null or ledge_floor_ray == null:
		return
	var reach := tuning.ledge_reach_forward
	var probe_lift := tuning.ledge_reach_down + 0.2

	ledge_wall_ray.position = Vector3(0.0, tuning.ledge_grab_height, 0.0)
	ledge_wall_ray.target_position = Vector3(float(facing) * reach, 0.0, 0.0)

	ledge_floor_ray.position = Vector3(
		float(facing) * reach, tuning.ledge_grab_height + probe_lift, 0.0
	)
	ledge_floor_ray.target_position = Vector3(0.0, -(probe_lift + tuning.ledge_reach_down), 0.0)
