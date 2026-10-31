class_name Ukemi
extends RefCounted
## Falls: a forward roll, a backward roll, and being laid face down.
##
## A body rolling on a mat turns about whatever part of it is touching the mat, and that part
## travels — shoulder, back, hip, feet. A character's root is at its feet, so turning the root is
## turning about the feet: pitch it forward and the body swings down through the floor like a
## felled tree, which is what the first hand-made ukemi did. `ground()` is the whole trick. Shape
## the body however the fall wants it, turn it as far as the fall has got, then drop or lift the
## root until the lowest part of the body rests on the mat. The pivot comes out where the contact
## is, without anyone having to work out where that is.
##
## The three falls a technique needs (spec §8 and the ones after it: forward for a projection,
## backward for a drop, face down for a pin) are the same body turned different ways, so they are
## one function with a `Kind`.
##
##     Ukemi.shape(rig, Ukemi.Kind.FORWARD, t)   # t: 0 upright, 1 back on the feet
##     await settle()                            # the skeleton has to solve before it can be read
##     Ukemi.ground(rig)
##
## Nothing here touches where the fall travels: the technique says where Uke lands, this says what
## his body is doing while he gets there.

enum Kind { FORWARD, BACKWARD, PRONE }

## The mat.
const MAT_Y := 0.0
## A tuck, in degrees of flexion, at its tightest. Well inside what Anatomy allows a trunk.
const TUCK := {"Spine": 42.0, "Chest": 30.0, "Neck": 25.0}
## Hip and knee flexion at the tightest part of a roll.
const HIP_TUCK := 70.0
const KNEE_TUCK := 85.0
## How far into the roll the tuck is complete, and how late it starts to open out again.
const TUCK_IN := 0.25
## A backward fall is tucked almost at once: the squat comes before anything turns.
const TUCK_IN_BACKWARD := 0.1
## The squat at the start of a backward fall, on top of the tuck: hips and knees, degrees.
const SQUAT_HIP := 25.0
const SQUAT_KNEE := 35.0
const TUCK_OUT := 0.75
## Where the arms go while rolling, as an offset from the shoulder in the body's own frame.
const ARM_ROLLING := Vector3(-0.10, -0.22, 0.24)
const ARM_REACHING := Vector3(-0.06, -0.34, 0.34)


## Poses `rig` at `t` (0..1) through a fall. Call `ground()` after the skeleton has solved.
static func shape(rig: CharacterRig, kind: int, t: float) -> void:
	t = clampf(t, 0.0, 1.0)
	var tuck := tuck_amount(kind, t)
	var side: Vector3 = rig.global_transform.basis.x
	var angles := tuck_angles(kind, t)
	for leg in ["Right", "Left"]:
		rig.set_limb_mode(leg + "Leg", Limb.Mode.FK)
	for bone: String in angles:
		bend_about(rig, bone, side, angles[bone])
	# The arms are put where the fall wants them, which means taking them over: call this after
	# the grips are released, or it will fight whatever is holding the hand.
	for arm in ["Right", "Left"]:
		var limb: Limb = rig.limbs[arm + "Arm"]
		# The arm relaxes as it lets go: a forearm keeps whatever roll its last grip baked into
		# it (the IK solver never touches roll), and a fist that took a wrist from behind was
		# rolled to the edge of what an elbow does.
		var sk := rig.skeleton
		for bone in [arm + "UpperArm", arm + "LowerArm", arm + "Hand"]:
			var i := sk.find_bone(bone)
			sk.set_bone_pose_rotation(i, sk.get_bone_rest(i).basis.get_rotation_quaternion())
		limb.set_orient_to_target(false)   # the hand is no longer turned to a grip's target
		rig.fingers.set_hand_curl(arm, 0.2)   # and the fist opens to meet the mat
		rig.set_limb_mode(arm + "Arm", Limb.Mode.IK)
		var reach: Vector3 = ARM_REACHING.lerp(ARM_ROLLING, tuck)
		if arm == "Left":
			reach.x = -reach.x
		limb.set_influence(1.0)
		limb.target.global_position = rig.bone_world_transform(arm + "UpperArm").origin \
			+ rig.global_transform.basis * reach
	rig.rotation.x = deg_to_rad(pitch_deg(kind, t))


## How far through its turn the body is, in degrees, at `t`. A roll is one whole turn about the
## body's own sideways axis; being laid face down is a quarter of one and stops there.
##
## A fall does not turn at an even rate, and the reference clips (aikido ukemi, forward and back)
## agree on how it starts. Going backward the body first goes *down* — a deep squat over the rear
## foot, then sitting close to the heel — and only then rolls back over a round back; going
## forward it bends low and reaches the leading arm to the mat before it turns over it. So the
## first third of a roll turns slowly and then catches up (TURN_START); from there on the turn is
## even, which is where every technique's fall keyframes already are (t 0.35, 0.4, 0.7, 0.75).
static func pitch_deg(kind: int, t: float) -> float:
	match kind:
		Kind.FORWARD:
			return _turn(FORWARD_START, t)
		Kind.BACKWARD:
			return -_turn(BACKWARD_START, t)
		_:
			return 90.0 * minf(t * 2.0, 1.0)


## How far a roll has turned (degrees) through its start, as [t, degrees] points; from the last
## point on it is 360·t.
const FORWARD_START := [[0.0, 0.0], [0.1, 14.0], [0.2, 45.0], [0.3, 108.0]]
const BACKWARD_START := [[0.0, 0.0], [0.1, 5.0], [0.2, 32.0], [0.3, 108.0]]


static func _turn(points: Array, t: float) -> float:
	var last: Array = points[-1]
	if t >= last[0]:
		return 360.0 * t
	for i in range(1, points.size()):
		if t <= points[i][0]:
			var a: Array = points[i - 1]
			var b: Array = points[i]
			return lerpf(a[1], b[1], (t - a[0]) / (b[0] - a[0]))
	return 360.0 * t


## Every bend of a fall's tuck at `t`, degrees, about the body's sideways axis (bend_about).
## A backward roll rounds the back the same way a forward one does: it is the same tuck, and it
## is the body that is going the other way, not the spine. A thigh hangs down where the spine
## stands up, so the same turn that folds the spine forward swings the thigh *backwards*: the
## first roll extended the hips 65° behind the body, which no hip does. The hip flexes toward the
## chest, the knee folds the heel toward the seat.
static func tuck_angles(kind: int, t: float) -> Dictionary:
	var tuck := tuck_amount(kind, t)
	var out := {}
	for bone: String in TUCK:
		out[bone] = TUCK[bone] * tuck
	# Going backward the knees and hips fold deeper than the roll needs, early: that is the
	# squat the body sits down out of (SQUAT, gone again by the time it is rolling).
	var squat := squat_amount(kind, t)
	for leg in ["Right", "Left"]:
		out[leg + "UpperLeg"] = -(HIP_TUCK * tuck + SQUAT_HIP * squat)
		out[leg + "LowerLeg"] = KNEE_TUCK * tuck + SQUAT_KNEE * squat
	return out


## How deep the extra squat at the start of a backward fall is, 0..1.
static func squat_amount(kind: int, t: float) -> float:
	if kind != Kind.BACKWARD:
		return 0.0
	return smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.15, 0.3, t))


## Which fall a blend between two poses is part of: their `fall` records (CharacterRig.fall),
## as {"kind": Kind, "from": t, "to": t}, or {} when the two are not one fall. A pose with no
## fall next to one with a fall is where it starts (t 0) or where the figure is back up (t 1).
## Being laid face down is not a roll and is blended as it always was.
static func fall_span(fa: Dictionary, fb: Dictionary) -> Dictionary:
	var kinds := {"forward": Kind.FORWARD, "backward": Kind.BACKWARD}
	if fa.is_empty() and fb.is_empty():
		return {}
	if not fa.is_empty() and not fb.is_empty():
		if fa.get("kind") != fb.get("kind") or not kinds.has(fa.get("kind")):
			return {}
		return {"kind": kinds[fa["kind"]], "from": float(fa.get("t", 0.0)), "to": float(fb.get("t", 0.0))}
	if fb.is_empty():
		if not kinds.has(fa.get("kind")):
			return {}
		return {"kind": kinds[fa["kind"]], "from": float(fa.get("t", 0.0)), "to": 1.0}
	if not kinds.has(fb.get("kind")):
		return {}
	return {"kind": kinds[fb["kind"]], "from": 0.0, "to": float(fb.get("t", 0.0))}


## The root's pitch at `u` between two poses of one fall (`span`), whose saved pitches are
## `from_pitch` and `to_pitch` (radians, `to_pitch` counted on from `from_pitch`): the fall's own
## turn at the blended t, plus whatever the two poses add to it, blended. Exact at both poses.
static func blend_pitch(span: Dictionary, from_pitch: float, to_pitch: float, u: float) -> float:
	var k: int = span["kind"]
	var ta: float = span["from"]
	var tb: float = span["to"]
	var at := func(t: float) -> float: return deg_to_rad(pitch_deg(k, t))
	return at.call(lerpf(ta, tb, u)) + lerpf(from_pitch - at.call(ta), to_pitch - at.call(tb), u)


## Bends the tuck of a body blended between two poses of one fall (`span`) by what the fall's own
## course adds to a straight blend between the two: the squat a backward fall sits down out of,
## the tuck taken up early. Call it after the bones are blended. Zero at both poses.
static func blend_tuck(rig: CharacterRig, span: Dictionary, u: float) -> void:
	var k: int = span["kind"]
	var a := tuck_angles(k, span["from"])
	var b := tuck_angles(k, span["to"])
	var here := tuck_angles(k, lerpf(span["from"], span["to"], u))
	var side: Vector3 = rig.global_transform.basis.x
	for bone: String in here:
		var extra: float = here[bone] - lerpf(a[bone], b[bone], u)
		if absf(extra) > 0.01:
			turn_bone(rig, bone, side, extra)


## Turns `bone` *further* by `deg` about a world axis, from whatever pose it has (bend_about sets
## the bend from the rest instead).
static func turn_bone(rig: CharacterRig, bone: String, axis_world: Vector3, deg: float) -> void:
	var sk := rig.skeleton
	var i := sk.find_bone(bone)
	if i < 0 or axis_world.length() < 1e-6:
		return
	var parent := sk.get_bone_parent(i)
	var frame := sk.global_transform.basis
	if parent >= 0:
		frame = frame * sk.get_bone_global_rest(parent).basis
	var turn := Basis(axis_world.normalized(), deg_to_rad(deg))
	var q := Basis(sk.get_bone_pose_rotation(i))
	sk.set_bone_pose_rotation(i, ((frame.inverse() * turn * frame) * q).get_rotation_quaternion().normalized())


## How tight the tuck is at `t`: taken up as the fall starts, held through the roll, let out as
## the body comes back to its feet. A body laid face down does not curl at all once it is down.
static func tuck_amount(kind: int, t: float) -> float:
	if kind == Kind.PRONE:
		return smoothstep(0.0, TUCK_IN, t) * (1.0 - smoothstep(0.5, 1.0, t)) * 0.4
	var tuck_in := TUCK_IN_BACKWARD if kind == Kind.BACKWARD else TUCK_IN
	if t < tuck_in:
		return smoothstep(0.0, tuck_in, t)
	if t > TUCK_OUT:
		return 1.0 - smoothstep(TUCK_OUT, 1.0, t)
	return 1.0


## Lifts or drops the root until the lowest part of the body rests on the mat. Run it after the
## skeleton has solved, since it measures where the body actually is.
static func ground(rig: CharacterRig, mat_y := MAT_Y) -> void:
	var lowest := resting_lowest(rig)
	if lowest < INF:
		rig.position.y += mat_y - lowest


## The lowest point of what a body rests on: every capsule, and the skull, toes and soles that
## reach past them (not the fingertips: a hand is put on the mat by hands_on_mat).
static func resting_lowest(rig: CharacterRig) -> float:
	var lowest := INF
	for seg: Array in Anatomy.segments(rig).values():
		lowest = minf(lowest, minf(seg[0].y, seg[1].y) - seg[2])
	lowest = minf(lowest, _tips_lowest(rig, ["Right", "Left"], ["Toes"], TOE_REACH, TOE_RADIUS))
	for side in ["Right", "Left"]:   # the heel and the ball, under the foot's capsule
		lowest = minf(lowest, PoseBlend.sole_lowest(rig, side, rig.bone_world_transform(side + "Foot")))
	return minf(lowest, _skull_lowest(rig))


## Raises a hand that the fall has put through the mat until its fingertips rest on it. A hand
## is IK in a fall (shape() places it from the shoulder), so it is the target that moves, and the
## solve has to happen before the next call can see the difference: call it, settle, repeat.
## Returns how far the deepest hand was under, metres (0 when every hand is clear).
static func hands_on_mat(rig: CharacterRig, mat_y := MAT_Y) -> float:
	var worst := 0.0
	for side in ["Right", "Left"]:
		var limb: Limb = rig.limbs[side + "Arm"]
		if limb.mode != Limb.Mode.IK:
			continue
		var hand: float = rig.bone_world_transform(side + "Hand").origin.y - Anatomy.RADII[side + "Hand"]
		var low := minf(hand, _tips_lowest(rig, [side], FINGERTIPS, FINGERTIP_REACH, FINGERTIP_RADIUS))
		var under := mat_y - low
		if under > MAT_SLACK:
			limb.target.global_position += Vector3(0.0, under, 0.0)
			worst = maxf(worst, under)
	return worst


## Fingertips, which reach past the hand's capsule: a hand put flat on the mat in a roll is
## a hand with its fingers on it, and a fingertip under it is a hand through the tatami.
const FINGERTIPS := ["IndexDistal", "MiddleDistal", "RingDistal", "LittleDistal", "ThumbDistal"]
## How far a fingertip reaches past its last bone's origin, metres, and its thickness.
const FINGERTIP_REACH := 0.022
const FINGERTIP_RADIUS := 0.008
## The toes reach past the foot's capsule the same way: a kneeling figure's toes went 2-3 cm into
## the mat when only the capsules were grounded.
const TOE_REACH := 0.03
const TOE_RADIUS := 0.02
## A body this little under the mat is a body resting on it (the skin gives, and the capsules
## are coarser than the skin), and is left alone.
const MAT_SLACK := 0.005


## The lowest point of the body as solved: what it rests on, and the fingertips.
static func lowest_point(rig: CharacterRig) -> float:
	return minf(resting_lowest(rig), _tips_lowest(rig, ["Right", "Left"], FINGERTIPS, FINGERTIP_REACH, FINGERTIP_RADIUS))


## The skull and face, which reach past the head's capsule (the crown by 1.5 cm, the face by 4):
## a sphere a little up and forward of the head bone.
const SKULL_CENTRE := Vector3(0.0, 0.10, 0.035)
const SKULL_RADIUS := 0.095


static func _skull_lowest(rig: CharacterRig) -> float:
	var h := rig.bone_world_transform("Head")
	var b := h.basis.orthonormalized()
	return (h.origin + b.x * SKULL_CENTRE.x + b.y * SKULL_CENTRE.y + b.z * SKULL_CENTRE.z).y - SKULL_RADIUS


## The lowest of the spheres `reach` past the end bones `tips` (per side) with radius `radius`.
static func _tips_lowest(rig: CharacterRig, sides: Array, tips: Array, reach: float, radius: float) -> float:
	var sk := rig.skeleton
	var lowest := INF
	for side: String in sides:
		for tip: String in tips:
			if sk.find_bone(side + tip) < 0:
				continue
			var xf := rig.bone_world_transform(side + tip)
			lowest = minf(lowest, (xf.origin + xf.basis.y.normalized() * reach).y - radius)
	return lowest


## Rests a solved figure on the mat: lifted out of it or lowered onto it until its lowest point
## (fingertips included: a hand pushing off the mat carries the body) is on it. For a figure in
## a fall, between two poses: a rolling body is never off the mat, and the blend can only guess
## where the IK will put the legs and hands before the solve.
static func keep_on_mat(rig: CharacterRig, mat_y := MAT_Y) -> void:
	var off := lowest_point(rig) - mat_y
	if absf(off) > MAT_SLACK:
		rig.position.y -= off


## Turns `bone` by `deg` about a world axis, by expressing that turn in the bone's own frame.
## Setting the rotation rather than adding to it means a shape can be asked for twice and the
## second answer is the same as the first.
##
## A bone's pose rotation is not zero when it is unposed: it is the rest rotation, and the pose
## replaces it rather than adding to it. So the turn is composed onto the rest, not written over
## it — writing identity here does not straighten a bone, it wrenches it to wherever its parent's
## frame points, which for a thigh is 170 degrees from where it belongs.
static func bend_about(rig: CharacterRig, bone: String, axis_world: Vector3, deg: float) -> void:
	var sk := rig.skeleton
	var i := sk.find_bone(bone)
	if i < 0 or axis_world.length() < 1e-6:
		return
	var parent := sk.get_bone_parent(i)
	var frame := sk.global_transform.basis
	if parent >= 0:
		frame = frame * sk.get_bone_global_rest(parent).basis
	var turn := Basis(axis_world.normalized(), deg_to_rad(deg))
	var rest := sk.get_bone_rest(i).basis
	sk.set_bone_pose_rotation(i, ((frame.inverse() * turn * frame) * rest).get_rotation_quaternion().normalized())
