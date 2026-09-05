# Engine notes (Godot 4.6)

Behaviour found by testing on 4.6-stable that the code depends on. Each entry says what breaks if it
is ignored, so a future change does not quietly reintroduce the problem.

## Skeleton and IK

- **Modifier output is transient.** `Skeleton3D` applies modifier results to the skin and then restores
  the authored pose. Reading `get_bone_global_pose()` in `_process` returns the *unsolved* pose. Read it
  in `skeleton_updated` (or `modification_processed`) instead. Pose saving, IK baking and grip syncing
  all rely on this.
- **Grip follow must sync in `skeleton_updated`.** Copying a gripped bone's transform to an IK target in
  `_process` lags one frame (143 mm at test speed); doing it in the gripped skeleton's `skeleton_updated`
  is exact (0.000 mm). See `feasibility/results/RESULTS.md`.
- **`TwoBoneIK3D` never rotates the end bone.** Hand orientation needs a separate `SkeletonModifier3D`
  placed after the IK node (child order is execution order).
- **IK does not stretch.** An out-of-reach target leaves the hand short by the shortfall, so the UI has to
  warn rather than assume the hand arrives.

## Still capture

`StillExport.capture()` awaits `RenderingServer.frame_post_draw`. Two constraints, both of which
manifest as a silent hang with the process spinning at full CPU:

- **A display is required.** Under `--headless` the callback never arrives. `capture()` checks
  `DisplayServer.get_name()` and returns `ERR_UNAVAILABLE` rather than hanging. On a server, run the
  app under `xvfb-run`; that is what `tests/run.sh` does.
- **The UI `CanvasLayer` must be hidden during the capture.** Capturing with it visible hangs the same
  way. This costs nothing in practice: an exported still must not contain the tool's own UI anyway, so
  the UI layer and the gizmo are always in `_hide_always()`.

## Project layout

- **Rendered output must not be scanned by the importer.** `tests/out/` carries a `.gdignore` so the PNGs
  the tests render are not turned into project resources. `tests/check_exports.gd` therefore reads them
  from disk with `Image.load_from_file()` and an absolute path, not through `res://`.
- **Renderer:** Compatibility (OpenGL). Verified to run and export correctly on llvmpipe software
  rendering, which is the "laptop without a GPU" requirement.
