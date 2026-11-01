class_name Attacks
extends RefCounted
## The attacks a technique starts from — katatedori, ryotedori, shomenuchi, ushiro
## kubishime… — as things the tool can set up, from one catalogue (data/attacks.json):
## what each is called in the schools that call it something else, who stands where, which
## hand takes what and from which side. `stage()` builds one: Tori in hanmi offering what the
## attack takes, Uke in hanmi where the attack has him, hands raised or wrapped round their
## targets, and then — because the joints now know what a wrist can do — Uke moved to where
## his arms can actually make the grip, which is closer than a script would have put him.
##
## The catalogue is data so the instructor can correct a name or a distance without touching
## code; docs/attacks.md is the same catalogue as a page.

const PATH := "res://data/attacks.json"
static var _catalogue: Dictionary = {}

## The fit search: Uke is tried at these offsets from his nominal place, toward or away from
## Tori (metres along the line between them) and sideways, and stays where his gripping arms
## have the least to refuse. Wide enough for a wrist that needs the elbow out, small enough
## that a katadori stays a katadori.
const FIT_STEPS_IN := [0.0, -0.05, -0.10, -0.15, -0.20, 0.05, 0.10]
const FIT_STEPS_SIDE := [0.0, -0.06, 0.06, -0.12, 0.12, -0.18, 0.18]
## A grip short of its point costs this much per metre against degrees of refused joint.
const FIT_ERROR_PER_M := 2000.0
## Moving Uke away from where the catalogue put him costs this much per metre.
const FIT_MOVE_PER_M := 10.0
## Any refused joint at all costs this much on top of its degrees: a place with none wins.
const FIT_REFUSAL := 6.0
## The two bodies passing through each other costs this much per metre of overlap.
const FIT_BODY_PER_M := 3000.0
## Uke standing closer than the attack's "min_gap" costs this much per metre.
const FIT_GAP_PER_M := 400.0


static func catalogue() -> Dictionary:
	if _catalogue.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary and parsed.has("attacks"):
				_catalogue = parsed["attacks"]
	return _catalogue


static func keys() -> Array:
	return catalogue().keys()


static func entry(key: String) -> Dictionary:
	return catalogue().get(key, {})


static func names(key: String) -> Dictionary:
	return entry(key).get("names", {})


## The attack in a line, for the panel: "Katatedori — single wrist grab, mirror stance".
static func summary(key: String) -> String:
	var n := names(key)
	return "%s — %s" % [n.get("short", key), n.get("english", "")]


## Sets the attack up on `tori_id` and `uke_id` (both must exist) and returns what came of it:
##   {"refused": [what Uke's gripping arms still could not do], "grip_error": worst metres,
##    "uke_offset": how far Uke was moved from the catalogue's place, "uke_position": Vector3}
## Options: "mirror" swaps every left and right (the attack on the other side); "fit" (default
## true) lets the joints decide where Uke stands; "fk" leaves Tori's unused arms alone.
##
## The pose is the moment of the attack: the grip taken, the cut or the punch arriving. How Uke
## gets there — kamae at ma-ai, the step, the hand raised — is `lead_in`.
static func stage(st: Staging, key: String, opts: Dictionary = {}) -> Dictionary:
	var e := entry(key)
	assert(not e.is_empty(), "unknown attack %s" % key)
	var mirror: bool = opts.get("mirror", false)
	var tori_id: String = opts.get("tori", "tori")
	var uke_id: String = opts.get("uke", "uke1")
	var tori := st.rig(tori_id)
	var uke := st.rig(uke_id)
	assert(tori and uke, "stage() needs both characters in the scene")
	# Everyone lets go and stands up straight before the attack is set.
	await st.release_all(uke_id)
	await st.release_all(tori_id)
	await st.rest_limbs(tori_id)
	await st.rest_limbs(uke_id)
	# Tori at the origin facing +z; Uke where the attack has him.
	var u: Dictionary = e["uke"]
	var t: Dictionary = e["tori"]
	var behind: bool = u.get("facing", "tori") == "same"
	var lateral: float = float(u.get("lateral", 0.0)) * (-1.0 if mirror else 1.0)
	var distance: float = float(u.get("distance", 0.6))
	st.stance(tori_id, 0.0, 0.0, 0.0)
	if behind:
		st.stance(uke_id, lateral, -distance, 0.0)
	else:
		st.stance(uke_id, lateral, distance, 180.0 + float(u.get("turn", 0.0)) * (-1.0 if mirror else 1.0))
	await st.settle()
	await _hanmi(st, tori_id, t, mirror)
	await _hanmi(st, uke_id, u, mirror)
	# Hands the attack places are placed; the others hang at the side (the rest pose reaches
	# forward, which at grip distance is into the partner).
	var uke_hands := {}
	for g in e.get("grips", []):
		uke_hands[_side(g["hand"], mirror)] = true
	if e.has("strike"):
		uke_hands[_side(e["strike"]["hand"], mirror)] = true
	# "hands": "kamae" holds both of a figure's hands in kamae, leading with its front foot's.
	var tori_hands = t.get("hands", {})
	var uke_kamae: bool = u.get("hands", {}) is String and u.get("hands") == "kamae"
	if tori_hands is String:
		await st.kamae_hands(tori_id, _side(t.get("hanmi", "Right"), mirror))
	if uke_kamae:
		await st.kamae_hands(uke_id, _side(u.get("hanmi", "Left"), mirror))
	for side in ["Right", "Left"]:
		var tori_side := _side(side, mirror)
		if tori_hands is String:
			pass
		elif tori_hands.has(side):
			await _place_hand(st, tori_id, tori_side, tori_hands[side], tori, mirror)
		else:
			await st.hang_arm(tori_id, tori_side)
		var uke_side := _side(side, mirror)
		if uke_kamae:
			pass
		elif u.get("hands", {}).has(side):
			await _place_hand(st, uke_id, uke_side, u["hands"][side], tori, mirror)
		elif not uke_hands.has(uke_side):
			await st.hang_arm(uke_id, uke_side)
	for side in u.get("curls", {}):
		st.fingers(uke_id, _side(side, mirror), float(u["curls"][side]))
	for side in t.get("curls", {}):
		st.fingers(tori_id, _side(side, mirror), float(t["curls"][side]))
	for side in u.get("feet", {}):
		await st.foot_at(uke_id, _side(side, mirror), _vec(u["feet"][side], mirror))
	for w in u.get("weapons", []):
		await st.hold(uke_id, _side(w["hand"], mirror), w["type"], float(w.get("t", -1.0)))
	await st.settle(3)
	if e.has("strike"):
		await _strike(st, e["strike"], tori, uke, mirror)
	var grips: Array = []
	for g in e.get("grips", []):
		grips.append(await _take(st, g, tori_id, uke_id, tori, mirror))
	var nominal: Vector3 = uke.position
	if not grips.is_empty() and opts.get("fit", true):
		# Twice: the way a hand wraps its target is chosen from where Uke stands, and where Uke
		# stands is chosen from how the hands wrap. Once round each is enough in practice.
		await _fit(st, tori, uke, grips, e)
		grips = await _regrab(st, e, tori_id, uke_id, tori, mirror)
		await _fit(st, tori, uke, grips, e)
	await st.feet_on_floor()
	await st.settle(3)
	return {
		"refused": _arm_refusals(uke, grips),
		"grip_error": _worst_error(st, grips),
		"uke_offset": uke.position.distance_to(nominal),
		"uke_position": uke.position,
	}


## A figure's stance from its catalogue block: hanmi with the block's "hanmi" (front foot),
## "depth", "width" and "drop", then the hips "weight" of the way onto the front foot (0.5 is
## between the feet) and the trunk leaned "lean" degrees forward (the spine bent; the feet stay).
static func _hanmi(st: Staging, id: String, b: Dictionary, mirror: bool) -> void:
	var depth: float = float(b.get("depth", 0.32))
	await st.hanmi(id, _side(b.get("hanmi", "Right"), mirror), depth, float(b.get("width", 0.16)), float(b.get("drop", 0.06)))
	var r := st.rig(id)
	var w: float = float(b.get("weight", 0.5))
	if absf(w - 0.5) > 1e-3:
		var fwd: Vector3 = r.global_transform.basis.z
		fwd.y = 0.0
		st.ctrl.set_root(r, r.position + fwd.normalized() * (w - 0.5) * depth, r.rotation.y, r.rotation.x, r.rotation.z, Stance.BOTH_LEGS)
		await st.settle(2)
	if b.has("lean"):
		st.lean_trunk(id, float(b["lean"]))
		await st.settle(2)


## A hand from the catalogue: an offset from its own shoulder (an array, [left, up, forward] in
## the figure's frame like every catalogue position), or a block with "at" (that offset) or "to"
## (a bone of Tori, "along" it, "offset" in Tori's frame), and optionally "point" and "palm"
## (directions in the figure's frame) and "curl". "kamae" holds both hands in kamae, "hang" lets
## this one hang.
static func _place_hand(st: Staging, id: String, side: String, h, tori: CharacterRig, mirror: bool) -> void:
	var r := st.rig(id)
	if h is String:
		if h == "hang":
			await st.hang_arm(id, side)
		elif h == "kamae":
			await st.kamae_hands(id, side)
		return
	if h is Array:
		await st.hand_at(id, side, _vec(h, mirror))
		return
	var d: Dictionary = h
	var basis := _flat(r)
	var goal: Vector3
	if d.has("to"):
		goal = _on_bone(tori, _side(d["to"], mirror), float(d.get("along", 0.0))) + _flat(tori) * _vec(d.get("offset", [0, 0, 0]), mirror)
	else:
		goal = r.bone_world_transform(side + "UpperArm").origin + basis * _vec(d.get("at", [0, -0.5, 0.1]), mirror)
	if d.has("point") or d.has("palm"):
		var point: Vector3 = basis * _vec(d["point"], mirror) if d.has("point") else Vector3.ZERO
		var palm: Vector3 = basis * _vec(d["palm"], mirror) if d.has("palm") else Vector3.ZERO
		await st.hand_to(id, side, goal, point, palm, float(d.get("curl", -1.0)))
	else:
		var off: Vector3 = goal - r.bone_world_transform(side + "UpperArm").origin
		await st.hand_at(id, side, basis.inverse() * off)
		if d.has("curl"):
			st.fingers(id, side, float(d["curl"]))
	await _elbow(st, r, side, d, mirror)


## "elbow": where the elbow points, [left, up, forward] from the shoulder in the figure's frame
## (the IK pole): arms that go round a body — a bear hug, a choke from behind — reach the front
## of it with the elbows out, not straight through it.
static func _elbow(st: Staging, r: CharacterRig, side: String, d: Dictionary, mirror: bool) -> void:
	if not d.has("elbow"):
		return
	var shoulder: Vector3 = r.bone_world_transform(side + "UpperArm").origin
	r.limbs[side + "Arm"].pole.global_position = shoulder + _flat(r) * _vec(d["elbow"], mirror).normalized() * 0.5
	await st.settle(2)


## A strike arriving: Uke is moved along the line to Tori until his striking arm reaches the
## target ("to", a bone of Tori, "along" it, "offset" in Tori's frame) at "reach" of its full
## length (1 straight, 0.9 the elbow easy), then the hand is put there turned as "point" and
## "palm" say, "curl" closed. A cut that stops short of the forehead and a punch at a body it
## cannot reach both read as a picture of someone not attacking.
static func _strike(st: Staging, s: Dictionary, tori: CharacterRig, uke: CharacterRig, mirror: bool) -> void:
	var side := _side(s["hand"], mirror)
	var bone := _side(s.get("to", "Head"), mirror)
	var reach: float = float(s.get("reach", 0.92))
	var arm: float = uke.bone_world_transform(side + "UpperArm").origin.distance_to(uke.bone_world_transform(side + "LowerArm").origin) \
		+ uke.bone_world_transform(side + "LowerArm").origin.distance_to(uke.bone_world_transform(side + "Hand").origin)
	for pass_ in 4:
		var goal: Vector3 = _on_bone(tori, bone, float(s.get("along", 0.0))) + _flat(tori) * _vec(s.get("offset", [0, 0, 0]), mirror)
		var point: Vector3 = _flat(uke) * _vec(s.get("point", [0, 0, 1]), mirror)
		var wrist: Vector3 = goal - point.normalized() * Staging.KNUCKLE_FROM_WRIST
		var shoulder: Vector3 = uke.bone_world_transform(side + "UpperArm").origin
		var span: Vector3 = wrist - shoulder
		var flat := Vector3(span.x, 0.0, span.z)
		var want_flat := sqrt(maxf(0.0, pow(arm * reach, 2.0) - span.y * span.y))
		if flat.length() < 1e-3 or absf(flat.length() - want_flat) < 0.005:
			break
		st.ctrl.set_root(uke, uke.position + flat.normalized() * (flat.length() - want_flat), uke.rotation.y, uke.rotation.x, uke.rotation.z)
		await st.settle(3)
	var d := s.duplicate()
	d["to"] = s.get("to", "Head")
	await _place_hand(st, uke.character_id, side, d, tori, mirror)


## Takes one grip of the catalogue: a hand wrapped round a bone, or with "cloth" a fist in the
## gi over it (knuckles "along" the bone plus "offset" in Tori's frame, turned as "point" and
## "palm" say in Uke's frame).
static func _take(st: Staging, g: Dictionary, tori_id: String, uke_id: String, tori: CharacterRig, mirror: bool) -> Grip:
	var hand := _side(g["hand"], mirror)
	var bone := _side(g["bone"], mirror)
	if g.get("cloth", false):
		var uke := st.rig(uke_id)
		var at: Vector3 = _on_bone(tori, bone, float(g.get("along", 0.0))) + _flat(tori) * _vec(g.get("offset", [0, 0, 0]), mirror)
		var point: Vector3 = _flat(uke) * _vec(g.get("point", [0, 0, 1]), mirror)
		var palm: Vector3 = _flat(uke) * _vec(g.get("palm", [0, -1, 0]), mirror)
		var grip: Grip = await st.grab_cloth(uke_id, hand, tori_id, bone, at, point, palm, float(g.get("curl", 0.85)))
		await _elbow(st, uke, hand, g, mirror)
		return grip
	var approach := Vector3.ZERO
	if g.has("approach"):
		approach = tori.global_transform.basis * _vec(g["approach"], mirror)
	return await st.grab(uke_id, hand, tori_id, bone, approach, float(g.get("along", 0.0)), float(g.get("curl", 0.6)), _skews(g, mirror))


## A point `along` a bone of `r`, from its joint (0) to its child's (1).
static func _on_bone(r: CharacterRig, bone: String, along: float) -> Vector3:
	var a: Vector3 = r.bone_world_transform(bone).origin
	var kids := r.skeleton.get_bone_children(r.skeleton.find_bone(bone))
	if along > 0.0 and kids.size() > 0:
		return a.lerp(r.bone_world_transform(r.skeleton.get_bone_name(kids[0])).origin, along)
	return a


## A figure's frame turned only about the vertical.
static func _flat(r: CharacterRig) -> Basis:
	var x := r.global_transform.basis.x
	return Basis(Vector3.UP, atan2(-x.z, x.x))


# ---------------------------------------------------------------- getting there

## How long a walking step takes, and how far apart the feet land, metres along the way (a
## stride in hanmi is shorter than a walk's; an attacker coming in is not strolling).
const WALK_TRANSITION := 0.5
const WALK_STRIDE := 0.6
## The hips over the leading foot while walking in.
const WALK_WEIGHT := 0.58

## The stages before the attack itself, as poses to save, in order: Uke from kamae at ma-ai
## through the step and the hand raised or reaching to just before the moment `stage` sets —
## and with `approach` "moving", `steps` walking steps in from further away before that.
## "static" is the attack from ma-ai, with no walk. Each stage is a dictionary for `pose_stage`
## ("name", "transition", "hold", and the catalogue's own keys); the walk's stages are worked out
## from the first stage's feet by taking them back a step at a time, so the last step of the walk
## lands exactly on the first stage. Call it after `stage` has set the attack, which is where
## the stages are measured from (`frame`).
static func lead_in(st: Staging, key: String, approach: String, steps: int, opts: Dictionary = {}) -> Array:
	var e := entry(key)
	var mirror: bool = opts.get("mirror", false)
	var frame := final_frame(st, opts)
	var out: Array = []
	for s: Dictionary in e.get("motion", {}).get("stages", []):
		var r := resolve(st, s, frame, mirror)
		r["name"] = s.get("name", "Stage %d" % (out.size() + 1))
		r["transition"] = float(s.get("transition", 0.6))
		r["hold"] = float(s.get("hold", 0.0))
		r["spec"] = s
		out.append(r)
	if approach != "moving" or out.is_empty():
		return out
	var stride: float = float(e.get("motion", {}).get("stride", WALK_STRIDE))
	var first: Dictionary = out[0]
	var walk: Array = []
	var feet: Dictionary = first["feet"].duplicate()
	var fwd := Basis(Vector3.UP, first["yaw"]) * Vector3(0, 0, 1)
	for i in steps:
		# Take the front foot back past the other: it was a stride behind it.
		var front := "Right" if (feet["Right"] - feet["Left"]).dot(fwd) >= 0.0 else "Left"
		var rear := "Left" if front == "Right" else "Right"
		var f: Vector3 = feet[front]
		var b: Vector3 = feet[rear]
		var back: Vector3 = f - fwd * ((f - b).dot(fwd) + stride)
		feet[front] = back
		walk.push_front({"feet": feet.duplicate(), "yaw": first["yaw"], "weight": WALK_WEIGHT,
			"drop": float(first.get("drop", 0.06)), "spec": {"hands": "kamae"},
			"transition": WALK_TRANSITION, "hold": 0.0})
	for i in walk.size():
		walk[i]["name"] = "Ayumi %d" % i if i > 0 else "Kamae (far)"
	walk[0]["hold"] = 0.4
	# Out of the walk the first stage is a step, not a stop.
	first["transition"] = WALK_TRANSITION
	first["hold"] = 0.0
	return walk + out


## Where the attack has put Uke: the frame its stages are written in.
static func final_frame(st: Staging, opts: Dictionary = {}) -> Dictionary:
	var uke := st.rig(opts.get("uke", "uke1"))
	var tori := st.rig(opts.get("tori", "tori"))
	var feet := {}
	for side in ["Right", "Left"]:
		var p: Vector3 = uke.limbs[side + "Leg"].target.global_position
		feet[side] = Vector3(p.x, 0.0, p.z)
	return {"basis": _flat(uke), "origin": Vector3(uke.position.x, 0.0, uke.position.z), "feet": feet,
		"tori_basis": _flat(tori), "tori_origin": Vector3(tori.position.x, 0.0, tori.position.z)}


## A stage of the catalogue in the world: each foot's place and the way the body faces. "feet"
## gives a foot as [left, forward] metres from where that foot ends up in the attack, in Uke's
## frame there (a foot not given is where it ends up); with "frame": "tori" the feet are instead
## places in Tori's frame from Tori's root, for stages that go round him (an attack from
## behind starts in front); "final" there puts that foot where it ends up. "turn" is degrees from the way Uke faces in the attack (or, in
## Tori's frame, from the way Tori faces: 180 is facing him).
static func resolve(st: Staging, s: Dictionary, frame: Dictionary, mirror: bool) -> Dictionary:
	var in_tori: bool = s.get("frame", "final") == "tori"
	var b: Basis = frame["tori_basis"] if in_tori else frame["basis"]
	var feet := {}
	for side in ["Right", "Left"]:
		var spec_side := _side(side, mirror)   # the catalogue's side that becomes this one
		var off = s.get("feet", {}).get(spec_side, null)
		var v := Vector3.ZERO
		if off is String and off == "final":
			# Where that foot ends up in the attack, whatever frame the stage is written in: the
			# step before an attack from behind lands exactly where the attack has it.
			feet[side] = frame["feet"][side]
			continue
		if off != null:
			v = Vector3(float(off[0]) * (-1.0 if mirror else 1.0), 0.0, float(off[1]))
		if in_tori:
			feet[side] = frame["tori_origin"] + b * v
		else:
			feet[side] = frame["feet"][side] + b * v
	var turn: float = deg_to_rad(float(s.get("turn", 0.0))) * (-1.0 if mirror else 1.0)
	var x := b.x
	var yaw := atan2(-x.z, x.x) + turn
	return {"feet": feet, "yaw": yaw, "weight": float(s.get("weight", 0.5)), "drop": float(s.get("drop", 0.06)),
		"lean": float(s.get("lean", 0.0))}


## Poses Uke for one stage `lead_in` returned: lets go of Tori, stands on the stage's feet, and
## puts the hands where the stage says ("kamae" by default; a side's hand as in the catalogue's
## hands — an offset, "to" a bone of Tori, "hang", "kamae") with the grips the stage names
## (indices into the attack's grips, taken as the attack takes them).
static func pose_stage(st: Staging, key: String, stage_: Dictionary, opts: Dictionary = {}) -> void:
	var e := entry(key)
	var mirror: bool = opts.get("mirror", false)
	var tori_id: String = opts.get("tori", "tori")
	var uke_id: String = opts.get("uke", "uke1")
	var tori := st.rig(tori_id)
	var spec: Dictionary = stage_.get("spec", {})
	for grip in st.director.grips_for(uke_id).duplicate():
		if grip.target.kind == GripTarget.Kind.BONE:
			st.director._remove(grip)
	await st.rest_limbs(uke_id)
	await st.stance_feet(uke_id, stage_["feet"], stage_["yaw"], stage_["weight"], stage_["drop"], stage_.get("lean", 0.0))
	var hands = spec.get("hands", "kamae")
	var front := "Right" if (stage_["feet"]["Right"] - stage_["feet"]["Left"]).dot(Basis(Vector3.UP, stage_["yaw"]) * Vector3(0, 0, 1)) >= 0.0 else "Left"
	if hands is String:
		if hands == "kamae":
			await st.kamae_hands(uke_id, _side(spec.get("lead", front), mirror) if spec.has("lead") else front)
		else:
			for side in ["Right", "Left"]:
				await st.hang_arm(uke_id, side)
	else:
		var placed := {}
		for side in hands:
			placed[_side(side, mirror)] = true
		if placed.size() < 2:
			await st.kamae_hands(uke_id, _side(spec.get("lead", front), mirror) if spec.has("lead") else front)
		for side in hands:
			await _place_hand(st, uke_id, _side(side, mirror), hands[side], tori, mirror)
	for side in spec.get("curls", {}):
		st.fingers(uke_id, _side(side, mirror), float(spec["curls"][side]))
	var grips: Array = e.get("grips", [])
	for i in spec.get("grips", []):
		await _take(st, grips[int(i)], tori_id, uke_id, tori, mirror)
	await st.settle(3)


## Takes every grip of the attack again from where Uke now stands.
static func _regrab(st: Staging, e: Dictionary, tori_id: String, uke_id: String, tori: CharacterRig, mirror: bool) -> Array:
	await st.release_all(uke_id)
	var grips: Array = []
	for g in e.get("grips", []):
		grips.append(await _take(st, g, tori_id, uke_id, tori, mirror))
	return grips


## The angles a grip's fingers may run across the bone at ("skews" in the catalogue, degrees;
## square to the bone when absent). Mirrored with the attack.
static func _skews(g: Dictionary, mirror: bool) -> Array:
	var out := []
	for sk in g.get("skews", [0.0]):
		out.append(-float(sk) if mirror else float(sk))
	return out


## Moves Uke to where his arms can make the grips they have been given: each candidate place is
## solved and scored by what the gripping arms' joints still refuse, how far a hand is short of
## its point, and how far Uke was moved. Nothing about the grips changes — where the hands are
## on Tori and how they are wrapped is the attack — only where Uke's shoulders are.
static func _fit(st: Staging, tori: CharacterRig, uke: CharacterRig, grips: Array, e: Dictionary = {}) -> void:
	var start: Vector3 = uke.position
	var toward: Vector3 = tori.global_position - start
	toward.y = 0.0
	if toward.length() < 1e-4:
		return
	toward = toward.normalized()
	var side := Vector3.UP.cross(toward).normalized()
	var best := start
	var best_cost := INF
	# An attack may hold Uke off: "min_gap" is how close his hips may come to Tori's, metres on
	# the mat. Arm's length is what a grab from the front looks like; without it the joints alone
	# pulled Uke in until the two stood chest to chest with the gripping elbow out to the side.
	var min_gap: float = float(e.get("uke", {}).get("min_gap", 0.0))
	for d_in in e.get("uke", {}).get("fit_in", FIT_STEPS_IN):
		for d_side in FIT_STEPS_SIDE:
			var at: Vector3 = start + toward * d_in + side * d_side
			st.ctrl.set_root(uke, at, uke.rotation.y, uke.rotation.x, uke.rotation.z)
			await st.settle(3)
			var cost := 0.0
			for line in _arm_refusals(uke, grips):
				cost += FIT_REFUSAL + _excess_of(uke, line)
			cost += FIT_ERROR_PER_M * _worst_error(st, grips) + FIT_MOVE_PER_M * at.distance_to(start)
			for o in Anatomy.body_overlaps(tori, uke, st.director):
				cost += FIT_BODY_PER_M * (o["depth"] - Anatomy.PENETRATION)
			if min_gap > 0.0:
				var gap := Vector2(at.x - tori.position.x, at.z - tori.position.z).length()
				cost += FIT_GAP_PER_M * maxf(0.0, min_gap - gap)
			if cost < best_cost:
				best_cost = cost; best = at
	st.ctrl.set_root(uke, best, uke.rotation.y, uke.rotation.x, uke.rotation.z)
	await st.settle(3)


## What the gripping arms (shoulder, elbow, wrist of each gripping hand) were refused.
static func _arm_refusals(uke: CharacterRig, grips: Array) -> PackedStringArray:
	var out := PackedStringArray()
	if uke.joint_limits == null:
		return out
	for grip in grips:
		for bone in [grip.hand + "UpperArm", grip.hand + "LowerArm", grip.hand + "Hand"]:
			for line in uke.joint_limits.report():
				if line.begins_with(bone + ":"):
					out.append(line)
	return out


static func _excess_of(uke: CharacterRig, line: String) -> float:
	var bone := line.get_slice(":", 0)
	if not uke.joint_limits.refused.has(bone):
		return 0.0
	var refusal: Dictionary = uke.joint_limits.refused[bone]
	var e := Joints.excess(uke.joints.specs[bone], refusal["wanted"], refusal.get("context", {}))
	return e["flex"] + e["abd"] + e["twist"]


static func _worst_error(st: Staging, grips: Array) -> float:
	var worst := 0.0
	for grip in grips:
		worst = maxf(worst, st.director.error_for(grip))
	return worst


static func _side(name: String, mirror: bool) -> String:
	if not mirror:
		return name
	if name.begins_with("Left"):
		return "Right" + name.trim_prefix("Left")
	if name.begins_with("Right"):
		return "Left" + name.trim_prefix("Right")
	return name


static func _vec(a: Array, mirror: bool) -> Vector3:
	var v := Vector3(float(a[0]), float(a[1]), float(a[2]))
	if mirror:
		v.x = -v.x
	return v
