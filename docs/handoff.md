# Handoff — Kamae posing tool

Written 2026-09-05 at the end of the session that produced M0–M3, updated the same day by a short
follow-up session that started M3W, M4 and the camera presets in parallel. Read this first; it says
where the work stands, how to run it, and what the next session should pick up.

## Where things stand

| Branch | Contents | State |
|---|---|---|
| `main` | Spec v2.3, build plan, feasibility, the application M0–M3 | PRs #1–#3 merged |
| `claude/handoff-continuation-8iw00t` | M3W weapons, M4 save/load, camera presets, CI workflow (see "Follow-up session" below) | this branch |

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
from the `godotengine/godot-builds` releases; this works from inside an agent session:

```sh
curl -sSL -o godot.zip https://github.com/godotengine/godot-builds/releases/download/4.6-stable/Godot_v4.6-stable_linux.x86_64.zip
unzip godot.zip && chmod +x Godot_v4.6-stable_linux.x86_64
```

`xvfb-run` is present on the agent machines; `ffmpeg` is **not**, so the M6 MP4 path can only be
tested there through its AVI fallback unless ffmpeg is installed first (`apt-get install ffmpeg`).
The full suite (`tests/run.sh`) takes about 25 s.

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

## Follow-up session (2026-09-05, evening)

Verified first: all of M0–M3 tests and the rendered-still checks pass on a fresh Godot 4.6-stable
download. Nothing from the earlier session was found broken.

Because the session had only minutes left, three agents were dispatched in parallel on disjoint
files. All three landed and the full suite (`tests/run.sh`, seven test scripts plus the rendered
stills) was green at the end of the session. Their code has not been read line by line by the
lead, so read it before building on it.

- **M3W weapons** — `src/weapons/Weapon.gd`, `PosingScene` weapon list, `GripDirector` weapon
  integration, `tests/test_m3w.gd`. Design decisions taken (all reversible):
  - Weapon local **+Y runs from butt (t=0) to tip (t=1)**; the bokken curves toward +Z, edge on −Z.
  - A hand-driven weapon is placed **inside its holder's `skeleton_updated`** (where the hand pose is
    live) and the grips on that weapon are applied in the same callback; a gripper of a weapon
    depends on the weapon's holder in the topological order.
  - Weapon-driven weapons apply their grips at **frame start**, from the director's internal
    process at `process_priority = -10`, which runs before any skeleton solves that frame (Godot
    runs internal process for the whole group before normal `_process`, ordered by priority).
  - Canonical hold mapping from the mannequin's hand frame, measured this session: hand-local +Y is
    wrist→fingers; palm width axis (little→index) ≈ (0.48, 0.13, 0.87) right / (−0.66, 0.10, 0.75)
    left; palm normal (back→palm) ≈ (−0.88, 0.10, 0.47) right / (−0.75, −0.06, −0.65) left. The
    weapon axis lies along the width axis toward the thumb side, the edge faces the palm normal,
    `roll_deg` turns about the weapon axis. **Render a still and look at it** before believing this
    mapping: the signs were derived from numbers, not from a picture.
  - Switching weapon-driven→hand-driven captures the raw hand⁻¹×weapon offset so the geometry is
    preserved exactly even when the weapon was tilted out of the palm plane.
  - Unfinished: no undo entries for `hold_weapon`, `attach_to_weapon`, `set_weapon_drive`,
    `close_gap`; the second hand's roll in `attach_to_weapon` is fixed at 0°; `Weapon.to_dict()`
    exists but `PoseFile.apply` does not yet recreate weapons or holds from a file.
- **M4 save/load** — `src/data/PoseFile.gd`, `tests/test_m4.gd`. Bone rotations are captured inside
  `skeleton_updated` (baked), grips through `Grip.to_dict()`. Weapons are serialised only if the
  weapon agent's `Weapon.to_dict()` landed; otherwise `weapons: []` and that is the first thing to
  add. No UI yet: the pose library panel (list, save, load, confirm-overwrite) is still to do.
- **Camera presets and CI** — `src/scene/CameraPresets.gd`, `OrbitCamera.apply_preset`,
  `Main.frame_all` now uses the Front preset (the default framing rendered the figures tiny),
  `tests/test_camera.gd`, `.github/workflows/tests.yml`. The workflow has not been seen to run
  yet; expect a first-run fix.

Next in order: verify the three pieces above and wire them into `SidePanel` (weapons section: add
weapon, hold by hand/t/roll, drive mode, attach second hand, contact gap and "close the gap";
poses section: save/load; camera section: Front/Side buttons), then M5 sequences, M6 video, M8.
