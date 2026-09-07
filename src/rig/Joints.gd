class_name Joints
extends RefCounted
## What each joint of the body is and how far it goes: the anatomy the rig did not come with.
##
## A skeleton is a list of bones with rotations. Nothing in it says that an elbow is a hinge, a
## wrist bends further toward the palm than away from it, a knee cannot turn unless it is bent,
## or a finger cannot spread once it is curled. Every joint here is described the way a
## physiotherapist would: a neutral direction, a flexion axis, an abduction direction, and an
## asymmetric range in degrees for each of flexion/extension, abduction/adduction and twist,
## taken from the normal passive range of a healthy adult (AAOS goniometry, Kapandji for the
## hand). `JointLimits` enforces them on every solved pose, `Anatomy` reports what a pose asked
## for that the joint could not give, and the side panel poses a joint in these terms.
##
## Every frame is measured from the rig's rest geometry, not typed in: the mannequin's bone axes
## are whatever the exporter left them (the two feet are not even mirror images), so a joint is
## described by directions in the character's space — down, forward, out, the palm normal, the
## fold direction of the rest elbow — and stored in the parent bone's rest frame so it moves
## with the parent.
##
## Conventions. A joint is the bone's rotation against its parent. `n` is the neutral direction
## of the bone (straight along the parent for a hinge, hanging down for a shoulder or hip); `f`
## is the flexion axis, chosen so that a positive rotation about it moves the bone toward `p`,
## the flexion direction; `b` is the abduction direction, ±`f`. Flexion is the angle of the
## bone within the (n, p) plane, abduction its angle out of that plane, and twist is the roll
## about the bone left over once the swing from rest is removed. Ranges are [min, max]: a
## negative flexion is extension, a negative abduction adduction, and the name of each end of a
## range is in `names` so a readout can say "ulnar deviation 12°" rather than "abd 12".

## One joint: see build(). Plain dictionaries so the specs can be printed and compared.
##   bone, parent, kind, label, f, n, b, p, along_rest, rest_q, flex, abd, twist, names, gate

const KINDS := {"ball": "ball-and-socket", "hinge": "hinge", "condyloid": "condyloid",
	"saddle": "saddle", "gliding": "gliding"}

## The joints this rig has, in a parents-first order so a parent is clamped before its children.
var order: Array[String] = []
var specs: Dictionary = {}


static func build(sk: Skeleton3D, fingers: FingerCurl) -> Joints:
	var j := Joints.new()
	j._build(sk, fingers)
	return j


func has(bone: String) -> bool:
	return specs.has(bone)


func spec(bone: String) -> Dictionary:
	return specs.get(bone, {})


# --- the catalogue --------------------------------------------------------------------------

func _build(sk: Skeleton3D, fingers: FingerCurl) -> void:
	var X := Vector3.RIGHT      # the character's left is +X: it faces +Z
	var Y := Vector3.UP
	var Z := Vector3.BACK       # forward for the character (it faces +Z)
	# Trunk: flexion bends forward, side-bend goes to the character's left, turning to the left.
	for entry in [["Spine", [-25.0, 60.0], 25.0, 10.0], ["Chest", [-20.0, 45.0], 20.0, 25.0],
			["UpperChest", [-15.0, 35.0], 15.0, 20.0]]:
		_add(sk, entry[0], "gliding", "spine", _dir(sk, entry[0]), Z, X, entry[1],
			[-entry[2], entry[2]], [-entry[3], entry[3]],
			{"flex": ["extension", "flexion"], "abd": ["side-bend right", "side-bend left"],
				"twist": ["turn right", "turn left"]})
	_add(sk, "Neck", "gliding", "neck", _dir(sk, "Neck"), Z, X, [-50.0, 45.0], [-40.0, 40.0], [-70.0, 70.0],
		{"flex": ["extension", "flexion"], "abd": ["side-bend right", "side-bend left"],
			"twist": ["turn right", "turn left"]})
	_add(sk, "Head", "condyloid", "head", _dir(sk, "Head"), Z, X, [-30.0, 30.0], [-20.0, 20.0], [-30.0, 30.0],
		{"flex": ["extension", "flexion"], "abd": ["tilt right", "tilt left"],
			"twist": ["turn right", "turn left"]})
	for side in ["Right", "Left"]:
		var out: Vector3 = -X if side == "Right" else X
		var mirror: bool = side == "Left"
		# Clavicle: it shrugs and swings forward a little; it does not rotate.
		_add(sk, side + "Shoulder", "gliding", "clavicle", _dir(sk, side + "Shoulder"), Y, Z,
			[-10.0, 45.0], [-30.0, 30.0], [-15.0, 15.0],
			{"flex": ["depression", "elevation"], "abd": ["retraction", "protraction"],
				"twist": ["rolled back", "rolled forward"]})
		# Shoulder: neutral is the arm hanging straight down whatever the rest pose does with it.
		# Twist about a hanging arm turns the forearm out (external) or in (internal); which
		# sign is which depends on the side, so the range is written for the right and mirrored.
		_add(sk, side + "UpperArm", "ball", "shoulder", -Y, Z, out,
			[-60.0, 180.0], [-45.0, 180.0], [-90.0, 90.0],
			{"flex": ["extension", "flexion"], "abd": ["adduction", "abduction"],
				"twist": _mirror_names(["internal rotation", "external rotation"], mirror)}, "shoulder")
		# Elbow: a hinge that folds the way the rest elbow already folds. The forearm bone carries
		# pronation and supination (HandOrient hands it most of the wrist's roll), so its twist
		# budget is the forearm's, and which sign is pronation is read off the palm.
		var upper_rest := sk.get_bone_global_rest(sk.find_bone(side + "UpperArm"))
		var fold_arm: Vector3 = upper_rest.basis.orthonormalized() * Anatomy.rest_bend_local(sk, side + "Arm")
		var pron := _pronation_sign(sk, fingers, side)
		_add(sk, side + "LowerArm", "hinge", "elbow", _dir(sk, side + "UpperArm"), fold_arm, out,
			[-5.0, 155.0], [-8.0, 8.0], [-85.0, 80.0] if pron > 0.0 else [-80.0, 85.0],
			{"flex": ["extension", "flexion"], "abd": ["carrying angle in", "carrying angle out"],
				"twist": ["supination", "pronation"] if pron > 0.0 else ["pronation", "supination"]})
		# Wrist: flexion toward the palm, deviation toward the little finger (ulnar) is the
		# larger of the two. The bone's roll is really the forearm's (HandOrient gives the hand
		# 30 % of it), which is why a wrist here may roll further than a real one.
		var hand_rest := sk.get_bone_global_rest(sk.find_bone(side + "Hand"))
		var palmward: Vector3 = (hand_rest.basis.orthonormalized() * fingers.palm_normal(side)).normalized()
		var ulnar: Vector3 = -(hand_rest.basis.orthonormalized() * fingers.palm_width(side)).normalized()
		_add(sk, side + "Hand", "condyloid", "wrist", _dir(sk, side + "LowerArm"), palmward, ulnar,
			[-70.0, 80.0], [-20.0, 30.0], [-45.0, 45.0],
			{"flex": ["extension", "flexion"], "abd": ["radial deviation", "ulnar deviation"],
				"twist": ["rolled toward the thumb", "rolled toward the little finger"] if side == "Right" \
					else ["rolled toward the little finger", "rolled toward the thumb"]})
		# Fingers. The flexion axis of every phalanx is the one FingerCurl measured (across the
		# knuckles, positive toward the palm). A knuckle spreads only while the finger is open.
		var width: Vector3 = (hand_rest.basis.orthonormalized() * fingers.palm_width(side)).normalized()
		for finger in ["Index", "Middle", "Ring", "Little"]:
			var spread_dir: Vector3 = width if finger in ["Index", "Middle"] else -width
			var spread := 30.0 if finger == "Little" else 20.0
			_add_phalanx(sk, fingers, side + finger + "Proximal", "condyloid", "knuckle (MCP)",
				spread_dir, [-30.0, 90.0], [-spread, spread], [-10.0, 10.0], "mcp")
			_add_phalanx(sk, fingers, side + finger + "Intermediate", "hinge", "middle joint (PIP)",
				spread_dir, [-5.0, 100.0], [-4.0, 4.0], [-5.0, 5.0])
			_add_phalanx(sk, fingers, side + finger + "Distal", "hinge", "fingertip joint (DIP)",
				spread_dir, [-15.0, 80.0], [-4.0, 4.0], [-5.0, 5.0])
		# The thumb: a saddle at its base that sweeps across the palm and lifts away from it,
		# then two hinges. Their fold axis is the one FingerCurl measured for the thumb as a
		# whole, which is not quite each phalanx's own, so a plain curl reads as a little roll
		# here; the roll budgets allow for it.
		_add_phalanx(sk, fingers, side + "ThumbMetacarpal", "saddle", "thumb base (CMC)",
			palmward, [-15.0, 60.0], [-10.0, 60.0], [-40.0, 40.0], "",
			{"flex": ["extension", "flexion across the palm"], "abd": ["adduction", "palmar abduction"],
				"twist": ["rolled back", "rolled to oppose"]})
		_add_phalanx(sk, fingers, side + "ThumbProximal", "hinge", "thumb knuckle (MP)",
			palmward, [-10.0, 55.0], [-10.0, 10.0], [-15.0, 15.0])
		_add_phalanx(sk, fingers, side + "ThumbDistal", "hinge", "thumb tip (IP)",
			palmward, [-20.0, 80.0], [-10.0, 10.0], [-15.0, 15.0])
		# Hip: neutral is the leg straight down. Flexion is more with the knee bent; the larger
		# value is allowed, since this tool poses squats and rolls more than straight-leg kicks.
		_add(sk, side + "UpperLeg", "ball", "hip", -Y, Z, out,
			[-30.0, 120.0], [-30.0, 45.0], [-45.0, 45.0],
			{"flex": ["extension", "flexion"], "abd": ["adduction", "abduction"],
				"twist": _mirror_names(["internal rotation", "external rotation"], mirror)})
		# Knee: a hinge that folds backwards, with a little rotation that is only there once it
		# is bent (the "screw-home" lock of a straight knee).
		var thigh_rest := sk.get_bone_global_rest(sk.find_bone(side + "UpperLeg"))
		var fold_leg: Vector3 = thigh_rest.basis.orthonormalized() * Anatomy.rest_bend_local(sk, side + "Leg")
		_add(sk, side + "LowerLeg", "hinge", "knee", _dir(sk, side + "UpperLeg"), fold_leg, out,
			[-5.0, 155.0], [-8.0, 8.0], [-35.0, 35.0],
			{"flex": ["extension", "flexion"], "abd": ["varus", "valgus"],
				"twist": _mirror_names(["internal rotation", "external rotation"], mirror)}, "knee")
		# Ankle: the foot points down much further than it lifts. Dorsiflexion is 20° by the
		# book, but this rig's foot is one bone from ankle to ball and a squat with the heels
		# down loads the midfoot too, so it is given what a deep stance needs. Inversion (sole
		# turned to face the other foot) is the roll about the foot's own length, and is larger
		# than eversion.
		_add(sk, side + "Foot", "hinge", "ankle", _dir(sk, side + "Foot"), -Y, out,
			[-35.0, 65.0], [-15.0, 20.0], _mirror([-15.0, 35.0], mirror),
			{"flex": ["dorsiflexion", "plantarflexion"], "abd": ["toes in", "toes out"],
				"twist": _mirror_names(["eversion", "inversion"], mirror)})
		_add(sk, side + "Toes", "hinge", "toes (MTP)", _dir(sk, side + "Toes"), -Y, out,
			[-60.0, 40.0], [-5.0, 5.0], [-5.0, 5.0],
			{"flex": ["extension (lifted)", "flexion (curled)"], "abd": ["adduction", "abduction"],
				"twist": ["rolled", "rolled"]})
	# Parents first: the skeleton's own order is not guaranteed to be, and a clamped parent
	# changes nothing about its children's local rotations, so the order only matters for the
	# gates that read a parent.
	var depth := {}
	for bone in specs:
		var d := 0
		var i := sk.find_bone(bone)
		while i >= 0:
			d += 1
			i = sk.get_bone_parent(i)
		depth[bone] = d
	var names: Array[String] = []
	for bone in specs:
		names.append(bone)
	names.sort_custom(func(a, b): return depth[a] < depth[b] if depth[a] != depth[b] else a < b)
	order = names


## Registers one joint from directions in the character's rest space.
##   n_rig: neutral bone direction; p_rig: the direction flexion moves the bone toward;
##   b_rig: the direction abduction moves it toward (made perpendicular to n and to p).
func _add(sk: Skeleton3D, bone: String, kind: String, label: String, n_rig: Vector3, p_rig: Vector3,
		b_rig: Vector3, flex: Array, abd: Array, twist: Array, names: Dictionary, gate := "") -> void:
	var i := sk.find_bone(bone)
	if i < 0:
		return
	var parent := sk.get_bone_parent(i)
	if parent < 0:
		return
	var parent_rest := sk.get_bone_global_rest(parent).basis.orthonormalized()
	var to_parent := parent_rest.inverse()
	var n := n_rig.normalized()
	var p := (p_rig - n * p_rig.dot(n))
	if p.length() < 1e-6:
		return
	p = p.normalized()
	var f := n.cross(p).normalized()
	var b := f * signf(b_rig.dot(f)) if absf(b_rig.dot(f)) > 1e-6 else f
	var along_rig := _dir(sk, bone)
	var rest_q := sk.get_bone_rest(i).basis.get_rotation_quaternion().normalized()
	specs[bone] = {
		"bone": bone, "parent": sk.get_bone_name(parent), "kind": kind, "label": label,
		"n": (to_parent * n).normalized(), "p": (to_parent * p).normalized(),
		"f": (to_parent * f).normalized(), "b": (to_parent * b).normalized(),
		"along_rest": (to_parent * along_rig).normalized(), "rest_q": rest_q,
		"flex": flex, "abd": abd, "twist": twist, "names": names, "gate": gate,
	}


## A phalanx: neutral is its own rest direction (this rig's fingers rest slightly bent, and
## that small bend is the natural one), the flexion axis is FingerCurl's measured one.
func _add_phalanx(sk: Skeleton3D, fingers: FingerCurl, bone: String, kind: String, label: String,
		b_rig: Vector3, flex: Array, abd: Array, twist: Array, gate := "", names := {}) -> void:
	var i := sk.find_bone(bone)
	if i < 0:
		return
	var axis := fingers.flex_axis_rest(i)
	if axis.is_zero_approx():
		return
	var n := _dir(sk, bone)
	# Positive rotation about the flexion axis moves the bone toward f × n.
	var p := axis.cross(n)
	if names.is_empty():
		names = {"flex": ["extension", "flexion"], "abd": ["adduction", "abduction"],
			"twist": ["rolled", "rolled"]}
	_add(sk, bone, kind, label, n, p, b_rig, flex, abd, twist, names, gate)


## The rest direction of a bone in the character's space: to its children, or along its own axis
## for a leaf (a fingertip, the toes, the head).
static func _dir(sk: Skeleton3D, bone: String) -> Vector3:
	var i := sk.find_bone(bone)
	var g := sk.get_bone_global_rest(i)
	var kids := sk.get_bone_children(i)
	if kids.is_empty():
		return g.basis.y.normalized()
	var d := Vector3.ZERO
	for c in kids:
		d += sk.get_bone_global_rest(c).origin - g.origin
	return d.normalized()


## +1 when a positive roll about the rest forearm turns the palm to face further down
## (pronation), -1 when it turns it up.
static func _pronation_sign(sk: Skeleton3D, fingers: FingerCurl, side: String) -> float:
	var hand_rest := sk.get_bone_global_rest(sk.find_bone(side + "Hand"))
	var palm: Vector3 = (hand_rest.basis.orthonormalized() * fingers.palm_normal(side)).normalized()
	var forearm := _dir(sk, side + "LowerArm")
	var turned := palm.rotated(forearm, deg_to_rad(5.0))
	return 1.0 if turned.y < palm.y else -1.0


static func _mirror(range: Array, mirror: bool) -> Array:
	return [-range[1], -range[0]] if mirror else range


static func _mirror_names(names: Array, mirror: bool) -> Array:
	return [names[1], names[0]] if mirror else names


# --- measuring and posing -------------------------------------------------------------------

## The joint's angles for a bone's local pose rotation `q`: {"flex", "abd", "twist"} in degrees.
static func angles(spec: Dictionary, q: Quaternion) -> Dictionary:
	var rest_q: Quaternion = spec["rest_q"]
	var D := (q.normalized() * rest_q.inverse()).normalized()
	var along_rest: Vector3 = spec["along_rest"]
	var d: Vector3 = (D * along_rest).normalized()
	var n: Vector3 = spec["n"]; var p: Vector3 = spec["p"]; var b: Vector3 = spec["b"]
	var flex := rad_to_deg(atan2(d.dot(p), d.dot(n)))
	var abd := rad_to_deg(asin(clampf(d.dot(b), -1.0, 1.0)))
	var S := _arc(along_rest, d, spec["f"])
	var T := (S.inverse() * D).normalized()
	return {"flex": flex, "abd": abd, "twist": _angle_about(T, along_rest)}


## The local pose rotation that puts the joint at these angles (degrees).
static func rotation(spec: Dictionary, flex: float, abd: float, twist: float) -> Quaternion:
	var n: Vector3 = spec["n"]; var p: Vector3 = spec["p"]; var b: Vector3 = spec["b"]
	var along_rest: Vector3 = spec["along_rest"]
	var fl := deg_to_rad(flex); var ab := deg_to_rad(abd)
	var d := ((n * cos(fl) + p * sin(fl)) * cos(ab) + b * sin(ab)).normalized()
	var S := _arc(along_rest, d, spec["f"])
	var T := Quaternion(along_rest.normalized(), deg_to_rad(twist))
	return (S * T * spec["rest_q"]).normalized()


## The range in force for a joint at these angles. Most ranges are fixed; a few depend on the
## joint's own position, which is what makes them joints rather than three sliders:
##   knee — rotation is locked with the knee straight and opens up as it bends (about 35° at 90°);
##   mcp  — a finger spreads while it is open and the spread closes as it curls;
##   shoulder — the arm crosses the body (adduction) only when it is also raised forward.
static func limits(spec: Dictionary, a: Dictionary) -> Dictionary:
	var flex: Array = spec["flex"]
	var abd: Array = spec["abd"]
	var twist: Array = spec["twist"]
	match spec["gate"]:
		"knee":
			var open: float = clampf(a["flex"] / 90.0, 0.0, 1.0)
			var t: float = 5.0 + (twist[1] - 5.0) * open
			twist = [-t, t]
		"mcp":
			var open: float = clampf(1.0 - a["flex"] / 70.0, 0.15, 1.0)
			abd = [abd[0] * open, abd[1] * open]
		"shoulder":
			var raised: float = clampf(a["flex"] / 60.0, 0.0, 1.0)
			abd = [-(10.0 + (-abd[0] - 10.0) * raised), abd[1]]
	return {"flex": flex, "abd": abd, "twist": twist}


## The same angles brought inside the joint's range.
static func clamp_angles(spec: Dictionary, a: Dictionary) -> Dictionary:
	var lim := limits(spec, a)
	var flex := _nearest_turn(a["flex"], lim["flex"][0], lim["flex"][1])
	return {
		"flex": clampf(flex, lim["flex"][0], lim["flex"][1]),
		"abd": clampf(a["abd"], lim["abd"][0], lim["abd"][1]),
		"twist": clampf(a["twist"], lim["twist"][0], lim["twist"][1]),
	}


## By how much each angle lies outside its range, degrees; all zero for a plausible joint.
static func excess(spec: Dictionary, a: Dictionary) -> Dictionary:
	var c := clamp_angles(spec, a)
	return {"flex": absf(_nearest_turn(a["flex"], c["flex"], c["flex"]) - c["flex"]),
		"abd": absf(a["abd"] - c["abd"]), "twist": absf(a["twist"] - c["twist"])}


## The local rotation with the joint held inside its range; `q` itself when it already is.
static func clamp_rotation(spec: Dictionary, q: Quaternion) -> Quaternion:
	var a := angles(spec, q)
	var c := clamp_angles(spec, a)
	if absf(c["flex"] - a["flex"]) < 1e-3 and absf(c["abd"] - a["abd"]) < 1e-3 and absf(c["twist"] - a["twist"]) < 1e-3:
		return q
	return rotation(spec, c["flex"], c["abd"], c["twist"])


## A joint that could not be held inside its range, in words: "wrist flexion 119°, past 80°".
static func describe(spec: Dictionary, a: Dictionary) -> String:
	var lim := limits(spec, a)
	var parts := PackedStringArray()
	for key in ["flex", "abd", "twist"]:
		var v: float = a[key] if key != "flex" else _nearest_turn(a[key], lim[key][0], lim[key][1])
		var lo: float = lim[key][0]; var hi: float = lim[key][1]
		if v > hi + 0.5:
			parts.append("%s %.0f°, past %.0f°" % [spec["names"][key][1], v, hi])
		elif v < lo - 0.5:
			parts.append("%s %.0f°, past %.0f°" % [spec["names"][key][0], -v, -lo])
	return "%s %s" % [spec["label"], "; ".join(parts)] if not parts.is_empty() else ""


## The joint's angles as a person would say them: "flexion 32°, ulnar deviation 12°".
static func readout(spec: Dictionary, a: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in ["flex", "abd", "twist"]:
		var v: float = a[key]
		if absf(v) < 0.5:
			continue
		parts.append("%s %.0f°" % [spec["names"][key][1] if v > 0.0 else spec["names"][key][0], absf(v)])
	return ", ".join(parts) if not parts.is_empty() else "neutral"


## A flexion angle is an azimuth and comes back in (-180, 180]; an arm raised past vertical reads
## as a large negative extension. Pick the representative a whole turn away when that is the one
## nearer the range, so a shoulder at 190° is 10° past 180, not 170° past -60.
static func _nearest_turn(v: float, lo: float, hi: float) -> float:
	var best := v
	var best_d := _distance_to_range(v, lo, hi)
	for alt in [v - 360.0, v + 360.0]:
		var d := _distance_to_range(alt, lo, hi)
		if d < best_d - 1e-6:
			best = alt; best_d = d
	return best


static func _distance_to_range(v: float, lo: float, hi: float) -> float:
	if v < lo: return lo - v
	if v > hi: return v - hi
	return 0.0


## The shortest rotation taking unit vector `a` onto unit vector `b`; about `fallback` when they
## are opposite and any axis would do.
static func _arc(a: Vector3, b: Vector3, fallback: Vector3) -> Quaternion:
	var c := a.dot(b)
	if c < -0.999999:
		return Quaternion(fallback.normalized(), PI)
	if c > 0.999999:
		return Quaternion.IDENTITY
	return Quaternion(a, b).normalized()


## The signed angle, degrees, of a rotation that is (up to rounding) about `axis`.
static func _angle_about(q: Quaternion, axis: Vector3) -> float:
	var qq := q.normalized()
	if qq.w < 0.0:
		qq = -qq
	var proj := Vector3(qq.x, qq.y, qq.z).dot(axis.normalized())
	var deg := rad_to_deg(2.0 * atan2(proj, qq.w))
	return wrapf(deg, -180.0, 180.0)
