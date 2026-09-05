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
    posing/GripDirector.gd  attachment list, target resolution (bone or weapon), sync, cycle order
    rig/Weapon.gd           procedural bokken/jo mesh, anchor transform at t, drive mode
    rig/WeaponHold.gd       weapon follows a hand, or hands follow the weapon
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
| M0 | Project skeleton, Compatibility renderer, README with Godot 4.6 pin, CC0 rigged humanoid (glTF) imported with the Humanoid bone map, `CharacterRig` instanced N times from a scene description (ids, roles, skin colour palette), floor grid, camera orbit. Asset choice and licence recorded in `assets/characters/LICENSE.md`. | Headless test instantiates 5 characters, lists the expected bone names on each, applies 5 distinct colours; screenshot under Xvfb. | 1.5 | Finding a CC0 humanoid whose finger bones map cleanly; fallback is a CC0 body plus a hand-authored finger rig in Blender (+1 session). |
| M1 | FK posing loop: pick capsules, selection highlight, rotation gizmo, Euler sliders, root move/turn, undo/redo, PNG still (flat + transparent). | Xvfb test: synthetic click on a capsule selects the right bone; gizmo drag rotates; still is RGBA. | 3 | The gizmo is the biggest UI piece. Fallback: sliders only for M1, gizmo polish in M7. |
| M2 | IK for 4 limbs with draggable targets and poles, IK/FK toggle with baking, `HandOrient`, reach warning, finger curl sliders + grip preset. | Headless: target set → hand within 1e-4; toggle to FK leaves bones unchanged; reach flag flips at length. | 2 | Pole placement heuristics for natural elbows/knees; may need a per-limb default pole offset. |
| M3 | Characters panel (add/remove/duplicate/rename, colour picker); `GripDirector` with attach/detach UI between any pair, offset capture, grip graph + topological order, cycles, orientation follow. Validate on Katatedori Ikkyo Grepp→Kuzushi and the three-person fixture. | Headless: move Tori's arm → Uke's hand error 0.000; two Ukes on two wrists independent; chain Uke2→Uke1→Tori resolves in one frame; grip reversed mid-sequence. (Ported from `feasibility/iktest`.) | 2.5 | Mostly pre-paid by feasibility. Remaining risk: hand offset capture when the hand is already mid-IK. |
| M3W | Weapons: procedural bokken, jo and tanto at standard aikido dimensions, hand-driven and weapon-driven modes, two-handed holds, hands attaching to weapon anchors, weapon handover between characters, contact indicator with "close the gap", sliding grips. | Headless: a hand-driven bokken follows its holder with no error; a second hand tracks its anchor; handover changes owner without the weapon jumping; contact gap is reported and closes to under 1 cm; `t` interpolates. | 2.5 | Contact ergonomics on paired forms; the target abstraction itself is already paid for in M3. |
| M4 | Pose save/load JSON, pose library panel, confirm dialogs, slugs, copy pose Tori↔Uke, mirror. | Headless: save→load→compare all bones, grips, camera within 1e-4. | 1.5 | None significant. |
| M5 | Sequences: steps, durations, interpolation rules incl. live IK for double-active grips and influence ramps; in-app preview with scrub bar. | Headless: interpolate Ikkyo at t=0.5 and assert grip error stays 0; ramp reaches 0/1 at ends. | 2 | Visual quality of straight slerp on Shihonage's 180° turn; mitigated by inserting poses, per spec. |
| M6 | Video export via spawned Movie Maker child (`--render-sequence`) → PNG frames → ffmpeg MP4 (H.264), per-keyframe stills, progress UI, AVI fallback when ffmpeg is absent. | Xvfb: export Ikkyo → MP4 exists and probes as H.264 30 fps, frame count = duration×30, stills for 3 phases exist with right slugs. | 1.5 | ffmpeg availability on the instructor's machine (documented install). |
| M7 | Camera presets Front/Side, per-pose camera, Front+Side batch export, 2× supersampling, UI polish, tooltips, keyboard shortcuts, gizmo snapping. | Xvfb screenshots of both presets for each acceptance pose. | 1.5 | Edge halo on transparent export (godot#113103); flat background remains default if it shows. |
| M8 | Acceptance: build the three techniques plus the three-person fixture as saved poses/sequences, export all stills and videos, check every criterion in spec-v2 §8, write the instructor guide. | `tests/run.sh` green; `exports/` contains 4 AVIs and 24 stills. | 2 |
| M9 | Optional, after sign-off: anatomical body with detailed hands rigged to the same bone names, white gi as skinned mesh with per-character belt colour, gi toggle per character. No hakama. | Xvfb renders of the four acceptance sequences in gi; grip error unchanged; skin colours still visible on hands/head/feet. | 4–6 | Aikido correctness is the instructor's call; agent produces first drafts for them to adjust. |

Total: about 20.5 sessions for M0–M8 including weapons, plus 4–6 for the optional gi milestone M9. M3 stays early on purpose; do not start M5+ until M3's headless test is green.

## Testing strategy
- `tests/run.sh` runs every `tests/test_*.gd` with `godot --headless -s`, printing `PASS`/`FAIL`; exits non-zero on failure. Rendering tests wrap Godot in `xvfb-run` when no display exists (pattern from `feasibility/run.sh`).
- GitHub Actions: download the pinned Godot 4.6 release, `apt install xvfb`, run `tests/run.sh`, upload `exports/` as an artifact so the instructor can preview renders from any PR.
- The three acceptance sequences are regression fixtures: every PR re-renders them.

## Decisions taken without waiting for the instructor (reversible)
- JSON over `.tres`.
- MP4 via ffmpeg (instructor decision), AVI fallback.
- Flat background default, transparent as a setting.
- Humanoid bone names, not `mixamorig:*`.
- Compatibility renderer.
- Grip targets are an abstraction (a bone or a weapon anchor) from M3, so weapons need no rework of the grip system.
- N-character data model from M0 (a list of characters with ids), even though the first techniques use two, because retrofitting it later touches every panel.

## Immediate next steps
1. Decided: CC0 character, Linux, MP4. Remaining questions in `spec-review.md` can be answered during M4–M7.
2. Start M0 on a development branch.
