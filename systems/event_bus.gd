extends Node

## Global signal hub. The only sanctioned channel for cross-system communication.
##
## Rules (enforced in review, see [code]CLAUDE.md[/code]):
## [br]- Signals are named [code]<noun>_<past_tense_verb>[/code]: [code]player_died[/code],
##   [code]boss_phase_changed[/code], [code]ember_count_changed[/code].
## [br]- Payloads are typed. Prefer a single Resource/RefCounted argument over four primitives.
## [br]- The bus carries [i]facts about the past[/i], never commands. "Do X" is a direct call on
##   the system that owns X; "X happened" is a bus signal.
## [br]- A system may emit on the bus and listen on the bus, but must never assume another
##   listener exists. No return values, no ordering guarantees.
##
## Signals are declared here as each phase needs them.

## A defender caught an attacker inside the parry window. Phase 8 hangs the audio sting off this;
## Phase 7, the haptic pulse.
signal attack_parried(defender: Node, attacker: Node)

## An actor's poise pool emptied and it entered stagger.
signal poise_broken(actor: Node)

## Damage was resolved against an actor. Damage numbers listen; nothing acts on it.
signal damage_dealt(target: Node, packet: DamagePacket, result: DamagePacket.Result)

## An enemy died, carrying the Embers it dropped. Phase 3 credits the player from this.
signal enemy_died(enemy: Node, embers: int)

## The player died. GameState drops the bloodstain from this.
signal player_died(at: Vector3)

## The player rested. Levels respawn their world enemies on this; bosses ignore it.
signal rested_at_wayshrine(shrine_id: String)

## An enemy began a readable telegraph. Phase 8 hangs the audio tell off this — the Gravewretch's
## rattle and the Bell-Bearer's bell are gameplay signals, not decoration.
signal enemy_telegraphed(enemy: Node, tell: StringName, lead_time: float)

## A boss changed phase, carrying the new phase index.
signal boss_phase_changed(boss: Node, phase: int)

## A boss fight began. The HP bar and the fog gate both listen.
signal boss_engaged(boss: Node, display_name: String)

## Carried Embers changed, for the HUD.
signal embers_changed(current: int)

## Autoload scripts deliberately omit [code]class_name[/code]: a global class sharing a name with
## an autoload singleton is a hard parse error in Godot 4. This is the one documented exception
## to the "class_name on every reusable script" rule.
