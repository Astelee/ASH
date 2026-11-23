class_name ColorGrade
extends ColorRect

## The fullscreen grade pass, handed to [MoodDirector] on ready.
##
## Sits on its own [CanvasLayer] below the HUD so it grades the world and leaves the UI alone —
## a graded HUD picks up the biome's vignette and grain, which makes text crawl.
##
## This node owns nothing. It picks a material for the tier, registers it, and gets out of the way;
## every value written into that material comes from the active [BiomeMood], because
## [code]CLAUDE.md §2[/code] makes [MoodDirector] the only thing permitted to touch the grade.
##
## [b]Two materials, one quad.[/b] The HIGH-tier material samples the screen so it can do chromatic
## aberration; that screen copy costs 11.8 MB of a 60 MB texture budget, which the tier that
## [i]defines[/i] the budget cannot spend. Every tier below HIGH mounts a `blend_mul` material that
## produces the same vignette, grain and pulse as a pure multiplier and allocates nothing.
##
## [b]Tonemapping is not done here.[/b] [Environment] applies exposure, ACES, contrast, saturation
## and the LUT as part of the tonemap resolve on every tier, which costs no extra pass and no extra
## memory. Doing any of it again in this shader would grade the image twice.

## Material for tiers that may pay for a screen copy.
@export var screen_material: ShaderMaterial

## Material for every other tier. Must not sample the screen.
@export var cheap_material: ShaderMaterial


func _ready() -> void:
	# Nothing under a grade pass should ever be clickable through it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var chosen := screen_material if QualityManager.allows_screen_texture() else cheap_material
	if chosen == null:
		Log.warn(
			"ColorGrade", "no material for tier %s; grade disabled" % QualityManager.tier_name()
		)
		visible = false
		return

	# Duplicated so two levels alive at once during a scene change cannot fight over one material.
	var grade := chosen.duplicate() as ShaderMaterial
	material = grade
	MoodDirector.bind_grade(grade)

	QualityManager.tier_changed.connect(_on_tier_changed)


func _exit_tree() -> void:
	MoodDirector.unbind_grade()


## Re-mount the other material when the dynamic tier crosses the screen-copy boundary. Without this
## a device that drops from HIGH under load keeps paying for the back buffer it dropped tier to
## avoid, which is the opposite of what the tier change is for.
func _on_tier_changed(_tier: int) -> void:
	var wanted := screen_material if QualityManager.allows_screen_texture() else cheap_material
	if wanted == null or material == null:
		return
	if (material as ShaderMaterial).shader == wanted.shader:
		return

	var grade := wanted.duplicate() as ShaderMaterial
	material = grade
	MoodDirector.bind_grade(grade)
