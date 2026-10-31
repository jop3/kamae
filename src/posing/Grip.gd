class_name Grip
extends RefCounted
## One hand held onto a target, with the offset that was captured when it was attached.

var gripper_id: String = ""
var hand: String = "Right"          ## "Right" | "Left"
var target: GripTarget
var offset := Transform3D()          ## target_world⁻¹ × hand_world at attach time
## How the hand sits on a weapon's shaft: the roll about the shaft and the skew of the fingers
## across it that produced `offset`. Kept so a re-fit can prefer the hold the hand already has
## over the weapon's default guess; `hold_known` is false for a grip whose hand was captured
## where it happened to be (a bone grip, or a weapon grip taken without snapping).
var hold_known := false
var roll_deg := 0.0
var skew_deg := 0.0


func limb_key() -> String:
	return hand + "Arm"


## Where the gripping hand should be, given where the target is now.
func desired_hand_transform() -> Transform3D:
	return target.world_transform() * offset


func describe() -> String:
	return "%s %s hand → %s" % [gripper_id, hand.to_lower(), target.describe()]


func to_dict() -> Dictionary:
	var d := {"gripper": gripper_id, "hand": hand, "target": target.to_dict(), "offset": offset}
	if hold_known:
		d["roll_deg"] = roll_deg
		d["skew_deg"] = skew_deg
	return d


static func from_dict(scene: Node, data: Dictionary) -> Grip:
	var grip := Grip.new()
	grip.gripper_id = data["gripper"]
	grip.hand = data["hand"]
	grip.target = GripTarget.from_dict(scene, data["target"])
	grip.offset = data.get("offset", Transform3D())
	if data.has("roll_deg"):
		grip.hold_known = true
		grip.roll_deg = float(data["roll_deg"])
		grip.skew_deg = float(data.get("skew_deg", 0.0))
	return grip
