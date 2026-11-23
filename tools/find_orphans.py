#!/usr/bin/env python3
"""Report scripts that nothing in the project can ever reach.

An orphan is a script whose ``res://`` path appears in no ``.tscn`` or ``.tres``, whose
``class_name`` appears in no other script, and which is not registered as an autoload. It is dead
weight at best; twice now it has been a finished, tested system that simply never reached the screen.

WHY THIS EXISTS AS A GATE. The unit suite cannot catch this failure mode by construction: a
well-tested orphan passes every test it has. Both audits on 2026-08-15 found the same class of
defect -- ``PlayerHud``, ``PauseMenu``, ``DeathScreen``, ``FootstepEmitter`` and the grade pass wired
into nothing; ``Bloodstain`` with no scene to instantiate, so the entire Souls death loop could not
close; ``StatusEffect`` with no consumer anywhere. Every one of those was green in CI.

Exits 1 if any orphan is not listed in ALLOWED below.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Directories whose scripts are entry points by nature -- nothing is expected to reference them.
SKIP_DIRS = (".godot", "addons", "tests", "tools")

# Scripts that are legitimately unreferenced. Every entry needs a reason, and the reason has to be
# structural rather than "not wired up yet" -- the latter is the bug this script exists to find.
ALLOWED: dict[str, str] = {
    "systems/log.gd": "static-only utility, called as Log.* from everywhere",
    "levels/chunks/level_chunk.gd": (
        "@tool authoring aid -- dragged into a scene by hand when assembling a level, "
        "so it is referenced by the levels a designer builds, not by any shipped scene"
    ),
}


def main() -> int:
    scripts = [
        p
        for p in ROOT.rglob("*.gd")
        if not any(part in SKIP_DIRS for part in p.relative_to(ROOT).parts)
    ]

    scenes = list(ROOT.rglob("*.tscn")) + list(ROOT.rglob("*.tres"))
    scene_text = "\n".join(
        p.read_text(encoding="utf-8", errors="ignore")
        for p in scenes
        if ".godot" not in p.parts
    )
    project = (ROOT / "project.godot").read_text(encoding="utf-8", errors="ignore")

    sources = {p: p.read_text(encoding="utf-8", errors="ignore") for p in scripts}

    orphans = []
    for path, text in sources.items():
        rel = path.relative_to(ROOT).as_posix()
        if rel in ALLOWED:
            continue

        if f"res://{rel}" in scene_text or rel in project:
            continue

        match = re.search(r"^class_name\s+(\w+)", text, re.M)
        if match:
            name = match.group(1)
            word = re.compile(rf"\b{name}\b")
            if any(word.search(other) for p2, other in sources.items() if p2 != path):
                continue
            if word.search(scene_text):
                continue
            orphans.append((rel, name))
        else:
            orphans.append((rel, None))

    if not orphans:
        print(f"no orphaned scripts ({len(scripts)} checked)")
        return 0

    print(f"{len(orphans)} orphaned script(s) -- referenced by no scene, no script, no autoload:")
    for rel, name in sorted(orphans):
        print(f"  {rel}" + (f"   (class_name: {name})" if name else ""))
    print("\nEither wire it into a scene, reference it, delete it, or add it to ALLOWED with a reason.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
