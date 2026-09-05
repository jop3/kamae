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
	var local := (parent_basis.inverse() * wanted).orthonormalized()
	sk.set_bone_pose_rotation(_bone, local.get_rotation_quaternion())
