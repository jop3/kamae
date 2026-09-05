# Feasibility results — Godot 4.6-stable (official build 89cea1439), Linux x86_64, headless / Xvfb + Mesa llvmpipe

Run on 2026-09-05 with `feasibility/run.sh`. Synthetic 4-bone arm skeletons were used (no Mixamo asset was available in the sandbox); every conclusion below is about engine behaviour, not about the character mesh.

## 1. Class availability (4.6-stable)

| Class | Present |
|---|---|
| `TwoBoneIK3D`, `IKModifier3D` | yes |
| `CopyTransformModifier3D`, `BoneConstraint3D`, `ModifierBoneTarget3D`, `LookAtModifier3D` | yes |
| `SkeletonProfileHumanoid` (bone-map retargeting on import) | yes |
| `FBXDocument` (built-in ufbx importer, no external FBX2glTF needed) | yes |
| `UndoRedo` | yes |

## 2. TwoBoneIK3D solves exactly, but the result is transient

`dbg.tscn`: end bone lands on the target at (0.3, 1.3, 0.1) with zero error, seen in both `modification_processed` and `skeleton_updated`. Reading `get_bone_global_pose()` in the next `_process` returns the **unmodified** pose (0, 1.6, 0). Skeleton3D applies modifier output to the skin and then restores the authored pose every frame.

Consequence: any code that wants the solved pose (saving a pose, baking IK to FK, computing a grip point) must read it inside `skeleton_updated` / `modification_processed`, never in `_process`.

## 3. Grip-follow tracking error (Tori's wrist drives Uke's IK target), reachable distance

| Sync mode | Uke before Tori in tree | Tori before Uke in tree |
|---|---|---|
| `process`: copy `BoneAttachment3D` transform in `_process` (the spec's suggestion) | 143 mm (1 frame lag) | 143 mm |
| `signal`: copy `BoneAttachment3D` transform inside Tori's `skeleton_updated` | **0.000 mm** | **0.000 mm** |
| `signal_direct`: compute `tori.global_transform * get_bone_global_pose()` inside `skeleton_updated` | **0.000 mm** | **0.000 mm** |
| `manual`: MANUAL modifier mode, `advance()`, then read `BoneAttachment3D` | 143 mm | 143 mm |
| `manual_direct`: MANUAL mode, `advance()`, then compute from bone pose | **0.000 mm** | **0.000 mm** |

`BoneAttachment3D` itself is exact when read inside `skeleton_updated`; it is stale when read in `_process` or right after `advance()`. Scene-tree order did not matter in this test, but the design should not rely on that: drive grips from the gripped skeleton's `skeleton_updated` signal.

## 4. Out-of-reach behaviour

With Uke placed so the wrist was ~44 mm beyond arm length, the exact modes reported a constant 45 mm error: the IK stops short, it does not stretch. The tool must show a reach warning rather than expect the hand to arrive.

## 5. End-bone orientation

`TwoBoneIK3D` does not rotate the end bone toward the target (by design, see godot PR 110120 and issue 112964). A 10-line GDScript `SkeletonModifier3D` subclass placed after the IK node (child order = execution order) set the hand's global rotation to the target's rotation exactly (`handrot.tscn`: z = 90.00002°). This is how "hand wraps the wrist" orientation will be done.

## 6. Still export with transparent background

`Viewport.transparent_bg = true` + `display/window/size/transparent` + `rendering/viewport/transparent_background`: `get_viewport().get_texture().get_image().save_png()` produced a 640×360 RGBA8 PNG, background alpha 0.0, subject alpha 1.0 (`transparent_still.png`). Rendered with the Compatibility (OpenGL) renderer on llvmpipe, i.e. no GPU needed.

## 7. Movie Maker

`--write-movie out/seq.png --fixed-fps 30` → RGBA PNG sequence + WAV. `out/clip.avi` → MJPEG AVI 640×360 @ 30 fps. `out/clip.ogv` → Theora. All three succeeded under Xvfb. Movie Maker does **not** create the output directory; the tool must `mkdir` first. No MP4/H.264 writer exists in Godot; MP4 needs an external ffmpeg step (optional).

## Known upstream issues checked

- godotengine/godot#113047 (infinite "Vectors must not be zero" errors from TwoBoneIK3D): fixed before 4.6-stable (#113055, Nov 2025). Not observed.
- godotengine/godot#112964: end bone ignores target rotation. Confirmed; handled by §5 above.
- godotengine/godot#113103: partially transparent edge pixels blended with black in viewport screenshots. Not tested (no antialiasing in the test); mitigation is to export at 2× resolution with MSAA off, or offer the flat-colour background as the default.
