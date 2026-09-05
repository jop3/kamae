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
			for b in bones:
				# Must be normalised: Quaternion(axis, angle) with a non-unit axis is not a unit
				# quaternion, and using it as a bone rotation smuggles scale into the pose, which
				# stretches the skinned mesh into strands.
				_axes[b] = (sk.get_bone_global_rest(b).basis.inverse() * axis).normalized()
		if palmward_sum.length_squared() > 0.0:
			_palm_normals[side] = (sk.get_bone_global_rest(wrist_bone).basis.inverse() * palmward_sum.normalized()).normalized()


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
	if _axes.is_empty():
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
				var weight: float = SEGMENT_WEIGHT[i]
				var angle := deg_to_rad(FULL_CURL_DEG) * amount * weight * scale
				var axis: Vector3 = _axes.get(bone, Vector3(0, 0, 1))
				sk.set_bone_pose_rotation(bone, rest * Quaternion(axis, angle))
