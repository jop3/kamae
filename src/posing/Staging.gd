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
## The rear hand of a two-handed hold takes the shaft a quarter turn further round than the
## default's guess (a jo's at 90° past it, a bokken's at 75°), and a cut brought down needs
## 60° of skew: up to ±60° of roll the search stopped at its own edge with the cost still
## falling and called those hands impossible.
##
## The rolls go in 7.5° steps rather than 15°: with the fit keeping the hold a hand already has,
## the step is how far a hand must turn between two poses when its own hold stops clearing the
## wrist, and halving it halved those turns — kumitachi's cut, 11 frames not plausible on the
## 15° grid, has none on this one. The search costs no more for it, because a hold that still
## clears its joints is taken before the rest of the grid is tried.
const HOLD_ROLLS := [0.0, -7.5, 7.5, -15.0, 15.0, -22.5, 22.5, -30.0, 30.0, -37.5, 37.5, -45.0, 45.0, -52.5, 52.5, -60.0, 60.0, -67.5, 67.5, -75.0, 75.0, -82.5, 82.5, -90.0, 90.0]
const HOLD_SKEWS := [0.0, -20.0, 20.0, -40.0, 40.0, -60.0, 60.0]

## Turns each of `id`'s hands that grips `weapon` about the shaft, and skews the fingers across
## it, to where its wrist, elbow and shoulder refuse least: the roll and the skew of a hold are
## what a two-handed weapon grip leaves to the wrist, and the default hold's 45° was a guess. Weapon-driven weapons only
## (both hands are grips); a hand-driven holder's own hand is placed by its arm.
##
## A hand that already holds the weapon keeps the hold it has wherever its joints allow: the
## poses of a technique are fitted one after another on the same hands, and a hand rolled one
## way in one pose and back in the next asks the wrist, half-way between them, for a turn
## neither pose asks for (tests/check_motion.gd). FIT_VERBOSE=1 prints each hand's chosen hold,
## =2 every candidate it was chosen over.
func fit_weapon_hands(id: String, weapon: Weapon) -> void:
	# Two passes: the arms share a shoulder girdle, so fitting the second hand moves the first
	# hand's shoulder and can undo its fit; the second pass re-fits each hand against the other
	# hand's final hold, and a hand already at cost 0 keeps its hold.
	for _pass in 2:
		await _fit_weapon_hands_once(id, weapon)


func _fit_weapon_hands_once(id: String, weapon: Weapon) -> void:
	var r := rig(id)
	var verbose := OS.get_environment("FIT_VERBOSE")
	for grip in director.grips_for(id).duplicate():
		if grip.target.kind != GripTarget.Kind.WEAPON or grip.target.weapon_id != weapon.weapon_id:
			continue
		var hand: String = grip.hand
		var t: float = grip.target.t
		# Closed onto the shaft before anything is measured: a fist leaves the wrist less range
		# than an open hand and the search reads that range (JointLimits).
		GripDirector.close_fingers_on_weapon(r, hand, weapon)
		var base: float = float(weapon.default_hold(hand)["roll_deg"])
		# A hand that already holds the shaft is measured from the hold it has, not from the
		# weapon's default guess: consecutive poses of a technique refit the same hands, and a
		# hand rolled 75° from the default in one pose and back to it in the next asks the wrist
		# for the whole turn in between, which is what the frames between them were failing on.
		var from_roll: float = grip.roll_deg if grip.hold_known else base
		var from_skew: float = grip.skew_deg if grip.hold_known else 0.0
		# Nearest candidate first, so a hand whose own hold still costs nothing keeps it without
		# the rest of the grid being tried. Ties keep the lists' own order (Godot's sort is not
		# stable), so a fit from the default hold tries exactly what it tried before.
		var rolls := _nearest_first(HOLD_ROLLS, func(d: float) -> float: return _turn(base + d, from_roll))
		var skews := _nearest_first(HOLD_SKEWS, func(sk: float) -> float: return absf(sk - from_skew))
		var current: Grip = grip
		var best_roll := from_roll
		var best_skew := from_skew
		var best_cost := INF
		for d in rolls:
			for sk in skews:
				director._remove(current)
				current = director._attach_to_weapon_raw(r, hand, weapon, t, true, base + float(d), float(sk))
				await settle(4)
				var turn := _turn(base + float(d), from_roll) + absf(float(sk) - from_skew)
				var excess := arm_refusal_excess(r, hand)
				var cost := excess + 2000.0 * director.error_for(current) + 0.02 * turn
				if verbose == "2":
					print("  try %s/%s roll %+.0f skew %+.0f: excess %.1f reach %.3f turn %.0f"
						% [id, hand, base + float(d), float(sk), excess, director.error_for(current), turn])
				if cost < best_cost:
					best_cost = cost; best_roll = base + float(d); best_skew = float(sk)
				if best_cost < 1e-3:
					break
			if best_cost < 1e-3:
				break
		# Through the default hold, always: an arm's pole is taken from where the arm is now, so
		# the pose kept would otherwise depend on whichever candidate the search happened to try
		# last, and that is the order the grid was walked in. Coming to the chosen hold from the
		# same place every time makes the fit reproducible.
		director._remove(current)
		current = director._attach_to_weapon_raw(r, hand, weapon, t, true, base, 0.0)
		await settle(4)
		director._remove(current)
		director._attach_to_weapon_raw(r, hand, weapon, t, true, best_roll, best_skew)
		await settle(4)
		if verbose == "1" or verbose == "2":
			print("fit %s/%s on %s t=%.3f: roll %+.0f skew %+.0f cost %.2f; refused now: %s"
				% [id, hand, weapon.weapon_id, t, best_roll, best_skew, best_cost, "; ".join(r.joint_limits.report())])


## `values` ordered by `distance`, ties in the order they were given.
static func _nearest_first(values: Array, distance: Callable) -> Array:
	var order := range(values.size())
	order.sort_custom(func(i: int, j: int) -> bool:
		var di: float = distance.call(float(values[i]))
		var dj: float = distance.call(float(values[j]))
		return di < dj if not is_equal_approx(di, dj) else i < j)
	var out := []
	for i in order:
		out.append(float(values[i]))
	return out


## How far a hand turns on the shaft to go from one roll to another, in degrees the short way round.
static func _turn(roll_deg: float, from_deg: float) -> float:
	return absf(wrapf(roll_deg - from_deg, -180.0, 180.0))


## How much of the fitted curl a grip may settle for, tried tightest first (see `grab`).
const CURL_EASE := [1.0, 0.8, 0.6]
## The skews a wrapped grip falls back to when the catalogue's own leave the arm refused.
const WIDE_SKEWS := [0.0, -10.0, 10.0, -20.0, 20.0, -30.0, 30.0, -40.0, 40.0]


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
	# Close the fingers onto what is being held before anything is measured: the wrist's range
	# depends on the hand's curl (a fist bends less than an open hand), so the side and skew
	# search below must see the hand it is going to end up with. `curl` is now only what a
	# finger that cannot reach falls back to.
	var seat_along := clampf(along, 0.25, 0.9)
	close_fingers_onto(g, hand, t, bone, curl, seat_along)
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
		# ... and how far the fingers close is part of the search too: a hand closed onto what it
		# holds leaves its wrist less range than an open one (JointLimits reads the curl), so a
		# grip the joints refuse by a few degrees is worth taking with the fingers a little short
		# of the surface rather than not at all. CURL_EASE is how much of the fitted curl to try,
		# tightest first; anything looser than this is a hand not holding anything.
		var best_ease := 1.0
		# The catalogue's own skews first; if none of them leaves the arm free, the wider list,
		# because a grip the joints refuse is worse than one whose fingers run a little more
		# diagonally across the wrist than the catalogue thought.
		var rounds := [skews, WIDE_SKEWS]
		for round_skews in rounds:
			if best_cost < 1e-3:
				break
			for candidate in [radial, -radial]:
				for f in [false, true]:
					for sk in round_skews:
						for ease in CURL_EASE:
							close_fingers_onto(g, hand, t, bone, curl, seat_along, float(ease))
							g.limbs[hand + "Arm"].target.global_position = start + candidate * reach
							await settle(2)
							var trial := director.attach_wrapped(g, hand, t, bone, true, f, float(sk))
							await settle(4)
							var cost := arm_refusal_excess(g, hand) + 2000.0 * director.error_for(trial) + 0.02 * absf(float(sk)) + 2.0 * (1.0 - float(ease))
							director._remove(trial)
							if cost < best_cost:
								best_cost = cost; best_side = candidate; flip = f; skew = float(sk); best_ease = float(ease)
		approach_offset = best_side * reach
		close_fingers_onto(g, hand, t, bone, curl, seat_along, best_ease)
	g.limbs[hand + "Arm"].target.global_position = start + approach_offset
	await settle()
	var grip := director.attach_wrapped(g, hand, rig(target), bone, true, flip, skew)
	await settle(3)
	return grip


## Closes each of `hand`'s fingers as far as resting on `bone` takes, no further: the curl is
## worked out from the mesh's own radius there and the finger's own length
## (FingerCurl.curls_onto), rather than from a number in the catalogue. A finger that cannot
## reach round what it holds keeps `fallback`.
func close_fingers_onto(g: CharacterRig, hand: String, t: CharacterRig, bone: String, fallback: float, along: float = 0.5, ease: float = 1.0) -> void:
	var seat := GripDirector.grip_seat(g, hand, t, bone, along)
	var axis: Vector3 = Weapon.canonical_basis(g, hand).y
	var fitted := g.fingers.curls_onto(hand, seat, axis, t.skin_radius(bone, along))
	for finger: String in fitted:
		var c: float = fitted[finger]
		g.fingers.set_curl(hand, finger, (fallback if is_equal_approx(c, 1.0) else c) * ease)


## Degrees by which `hand`'s arm (shoulder, elbow, wrist) is past its joints' ranges on screen,
## with the wrist measured against the range its fist leaves it (the refusal records that).
static func arm_refusal_excess(r: CharacterRig, hand: String) -> float:
	var total := 0.0
	if r.joint_limits == null:
		return 0.0
	for bone in [hand + "UpperArm", hand + "LowerArm", hand + "Hand"]:
		if r.joint_limits.refused.has(bone):
			var refusal: Dictionary = r.joint_limits.refused[bone]
			var e := Joints.excess(r.joints.specs[bone], refusal["wanted"], refusal.get("context", {}))
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
