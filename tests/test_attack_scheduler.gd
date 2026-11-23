extends GutTest

## The attack-token system from docs/GDD.md §6.7 — the one mechanism standing between a fair fight
## and a mob pile-on.

var _scheduler: AttackScheduler


func before_each() -> void:
	_scheduler = AttackScheduler.new(2)


func test_first_two_requests_are_granted() -> void:
	assert_true(_scheduler.request(1), "first attacker swings")
	assert_true(_scheduler.request(2), "second attacker swings")
	assert_eq(_scheduler.active_count(), 2, "two tokens out")


func test_third_request_is_refused() -> void:
	_scheduler.request(1)
	_scheduler.request(2)
	assert_false(_scheduler.request(3), "third attacker waits")
	assert_eq(_scheduler.active_count(), 2, "never more than the cap")
	assert_eq(_scheduler.waiting_count(), 1, "and is queued, not dropped")


func test_never_exceeds_cap_under_load() -> void:
	# The acceptance criterion: three Husks, never more than two attacking.
	for id: int in range(1, 21):
		_scheduler.request(id, float(id))
	assert_eq(_scheduler.active_count(), 2, "twenty claimants, two tokens")


func test_release_promotes_a_waiter() -> void:
	_scheduler.request(1)
	_scheduler.request(2)
	_scheduler.request(3)
	_scheduler.release(1)
	assert_true(_scheduler.has_token(3), "the waiter is promoted immediately")
	assert_false(_scheduler.has_token(1), "and the releaser has given it up")
	assert_eq(_scheduler.active_count(), 2, "still capped")


func test_highest_score_wins_not_first_come() -> void:
	# Tokens go to the best approach angle, not the nearest or the earliest — the nearest enemy is
	# often the one standing behind the player.
	_scheduler.request(1, 0.0)
	_scheduler.request(2, 0.0)
	_scheduler.request(3, 0.1)
	_scheduler.request(4, 0.9)
	_scheduler.release(1)
	assert_true(_scheduler.has_token(4), "best-scoring waiter is promoted")
	assert_false(_scheduler.has_token(3), "the lower score keeps waiting")


func test_rerequesting_keeps_an_existing_token() -> void:
	_scheduler.request(1)
	assert_true(_scheduler.request(1, 5.0), "a holder refreshing does not lose its turn")
	assert_eq(_scheduler.active_count(), 1, "and does not consume a second token")


func test_release_of_a_waiter_removes_it_from_the_queue() -> void:
	# An enemy that dies or is poise-broken while queued must not be promoted later.
	_scheduler.request(1)
	_scheduler.request(2)
	_scheduler.request(3)
	_scheduler.release(3)
	assert_eq(_scheduler.waiting_count(), 0, "withdrawn")
	_scheduler.release(1)
	assert_false(_scheduler.has_token(3), "and never granted afterwards")


func test_poise_break_frees_the_token_immediately() -> void:
	_scheduler.request(1)
	_scheduler.request(2)
	_scheduler.request(3)
	# Staggering a mid-swing attacker must hand its slot to someone else, or breaking poise would
	# quietly reduce the pressure below the intended two.
	_scheduler.release(2)
	assert_eq(_scheduler.active_count(), 2, "the freed slot is refilled")
	assert_true(_scheduler.has_token(3))


func test_releasing_an_unknown_id_is_safe() -> void:
	_scheduler.release(99)
	assert_eq(_scheduler.active_count(), 0, "no crash, no phantom token")


func test_clear_drops_everything() -> void:
	_scheduler.request(1)
	_scheduler.request(2)
	_scheduler.request(3)
	_scheduler.clear()
	assert_eq(_scheduler.active_count(), 0)
	assert_eq(_scheduler.waiting_count(), 0)


func test_token_granted_signal_fires() -> void:
	watch_signals(_scheduler)
	_scheduler.request(7)
	assert_signal_emitted_with_parameters(_scheduler, "token_granted", [7])


func test_token_released_signal_fires() -> void:
	_scheduler.request(7)
	watch_signals(_scheduler)
	_scheduler.release(7)
	assert_signal_emitted_with_parameters(_scheduler, "token_released", [7])


func test_cap_of_one_serialises_attacks() -> void:
	var solo := AttackScheduler.new(1)
	solo.request(1)
	assert_false(solo.request(2), "a boss arena can serialise adds entirely")
