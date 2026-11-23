class_name State
extends Node

## Base class for every state in a [StateMachine].
##
## A state owns exactly one behaviour and one set of exit conditions. If a state needs a boolean
## flag to remember what it is doing, it is two states — see [code]CLAUDE.md §1[/code].
##
## Lifecycle: [method setup] once, then [method enter] / [method physics_update] / [method exit]
## per visit. Never call these yourself; the machine drives them.

## Set by the owning machine before [method setup] runs.
var machine: StateMachine


## Called once, after [member machine] is assigned and before any transition. Resolve typed
## references to the actor here rather than in [method _ready], which runs too early.
func setup() -> void:
	pass


## Entered this state. The argument is the state left behind, or [code]&""[/code] on the machine's
## initial state.
func enter(_previous: StringName) -> void:
	pass


## Leaving this state. Release anything [method enter] acquired.
func exit() -> void:
	pass


## Fixed-step update. Returns the state to transition into, or [code]&""[/code] to stay.
## Returning a name is the only sanctioned way to change state from inside one.
func physics_update(_delta: float) -> StringName:
	return &""


## Unhandled input for this state. Buffering belongs in the actor, not here.
func handle_input(_event: InputEvent) -> StringName:
	return &""
