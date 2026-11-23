extends Node

## Phase 2 integration check. Runs the real combat gym — three Husks, a real player, the real
## EncounterDirector — and asserts the acceptance criteria in docs/PLAN.md.
##
## The unit suites (test_damage, test_attack_scheduler) prove the maths in isolation. This proves
## the wiring: the numbers survive the trip through Hitbox → DamagePacket → Hurtbox → receive_hit,
## and that the token cap holds against live AI rather than against a loop of integers.

## Frames to observe the encounter before reporting.
const OBSERVE_FRAMES: int = 900

@export var director: EncounterDirector

var _frame: int = 0
var _failures: int = 0
var _peak_attackers: int = 0
var _saw_an_attack: bool = false
var _player: Player
var _husk: Enemy
var _reported: bool = false


func _ready() -> void:
	print("--- Phase 2 combat verification ---")
	_player = get_tree().get_first_node_in_group(&"player") as Player
	var enemies := get_tree().get_nodes_in_group(&"enemy")
	_husk = enemies[0] as Enemy if not enemies.is_empty() else null
	_assert(_player != null, "player present")
	_assert(enemies.size() == 3, "three Husks in the encounter")
	if director == null:
		director = get_tree().get_first_node_in_group(&"encounter") as EncounterDirector
	_assert(director != null, "encounter director present")


func _physics_process(_delta: float) -> void:
	if _reported:
		return
	_frame += 1

	var attacking := director.attacking_count()
	_peak_attackers = maxi(_peak_attackers, attacking)
	if attacking > 0:
		_saw_an_attack = true

	# The acceptance criterion, checked every single frame rather than sampled.
	if attacking > director.max_attackers:
		_assert(false, "token cap breached: %d attackers" % attacking)
		_reported = true
		_finish()
		return

	if _frame >= OBSERVE_FRAMES:
		_reported = true
		_check_damage_integration()
		_finish()


func _check_damage_integration() -> void:
	_assert(_saw_an_attack, "the Husks actually engaged")
	_assert(
		_peak_attackers <= 2, "never more than two attacked at once (peak %d)" % _peak_attackers
	)
	_assert(_peak_attackers == 2, "the cap was actually reached, so the test means something")
	_assert(_peak_attackers >= 1, "at least one attacked")

	if _husk == null or not is_instance_valid(_husk):
		_assert(false, "a Husk survived to be measured")
		return

	# Light-1 through the real resolution path: raw 53.55, Husk defence 24, no resist -> 43.19.
	_husk.combatant.reset()
	var before := _husk.combatant.health
	var packet := _light_one_packet()
	_husk.receive_hit(packet)
	var dealt := before - _husk.combatant.health
	_assert_close("light-1 versus a Husk", dealt, 43.1855, 0.05)

	# Riposte tier against a staggered target: x2.2 before mitigation -> 95.01.
	_husk.combatant.reset()
	_husk.combatant.is_staggered = true
	var before_riposte := _husk.combatant.health
	_husk.receive_hit(_light_one_packet())
	var riposte := before_riposte - _husk.combatant.health
	_assert_close("riposte on a staggered Husk", riposte, 95.0129, 0.05)
	_assert_close("riposte is 2.2x a normal hit", riposte / dealt, 2.2, 0.01)

	# Poise: the Husk's 40-point pool must break to a charged heavy and survive a single light.
	_husk.combatant.reset()
	_husk.combatant.apply_poise_damage(12.0)
	_assert(not _husk.combatant.is_staggered, "one light hit does not break a Husk's poise")
	_husk.combatant.apply_poise_damage(INF)
	_assert(_husk.combatant.is_staggered, "a charged heavy is a guaranteed break")


func _light_one_packet() -> DamagePacket:
	var raw := Damage.raw_damage(_player.weapon, _player.combatant.stats, 1.0, 1.0, 1.0)
	var packet := DamagePacket.create(
		raw, raw, DamagePacket.Type.PHYSICAL, _player, _husk.global_position
	)
	packet.poise_damage = 0.0
	return packet


func _finish() -> void:
	print("--- %s ---" % ("ALL PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


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
			"  %s  %-32s actual %8.4f  expected %8.4f"
			% ["PASS" if ok else "FAIL", label, actual, expected]
		)
	)
