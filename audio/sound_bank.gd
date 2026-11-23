class_name SoundBank
extends Resource

## A named set of interchangeable takes for one sound, plus how it should be played.
##
## Variation is the entire difference between a footstep and machine-gun fire. Every bank holds
## several takes and picks between them **without repeating the last one**, and randomises pitch
## within a band. A single sample played 400 times a minute is the most fatiguing thing a game can
## do to a player's ears, and footsteps are exactly that frequent.

## Identifier the game asks for.
@export var id: StringName = &"none"

## Interchangeable takes. More is better; three is the practical floor for anything frequent.
@export var streams: Array[AudioStream] = []

## Bus this bank plays on.
@export var bus: StringName = &"SFX"

## Base volume, dB.
@export_range(-40.0, 12.0, 0.5) var volume_db: float = 0.0

## Random volume spread either side of the base, dB.
@export_range(0.0, 8.0, 0.1) var volume_jitter_db: float = 1.2

## Random pitch spread, as a multiplier either side of 1.0. Kept small — beyond about 0.12 a
## footstep starts sounding like a different surface rather than the same one twice.
@export_range(0.0, 0.4, 0.01) var pitch_jitter: float = 0.08

@export_group("Spatial")

## Distance at which the sound is at full volume, metres.
@export var unit_size: float = 6.0

## Maximum audible distance, metres. Zero means unlimited.
@export var max_distance: float = 40.0

## Attenuation curve. Inverse-square is physically right and almost always too aggressive for a
## sidescroller, where the camera sits 8 m back from everything.
@export var attenuation: int = 1

## When true this sound ignores walls and distance falloff entirely. Reserved for **gameplay
## signals** — the Bell-Bearer's bell has to be audible through a building or it is not a warning.
@export var is_gameplay_signal: bool = false

@export_group("Voice management")

## Higher priority steals a voice from a lower one when the pool is exhausted. Combat tells sit
## above footsteps, because losing a Gravewretch rattle to a puddle of grass sounds costs the player
## a life.
@export_range(0, 10, 1) var priority: int = 5

## Minimum seconds between two plays of this bank. Stops a multi-hit swing from firing six impact
## sounds in one frame and turning into a click.
@export var min_interval: float = 0.03

var _last_index: int = -1


## Pick a take, avoiding an immediate repeat.
##
## With two streams this alternates; with one it returns that one. Both are correct — the
## anti-repeat rule should never make a bank unplayable.
func pick(rng: RandomNumberGenerator) -> AudioStream:
	if streams.is_empty():
		return null
	if streams.size() == 1:
		return streams[0]

	var index := rng.randi() % streams.size()
	if index == _last_index:
		index = (index + 1) % streams.size()
	_last_index = index
	return streams[index]


## Volume for one play, including jitter.
func roll_volume(rng: RandomNumberGenerator) -> float:
	return volume_db + rng.randf_range(-volume_jitter_db, volume_jitter_db)


## Pitch scale for one play, including jitter.
func roll_pitch(rng: RandomNumberGenerator) -> float:
	return 1.0 + rng.randf_range(-pitch_jitter, pitch_jitter)
