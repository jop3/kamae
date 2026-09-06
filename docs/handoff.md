# Handoff — Kamae posing tool

Written 2026-09-05 at the end of the session that produced M0–M3, updated the same day by a short
follow-up session that started M3W, M4 and the camera presets in parallel. Read this first; it says
where the work stands, how to run it, and what the next session should pick up.

## Where things stand

| Branch | Contents | State |
|---|---|---|
| `main` | Spec v2.3, build plan, feasibility, the application M0–M3 | PRs #1–#3 merged |
| `claude/handoff-continuation-8iw00t` | M3W weapons, M4 save/load, camera presets, CI workflow (see "Follow-up session" below) | PR #4 merged |
| `claude/project-continuation-46gatk` | CI fix (absolute paths in tests), undo for close-the-gap, roll for the second hand | this branch |

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
src/rig/       CharacterRig, Limb, HandOrient, TwistFollow, FingerCurl, Anatomy, LimbHandle
src/scene/     PosingScene (owns 1–5 characters), Palette, FloorGrid
src/posing/    PoseController (selection, FK, undo), RotationGizmo, GripTarget, Grip, GripDirector
src/ui/        SidePanel (characters, placement, joint, limbs, grips, fingers, export)
src/export/    StillExport
tests/         test_m0..test_m3, check_exports, run.sh
docs/          spec-v1, spec-v2, spec-review, build-plan, engine-notes, this file
```

Frame order everything depends on: FK pose → `FingerCurl` → four × (`TwoBoneIK3D` → `TwistFollow` → `HandOrient`) →
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
  - A second pass added undo for `hold_weapon`, `attach_to_weapon` and `set_weapon_drive`, and
    `Weapon.apply_dict()` so `PoseFile.apply` recreates weapons and holds (tested in `test_m4`).
    Still unfinished: no undo for `close_gap`; the second hand's roll in `attach_to_weapon` is
    fixed at 0°; a first still was rendered with `--demo-weapon <path>` (hook in `Main.gd`): the bokken sits in
    Tori's right hand across the palm with the blade up, which looks plausible; the second hand at
    t=0.05 was 10 cm short (reach, given the demo's arbitrary IK targets), so the two-handed
    geometry still needs a proper chudan pose before judging it.
- **M4 save/load** — `src/data/PoseFile.gd`, `tests/test_m4.gd`. Bone rotations are captured inside
  `skeleton_updated` (baked), grips through `Grip.to_dict()`. Weapons are serialised only if the
  weapon agent's `Weapon.to_dict()` landed; otherwise `weapons: []` and that is the first thing to
  add. No UI yet: the pose library panel (list, save, load, confirm-overwrite) is still to do.
- **Camera presets and CI** — `src/scene/CameraPresets.gd`, `OrbitCamera.apply_preset`,
  `Main.frame_all` now uses the Front preset (the default framing rendered the figures tiny),
  `tests/test_camera.gd`, `.github/workflows/tests.yml`. The workflow has not been seen to run
  yet; expect a first-run fix. **Seen in the render:** the Front preset stands directly behind
  Tori on the Tori→Uke line, so Tori hides Uke and the head nearly clips the frame. Side is the
  usable default; Front needs either an offset off the line or a larger distance before it is
  worth a button in the handout workflow. Raise with the instructor (spec §5.7).

Later the same evening the weapon render was looked at properly and it was bad: hands flat on
the shaft, shaft through the wrist. Root causes fixed, each with a test or a render:
`FingerCurl` bent fingers sideways (axis was the palm normal); the hold anchored at the wrist
joint instead of the palm centre; the palm axes were typed constants with the left hand's sign
wrong (now measured by `FingerCurl.calibrate()`); the thumb now sweeps and folds over the
fingers; `HandOrient` gives the forearm 70 % of the wrist twist. `--demo-weapon <path>` renders
a chudan kamae built weapon-driven with both hands snapped on, plus hand close-ups, and
`--demo-hand <path>` renders one fist open and closed from three sides. Look at
`tests/out/weapon_demo_rh_side.png` before and after any change to hands or holds. Still
visibly off in that render: the left elbow rides high and its forearm shears at the wrist,
which is the default elbow pole (`Limb.ARM_POLE_OFFSET`) fighting the hold orientation; a
per-pose pole adjustment or a better default is the next thing to try.

`SidePanel` now has Weapons, Camera and Poses sections wired to these APIs (untested beyond
"compiles and the app launches"; no contact-gap UI yet). `Main.frame_all` uses the Side preset.

Then M5 and M6 landed the same night: `Sequence` (steps with transition and hold), `PoseBlend`
(the §5.6 rules: root lerp, bone slerp, finger lerp, grips live when in both poses and ramped via
modifier influence when in one, weapon holds blended), `SequencePlayer`, a Sequence section in
the panel, `MovieExport` plus the `--render-sequence` child mode, and `tests/check_movie.gd`
which renders the test_m5 sequence under Xvfb and checks frame count, size, handle-free frames
and the per-phase stills. Two engine facts found on the way are in `docs/engine-notes.md`:
Movie Maker records at the configured window size and ignores `--resolution` (so the project
viewport is 1920×1080 and the interactive window shrinks itself), and a coroutine that awaits
`skeleton_updated` resumes inside the update, so `capture_baked` now awaits `process_frame`
before returning.

M7 and M8 followed: Front+Side batch stills (`--render-stills` child), gizmo snapping with
Shift, the camera saved per pose and blended in per-pose sequences, the Front preset swung 35°
off the line (on the line the near figure hides the other), and the acceptance techniques as
committed `poses/` and `sequences/` written by `tools/build_fixtures.gd`. The fixtures are
schematic drafts by a script, not by an aikidoka; the instructor loads and corrects them. What
they guarantee is the mechanics of spec §8: exact grips (an automatic "step in until the hand
reaches" in the builder), the reused Grepp slug, the deliberate out-of-reach Zenponage Kake,
holds that survive reload, contact gap under 1 cm, jo at chin height. `tests/run.sh` now also
renders every technique's Front+Side stills and a video into `exports/` (about 6 minutes in
total) and checks them; set `RENDER_ACCEPTANCE=0` to skip that part. `docs/guide.md` is the
instructor guide.

A read-only review agent then went through GripDirector, Weapon, PoseFile, PoseBlend,
SequencePlayer, MovieExport and SidePanel and found twelve real problems, all fixed in commit
"Fix twelve review findings" (undo of holds not restoring arm modes, loaded poses keeping
playback blend state, a second hand on a weapon trailing a frame, and so on; the commit message
lists them). The two-handed fix introduced `ArmBridge`, a modifier between the arms' solvers; see
`docs/engine-notes.md`.

A second review pass over the first-session rig and posing code found eight more (undo history
binding freed rigs after a pose load, a stale selection after character removal, the IK/FK bake
unguarded across its awaits, overlapping still captures leaving the UI hidden, the gizmo never
getting its screen-space size, hidden IK balls stealing clicks, uncalibrated finger bones
rotated about a default axis, empty sequences crashing the render children); all fixed in
"Fix eight findings from the second review".

After that: 2× supersampled stills through a private viewport (the Compatibility renderer
ignores `scaling_3d_scale`), the Characters panel (add, duplicate, remove with a grip
confirmation, rename, colour, visibility), mirror and copy pose (exact, tested), weapon-contact
controls, a primary-Uke picker, the sequence's camera mode, keyboard shortcuts, confirm before
overwriting a pose, `export_presets.cfg` for Linux and Windows builds (templates not fetched
here), and a user-folder fallback for poses in exported builds. Every spec §2.1 item is now
present in some form except undo for camera moves and the optional M9 gi.

Last in this session: hanmi stances in every acceptance draft (`hanmi()` in the builder plants
the feet with leg IK; the acceptance check asserts every toe is within 6 cm of the floor) and
undo for camera gestures. `tests/run.sh` exits 0 with all twelve sections green, acceptance
renders included, on the pinned Godot 4.6-stable.

Next: hand the drafts to the instructor; 2×
supersampled stills if the Compatibility renderer allows it; tooltips and keyboard shortcuts;
the pose panel's confirm-before-overwrite; then wait for the instructor's corrections and the
open questions in `docs/spec-v2.md` §9. M9 (gi) remains optional.

## Session 2026-09-06

The CI workflow had never gone green: five test scripts carried the absolute path
`/home/user/kamae/...`, which does not exist on the GitHub runner, so test_m4 could not save its
round-trip file and everything downstream of it (m5, the movie check, the acceptance exports)
failed. Test paths now derive from `res://` through `ProjectSettings.globalize_path`. Never write
an absolute path into a test again; `tests/check_exports.gd` shows the pattern.

Two loose ends from the list above closed: **close the gap** is undoable (it records the moved
weapon's position, or the holder's arm mode, orient flag and IK target), and the hand-driven
branch of it now works at all: the target is first reset onto the hand and orient-to-target is
switched on, otherwise the re-solved arm changes the hand's rotation and swings the weapon's far
end away. If the point is out of reach the gap ends up equal to the reach shortfall, which the
test asserts. **attach_to_weapon** takes a `roll_deg` and the panel passes the roll box to the
second hand too.

### Plausibility tests (same session, on request)

Two new layers, both in `tests/run.sh` and CI:

- **Anatomy, headless and fast.** `src/rig/Anatomy.gd` checks a posed character: elbow and knee
  flexion range and *direction* (from the mannequin's rest fold), no limb through the torso or
  through the other body, no weapon through anyone, no bone scale, and a CPU-skinned mesh whose
  vertices keep their rest distance from their bones. `tests/test_anatomy.gd` proves each rule on
  deliberate poses; `tests/check_anatomy.gd` runs them over every committed pose (about 2 s).
  Grips and two-handed holds are exempted where bodies touch by design (fist on wrist, stacked
  hands, forearms side by side); the rules are coarse on purpose and documented in the file.
- **Golden stills.** `tests/check_golden.gd` shrinks every rendered still to 192×108 and compares
  it with `tests/golden/`; more than 2 % of pixels moving fails. Goldens are what a person looked
  at and accepted: after a deliberate visual change, look at the full-size renders in `exports/`
  and `tests/out/`, then `UPDATE_GOLDEN=1 tests/run.sh` and commit the thumbnails.

Running the anatomy check over the drafts found real defects (Uke's bokken through Uke's chest
in kumitachi, the jo through both bodies in kumijo, hands inside the pelvis in ushiro, both
Ukes crossing arms in ryotemochi, Tori on the wrong side in shihonage) and one mechanics gap:
`TwoBoneIK3D` never twists the upper arm, so overhead and behind-the-back holds bent the elbow
through the skin. `TwistFollow` fixes that (see `docs/engine-notes.md`); `tools/build_fixtures.gd`
was corrected for the rest and every pose was rebuilt. They are still drafts by a script, but
they are now drafts a body could take.

Still open: the instructor's corrections to the acceptance drafts, spec §9 questions, and the
optional M9 gi.

**Default weapon holds** (instructor feedback, same day): the hands used to take the tsuka with
both palms straight under it. `Weapon.default_hold(hand)` now defines the grip per weapon type:
bokken right hand in front just below the tsuba, left against the kashira, palms turned in from
their own sides (roll −45° right, +45° left, measured: the right palm faces inward and down);
the jo starts from the same grip, right hand forward, hands a forearm apart, and slides from
there. `GripDirector.attach_default_hands` applies it, the panel has a "Both hands, default
hold" button and pre-fills t and roll, the builder and the weapon demo use it, and test_m3w
asserts the geometry. Look at `tests/out/demo/weapon_hands.png` after any change to the hold
mapping.

## Session 2026-09-06 (afternoon): wrists, fingers, collision, first gi

Instructor's asks: wrists fully posable as well as grips and fingers; proper collision so a grip
on the neck does not pass through the neck; and a first look at the gi.

- **Wrists.** In FK and in plain IK the wrist was already an ordinary bone (`TwoBoneIK3D` leaves
  the end bone alone, measured). A gripping hand was not: `HandOrient` overwrote it every frame
  from the IK target. `PoseController.target_driven_limb()` now recognises that case and routes
  the gizmo and the sliders to the target's orientation instead, re-capturing the grip's offset
  (`_set_target_basis`), so the new wrist angle is what the grip keeps. `get_bone_rotation`
  returns the solved wrist for such a hand so the sliders show the truth, and undo works through
  the same path. `GripDirector.setup` hands itself to the controller for this.
- **Fingers.** `FingerCurl` composes the curl on top of the authored phalanx rotation instead
  of overwriting it, so single finger joints are posable with the gizmo. Two engine facts came
  out of it (both in `docs/engine-notes.md`): a modifier must write every bone every pass, and
  a coroutine resumed after `skeleton_updated` reads the modified pose. `PoseFile` stores finger
  bones authored; the committed `poses/` were rebuilt with `tools/build_fixtures.gd` because the
  old files carried baked (curled) finger rotations that would now curl twice.
- **Collision.** `src/rig/BodyCapsules.gd` is the body as capsules with Anatomy's radii:
  `push_out`, `penetration`, `neighbours`. `GripDirector.attach_wrapped` works on any bone,
  placing the palm at `hold_radius(bone)` (a wrist wrapped at 2 cm, a neck held at its 5 cm
  surface less the palm depth), with `curl_for_bone` closing the fingers as far as the part
  allows; the panel always wraps now. `resolved_hand_transform` pushes a gripping hand out of
  the gripped body every frame (the gripped bone and its neighbours excepted, where the hand
  overlaps by design), and `error_for` measures against that. A dragged hand target stops at
  other figures' skin (`PoseController.keep_out_of_other_bodies`; a figure's own body is not
  solid to its own hands). The panel shows `Anatomy.scene_problems` live, three times a second.
  `tests/test_wrist.gd` covers all of it; the fixture poses render the same as before.
- **Gi (M9, first look).** `src/rig/Gi.gd` builds it at runtime from the mannequin: the body
  mesh pushed out along its normals (jacket 2.2 cm, sleeves 3 cm, trousers 1.4 cm), cut into a
  jacket (hem at 0.76 m, collar at 1.43 m, a V to the sternum, sleeves to 62 % of the forearm)
  and trousers (waist to 82 % of the shin), triangles across an edge kept with their outside
  vertices moved onto it so the edges are straight; skinned through the body's own binds. The
  belt is a ring measured on the torso vertices at 0.985 m (the first version measured the
  hanging hands too and came out as a hoop), over the jacket, with a knot and two ends, in the
  character's colour and following colour changes. `CharacterRig.set_gi_visible`, saved as
  `"gi"` per character, a **gi** checkbox next to "shown". Off by default so nothing rendered
  changes unless asked. `--demo-gi <path>` renders five views, now part of `tests/run.sh` and the
  goldens (`gi_front`, `gi_side`, `gi_belt`, `gi_sleeve`); look at `tests/out/demo/gi_*.png`.
  Instructor feedback the same day: "needs more texture". The cloth now carries procedural
  weave textures made in code (`Gi._cloth_textures`): rice-grain sashiko quilting with a
  coarse weave for the jacket, plain canvas for trousers and belt, each as an albedo and a
  normal map, mapped triplanar in world metres (8 cm tiles) so the shell needs no UVs; base
  colour a warm off-white so the cloth separates from the white background. Tuned by looking
  at `gi_belt.png`: the first pass was invisible, the second too bold.
  Then "the jacket doesn't seem connected to the arms": the cloth was drawn in its rest pose
  because a code-made MeshInstance3D has an empty skeleton path (engine note); the sleeve
  had looked attached only because the demo's other arm hung at rest. Fixed, with a test on
  the resolved path, and the demo now bends Uke's spine so the render itself shows the cloth
  following (`gi_shoulder.png` is the raised arm's sleeve up close).
  Then, against two photos of a real keikogi ("something like this"): the weave is now fine
  (6 mm rice grains), the sleeves wider and shorter, and the jacket has an **eri**: the collar
  is the jacket shell itself along the neck and the V edges raised by `LAPEL_THICKNESS` as a
  second surface in a canvas cloth (`_in_collar`; triangles touching the band belong to it and
  bevel down, or a slit shows skin), and the two fronts are stitched ribbons (`_ribbon_path`,
  skinned from the nearest skin vertex) that cross below the sternum, the character's left on
  top. Two dead ends worth not repeating: a collar built as a ring of measured radii round the
  neck ended up either inside the jacket or as a shelf out at the shoulders, and quads must be
  wound toward an explicit "outside" (`_rq(..., want)`) or half of them render unlit grey.
  `gi_collar.png` and `gi_collar_back.png` are the views to look at.
  Then "the breasts and bulge are distracting, the gi should be looser": the cloth is now
  draped, not shrink-wrapped (`_drape`): for the torso and hips the shell's radius in each
  direction is at least the body's widest radius above it (less a slow taper, cinched at the
  belt), so the front falls straight from the chest and the jacket skirt hides the crotch.
  The mannequin itself is untouched; flattening it would be a `generate_mannequin.py`
  parameter change and a re-export if ever wanted. The belt is measured on the draped shell.
  Known limits to raise with the instructor: the V still shows skin to the sternum (the
  overlap starts below it),
  the shell self-intersects a little in the armpit of a raised arm, no hakama by decision, and the
  cloth has no wrinkles or thickness of its own. A modelled gi (spec §7.1's transferred-weight
  mesh from Blender) would replace this file without touching anything else.

### Video draft import (same day, on request)

The instructor's `pose_pipeline` (MediaPipe on video; now in `tools/video_pipeline/` with its
README and status notes, and the two in-scope drafts in `imports/`) is worth exactly one
thing to this tool: 33 world landmarks per figure and phase. `src/data/PoseImport.gd` turns a
draft into poses and a sequence: facing from the shoulder line, partners placed to face each
other (the data has no inter-figure distance), arms and legs as IK rebuilt from the landmark
directions with the mannequin's own bone lengths, feet planted at the data's stance with the
hips lowered until the legs reach (leg heights under a hakama are noise), spine and neck as FK
tilts, the grip the file names attached with the nearest hand/forearm pair and the gripper
stepping in until it reaches (every phase, since the distance is not in the data), a figure
without landmarks keeping its previous pose with the file's description as a note, timings
from the file. MediaPipe's frame is y-down, z-away; flipping both keeps the handedness. The
schema-format file (direction vectors only) is also read, without facing. `--import-draft` in
`Main.gd` runs it headless and renders a Side still per pose; the panel has "Import video
draft…"; `tests/test_import.gd` and three goldens cover the katatedori tenkan draft. The
imported Grepp is a recognisable katatedori; Kuzushi and Kake are rougher, as the pipeline's
own log predicts for contact phases. Not done: weapons for the jo draft (not in the data), and
using the image landmarks for the distance between partners.


### The motion, not just the poses (this session)

The videos were plausible pose by pose and not plausible in between. `tests/check_anatomy.gd`
checks every committed pose; nothing checked the frames a blend puts between them, and those are
most of the video. `tests/check_motion.gd` now walks every sequence at the export frame rate and
runs the same checks on every frame. On the first run 50 of the 707 rendered frames broke a body,
from three separate causes:

1. **A root position lerps in a straight line.** In `ushiro_ryotedori_zenponage` Tori ended up on
   the far side of Uke, so the straight line took him *through* Uke — 17 cm deep at worst, one
   whole body inside another.
2. **A bone rotation slerps the short way round**, which walks an arm through a chest rather than
   round it, and rolls an IK-driven humerus 178° between two poses that are both fine.
3. **A gripping hand is carried to its next hold in a straight line** when a grip is released and
   re-taken, and that line runs through the partner.

`src/posing/MotionClearance.gd` fixes the first two and the part of the third that does not
involve a grip: after every blend, trunks that overlap are pushed apart horizontally by their
roots so one figure goes round another, and a limb inside a body is solved by IK to a cleared
target with the influence ramped by how far it had to move. Every correction is derived from
`CharacterRig.fk_bone_transform` — the pose before any modifier runs — which is what keeps it from
feeding back into its own input, and what makes it exactly zero on a keyframe, so a hold still
shows the saved pose and every golden still is unchanged. That took the bad frames from 50 to 40.

What is left is recorded, per sequence, in `check_motion.gd`'s `OUTSTANDING`, and the count may
only go down — beating it fails the check and asks for the number to be lowered.

**Still open, in the order I would take them:**

- **The wrists in weapon holds.** New swing and twist limits in `Anatomy` (`SWING`, `TWIST`,
  measured from bone directions in the parent's frame, so they do not depend on the rig's axis
  conventions) pass on every committed pose except the wrists: 13 poses bend a wrist 93°–151° off
  rest where a real one manages about 90°, worst in `jo_dori_uke`. They are listed in
  `check_anatomy.gd`'s `OUTSTANDING` so nothing new can join them. The cause is one thing, not
  thirteen: a hand is placed on a weapon or a grip while the forearm points somewhere else, and
  the wrist takes up the difference. The fix is to choose the elbow that leaves the wrist neutral
  when a hand is placed — with the hand's position and orientation fixed, the pole is what decides
  the forearm's direction — and then rebuild the fixtures. That changes every weapon pose, so it
  wants the instructor's eye before the goldens are refreshed.
- **The IK-driven shoulder roll.** One frame of `jo_dori` rolls the humerus 178°. The arm is in
  IK there, so it comes from the solver and its interpolated target, not from the blend.
  Interpolating the blend's rotations as swing and twist separately was tried and reverted: it
  did not touch this (the rotation is not the blend's) and it made intersections worse, 39 frames
  to 51.
- **Where a gripping hand travels.** The remaining 40 frames are all a gripping arm mid re-grip.
  A blend cannot fix them — `MotionClearance` will not move a gripping hand, because that would
  tear it off what it holds — so each one needs a pose that says where the hand goes.
  `tools/add_step.gd <slug> <seconds>` bakes the pose the technique is already showing at that
  moment, clearance included, and splits the transition around it without changing the technique's
  length; open it in the tool, move the offending limb, save. `MOTION_VERBOSE=1` on
  `check_motion.gd` lists every offending frame with its time, which is where the seconds come
  from.
- **Nobody's head ever moves.** Measuring the poses turned up Neck, Head, Chest and both clavicles
  at exactly 0° in every committed pose. The figures stare straight ahead through every technique,
  which is a large part of why they read as mannequins rather than people.
