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
- **`TwoBoneIK3D` swings the root bone but never twists it.** The humerus keeps its rest twist
  whatever the pole asks for, so with the hand overhead or behind the back the elbow crease ends up
  facing away from the fold and the mesh shows an elbow point on the inside of the arm. A person
  turns the humerus as the arm rises. `TwistFollow` (after each limb's IK node, before
  `HandOrient`) rotates the root bone about its own axis until the rest fold direction
  (`Anatomy.rest_bend_local`, from the mannequin's rest elbows and knees) lines up with the actual
  bend, and re-expresses the middle bone against the turned root so the hand does not move. Capped
  at 110° so an impossible pose stays visible to `Anatomy.joint_problems` instead of being hidden.

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
- **Two hands of one character on one weapon need a modifier between the arms.** The second
  hand's target cannot be set from that character's `skeleton_updated` (both arms have solved
  by then, so it trails a frame), nor predicted at frame start (the holding hand's rotation is
  only known after its solve). `ArmBridge` is a `SkeletonModifier3D` between the two arms'
  solvers; the director orders the holding arm first (`CharacterRig.put_arm_first`) and the
  bridge reads that hand live, moves the weapon and places the other hand before its arm solves.
  Verified exact (0.000 m) one frame after a 12 cm move in `tests/test_m3w.gd`.
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

## Movie Maker

- **Movie Maker records at the project's configured window size and ignores `--resolution`.**
  With a `window_width_override` set it records at the override. The project viewport is
  therefore 1920×1080 with no override, and `Main._ready()` shrinks the interactive window on
  small screens instead. The child render is checked by `tests/check_movie.gd`.
- **IK handles come back on every limb-mode change.** `CharacterRig.show_handles` (inherited
  from `PosingScene.show_handles`) keeps them hidden for the whole render; hiding them once at
  the start is not enough, since the sequence blend re-applies limb modes every frame.
- **A coroutine that awaits `skeleton_updated` resumes inside the skeleton update.** See
  "Write baked poses after the frame boundary" above; `PoseFile.capture_baked` awaits
  `process_frame` before returning for this reason.
- **Movie Maker does not create its output directory.** `MovieExport` makes it first.

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
- **A gripped wrist is a shaft too.** `GripDirector.attach_wrapped()` treats the gripped limb bone
  as a weapon axis: nearest point along the bone, same side the hand is on now, palm centre
  2 cm off the bone line, fingers across it. Attaching without the wrap freezes the hand wherever
  it happens to be, which for a hand hovering above a wrist looks like nothing at all.
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
- **A modifier must write every bone it owns, every pass.** Inside `_process_modification`,
  `get_bone_pose_rotation()` returns the authored value (the previous modifiers' output for bones
  they touched), so a modifier can compose with the authored pose (`FingerCurl` adds the curl on
  top of a hand-posed phalanx). But a modifier that writes nothing for a bone leaves that bone
  as the last thing the skeleton had for it: setting a finger's curl back to 0 and skipping the
  write left the finger curled. Write the unchanged authored value instead.
- **A coroutine that awaited `skeleton_updated` reads the solved pose afterwards.** It resumes
  inside the update, so a "synchronous" `get_bone_pose_rotation()` after the await returns the
  modified value, not the authored one. `PoseFile.capture_baked` reads the authored finger
  rotations before its first await for this reason.
- **A `MeshInstance3D` made in code has an empty `skeleton` path.** The importer writes `..`;
  `MeshInstance3D.new()` does not, and setting `skin` alone is not enough. Without the path the
  mesh draws in its rest pose whatever the bones do, silently. `Gi` sets the path after adding
  the mesh under the skeleton; `tests/test_gi.gd` checks that it resolves.
- **GDScript lambdas capture locals by value.** A callback that assigns to a local variable of the
  enclosing function changes only its own copy. Write into a Dictionary or Array instead.

## Project layout

- **Rendered output must not be scanned by the importer.** `tests/out/` carries a `.gdignore` so the PNGs
  the tests render are not turned into project resources. `tests/check_exports.gd` therefore reads them
  from disk with `Image.load_from_file()` and a path from `ProjectSettings.globalize_path()`, not
  through `res://`. Never hard-code the checkout path: the CI runner's differs.
- **A parse error in a `class_name` script hangs `--headless -s`** instead of failing: the global class
  cache cannot load and the main loop spins. `godot --headless --check-only -s file.gd` reports the
  error; `tests/run.sh` bounds every run with `timeout` for the same reason.
- **Skinning can be reproduced on the CPU** from `Mesh.surface_get_arrays()` (`ARRAY_BONES`,
  `ARRAY_WEIGHTS`, four per vertex) and `Skin.get_bind_pose()` (the inverse global rest), with the
  solved bone poses from `skeleton_updated`. `Anatomy.skin_problems` does this to check the mesh
  itself, about 30 ms per character.
- **Renderer:** Compatibility (OpenGL). Verified to run and export correctly on llvmpipe software
  rendering, which is the "laptop without a GPU" requirement.
