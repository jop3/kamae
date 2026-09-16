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
## Tenodesis at the fingertip: a DIP bent by hand (the wrap fit, the gizmo) rather than by the
## curl slider pulls its own DIP part-way with it, the way the flexor tendon that flexes the PIP
## flexes the DIP too. The curl slider already gives each segment its own share (SEGMENT_WEIGHT)
## and is left alone; this only adds to whatever the PIP was posed *beyond* that.
const DIP_FOLLOWS_PIP := 0.6
## The thumb folds across the palm rather than into it, so it curls less and about the same axis.
const THUMB_SCALE := 0.6
## How far past the distal joint the fingertip is, and the flesh on it: both for working out how
## far a finger has to close to rest on something (curls_onto).
const TIP_LENGTH := 0.022
const TIP_PAD := 0.008

## side -> finger -> 0..1
var curls: Dictionary = {}
## bone index -> flex axis in that bone's own rest frame, measured from the rig (see calibrate()).
var _axes: Dictionary = {}
## side -> palm normal in the hand bone's rest frame (see calibrate()).
var _palm_normals: Dictionary = {}
## side -> little-finger-to-index direction in the hand bone's rest frame.
var _palm_widths: Dictionary = {}
## side -> the middle of the four finger knuckles in the hand bone's rest frame.
var _knuckles: Dictionary = {}
## side+finger -> how far it can close before it is inside the palm (max_curl).
var _max_curls: Dictionary = {}
## The character this hand belongs to, for the palm's own surface. Null in a bare skeleton test,
## and then a curl is unclamped as it was.
var rig: Node = null
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
	_knuckles.clear()
	_max_curls.clear()
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
		var knuckle_sum := Vector3.ZERO
		var knuckle_n := 0
		for finger in FINGERS:
			if finger == "Thumb":
				continue
			var kb := sk.find_bone("%s%sProximal" % [side, finger])
			if kb < 0:
				continue
			knuckle_sum += sk.get_bone_global_rest(wrist_bone).affine_inverse() * sk.get_bone_global_rest(kb).origin
			knuckle_n += 1
		if knuckle_n > 0:
			_knuckles[side] = knuckle_sum / float(knuckle_n)
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


## The flexion axis of a phalanx in the character's rest space (positive toward the palm), as
## measured by calibrate(); zero for a bone that is not a phalanx. Joints builds the finger
## joints from these so the two never disagree about which way a finger bends.
func flex_axis_rest(bone: int) -> Vector3:
	var sk := get_skeleton()
	if sk == null or not _axes.has(bone):
		return Vector3.ZERO
	return (sk.get_bone_global_rest(bone).basis.orthonormalized() * _axes[bone]).normalized()


## The phalanx's own bend away from rest about its measured flex axis, radians, positive the
## way a positive curl closes it. Only the part of the rotation that lies about that axis; a
## bone posed purely as a hinge (as a finger joint is) has none anywhere else.
func _flex_angle(sk: Skeleton3D, bone: int, q: Quaternion) -> float:
	var rest_q := sk.get_bone_rest(bone).basis.get_rotation_quaternion().normalized()
	var d := (q.normalized() * rest_q.inverse()).normalized()
	if d.w < 0.0:
		d = -d
	var proj := Vector3(d.x, d.y, d.z).dot(_axes[bone].normalized())
	return 2.0 * atan2(proj, d.w)


## True for a phalanx bone (thumb included): the bones this modifier drives.
static func is_finger_bone(bone_name: String) -> bool:
	for finger in FINGERS:
		if finger in bone_name:
			return true
	return false


## Direction from the back of the hand out through the palm, in the hand bone's own frame, as
## measured from the rig. Weapons use it to put a shaft where the fingers close.
func palm_normal(side: String) -> Vector3:
	return _palm_normals.get(side, Vector3.ZERO)


## Direction across the palm from the little finger to the index finger, hand bone frame.
func palm_width(side: String) -> Vector3:
	return _palm_widths.get(side, Vector3.ZERO)


## Where `finger`'s joints would sit, in the hand bone's frame, if the hand were at `amount` of
## curl on the rest pose: the knuckle, the two joints after it and the tip (the distal joint
## carried on by TIP_LENGTH). The same walk down the chain that _process_modification does, so
## the two cannot drift apart.
func chain_at_curl(side: String, finger: String, amount: float) -> Array:
	return _chain_raw(side, finger, minf(amount, max_curl(side, finger)))


## How far `finger` can close before it would be inside the palm: the curl at which its tip
## meets the palm's own surface (CharacterRig.palm_surface), measured on the rest chain. A curl
## of 1 means a closed hand, not a hand closed through itself, so this is what 1 now is.
func max_curl(side: String, finger: String) -> float:
	var key := side + finger
	if _max_curls.has(key):
		return _max_curls[key]
	var limit := 1.0
	var box: Dictionary = rig.palm_box(side) if rig != null else {}
	if not box.is_empty():
		var n: Vector3 = palm_normal(side).normalized()
		var w: Vector3 = palm_width(side).normalized()
		# A curled finger lies *across the front* of the palm, which is not inside it; inside is
		# between the palm's own surface and the back of the hand. A finger's own thickness keeps
		# its bones that far out of the box.
		var inside := func(p: Vector3) -> bool:
			if p.y < float(box["y_min"]) - TIP_PAD or p.y > float(box["y_max"]) + TIP_PAD:
				return false
			if absf(p.dot(w)) > float(box["half_width"]) + TIP_PAD:
				return false
			var d: float = p.dot(n)
			return d < float(box["front"]) + TIP_PAD and d > float(box["back"]) - TIP_PAD
		# A knuckle is part of the hand and sits inside that box from the start; only the joints
		# that begin outside it can be driven into it.
		var rest := _chain_raw(side, finger, 0.0)
		var loose := []
		for i in rest.size():
			loose.append(not inside.call(rest[i]))
		var in_palm := func(amount: float) -> bool:
			var chain := _chain_raw(side, finger, amount)
			for i in chain.size():
				if loose[i] and inside.call(chain[i]):
					return true
			return false
		if in_palm.call(1.0):
			var lo := 0.0
			var hi := 1.0
			for i in 12:
				var mid := 0.5 * (lo + hi)
				if in_palm.call(mid):
					hi = mid
				else:
					lo = mid
			limit = lo
	_max_curls[key] = limit
	return limit


func _chain_raw(side: String, finger: String, amount: float) -> Array:
	var sk := get_skeleton()
	if sk == null:
		return []
	if not _calibrated:
		calibrate()
	var hand := sk.find_bone(side + "Hand")
	if hand < 0:
		return []
	var scale: float = THUMB_SCALE if finger == "Thumb" else 1.0
	var segments: Array = SEGMENTS[finger]
	var to_hand: Transform3D = sk.get_bone_global_rest(hand).affine_inverse()
	var parent_rest: Transform3D = sk.get_bone_global_rest(hand)
	var carried: Transform3D = parent_rest
	var out: Array = []
	for i in segments.size():
		var bone := sk.find_bone("%s%s%s" % [side, finger, segments[i]])
		if bone < 0:
			return []
		var rest: Transform3D = sk.get_bone_global_rest(bone)
		carried = carried * (parent_rest.affine_inverse() * rest)
		if _axes.has(bone):
			carried = carried * Transform3D(Basis(Quaternion(_axes[bone], deg_to_rad(FULL_CURL_DEG) * amount * SEGMENT_WEIGHT[i] * scale)), Vector3.ZERO)
		parent_rest = rest
		out.append(to_hand * carried.origin)
	out.append(to_hand * (carried * Vector3(0, TIP_LENGTH, 0)))
	return out


## How far each finger has to close for the hand to rest on a shaft of `radius` lying along
## `axis` through `seat` (both in the hand bone's frame): as far as it goes before any part of
## it — knuckle, joints or tip — would be inside that surface. A finger fitted by its tip alone
## still lies straight across what it holds with its middle inside it, which is what the
## close-up renders showed; this closes it until it is resting on the thing.
##
## It replaces a guessed number per grip: a fist closed by a constant drives its fingers through
## a thin wrist and leaves them short of a thick thigh, and what a finger has to do depends on
## what it is holding.
func curls_onto(side: String, seat: Vector3, axis: Vector3, radius: float) -> Dictionary:
	var want := radius + TIP_PAD
	var dir := axis.normalized()
	var clear := func(finger: String, amount: float) -> float:
		var worst := INF
		for p: Vector3 in chain_at_curl(side, finger, amount):
			var v: Vector3 = p - seat
			worst = minf(worst, (v - dir * v.dot(dir)).length())
		return worst
	var out := {}
	for finger in FINGERS:
		if clear.call(finger, 1.0) >= want:
			out[finger] = 1.0   # closes fully without ever meeting it
			continue
		if clear.call(finger, 0.0) < want:
			# Open, the finger is already inside what the hand holds — the thumb, usually, lying
			# across the shaft rather than along it. Closing it may take it over and clear, so
			# the whole range is tried and the least buried kept.
			var best := 0.0
			var best_clear := -INF
			for step in 21:
				var c := step / 20.0
				var d: float = clear.call(finger, c)
				if d > best_clear:
					best_clear = d
					best = c
			out[finger] = best
			continue
		var lo := 0.0   # clear
		var hi := 1.0   # into it
		for i in 12:
			var mid := 0.5 * (lo + hi)
			if clear.call(finger, mid) >= want:
				lo = mid
			else:
				hi = mid
		out[finger] = lo
	return out


## The middle of the four finger knuckles in the hand bone's frame — where the palm ends and the
## fingers begin, and where anything held in a fist lies across it.
func knuckle_centre(side: String) -> Vector3:
	return _knuckles.get(side, Vector3(0, 0.09, 0))


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if not _calibrated:
		calibrate()
	# The curl is added on top of whatever rotation each phalanx already carries, so a finger
	# can also be posed on its own (spread, or one joint bent) with the gizmo or the sliders;
	# the curl then closes it from there. This modifier runs first, so the value read here is the
	# authored pose, never another modifier's output. Saved poses store that authored value
	# (PoseFile), otherwise a reloaded curl would be applied twice.
	# Every phalanx is written every pass, an open finger with its authored value unchanged: a
	# modifier that writes nothing leaves the skeleton unrefreshed and the finger stuck curled.
	for side in SIDES:
		for finger in FINGERS:
			var amount: float = curls[side][finger]
			var scale: float = THUMB_SCALE if finger == "Thumb" else 1.0
			var segments: Array = SEGMENTS[finger]
			# The PIP's own hand-authored bend (read before this pass touches it), for the DIP to
			# partly follow below. Zero for the thumb, which has no PIP in this chain.
			var pip_authored_flex := 0.0
			if finger != "Thumb":
				var pip_bone := sk.find_bone("%s%sIntermediate" % [side, finger])
				if pip_bone >= 0 and _axes.has(pip_bone):
					pip_authored_flex = _flex_angle(sk, pip_bone, sk.get_bone_pose_rotation(pip_bone))
			amount = minf(amount, max_curl(side, finger))
			for i in segments.size():
				var bone := sk.find_bone("%s%s%s" % [side, finger, segments[i]])
				if bone < 0:
					continue
				var q := sk.get_bone_pose_rotation(bone)
				if _axes.has(bone):
					var angle := 0.0
					if not is_zero_approx(amount):
						angle += deg_to_rad(FULL_CURL_DEG) * amount * SEGMENT_WEIGHT[i] * scale
					if finger != "Thumb" and segments[i] == "Distal":
						angle += DIP_FOLLOWS_PIP * pip_authored_flex
					if not is_zero_approx(angle):
						q = q * Quaternion(_axes[bone], angle)
				sk.set_bone_pose_rotation(bone, q)
