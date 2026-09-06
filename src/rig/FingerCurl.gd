class_name FingerCurl
extends SkeletonModifier3D
## Per-finger curl, 0 (open) to 1 (closed fist), for both hands.
##
## Fidelity bar from the spec: one slider per finger, not per-phalanx IK. Each phalanx is rotated
## about its local Z axis, which is the flex axis of this rig (measured, see docs/engine-notes.md),
## by a share of the full curl angle.

const FINGERS := ["Thumb", "Index", "Middle", "Ring", "Little"]
const SIDES := ["Left", "Right"]
## Segment suffixes per finger. The thumb has a metacarpal where the others have a proximal.
const SEGMENTS := {
	"Thumb": ["Metacarpal", "Proximal", "Distal"],
	"Index": ["Proximal", "Intermediate", "Distal"],
	"Middle": ["Proximal", "Intermediate", "Distal"],
	"Ring": ["Proximal", "Intermediate", "Distal"],
	"Little": ["Proximal", "Intermediate", "Distal"],
}
## How much of the full curl each segment takes. Knuckle bends most, tip least.
const SEGMENT_WEIGHT := [1.0, 0.85, 0.65]
const FULL_CURL_DEG := 85.0
## The thumb folds across the palm rather than into it, so it curls less and about the same axis.
const THUMB_SCALE := 0.6

## side -> finger -> 0..1
var curls: Dictionary = {}
## bone index -> flex axis in that bone's own rest frame, measured from the rig (see calibrate()).
var _axes: Dictionary = {}
## side -> palm normal in the hand bone's rest frame (see calibrate()).
var _palm_normals: Dictionary = {}
## side -> little-finger-to-index direction in the hand bone's rest frame.
var _palm_widths: Dictionary = {}
var _calibrated := false


func _init() -> void:
	for side in SIDES:
		var d := {}
		for f in FINGERS:
			d[f] = 0.0
		curls[side] = d


func set_curl(side: String, finger: String, value: float) -> void:
	curls[side][finger] = clampf(value, 0.0, 1.0)


func get_curl(side: String, finger: String) -> float:
	return curls[side][finger]


func set_hand_curl(side: String, value: float) -> void:
	for f in FINGERS:
		set_curl(side, f, value)


## A natural grasp: fingers well closed, thumb wrapping.
func apply_grip_preset(side: String) -> void:
	set_curl(side, "Thumb", 0.75)
	set_curl(side, "Index", 0.85)
	set_curl(side, "Middle", 0.9)
	set_curl(side, "Ring", 0.9)
	set_curl(side, "Little", 0.85)


## Works out which way each phalanx bends, from the rig's own geometry rather than a guessed axis.
##
## A finger flexes about the axis that runs across the knuckles (the index-to-little line, made
## perpendicular to the finger). The sign is taken from the rig's rest pose: the mannequin's
## fingers already carry a slight natural bend, and the direction that bend turns in is the palm
## side. Rotating about the palm normal instead, or picking the sign by "whichever brings the tip
## nearer the wrist", both produce a finger that bends sideways across the palm and looks flat on
## anything it holds; that was the bug in the first version of this file.
func calibrate() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	_calibrated = true
	_axes.clear()
	_palm_normals.clear()
	_palm_widths.clear()
	for side in SIDES:
		var wrist_bone := sk.find_bone(side + "Hand")
		var index_bone := sk.find_bone(side + "IndexProximal")
		var little_bone := sk.find_bone(side + "LittleProximal")
		if wrist_bone < 0 or index_bone < 0 or little_bone < 0:
			continue
		var across := (sk.get_bone_global_rest(index_bone).origin - sk.get_bone_global_rest(little_bone).origin).normalized()
		_palm_widths[side] = (sk.get_bone_global_rest(wrist_bone).basis.inverse() * across).normalized()
		var palmward_sum := Vector3.ZERO
		var thumb_bones := {}
		for finger in FINGERS:
			var segments: Array = SEGMENTS[finger]
			var bones: Array[int] = []
			for seg in segments:
				var b := sk.find_bone("%s%s%s" % [side, finger, seg])
				if b >= 0:
					bones.append(b)
			if bones.size() < 3:
				continue
			var p0 := sk.get_bone_global_rest(bones[0]).origin
			var p1 := sk.get_bone_global_rest(bones[1]).origin
			var p2 := sk.get_bone_global_rest(bones[2]).origin
			var finger_dir := (p2 - p0).normalized()
			var axis := (across - finger_dir * across.dot(finger_dir)).normalized()
			if axis.length_squared() < 0.5:
				continue
			# The rest pose's own bend says which side the palm is on.
			var palmward := (p2 - p1).normalized() - (p1 - p0).normalized()
			palmward -= finger_dir * palmward.dot(finger_dir)
			if finger != "Thumb":
				palmward_sum += palmward
			var moved := Basis(axis, 0.5) * (p2 - p0) - (p2 - p0)
			if moved.dot(palmward) < 0.0:
				axis = -axis
			if finger == "Thumb":
				thumb_bones[side] = bones
				continue
			for b in bones:
				# Must be normalised: Quaternion(axis, angle) with a non-unit axis is not a unit
				# quaternion, and using it as a bone rotation smuggles scale into the pose, which
				# stretches the skinned mesh into strands.
				_axes[b] = (sk.get_bone_global_rest(b).basis.inverse() * axis).normalized()
		if palmward_sum.length_squared() > 0.0:
			_palm_normals[side] = (sk.get_bone_global_rest(wrist_bone).basis.inverse() * palmward_sum.normalized()).normalized()
		# The thumb does not curl like a finger. Its metacarpal sweeps across the palm (rotation
		# about the palm normal) and its two joints then fold the tip in, which together lay the
		# thumb over the closed fingers as in a grip. The signs of both axes are chosen by
		# simulating the chain on the rest pose and keeping the combination that brings the thumb
		# tip closest to a point just palmward of the index knuckle, which is where a gripping
		# thumb ends up. Guessing them from geometry got them wrong on this rig, twice.
		if thumb_bones.has(side) and palmward_sum.length_squared() > 0.0:
			var bones: Array[int] = thumb_bones[side]
			var palm_n := palmward_sum.normalized()
			var t0 := sk.get_bone_global_rest(bones[0]).origin
			var t2 := sk.get_bone_global_rest(bones[2]).origin
			var thumb_dir := (t2 - t0).normalized()
			var fold0 := thumb_dir.cross(palm_n).normalized()
			var goal := sk.get_bone_global_rest(index_bone).origin + palm_n * 0.025
			var best_d := INF
			var best: Array = []
			for sweep_sign in [1.0, -1.0]:
				for fold_sign in [1.0, -1.0]:
					var axes := [palm_n * sweep_sign, fold0 * fold_sign, fold0 * fold_sign]
					var tip := _thumb_tip(sk, bones, axes, 1.0)
					var d := tip.distance_to(goal)
					if d < best_d:
						best_d = d
						best = axes
			for i in bones.size():
				_axes[bones[i]] = (sk.get_bone_global_rest(bones[i]).basis.inverse() * best[i]).normalized()


## Where the thumb tip ends up after curling `amount` about the given world-space axes, computed
## from the rest pose alone (no skeleton update needed).
func _thumb_tip(sk: Skeleton3D, bones: Array[int], axes: Array, amount: float) -> Vector3:
	var parent_world := Transform3D()
	var prev_rest_global := Transform3D()
	var world := Transform3D()
	for i in bones.size():
		var rest_global := sk.get_bone_global_rest(bones[i])
		var local_rest := rest_global if i == 0 else prev_rest_global.affine_inverse() * rest_global
		var angle: float = deg_to_rad(FULL_CURL_DEG) * amount * SEGMENT_WEIGHT[i] * THUMB_SCALE
		var axis_local: Vector3 = (rest_global.basis.inverse() * axes[i]).normalized()
		var rotated := Transform3D(local_rest.basis * Basis(axis_local, angle), local_rest.origin)
		world = parent_world * rotated
		parent_world = world
		prev_rest_global = rest_global
	# The tip is one more segment beyond the distal joint; approximate it with the distal's length.
	var distal_len := sk.get_bone_global_rest(bones[2]).origin.distance_to(sk.get_bone_global_rest(bones[1]).origin)
	return world.origin + world.basis.y.normalized() * distal_len * 0.8


## Direction from the back of the hand out through the palm, in the hand bone's own frame, as
## measured from the rig. Weapons use it to put a shaft where the fingers close.
func palm_normal(side: String) -> Vector3:
	return _palm_normals.get(side, Vector3.ZERO)


## Direction across the palm from the little finger to the index finger, hand bone frame.
func palm_width(side: String) -> Vector3:
	return _palm_widths.get(side, Vector3.ZERO)


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if not _calibrated:
		calibrate()
	for side in SIDES:
		for finger in FINGERS:
			var amount: float = curls[side][finger]
			var scale: float = THUMB_SCALE if finger == "Thumb" else 1.0
			var segments: Array = SEGMENTS[finger]
			for i in segments.size():
				var bone := sk.find_bone("%s%s%s" % [side, finger, segments[i]])
				if bone < 0:
					continue
				var rest := sk.get_bone_rest(bone).basis.get_rotation_quaternion()
				if is_zero_approx(amount):
					sk.set_bone_pose_rotation(bone, rest)
					continue
				if not _axes.has(bone):
					continue   # a finger calibrate() could not work out; leave it at rest
				var weight: float = SEGMENT_WEIGHT[i]
				var angle := deg_to_rad(FULL_CURL_DEG) * amount * weight * scale
				var axis: Vector3 = _axes[bone]
				sk.set_bone_pose_rotation(bone, rest * Quaternion(axis, angle))
