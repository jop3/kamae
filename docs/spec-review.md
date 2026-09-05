# Spec review: Aikido Posing Machine (draft v1)

Reviewed 2026-09-05 against Godot 4.6-stable, with the engine claims actually exercised in `feasibility/` (see `feasibility/results/RESULTS.md`). Verdict first, then what holds, what needs changing, what is missing, and what to ask the instructor. The revised spec incorporating all of this is `docs/spec-v2.md`; the build plan is `docs/build-plan.md`.

## Verdict

The tool is buildable as specified, in Godot 4.6, with no third-party dependencies. Every high-risk claim in the spec checks out with one important correction to the suggested grip implementation and one correction to the video format claim. The single biggest hidden cost is not IK or grips at all: it is the custom in-app posing UI (click-to-select, rotation gizmo, undo), which the spec treats as a given but is the largest body of code.

## What the tests confirmed

1. **Godot 4.6 IK stack exists and works.** 4.6-stable shipped January 2026 with `IKModifier3D` and `TwoBoneIK3D`. Configuration is per index: `setting_count`, `set_root_bone_name(i)`, `set_middle_bone_name(i)`, `set_end_bone_name(i)`, `set_target_node(i, NodePath)`, `set_pole_node(i, NodePath)`. The solve is exact and deterministic.
2. **Two-body grip follow is achievable with zero tracking error**, including with the gripping character earlier in the scene tree than the gripped one, if the IK target is synced inside the gripped skeleton's `skeleton_updated` signal.
3. **Transparent still export works** (RGBA PNG, alpha 0 background) with the Compatibility renderer on software OpenGL, so it will run on a laptop without a GPU.
4. **Movie Maker works headless-ish** (Xvfb) and produces PNG sequence, MJPEG AVI, and Theora OGV at a fixed 30 fps.
5. **Native FBX import** (ufbx) is built in, so a Mixamo FBX drops straight into the project. `SkeletonProfileHumanoid` is available for renaming `mixamorig:*` bones to standard humanoid names on import.

## Corrections to the spec

### C1. Modifier results are transient (affects §5.2, §5.5, §5.3)
Skeleton3D applies IK output to the skin and then restores the authored bone pose every frame. Reading a bone pose in `_process` after IK returns the *unsolved* pose. This changes three things:
- Saving a pose must capture bone rotations inside `skeleton_updated` (or store IK targets and re-solve on load). v2 does both: baked rotations are the canonical data, IK targets and grips are stored alongside.
- The IK→FK toggle (§5.2) is implemented as "bake the current solve into FK rotations, then disable the modifier", which the instructor will read as "freeze the arm where it is". This is a feature, not a workaround.
- Grip sync code must run in `skeleton_updated`, not `_process`.

### C2. The suggested grip implementation lags one frame (§5.3)
"Set the IK target's global transform each `_process` tick from a `BoneAttachment3D`" measured a one-frame lag (143 mm at test speed). Synced inside `skeleton_updated`, error is 0.000 mm. `BoneAttachment3D` is fine as a marker but unnecessary; computing `skeleton.global_transform * get_bone_global_pose(bone)` is simpler and equally exact. v2 specifies a single `GripDirector` that owns all attachments and does the sync in the right callback.

### C3. IK does not orient the hand (§5.3, §5.4)
`TwoBoneIK3D` deliberately leaves end-bone rotation alone. A grip is a position **and** an orientation (palm down over the forearm, thumb around). v2 adds a required `HandOrient` modifier (a small GDScript `SkeletonModifier3D`, proven in `handrot.tscn`) that runs after the IK and applies a per-grip rotation offset relative to the gripped bone. Without this the grip "holds" but the hand can point anywhere.

### C4. IK cannot stretch; out-of-reach grips stop short (§8.2)
Confirmed: with the target 45 mm beyond reach the hand stops 45 mm short. This is exactly the §8.2 case (Uke thrown far while still attached). v2 makes the reach warning a requirement: colour the hand target red and show the shortfall in centimetres when `distance(shoulder, target) > upper + lower arm length`.

### C5. No MP4/H.264 output (§5.7)
Godot's Movie Maker writes OGV (Theora), AVI (MJPEG), or PNG sequence only. v2 sets the default to AVI/MJPEG (Word embeds AVI; files are large but clips are seconds long) with PNG sequence always written as well, and documents an *optional* one-line ffmpeg conversion to MP4 for users who have ffmpeg. This keeps the "no third-party dependency" rule.

### C6. Movie Maker is a launch-time mode (§5.7)
It is enabled by launching Godot with `--write-movie`. The running tool cannot switch into it. v2 specifies that "Export video" spawns a second instance of the same executable with `--write-movie <file> --fixed-fps 30 -- --render-sequence <name>` and shows progress until it exits. Also: Movie Maker does not create the output directory.

### C7. Mixamo assets cannot be fetched by the agent and must not be committed (§3, §5.1)
Mixamo downloads require an Adobe login; the sandbox got 403. Mixamo terms allow unlimited use of characters *inside* a project but forbid redistributing the raw files. This repository is public. v2 therefore: the instructor downloads X Bot (T-pose FBX) once; the file lives in `assets/characters/` which is git-ignored; the build has a one-time "Import character" step and a documented CC0 fallback if the instructor prefers a redistributable mannequin.

### C8. Version pin
4.6.x is right. The docs site's "stable" already points at 4.7, so the README must link the 4.6 docs explicitly. IK API is unchanged between 4.6 and 4.7 dev so far; still pin.

## Gaps in the spec (added in v2)

- **Whole-body placement.** Nothing in v1 says how the instructor moves or turns a whole character (Uke behind Tori, Uke lying on the floor for Kake). v2 adds a root translate/rotate control per character and a floor grid with a snap-to-floor helper. Every Kake pose in §8 needs this.
- **Rotation gizmo is the largest UI item.** Godot ships no runtime gizmo. v2 specifies a minimal one (three rings, drag = rotate about that axis, shift = 15° snapping) and a "trackball" fallback, and budgets it explicitly.
- **Click-to-select needs collision proxies.** Mixamo meshes have no colliders. v2 specifies auto-generated capsule `Area3D`s per bone (from bone rest length) for picking.
- **Bone naming.** Import with the Humanoid bone map so both characters use `LeftHand`, `RightLowerArm` and so on. Pose files then work across any humanoid-mapped character, which also unlocks pose mirroring.
- **Interpolation rules.** v1 says poses are interpolated but not how grips behave during a transition. v2: root transforms lerp/slerp, FK bones slerp, arms with an attachment active in *both* neighbouring poses are re-solved live (so the grip never drifts), an attachment present in only one neighbour fades the IK `influence` 0→1 or 1→0 over the transition.
- **Mutual grips** (Tori grips Uke while Uke grips Tori) form a cycle. v2 defines a fixed evaluation order (attachments are processed in list order, each source skeleton is evaluated before its dependent) and says cycles are allowed but resolved one frame late for the second link.
- **Pose file format**: JSON, one file per pose, one per sequence, quaternions as arrays, versioned with a `format` field. Human-diffable, trivially testable headless.
- **Filenames**: slugify with Swedish transliteration (å→a, ä→a, ö→o) so `Katatedori Ikkyo — Kake` becomes `katatedori_ikkyo_kake.png`.
- **Headless test harness**: the feasibility scripts become the project's regression tests; poses can be loaded, solved and checked (grip error, reach) without a display, and stills rendered under Xvfb in CI.
- **Scale**: Mixamo characters import at centimetre scale (bone lengths ~100× too large for Godot's metre units) unless the import scale is set to 0.01. State it.

## Things in v1 that are right and should stay

- Engine choice, Mixamo stock rig, Movie Maker for video, no physics, manual posing only.
- Milestone order with grip attachment third (early). The feasibility work here effectively pre-paid the riskiest part of M3.
- The three acceptance techniques. They exercise single grip, two grips, and grip reversal, in that order of difficulty. No change.
- Finger curl slider fidelity bar.

## Questions for the instructor (v1's four, plus new ones)

1. Transparent vs flat background default? Both work; flat is safer at antialiased edges.
2. Manual add/remove of attachments per pose is acceptable for Shihonage? (Assumed yes.)
3. Godot version: 4.6.x confirmed available; no action unless the instructor's machine cannot run 4.6.
4. One-off local build vs packaged for other clubs? Affects README depth and whether the CC0 fallback character becomes the default.
5. **New:** Is AVI (MJPEG) acceptable for video, or is MP4 required (then ffmpeg becomes an optional install)?
6. **New:** Can the instructor download Mixamo X Bot and place the FBX in the project? Or should the tool ship with a CC0 mannequin instead (loses the "known-good finger rig" argument, gains redistributability)?
7. **New:** Is a per-technique fixed camera the norm, with Front and Side both exported automatically for every pose? (Cheap to do; doubles usefulness of each pose for the handout.)
8. **New:** Which syllabus technique should be the three-person acceptance case (spec-v2 §8.4)?
9. **New:** Should each pose also record which foot bears weight / footprints on the floor grid? The handout emphasises footwork; a simple floor footprint overlay in exports would help and is cheap.
