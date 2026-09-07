class_name JointLimits
extends SkeletonModifier3D
## Holds every joint inside its anatomical range (Joints), last in the modifier stack.
##
## The pose the earlier modifiers produce — FK rotations, the finger curls, each limb's IK
## solve, twist and hand orientation — is what the instructor, a grip or a video asked for. This
## is what the body can do about it. Each joint is measured as flexion, abduction and twist,
## brought inside the range for a joint in that position (a knee only turns once it is bent,
## a finger only spreads while it is open), and written back. A hand that was asked to bend its
## wrist 120° shows a wrist bent 80°, the way a real one would, and the readout below says what
## was refused so nothing is hidden: Anatomy.joint_problems reports these, and a grip or an IK
## target that needed the impossible is short by exactly what the joint could not give.
##
## Off, the skeleton shows whatever it was given; the checks then measure that instead.

## A joint is held at its range however little it is over; it is *recorded* as refused from
## this much over, degrees, so rounding at the edge is not reported as a broken joint.
const RECORDED := 0.5

## The rig whose joints these are; its catalogue is built once from the rest pose.
var rig: CharacterRig
var enabled := true
## Joints held back on the last pass: bone -> {"wanted": angles, "held": angles}. Empty when
## the whole pose was within range. Read it after skeleton_updated.
var refused: Dictionary = {}
## Distinct from `refused` so a reader never sees a half-written pass.
var _pass: Dictionary = {}


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or rig == null or rig.joints == null:
		return
	_pass.clear()
	if not enabled:
		refused = {}
		return
	var joints: Joints = rig.joints
	for bone in joints.order:
		var i := sk.find_bone(bone)
		if i < 0:
			continue
		var spec: Dictionary = joints.specs[bone]
		var q := sk.get_bone_pose_rotation(i)
		var a := Joints.angles(spec, q)
		var c := Joints.clamp_angles(spec, a)
		var over := maxf(absf(c["flex"] - a["flex"]), maxf(absf(c["abd"] - a["abd"]), absf(c["twist"] - a["twist"])))
		if over > 0.01:
			if over >= RECORDED:
				_pass[bone] = {"wanted": a, "held": c}
			q = Joints.rotation(spec, c["flex"], c["abd"], c["twist"])
		# Written whether or not it changed: a modifier that skips a bone leaves it as the
		# skeleton last had it (docs/engine-notes.md).
		sk.set_bone_pose_rotation(i, q)
	refused = _pass.duplicate()


## What the last pass refused, one line per joint, for the checks and the panel.
func report() -> PackedStringArray:
	var out := PackedStringArray()
	if rig == null or rig.joints == null:
		return out
	for bone in rig.joints.order:
		if not refused.has(bone):
			continue
		var line := Joints.describe(rig.joints.specs[bone], refused[bone]["wanted"])
		if line != "":
			out.append("%s: %s" % [bone, line])
	return out
