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

## Grips

- **Capture grip offsets from the cached solved pose, not from the skeleton.** `Skeleton3D` reports
  the *unposed* pose outside `skeleton_updated`, so reading a bone there when attaching a grip puts
  the captured offset out by however far the limb was posed (half a metre in practice). The cached
  pose each `CharacterRig` keeps is correct in both contexts: it is refreshed at the start of that
  character's own update, so it is live inside the signal and last-frame outside it.
- **Order characters in the scene tree by their grip dependencies.** Godot evaluates skeletons in
  tree order, so a chain (Uke 2 grips Uke 1 who grips Tori) resolves in one frame only if targets
  come before grippers. The director topologically sorts the characters whenever the grip list
  changes, and breaks cycles by leaving the closing edge one frame behind.
- **A gripping hand that misses its point is out of reach, never stretched.** The only two legitimate
  outcomes are "exactly on the point" and "short by exactly the arm's reach shortfall", which is what
  `tests/test_m3.gd` asserts rather than pinning down particular coordinates.

## Still capture

`StillExport.capture()` awaits `RenderingServer.frame_post_draw`. Two constraints, both of which
manifest as a silent hang with the process spinning at full CPU:

- **A display is required.** Under `--headless` the callback never arrives. `capture()` checks
  `DisplayServer.get_name()` and returns `ERR_UNAVAILABLE` rather than hanging. On a server, run the
  app under `xvfb-run`; that is what `tests/run.sh` does.
- **The UI `CanvasLayer` must be hidden during the capture.** Capturing with it visible hangs the same
  way. This costs nothing in practice: an exported still must not contain the tool's own UI anyway, so
  the UI layer and the gizmo are always in `_hide_always()`.

## Character generation (MakeHuman / MPFB)

Three mistakes here all show up the same way: the mesh tears into ribbons or strands as soon as a
bone moves, while every numeric check on the skeleton still passes. `tools/generate_mannequin.py`
now asserts against all three, so a bad character cannot be exported silently.

- **Keep `detailed_helpers=True` when creating the body.** MPFB fits bone positions to MakeHuman's
  helper geometry. Without it the arm and hand bones land up to 47 cm away from the body, so any arm
  pose swings the skin around a pivot outside the mesh. The generator checks that no bone is further
  than 12 cm from the nearest body vertex.
- **Never delete the helper vertices with bmesh.** Rewriting the mesh that way detaches the skin
  weights from their vertices, leaving e.g. finger weights on hip vertices. Leave MPFB's Mask
  modifier in place and let the glTF exporter apply it. The generator checks that a 70 degree bend
  of one finger phalanx moves no vertex more than 12 cm (the correct arc is about 8.6 cm).
- **Bone renaming is safe.** Renaming armature bones in Blender renames the matching vertex groups,
  so the humanoid rename pass does not disturb weights.

## Hands and weapons

- **The finger flex axis is the across-the-knuckles line, not the palm normal.** The first
  `FingerCurl` rotated each phalanx about `finger_dir × across`, which is the palm normal, so a
  "curl" swept the fingers sideways across the palm. Every numeric check still passed (the
  fingertip-to-wrist distance shrinks either way) and the hands looked flat on anything they held.
  The axis is now `across` made perpendicular to the finger, with the sign taken from the rig's
  own slight rest-pose bend, and `tests/test_m2.gd` checks that the middle knuckle moves out
  through the palm rather than along it. Render a close-up of a closed fist before trusting any
  change here.
- **A held shaft runs through the palm, not the wrist joint.** The hand bone's origin is the wrist.
  `Weapon.palm_centre()` puts the anchor about 6 cm toward the fingers and 2 cm out from the palm,
  inside the curled fingers; every hold and weapon grip goes through it.
- **The thumb is not a fourth finger.** It sweeps across the palm about the palm normal and then
  folds; `FingerCurl.calibrate()` picks the sign of both axes by simulating the chain on the rest
  pose and keeping the combination that lands the tip over the index knuckle. Two attempts at
  deriving the signs from geometry were wrong on this rig.
- **Let the forearm carry the wrist twist.** `HandOrient` splits the rotation the hand still needs
  into twist about the elbow-to-wrist axis and the rest, and gives the forearm bone 70 % of the
  twist (`twist_share`). Rotating the forearm about its own axis moves neither joint, so this is
  free, and without it every bit of pronation is a kink at the wrist. Twist far beyond what a real
  forearm does still shears the mesh; that is a sign the pose or elbow pole is wrong, not the
  modifier.
- **Measure the palm axes from the rig; do not type them in.** Hand-typed palm normals had the
  left hand's sign wrong. `FingerCurl.calibrate()` now records the palm normal and the
  little-to-index direction per hand, and `Weapon.canonical_basis()` builds the hold from those.

## Posing pitfalls

- **A non-unit rotation axis silently adds scale.** `Quaternion(axis, angle)` expects a normalised
  axis. Transforming an axis into a bone's local frame can leave it unnormalised, and the resulting
  non-unit quaternion smuggles scale into the bone pose, which stretches the skinned mesh. Normalise
  after transforming.
- **Do not force an absolute hand orientation by default.** Making the hand take an arbitrary target
  rotation twists the wrist beyond what the single-bone forearm can absorb and shears the mesh.
  Hand orientation is opt-in per limb, and grips supply a captured offset that stays near the
  natural orientation.
- **Write baked poses after the frame boundary.** Rotations captured inside `skeleton_updated` must
  be written back on a later frame; writing them during the signal is undone by Skeleton3D's pose
  restore.
- **GDScript lambdas capture locals by value.** A callback that assigns to a local variable of the
  enclosing function changes only its own copy. Write into a Dictionary or Array instead.

## Project layout

- **Rendered output must not be scanned by the importer.** `tests/out/` carries a `.gdignore` so the PNGs
  the tests render are not turned into project resources. `tests/check_exports.gd` therefore reads them
  from disk with `Image.load_from_file()` and an absolute path, not through `res://`.
- **Renderer:** Compatibility (OpenGL). Verified to run and export correctly on llvmpipe software
  rendering, which is the "laptop without a GPU" requirement.
