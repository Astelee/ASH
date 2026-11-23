extends Node

## Phase 1 movement check. Drives the player through the movement table headlessly and asserts the
## physics produce the numbers in [code]docs/GDD.md §5[/code]. Run by [code]scripts/test.sh[/code];
## exits non-zero on any failure.
##
## Frame-driven rather than coroutine-driven: awaiting [signal SceneTree.physics_frame] from a
## custom [SceneTree] never ticks under [code]--headless[/code], it just hangs.
##
## [b]Interim harness.[/b] Phase 2 brings in GUT and this becomes a proper suite. It exists now
## because Phase 1's acceptance criteria are numeric — a jump that reaches 2.118 m instead of 2.2 m
## looks completely correct on screen, and only a measurement catches it. It did.

enum Phase { SETTLE, JUMP, COYOTE_ENTER, COYOTE_MEASURE, BUFFER_PRESS, BUFFER_WAIT, FALL, DONE }

const PHYSICS_STEP: float = 1.0 / 60.0

@export var player: Player

var _phase: Phase = Phase.SETTLE
var _frame: int = 0
var _failures: int = 0
var _peak: float = 0.0
var _start_y: float = 0.0
var _coyote_frames: int = 0
var _saw_coyote: bool = false
var _landed_distance: float = 0.0
var _landed_damage: float = 0.0
var _health_before_fall: float = 0.0


func _ready() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group(&"player") as Player
	player.landed.connect(_on_landed)
	print("--- Phase 1 movement verification ---")


func _physics_process(_delta: float) -> void:
	_frame += 1
	match _phase:
		Phase.SETTLE:
			if _frame == 1:
				_teleport(Vector3(8.0, 0.5, 0.0))
			if _frame >= 40:
				_start_y = player.global_position.y
				_peak = _start_y
				player.state_machine.transition_to(Player.STATE_JUMP)
				_advance(Phase.JUMP)

		Phase.JUMP:
			_peak = maxf(_peak, player.global_position.y)
			if _frame >= 100:
				_assert_close(
					"jump apex height", _peak - _start_y, player.tuning.jump_apex_height, 0.02
				)
				# 9.8387 continuous + half a step of gravity (22 / 120) for the 60 Hz integrator.
				_assert_close("jump velocity", player.tuning.jump_velocity(), 10.0220, 0.001)
				_teleport(Vector3(15.0, 0.5, 0.0))
				_advance(Phase.COYOTE_ENTER)

		Phase.COYOTE_ENTER:
			if _frame >= 20:
				# Walk off the end of GroundStart, which stops at x = 16.
				player.velocity.x = 5.0
				if not player.is_on_floor():
					_saw_coyote = player.has_coyote()
					_advance(Phase.COYOTE_MEASURE)
				elif _frame >= 90:
					_assert(false, "player reached the ledge edge")
					_advance(Phase.BUFFER_PRESS)

		Phase.COYOTE_MEASURE:
			if player.has_coyote() and not player.is_on_floor():
				_coyote_frames += 1
			else:
				_assert(_saw_coyote, "coyote window opens after walking off a ledge")
				_assert_close(
					"coyote window length",
					float(_coyote_frames) * PHYSICS_STEP,
					player.tuning.coyote_time,
					0.035
				)
				_teleport(Vector3(8.0, 5.0, 0.0))
				_advance(Phase.BUFFER_PRESS)

		Phase.BUFFER_PRESS:
			# Drop from a height whose fall time (~0.135 s) is inside the 0.15 s buffer. Pressing
			# from higher up would expire the buffer legitimately and prove nothing.
			_teleport(Vector3(8.0, 1.0, 0.0))
			player.velocity.y = -5.0
			_press(&"jump")
			_advance(Phase.BUFFER_WAIT)

		Phase.BUFFER_WAIT:
			if _frame == 2:
				_assert(player.has_buffered_jump(), "jump press is buffered while airborne")
				_release(&"jump")
			if player.state_machine.current_state_name() == Player.STATE_JUMP:
				_assert(true, "buffered jump fires on the landing frame")
				_teleport(Vector3(8.0, 11.0, 0.0))
				player.combatant.reset()
				_health_before_fall = player.health()
				_advance(Phase.FALL)
			elif _frame >= 120:
				_assert(false, "buffered jump fires on the landing frame")
				_teleport(Vector3(8.0, 11.0, 0.0))
				player.combatant.reset()
				_health_before_fall = player.health()
				_advance(Phase.FALL)

		Phase.FALL:
			if _landed_distance > 0.0:
				_assert_close("fall distance measured", _landed_distance, 11.0, 0.4)
				_assert_close(
					"fall damage applied",
					_landed_damage,
					player.tuning.fall_damage_for(_landed_distance),
					0.01
				)
				_assert(_landed_damage > 0.0, "an 11 m drop exceeds the 6 m threshold and hurts")
				_assert_close(
					"health after fall", player.health(), _health_before_fall - _landed_damage, 0.01
				)
				_advance(Phase.DONE)
			elif _frame >= 240:
				_assert(false, "player landed within 4 s")
				_advance(Phase.DONE)

		Phase.DONE:
			print("--- %s ---" % ("ALL PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
			get_tree().quit(1 if _failures > 0 else 0)


func _on_landed(distance: float, damage: float) -> void:
	if _phase == Phase.FALL:
		_landed_distance = distance
		_landed_damage = damage


func _advance(to: Phase) -> void:
	_phase = to
	_frame = 0


func _teleport(position: Vector3) -> void:
	player.global_position = position
	player.velocity = Vector3.ZERO


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


func _release(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)


func _assert(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
	print("  %s  %s" % ["PASS" if condition else "FAIL", label])


func _assert_close(label: String, actual: float, expected: float, tolerance: float) -> void:
	var ok := absf(actual - expected) <= tolerance
	if not ok:
		_failures += 1
	print(
		(
			"  %s  %-26s actual %8.4f  expected %8.4f  (+/- %.3f)"
			% ["PASS" if ok else "FAIL", label, actual, expected, tolerance]
		)
	)
