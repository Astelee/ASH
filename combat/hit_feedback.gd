class_name HitFeedback
extends Node

## Drives the character shader's per-instance feedback uniforms: hit flash, poise-break glow, and
## the death dissolve.
##
## Presentation only. It reads combat facts and writes shader parameters; it decides nothing and
## nothing depends on it, so an actor without one still fights correctly and just looks flat.
##
## [b]Per-instance, not per-material.[/b] Every actor shares one [ShaderMaterial] so the roster
## batches into a handful of draw calls. Writing [code]material.set_shader_parameter[/code] here
## would flash every enemy on screen when one of them got hit — these three uniforms are declared
## [code]instance uniform[/code] in [code]character_pbr.gdshader[/code] and are written through
## [method GeometryInstance3D.set_instance_shader_parameter] instead.

const FLASH_UNIFORM: StringName = &"hit_flash"
const GLOW_UNIFORM: StringName = &"poise_break_glow"
const DISSOLVE_UNIFORM: StringName = &"dissolve_amount"

## Meshes to drive. Every visible piece of the actor, or the flash covers half a body.
@export var meshes: Array[MeshInstance3D] = []

## The actor these meshes belong to. Hits aimed at anyone else are ignored.
@export var actor: Node3D

## Source of [signal Combatant.poise_broken] and [signal Combatant.died].
@export var combatant: Combatant

## Shared combat constants. Supplies the flash duration.
@export var combat_tuning: CombatTuning

## Seconds the death dissolve takes to run to full.
@export var dissolve_duration: float = 1.4

## Seconds the poise-break glow takes to fade once the actor recovers.
@export var glow_fade: float = 0.45

var _flash_left: float = 0.0
var _glow: float = 0.0
var _dissolve: float = 0.0
var _dying: bool = false


func _ready() -> void:
	if combat_tuning == null:
		combat_tuning = CombatTuning.new()

	# Nothing to drive is not an error: a greybox actor with no mesh list still runs.
	if meshes.is_empty():
		set_process(false)
		return

	EventBus.damage_dealt.connect(_on_damage_dealt)
	if combatant != null:
		combatant.poise_broken.connect(_on_poise_broken)
		combatant.died.connect(_on_died)

	_write(FLASH_UNIFORM, 0.0)
	_write(GLOW_UNIFORM, 0.0)
	_write(DISSOLVE_UNIFORM, 0.0)
	set_process(false)


func _process(delta: float) -> void:
	var busy := false

	if _flash_left > 0.0:
		_flash_left = maxf(0.0, _flash_left - delta)
		var duration := maxf(combat_tuning.hit_flash_duration, 0.0001)
		# Squared falloff, so the flash reads as a sharp impact rather than a slow bloom.
		var k := _flash_left / duration
		_write(FLASH_UNIFORM, k * k)
		busy = true

	if _dying:
		_dissolve = minf(1.0, _dissolve + delta / maxf(dissolve_duration, 0.0001))
		_write(DISSOLVE_UNIFORM, _dissolve)
		busy = busy or _dissolve < 1.0

	if _glow > 0.0:
		_glow = maxf(0.0, _glow - delta / maxf(glow_fade, 0.0001))
		_write(GLOW_UNIFORM, _glow)
		busy = true

	# Stop processing the moment there is nothing left to animate. An idle crowd of enemies must not
	# cost a per-frame shader write each (CLAUDE.md §3).
	if not busy:
		set_process(false)


## Flash now, as though this actor had just been struck. Exposed for tests and for scripted beats.
##
## Writes full strength immediately rather than waiting for the next [method _process]. On a frame
## that runs longer than [member CombatTuning.hit_flash_duration] -- a hitch, or the 33 ms low-tier
## budget against a 120 ms flash -- decaying first would land on zero and drop the flash entirely.
## The one guaranteed lit frame is the whole point of the effect.
func flash() -> void:
	_flash_left = combat_tuning.hit_flash_duration
	_write(FLASH_UNIFORM, 1.0)
	set_process(true)


func _on_damage_dealt(target: Node, _packet: DamagePacket, result: int) -> void:
	if target != actor or result == DamagePacket.Result.IMMUNE:
		return
	flash()


func _on_poise_broken() -> void:
	_glow = 1.0
	set_process(true)


func _on_died() -> void:
	_dying = true
	set_process(true)


## Write [param uniform] to every driven mesh.
func _write(uniform: StringName, value: float) -> void:
	for mesh: MeshInstance3D in meshes:
		if is_instance_valid(mesh):
			mesh.set_instance_shader_parameter(uniform, value)
