class_name PoseImport
extends RefCounted
## Turns a video-derived draft (tools/video_pipeline, MediaPipe Pose) into saved poses and a
## sequence for this tool: a rough first draft the instructor then corrects, never a finished
## pose. Two file shapes are read: the pipeline's *draft* (33 world landmarks per figure and
## phase, the useful one) and its *Godot schema* (only per-limb direction vectors).
##
## What is taken from the data, and how:
##  - Each figure's facing, from the shoulder line (draft only), and a root side by side in
##    the order the file lists the figures (MediaPipe places every person at its own hips, so
##    the distance between them is not in the data; the instructor sets it).
##  - Arms and legs as IK: the elbow and hand (knee and ankle) are rebuilt from the landmark
##    directions with the mannequin's own bone lengths, from the rig's real shoulders and
##    hips, so proportions stay the mannequin's. Feet are kept on the floor by lowering the
##    hips when the legs bend.
##  - Spine and neck tilt as FK, from hips-to-shoulders and shoulders-to-ears.
##  - A grip, when the file marks one active: the gripper's hand nearest a forearm of the
##    target takes that forearm (attach_wrapped), and the gripper steps in until it reaches.
##  - A figure without landmarks in a phase (bodies overlapping at the throw) keeps its pose
##    from the previous phase, and the file's description is passed on as a note.
## Fingers, weapons and hand orientation are not in the data and are left for the instructor.

## MediaPipe world landmarks: x to the image's right, y down, z away from the camera. The
## tool's world: y up, the camera presets look along the Tori-Uke line. Same handedness once
## y and z are flipped.
static func to_world(v: Dictionary) -> Vector3:
	return Vector3(float(v.get("x", 0.0)), -float(v.get("y", 0.0)), -float(v.get("z", 0.0)))


const LIMBS := {
	"RightArm": ["right_shoulder", "right_elbow", "right_wrist"],
	"LeftArm": ["left_shoulder", "left_elbow", "left_wrist"],
	"RightLeg": ["right_hip", "right_knee", "right_ankle"],
	"LeftLeg": ["left_hip", "left_knee", "left_ankle"],
}
## Schema-format names for the same segments.
const SCHEMA_SEGMENTS := {
	"RightArm": ["upper_arm_R", "forearm_R"], "LeftArm": ["upper_arm_L", "forearm_L"],
	"RightLeg": ["thigh_R", "shin_R"], "LeftLeg": ["thigh_L", "shin_L"],
}
const FIGURE_SPACING := 0.9


## Imports `path`, writing "<technique> <phase>" poses into `poses_dir` and the sequence into
## `sequences_dir`. Returns {"sequence": Sequence, "poses": [paths], "notes": [strings]}.
## A coroutine: the skeletons need frames between steps.
static func import_draft(path: String, scene: PosingScene, director: GripDirector, controller: PoseController, camera, poses_dir: String, sequences_dir: String) -> Dictionary:
	var notes: Array[String] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "cannot open %s" % path}
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary or not data.has("sequence"):
		return {"error": "%s is not a video draft" % path}
	var technique: String = str(data.get("technique", path.get_file().get_basename()))
	var tree := Engine.get_main_loop() as SceneTree
	# Characters: one per figure named in the first phase, Tori-role for tori/shidachi.
	var first: Dictionary = data["sequence"][0]
	var figure_names: Array = first.get("figures", {}).keys()
	if figure_names.is_empty():
		return {"error": "no figures in %s" % path}
	if director:
		director.clear()
	if controller:
		controller.select(null, "")
	for w in scene.weapons.duplicate():
		scene.remove_weapon(w.weapon_id)
	for c in scene.characters.duplicate():
		scene.remove_character(c.character_id)
	await tree.process_frame
	var ids := {}
	# Side by side across the camera. MediaPipe puts every person at its own hips, so where
	# they stand relative to each other is not in the data; a figure facing the image's right
	# is put on the left and one facing left on the right, so two partners face each other.
	var order: Array = figure_names.duplicate()
	var facing_x := {}
	for fname in figure_names:
		facing_x[fname] = _facing_from(first["figures"][fname]).x
	order.sort_custom(func(a, b): return facing_x[a] > facing_x[b])
	for i in order.size():
		var fname: String = order[i]
		var tori_like := fname.to_lower() in ["tori", "nage", "shidachi"]
		var id := "tori" if tori_like else scene.next_free_id("uke")
		var rig := scene.add_character(id, fname.capitalize(), "Tori" if tori_like else "Uke")
		rig.position = Vector3(-FIGURE_SPACING * 0.5 + FIGURE_SPACING * i / maxf(order.size() - 1, 1), 0, 0)
		rig.rotation.y = PI * 0.5 if i == 0 else -PI * 0.5   # facing each other by default
		ids[fname] = id
	await tree.process_frame
	await tree.process_frame
	var seq := Sequence.new()
	seq.name = technique
	var poses: Array[String] = []
	for step_index in data["sequence"].size():
		var step: Dictionary = data["sequence"][step_index]
		var phase: String = str(step.get("phase", step.get("pose_name", "Pose %d" % (step_index + 1))))
		var figures: Dictionary = step.get("figures", {})
		for fname in figures:
			var rig := scene.get_character(ids.get(fname, ""))
			if rig == null:
				continue
			var fig = figures[fname]
			if fig is Dictionary and fig.has("raw_world_landmarks"):
				await _apply_landmarks(rig, fig["raw_world_landmarks"], tree)
			elif fig is Dictionary and fig.has("bone_directions"):
				await _apply_directions(rig, fig["bone_directions"], tree)
			else:
				var why: String = str(fig.get("description", fig.get("source", "no landmarks"))) if fig is Dictionary else "no landmarks"
				notes.append("%s, %s: kept the previous phase's pose (%s)" % [phase, fname, why])
		await _settle(tree, 3)
		# The grip, if the file marks one.
		var grip_info = step.get("grip_attachment")
		var grip_note := await _apply_grip(grip_info, ids, scene, director, tree)
		if grip_note != "":
			notes.append("%s: %s" % [phase, grip_note])
		var pose_name := "%s %s" % [technique, phase]
		var pose: Dictionary = await PoseFile.capture_baked(scene, director, camera, pose_name)
		var pose_path := PoseFile.pose_path(poses_dir, pose_name)
		var err := PoseFile.save(pose_path, pose)
		if err != OK:
			return {"error": "could not write %s" % pose_path}
		poses.append(pose_path)
		var last: bool = step_index == data["sequence"].size() - 1
		seq.steps.append({"pose": PoseFile.slugify(pose_name),
			"transition": 0.0 if step_index == 0 else float(step.get("transition_duration_s", 0.6)),
			"hold": float(step.get("hold_duration_s", 1.0 if last else 0.5))})
	var seq_path := Sequence.sequence_path(sequences_dir, technique)
	seq.save(seq_path)
	for key in ["source", "terminology_note", "role_correction_note", "hakama_caveat"]:
		if data.has(key):
			notes.append("%s: %s" % [key, str(data[key])])
	return {"sequence": seq, "sequence_path": seq_path, "poses": poses, "notes": notes}


static func _settle(tree: SceneTree, frames: int) -> void:
	for i in frames:
		await tree.process_frame


# ---------------------------------------------------------------- one figure

static func _lm(landmarks: Dictionary, name: String) -> Vector3:
	return to_world(landmarks.get(name, {}))


## Which way a figure faces, horizontal, from the shoulder line (the character's left
## shoulder is on its +X); zero when the figure has no landmarks.
static func _facing_from(fig) -> Vector3:
	if not fig is Dictionary or not fig.has("raw_world_landmarks"):
		return Vector3.ZERO
	var lm: Dictionary = fig["raw_world_landmarks"]
	var facing := (_lm(lm, "left_shoulder") - _lm(lm, "right_shoulder")).cross(Vector3.UP)
	facing.y = 0.0
	return facing.normalized() if facing.length() > 1e-4 else Vector3.ZERO


static func _apply_landmarks(rig: CharacterRig, lm: Dictionary, tree: SceneTree) -> void:
	var ls := _lm(lm, "left_shoulder"); var rs := _lm(lm, "right_shoulder")
	var facing := _facing_from({"raw_world_landmarks": lm})
	if facing.length() > 1e-4:
		rig.rotation.y = atan2(facing.x, facing.z)
	var dirs := {}
	for key in LIMBS:
		var names: Array = LIMBS[key]
		var a := _lm(lm, names[0]); var b := _lm(lm, names[1]); var c := _lm(lm, names[2])
		dirs[key] = [(b - a).normalized(), (c - b).normalized()]
	var hips := (_lm(lm, "left_hip") + _lm(lm, "right_hip")) * 0.5
	var shoulders := (ls + rs) * 0.5
	var ears := (_lm(lm, "left_ear") + _lm(lm, "right_ear")) * 0.5
	dirs["spine"] = (shoulders - hips).normalized()
	dirs["neck"] = (ears - shoulders).normalized()
	await _apply_directions(rig, {}, tree, dirs)


## `schema` holds the pipeline's schema-format vectors; `dirs` (limb key -> [upper, lower],
## plus spine/neck) is what _apply_landmarks computed. Either may be empty.
static func _apply_directions(rig: CharacterRig, schema: Dictionary, tree: SceneTree, dirs: Dictionary = {}) -> void:
	if dirs.is_empty():
		for key in SCHEMA_SEGMENTS:
			var segs: Array = SCHEMA_SEGMENTS[key]
			if schema.has(segs[0]) and schema.has(segs[1]):
				dirs[key] = [_vec(schema[segs[0]]), _vec(schema[segs[1]])]
		if schema.has("spine"):
			dirs["spine"] = _vec(schema["spine"])
		if schema.has("neck"):
			dirs["neck"] = _vec(schema["neck"])
	await tree.process_frame
	# Spine and neck first: the shoulders move with them, and the arms hang off the shoulders.
	if dirs.has("spine"):
		_aim(rig, "Spine", "Neck", dirs["spine"])
		await tree.process_frame
	if dirs.has("neck"):
		_aim(rig, "Neck", "Head", dirs["neck"])
		await tree.process_frame
	rig.position.y = 0.0
	for key in LIMBS:
		if not dirs.has(key):
			continue
		var limb: Limb = rig.limbs[key]
		var pts := _chain_points(rig, key, dirs[key])
		rig.set_limb_mode(key, Limb.Mode.IK)
		limb.set_orient_to_target(false)
		var target: Vector3 = pts[2]
		if not limb.is_arm:
			# Feet are planted: the data gives the stance (where the feet are across the floor),
			# never their height; leg landmarks under a hakama are the least reliable of all.
			target.y = rig.skeleton.get_bone_global_rest(rig.skeleton.find_bone(limb.end_bone)).origin.y
		limb.target.global_position = target
		# The pole steers the joint: put it where the elbow or knee is, pushed out of the line.
		var mid: Vector3 = (pts[0] + pts[2]) * 0.5
		var out: Vector3 = pts[1] - mid
		if out.length() > 0.02:
			limb.pole.global_position = pts[1] + out.normalized() * 0.25
		else:
			limb.reset_pole()
	await tree.process_frame
	# Legs the landmarks bend more than the mannequin can while standing on the floor: lower
	# the hips by the reach the legs are short, a few times, until both feet arrive.
	for attempt in 4:
		var short := 0.0
		for key in ["RightLeg", "LeftLeg"]:
			if dirs.has(key):
				short = maxf(short, rig.limbs[key].reach_shortfall())
		if short < 0.005:
			break
		rig.position.y -= short
		# The targets hang under the rig root and came down with it; plant the feet again.
		for key in ["RightLeg", "LeftLeg"]:
			if dirs.has(key):
				var limb: Limb = rig.limbs[key]
				limb.target.global_position.y = rig.skeleton.get_bone_global_rest(rig.skeleton.find_bone(limb.end_bone)).origin.y
		await tree.process_frame


## Joint, middle joint and end for a limb, from the rig's own root joint and bone lengths.
static func _chain_points(rig: CharacterRig, key: String, d: Array) -> Array:
	var limb: Limb = rig.limbs[key]
	var sk := rig.skeleton
	var root: Vector3 = rig.bone_world_transform(limb.root_bone).origin
	var l1 := sk.get_bone_global_rest(sk.find_bone(limb.root_bone)).origin.distance_to(sk.get_bone_global_rest(sk.find_bone(limb.middle_bone)).origin)
	var l2 := sk.get_bone_global_rest(sk.find_bone(limb.middle_bone)).origin.distance_to(sk.get_bone_global_rest(sk.find_bone(limb.end_bone)).origin)
	var mid: Vector3 = root + d[0] * l1
	return [root, mid, mid + d[1] * l2]


static func _vec(a) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), -float(a[1]), -float(a[2])).normalized()
	return Vector3.ZERO


## Rotates `bone` (FK) so the line from it to `toward` points along `want`, world space.
static func _aim(rig: CharacterRig, bone: String, toward: String, want: Vector3) -> void:
	if want.length() < 1e-4:
		return
	var sk := rig.skeleton
	var idx := sk.find_bone(bone)
	var from: Vector3 = rig.bone_world_transform(toward).origin - rig.bone_world_transform(bone).origin
	if from.length() < 1e-4:
		return
	var axis := from.normalized().cross(want.normalized())
	if axis.length() < 1e-4:
		return
	var angle := from.normalized().angle_to(want.normalized())
	var axis_skel := (sk.global_transform.basis.inverse() * axis).normalized()
	var g := rig.bone_world_transform(bone)
	var g_skel := sk.global_transform.affine_inverse() * g
	var new_basis := Basis(axis_skel, angle) * g_skel.basis.orthonormalized()
	var parent := sk.get_bone_parent(idx)
	var parent_basis := (sk.global_transform.affine_inverse() * rig.bone_world_transform(sk.get_bone_name(parent))).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(idx, (parent_basis.inverse() * new_basis).orthonormalized().get_rotation_quaternion())


# ---------------------------------------------------------------- grips

## Moves the gripper horizontally until its hand reaches the grip, the way the fixture builder
## does: the distance between the two figures is not in the data, the grip is.
static func _step_in(gripper: CharacterRig, grip: Grip, tree: SceneTree) -> void:
	if grip == null:
		return
	for attempt in 10:
		await _settle(tree, 3)
		var want: Vector3 = grip.desired_hand_transform().origin
		var e := want.distance_to(gripper.bone_world_transform(grip.hand + "Hand").origin)
		if e < 0.008:
			break
		var toward: Vector3 = want - gripper.bone_world_transform(grip.hand + "UpperArm").origin
		toward.y = 0.0
		if toward.length() > 1e-4:
			gripper.position += toward.normalized() * (e * 0.8 + 0.01)
	await _settle(tree, 3)

## The file names a gripper and a target but rarely which hand or which wrist; the hand that
## ended up nearest a forearm of the target takes it. Returns a note for the instructor.
static func _apply_grip(info, ids: Dictionary, scene: PosingScene, director: GripDirector, tree: SceneTree) -> String:
	if director == null or not info is Dictionary:
		return ""
	var raw: Dictionary = info.get("raw", info)
	if not bool(info.get("active", true)) or not raw.has("gripper") or not raw.has("grip_target"):
		return ""
	var gripper := scene.get_character(ids.get(str(raw["gripper"]), ""))
	var target := scene.get_character(ids.get(str(raw["grip_target"]), ""))
	if gripper == null or target == null or gripper == target:
		return ""
	# Already holding from the previous phase: keep the grip, but step in again for this phase.
	var held := director.grips_for(gripper.character_id)
	if not held.is_empty():
		await _step_in(gripper, held[0], tree)
		return ""
	var best_d := INF
	var best_hand := ""
	var best_bone := ""
	for hand in ["Right", "Left"]:
		var palm: Vector3 = gripper.bone_world_transform(hand + "Hand") * Weapon.palm_centre(gripper, hand)
		for bone in ["RightLowerArm", "LeftLowerArm"]:
			var a: Vector3 = target.bone_world_transform(bone).origin
			var b: Vector3 = target.bone_world_transform(bone.replace("LowerArm", "Hand")).origin
			var d := palm.distance_to(BodyCapsules.closest_on_segment(palm, a, b))
			if d < best_d:
				best_d = d; best_hand = hand; best_bone = bone
	if best_hand == "":
		return ""
	director.attach_wrapped(gripper, best_hand, target, best_bone)
	var curl := GripDirector.curl_for_bone(best_bone)
	for finger in FingerCurl.FINGERS:
		gripper.fingers.set_curl(best_hand, finger, minf(curl + 0.1, 1.0) if finger == "Thumb" else curl)
	await _step_in(gripper, director.grip_on_limb(gripper.character_id, best_hand + "Arm"), tree)
	return "%s's %s hand put on %s's %s (%.1f cm away in the data; the file says \"%s\" / \"%s\")" % [
		gripper.display_name, best_hand.to_lower(), target.display_name, best_bone, best_d * 100.0,
		str(raw.get("gripper_hand", "")), str(raw.get("grip_bone", ""))]
