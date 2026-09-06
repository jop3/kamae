class_name HandOrient
extends SkeletonModifier3D
## Orients one bone (a hand or foot) to a target's rotation.
##
## TwoBoneIK3D deliberately ignores the target's rotation, so an IK-driven hand keeps whatever
## orientation the chain happens to produce. A grip is a position *and* an orientation, so this
## modifier runs after the IK node (child order is execution order) and rotates the end bone.

@export var bone_name: String = ""
@export var target: Node3D
@export var enabled: bool = true
## How much of the roll about the forearm axis the forearm itself takes, the hand taking the rest.
## Rotating the lower arm about its own elbow-to-wrist axis moves neither joint, so this is free;
## without it every bit of pronation shows up as a kink at the wrist.
@export var twist_share: float = 0.7

var _bone := -1


func _process_modification_with_delta(_delta: float) -> void:
	if not enabled or target == null:
		return
	var sk := get_skeleton()
	if sk == null:
		return
	if _bone < 0 or sk.get_bone_name(_bone) != bone_name:
		_bone = sk.find_bone(bone_name)
		if _bone < 0:
			return
	# Rotation only, expressed as a *local* pose rotation against the parent the IK just solved.
	# Writing a global pose here instead (set_bone_global_pose) makes Godot derive a local transform
	# that can carry scale and shear, which stretches the skinned arm into a ribbon.
	var wanted := (sk.global_transform.affine_inverse() * target.global_transform).basis.orthonormalized()
	var parent := sk.get_bone_parent(_bone)
	var parent_basis := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	if parent >= 0 and twist_share > 0.0:
		# Split the rotation still needed at the wrist into the part about the forearm axis (twist)
		# and the rest (swing); hand the forearm its share of the twist first.
		var hand_now := sk.get_bone_global_pose(_bone).basis.orthonormalized()
		var forearm_axis := (sk.get_bone_global_pose(_bone).origin - sk.get_bone_global_pose(parent).origin).normalized()
		var delta := (wanted * hand_now.inverse()).get_rotation_quaternion()
		var proj := Vector3(delta.x, delta.y, delta.z).dot(forearm_axis)
		var twist_angle := 2.0 * atan2(proj, delta.w)
		twist_angle = wrapf(twist_angle, -PI, PI)
		if absf(twist_angle) > 1e-4:
			var new_parent := (Basis(forearm_axis, twist_angle * twist_share) * parent_basis).orthonormalized()
			var grand := sk.get_bone_parent(parent)
			var grand_basis := sk.get_bone_global_pose(grand).basis.orthonormalized() if grand >= 0 else Basis.IDENTITY
			sk.set_bone_pose_rotation(parent, (grand_basis.inverse() * new_parent).orthonormalized().get_rotation_quaternion())
			parent_basis = new_parent
	var local := (parent_basis.inverse() * wanted).orthonormalized()
	sk.set_bone_pose_rotation(_bone, local.get_rotation_quaternion())
