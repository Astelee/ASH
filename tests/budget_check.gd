extends Node

## Measures a real scene against the budgets in CLAUDE.md §3.
##
## Runs with a **real rendering driver** — the headless dummy rasteriser reports zero for every
## render monitor, so a headless budget check would pass a scene with ten thousand draw calls.
##
## **This is a desktop measurement, not a device one.** Draw calls and triangle counts are
## platform-independent and mean the same thing on a phone; frame time and VRAM do not. Treat the
## first two as binding and the rest as a smoke test until `scripts/perf.sh` runs on hardware.

## Frames to warm up before sampling. The first frames pay for shader compilation and resource
## upload, and including them would make every scene look catastrophic.
const WARMUP_FRAMES: int = 90

## Frames sampled after warmup.
const SAMPLE_FRAMES: int = 120

## Budgets from CLAUDE.md §3, mid tier, per frame.
const BUDGET_DRAW_CALLS: int = 130
const BUDGET_PRIMITIVES: int = 250_000
const BUDGET_TEXTURE_MB: float = 60.0

## Scene under test.
@export var scene: PackedScene

## Label for the report.
@export var scene_name: String = "scene"

var _frame: int = 0
var _peak_draw: int = 0
var _peak_prims: int = 0
var _peak_texture_mb: float = 0.0
var _frame_ms_total: float = 0.0
var _samples: int = 0
var _failures: int = 0


func _ready() -> void:
	if scene != null:
		add_child(scene.instantiate())
	print("--- budget check: %s ---" % scene_name)


func _process(delta: float) -> void:
	_frame += 1
	if _frame <= WARMUP_FRAMES:
		return

	_peak_draw = maxi(
		_peak_draw, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	)
	_peak_prims = maxi(
		_peak_prims, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	)
	_peak_texture_mb = maxf(
		_peak_texture_mb, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	)
	_frame_ms_total += delta * 1000.0
	_samples += 1

	if _frame >= WARMUP_FRAMES + SAMPLE_FRAMES:
		_report()


func _report() -> void:
	var average_ms := _frame_ms_total / float(maxi(_samples, 1))

	_check("draw calls", float(_peak_draw), float(BUDGET_DRAW_CALLS), "%.0f")
	_check("triangles", float(_peak_prims), float(BUDGET_PRIMITIVES), "%.0f")
	_check("texture VRAM (MB)", _peak_texture_mb, BUDGET_TEXTURE_MB, "%.1f")

	# Desktop frame time is not the device number, so it is reported and not enforced. A desktop that
	# cannot hold the budget is still a red flag worth seeing.
	print(
		(
			"  INFO  %-22s %8.2f ms  (desktop only — not the device budget)"
			% ["avg frame time", average_ms]
		)
	)

	print("--- %s ---" % ("WITHIN BUDGET" if _failures == 0 else "%d OVER BUDGET" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check(label: String, value: float, budget: float, format: String) -> void:
	var ok := value <= budget
	if not ok:
		_failures += 1
	var shown := format % value
	var limit := format % budget
	print(
		(
			"  %s  %-22s %10s / %s%s"
			% ["PASS" if ok else "FAIL", label, shown, limit, "" if ok else "   OVER"]
		)
	)
