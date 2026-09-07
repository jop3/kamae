class_name TwistFollow
extends SkeletonModifier3D
## Twists a two-bone chain's root bone about its own axis so that the joint bends the way the
## anatomy allows: the elbow crease faces the direction the forearm folds, the knee cap faces
## away from the fold. Runs right after the chain's TwoBoneIK3D.
##
## TwoBoneIK3D swings the upper arm toward the elbow the pole asks for but never twists it, so
## with the hand overhead or behind the back the humerus keeps its rest twist and the elbow
## ends up bending "backwards" through the skin (the mesh shows an elbow point on the inside
## of the arm). A person turns the humerus as the arm rises. This modifier adds that turn, and
## re-expresses the middle bone against the turned root so the hand does not move at all.
##
## A humerus only twists so far (Joints). When the pole asks for an elbow the shoulder cannot
## turn to, the elbow goes where it can: the whole arm turns about the line from shoulder to
## wrist (LimbTurn), which moves the elbow round and leaves the hand where it is, until the
## shoulder is back inside its range. The pole is then a preference, not an order, and the
## body is never shown with a shoulder it does not have.

@export var root_bone: String = ""
@export var middle_bone: String = ""
@export var end_bone: String = ""
## Direction the joint folds toward at rest, in the root bone's own frame (Anatomy.rest_bend_local).
@export var rest_bend_local: Vector3 = Vector3.ZERO
@export var enabled: bool = true
## Below this flexion the bend plane is too ill-defined to follow.
const MIN_FLEXION_DEG := 5.0

## The rig whose joint ranges bound the root; without one the twist is unbounded.
var rig: CharacterRig
var _r := -1
var _m := -1
var _e := -1
## The twist applied on the last pass, degrees; for tests and the reach display.
var last_twist_deg := 0.0
## How far the limb was turned about its root-to-end line on the last pass, degrees.
var last_turn_deg := 0.0


func _process_modification_with_delta(_delta: float) -> void:
	last_twist_deg = 0.0
	last_turn_deg = 0.0
	if not enabled or rest_bend_local.is_zero_approx():
		return
	var sk := get_skeleton()
	if sk == null:
		return
	if _r < 0 or sk.get_bone_name(_r) != root_bone:
		_r = sk.find_bone(root_bone); _m = sk.find_bone(middle_bone); _e = sk.find_bone(end_bone)
		if _r < 0 or _m < 0 or _e < 0:
			return
	var r := sk.get_bone_global_pose(_r)
	var m := sk.get_bone_global_pose(_m)
	var e := sk.get_bone_global_pose(_e)
	var d1 := (m.origin - r.origin).normalized()
	var d2 := (e.origin - m.origin).normalized()
	if rad_to_deg(d1.angle_to(d2)) < MIN_FLEXION_DEG:
		return
	var bend := d2 - d1 * d2.dot(d1)
	var allowed := r.basis.orthonormalized() * rest_bend_local
	allowed -= d1 * allowed.dot(d1)
	if bend.length_squared() < 1e-10 or allowed.length_squared() < 1e-10:
		return
	bend = bend.normalized(); allowed = allowed.normalized()
	var angle := atan2(allowed.cross(bend).dot(d1), allowed.dot(bend))
	if absf(angle) > 1e-4:
		last_twist_deg = rad_to_deg(angle)
		var new_root := (Basis(d1, angle) * r.basis.orthonormalized()).orthonormalized()
		var parent := sk.get_bone_parent(_r)
		var parent_basis := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
		# Local rotations only (see HandOrient): a global write can smuggle scale into the pose.
		sk.set_bone_pose_rotation(_r, (parent_basis.inverse() * new_root).orthonormalized().get_rotation_quaternion())
		sk.set_bone_pose_rotation(_m, (new_root.inverse() * m.basis.orthonormalized()).orthonormalized().get_rotation_quaternion())
	_keep_root_in_range(sk)


## The fold now faces the bend, which is a fact about the arm alone: turning the whole arm about
## the shoulder-to-wrist line keeps it so. What that turn changes is the shoulder, so it is used
## to bring the shoulder back inside its range when the twist above took it out.
func _keep_root_in_range(sk: Skeleton3D) -> void:
	if rig == null or rig.joints == null or not rig.joints.has(root_bone):
		return
	var spec: Dictionary = rig.joints.specs[root_bone]
	var parent := sk.get_bone_parent(_r)
	var parent_basis := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	var r0 := sk.get_bone_global_pose(_r).basis.orthonormalized()
	var line := (sk.get_bone_global_pose(_e).origin - sk.get_bone_global_pose(_r).origin).normalized()
	if line.length_squared() < 0.5:
		return
	var cost := func(phi_deg: float) -> float:
		var turned := (Basis(line, deg_to_rad(phi_deg)) * r0).orthonormalized()
		return LimbTurn.excess(spec, LimbTurn.angles_of(spec, parent_basis, turned)) \
			+ LimbTurn.TURN_COST_PER_DEG * absf(phi_deg)
	var phi := LimbTurn.search(cost)
	if absf(phi) < 1e-3:
		return
	last_turn_deg = phi
	LimbTurn.set_world_basis(sk, _r, Basis(line, deg_to_rad(phi)) * r0)
