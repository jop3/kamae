class_name ShoulderGirdle
extends SkeletonModifier3D
## Raises the clavicle with the arm, the way a shoulder blade rides up a back.
##
## An arm does not go overhead on the shoulder joint alone: past about 60° of elevation the
## shoulder blade turns upward on the ribs and the collarbone rises with it, contributing
## roughly one degree in three (the scapulohumeral rhythm). The rig's clavicle bone sat at 0°
## in every committed pose, so an arm raised for a cut read as 180° of pure shoulder, the
## shoulder's ranges in Joints were doing the scapula's work, and the shoulders themselves never
## rose. This modifier runs *before* the arms solve — it reads where each arm is going, not where
## the solve left it, so the answer never depends on the previous frame — and elevates and
## protracts the clavicle for it. The IK then solves from a shoulder that has moved, so a hand
## still lands on its target.
##
## For an arm in IK the elevation is read from its target; for an arm in FK, from the authored
## humerus. Both are set before this runs.

## Arm elevation, degrees from hanging, below which the girdle does nothing.
const FREE_DEG := 60.0
## Clavicle elevation per degree of arm elevation past FREE_DEG (one in three), and its limit.
const RHYTHM := 1.0 / 3.0
const MAX_ELEVATION_DEG := 20.0
## Protraction (the shoulder blade sliding forward as the arm reaches across the front) is
## deliberately not modelled: it moved every shoulder a few centimetres forward in poses that
## were authored without it, and in shihonage put Tori's arm inside Uke's for the whole of the
## held pin. Elevation is the rhythm that matters for an arm overhead; the rest waits for poses
## authored with it.

var rig: CharacterRig
var enabled := true
## The last pass's clavicle elevation per side, degrees, for tests: {"Right": [elev, 0], ...}.
var last: Dictionary = {}


func _process_modification_with_delta(_delta: float) -> void:
	last.clear()
	if not enabled or rig == null or rig.joints == null:
		return
	var sk := get_skeleton()
	if sk == null:
		return
	var to_skel := sk.global_transform.affine_inverse()
	for side in ["Right", "Left"]:
		var clav := sk.find_bone(side + "Shoulder")
		if clav < 0 or not rig.joints.has(side + "Shoulder"):
			continue
		var limb: Limb = rig.limbs.get(side + "Arm")
		if limb == null:
			continue
		var spec: Dictionary = rig.joints.specs[side + "Shoulder"]
		# The arm's elevation depends on where the shoulder joint is, which depends on the
		# clavicle, which depends on the elevation: a fixed point, reached in a few rounds
		# (the rhythm is one in three, so each round closes two thirds of the gap). Nothing in it
		# reads the authored clavicle or the previous frame, so a reloaded pose gives the same
		# answer as the pose it was saved from.
		var raise := 0.0
		var protract := 0.0
		for _round in 4:
			var toward := _arm_direction(sk, side, limb, spec, raise, protract, to_skel)
			if toward.length() < 0.05:
				break
			toward = toward.normalized()
			var elevation := rad_to_deg(Vector3.DOWN.angle_to(toward))
			raise = clampf((elevation - FREE_DEG) * RHYTHM, 0.0, MAX_ELEVATION_DEG)
		sk.set_bone_pose_rotation(clav, Joints.rotation(spec, raise, protract, 0.0))
		last[side] = [raise, protract]


## Where the arm is going, from the shoulder joint as it would be with the clavicle at these
## angles: to the target for an arm in IK, to the wrist under the authored pose for one in FK
## (hanging from that same clavicle, so a baked arm measures as the solved one did).
func _arm_direction(sk: Skeleton3D, side: String, limb: Limb, spec: Dictionary, raise: float, protract: float, to_skel: Transform3D) -> Vector3:
	var clav := sk.find_bone(side + "Shoulder")
	var humerus := sk.find_bone(side + "UpperArm")
	var above := _authored_global(sk, sk.get_bone_parent(clav))
	var clav_pose := sk.get_bone_pose(clav)
	var t_clav: Transform3D = above * Transform3D(Basis(Joints.rotation(spec, raise, protract, 0.0)), clav_pose.origin)
	var t_humerus: Transform3D = t_clav * sk.get_bone_pose(humerus)
	if limb.mode == Limb.Mode.IK:
		return to_skel * limb.target.global_position - t_humerus.origin
	var t_hand: Transform3D = t_humerus * sk.get_bone_pose(sk.find_bone(side + "LowerArm")) * sk.get_bone_pose(sk.find_bone(side + "Hand"))
	return t_hand.origin - t_humerus.origin


## A bone's global pose under the authored rotations alone, this frame, without waiting for the
## skeleton to update it: walked up from the root.
static func _authored_global(sk: Skeleton3D, idx: int) -> Transform3D:
	var t := Transform3D.IDENTITY
	while idx >= 0:
		t = sk.get_bone_pose(idx) * t
		idx = sk.get_bone_parent(idx)
	return t
