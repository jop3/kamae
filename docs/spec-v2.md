# Kamae — Aikido Posing Machine — Build Specification v2

**Status:** v2.1 — revised after feasibility testing on Godot 4.6-stable (2026-09-05), then updated with instructor decisions: N characters per scene (2–5), customizable skin colour, white gi later, no hakama. Supersedes `spec-v1.md`; changes are summarised at the end and justified in `spec-review.md`.
**Target engine:** Godot 4.6.x (pinned). Uses `IKModifier3D` / `TwoBoneIK3D` / `SkeletonModifier3D` introduced in 4.6. Renderer: Compatibility (OpenGL 3.3) so the tool runs on laptops without a dedicated GPU.
**Audience:** the engineering agent building the tool; the instructor who owns it.
**Owner / domain expert:** a Ki-Aikido instructor documenting grading techniques for children. Sole judge of pose correctness.

---

## 1. Purpose (unchanged)

Produce clean, consistent, annotatable stills and short clips of two neutral figures (Tori, Uke) performing 5th–3rd kyu techniques, posed by hand by the instructor, for a Swedish printed handout. The tool is an authoring instrument, not a game and not a distribution app.

## 2. Scope

### 2.1 In scope
- Godot 4.6 project, runnable from the editor and as a standalone desktop build (Linux/Windows/macOS).
- Two to five humanoid characters per scene (one Tori, one or more Uke, optionally observers), all instances of the same humanoid-mapped rig with finger bones. Characters can be added and removed per pose.
- Per-character skin colour (and later belt colour) chosen from a palette or colour picker, saved with the pose, so hands in a grip are identifiable at a glance.
- Whole-body placement (root move/turn) of each character, plus a floor grid.
- FK posing of every major joint by click-to-select + on-screen rotation gizmo + sliders.
- IK posing of arms and legs (`TwoBoneIK3D`) with per-limb IK/FK toggle (toggle to FK bakes the current solve).
- Hand orientation control at the IK end (required, see §5.3).
- Grip attachments: any hand ↔ any bone of the other character, many at once, direction reversible, stored per pose.
- Finger curl sliders and a grip preset.
- Undo/redo within a session.
- Pose library and technique sequences persisted as JSON.
- Interpolated preview and Movie Maker video export; PNG still export with flat or transparent background.
- Camera orbit + Front/Side presets; camera saved per pose optionally.
- Headless regression tests and the three acceptance techniques (§8) saved in the repo.

### 2.2 Out of scope
Physics/ragdoll, AI pose generation, mocap, cloth simulation, hakama (dropped by decision; gi is a later milestone), networking, mobile/web, correctness checking, ukemi depiction.

## 3. Design decisions (constraints)

- **Engine:** Godot 4.6.x. If the environment only has < 4.6, stop and flag.
- **Character rig:** Mixamo stock character (X Bot, T-pose FBX) imported natively via Godot's built-in FBX importer at scale 0.01, with the `SkeletonProfileHumanoid` bone map applied so bones are named `Hips`, `Spine`, `Chest`, `UpperChest`, `Neck`, `Head`, `LeftShoulder`, `LeftUpperArm`, `LeftLowerArm`, `LeftHand`, `LeftThumbMetacarpal` … `LeftLittleDistal`, `LeftUpperLeg`, `LeftLowerLeg`, `LeftFoot`, `LeftToes`, and mirrored `Right*`. All pose data uses these names, so any humanoid-mapped character can replace X Bot later.
- **Asset licensing:** the Mixamo FBX is downloaded by the instructor and lives in `assets/characters/` which is git-ignored (Mixamo forbids redistributing raw files; this repo is public). The README documents the download and a CC0 fallback mannequin.
- **IK:** `TwoBoneIK3D` for arms and legs. `SkeletonIK3D` is not used.
- **Pose data:** JSON, versioned. Baked bone rotations are canonical; IK targets and grips are stored alongside so poses can be re-solved live.
- **Video:** Movie Maker (`--write-movie`), spawned as a child process of the tool. Formats: AVI/MJPEG default, PNG sequence always, OGV optional. MP4 only via an optional external ffmpeg step, never required.
- **Grip attachment is the load-bearing feature.** Engine behaviour verified in `feasibility/`; the design in §5.3 is the tested one.

## 4. UX principle (unchanged, with concrete implications)

The instructor never opens the Godot editor. Therefore the tool implements its own: bone picking via auto-generated per-bone capsule colliders, a runtime rotation gizmo (three coloured rings; drag rotates about that axis; Shift snaps to 15°; a fourth "trackball" drag rotates freely), sliders for fine values, hover tooltips with plain names ("Right elbow"), confirmation dialogs for delete/overwrite, and Ctrl+Z / Ctrl+Y.

## 5. Functional requirements

### 5.1 Characters
- A scene holds 2–5 characters. Each has a unique `id` (`tori`, `uke1`, `uke2`, …), a display name, a **role** (`Tori` | `Uke` | `Other`), and a **skin colour**. The default palette is teal (Tori), amber (Uke 1), violet (Uke 2), green (Uke 3), rose (Uke 4), all chosen to stay distinct in print and for common colour-vision deficiency; a free colour picker is also available. Colour is applied to the skin material only, so it survives the later gi milestone (hands, feet and head stay coloured while the gi is white).
- Flat-shaded material with a slight rim so limbs read against each other. Bald, featureless.
- A Characters panel lists the scene's characters with add/remove/duplicate/rename and the colour swatch. Removing a character that is part of a grip detaches the grip after confirmation.
- Each character is an instance of one `CharacterRig` scene: `Node3D` root → `Skeleton3D` (imported) → `TwoBoneIK3D` ×4 (LArm, RArm, LLeg, RLeg) → `HandOrient` ×2 → `FingerCurl` modifier → target/pole `Marker3D`s under the rig root, per-bone `Area3D` pick capsules.
- Root transform (position on floor, yaw) is part of the pose. A "Turn 180°" and "Snap to floor" button exist per character.
- Floor: 1 m grid. Camera presets reference the Tori→primary-Uke line (§5.7).

### 5.2 Body posing
- FK: click a body part → gizmo appears at the joint → drag ring or use Euler sliders. Joint limits are soft hints (colour), not enforced.
- IK: each arm/leg has a draggable hand/foot target (a small sphere) and an elbow/knee pole (a smaller sphere, shown while the limb is selected). Toggle IK→FK bakes the current solved rotations into FK and disables the modifier; FK→IK moves the target to the current hand position first so nothing jumps.
- Reach indicator: if `|target − shoulder| > upper + lower` the target turns red and shows the shortfall in cm.
- Spine (`Spine`, `Chest`, `UpperChest`), `Neck`, `Head`: FK only.
- Undo/redo: Godot `UndoRedo`, one entry per drag gesture or slider release, covering bones, root, targets, grips, fingers, camera.

### 5.3 Grip attachments
**Behaviour** as v1 (attach a hand to a bone on another character, follows automatically, detachable, multiple, saved per pose), plus orientation, for any pair of characters in the scene. Two Ukes gripping Tori's two wrists, or Tori gripping Uke 1 while Uke 2 grips Tori, are all just entries in the same list.

**Data:** `{ "gripper": "uke1", "hand": "Right", "target_character": "tori", "target_bone": "RightLowerArm", "offset": Transform3D (local to target bone) }`. The offset is captured at attach time as `target_bone_world⁻¹ × hand_world`, so "attach" freezes the hand exactly where the instructor left it; the instructor can then nudge the offset with the gizmo while attached.

**Implementation (verified):**
- One `GripDirector` node owns the attachment list.
- For each attachment it connects to the *target* skeleton's `skeleton_updated` signal and, in that callback, sets the gripper's hand IK target to `target_skeleton.global_transform × get_bone_global_pose(target_bone) × offset`. Verified 0.000 mm tracking error regardless of scene-tree order. Never sync in `_process` (one-frame lag, verified).
- `HandOrient` (GDScript `SkeletonModifier3D`, child after the arm `TwoBoneIK3D`) sets the hand bone's global rotation to the target's rotation, so the palm/fingers follow the offset orientation. Verified exact.
- Evaluation order: the `GripDirector` builds the grip graph (gripper depends on target) each time the list changes and orders skeleton updates by topological sort, so chains (Uke 2 grips Uke 1 who grips Tori) resolve in one frame. Cycles (A grips B and B grips A) are permitted: the back edge resolves one frame late, which is invisible at 30 fps and disappears in baked stills. Document, do not "fix".
- Detaching bakes the hand's current solve into the IK target so nothing jumps.

### 5.4 Fingers
Curl slider 0–1 per finger per hand, driving proximal/intermediate/distal by weights (1.0, 0.8, 0.6) about the local flex axis found from the rest pose; thumb also gets an opposition slider. "Grip" preset button sets a natural grasp. Implemented as a `FingerCurl` `SkeletonModifier3D` placed before the IK so it never fights the hand orientation.

### 5.5 Data model
```
poses/<slug>.json
{ "format": 1, "name": "Katatedori Ikkyo — Grepp",
  "characters": [ { "id": "tori", "name": "Tori", "role": "Tori", "skin_color": "#1f8a8a", "visible": true,
                    "root": {pos, yaw}, "bones": { "RightUpperArm": [x,y,z,w], ... },
                    "ik": { "RightArm": { "mode": "ik", "target": Transform3D, "pole": Vector3 }, ... },
                    "fingers": { "Right": { "thumb":0.2, "index":0.0, ... } } },
                  { "id": "uke1", "name": "Uke", "role": "Uke", "skin_color": "#e0a030", ... },
                  { "id": "uke2", ... } ],
  "grips": [ {gripper, hand, target_character, target_bone, offset} ],
  "camera": null | { "preset": "Front" | "Side" | "Free", transform } }
sequences/<slug>.json
{ "format": 1, "name": "Katatedori Ikkyo", "camera": "Side" | "per_pose",
  "steps": [ { "pose": "katatedori_ikkyo_grepp", "transition": 0.0, "hold": 0.5 },
             { "pose": "katatedori_ikkyo_kuzushi", "transition": 0.6, "hold": 0.3 },
             { "pose": "katatedori_ikkyo_kake", "transition": 0.6, "hold": 1.0 } ] }
```
- New sequences pre-fill three steps named Grepp, Kuzushi, Kake; 2–5 steps allowed.
- Every pose in a sequence must contain the same character ids; the UI adds missing characters (at their previous pose) when a character is added mid-sequence, and asks before removing one from all poses.
- Copy/mirror pose works between any two characters, since all share the rig.
- Slugs: lowercase, transliterate å/ä→a, ö→o, non-alphanumerics→`_`.
- Saving reads bone rotations inside `skeleton_updated` (post-IK) so the baked pose equals what is on screen.
- Reload test: load → solve one frame → compare every bone to the file within 1e-4.

### 5.6 Interpolation (new)
Between step *i* and *i+1* over `transition` seconds with smoothstep easing:
- root position lerp, root yaw slerp; FK bones slerp; finger curls lerp; camera lerp if per-pose.
- A limb whose grip is active in **both** poses stays in IK and is re-solved live from the moving grip (no drift).
- A grip present in only one of the two poses: IK `influence` ramps 0→1 (appearing) or 1→0 (disappearing) across the transition while the FK rotations slerp underneath.
- Anything the instructor dislikes is fixed by inserting a pose, not by tuning curves.

### 5.7 Camera
Orbit/pan/zoom always. Presets **Front** (on the Tori→primary Uke line, 1.4 m high) and **Side** (perpendicular), both framing all visible characters. The primary Uke is the first character with role Uke; the Camera panel lets the instructor pick another. Sequence camera is fixed by default; per-pose optional. Both presets can be exported for every pose in one click ("Export Front+Side").

### 5.8 Export
- Still: `exports/<sequence_slug>_<phase_slug>[_front|_side].png` at 1920×1080 (2× supersampled then downscaled to soften edges), flat colour or transparent per setting. Uses a `SubViewport` with `transparent_bg`.
- Video: "Export video" writes `exports/<sequence_slug>.avi` (+ `exports/<sequence_slug>_frames/*.png`) by launching a second instance: `<exe> --path <project> --write-movie <file> --fixed-fps 30 -- --render-sequence <slug>`; the child loads the sequence, plays it, quits on finish. The parent shows progress and the output folder. Output directory is created first (Movie Maker does not create it). Optional: if `ffmpeg` is on PATH, offer MP4 conversion.
- Rendering each keyframe as a still is a side effect of video export (required, was nice-to-have; it is trivial in the child process).

## 6. Non-functional
Laptop without GPU (Compatibility renderer, verified on llvmpipe); ready in < 5 s; offline; Godot 4.6.x pinned in README with a link to the 4.6 docs; headless tests run with `godot --headless`; stills render in CI under Xvfb.

## 7. Milestones
See `build-plan.md`. Order: M0 project + character import (N-character data model from day one) → M1 FK posing + still → M2 IK + hand orient + fingers → M3 multiple characters + grips + skin colours → M4 save/load → M5 sequences + interpolation → M6 video export → M7 camera/export polish → M8 acceptance → M9 white gi (optional, later).

### 7.1 Clothing (M9, after the tool is proven)
- White gi (jacket, trousers, belt) as a skinned mesh sharing the rig, transferred weights from the body, toggle per character saved with the pose. Belt colour follows a per-character setting (defaults to the skin palette colour) as a second identification cue.
- A more anatomical body with detailed hands (MakeHuman/MPFB or a CC0 base mesh, rigged to the same humanoid bone names) is part of M9, not the mannequin phase.
- **No hakama** (decision 2026-09-05).

## 8. Acceptance techniques
Unchanged from v1 (Katatedori Ikkyo, Ushiro Ryotedori Zenponage, Katatedori Shihonage irimi) plus a fourth:

### 8.4 Test case 4 — three-person scene (technique to be named by the instructor)
Tori plus two Ukes, each Uke gripping one of Tori's wrists, Tori raising both arms as in 8.2 Kuzushi. Acceptance: both grips track independently, both Ukes have distinct skin colours in the exports, adding the third character required no special code path, Front and Side presets frame all three, and the JSON round-trips with three characters. The instructor names a real syllabus technique for this (a two-attacker form or a ryotemochi variant); until then the scene is a synthetic fixture.

Additions to the existing cases:
- 8.1 also asserts the grip **orientation** (Uke's palm down over the forearm) survives all three phases.
- 8.2 also asserts the reach warning appears if the instructor keeps grips attached in Kake and Uke is thrown beyond reach.
- 8.3 also asserts the pose "Grepp" file is literally reused (same slug referenced by two sequences).
- Each technique exports Front and Side stills for every phase and one AVI, all with predictable filenames.
- In every exported still the gripping hand and the gripped limb have different skin colours.

## 9. Open questions for the instructor
See `spec-review.md` §"Questions" (nine items: background default, manual grip editing, Godot availability, packaging depth, AVI vs MP4, Mixamo download vs CC0 mannequin, auto Front+Side export, three-person technique, footprint overlay).

## 10. Reference material
Unchanged from v1.

---

## Changes from v1 (v2.1 adds the last three)
- C1 pose transience → save/bake in `skeleton_updated`; IK→FK toggle bakes (§5.2, §5.5).
- C2 grip sync moved from `_process` to `skeleton_updated`; `GripDirector` owns attachments (§5.3).
- C3 hand orientation modifier and grip offset transform are required (§5.3).
- C4 reach warning required (§5.2, 8.2).
- C5/C6 video: AVI/PNG via spawned Movie Maker child; MP4 optional (§5.8).
- C7 Mixamo asset git-ignored; humanoid bone map; import scale 0.01 (§3).
- Added: root placement + floor, gizmo and picking spec, interpolation rules, cycles, JSON schema, slugs, Front+Side export, headless tests, M0/M8.
- 2–5 characters per scene with ids/roles; grip graph with topological ordering; Front/Side relative to Tori→primary Uke; test case 8.4 (§2.1, 5.1, 5.3, 5.5, 5.7, 8.4).
- Per-character skin colour, saved with the pose, applied to skin only so it survives the gi (§5.1).
- Hakama dropped; white gi and anatomical body deferred to M9 (§2.2, 7.1).
