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

@export var root_bone: String = ""
@export var middle_bone: String = ""
@export var end_bone: String = ""
## Direction the joint folds toward at rest, in the root bone's own frame (Anatomy.rest_bend_local).
@export var rest_bend_local: Vector3 = Vector3.ZERO
@export var enabled: bool = true
## The shoulder or hip will not twist further than this from the solver's own answer; beyond it
## the pose is one a person cannot take, and Anatomy reports it rather than hiding it.
@export var max_twist_deg: float = 110.0
## Below this flexion the bend plane is too ill-defined to follow.
const MIN_FLEXION_DEG := 5.0

var _r := -1
var _m := -1
var _e := -1
## The twist applied on the last pass, degrees; for tests and the reach display.
var last_twist_deg := 0.0


func _process_modification_with_delta(_delta: float) -> void:
	last_twist_deg = 0.0
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
	angle = clampf(angle, -deg_to_rad(max_twist_deg), deg_to_rad(max_twist_deg))
	if absf(angle) < 1e-4:
		return
	last_twist_deg = rad_to_deg(angle)
	var new_root := (Basis(d1, angle) * r.basis.orthonormalized()).orthonormalized()
	var parent := sk.get_bone_parent(_r)
	var parent_basis := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	# Local rotations only (see HandOrient): a global write can smuggle scale into the pose.
	sk.set_bone_pose_rotation(_r, (parent_basis.inverse() * new_root).orthonormalized().get_rotation_quaternion())
	sk.set_bone_pose_rotation(_m, (new_root.inverse() * m.basis.orthonormalized()).orthonormalized().get_rotation_quaternion())
