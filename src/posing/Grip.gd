class_name Grip
extends RefCounted
## One hand held onto a target, with the offset that was captured when it was attached.

var gripper_id: String = ""
var hand: String = "Right"          ## "Right" | "Left"
var target: GripTarget
var offset := Transform3D()          ## target_world⁻¹ × hand_world at attach time


func limb_key() -> String:
	return hand + "Arm"


## Where the gripping hand should be, given where the target is now.
func desired_hand_transform() -> Transform3D:
	return target.world_transform() * offset


func describe() -> String:
	return "%s %s hand → %s" % [gripper_id, hand.to_lower(), target.describe()]


func to_dict() -> Dictionary:
	return {"gripper": gripper_id, "hand": hand, "target": target.to_dict(), "offset": offset}


static func from_dict(scene: Node, data: Dictionary) -> Grip:
	var grip := Grip.new()
	grip.gripper_id = data["gripper"]
	grip.hand = data["hand"]
	grip.target = GripTarget.from_dict(scene, data["target"])
	grip.offset = data.get("offset", Transform3D())
	return grip
