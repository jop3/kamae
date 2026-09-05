class_name PickCapsules
extends Node
## Builds one Area3D capsule per bone so body parts can be clicked in the 3D view.
## Each capsule hangs under a BoneAttachment3D, so it follows the posed skeleton.

const RADII := {
	"Hips": 0.11, "Spine": 0.10, "Chest": 0.11, "UpperChest": 0.11, "Neck": 0.05, "Head": 0.10,
	"Shoulder": 0.05, "UpperArm": 0.045, "LowerArm": 0.04, "Hand": 0.035,
	"UpperLeg": 0.075, "LowerLeg": 0.055, "Foot": 0.04, "Toes": 0.03,
}
const FINGER_RADIUS := 0.011
const LEAF_LENGTH := {"Head": 0.22, "Toes": 0.06, "Distal": 0.025}

var rig: CharacterRig
var areas: Dictionary = {}  # bone_name -> Area3D


func build(for_rig: CharacterRig) -> void:
	rig = for_rig
	var sk := rig.skeleton
	for i in sk.get_bone_count():
		var bname := sk.get_bone_name(i)
		var children := sk.get_bone_children(i)
		var dir := Vector3.UP
		var length := 0.0
		if children.size() > 0:
			# Point along the mean of child rest origins (in this bone's space).
			var acc := Vector3.ZERO
			for c in children:
				acc += sk.get_bone_rest(c).origin
			acc /= children.size()
			length = acc.length()
			if length > 0.001:
				dir = acc / length
		else:
			length = _leaf_length(bname)
			dir = _leaf_dir(sk, i)
		var radius := _radius(bname)
		var att := BoneAttachment3D.new()
		att.name = "Pick_" + bname
		sk.add_child(att)
		att.bone_name = bname
		var area := Area3D.new()
		area.collision_layer = 2
		area.collision_mask = 0
		area.input_ray_pickable = false
		area.set_meta("character_id", rig.character_id)
		area.set_meta("bone_name", bname)
		var shape := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = radius
		cap.height = maxf(length + radius * 2.0, radius * 2.0)
		shape.shape = cap
		# Capsule axis is local Y; align Y with dir and centre it on the bone segment.
		shape.transform = Transform3D(_basis_y_to(dir), dir * length * 0.5)
		area.add_child(shape)
		att.add_child(area)
		areas[bname] = area


func _radius(bname: String) -> float:
	for key in ["Thumb", "Index", "Middle", "Ring", "Little"]:
		if key in bname:
			return FINGER_RADIUS
	for key in RADII:
		if bname.ends_with(key):
			return RADII[key]
	return 0.04


func _leaf_length(bname: String) -> float:
	for key in LEAF_LENGTH:
		if key in bname:
			return LEAF_LENGTH[key]
	return 0.05


func _leaf_dir(sk: Skeleton3D, bone: int) -> Vector3:
	# Continue in the direction the parent pointed at us.
	var parent := sk.get_bone_parent(bone)
	if parent < 0:
		return Vector3.UP
	var my_origin := sk.get_bone_rest(bone).origin
	if my_origin.length() < 0.001:
		return Vector3.UP
	# Express parent->me direction in my own rest space.
	return (sk.get_bone_rest(bone).basis.inverse() * my_origin).normalized()


static func _basis_y_to(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var helper := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(helper).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)
