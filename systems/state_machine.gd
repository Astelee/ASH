class_name StateMachine
extends Node

## Drives a set of [State] children. One actor, one machine, no nested string comparisons.
##
## Wire [member actor] and [member initial_state] in the inspector. Every [State] child is
## registered by its node name, so [code]transition_to(&"Jump")[/code] finds the child named
## [code]Jump[/code].

## Emitted after the transition completes, so listeners observe the new state as current.
signal state_changed(from: StringName, to: StringName)

## The node these states act upon. Injected into every child so no state walks the tree.
@export var actor: Node

## State entered on [method _ready]. Must be one of this node's [State] children.
@export var initial_state: State

## The state currently running. Null only before [method _ready].
var current_state: State

var _states: Dictionary[StringName, State] = {}


func _ready() -> void:
	for child: Node in get_children():
		var state := child as State
		if state == null:
			Log.warn("StateMachine", "%s is not a State and will be ignored" % child.name)
			continue
		_states[StringName(child.name)] = state
		state.machine = self
		state.setup()

	if initial_state == null:
		Log.error("StateMachine", "%s has no initial_state; machine is inert" % get_path())
		return

	current_state = initial_state
	current_state.enter(&"")


## Advance the current state one physics step, applying any transition it asks for.
##
## The actor calls this — the machine does not run its own [method Node._physics_process]. A child
## node would tick *after* its parent, so a self-driving machine would set velocity only after the
## actor had already moved on it, costing a frame of input latency.
func update(delta: float) -> void:
	if current_state == null:
		return
	var next := current_state.physics_update(delta)
	if next != &"":
		transition_to(next)


## Route an input event to the current state. Also actor-driven, for the same reason as
## [method update].
func route_input(event: InputEvent) -> void:
	if current_state == null:
		return
	var next := current_state.handle_input(event)
	if next != &"":
		transition_to(next)


## Switch to the state child named [param to]. A transition to the current state still re-runs
## [method State.exit] and [method State.enter] — self-transitions are how a combo restarts.
func transition_to(to: StringName) -> void:
	var target := _states.get(to) as State
	if target == null:
		Log.error("StateMachine", "no state named '%s' on %s" % [to, get_path()])
		return

	var from := StringName(current_state.name)
	current_state.exit()
	current_state = target
	current_state.enter(from)
	state_changed.emit(from, to)


## Name of the running state. Useful for the debug overlay; not for branching on.
func current_state_name() -> StringName:
	return StringName(current_state.name) if current_state != null else &""
