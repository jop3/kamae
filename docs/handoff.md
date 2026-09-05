# Handoff — Kamae posing tool

Written 2026-09-05 at the end of the session that produced M0–M3. Read this first; it says where the
work stands, how to run it, and what the next session should pick up.

## Where things stand

| Branch | Contents | State |
|---|---|---|
| `main` | Spec v2.2, spec review, build plan, feasibility experiments | merged (PR #1) |
| `claude/spec-analysis-planning-cfcmc4` | Spec v2.3: weapons (bokken, jo, tanto) | open as PR #2, **not merged** |
| `claude/m0-project-setup` | The application: M0, M1, M2, M3 | open as PR #3 |

The two open pull requests do not conflict: one touches `docs/` only, the other adds the Godot
project. Merge the spec PR first so the implementation branch is working against the current spec.

Milestones done: **M0** project and character, **M1** click-to-select FK posing with a gizmo and PNG
export, **M2** IK arms and legs with finger curls, **M3** grip attachments. Next up is **M3W**
(weapons), then M4 (save/load), M5 (sequences), M6 (video), M7 (camera and export polish), M8
(acceptance), M9 (optional gi).

## Running it

```sh
godot --path .                       # the tool itself, Godot 4.6.x on PATH
GODOT=/path/to/godot tests/run.sh    # all headless tests plus rendered-still checks
```

Rendering needs a display. On a headless machine install `xvfb` and the scripts use it automatically;
`StillExport.capture()` refuses to run headless rather than hanging. The tests write into `tests/out/`,
which carries a `.gdignore` so Godot's importer leaves the rendered PNGs alone.

Godot 4.6.x is required and pinned: the IK stack does not exist before it. A binary can be fetched
from the `godotengine/godot-builds` releases.

## The shape of the code

```
assets/characters/mannequin.glb   generated, CC0, 52 humanoid bones incl. fingers (LICENSE.md)
tools/generate_mannequin.py       regenerates it headlessly via bpy + MPFB (see tools/README.md)
src/rig/       CharacterRig, Limb, HandOrient, FingerCurl, LimbHandle, PickCapsules
src/scene/     PosingScene (owns 1–5 characters), Palette, FloorGrid
src/posing/    PoseController (selection, FK, undo), RotationGizmo, GripTarget, Grip, GripDirector
src/ui/        SidePanel (characters, placement, joint, limbs, grips, fingers, export)
src/export/    StillExport
tests/         test_m0..test_m3, check_exports, run.sh
docs/          spec-v1, spec-v2, spec-review, build-plan, engine-notes, this file
```

Frame order everything depends on: FK pose → `FingerCurl` → four `TwoBoneIK3D` → `HandOrient` →
`skeleton_updated` (the character caches its solved pose; the grip director drives dependent hands) →
skin → pose restored.

## Read this before touching the posing code

`docs/engine-notes.md` is the list of engine behaviours that bit me, each with what breaks if it is
ignored. The four that cost the most time:

1. **Bone poses are transient.** Reading a bone outside `skeleton_updated` gives the *unposed* value.
   Use `CharacterRig.bone_world_transform()`, which returns the cached solved pose and is correct in
   both contexts. Capturing a grip offset from the raw skeleton put every grip half a metre out.
2. **The character generator is fragile in two specific ways.** MakeHuman's helper geometry must stay
   enabled, or the arm bones are fitted up to 47 cm outside the body; and the helpers must be removed
   by the Mask modifier, never by deleting vertices, or the skin weights detach from their vertices.
   Both now fail the generator's own assertions.
3. **A non-unit quaternion axis silently adds scale** to a bone pose and stretches the mesh.
4. **Still capture hangs** under `--headless`, and also if the UI layer is visible during the capture.

A useful habit from this session: when the numbers all pass but a render looks wrong, render the
stages in isolation and compare, rather than reasoning about it. Bones being right does not mean the
mesh is.

## M3W: weapons, the next milestone

The spec section is `docs/spec-v2.md` §5.9 and the acceptance cases are §8.5–8.8. The design is
settled; what remains is building it.

- `GripTarget` already has a `WEAPON` kind that resolves through `PosingScene.get_weapon()`, which
  currently returns null. Implementing weapons means filling that in, not changing the grip system.
- Build `Weapon` (procedural mesh from measurements, plus `anchor_transform(t)` along its length) and
  the two drive modes: weapon follows a hand, or hands follow the weapon.
- Dimensions confirmed by the instructor: bokken 1.02 m with a 0.24 m tsuka, jo 1.28 m, tanto 0.30 m,
  all editable per weapon.
- Weapon-to-weapon contact is a measured gap with a "close the gap" action, deliberately not a
  constraint.
- Follow the existing test style: assert invariants (a hand is on its anchor or short by exactly its
  reach shortfall) rather than fixed coordinates, which drift whenever the setup changes.

## Decisions already taken

CC0 character committed to the repo rather than Mixamo; Linux primary; MP4 via ffmpeg with an AVI
fallback; JSON rather than `.tres`; flat background by default with transparent available; humanoid
bone names; Compatibility renderer; 1–5 characters with per-character skin colour; no hakama, with the
white gi deferred to M9; grip targets abstracted over bones and weapons from M3.

## Still open with the instructor

Numbered in `docs/spec-v2.md` §9: which technique the three-person case should be, which syllabus
forms the four weapon cases should be, whether blade contact needs to be a real constraint, whether
Front and Side stills should be exported automatically for every pose, whether a footprint overlay is
wanted, and how much packaging other clubs need. None of them block M3W.

One judgement call worth raising early: the mannequin is MakeHuman's neutral body and has mild
anatomical detail. For a children's handout it may want to be flatter and more androgynous. That is a
parameter change plus a re-export via `tools/generate_mannequin.py`, and the gi in M9 covers it
anyway.
