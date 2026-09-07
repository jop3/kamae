class_name Staging
extends RefCounted
## Puts figures into stances, offers hands, takes grips: the moves a technique is built from,
## as a script would do them. tools/build_fixtures.gd grew these one at a time; Attacks and the
## panel's "Start from attack" use them through this, so a stance is the same stance wherever
## it is asked for. Everything here awaits the skeleton, so call it from a coroutine.

var tree: SceneTree
var scene: PosingScene
var director: GripDirector
var ctrl: PoseController
## Feet lifted on purpose ("id/Side"), which feet_on_floor leaves in the air.
var _lifted: Dictionary = {}


func _init(t: SceneTree, s: PosingScene, d: GripDirector, c: PoseController) -> void:
	tree = t; scene = s; director = d; ctrl = c


func settle(frames: int = 2) -> void:
	for i in frames:
		await tree.process_frame


func rig(id: String) -> CharacterRig:
	return scene.get_character(id)


## Places a character: `x`, `z` on the mat, `yaw_deg` about the vertical, and for a figure that
## is not upright a height and a lean.
func stance(id: String, x: float, z: float, yaw_deg: float, y := 0.0, pitch_deg := 0.0, roll_deg := 0.0) -> void:
	ctrl.set_root(rig(id), Vector3(x, y, z), deg_to_rad(yaw_deg), deg_to_rad(pitch_deg), deg_to_rad(roll_deg))


## Puts a hand at an offset from its own shoulder, in the character's frame (x right-to-left,
## y up, z forward for a character at yaw 0).
func hand_at(id: String, side: String, local_offset: Vector3) -> void:
	var r := rig(id)
	if r.limbs[side + "Arm"].mode != Limb.Mode.IK:
		await ctrl.set_limb_mode(r, side + "Arm", Limb.Mode.IK)
	var shoulder: Vector3 = r.bone_world_transform(side + "UpperArm").origin
	r.limbs[side + "Arm"].target.global_position = shoulder + r.global_transform.basis * local_offset
	r.limbs[side + "Arm"].reset_pole()


## Lifts a foot to an offset from its own hip, in the character's frame, keeping the foot level:
## a kick, a knee raised. The leg goes to IK.
func foot_at(id: String, side: String, local_offset: Vector3) -> void:
	var r := rig(id)
	if r.limbs[side + "Leg"].mode != Limb.Mode.IK:
		await ctrl.set_limb_mode(r, side + "Leg", Limb.Mode.IK)
	var limb: Limb = r.limbs[side + "Leg"]
	var hip: Vector3 = r.bone_world_transform(side + "UpperLeg").origin
	var foot_now: Transform3D = r.bone_world_transform(side + "Foot")
	limb.target.global_transform = Transform3D(foot_now.basis, hip + r.global_transform.basis * local_offset)
	limb.set_orient_to_target(true)
	limb.reset_pole()
	_lifted["%s/%s" % [id, side]] = true


## Puts a weapon of `type` in `id`'s `hand` at `t` along it (Weapon.default_hold's t when
## negative), hand-driven, and returns it.
func hold(id: String, side: String, type: String, t: float = -1.0, weapon_id: String = "") -> Weapon:
	if weapon_id == "":
		weapon_id = "%s_%s" % [type, id]
	var w := scene.get_weapon(weapon_id)
	if w == null:
		w = scene.add_weapon(weapon_id, type)
	var r := rig(id)
	if r.limbs[side + "Arm"].mode != Limb.Mode.IK:
		await ctrl.set_limb_mode(r, side + "Arm", Limb.Mode.IK)
	var at: float = t if t >= 0.0 else float(w.default_hold(side)["t"])
	director.hold_weapon(r, side, w, at)
	await settle(3)
	return w


## The rolls tried for a hand on a weapon, degrees either side of the weapon's default hold,
## and the skews (the fingers running diagonally across the shaft rather than square to it).
const HOLD_ROLLS := [0.0, -15.0, 15.0, -30.0, 30.0, -45.0, 45.0, -60.0, 60.0]
const HOLD_SKEWS := [0.0, -20.0, 20.0, -40.0, 40.0]

## Turns each of `id`'s hands that grips `weapon` about the shaft, and skews the fingers across
## it, to where its wrist, elbow and shoulder refuse least: the roll and the skew of a hold are
## what a two-handed weapon grip leaves to the wrist, and the default hold's 45° was a guess. Weapon-driven weapons only
## (both hands are grips); a hand-driven holder's own hand is placed by its arm.
func fit_weapon_hands(id: String, weapon: Weapon) -> void:
	var r := rig(id)
	for grip in director.grips_for(id).duplicate():
		if grip.target.kind != GripTarget.Kind.WEAPON or grip.target.weapon_id != weapon.weapon_id:
			continue
		var hand: String = grip.hand
		var t: float = grip.target.t
		var base: float = float(weapon.default_hold(hand)["roll_deg"])
		var current: Grip = grip
		var best_roll := base
		var best_skew := 0.0
		var best_cost := INF
		for d in HOLD_ROLLS:
			for sk in HOLD_SKEWS:
				director._remove(current)
				current = director._attach_to_weapon_raw(r, hand, weapon, t, true, base + float(d), float(sk))
				await settle(4)
				var cost := arm_refusal_excess(r, hand) + 2000.0 * director.error_for(current) + 0.02 * (absf(float(d)) + absf(float(sk)))
				if cost < best_cost:
					best_cost = cost; best_roll = base + float(d); best_skew = float(sk)
				if best_cost < 1e-3:
					break
			if best_cost < 1e-3:
				break
		director._remove(current)
		director._attach_to_weapon_raw(r, hand, weapon, t, true, best_roll, best_skew)
		await settle(4)


## A hanmi stance: `front` foot a step forward, rear foot back and turned out, knees bent by
## dropping the hips onto planted feet.
func hanmi(id: String, front: String = "Right", depth: float = 0.32, width: float = 0.16, drop: float = 0.06) -> void:
	var r := rig(id)
	var rear := "Left" if front == "Right" else "Right"
	for side in ["Right", "Left"]:
		if r.limbs[side + "Leg"].mode != Limb.Mode.IK:
			await ctrl.set_limb_mode(r, side + "Leg", Limb.Mode.IK)
	await settle()
	var b := r.global_transform.basis
	var lateral := func(side: String) -> float: return -width if side == "Right" else width   # right is -x
	var foot := func(side: String, forward: float, turn_deg: float) -> void:
		var limb: Limb = r.limbs[side + "Leg"]
		var pos: Vector3 = r.global_position + b * Vector3(lateral.call(side), 0.0, forward)
		var foot_now: Transform3D = r.bone_world_transform(side + "Foot")
		var ankle_height: float = foot_now.origin.y - r.global_position.y
		# Keep the foot's own orientation (its bone axis is not level) and only turn it about the
		# vertical; forcing the rig's basis onto the foot bone points the toes at the sky.
		limb.target.global_transform = Transform3D(foot_now.basis.rotated(Vector3.UP, deg_to_rad(turn_deg)), pos + Vector3(0, ankle_height, 0))
		limb.set_orient_to_target(true)
		limb.reset_pole()
	foot.call(front, depth * 0.5, 0.0)
	foot.call(rear, -depth * 0.5, 40.0 if rear == "Left" else -40.0)
	await settle(2)
	Stance.drop_hips(ctrl, r, drop)
	await settle(3)


func fingers(id: String, side: String, curl: float) -> void:
	rig(id).fingers.set_hand_curl(side, curl)


## Takes `target`'s `bone` in `gripper`'s `hand`: the hand is brought to the bone (at `along`
## of its length) and wrapped round it. It comes from `approach_offset` (world metres) when one
## is given; otherwise from the side its own forearm comes from, which is the only side a
## wrapped hand can be on with a straight wrist: a fist round a shaft has its fingers across the
## shaft and its length at right angles to it, so the forearm must arrive at right angles to the
## shaft too, and the palm lies on the side of the shaft that faces away from the shoulder's
## direction turned a quarter round the shaft. For a wrist held from in front that is the
## *side* of the wrist with the thumb on top — not the top, which is where a script would put
## it and where the wrist would have to bend 90° sideways to hold it.
func grab(gripper: String, hand: String, target: String, bone: String, approach_offset: Vector3 = Vector3.ZERO, along: float = 0.0, curl: float = 0.6, skews: Array = [0.0]) -> Grip:
	var g := rig(gripper)
	if g.limbs[hand + "Arm"].mode != Limb.Mode.IK:
		await ctrl.set_limb_mode(g, hand + "Arm", Limb.Mode.IK)
	var t := rig(target)
	var start: Vector3 = t.bone_world_transform(bone).origin
	var children := t.skeleton.get_bone_children(t.skeleton.find_bone(bone))
	var shaft := Vector3.UP
	if children.size() > 0:
		var end: Vector3 = t.bone_world_transform(t.skeleton.get_bone_name(children[0])).origin
		shaft = (end - start).normalized()
		if along > 0.0:
			start = start.lerp(end, along)
	else:
		shaft = t.bone_world_transform(bone).basis.y.normalized()
	var flip := false
	var skew := 0.0
	if approach_offset.is_zero_approx():
		# Two sides of the shaft leave the wrist straight in principle, and the fingers can run
		# either way along it (thumb toward the hand or toward the elbow). Which of the four the
		# arm can actually make is a question for the joints, so each is tried — attached, solved,
		# and measured by what the arm's shoulder, elbow and wrist refuse — and the best is kept.
		var radial := approach_from_forearm(g, hand, start, shaft)
		var reach := GripDirector.hold_radius(bone) + 0.04
		var best_cost := INF
		var best_side := radial
		for candidate in [radial, -radial]:
			for f in [false, true]:
				for sk in skews:
					g.limbs[hand + "Arm"].target.global_position = start + candidate * reach
					await settle(2)
					var trial := director.attach_wrapped(g, hand, t, bone, true, f, float(sk))
					await settle(4)
					var cost := arm_refusal_excess(g, hand) + 2000.0 * director.error_for(trial) + 0.02 * absf(float(sk))
					director._remove(trial)
					if cost < best_cost:
						best_cost = cost; best_side = candidate; flip = f; skew = float(sk)
		approach_offset = best_side * reach
	g.limbs[hand + "Arm"].target.global_position = start + approach_offset
	await settle()
	var grip := director.attach_wrapped(g, hand, rig(target), bone, true, flip, skew)
	fingers(gripper, hand, curl)
	await settle(3)
	return grip


## Degrees by which `hand`'s arm (shoulder, elbow, wrist) is past its joints' ranges on screen.
static func arm_refusal_excess(r: CharacterRig, hand: String) -> float:
	var total := 0.0
	if r.joint_limits == null:
		return 0.0
	for bone in [hand + "UpperArm", hand + "LowerArm", hand + "Hand"]:
		if r.joint_limits.refused.has(bone):
			var e := Joints.excess(r.joints.specs[bone], r.joint_limits.refused[bone]["wanted"])
			total += e["flex"] + e["abd"] + e["twist"]
	return total


## A side of a shaft through `point` that `gripper`'s `hand` can wrap it from with the wrist
## straight: perpendicular to the shaft and to the line from the shoulder. The opposite side is
## the other such place; grab() tries both.
static func approach_from_forearm(gripper: CharacterRig, hand: String, point: Vector3, shaft: Vector3) -> Vector3:
	var shoulder: Vector3 = gripper.bone_world_transform(hand + "UpperArm").origin
	var f := point - shoulder
	f -= shaft * f.dot(shaft)
	if f.length() < 1e-4:
		f = Vector3.UP
	return f.normalized().cross(shaft).normalized()


func release_all(gripper: String) -> void:
	for grip in director.grips_for(gripper):
		director._remove(grip)
		fingers(gripper, grip.hand, 0.0)
	for w in scene.weapons.duplicate():
		if w.drive == "hand" and w.hold.get("character", "") == gripper:
			scene.remove_weapon(w.weapon_id)
	await settle()


## Where a hand hangs when the attack has nothing for it: at the side, a little forward.
const HANGING := Vector3(0.05, -0.50, 0.08)

## Every limb back to FK at rest, its target on the bone, so a stance built next starts from
## the rest pose and not from whatever the last one left (a rear foot turned out once more each
## time, an arm still reaching for a wrist that is gone).
func rest_limbs(id: String) -> void:
	var r := rig(id)
	for key in r.limbs:
		var limb: Limb = r.limbs[key]
		limb.set_orient_to_target(false)
		limb.set_influence(1.0)
		r.set_limb_mode(key, Limb.Mode.FK)
	for i in r.skeleton.get_bone_count():
		r.skeleton.set_bone_pose_rotation(i, r.skeleton.get_bone_rest(i).basis.get_rotation_quaternion())
	for side in ["Right", "Left"]:
		r.fingers.set_hand_curl(side, 0.0)
		_lifted.erase("%s/%s" % [id, side])
	await settle(2)
	for key in r.limbs:
		(r.limbs[key] as Limb).reset_target_to_pose()


## Hangs `side`'s arm at the side (HANGING, mirrored for the right).
func hang_arm(id: String, side: String) -> void:
	var off := HANGING
	if side == "Right":
		off.x = -off.x
	await hand_at(id, side, off)


## Anyone still on their feet stands on the floor: bending the knees tilts the shins, and arm
## work can pull a figure about, either of which lifts a foot a centimetre or two.
func feet_on_floor() -> void:
	for r in scene.characters:
		if not r.visible or absf(r.rotation.x) > 0.6 or absf(r.rotation.z) > 0.6:
			continue
		for pass_ in 3:
			var moved := false
			for side in ["Right", "Left"]:
				var leg: Limb = r.limbs[side + "Leg"]
				if leg.mode != Limb.Mode.IK or _lifted.has("%s/%s" % [r.character_id, side]):
					continue
				var err: float = 0.02 - r.bone_world_transform(side + "Toes").origin.y
				if absf(err) > 0.004:
					leg.target.global_position += Vector3(0.0, err, 0.0)
					moved = true
			if not moved:
				break
			await settle(3)
