# kamae

An engine for creating illustrations and videos of budo positions and techniques.

Kamae is a small Godot 4.6 desktop tool that lets an Aikido instructor hand-pose two neutral figures (Tori and Uke), keep grips attached while bodies move, save poses, sequence them into a technique, and export clean stills and short clips for a printed grading handout.

## Status

M0–M6 on this branch: Godot project, CC0 mannequin with 52 humanoid bones
including fingers, N-character scene with per-character skin colour, floor grid, orbit camera, click-to-select FK posing with a rotation gizmo, undo/redo, PNG still export
on a flat or transparent background, IK for both arms and legs with draggable targets and an IK/FK
toggle that bakes the current solve, a reach warning, per-finger curl sliders with a grip preset, and grip attachments that keep one character's hand on another's
body as either of them moves, procedural bokken/jo/tanto weapons held in one or two hands (hand-driven or weapon-driven, with handover and a weapon-contact gap indicator), pose save/load as JSON, Front/Side camera presets that frame every character, sequences of 2–5 poses with the spec's interpolation rules and an in-app player, and video export through a Movie Maker child process (MP4 via ffmpeg, AVI fallback) with a still per phase. Headless tests plus rendered-still checks, also run by the GitHub Actions workflow.

## Running

```sh
godot --path .                       # open the tool (Godot 4.6.x binary on PATH)
GODOT=/path/to/godot tests/run.sh    # headless tests + rendered stills in tests/out/
```

The character asset is generated, not hand-modelled: see `tools/README.md`.

- `docs/spec-v1.md` — original specification as received.
- `docs/spec-review.md` — analysis of v1 against Godot 4.6, verified findings, corrections, open questions for the instructor.
- `docs/spec-v2.md` — revised specification.
- `docs/build-plan.md` — architecture, milestones, tests.
- `docs/engine-notes.md` — Godot 4.6 behaviour the code depends on (IK timing, capture constraints).
- `docs/handoff.md` — where the work stands and what the next session should pick up.
- `feasibility/` — headless Godot experiments that prove the risky parts (IK, two-body grip follow, hand orientation, transparent stills, Movie Maker). Results in `feasibility/results/RESULTS.md`.

## Requirements

- Linux (primary platform). Windows/macOS best-effort.
- Godot 4.6.x.
- `ffmpeg` on PATH for MP4 video export (`sudo apt install ffmpeg`). Without it the tool falls back to AVI.

## Godot version

Pinned to **Godot 4.6.x** (tested with 4.6-stable, official build). The IK stack (`TwoBoneIK3D`, `SkeletonModifier3D`) does not exist before 4.6. Documentation for this version: https://docs.godotengine.org/en/4.6/

## Running the feasibility tests

```sh
GODOT=/path/to/Godot_v4.6-stable_linux.x86_64 ./feasibility/run.sh
```

Rendering tests need a display; on a headless machine install `xvfb` and the script uses it automatically.
