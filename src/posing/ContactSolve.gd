class_name ContactSolve
extends RefCounted
## Two bodies kept out of each other between two poses, solved together every frame.
##
## The blend says where each figure's hips, hands and feet go and which way its elbows and
## knees point; nothing in it knows the other body. Two people doing a technique are in contact
## the whole time, and when Tori turns with Uke's hand on his wrist, Uke's arm is carried round
## with him rather than left for Tori's chest to pass through. This solves for that, the way a
## position-based physics step does: every figure as points — its hips (the whole trunk moves
## with them, rigid), and each limb's elbow or knee and hand or foot — held by constraints that
## are satisfied a few at a time, over and over:
##   - a limb's two bones keep their lengths;
##   - a hand or foot stays where the blend puts it, softly, and a foot that stands on the mat
##     firmly; a gripping hand stays on its place on the bone it grips, wherever that has gone;
##   - every capsule (trunk, upper arm, forearm, hand, thigh, shin, foot) keeps out of every
##     capsule of the other figure, and out of its own body's parts it does not join by design;
##   - everything is drawn back toward where the blend had it, the hips hardest, so the solve
##     changes only what contact asks it to.
## The answer goes back to the IK as it understands it: the hips moved, hands and feet as
## targets, elbows and knees as poles. The joint handling (TwistFollow, HandOrient, JointLimits)
## still finishes each limb. `strength` (0..1) fades the whole thing in and out with the move,
## so a keyframe is shown exactly as saved.

const ITERATIONS := 20
## How much overlap is left alone, metres: a little under what the checks allow.
const ALLOW_PARTNER := 0.02
const ALLOW_OWN_TRUNK := 0.05
const ALLOW_OWN := 0.02
## Stiffness of the pull back toward the blend, per iteration (0..1).
const PRIOR_HIPS := 0.1
const PRIOR_JOINT := 0.04
const PRIOR_END := 0.15
const PRIOR_FOOT_DOWN := 0.9
## A gripping hand is held by its grip (below), hardly by where it started.
const PRIOR_GRIPPING := 0.05
## Inverse masses: the hips move least, a planted foot hardly at all.
const W_HIPS := 0.15
const W_JOINT := 1.0
const W_END := 0.6
const W_FOOT_DOWN := 0.02
## A foot whose target is below this, metres, and is not stepping, stands on the mat.
const FOOT_DOWN := 0.2
## Less than this moved by the solve, metres, and a limb is left as the blend set it.
const MOVED := 0.015
## How far out past the solved elbow or knee its pole is put, metres.
const POLE_OUT := 0.3
## Radii of the limb segments (Anatomy.RADII).
const LIMB_BONES := {"Arm": ["UpperArm", "LowerArm", "Hand"], "Leg": ["UpperLeg", "LowerLeg", "Foot"]}


## Solves the scene as PoseBlend has just set it. `strength` per part as clearance_strength.
static func solve(scene: PosingScene, director: GripDirector, strength: Dictionary) -> void:
	var k := maxf(float(strength.get("root", 0.0)), maxf(float(strength.get("arms", 0.0)), float(strength.get("legs", 0.0))))
	if k <= 0.0:
		return
	var figures := []
	for rig in scene.characters:
		if rig.visible and not rig.keep_on_mat:
			var f := _figure(rig, director)
			if not f.is_empty():
				figures.append(f)
	if figures.is_empty():
		return
	var grips := _grip_links(figures, director)
	for _it in ITERATIONS:
		for f: Dictionary in figures:
			_lengths(f)
			_priors(f)
		for g: Dictionary in grips:
			_grip(g)
		for i in figures.size():
			_self_contact(figures[i])
			for j in range(i + 1, figures.size()):
				_contact(figures[i], figures[j])
	for f: Dictionary in figures:
		_write(f, k)


# --- the figure as points --------------------------------------------------------------------

## {rig, hips: point, hips0, trunk: [[name, a_local, b_local, r]] relative to the hips, limbs:
## {key: {root_local, mid, end, mid0, end0, l1, l2, arm, down, bones}}}. A point is a Dictionary
## {p: Vector3, w: inverse mass} so constraints can move it in place.
static func _figure(rig: CharacterRig, director: GripDirector) -> Dictionary:
	var hips := rig.fk_bone_transform("Hips").origin
	var segs := Anatomy.segments(rig, true)
	var trunk := []
	for name: String in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "RightShoulder", "LeftShoulder"]:
		if segs.has(name):
			trunk.append([name, segs[name][0] - hips, segs[name][1] - hips, segs[name][2]])
	var limbs := {}
	for key: String in rig.limbs:
		var limb: Limb = rig.limbs[key]
		var root := rig.fk_bone_transform(limb.root_bone).origin
		var l1 := rig.skeleton.get_bone_pose_position(rig.skeleton.find_bone(limb.middle_bone)).length()
		var l2 := rig.skeleton.get_bone_pose_position(rig.skeleton.find_bone(limb.end_bone)).length()
		var end: Vector3 = limb.target.global_position if limb.mode == Limb.Mode.IK else rig.fk_bone_transform(limb.end_bone).origin
		var mid := _ik_middle(root, end, limb.pole.global_position, l1, l2) if limb.mode == Limb.Mode.IK \
			else rig.fk_bone_transform(limb.middle_bone).origin
		var down := not limb.is_arm and limb.mode == Limb.Mode.IK and end.y < FOOT_DOWN and not limb.stepping
		var grip: Grip = director.grip_on_limb(rig.character_id, key) if director else null
		var gripping := grip != null
		if gripping:
			# Where the grip has the hand (the gripped bone as last solved), as weighted this frame.
			end = grip.free.interpolate_with(director.resolved_hand_transform(grip), clampf(grip.weight, 0.0, 1.0)).origin
			mid = _ik_middle(root, end, limb.pole.global_position, l1, l2)
		limbs[key] = {"limb": limb, "root_local": root - hips, "l1": l1, "l2": l2, "arm": limb.is_arm,
			"mid": {"p": mid, "w": W_JOINT}, "end": {"p": end, "w": W_FOOT_DOWN if down else W_END},
			"mid0": mid, "end0": end, "down": down, "gripping": gripping, "ik": limb.mode == Limb.Mode.IK,
			"names": [limb.root_bone, limb.middle_bone, limb.end_bone]}
	return {"rig": rig, "hips": {"p": hips, "w": W_HIPS}, "hips0": hips, "trunk": trunk, "limbs": limbs,
		"parents": Anatomy.parents_of(rig)}


## Where a two-bone IK puts the middle joint for root, end and pole.
static func _ik_middle(root: Vector3, end: Vector3, pole: Vector3, l1: float, l2: float) -> Vector3:
	var line := end - root
	var d := clampf(line.length(), absf(l1 - l2) + 1e-3, (l1 + l2) * 0.999)
	var n := line.normalized() if line.length() > 1e-5 else Vector3.DOWN
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var r := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var c := root + n * a
	var ref := pole - c
	ref -= n * ref.dot(n)
	if ref.length() < 1e-5:
		ref = n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT)
	return c + ref.normalized() * r


static func _root(f: Dictionary, lb: Dictionary) -> Vector3:
	return (f["hips"]["p"] as Vector3) + (lb["root_local"] as Vector3)


# --- constraints -----------------------------------------------------------------------------

## A limb's bones keep their lengths: root–middle (the root moves with the hips) and middle–end.
static func _lengths(f: Dictionary) -> void:
	for key: String in f["limbs"]:
		var lb: Dictionary = f["limbs"][key]
		_distance_to_fixed(lb["mid"], _root(f, lb), lb["l1"])
		_distance(lb["mid"], lb["end"], lb["l2"])


static func _distance(a: Dictionary, b: Dictionary, length: float) -> void:
	var d: Vector3 = b["p"] - a["p"]
	var l := d.length()
	var w := float(a["w"]) + float(b["w"])
	if l < 1e-6 or w <= 0.0:
		return
	var c := (l - length) / l / w
	a["p"] += d * c * float(a["w"])
	b["p"] -= d * c * float(b["w"])


static func _distance_to_fixed(a: Dictionary, fixed: Vector3, length: float) -> void:
	var d: Vector3 = a["p"] - fixed
	if d.length() < 1e-6:
		return
	a["p"] = fixed + d.normalized() * length


## Drawn back toward the blend.
static func _priors(f: Dictionary) -> void:
	f["hips"]["p"] = (f["hips"]["p"] as Vector3).lerp(f["hips0"], PRIOR_HIPS)
	for key: String in f["limbs"]:
		var lb: Dictionary = f["limbs"][key]
		lb["mid"]["p"] = (lb["mid"]["p"] as Vector3).lerp(lb["mid0"], PRIOR_JOINT)
		var pull := PRIOR_FOOT_DOWN if lb["down"] else (PRIOR_GRIPPING if lb["gripping"] else PRIOR_END)
		lb["end"]["p"] = (lb["end"]["p"] as Vector3).lerp(lb["end0"], pull)


## Each grip as {hand: point, figure, limb key, target figure, bone, at}: the hand is kept on
## the gripped segment at the fraction along it where it is now.
static func _grip_links(figures: Array, director: GripDirector) -> Array:
	var out := []
	if director == null:
		return out
	var by_id := {}
	for f: Dictionary in figures:
		by_id[(f["rig"] as CharacterRig).character_id] = f
	for g in director.grips:
		if g.target.kind != GripTarget.Kind.BONE or g.weight < 0.5:
			continue
		var gf: Dictionary = by_id.get(g.gripper_id, {})
		var tf: Dictionary = by_id.get(g.target.character_id, {})
		if gf.is_empty() or tf.is_empty():
			continue
		var hand: Dictionary = gf["limbs"].get(g.limb_key(), {})
		if hand.is_empty():
			continue
		var seg := _segment_points(tf, g.target.bone_name)
		if seg.is_empty():
			continue
		var a: Vector3 = seg[0]["p"]; var b: Vector3 = seg[1]["p"]
		var p: Vector3 = hand["end"]["p"]
		var t := clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 1e-9), 0.0, 1.0)
		var off := p - a.lerp(b, t)
		out.append({"hand": hand["end"], "seg": seg, "t": t, "off": off})
	return out


## A bone of a figure as two points (moving with the solve), or [] when it is not one the solve
## moves as a limb (a trunk bone moves with the hips: given as points fixed to them).
static func _segment_points(f: Dictionary, bone: String) -> Array:
	for key: String in f["limbs"]:
		var lb: Dictionary = f["limbs"][key]
		var names: Array = lb["names"]
		if bone == names[0]:
			return [{"p": _root(f, lb), "w": 0.0, "hips": f["hips"], "local": lb["root_local"]}, lb["mid"]]
		if bone == names[1]:
			return [lb["mid"], lb["end"]]
	return []


static func _grip(g: Dictionary) -> void:
	var seg: Array = g["seg"]
	if seg[0].has("hips"):
		seg[0]["p"] = (seg[0]["hips"]["p"] as Vector3) + (seg[0]["local"] as Vector3)
	var on := (seg[0]["p"] as Vector3).lerp(seg[1]["p"], g["t"]) + (g["off"] as Vector3)
	var hand: Dictionary = g["hand"]
	var d: Vector3 = on - hand["p"]
	# The hand and the held segment meet half way, by their masses.
	var t := float(g["t"])
	var wh := float(hand["w"])
	var ws := float(seg[0]["w"]) * (1.0 - t) + float(seg[1]["w"]) * t
	if wh + ws <= 0.0:
		return
	hand["p"] += d * (wh / (wh + ws))
	var back := d * (ws / (wh + ws))
	if not seg[0].has("hips"):
		seg[0]["p"] -= back * (1.0 - t)
	seg[1]["p"] -= back * t


## Every capsule of a figure as [end a (point or fixed), end b, radius, name], for contact.
static func _capsules(f: Dictionary) -> Array:
	var out := []
	var hips: Dictionary = f["hips"]
	for t: Array in f["trunk"]:
		out.append([{"hips": hips, "local": t[1]}, {"hips": hips, "local": t[2]}, t[3], t[0]])
	for key: String in f["limbs"]:
		var lb: Dictionary = f["limbs"][key]
		var names: Array = lb["names"]
		out.append([{"hips": hips, "local": lb["root_local"]}, lb["mid"], Anatomy.RADII.get(names[0], 0.05), names[0]])
		out.append([lb["mid"], lb["end"], Anatomy.RADII.get(names[1], 0.04), names[1]])
		# The hand or foot as a short stub on past the end, along the forearm or shin.
		out.append([lb["end"], {"stub": lb["end"], "from": lb["mid"], "len": 0.08 if lb["arm"] else 0.12},
			Anatomy.RADII.get(names[2], 0.03), names[2]])
	return out


static func _pos(e: Dictionary) -> Vector3:
	if e.has("hips"):
		return (e["hips"]["p"] as Vector3) + (e["local"] as Vector3)
	if e.has("stub"):
		var s: Vector3 = e["stub"]["p"]
		return s + (s - (e["from"]["p"] as Vector3)).normalized() * float(e["len"])
	return e["p"]


## Moves one end of a capsule by `d` (a fixed-to-hips end moves the hips, by their mass).
static func _move(e: Dictionary, d: Vector3, share: float) -> void:
	if e.has("hips"):
		e["hips"]["p"] += d * share * float(e["hips"]["w"])
	elif e.has("stub"):
		e["stub"]["p"] += d * share * float(e["stub"]["w"])
	else:
		e["p"] += d * share * float(e["w"])


static func _push_apart(c1: Array, c2: Array, allow: float) -> void:
	var a1 := _pos(c1[0]); var b1 := _pos(c1[1])
	var a2 := _pos(c2[0]); var b2 := _pos(c2[1])
	var pts := Anatomy._closest_points(a1, b1, a2, b2)
	var diff: Vector3 = pts[0] - pts[1]
	var dist := diff.length()
	var depth: float = float(c1[2]) + float(c2[2]) - dist - allow
	if depth <= 0.0:
		return
	var n := diff / dist if dist > 1e-6 else Vector3.UP
	var s1 := _along(a1, b1, pts[0])
	var s2 := _along(a2, b2, pts[1])
	var push := n * depth * 0.5
	_move(c1[0], push, 1.0 - s1); _move(c1[1], push, s1)
	_move(c2[0], -push, 1.0 - s2); _move(c2[1], -push, s2)


static func _along(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	return clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)


## Two figures: every capsule of one out of every capsule of the other, bar a gripping hand and
## forearm on the bone they hold and its neighbours.
static func _contact(f1: Dictionary, f2: Dictionary) -> void:
	var c1 := _capsules(f1)
	var c2 := _capsules(f2)
	for x: Array in c1:
		for y: Array in c2:
			if _held(f1, x[3], f2, y[3]) or _held(f2, y[3], f1, x[3]):
				continue
			_push_apart(x, y, ALLOW_PARTNER)


## A figure's own limbs out of its own body where they are not joined by design.
static func _self_contact(f: Dictionary) -> void:
	var caps := _capsules(f)
	var trunk_names := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "RightShoulder", "LeftShoulder"]
	for i in caps.size():
		for j in range(i + 1, caps.size()):
			var a: String = caps[i][3]; var b: String = caps[j][3]
			if a in trunk_names and b in trunk_names:
				continue
			if Anatomy.touching_by_design(a, b, f["parents"]):
				continue
			var allow := ALLOW_OWN_TRUNK if (a in trunk_names or b in trunk_names) else ALLOW_OWN
			_push_apart(caps[i], caps[j], allow)


## Whether `bone` of `f1` is a gripping hand (or its forearm) on `other` of `f2` or next to it.
static func _held(f1: Dictionary, bone: String, f2: Dictionary, other: String) -> bool:
	var rig: CharacterRig = f1["rig"]
	if not (bone.ends_with("Hand") or bone.ends_with("LowerArm")):
		return false
	var side := "Right" if bone.begins_with("Right") else "Left"
	var lb: Dictionary = f1["limbs"].get(side + "Arm", {})
	if lb.is_empty() or not lb["gripping"]:
		return false
	var grip: Grip = null
	var scene := rig.get_parent() as PosingScene
	for n in scene.get_parent().get_children() if scene and scene.get_parent() else []:
		if n is GripDirector:
			grip = n.grip_on_limb(rig.character_id, side + "Arm")
	if grip == null or grip.target.kind != GripTarget.Kind.BONE or grip.target.character_id != (f2["rig"] as CharacterRig).character_id:
		return false
	var held := grip.target.bone_name
	var parents: Dictionary = f2["parents"]
	return other == held or parents.get(other, "") == held or parents.get(held, "") == other


# --- the answer, back to the IK ---------------------------------------------------------------

static func _write(f: Dictionary, k: float) -> void:
	var rig: CharacterRig = f["rig"]
	var moved: Vector3 = (f["hips"]["p"] as Vector3) - (f["hips0"] as Vector3)
	rig.position += moved * k
	for key: String in f["limbs"]:
		var lb: Dictionary = f["limbs"][key]
		var limb: Limb = lb["limb"]
		if not lb["ik"]:
			continue
		var mid: Vector3 = (lb["mid0"] as Vector3).lerp(lb["mid"]["p"], k)
		var end: Vector3 = (lb["end0"] as Vector3).lerp(lb["end"]["p"], k)
		# A limb contact did not move is left as the blend set it: re-aiming an elbow nothing
		# pushed only hands the wrist a different problem.
		var pushed: float = maxf((mid - (lb["mid0"] as Vector3) - moved * k).length(), (end - (lb["end0"] as Vector3)).length())
		if pushed < MOVED:
			continue
		if not lb["gripping"]:
			limb.target.global_position = end
		var root := (f["hips0"] as Vector3) + moved * k + (lb["root_local"] as Vector3)
		var line := end - root
		var off := mid - (root + line.normalized() * (mid - root).dot(line.normalized())) if line.length() > 1e-5 else Vector3.ZERO
		if off.length() > 0.005:
			limb.pole.global_position = mid + off.normalized() * POLE_OUT
