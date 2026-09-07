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
	var behind: bool = u.get("facing", "tori") == "same"
	var lateral: float = float(u.get("lateral", 0.0)) * (-1.0 if mirror else 1.0)
	var distance: float = float(u.get("distance", 0.6))
	st.stance(tori_id, 0.0, 0.0, 0.0)
	if behind:
		st.stance(uke_id, lateral, -distance, 0.0)
	else:
		st.stance(uke_id, lateral, distance, 180.0)
	await st.settle()
	await st.hanmi(tori_id, _side(e["tori"].get("hanmi", "Right"), mirror))
	await st.hanmi(uke_id, _side(u.get("hanmi", "Left"), mirror))
	# Hands the attack places are placed; the others hang at the side (the rest pose reaches
	# forward, which at grip distance is into the partner).
	var uke_hands := {}
	for g in e.get("grips", []):
		uke_hands[_side(g["hand"], mirror)] = true
	for side in ["Right", "Left"]:
		var tori_side := _side(side, mirror)
		if e["tori"].get("hands", {}).has(side):
			await st.hand_at(tori_id, tori_side, _vec(e["tori"]["hands"][side], mirror))
		else:
			await st.hang_arm(tori_id, tori_side)
		var uke_side := _side(side, mirror)
		if u.get("hands", {}).has(side):
			await st.hand_at(uke_id, uke_side, _vec(u["hands"][side], mirror))
		elif not uke_hands.has(uke_side):
			await st.hang_arm(uke_id, uke_side)
	for side in u.get("curls", {}):
		st.fingers(uke_id, _side(side, mirror), float(u["curls"][side]))
	await st.settle(3)
	var grips: Array = []
	for g in e.get("grips", []):
		var approach := Vector3.ZERO
		if g.has("approach"):
			approach = tori.global_transform.basis * _vec(g["approach"], mirror)
		grips.append(await st.grab(uke_id, _side(g["hand"], mirror), tori_id, _side(g["bone"], mirror),
			approach, float(g.get("along", 0.0)), float(g.get("curl", 0.6)), _skews(g, mirror)))
	var nominal: Vector3 = uke.position
	if not grips.is_empty() and opts.get("fit", true):
		# Twice: the way a hand wraps its target is chosen from where Uke stands, and where Uke
		# stands is chosen from how the hands wrap. Once round each is enough in practice.
		await _fit(st, tori, uke, grips)
		grips = await _regrab(st, e, tori_id, uke_id, tori, mirror)
		await _fit(st, tori, uke, grips)
	await st.feet_on_floor()
	await st.settle(3)
	return {
		"refused": _arm_refusals(uke, grips),
		"grip_error": _worst_error(st, grips),
		"uke_offset": uke.position.distance_to(nominal),
		"uke_position": uke.position,
	}


## Takes every grip of the attack again from where Uke now stands.
static func _regrab(st: Staging, e: Dictionary, tori_id: String, uke_id: String, tori: CharacterRig, mirror: bool) -> Array:
	await st.release_all(uke_id)
	var grips: Array = []
	for g in e.get("grips", []):
		var approach := Vector3.ZERO
		if g.has("approach"):
			approach = tori.global_transform.basis * _vec(g["approach"], mirror)
		grips.append(await st.grab(uke_id, _side(g["hand"], mirror), tori_id, _side(g["bone"], mirror),
			approach, float(g.get("along", 0.0)), float(g.get("curl", 0.6)), _skews(g, mirror)))
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
static func _fit(st: Staging, tori: CharacterRig, uke: CharacterRig, grips: Array) -> void:
	var start: Vector3 = uke.position
	var toward: Vector3 = tori.global_position - start
	toward.y = 0.0
	if toward.length() < 1e-4:
		return
	toward = toward.normalized()
	var side := Vector3.UP.cross(toward).normalized()
	var best := start
	var best_cost := INF
	for d_in in FIT_STEPS_IN:
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
	var e := Joints.excess(uke.joints.specs[bone], uke.joint_limits.refused[bone]["wanted"])
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
