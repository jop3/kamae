class_name HandOrient
extends SkeletonModifier3D
## Orients one bone (a hand or foot) to a target's rotation, through the joints that can do it.
##
## TwoBoneIK3D deliberately ignores the target's rotation, so an IK-driven hand keeps whatever
## orientation the chain happens to produce. A grip is a position *and* an orientation, so this
## modifier runs after the IK node (child order is execution order) and turns the end bone.
##
## A wrist alone cannot turn a hand any way it likes: it flexes and deviates, but it barely
## rolls, and it has an edge in every direction. What the wrist cannot give comes from the rest
## of the arm. The forearm rolls (pronation and supination), which moves neither joint; and the
## whole arm can turn about the line from shoulder to wrist (LimbTurn), which swings the elbow
## round, leaves the hand where it is, and changes which way the forearm arrives at the wrist.
## So the turn is chosen that leaves the wrist with the least to do that it cannot do, with the
## shoulder kept inside its own range and the elbow kept near where the pole put it; the forearm
## then rolls as far as it may; and the wrist takes what is left, where JointLimits holds it
## inside its range. A foot is the same with the hip, the knee (which only turns once it is
## bent) and the ankle. When the whole limb cannot do it the hand is short of its orientation by
## exactly the excess, visibly, rather than a wrist being broken to hide it.

@export var bone_name: String = ""
@export var target: Node3D
@export var enabled: bool = true
## The chain above the bone: the twist about the middle bone is pronation (or knee rotation),
## the turn about the root-to-end line is the shoulder's (or hip's). Empty names skip a stage.
@export var root_bone: String = ""
@export var middle_bone: String = ""
## Without a rig (no joint catalogue) the middle bone takes this share of the roll, unbounded,
## which is what this modifier did before the joints had ranges.
@export var twist_share: float = 0.7
## The shoulder or hip being out of range costs this much more than the wrist being out.
const ROOT_WEIGHT := 4.0
## An arm spends its turn freely: the elbow goes wherever leaves the wrist least to do, and
## the forearm rolls before the shoulder turns (pronation is the cheap one). A leg does not: a
## knee stays over its toes, so the hip turns only for where the foot *points* (its yaw about
## the shin and its roll), never to help an ankle that is asked to bend too far; and the hip
## turns before the knee (which barely turns) rolls.
@export var is_arm: bool = true
## Turning a leg away from where the pole put the knee costs this much per degree.
const LEG_TURN_COST_PER_DEG := 0.15

var rig: CharacterRig
var _bone := -1
var _root := -1
var _middle := -1
## What the last pass did, degrees, for tests: roll given to the middle bone, and the turn of
## the whole limb about its root-to-end line.
var last_middle_twist_deg := 0.0
var last_turn_deg := 0.0


func _process_modification_with_delta(_delta: float) -> void:
	last_middle_twist_deg = 0.0
	last_turn_deg = 0.0
	if not enabled or target == null:
		return
	var sk := get_skeleton()
	if sk == null:
		return
	if _bone < 0 or sk.get_bone_name(_bone) != bone_name:
		_bone = sk.find_bone(bone_name)
		_root = sk.find_bone(root_bone) if root_bone != "" else -1
		_middle = sk.find_bone(middle_bone) if middle_bone != "" else -1
		if _bone < 0:
			return
	# Rotation only, expressed as a *local* pose rotation against the parent the IK just solved.
	# Writing a global pose here instead (set_bone_global_pose) makes Godot derive a local
	# transform that can carry scale and shear, which stretches the skinned arm into a ribbon.
	var wanted := (sk.global_transform.affine_inverse() * target.global_transform).basis.orthonormalized()
	var parent := sk.get_bone_parent(_bone)
	var joints: Joints = rig.joints if rig else null
	if parent >= 0 and _middle == parent and joints and joints.has(middle_bone) and joints.has(bone_name):
		_through_the_limb(sk, wanted, joints)
	elif parent >= 0 and _middle == parent:
		# No catalogue: the forearm takes a fixed share of the roll, as it always did.
		var forearm_axis := (sk.get_bone_global_pose(_bone).origin - sk.get_bone_global_pose(_middle).origin).normalized()
		var twist := LimbTurn.twist_between(sk.get_bone_global_pose(_bone).basis, wanted, forearm_axis)
		if absf(twist) > 1e-4 and twist_share > 0.0:
			LimbTurn.set_world_basis(sk, _middle, Basis(forearm_axis, twist * twist_share) * sk.get_bone_global_pose(_middle).basis.orthonormalized())
			last_middle_twist_deg = rad_to_deg(twist * twist_share)
	var parent_basis := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	var local := (parent_basis.inverse() * wanted).orthonormalized()
	sk.set_bone_pose_rotation(_bone, local.get_rotation_quaternion())


func _through_the_limb(sk: Skeleton3D, wanted: Basis, joints: Joints) -> void:
	var mid_spec: Dictionary = joints.specs[middle_bone]
	var end_spec: Dictionary = joints.specs[bone_name]
	var root_spec: Dictionary = joints.specs[root_bone] if (_root >= 0 and joints.has(root_bone)) else {}
	# 0. A forearm already rolled past its range (a saved pose from before the joints had one)
	#    is rolled back first, so the search below starts from a forearm that exists.
	var r_basis := sk.get_bone_global_pose(_middle).basis.orthonormalized()
	var m_now := LimbTurn.angles_of(mid_spec, sk.get_bone_global_pose(sk.get_bone_parent(_middle)).basis, r_basis)
	var m_clamped := Joints.clamp_angles(mid_spec, m_now)
	if absf(m_clamped["twist"] - m_now["twist"]) > 0.01:
		var axis0 := (sk.get_bone_global_pose(_bone).origin - sk.get_bone_global_pose(_middle).origin).normalized()
		LimbTurn.set_world_basis(sk, _middle, Basis(axis0, deg_to_rad(m_clamped["twist"] - m_now["twist"])) * r_basis)
	# Where everything is now, in the skeleton's space.
	var root_origin := sk.get_bone_global_pose(_root).origin if _root >= 0 else Vector3.ZERO
	var end_origin := sk.get_bone_global_pose(_bone).origin
	var line := (end_origin - root_origin).normalized() if _root >= 0 else Vector3.ZERO
	var root0 := sk.get_bone_global_pose(_root).basis.orthonormalized() if _root >= 0 else Basis.IDENTITY
	var root_parent := sk.get_bone_global_pose(sk.get_bone_parent(_root)).basis.orthonormalized() if _root >= 0 else Basis.IDENTITY
	var mid0 := sk.get_bone_global_pose(_middle).basis.orthonormalized()
	var mid_parent0 := sk.get_bone_global_pose(sk.get_bone_parent(_middle)).basis.orthonormalized()
	var axis0 := (end_origin - sk.get_bone_global_pose(_middle).origin).normalized()
	# The hand as it hangs from the forearm with the wrist at rest. The roll the forearm needs
	# is measured from there, not from wherever the hand is now: what it is now depends on how
	# it got there (a reloaded pose carries yesterday's roll), and a solve that depends on its
	# own history lands a reloaded pose somewhere else.
	var hand_rest := Basis(end_spec["rest_q"])
	# The outcome of turning the limb by phi about its line, then rolling the forearm as far as
	# it may toward the hand's orientation: {cost, roll} with roll in radians.
	var outcome := func(phi_deg: float) -> Dictionary:
		var turn := Basis(line, deg_to_rad(phi_deg)) if (_root >= 0 and absf(phi_deg) > 1e-9) else Basis.IDENTITY
		var mid := (turn * mid0).orthonormalized()
		var mid_parent := (turn * mid_parent0).orthonormalized()
		var hand := (mid * hand_rest).orthonormalized()
		var axis := turn * axis0
		var need := LimbTurn.twist_between(hand, wanted, axis)
		var roll := LimbTurn.roll_within(mid_spec, mid_parent, mid, axis, need)
		var mid_rolled := (Basis(axis, roll) * mid).orthonormalized()
		var wrist := LimbTurn.angles_of(end_spec, mid_rolled if is_arm else mid, wanted)
		var cost: float
		if is_arm:
			cost = LimbTurn.excess(end_spec, wrist) + LimbTurn.TURN_COST_PER_DEG * absf(phi_deg)
		else:
			var e := Joints.excess(end_spec, wrist)
			cost = e["abd"] + e["twist"] + LEG_TURN_COST_PER_DEG * absf(phi_deg)
		if not root_spec.is_empty():
			cost += ROOT_WEIGHT * LimbTurn.excess(root_spec, LimbTurn.angles_of(root_spec, root_parent, (turn * root0).orthonormalized()))
		return {"cost": cost, "roll": roll}
	var phi := 0.0
	if _root >= 0 and not root_spec.is_empty() and sk.get_bone_parent(_middle) == _root:
		phi = LimbTurn.search(func(p: float) -> float: return outcome.call(p)["cost"])
	if absf(phi) > 1e-3:
		last_turn_deg = phi
		LimbTurn.set_world_basis(sk, _root, Basis(line, deg_to_rad(phi)) * root0)
	var roll: float = outcome.call(phi)["roll"]
	if absf(roll) > 1e-4:
		last_middle_twist_deg = rad_to_deg(roll)
		var axis := (sk.get_bone_global_pose(_bone).origin - sk.get_bone_global_pose(_middle).origin).normalized()
		LimbTurn.set_world_basis(sk, _middle, Basis(axis, roll) * sk.get_bone_global_pose(_middle).basis.orthonormalized())
