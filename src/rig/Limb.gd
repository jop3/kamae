class_name Limb
extends RefCounted
## One IK-able limb: a two-bone chain with a draggable target and pole.
##
## Mode IK: TwoBoneIK3D solves the chain toward the target every frame.
## Mode FK: the modifier is off and the instructor rotates the joints directly.
## Switching bakes, so the limb never jumps when the mode changes.

enum Mode { IK, FK }

const ARM_POLE_OFFSET := Vector3(0.12, -0.45, -0.10)  ## elbows hang down, a little out and back
const LEG_POLE_OFFSET := Vector3(0.0, -0.25, 0.55)    ## knees point forward

var key: String            ## "RightArm", "LeftLeg", …
var root_bone: String
var middle_bone: String
var end_bone: String
var is_arm: bool
var rig: Node3D            ## CharacterRig
var skeleton: Skeleton3D
var ik: TwoBoneIK3D
var hand_orient: HandOrient
var target: Node3D
var pole: Node3D
var mode: int = Mode.FK
## When true the hand (or foot) takes the target's rotation as well as its position.
## Off by default: forcing an absolute orientation that the arm's natural roll cannot reach twists
## the wrist far enough to shear the skinned mesh. Grips (M3) turn it on with a captured offset,
## which stays close to the natural orientation and therefore looks right.
var orient_to_target := false


func _init(limb_key: String, root_b: String, middle_b: String, end_b: String, arm: bool) -> void:
	key = limb_key
	root_bone = root_b
	middle_bone = middle_b
	end_bone = end_b
	is_arm = arm


## Builds the IK node, target and pole. Targets live under the rig root so that moving or
## turning the whole character carries its limb targets along.
func build(character_rig: Node3D, sk: Skeleton3D, target_node: Node3D, pole_node: Node3D) -> void:
	rig = character_rig
	skeleton = sk
	target = target_node
	pole = pole_node
	reset_target_to_pose()
	reset_pole()
	ik = TwoBoneIK3D.new()
	ik.name = "IK_" + key
	skeleton.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, root_bone)
	ik.set_middle_bone_name(0, middle_bone)
	ik.set_end_bone_name(0, end_bone)
	ik.set_target_node(0, ik.get_path_to(target))
	ik.set_pole_node(0, ik.get_path_to(pole))
	ik.active = false
	hand_orient = HandOrient.new()
	hand_orient.name = "Orient_" + key
	hand_orient.bone_name = end_bone
	hand_orient.target = target
	hand_orient.enabled = false
	skeleton.add_child(hand_orient)  # after the IK node, so it runs after the solve


func set_mode(new_mode: int) -> void:
	if new_mode == mode:
		return
	if new_mode == Mode.IK:
		reset_target_to_pose()   # target adopts the current hand transform, so nothing jumps
	mode = new_mode
	ik.active = mode == Mode.IK
	hand_orient.enabled = mode == Mode.IK and orient_to_target


## Moves the target (and its rotation) onto the limb's current end bone.
func reset_target_to_pose() -> void:
	var end_pose: Transform3D = rig.bone_world_transform(end_bone)
	target.global_transform = end_pose


## Puts the pole where a relaxed elbow or knee would be for the current target: arms hang their
## elbow below the shoulder-to-hand line, a little outward and back; knees point forward.
## Measured from the current line rather than the rest-pose joint, so it stays sensible when the
## hand is somewhere the rest pose never had it.
func reset_pole() -> void:
	var shoulder: Vector3 = rig.bone_world_transform(root_bone).origin
	var mid: Vector3 = (shoulder + target.global_position) * 0.5
	var offset := ARM_POLE_OFFSET if is_arm else LEG_POLE_OFFSET
	if is_arm and key.begins_with("Right"):
		offset.x = -offset.x   # the character faces +Z, so its right side is -X
	pole.global_position = mid + rig.global_transform.basis * offset


func set_orient_to_target(enabled: bool) -> void:
	orient_to_target = enabled
	hand_orient.enabled = enabled and mode == Mode.IK


func chain_length() -> float:
	var a := skeleton.get_bone_global_rest(skeleton.find_bone(root_bone)).origin
	var b := skeleton.get_bone_global_rest(skeleton.find_bone(middle_bone)).origin
	var c := skeleton.get_bone_global_rest(skeleton.find_bone(end_bone)).origin
	return a.distance_to(b) + b.distance_to(c)


## How far beyond the limb's reach the target sits, in metres. 0 when reachable.
## TwoBoneIK3D does not stretch, so a positive value means the hand will stop short.
func reach_shortfall() -> float:
	var shoulder: Transform3D = rig.bone_world_transform(root_bone)
	var distance: float = shoulder.origin.distance_to(target.global_position)
	return maxf(0.0, distance - chain_length())


## Captures the solved rotations so they can be written back as plain FK.
## Must be called while the skeleton reports the solved pose, i.e. from skeleton_updated.
func capture_solved_rotations() -> Dictionary:
	var out := {}
	for b in [root_bone, middle_bone, end_bone]:
		out[b] = skeleton.get_bone_pose_rotation(skeleton.find_bone(b))
	return out


func apply_rotations(rotations: Dictionary) -> void:
	for b in rotations:
		skeleton.set_bone_pose_rotation(skeleton.find_bone(b), rotations[b])
