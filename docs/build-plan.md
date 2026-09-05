# Build plan — Kamae posing tool

Derived from `spec-v2.md`. Each milestone ends with something runnable and a headless or Xvfb test that proves it. Effort is in focused agent-sessions (roughly half-days); the risk column says what could still surprise us.

## Architecture

```
kamae/                      Godot 4.6 project root (project.godot)
  addons/                   none planned
  assets/characters/        X Bot FBX (git-ignored) + import settings; CC0 fallback (committed)
  src/
    app/Main.tscn           3D viewport + UI dock
    rig/CharacterRig.tscn   Skeleton3D + 4×TwoBoneIK3D + 2×HandOrient + FingerCurl + pick capsules
    rig/HandOrient.gd       SkeletonModifier3D: end-bone rotation = target rotation
    rig/FingerCurl.gd       SkeletonModifier3D: per-finger curl
    rig/PickCapsules.gd     builds Area3D per bone from rest pose
    posing/GripDirector.gd  attachment list, skeleton_updated sync, cycle order
    posing/Gizmo.gd         runtime rotation gizmo (rings, snapping, trackball)
    posing/PoseController.gd selection, drag, UndoRedo
    data/PoseFile.gd        JSON (de)serialisation, slugs, format versioning
    data/Sequence.gd        steps, interpolation, influence ramps
    export/StillExport.gd   SubViewport, flat/transparent, 2× supersample
    export/MovieExport.gd   spawn child with --write-movie, progress
    ui/                     dock panels: Characters, Joint, Grips, Fingers, Poses, Sequence, Camera, Export
  poses/  sequences/  exports/   instructor data (poses/sequences committed; exports git-ignored)
  tests/                    headless GDScript tests, run by tests/run.sh
  feasibility/              the engine experiments that informed the spec (kept as documentation)
```

Frame order that everything relies on (verified): animation/FK pose → `FingerCurl` → `TwoBoneIK3D` ×4 → `HandOrient` ×2 → `skeleton_updated` (GripDirector syncs dependents, PoseFile reads baked pose) → skin → pose restored.

## Milestones

| # | Deliverable | Proof | Est. | Risk |
|---|---|---|---|---|
| M0 | Project skeleton, Compatibility renderer, README with Godot 4.6 pin, X Bot import at 0.01 with Humanoid bone map, teal/amber materials, floor grid, camera orbit. CC0 fallback character wired the same way. | Headless test lists the expected bone names on both characters; screenshot under Xvfb. | 1 | Mixamo download is manual; finger bone names after bone-map must be checked once against the real asset. |
| M1 | FK posing loop: pick capsules, selection highlight, rotation gizmo, Euler sliders, root move/turn, undo/redo, PNG still (flat + transparent). | Xvfb test: synthetic click on a capsule selects the right bone; gizmo drag rotates; still is RGBA. | 3 | The gizmo is the biggest UI piece. Fallback: sliders only for M1, gizmo polish in M7. |
| M2 | IK for 4 limbs with draggable targets and poles, IK/FK toggle with baking, `HandOrient`, reach warning, finger curl sliders + grip preset. | Headless: target set → hand within 1e-4; toggle to FK leaves bones unchanged; reach flag flips at length. | 2 | Pole placement heuristics for natural elbows/knees; may need a per-limb default pole offset. |
| M3 | Second character; `GripDirector` with attach/detach UI, offset capture, multi-grip, cycles, orientation follow. Validate on Katatedori Ikkyo Grepp→Kuzushi. | Headless: move Tori's arm → Uke's hand error 0.000; two grips independent; grip reversed mid-sequence. (Ported from `feasibility/iktest`.) | 2 | Mostly pre-paid by feasibility. Remaining risk: hand offset capture when the hand is already mid-IK. |
| M4 | Pose save/load JSON, pose library panel, confirm dialogs, slugs, copy pose Tori↔Uke, mirror. | Headless: save→load→compare all bones, grips, camera within 1e-4. | 1.5 | None significant. |
| M5 | Sequences: steps, durations, interpolation rules incl. live IK for double-active grips and influence ramps; in-app preview with scrub bar. | Headless: interpolate Ikkyo at t=0.5 and assert grip error stays 0; ramp reaches 0/1 at ends. | 2 | Visual quality of straight slerp on Shihonage's 180° turn; mitigated by inserting poses, per spec. |
| M6 | Video export via spawned Movie Maker child (`--render-sequence`), AVI + PNG frames, per-keyframe stills, progress UI, optional ffmpeg MP4. | Xvfb: export Ikkyo → AVI exists, frame count = duration×30, stills for 3 phases exist with right slugs. | 1.5 | Child-process launch path differences on Windows/macOS (exe path, quoting). |
| M7 | Camera presets Front/Side, per-pose camera, Front+Side batch export, 2× supersampling, UI polish, tooltips, keyboard shortcuts, gizmo snapping. | Xvfb screenshots of both presets for each acceptance pose. | 1.5 | Edge halo on transparent export (godot#113103); flat background remains default if it shows. |
| M8 | Acceptance: build all three techniques as saved poses/sequences, export all stills and videos, check every criterion in spec-v2 §8, write the instructor guide. | `tests/run.sh` green; `exports/` contains the 3 AVIs and 18 stills. | 2 | Aikido correctness is the instructor's call; agent produces first drafts for them to adjust. |

Total: about 16.5 sessions. M3 stays early on purpose; do not start M5+ until M3's headless test is green.

## Testing strategy
- `tests/run.sh` runs every `tests/test_*.gd` with `godot --headless -s`, printing `PASS`/`FAIL`; exits non-zero on failure. Rendering tests wrap Godot in `xvfb-run` when no display exists (pattern from `feasibility/run.sh`).
- GitHub Actions: download the pinned Godot 4.6 release, `apt install xvfb`, run `tests/run.sh`, upload `exports/` as an artifact so the instructor can preview renders from any PR.
- The three acceptance sequences are regression fixtures: every PR re-renders them.

## Decisions taken without waiting for the instructor (reversible)
- JSON over `.tres`.
- AVI/MJPEG default, PNG frames always, MP4 optional.
- Flat background default, transparent as a setting.
- Humanoid bone names, not `mixamorig:*`.
- Compatibility renderer.

## Immediate next steps
1. Instructor answers the eight questions in `spec-review.md` (especially Mixamo download and AVI vs MP4).
2. Instructor drops `xbot.fbx` into `assets/characters/` (or approves the CC0 fallback).
3. Start M0.
