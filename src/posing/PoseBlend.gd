class_name PoseBlend
extends RefCounted
## Puts the scene at a point between two saved poses (spec §5.6).
##
## Each saved pose is shown exactly at u = 0 and u = 1; between them a body moves the way a person
## does rather than every joint sliding together: each part on its own clock (CHANNELS, from
## SequencePlayer.timing), joints and root on curves through the poses either side, free hands
## round the shoulder with the body, feet round a turn, elbows and knees steered between where the
## two poses were solved, grips handed over by weight. Falls follow their own course (Ukemi).
## Nothing here touches undo: a preview is not an edit.


## Applies the blend for `u` in 0..1 between pose dictionaries `a` and `b` (PoseFile format).
## Characters and weapons are matched by id; both poses are expected to contain the same ids.
##
## `ctx` carries what the player knows beyond the four poses:
##   "solved_a", "solved_b": where each limb's elbow or knee and hand or foot really were when the
##     two poses were shown (SequencePlayer.prepare: {character id: {limb key: {"mid", "end"}}},
##     in the figure's own frame). With them a bending limb is steered from one solved shape to
##     the other.
##   "u": {channel: 0..1}, how far each part of a body is (CHANNELS); `u` for any not given.
##   "times": [prev, b, next], the times of the neighbouring poses and of b, seconds from a, for
##     the curves through them.
static func apply(scene: PosingScene, director: GripDirector, a: Dictionary, b: Dictionary, u: float,
		prev: Dictionary = {}, next: Dictionary = {}, ctx: Dictionary = {}) -> void:
	u = clampf(u, 0.0, 1.0)
	var chars_a := _by_id(a.get("characters", []))
	var chars_b := _by_id(b.get("characters", []))
	var chars_prev := _by_id(prev.get("characters", []))
	var chars_next := _by_id(next.get("characters", []))
	var grips_a := _grips_by_key(a)
	var grips_b := _grips_by_key(b)
	var orient_after := {}
	# A figure with a weapon in hand moves its arms with its trunk: the weapon is held by both
	# hands and driven from the hips, and arms trailing the turning body would put a forearm
	# through it (kumijo's thrust).
	var holders := {}
	for pose in [a, b]:
		for wd in pose.get("weapons", []):
			var h = wd.get("hold", {})
			if h is Dictionary and h.has("character"):
				holders[h["character"]] = true
		for g in pose.get("grips", []):
			if g.get("target", {}).get("kind", "") == "weapon":
				holders[g.get("gripper", "")] = true
	if not holders.is_empty():
		ctx = ctx.duplicate()
		ctx["holders"] = holders
	for id in _union(chars_a.keys(), chars_b.keys()):
		var rig: CharacterRig = scene.get_character(id)
		if rig == null:
			continue
		var ca: Dictionary = chars_a.get(id, chars_b.get(id))
		var cb: Dictionary = chars_b.get(id, chars_a.get(id))
		var orient: Dictionary = _apply_character(rig, ca, cb, u, grips_a, grips_b,
			chars_prev.get(id, ca), chars_next.get(id, cb),
			ctx.get("solved_a", {}).get(id, {}), ctx.get("solved_b", {}).get(id, {}), ctx)
		if not orient.is_empty():
			orient_after[rig] = orient
	var cu: Dictionary = ctx.get("u", {})
	var u_arms: float = clampf(float(cu.get("arms", u)), 0.0, 1.0)
	var u_held: float = clampf(float(cu.get("spine", u)), 0.0, 1.0)
	var arm_u := {}
	for id in holders:
		arm_u[id] = u_held
	var holds_before := _hold_signature(scene)
	_apply_weapons(scene, a, b, u_held if not holders.is_empty() else u_arms)
	_apply_grips(scene, director, a, b, u_arms, grips_a, grips_b, arm_u)
	# Adding and removing grips sets the hands' orientation outright; a hand on its way to or from
	# a grip turns to it as far as the grip has it.
	for rig: CharacterRig in orient_after:
		for key: String in orient_after[rig]:
			rig.limbs[key].set_orient_weight(orient_after[rig][key])
	if director and _hold_signature(scene) != holds_before:
		director.rebuild()
	if director:
		director.refresh_hand_driven()
	# Strictly between two poses only: on a keyframe (u == 0) the saved pose is shown untouched.
	if moving(u, ctx):
		MotionClearance.resolve(scene, director, clearance_strength(u, ctx))


## How strongly MotionClearance corrects each part: fully through the middle of its move, fading
## to nothing over the first and last CLEARANCE_FADE of it, so its corrections start and end as
## smoothly as the move itself (MotionClearance.resolve).
const CLEARANCE_FADE := 0.2


static func clearance_strength(u: float, ctx: Dictionary) -> Dictionary:
	var out := {}
	var cu: Dictionary = ctx.get("u", {})
	for part in ["root", "arms", "legs"]:
		var w := clampf(float(cu.get(part, u)), 0.0, 1.0)
		out[part] = smoothstep(0.0, CLEARANCE_FADE, w) * smoothstep(0.0, CLEARANCE_FADE, 1.0 - w)
	return out


## Whether anything is strictly between the two poses: the blend's own `u`, or any part of a body
## on its own clock (ctx "u", see CHANNELS).
static func moving(u: float, ctx: Dictionary) -> bool:
	if u > 0.0 and u < 1.0:
		return true
	for c in ctx.get("u", {}):
		var w := float(ctx["u"][c])
		if w > 0.0 and w < 1.0:
			return true
	return false


## Makes sure every character and weapon named by any of `poses` exists in the scene, so a
## figure or weapon that first appears in a later step is there to be blended into.
static func ensure_entities(scene: PosingScene, poses: Array) -> void:
	for pose in poses:
		for c in pose.get("characters", []):
			if scene.get_character(c["id"]) == null and scene.characters.size() < PosingScene.MAX_CHARACTERS:
				var rig := scene.add_character(c["id"], c.get("name", c["id"]), c.get("role", "Other"))
				if c.has("skin_color"):
					rig.set_skin_color(Color.html(c["skin_color"]))
		for wd in pose.get("weapons", []):
			if scene.get_weapon(wd["id"]) == null:
				var w := scene.add_weapon(wd["id"], wd.get("type", "bokken"))
				w.apply_dict(wd)


## Who holds what: when this changes the director must re-derive its order and connections.
static func _hold_signature(scene: PosingScene) -> Array:
	var sig := []
	for w in scene.weapons:
		sig.append([w.weapon_id, w.drive, w.hold.get("character", ""), w.hold.get("hand", "")])
	return sig


## The parts of a body that move on their own clocks between two poses (SequencePlayer.channels):
## a person moves from the centre, so the hips lead, the spine and head go with them, the legs step
## and land, and the arms and hands follow and arrive last. Every bone, target and setting belongs
## to one of them.
const CHANNELS := ["root", "spine", "head", "legs", "arms", "hands"]


static func bone_channel(bone: String) -> String:
	if bone == "Hips":
		return "root"
	if bone in ["Spine", "Chest", "UpperChest"]:
		return "spine"
	if bone.begins_with("Neck") or bone.begins_with("Head") or bone.contains("Eye") or bone.contains("Jaw"):
		return "head"
	if FingerCurl.is_finger_bone(bone):
		return "hands"
	if bone.contains("Leg") or bone.contains("Foot") or bone.contains("Toe"):
		return "legs"
	return "arms"


static func _apply_character(rig: CharacterRig, ca: Dictionary, cb: Dictionary, u: float, grips_a: Dictionary, grips_b: Dictionary,
		cprev: Dictionary = {}, cnext: Dictionary = {}, solved_a: Dictionary = {}, solved_b: Dictionary = {},
		ctx: Dictionary = {}) -> Dictionary:
	var orient := {}   # limb key -> how far its hand takes its target's orientation, for grip hands
	var ra: Dictionary = ca.get("root", {})
	var rb: Dictionary = cb.get("root", {})
	# Turning is a direction, so a yaw takes the short way round. Leaning is an amount — a body
	# rolling right over goes through 360 degrees, and 360 is the same *orientation* as 0, so
	# slerping the root would send a completed roll backwards to where it started instead of
	# through. Pitch and roll therefore interpolate as the angles they are, and a figure getting
	# up from a roll carries on round to its feet (continue_turn) rather than unrolling.
	var lean_a := root_euler(ra)
	var lean_b := root_euler(rb)
	lean_b.x = continue_turn(lean_a.x, lean_b.x)
	lean_b.z = continue_turn(lean_a.z, lean_b.z)
	var span := Ukemi.fall_span(ca.get("fall", {}) if ca.get("fall") is Dictionary else {},
		cb.get("fall", {}) if cb.get("fall") is Dictionary else {})
	# A figure is falling between two poses when either is tipped over, or when either says it is
	# in a fall: the squat a backward fall starts with is barely tipped at all. A fall keeps one
	# clock for the whole body: its course (Ukemi) is the timing.
	var fall_blend := is_fall(lean_a) or is_fall(lean_b) or not span.is_empty()
	if fall_blend and ctx.has("fall_u"):
		u = clampf(float(ctx["fall_u"]), 0.0, 1.0)   # a fall keeps the timing it was made with
	var falling := u > 0.0 and u < 1.0 and fall_blend
	# Away from a fall the curves bend through the poses either side only where the movement
	# passes through (a waypoint); a pose the technique rests on is approached and left straight.
	var rest: Array = ctx.get("rest", [false, false])
	if not fall_blend:
		if rest[0]:
			cprev = ca
		if rest[1]:
			cnext = cb
	var uc := {}
	var channel_u: Dictionary = ctx.get("u", {})
	for c in CHANNELS:
		uc[c] = u if (fall_blend or not channel_u.has(c)) else clampf(float(channel_u[c]), 0.0, 1.0)
	if ctx.get("holders", {}).has(rig.character_id):
		uc["arms"] = uc["spine"]
		uc["hands"] = uc["spine"]
	# Times of the four poses for the curves through them, seconds from pose a: the curve meets
	# its neighbours with the speed the blend actually has there (cubic_interpolate_in_time).
	var times: Array = ctx.get("times", [-1.0, 1.0, 2.0])
	var t_pre: float = times[0]
	var t_b: float = times[1]
	var t_post: float = times[2]
	var u_root: float = uc["root"]
	var lean := Vector3(lerpf(lean_a.x, lean_b.x, u_root), lerp_angle(lean_a.y, lean_b.y, u_root),
		lerpf(lean_a.z, lean_b.z, u_root))
	var rprev: Dictionary = cprev.get("root", ra)
	var rnext: Dictionary = cnext.get("root", rb)
	if not falling and u_root > 0.0 and u_root < 1.0:
		# The turn sweeps through a waypoint as the position does, rather than turning a corner.
		var y_pre := lean_a.y + yaw_turn(lean_a.y, root_euler(rprev).y)
		var y_b := lean_a.y + yaw_turn(lean_a.y, lean_b.y)
		var y_post := y_b + yaw_turn(lean_b.y, root_euler(rnext).y)
		lean.y = cubic_interpolate_in_time(lean_a.y, y_b, y_pre, y_post, u_root, t_b, t_pre, t_post)
	# Between two poses of one fall the body turns as the fall turns (Ukemi.pitch_deg: down
	# first, then over), not at the even rate a straight blend of the two would give it.
	if not span.is_empty() and u > 0.0 and u < 1.0:
		lean.x = Ukemi.blend_pitch(span, lean_a.x, lean_b.x, u)
		lean.z = Ukemi.blend_tilt(span, lean_a.z, lean_b.z, u)
	rig.rotation = lean
	var sk := rig.skeleton
	var bones_a: Dictionary = ca.get("bones", {})
	var bones_b: Dictionary = cb.get("bones", {})
	var bones_prev: Dictionary = cprev.get("bones", bones_a)
	var bones_next: Dictionary = cnext.get("bones", bones_b)
	for bone in _union(bones_a.keys(), bones_b.keys()):
		var idx := sk.find_bone(bone)
		if idx < 0:
			continue
		var qa := PoseFile.array_to_quat(bones_a.get(bone, bones_b.get(bone)))
		var qb := PoseFile.array_to_quat(bones_b.get(bone, bones_a.get(bone)))
		var w: float = uc[bone_channel(bone)]
		if w <= 0.0:
			sk.set_bone_pose_rotation(idx, qa)
		elif w >= 1.0:
			sk.set_bone_pose_rotation(idx, qb)
		elif falling:
			sk.set_bone_pose_rotation(idx, qa.slerp(qb, w).normalized())
		else:
			# A joint turns on a curve through the poses either side, so it does not stop dead or
			# change speed at a waypoint (a straight slerp per segment does both); exact at a and b.
			var q0 := PoseFile.array_to_quat(bones_prev.get(bone, bones_a.get(bone, bones_b.get(bone))))
			var q3 := PoseFile.array_to_quat(bones_next.get(bone, bones_b.get(bone, bones_a.get(bone))))
			sk.set_bone_pose_rotation(idx, qa.spherical_cubic_interpolate_in_time(qb, q0, q3, w, t_b, t_pre, t_post).normalized())
	if not span.is_empty() and u > 0.0 and u < 1.0:
		Ukemi.blend_tuck(rig, span, u)
	# The root follows a curve through the steps on either side rather than a straight line
	# between these two, so a technique that passes through a waypoint sweeps through it instead
	# of turning a corner on the spot. The curve still passes exactly through every keyframe.
	var p1 := PoseFile.array_to_vec(ra.get("pos", [0, 0, 0]))
	var p2 := PoseFile.array_to_vec(rb.get("pos", [0, 0, 0]))
	var p0 := PoseFile.array_to_vec(rprev.get("pos", ra.get("pos", [0, 0, 0])))
	var p3 := PoseFile.array_to_vec(rnext.get("pos", rb.get("pos", [0, 0, 0])))
	rig.keep_on_mat = falling
	if not falling:
		rig.position = p1.cubic_interpolate_in_time(p2, p0, p3, u_root, t_b, t_pre, t_post)
	else:
		_fall_root(rig, ca, cb, lean_a, lean_b, [p0, p1, p2, p3], [root_euler(rprev), root_euler(rnext)], u)
	var fa: Dictionary = ca.get("fingers", {})
	var fb: Dictionary = cb.get("fingers", {})
	for side in FingerCurl.SIDES:
		for finger in FingerCurl.FINGERS:
			var va: float = float(fa.get(side, {}).get(finger, 0.0))
			var vb: float = float(fb.get(side, {}).get(finger, 0.0))
			rig.fingers.set_curl(side, finger, lerpf(va, vb, uc["hands"]))
	# Limbs. A gripped limb is handled by the grip rules; otherwise blend the IK state.
	var ik_a: Dictionary = ca.get("ik", {})
	var ik_b: Dictionary = cb.get("ik", {})
	var xa := Transform3D(Basis.from_euler(lean_a), p1)
	var xb := Transform3D(Basis.from_euler(lean_b), p2)
	var body_moving := false
	for c in uc:
		body_moving = body_moving or (uc[c] > 0.0 and uc[c] < 1.0)
	for key in rig.limbs:
		var limb: Limb = rig.limbs[key]
		var ul: float = uc["arms"] if limb.is_arm else uc["legs"]
		var blending := ul > 0.0 and ul < 1.0
		# Mid-move as far as the limb's solve goes whenever any part of the body is: an arm still
		# on its pose while the hips lead off is carried, and searched afresh it can flip.
		var steer := (blending or body_moving) and not falling
		# A falling limb's pole is the fall's own (below), but its turn too is searched locally.
		limb.set_blending(steer or (falling and (blending or body_moving)))
		var grip_key := "%s/%s" % [rig.character_id, key.trim_suffix("Arm")]
		var in_a := grips_a.has(grip_key)
		var in_b := grips_b.has(grip_key)
		if steer:
			var pole := body_pole(rig, ik_a.get(key, {}), ik_b.get(key, {}), xa, xb, ul, limb.pole.global_position)
			limb.pole.global_position = steered_pole(rig, limb, solved_a.get(key, {}), solved_b.get(key, {}), ul, pole)
		if in_a or in_b:
			# The grip director drives the target, weighted against the hand's own way between
			# the two poses (grip_weight): a grip taken or let go hands the hand over gradually.
			# That way is set here, as the target the director blends from.
			rig.set_limb_mode(key, Limb.Mode.IK)
			limb.set_influence(1.0)
			var ga: Dictionary = ik_a.get(key, {})
			var gb: Dictionary = ik_b.get(key, {})
			var weight := grip_weight(grip_key, grips_a, grips_b, ul)
			var oa := 1.0 if in_a else (1.0 if ga.get("orient", false) else 0.0)
			var ob := 1.0 if in_b else (1.0 if gb.get("orient", false) else 0.0)
			if in_a and in_b:
				orient[key] = 1.0
			elif in_a:
				orient[key] = ob + (1.0 - ob) * weight
			else:
				orient[key] = oa + (1.0 - oa) * weight
			limb.set_orient_weight(orient[key])
			if ga.has("target") and gb.has("target"):
				var gta := PoseFile.array_to_transform(ga["target"])
				var gtb := PoseFile.array_to_transform(gb["target"])
				limb.target.global_transform = gta.interpolate_with(gtb, ul) if falling \
					else arm_with_body(rig, limb, gta, gtb, bones_a, bones_b, xa, xb, ul)
			continue
		var ea: Dictionary = ik_a.get(key, {})
		var eb: Dictionary = ik_b.get(key, {})
		var ik_in_a: bool = ea.get("mode", "fk") == "ik"
		var ik_in_b: bool = eb.get("mode", "fk") == "ik"
		if not ik_in_a and not ik_in_b:
			rig.set_limb_mode(key, Limb.Mode.FK)
			limb.set_influence(1.0)
			continue
		rig.set_limb_mode(key, Limb.Mode.IK)
		var ta := PoseFile.array_to_transform(ea.get("target", eb.get("target")))
		var tb := PoseFile.array_to_transform(eb.get("target", ea.get("target")))
		var pa := PoseFile.array_to_vec(ea.get("pole", eb.get("pole", [0, 0, 0])))
		var pb := PoseFile.array_to_vec(eb.get("pole", ea.get("pole", [0, 0, 0])))
		var t: Transform3D
		if falling and limb.is_arm:
			# A falling body's free arm goes with the body: its target and pole are blended in
			# the body's own frame, not across the room. In the world frame the hand takes the
			# straight line between two places while the shoulder turns over through a circle,
			# so the arm is flung out and the hand driven into the mat on the way.
			var here := rig.global_transform
			t = here * (xa.affine_inverse() * ta).interpolate_with(xb.affine_inverse() * tb, ul)
			t.origin.y = maxf(t.origin.y, Ukemi.MAT_Y + HAND_ABOVE_MAT)
			limb.target.global_transform = t
			limb.pole.global_position = here * (xa.affine_inverse() * pa).lerp(xb.affine_inverse() * pb, ul)
		elif not limb.is_arm and ik_in_a and ik_in_b and blending:
			# A foot on the mat in both poses. A saved target can lie out of the leg's reach —
			# under the mat, where a stance's hips were too high for the foot to get down to it —
			# and the leg then stands straight toward it with the foot wherever that leaves it.
			# Blended toward such a target, the leg sweeps the foot down through the mat. So the
			# foot is blended between where it actually was in each pose (the target pulled in
			# to the leg's reach, which the IK reaches exactly as it reached for the original).
			var foot_a := within_reach(rig, limb, ta, bones_a, xa)
			var foot_b := within_reach(rig, limb, tb, bones_b, xb)
			t = foot_a.interpolate_with(foot_b, ul) if falling else turn_with_body(foot_a, foot_b, yaw_turn(lean_a.y, lean_b.y), ul)
			t.origin.y += step_lift(foot_a.origin, foot_b.origin, ul)
			# A foot turning on the mat (a pivot, a tenkan) turns about its ball, not its ankle,
			# which is where the target is: the ankle's straight line and the foot's turn put the
			# heel or the toes through the mat half-way. Lifted until the sole is as high as the
			# two poses have it, or on the mat.
			var side: String = key.trim_suffix("Leg")
			var want := clampf(lerpf(sole_lowest(rig, side, foot_a), sole_lowest(rig, side, foot_b), ul), -Ukemi.MAT_SLACK, 0.0)
			var short := want - sole_lowest(rig, side, t)
			if short > 0.0:
				t.origin.y += short
			limb.target.global_transform = t
			if falling:
				limb.pole.global_position = pa.lerp(pb, ul)
		elif limb.is_arm and ik_in_a and ik_in_b and (blending or (u_root > 0.0 and u_root < 1.0)):
			t = arm_with_body(rig, limb, ta, tb, bones_a, bones_b, xa, xb, ul)
			limb.target.global_transform = t
		else:
			t = ta.interpolate_with(tb, ul)
			if not limb.is_arm and ik_in_a and ik_in_b:
				t.origin.y += step_lift(ta.origin, tb.origin, ul)
			limb.target.global_transform = t
			if not steer:
				limb.pole.global_position = pa.lerp(pb, ul)
		limb.set_orient_to_target(bool(ea.get("orient", eb.get("orient", false))))
		limb.set_influence(1.0 if (ik_in_a and ik_in_b) else (1.0 - ul if ik_in_a else ul))
	return orient


## Where a limb's pole goes between two poses: carried with the body. Each pose's pole is taken
## into its own root's frame, the two are blended there, and the result is put back with the root
## as it is now (`here`). A pole lerped across the room instead stays where it was while the
## figure turns round (a tenkan, a kaiten): half-way it passes through the line from hip to ankle
## and the knee flips over in a frame. Exact at either pose.
static func body_pole(rig: CharacterRig, ea: Dictionary, eb: Dictionary, xa: Transform3D, xb: Transform3D,
		u: float, fallback: Vector3) -> Vector3:
	if not (ea.has("pole") or eb.has("pole")):
		return fallback
	var pa := PoseFile.array_to_vec(ea.get("pole", eb.get("pole")))
	var pb := PoseFile.array_to_vec(eb.get("pole", ea.get("pole")))
	var here := Transform3D(Basis.from_euler(rig.rotation), rig.position)
	return here * (xa.affine_inverse() * pa).lerp(xb.affine_inverse() * pb, u)


## Where a limb's pole goes between two poses when the player has seen both solved: so that the
## elbow (or knee) goes from where it really was in the one to where it really was in the other,
## carried with the body. The solved joints are what the two keyframes show — the saved bone
## rotations are not quite (a leg's knee can sit 3–5 cm off them), and a pole taken from those
## puts the knee a few centimetres off the keyframe in the first frame after it. Steered this way
## the joint moves on smoothly from exactly where the keyframe had it, and the searches that
## place it last (LimbTurn.descend) start from there. `fallback` without both solves, or for a
## limb too straight to have a bend.
const POLE_OUT := 0.3


static func steered_pole(rig: CharacterRig, limb: Limb, sa: Dictionary, sb: Dictionary, u: float, fallback: Vector3) -> Vector3:
	if sa.is_empty() or sb.is_empty():
		return fallback
	var here := rig.global_transform
	var mid: Vector3 = here * (sa["mid"] as Vector3).lerp(sb["mid"], u)
	var end: Vector3 = here * (sa["end"] as Vector3).lerp(sb["end"], u)
	var root := rig.fk_bone_transform(limb.root_bone).origin
	var line := end - root
	if line.length() < 1e-4:
		return fallback
	var dir := line.normalized()
	var off := mid - (root + dir * (mid - root).dot(dir))
	var bent := off.length()
	if bent < 1e-5:
		return fallback
	return fallback.lerp(mid + off / bent * POLE_OUT, smoothstep(0.01, 0.03, bent))


## How far the root turns about the vertical from yaw `from` to yaw `to`, radians, the way the
## blend turns it (lerp_angle: the short way round).
static func yaw_turn(from: float, to: float) -> float:
	var d := fmod(to - from, TAU)
	return fmod(2.0 * d, TAU) - d


## A foot's way from `from` to `to` while its figure turns by `turn` radians about the vertical.
## A foot carried round a turn travels on the circle the turn implies — about the other foot in a
## tenkan, about itself in a pivot — not on the straight line between where it was and where it
## ends up, which in a turn of half a circle passes through the pivot foot and whoever stands
## there. The circle's centre is the one point that the turn takes `from` to `to`; the foot's
## heading turns with the body. Straight for a step that turns less than ARC_MIN_TURN (a step with
## a quarter turn on the way is a step, and bending it only bends the ankle), exact at both ends.
const ARC_MIN_TURN := deg_to_rad(45.0)


static func turn_with_body(from: Transform3D, to: Transform3D, turn: float, u: float) -> Transform3D:
	if absf(turn) < ARC_MIN_TURN:
		return from.interpolate_with(to, u)
	var c := cos(turn)
	var s := sin(turn)
	# Vector3.rotated(UP, turn) takes (x, z) to (x c + z s, -x s + z c); the centre solves
	# to - centre = R (from - centre), i.e. (I - R) centre = to - R from.
	var ra := from.origin.rotated(Vector3.UP, turn)
	var rhs := Vector2(to.origin.x - ra.x, to.origin.z - ra.z)
	var det := 2.0 - 2.0 * c
	var centre := Vector3(((1.0 - c) * rhs.x + s * rhs.y) / det, 0.0, (-s * rhs.x + (1.0 - c) * rhs.y) / det)
	var flat := Vector3(from.origin.x, 0.0, from.origin.z) - centre
	var at := centre + flat.rotated(Vector3.UP, turn * u)
	var basis := Basis(Vector3.UP, turn * u) * from.basis.slerp(Basis(Vector3.UP, -turn) * to.basis, u)
	return Transform3D(basis, Vector3(at.x, lerpf(from.origin.y, to.origin.y, u), at.z))


## A free hand's way between two poses: with the body, round the shoulder. Each pose's target is
## taken into its own root's frame and measured from where that pose has the shoulder; between
## them the hand's direction from the shoulder turns and its distance changes evenly, and the
## whole is carried by the root as it is now. A hand lerped across the room goes in a straight
## line however the body turns under it — through the chest when a figure turns round — and a
## real arm swings from the shoulder, so its hand travels on an arc. Exact at both ends.
static func arm_with_body(rig: CharacterRig, limb: Limb, ta: Transform3D, tb: Transform3D, bones_a: Dictionary,
		bones_b: Dictionary, xa: Transform3D, xb: Transform3D, u: float) -> Transform3D:
	var sk := rig.skeleton
	var sk_in_root := rig.global_transform.affine_inverse() * sk.global_transform
	var i := sk.find_bone(limb.root_bone)
	var sh_a: Vector3 = sk_in_root * _fk_global(sk, i, bones_a, {}).origin
	var sh_b: Vector3 = sk_in_root * _fk_global(sk, i, bones_b, {}).origin
	var la := xa.affine_inverse() * ta
	var lb := xb.affine_inverse() * tb
	var da := la.origin - sh_a
	var db := lb.origin - sh_b
	var reach: Vector3
	if da.length() > 0.02 and db.length() > 0.02 and da.normalized().dot(db.normalized()) > -0.99:
		reach = da.normalized().slerp(db.normalized(), u) * lerpf(da.length(), db.length(), u)
	else:
		reach = da.lerp(db, u)
	var local := Transform3D(la.basis.slerp(lb.basis, u), sh_a.lerp(sh_b, u) + reach)
	return rig.global_transform * local


## How high a foot is carried at `u` on its way from `from` to `to`. A foot that moves across
## the mat between two poses where it stands on it is stepped, not slid: lifted on an arc as
## high as a quarter of the stride, up to 10 cm, and set down again. A foot that only turns, or
## moves less than a short shuffle, stays down; so does one that was not on the mat to begin
## with (a kick, a fall). Exactly zero at either pose, so a saved pose is shown as saved.
const STEP_MIN := 0.08
const STEP_MAX_LIFT := 0.10
const STEP_FLOOR := 0.2


static func step_lift(from: Vector3, to: Vector3, u: float) -> float:
	var stride := Vector2(to.x - from.x, to.z - from.z).length()
	if stride < STEP_MIN or from.y > STEP_FLOOR or to.y > STEP_FLOOR:
		return 0.0
	return minf(STEP_MAX_LIFT, stride * 0.25) * sin(PI * clampf(u, 0.0, 1.0))


static func _apply_weapons(scene: PosingScene, a: Dictionary, b: Dictionary, u: float) -> void:
	var wa := _by_id(a.get("weapons", []))
	var wb := _by_id(b.get("weapons", []))
	for id in _union(wa.keys(), wb.keys()):
		var weapon: Weapon = scene.get_weapon(id)
		if weapon == null:
			continue
		var da: Dictionary = wa.get(id, wb.get(id))
		var db: Dictionary = wb.get(id, wa.get(id))
		var xa := PoseFile.array_to_transform(da.get("transform"))
		var xb := PoseFile.array_to_transform(db.get("transform"))
		weapon.free_transform = xa.interpolate_with(xb, u)
		var ha: Dictionary = da.get("hold", {})
		var hb: Dictionary = db.get("hold", {})
		var held_a: bool = da.get("drive", "hand") == "hand" and not ha.is_empty()
		var held_b: bool = db.get("drive", "hand") == "hand" and not hb.is_empty()
		var same_holder: bool = held_a and held_b and ha.get("character") == hb.get("character") and ha.get("hand") == hb.get("hand")
		if same_holder:
			weapon.drive = "hand"
			var rig: CharacterRig = scene.get_character(ha["character"])
			var oa := PoseFile.array_to_transform(ha.get("offset"))
			var ob := PoseFile.array_to_transform(hb.get("offset"))
			weapon.hold = {"character": ha["character"], "hand": ha["hand"],
				"t": lerpf(float(ha.get("t", 0.0)), float(hb.get("t", 0.0)), u),
				"roll_deg": lerpf(float(ha.get("roll_deg", 0.0)), float(hb.get("roll_deg", 0.0)), u),
				"offset": oa.interpolate_with(ob, u)}
			weapon.hold_influence = 1.0
			if rig == null:
				weapon.drive = "weapon"
		elif held_a and held_b:
			# Handed from one hand to another: the first hold lets go over the first half, the
			# second takes over during the second half, the free transform bridging between.
			var h: Dictionary = ha if u < 0.5 else hb
			weapon.drive = "hand"
			weapon.hold = h.duplicate()
			weapon.hold["offset"] = PoseFile.array_to_transform(h.get("offset"))
			weapon.hold_influence = absf(2.0 * u - 1.0)
		elif held_a or held_b:
			# Held in one pose only (a disarm, a hand-over to nobody): the hand's influence ramps.
			var h: Dictionary = ha if held_a else hb
			weapon.drive = "hand"
			weapon.hold = h.duplicate()
			weapon.hold["offset"] = PoseFile.array_to_transform(h.get("offset"))
			weapon.hold_influence = 1.0 - u if held_a else u
		else:
			weapon.drive = "weapon"
			weapon.hold = {}
			weapon.hold_influence = 1.0
			weapon.global_transform = weapon.free_transform


## How far a hand is on its grip at `u` between two poses (Grip.weight): 1 for a grip held in
## both, ramping out for one let go, in for one taken, out and back in for a hand that moves its
## grip to something else. Two figures who take hold of each other while letting go of each
## other (Uke's hand leaves Tori's wrist as Tori's takes Uke's) would each follow the other a frame
## late and shake; there the letting go is done in the first half and the taking in the second.
static func grip_weight(key: String, grips_a: Dictionary, grips_b: Dictionary, u: float) -> float:
	var ga: Dictionary = grips_a.get(key, {})
	var gb: Dictionary = grips_b.get(key, {})
	if not ga.is_empty() and not gb.is_empty():
		return 1.0 if _same_target(ga, gb) else absf(2.0 * u - 1.0)
	var g: Dictionary = ga if not ga.is_empty() else gb
	var cyclic := false
	var owner: String = g.get("target", {}).get("character", "")
	for other_key: String in _union(grips_a.keys(), grips_b.keys()):
		var o: Dictionary = grips_a.get(other_key, grips_b.get(other_key))
		if o.get("gripper") == owner and o.get("target", {}).get("character", "") == g.get("gripper"):
			cyclic = true
	if not ga.is_empty():
		return clampf(1.0 - 2.0 * u, 0.0, 1.0) if cyclic else 1.0 - u
	return clampf(2.0 * u - 1.0, 0.0, 1.0) if cyclic else u


## Keeps the director's grip list equal to the grips with any weight between the two poses. Grips
## in both keep pose a's target and blend their offsets; one-sided grips keep their own. A grip
## at no weight is left out, so it neither steers its hand nor orders the figures.
static func _apply_grips(scene: PosingScene, director: GripDirector, a: Dictionary, b: Dictionary, u_all: float,
		grips_a: Dictionary, grips_b: Dictionary, arm_u: Dictionary = {}) -> void:
	if director == null:
		return
	var wanted := {}
	for key in _union(grips_a.keys(), grips_b.keys()):
		var ga: Dictionary = grips_a.get(key, {})
		var gb: Dictionary = grips_b.get(key, {})
		var u: float = arm_u.get((ga if not ga.is_empty() else gb).get("gripper", ""), u_all)
		var weight := grip_weight(key, grips_a, grips_b, u)
		if weight <= 0.0:
			continue
		var src: Dictionary = ga if not ga.is_empty() else gb
		var d: Dictionary = src.duplicate(true)
		if not ga.is_empty() and not gb.is_empty() and _same_target(ga, gb):
			d["offset"] = PoseFile.array_to_transform(ga.get("offset")).interpolate_with(PoseFile.array_to_transform(gb.get("offset")), u)
		elif not ga.is_empty() and not gb.is_empty():
			d = (ga if u < 0.5 else gb).duplicate(true)
			d["offset"] = PoseFile.array_to_transform(d.get("offset"))
		else:
			d["offset"] = PoseFile.array_to_transform(d.get("offset"))
		d["weight"] = weight
		wanted[key] = d
	# Reuse existing grip objects where the key matches, so the director is not rebuilt per frame.
	var existing := {}
	for grip in director.grips:
		existing["%s/%s" % [grip.gripper_id, grip.hand]] = grip
	for key in existing:
		if not wanted.has(key):
			director._remove(existing[key])
	for key in wanted:
		var d: Dictionary = wanted[key]
		var grip: Grip = existing.get(key)
		if grip and grip.target.to_dict() == d["target"]:
			grip.offset = d["offset"]
		else:
			if grip:
				director._remove(grip)
			grip = Grip.from_dict(scene, d)
			director._add(grip)
		grip.weight = d["weight"]
		var rig: CharacterRig = scene.get_character(grip.gripper_id)
		if rig and rig.limbs.has(grip.limb_key()):
			grip.free = rig.limbs[grip.limb_key()].target.global_transform


static func _same_target(ga: Dictionary, gb: Dictionary) -> bool:
	return ga.get("target") == gb.get("target")


static func _grips_by_key(pose: Dictionary) -> Dictionary:
	var out := {}
	for g in pose.get("grips", []):
		out["%s/%s" % [g.get("gripper"), g.get("hand")]] = g
	return out


static func _by_id(list: Array) -> Dictionary:
	var out := {}
	for item in list:
		out[item.get("id")] = item
	return out


static func _union(x: Array, y: Array) -> Array:
	var out: Array = x.duplicate()
	for item in y:
		if not item in out:
			out.append(item)
	return out



## A saved root's orientation. Poses written before a figure could lean carry only a yaw.
static func root_euler(root: Dictionary) -> Vector3:
	return Vector3(float(root.get("pitch", 0.0)), float(root.get("yaw", 0.0)), float(root.get("roll", 0.0)))


## Points of the sole, in the rest pose (where the sole is on the mat at y = 0): heel, the outer
## and inner edge at the ball, and the tip of the big toe, x relative to the ankle.
const SOLE := [Vector3(0.0, 0.0, -0.02), Vector3(-0.035, 0.0, 0.13), Vector3(0.035, 0.0, 0.13), Vector3(0.0, 0.0, 0.2)]


## The lowest point of a foot's sole with its IK target (where the foot bone goes, and how it is
## turned) at `target`.
static func sole_lowest(rig: CharacterRig, side: String, target: Transform3D) -> float:
	var sk := rig.skeleton
	var rest := sk.get_bone_global_rest(sk.find_bone(side + "Foot"))
	var lowest := INF
	for p: Vector3 in SOLE:
		var local := rest.affine_inverse() * Vector3(rest.origin.x + p.x, p.y, p.z)
		lowest = minf(lowest, (target * local).y)
	return lowest


## `target` (an IK target in a saved pose) pulled in to what the limb can reach from where its
## root bone was in that pose (the pose's bone rotations `bones`, its root at `root_xf`): what
## the IK solver reaches for when the target is further away. Unchanged when it is in reach.
static func within_reach(rig: CharacterRig, limb: Limb, target: Transform3D, bones: Dictionary, root_xf: Transform3D) -> Transform3D:
	var sk := rig.skeleton
	var i := sk.find_bone(limb.root_bone)
	var sk_xf := root_xf * (rig.global_transform.affine_inverse() * sk.global_transform)
	var hip: Vector3 = sk_xf * _fk_global(sk, i, bones, {}).origin
	var d := target.origin - hip
	var reach := limb.chain_length()
	if d.length() > reach:
		target.origin = hip + d.normalized() * reach
	return target


# --- falls -----------------------------------------------------------------------------------

## A pose whose root is tipped this far (pitch or roll, radians) is a figure off its feet: a fall,
## a roll, lying down. A blend into or out of one is moved as a fall (_fall_root).
const FALL_TIP := deg_to_rad(30.0)
## A falling figure's free hand is kept at least this far above the mat, metres: it can rest on
## the mat but not reach through it.
const HAND_ABOVE_MAT := 0.03


static func is_fall(euler: Vector3) -> bool:
	return absf(wrapf(euler.x, -PI, PI)) > FALL_TIP or absf(wrapf(euler.z, -PI, PI)) > FALL_TIP


## The lean to blend toward, as the same orientation as `to` but counted on from `from`. A
## figure that has rolled 252 degrees and is then stood up (a lean of 0) finishes the roll at
## 360 rather than unrolling backwards through the floor. Only an orientation is re-counted: a
## lean already given as a count of turns (outside -180..180, as Ukemi writes a roll) is kept as
## it is, so a full roll written as 0 to 360 in one step still goes all the way round.
static func continue_turn(from: float, to: float) -> float:
	if absf(to) > PI + 1e-4:
		return to
	return from + wrapf(to - from, -PI, PI)


## Where a falling figure's root goes at `u`. A body rolling on a mat turns about its middle and
## rests on whatever part of it is lowest; its root is at its feet, so blending the root's
## position while the lean turns swings the whole body about the feet — through the floor, in
## the middle of a roll, by more than a metre. So the hips are what travel (on the same curve
## through the neighbouring steps that a root would follow), the body is turned about them, and
## then the root is lifted or dropped so the body's lowest part keeps the clearance it has in the
## two poses — on the mat, for a fall that was grounded in both. The clearance is measured from
## the pose alone (no solve, see _fk_lowest) the same way at both ends and in between, so the
## correction is exactly what the in-between adds and a keyframe is reached exactly.
static func _fall_root(rig: CharacterRig, ca: Dictionary, cb: Dictionary, lean_a: Vector3, lean_b: Vector3,
		pos: Array, lean_nb: Array, u: float) -> void:
	var hips := _hips_local(rig)
	var basis_u := Basis.from_euler(rig.rotation)
	var h0: Vector3 = pos[0] + Basis.from_euler(lean_nb[0]) * hips
	var h1: Vector3 = pos[1] + Basis.from_euler(lean_a) * hips
	var h2: Vector3 = pos[2] + Basis.from_euler(lean_b) * hips
	var h3: Vector3 = pos[3] + Basis.from_euler(lean_nb[1]) * hips
	var root := h1.cubic_interpolate(h2, h0, h3, u) - basis_u * hips
	var low_a := _fk_lowest(rig, ca.get("bones", {}), Transform3D(Basis.from_euler(lean_a), pos[1]))
	var low_b := _fk_lowest(rig, cb.get("bones", {}), Transform3D(Basis.from_euler(lean_b), pos[2]))
	var low_u := _fk_lowest(rig, {}, Transform3D(basis_u, root))
	root.y += lerpf(low_a, low_b, u) - low_u
	rig.position = root


## The hips in the root's frame. Nothing poses the hips' position, so this is the rest.
static func _hips_local(rig: CharacterRig) -> Vector3:
	var sk := rig.skeleton
	var i := sk.find_bone("Hips")
	var sk_in_root := rig.global_transform.affine_inverse() * sk.global_transform
	return sk_in_root * sk.get_bone_global_rest(i).origin


## The height of the lowest point of the trunk, head and legs (capsule surfaces, as Anatomy
## measures them) for the bone rotations `rotations` (PoseFile arrays; empty: the skeleton's
## current pose) with the root at `root_xf`. The arms are left out: they are IK, so where they
## are depends on a solve, and a falling figure's free hand is kept off the mat on its own.
static func _fk_lowest(rig: CharacterRig, rotations: Dictionary, root_xf: Transform3D) -> float:
	var sk := rig.skeleton
	var sk_xf := root_xf * (rig.global_transform.affine_inverse() * sk.global_transform)
	var glob := {}
	var lowest := INF
	for name: String in Anatomy.RADII:
		if name in Anatomy.ARM_BONES:
			continue
		var i := sk.find_bone(name)
		if i < 0:
			continue
		var here := _fk_global(sk, i, rotations, glob)
		var a: Vector3 = sk_xf * here.origin
		var b: Vector3
		var children := sk.get_bone_children(i)
		if children.size() > 0:
			b = Vector3.ZERO
			for c in children:
				b += sk_xf * _fk_global(sk, c, rotations, glob).origin
			b /= children.size()
		else:
			b = a + (sk_xf.basis * here.basis).y * 0.08
		lowest = minf(lowest, minf(a.y, b.y) - Anatomy.RADII[name])
	return lowest


static func _fk_global(sk: Skeleton3D, i: int, rotations: Dictionary, memo: Dictionary) -> Transform3D:
	if memo.has(i):
		return memo[i]
	var q: Quaternion
	var name := sk.get_bone_name(i)
	if rotations.is_empty():
		q = sk.get_bone_pose_rotation(i)
	elif rotations.has(name):
		q = PoseFile.array_to_quat(rotations[name])
	else:
		q = sk.get_bone_rest(i).basis.get_rotation_quaternion()
	var local := Transform3D(Basis(q), sk.get_bone_pose_position(i))
	var parent := sk.get_bone_parent(i)
	var g := local if parent < 0 else _fk_global(sk, parent, rotations, memo) * local
	memo[i] = g
	return g
