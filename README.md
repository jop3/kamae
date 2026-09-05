# kamae

An engine for creating illustrations and videos of budo positions and techniques.

Kamae is a small Godot 4.6 desktop tool that lets an Aikido instructor hand-pose two neutral figures (Tori and Uke), keep grips attached while bodies move, save poses, sequence them into a technique, and export clean stills and short clips for a printed grading handout.

## Status

Planning. No application code yet.

- `docs/spec-v1.md` — original specification as received.
- `docs/spec-review.md` — analysis of v1 against Godot 4.6, verified findings, corrections, open questions for the instructor.
- `docs/spec-v2.md` — revised specification.
- `docs/build-plan.md` — architecture, milestones, tests.
- `feasibility/` — headless Godot experiments that prove the risky parts (IK, two-body grip follow, hand orientation, transparent stills, Movie Maker). Results in `feasibility/results/RESULTS.md`.

## Godot version

Pinned to **Godot 4.6.x** (tested with 4.6-stable, official build). The IK stack (`TwoBoneIK3D`, `SkeletonModifier3D`) does not exist before 4.6. Documentation for this version: https://docs.godotengine.org/en/4.6/

## Running the feasibility tests

```sh
GODOT=/path/to/Godot_v4.6-stable_linux.x86_64 ./feasibility/run.sh
```

Rendering tests need a display; on a headless machine install `xvfb` and the script uses it automatically.
