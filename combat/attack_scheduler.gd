class_name AttackScheduler
extends RefCounted

## Hands out attack tokens. At most [member max_tokens] enemies may be swinging at once.
##
## This is the single system that separates a fair fight from a pile-on, so it is a plain
## [RefCounted] keyed on instance ids — no nodes, no scene tree, fully testable headless.
##
## Waiters are ranked by a caller-supplied score rather than by distance. The nearest enemy is often
## the one behind you; the *best* attacker is the one with a clean approach angle to the player's
## facing, and only the enemy can compute that.

## Emitted when [param id] is granted a token.
signal token_granted(id: int)

## Emitted when [param id] gives one up, for any reason.
signal token_released(id: int)

## Concurrent attackers allowed.
var max_tokens: int = 2

var _holders: Array[int] = []
var _waiters: Dictionary[int, float] = {}


func _init(tokens: int = 2) -> void:
	max_tokens = maxi(1, tokens)


## Ask for a token, or refresh the priority of an existing request. Returns true if a token is held
## immediately. A holder re-requesting keeps its token.
func request(id: int, score: float = 0.0) -> bool:
	if _holders.has(id):
		return true
	_waiters[id] = score
	_grant_available()
	return _holders.has(id)


## Give up a token or withdraw a pending request. Safe to call for an id that holds neither.
func release(id: int) -> void:
	var had_token := _holders.has(id)
	_holders.erase(id)
	_waiters.erase(id)
	if had_token:
		token_released.emit(id)
		_grant_available()


## True while [param id] may be in its attack.
func has_token(id: int) -> bool:
	return _holders.has(id)


## Tokens currently out. Never exceeds [member max_tokens].
func active_count() -> int:
	return _holders.size()


## Enemies queued for a token.
func waiting_count() -> int:
	return _waiters.size()


## Drop everything. For encounter resets and level teardown.
func clear() -> void:
	_holders.clear()
	_waiters.clear()


## Grant free tokens to the highest-scoring waiters.
##
## Called automatically on request and release; exposed so an encounter can re-evaluate after every
## enemy has updated its approach score for the frame.
func _grant_available() -> void:
	while _holders.size() < max_tokens and not _waiters.is_empty():
		var best := _best_waiter()
		_waiters.erase(best)
		_holders.append(best)
		token_granted.emit(best)


func _best_waiter() -> int:
	var best_id := -1
	var best_score := -INF
	for id: int in _waiters:
		var score: float = _waiters[id]
		if score > best_score:
			best_score = score
			best_id = id
	return best_id
