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
const TUCK_OUT := 0.75
## Where the arms go while rolling, as an offset from the shoulder in the body's own frame.
const ARM_ROLLING := Vector3(-0.10, -0.22, 0.24)
const ARM_REACHING := Vector3(-0.06, -0.34, 0.34)


## Poses `rig` at `t` (0..1) through a fall. Call `ground()` after the skeleton has solved.
static func shape(rig: CharacterRig, kind: int, t: float) -> void:
	t = clampf(t, 0.0, 1.0)
	var tuck := tuck_amount(kind, t)
	var side: Vector3 = rig.global_transform.basis.x
	for bone: String in TUCK:
		# A backward roll rounds the back the same way a forward one does: it is the same tuck,
		# and it is the body that is going the other way, not the spine.
		bend_about(rig, bone, side, TUCK[bone] * tuck)
	for leg in ["Right", "Left"]:
		rig.set_limb_mode(leg + "Leg", Limb.Mode.FK)
		# A thigh hangs down where the spine stands up, so the same turn about the body's
		# sideways axis that folds the spine forward swings the thigh *backwards*: the first
		# roll extended the hips 65° behind the body, which no hip does. The hip flexes toward
		# the chest, the knee folds the heel toward the seat.
		bend_about(rig, leg + "UpperLeg", side, -HIP_TUCK * tuck)
		bend_about(rig, leg + "LowerLeg", side, KNEE_TUCK * tuck)   # heel towards the seat
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
static func pitch_deg(kind: int, t: float) -> float:
	match kind:
		Kind.FORWARD:
			return 360.0 * t
		Kind.BACKWARD:
			return -360.0 * t
		_:
			return 90.0 * minf(t * 2.0, 1.0)


## How tight the tuck is at `t`: taken up as the fall starts, held through the roll, let out as
## the body comes back to its feet. A body laid face down does not curl at all once it is down.
static func tuck_amount(kind: int, t: float) -> float:
	if kind == Kind.PRONE:
		return smoothstep(0.0, TUCK_IN, t) * (1.0 - smoothstep(0.5, 1.0, t)) * 0.4
	if t < TUCK_IN:
		return smoothstep(0.0, TUCK_IN, t)
	if t > TUCK_OUT:
		return 1.0 - smoothstep(TUCK_OUT, 1.0, t)
	return 1.0


## Lifts or drops the root until the lowest part of the body rests on the mat. Run it after the
## skeleton has solved, since it measures where the body actually is.
static func ground(rig: CharacterRig, mat_y := MAT_Y) -> void:
	var lowest := INF
	for seg: Array in Anatomy.segments(rig).values():
		lowest = minf(lowest, minf(seg[0].y, seg[1].y) - seg[2])
	if lowest < INF:
		rig.position.y += mat_y - lowest


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
