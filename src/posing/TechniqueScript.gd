class_name TechniqueScript
extends RefCounted
## A technique written as data: who is in it, how they are dressed, and a list of phases, each a
## list of plain moves — "Uke attacks katatedori", "Tori steps 30 cm forward and turns 180° on
## his front foot", "Tori's left hand takes Uke's right wrist", "Uke bends forward 35°" — that this
## runs through the same staging, grip, stance and fall code the hand-built techniques use
## (Staging, Attacks, Stance, Ukemi). Each phase ends in a saved pose; the phases together are a
## sequence. docs/technique-scripts.md is the reference for every move; techniques/*.json are
## worked examples.
##
## The point is that a new technique is a page of JSON, not a function of GDScript: it is what
## an assistant writes from a description or from a video, renders, looks at, and corrects.
##
## Directions are always given in a figure's own frame, as [right, up, forward] metres (or
## [right, forward] on the mat), never in the engine's axes — the engine's x runs to a figure's
## *left*, which is a sign error waiting in every hand-written offset. Turns are degrees,
## positive counter-clockwise seen from above, i.e. toward the figure's left.

var tree: SceneTree
var scene: PosingScene
var director: GripDirector
var ctrl: PoseController
var cam
var st: Staging
## Where the attack left Uke, so later moves can be placed relative to it ("of": "attack").
var attack_origin := Transform3D.IDENTITY
## What happened, phase by phase: pose names, what the joints refused, unknown moves.
var report := {"phases": [], "errors": []}

## Every move do_move knows, by its verb (the key that names it).
const VERBS := ["attack", "from_pose", "place", "move", "pivot", "turn_foot", "step", "hanmi", "drop_hips",
	"kneel", "stand", "lean", "bend", "straighten", "hand", "elbow", "arm_down", "grab", "refit", "release",
	"fingers", "ukemi", "ground", "weapon", "look", "where", "settle"]
const DEFAULT_SKEWS := [0.0, 30.0, -30.0, 45.0, -45.0]
## Who looks where, by figure id: "uke1.Head" (a bone of anyone), "none", or [right, up, forward]
## (a direction in the figure's own frame). Unset, a figure looks at its partner's face.
var looks := {}
## How the turn is shared between the neck and the head, which together turn about 100° either
## way (Joints: neck 70°, head 30° of rotation); JointLimits keeps each inside its own range.
const LOOK_SHARE := {"Neck": 0.6, "Head": 1.0}
## The most each bone is turned by a look, inside its range with some to spare; and how far off
## the body's own facing a partner may be and still be looked at — someone standing beside you
## is watched out of the corner of the eye, not by craning round.
const LOOK_MAX := {"Neck": 40.0, "Head": 22.0}
const LOOK_FIELD := 100.0
var _look_used := {}
const DEFAULT_CHARACTERS := [
	{"id": "tori", "name": "Tori", "role": "Tori", "gi": true, "hakama": true},
	{"id": "uke1", "name": "Uke", "role": "Uke", "gi": true},
]
## Bones whose "forward" bend folds the figure forward when turned about its left axis; a thigh
## hangs the other way, so the same turn swings it back, and its forward is the opposite sign.
const TRUNK := ["Spine", "Chest", "UpperChest", "Neck", "Head", "LowerLeg"]


func _init(t: SceneTree, s: PosingScene, d: GripDirector, c: PoseController, camera = null) -> void:
	tree = t
	scene = s
	director = d
	ctrl = c
	cam = camera
	st = Staging.new(t, s, d, c)


## Reads a technique script, or returns {} with the reason printed.
static func load_file(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("Cannot read technique script %s" % path)
		return {}
	var data = JSON.parse_string(text)
	if not data is Dictionary:
		push_error("Technique script %s is not a JSON object" % path)
		return {}
	return data


## Builds every phase of `script`, saving a pose per phase into `out_dir`/poses and the sequence
## into `out_dir`/sequences. Returns the report.
func run(script: Dictionary, out_dir: String) -> Dictionary:
	var name: String = script.get("name", "Technique")
	var poses_dir := out_dir.path_join("poses")
	var seq_dir := out_dir.path_join("sequences")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(poses_dir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(seq_dir))
	await _reset(script.get("characters", DEFAULT_CHARACTERS))
	looks = {}
	for c: Dictionary in script.get("characters", []):
		if c.has("look"):
			looks[c["id"]] = c["look"]
	var seq := Sequence.new()
	seq.name = name
	seq.camera = script.get("camera", "Side")
	if script.get("view") is Dictionary:
		seq.view = script["view"]
	for phase: Dictionary in script.get("phases", []):
		var phase_name: String = phase.get("name", "Phase %d" % (seq.steps.size() + 1))
		# A figure is in a fall in a phase that says so (an "ukemi" move), and in no other.
		for r in scene.characters:
			r.fall = {}
		for move in phase.get("do", []):
			await do_move(move)
		if not phase.get("save", true):
			continue
		var pose_name := "%s %s" % [name, phase_name]
		await _save_pose(poses_dir, pose_name, phase.get("allow_short", false))
		seq.steps.append({"pose": PoseFile.slugify(pose_name),
			"transition": 0.0 if seq.steps.is_empty() else float(phase.get("transition", 0.7)),
			"hold": float(phase.get("hold", 0.3))})
	var err := seq.save(Sequence.sequence_path(seq_dir, name))
	if err != OK:
		report["errors"].append("could not write the sequence: %s" % error_string(err))
	report["sequence"] = Sequence.sequence_path(seq_dir, name)
	report["poses_dir"] = poses_dir
	return report


# ---------------------------------------------------------------- moves

## Runs one move. A move is a dictionary whose first recognised key is its verb.
func do_move(m: Dictionary) -> void:
	if m.has("attack"):
		var res: Dictionary = await Attacks.stage(st, m["attack"], {"mirror": m.get("mirror", false)})
		var uke := _rig(m.get("uke", "uke1"))
		if uke:
			attack_origin = uke.global_transform
		_note("attack %s: Uke refused %s" % [m["attack"], res.get("refused", [])])
	elif m.has("from_pose"):
		var path: String = m["from_pose"]
		if not path.ends_with(".json"):
			path = PoseFile.pose_path("res://poses", path)
		PoseFile.apply(PoseFile.load(path), scene, director, ctrl)
		await st.settle(3)
	elif m.has("place"):
		_place(m)
		await st.settle(2)
	elif m.has("move"):
		var r := _rig(m["move"])
		var b := _flat_basis(r)
		var step := b * _local2(m.get("by", [0.0, 0.0]))
		r.position += step
		if m.has("turn"):
			ctrl.set_root(r, r.position, r.rotation.y + deg_to_rad(m["turn"]), r.rotation.x, r.rotation.z)
		await st.settle(2)
	elif m.has("pivot"):
		await _ensure_legs(m["pivot"])
		var foot: String = m.get("foot", "Right")
		Stance.pivot(ctrl, _rig(m["pivot"]), foot, m.get("deg", 180.0))
		# Stance.pivot leaves the planted foot exactly as it was, which after a half turn is an
		# ankle twisted backwards; a tenkan turns on the ball of the foot, so the foot turns too.
		Stance.turn_foot(_rig(m["pivot"]), foot, m.get("deg", 180.0))
		await st.settle(3)
	elif m.has("turn_foot"):
		var p := _part(m["turn_foot"])
		Stance.turn_foot(_rig(p[0]), p[1], m.get("deg", 0.0))
		await st.settle(2)
	elif m.has("step"):
		await _step(m)
	elif m.has("hanmi"):
		await st.hanmi(m["hanmi"], m.get("front", "Right"), m.get("depth", 0.32), m.get("width", 0.16), m.get("drop", 0.06))
	elif m.has("drop_hips"):
		Stance.drop_hips(ctrl, _rig(m["drop_hips"]), m.get("m", 0.05))
		await st.settle(3)
	elif m.has("kneel"):
		var r := _rig(m["kneel"])
		await _stand_legs(r)
		Stance.kneel(ctrl, r, Stance.Kneel.KIZA if m.get("kind", "seiza") == "kiza" else Stance.Kneel.SEIZA)
		await st.settle(4)
		if m.get("kind", "seiza") == "kiza":
			Stance.toes_flat(r)
			await st.settle(2)
		Ukemi.ground(r)
		await st.settle(2)
	elif m.has("stand"):
		var r := _rig(m["stand"])
		var aside := _fall_aside(r)
		var heading := _heading(r)
		await st.rest_limbs(m["stand"])
		ctrl.set_root(r, Vector3(r.position.x, 0.0, r.position.z) + aside, heading)
		await st.settle(2)
	elif m.has("lean"):
		var r := _rig(m["lean"])
		ctrl.set_root(r, r.position, r.rotation.y, deg_to_rad(m.get("forward", 0.0)), deg_to_rad(-m.get("side", 0.0)), Stance.BOTH_LEGS)
		await st.settle(2)
		_knees_over_toes(r)
		await st.settle(2)
	elif m.has("bend"):
		_bend(m)
		await st.settle(2)
	elif m.has("straighten"):
		var p := _part(m["straighten"])
		var sk := _rig(p[0]).skeleton
		for bone in ([p[1]] if p[1] != "" else ["Spine", "Chest", "UpperChest", "Neck", "Head"]):
			var i := sk.find_bone(bone)
			sk.set_bone_pose_rotation(i, sk.get_bone_rest(i).basis.get_rotation_quaternion())
		await st.settle(2)
	elif m.has("hand"):
		await _hand(m)
	elif m.has("elbow"):
		var p := _part(m["elbow"])
		var r := _rig(p[0])
		var shoulder: Vector3 = r.bone_world_transform(p[1] + "UpperArm").origin
		r.limbs[p[1] + "Arm"].pole.global_position = shoulder + _flat_basis(r) * _local3(m.get("toward", [0.0, -0.3, -0.2]))
		await st.settle(2)
	elif m.has("arm_down"):
		var p := _part(m["arm_down"])
		await st.hang_arm(p[0], p[1])
	elif m.has("grab"):
		var p := _part(m["grab"])
		var t := _part(m.get("target", ""))
		var approach := Vector3.ZERO
		if m.has("from"):
			approach = _flat_basis(_rig(t[0])) * _local3(m["from"])
		await st.grab(p[0], p[1], t[0], t[1], approach, m.get("along", 0.0), m.get("curl", 0.6), m.get("skews", DEFAULT_SKEWS))
	elif m.has("refit"):
		await _refit(m)
	elif m.has("release"):
		var p := _part(m["release"])
		for grip in director.grips_for(p[0]):
			if p[1] == "" or grip.hand == p[1]:
				director._remove(grip)
				st.fingers(p[0], grip.hand, 0.0)
		await st.settle(2)
	elif m.has("fingers"):
		var p := _part(m["fingers"])
		st.fingers(p[0], p[1], m.get("curl", 0.6))
		await st.settle(2)
	elif m.has("ukemi"):
		var r := _rig(m["ukemi"])
		# Ukemi.shape writes the pitch into the Euler angles and keeps whatever yaw and roll they
		# hold; read back after a fall past 90°, those are the heading turned 180° and a roll of
		# 180°, and the next phase of the same fall would tumble the body the wrong way round.
		# Upright on the true heading first, so each phase of a fall is shaped from the same frame.
		# Where the hips are is read *before* the body is stood upright for the shape: read after,
		# it was the spot over the previous phase's feet (the root), so each phase of a fall started
		# from wherever the last one's feet had been flung — up to a body's length off along the
		# roll, and, once a roll tilted toward its shoulder, off to the side as well.
		var hips_before: Vector3 = r.bone_world_transform("Hips").origin
		var heading := _heading(r)
		r.rotation = Vector3(0.0, heading, 0.0)
		r.set_meta("fall_heading", heading)
		var kinds := {"forward": Ukemi.Kind.FORWARD, "backward": Ukemi.Kind.BACKWARD, "prone": Ukemi.Kind.PRONE}
		var kind_name: String = m.get("kind", "forward") if kinds.has(m.get("kind", "forward")) else "forward"
		var lead: String = "Left" if m.get("lead", "Right") == "Left" else "Right"
		Ukemi.shape(r, kinds[kind_name], m.get("t", 0.5), lead)
		r.fall = {"kind": kind_name, "t": float(m.get("t", 0.5)), "lead": lead}
		await st.settle(4)
		# The fall turns the body about its root, which is at the feet: three quarters through a
		# backward roll the body lies a body's length *ahead* of where it stood. A script says
		# where Uke goes (a "move" before the fall), so the hips stay over the same spot of the mat
		# through the shape and the travel is only what the script asked for.
		var drift: Vector3 = r.bone_world_transform("Hips").origin - hips_before
		drift.y = 0.0
		r.position -= drift
		await st.settle(2)
		Ukemi.ground(r)
		await st.settle(2)
		for pass_ in 3:   # a hand the fall put through the mat is put on it
			if Ukemi.hands_on_mat(r) <= 0.0:
				break
			await st.settle(3)
	elif m.has("ground"):
		Ukemi.ground(_rig(m["ground"]))
		await st.settle(2)
	elif m.has("weapon"):
		await _weapon(m)
	elif m.has("look"):
		looks[m["look"]] = m.get("at", "none")
	elif m.has("where"):
		_where(m)
	elif m.has("settle"):
		await st.settle(int(m["settle"]))
	else:
		report["errors"].append("unknown move %s" % JSON.stringify(m))
		push_error("TechniqueScript: unknown move %s" % JSON.stringify(m))


## "place": puts a figure on the mat, either absolutely ("at": [x, z] metres in the world, "yaw")
## or relative to another figure ("of": id, or "attack" for where the attack left Uke) with
## "at": [right, forward] in that figure's frame and "facing": degrees from that figure's facing
## (0 the same way, 180 face to face). "height", "pitch" (lean forward) and "roll" are optional.
func _place(m: Dictionary) -> void:
	var r := _rig(m["place"])
	var at: Array = m.get("at", [0.0, 0.0])
	var pos: Vector3
	var yaw: float
	if m.has("of"):
		var ref: Transform3D = attack_origin
		if m["of"] != "attack":
			var q := _part(m["of"])
			ref = _rig(q[0]).global_transform
			if q[1] != "":
				# Beside a part of someone — a shoulder, the hips — rather than their root, which is
				# at the feet and for anyone lying down is nowhere near the body.
				ref.origin = _rig(q[0]).bone_world_transform(q[1]).origin
		var ref_yaw := atan2(-ref.basis.x.z, ref.basis.x.x)
		var b := Basis(Vector3.UP, ref_yaw)
		pos = Vector3(ref.origin.x, 0.0, ref.origin.z) + b * _local2(at)
		yaw = ref_yaw + deg_to_rad(m.get("facing", 0.0))
	else:
		pos = Vector3(at[0], 0.0, at[1])
		yaw = deg_to_rad(m.get("yaw", 0.0))
	pos.y = m.get("height", 0.0)
	ctrl.set_root(r, pos, yaw, deg_to_rad(m.get("pitch", 0.0)), deg_to_rad(m.get("roll", 0.0)))


## "step": moves one foot "by": [right, forward] metres from where it stands, in the figure's
## frame — or "to" a bone of anyone ("uke1.LeftFoot"), plus "offset": [right, forward] in that
## figure's frame — turned "turn" degrees, and lets the hips follow to between the feet
## ("weight": 0 stays over the other foot, 1 goes over the stepping one; 0.5 by default). This
## is irimi (a step in) and, with a turn, the start of every tai sabaki. "body_turn" turns the
## body with the step.
func _step(m: Dictionary) -> void:
	var p := _part(m["step"])
	var r := _rig(p[0])
	await _ensure_legs(p[0])
	var b := _flat_basis(r)
	var limb: Limb = r.limbs[p[1] + "Leg"]
	var other: Limb = r.limbs[("Left" if p[1] == "Right" else "Right") + "Leg"]
	var t := limb.target.global_transform
	var before := t.origin
	if m.has("to"):
		var q := _part(m["to"])
		var tr := _rig(q[0])
		var goal: Vector3 = tr.bone_world_transform(q[1]).origin + _flat_basis(tr) * _local2(m.get("offset", [0.0, 0.0]))
		t.origin = Vector3(goal.x, t.origin.y, goal.z)
	else:
		t.origin += b * _local2(m.get("by", [0.0, 0.3]))
	t.basis = t.basis.rotated(Vector3.UP, deg_to_rad(m.get("turn", 0.0)))
	limb.target.global_transform = t
	var a := other.target.global_position
	var shift := a.lerp(t.origin, m.get("weight", 0.5)) - a.lerp(before, m.get("weight", 0.5))
	shift.y = 0.0
	ctrl.set_root(r, r.position + shift, r.rotation.y + deg_to_rad(m.get("body_turn", 0.0)), r.rotation.x, r.rotation.z, Stance.BOTH_LEGS)
	await st.settle(3)


## "bend": sets a spine, neck, head, thigh or shin bone to "forward" degrees (fold forward; for a
## thigh, the knee comes up; for a shin, the heel goes back), "side" (toward the figure's right)
## and "turn" (toward the figure's left), from its rest. Setting, not adding: asking twice gives
## the same pose. "straighten" puts it back.
func _bend(m: Dictionary) -> void:
	var p := _part(m["bend"])
	var r := _rig(p[0])
	var b := r.global_transform.basis
	var fwd: float = m.get("forward", 0.0)
	if p[1].ends_with("UpperLeg"):
		fwd = -fwd
	var turn := Basis(b.y.normalized(), deg_to_rad(m.get("turn", 0.0))) \
		* Basis(b.z.normalized(), deg_to_rad(m.get("side", 0.0))) \
		* Basis(b.x.normalized(), deg_to_rad(fwd))
	var sk := r.skeleton
	var i := sk.find_bone(p[1])
	if i < 0:
		report["errors"].append("bend: no bone %s" % p[1])
		return
	var parent := sk.get_bone_parent(i)
	var frame := sk.global_transform.basis
	if parent >= 0:
		frame = frame * sk.get_bone_global_rest(parent).basis
	var rest := sk.get_bone_rest(i).basis
	sk.set_bone_pose_rotation(i, ((frame.inverse() * turn * frame) * rest).get_rotation_quaternion().normalized())


## "hand": puts a hand somewhere without holding anything — "at": [right, up, forward] from its
## own shoulder, or "to": "uke1.Head" (a bone of anyone, "along" its length toward its child)
## plus "offset": [right, up, forward] in *that* figure's frame. A hand on a face for atemi,
## on a shoulder, cutting down past a neck. "curl" closes the fingers.
func _hand(m: Dictionary) -> void:
	var p := _part(m["hand"])
	var r := _rig(p[0])
	if r.limbs[p[1] + "Arm"].mode != Limb.Mode.IK:
		await ctrl.set_limb_mode(r, p[1] + "Arm", Limb.Mode.IK)
	var goal: Vector3
	if m.has("to"):
		var t := _part(m["to"])
		var tr := _rig(t[0])
		goal = tr.bone_world_transform(t[1]).origin
		var along: float = m.get("along", 0.0)
		var kids := tr.skeleton.get_bone_children(tr.skeleton.find_bone(t[1]))
		if along > 0.0 and kids.size() > 0:
			goal = goal.lerp(tr.bone_world_transform(tr.skeleton.get_bone_name(kids[0])).origin, along)
		goal += _flat_basis(tr) * _local3(m.get("offset", [0.0, 0.0, 0.0]))
	else:
		var shoulder: Vector3 = r.bone_world_transform(p[1] + "UpperArm").origin
		goal = shoulder + _flat_basis(r) * _local3(m.get("at", [0.0, -0.5, 0.1]))
	var limb: Limb = r.limbs[p[1] + "Arm"]
	if m.has("palm") or m.has("point"):
		limb.target.global_transform = Transform3D(_hand_basis(r, p[1], m), goal)
		limb.set_orient_to_target(true)
	else:
		limb.target.global_position = goal
	limb.reset_pole()
	if m.has("curl"):
		st.fingers(p[0], p[1], m["curl"])
	await st.settle(3)


## "refit": takes a held grip again where the hand now is, letting the wrap's search choose the
## side and the finger angle afresh for the arm as it now stands. A grip keeps the wrap it was
## taken with, so when the held arm turns (Tori's hand rising in a tenkan, the wrist turned over
## in a kotegaeshi) the gripping wrist is bent through whatever the turn is; a real hand shifts
## on the wrist instead, and this is that shift.
func _refit(m: Dictionary) -> void:
	var p := _part(m["refit"])
	for grip in director.grips_for(p[0]).duplicate():
		if p[1] != "" and grip.hand != p[1]:
			continue
		if grip.target.kind != GripTarget.Kind.BONE:
			continue
		var target_id: String = grip.target.character_id
		var bone: String = grip.target.bone_name
		var tr := _rig(target_id)
		var start: Vector3 = tr.bone_world_transform(bone).origin
		var kids := tr.skeleton.get_bone_children(tr.skeleton.find_bone(bone))
		var along := 0.0
		if kids.size() > 0:
			var end: Vector3 = tr.bone_world_transform(tr.skeleton.get_bone_name(kids[0])).origin
			var hand: Vector3 = _rig(p[0]).bone_world_transform(grip.hand + "Hand").origin
			along = clampf((hand - start).dot(end - start) / maxf((end - start).length_squared(), 1e-6), 0.0, 1.0)
		var hand_side: String = grip.hand
		var had: Transform3D = grip.offset
		director._remove(grip)
		await st.settle(1)
		await st.grab(p[0], hand_side, target_id, bone, Vector3.ZERO, along, m.get("curl", 0.6),
			m.get("skews", [0.0, 30.0, -30.0, 45.0, -45.0, 60.0, -60.0, 90.0, -90.0]),
			null if m.get("free", false) else had)


## The hand's world orientation for "point" (where the fingers point) and "palm" (which way the
## palm faces), each [right, up, forward] in the figure's frame; either may be left out, and the
## other is then kept as near as it can be to where it is now. Worked out from the rest pose,
## where the fingers run from the wrist to the middle knuckle and the palm faces the body.
func _hand_basis(r: CharacterRig, side: String, m: Dictionary) -> Basis:
	var sk := r.skeleton
	var g := sk.global_transform
	var rest := func(bone: String) -> Transform3D: return g * sk.get_bone_global_rest(sk.find_bone(bone))
	var hand_rest: Transform3D = rest.call(side + "Hand")
	var f0: Vector3 = (rest.call(side + "MiddleProximal").origin - hand_rest.origin).normalized()
	var across: Vector3 = rest.call(side + "IndexProximal").origin - rest.call(side + "LittleProximal").origin
	var p0: Vector3 = f0.cross(across).normalized()
	# At rest the palm faces the body: toward the figure's left for the right hand.
	var medial: Vector3 = r.global_transform.basis.x * (1.0 if side == "Right" else -1.0)
	if p0.dot(medial) < 0.0:
		p0 = -p0
	var now: Basis = r.bone_world_transform(side + "Hand").basis.orthonormalized()
	var rot_now: Basis = now * hand_rest.basis.orthonormalized().inverse()
	var b := _flat_basis(r)
	var f: Vector3 = (b * _local3(m["point"])).normalized() if m.has("point") else (rot_now * f0).normalized()
	var pl: Vector3 = (b * _local3(m["palm"])).normalized() if m.has("palm") else (rot_now * p0).normalized()
	if not m.has("point"):
		# Keep the fingers as near as they are, square to the palm asked for.
		f = (f - pl * f.dot(pl)).normalized()
	pl = (pl - f * pl.dot(f)).normalized()
	var want := Basis(f, pl, f.cross(pl))
	var had := Basis(f0, p0, f0.cross(p0))
	return (want * had.inverse() * hand_rest.basis.orthonormalized()).orthonormalized()


## "weapon": a bokken, jo or tanto. "hold": "uke1.Right" puts it in one hand; "kamae": "uke1"
## holds it in two hands at chudan (a jo in the jo's own kamae); "to" with "of", "at" and
## "dir" ([right, up, forward] in that figure's frame) moves it, refitting the hands on it;
## "take": "tori.Right" puts it in another hand (a disarm).
func _weapon(m: Dictionary) -> void:
	var id: String = m["weapon"]
	var w := scene.get_weapon(id)
	if w == null:
		w = scene.add_weapon(id, m.get("type", "bokken"))
	if m.has("hold"):
		var p := _part(m["hold"])
		await st.hold(p[0], p[1], w.type, m.get("t", -1.0), id)
	if m.has("kamae"):
		var r := _rig(m["kamae"])
		var b := _flat_basis(r)
		w.drive = "weapon"
		if m.get("type", "bokken") == "jo":
			_set_weapon(w, r.global_position + b * Vector3(-0.10, 0.98, -0.19), b * Vector3(0, 0.08, 1.0), Vector3.UP)
		else:
			_set_weapon(w, r.global_position + b * Vector3(0.0, 1.02, 0.25), b * Vector3(0, 0.45, 0.9), b * Vector3(0, 0.9, -0.45))
		director.attach_default_hands(r, w)
		await st.settle(3)
		await st.fit_weapon_hands(m["kamae"], w)
	if m.has("to"):
		var r := _rig(m.get("of", "uke1"))
		var b := _flat_basis(r)
		_set_weapon(w, r.global_position + b * _local3(m["to"]), b * _local3(m.get("dir", [0.0, 0.0, 1.0])), Vector3.UP)
		await st.settle(2)
		if m.has("fit"):
			await st.fit_weapon_hands(m["fit"], w)
	if m.has("take"):
		var p := _part(m["take"])
		var dh: Dictionary = w.default_hold(p[1])
		director.hold_weapon(_rig(p[0]), p[1], w, dh["t"], dh["roll_deg"], true)
		await st.settle(2)
		_rig(p[0]).fingers.apply_grip_preset(p[1])
	await st.settle(2)


func _set_weapon(w: Weapon, origin: Vector3, along: Vector3, up_hint: Vector3) -> void:
	along = along.normalized()
	var up := (up_hint - along * up_hint.dot(along)).normalized()
	w.global_transform = Transform3D(Basis(along.cross(up), along, up), origin)


# ---------------------------------------------------------------- saving

func _reset(chars: Array) -> void:
	director.clear()
	for w in scene.weapons.duplicate():
		scene.remove_weapon(w.weapon_id)
	for c in scene.characters.duplicate():
		scene.remove_character(c.character_id)
	await st.settle()
	for c: Dictionary in chars:
		var r := scene.add_character(c["id"], c.get("name", c["id"]), c.get("role", "Other"))
		if c.has("color"):
			r.set_skin_color(Color.html(c["color"]))
		if c.has("appearance"):
			r.set_appearance(c["appearance"])
		r.set_gi_visible(c.get("gi", true))
		r.set_hakama_visible(c.get("hakama", false))
	await st.settle()
	attack_origin = Transform3D.IDENTITY


## The pose as staged, with its bodies taken out of each other: the contact solve the blends use
## (ContactSolve), at full strength, a few rounds with the solve settling between them. Limbs go
## round the partner and out of their own body, the hips give a little, grips hold and feet stay
## where they stand. The staging places each figure by rules that know where a foot or a hand
## goes, not where the other body is; without this a pose could have Tori's thigh 7 cm into
## Uke's, and every frame of the film near it too.
const RELAX_ROUNDS := 6


func _relax() -> void:
	for _round in RELAX_ROUNDS:
		ContactSolve.solve(scene, director, {"root": 1.0, "arms": 1.0, "legs": 1.0})
		await st.settle(2)
	await st.feet_on_floor()
	await st.settle(2)


## Feet onto the mat, gripping hands onto their points (the gripper steps in by what it is
## short, as a person would; `allow_short` keeps a deliberate reach), then the pose is saved and
## what the joints refused is noted for the report.
func _save_pose(dir: String, pose_name: String, allow_short: bool) -> void:
	await st.settle(3)
	await st.feet_on_floor()
	if not allow_short:
		await _step_in_to_grips()
	await _relax()
	var before_look := await _look_all()
	var data: Dictionary = await PoseFile.capture_baked(scene, director, cam, pose_name)
	var path := PoseFile.pose_path(dir, pose_name)
	PoseFile.save(path, data)
	var probs := Anatomy.scene_problems(scene, director)
	_unlook(before_look)
	await st.settle(2)
	report["phases"].append({"pose": pose_name, "path": path, "problems": Array(probs),
		"grip_error": director.worst_error()})
	print("pose %s: grips %d, worst grip error %.3f m%s" % [pose_name, director.grips.size(), director.worst_error(),
		"" if probs.is_empty() else "\n    " + "\n    ".join(probs)])


func _step_in_to_grips() -> void:
	for attempt in 12:
		var moves := {}
		for grip in director.grips:
			var e := director.error_for(grip)
			if e < 0.008:
				continue
			var g := _rig(grip.gripper_id)
			var shoulder: Vector3 = g.bone_world_transform(grip.hand + "UpperArm").origin
			var toward: Vector3 = grip.desired_hand_transform().origin - shoulder
			toward.y = 0.0
			if not moves.has(grip.gripper_id):
				moves[grip.gripper_id] = [Vector3.ZERO, 0.0]
			moves[grip.gripper_id][0] += toward.normalized()
			moves[grip.gripper_id][1] = maxf(moves[grip.gripper_id][1], e)
		if moves.is_empty():
			break
		var blocked := 0
		for id in moves:
			var dir: Vector3 = moves[id][0]
			var r := _rig(id)
			if dir.length() < 1e-4 or r in _stopped:
				blocked += 1
				continue
			var step: Vector3 = dir.normalized() * (moves[id][1] * 0.8 + 0.01)
			# Walking in to a grip stops where the bodies would meet: a hand that cannot reach a
			# neck from outside is a move written a little wrong, and walking through the
			# partner to get there (which this used to do) hides that rather than showing it.
			if _closest_trunk(r, r.position + step) < _trunk_gap(r):
				_stopped.append(r)
				blocked += 1
				continue
			r.position += step
		if blocked == moves.size():
			break
		await st.settle(3)
	for grip in director.grips:
		if director.error_for(grip) > 0.02:
			_note("%s's %s hand is %.0f cm short of its grip: move the figure or the grip" % [grip.gripper_id, grip.hand, director.error_for(grip) * 100.0])
	_stopped.clear()


## How close two standing trunks may come, hip to hip on the mat.
const MIN_TRUNK_GAP := 0.30
var _stopped: Array = []


## How close `r`'s hips may come to anyone else's: further when someone is kneeling, whose
## thighs reach forward from the hips (two people in seiza touch knees with the hips 0.85 m apart).
func _trunk_gap(r: CharacterRig) -> float:
	var kneeling := 0
	for c: CharacterRig in scene.characters:
		if c.visible and c.position.y < -0.2 and absf(c.rotation.x) < 0.5:
			kneeling += 1
	return [MIN_TRUNK_GAP, 0.55, 0.85][mini(kneeling, 2)]


## The horizontal distance from `r`'s hips, were its root at `at`, to the nearest other figure's.
func _closest_trunk(r: CharacterRig, at: Vector3) -> float:
	var hips: Vector3 = r.bone_world_transform("Hips").origin + (at - r.position)
	var best := INF
	for other in scene.characters:
		if other == r or not other.visible:
			continue
		var o: Vector3 = other.bone_world_transform("Hips").origin
		best = minf(best, Vector2(hips.x - o.x, hips.z - o.z).length())
	return best


# ---------------------------------------------------------------- looking

## Turns every standing figure's neck and head toward what it looks at, just before a pose is
## saved, and returns the rotations it replaced so `_unlook` can put them back: a look decorates
## the pose it is saved with, and the next phase's moves start from the head as the script left it.
## A face that stares straight ahead past its partner is the first thing that makes a still read
## as dolls rather than people.
func _look_all() -> Dictionary:
	var saved := {}
	for r: CharacterRig in scene.characters:
		if not r.visible or absf(r.rotation.x) > 0.5 or absf(r.rotation.z) > 0.5:
			continue   # falling or lying: the fall shapes the neck (Ukemi's tuck)
		var goal = _look_goal(r)
		if goal == null:
			continue
		saved[r] = {}
		_look_used.clear()
		for bone: String in LOOK_SHARE:
			var i := r.skeleton.find_bone(bone)
			saved[r][i] = r.skeleton.get_bone_pose_rotation(i)
		# Neck first, then the head from where the neck left it; twice, since each solve moves
		# the eyes the next turn is measured from.
		for pass_ in 2:
			for bone: String in LOOK_SHARE:
				_turn_toward(r, bone, goal, LOOK_SHARE[bone] * (0.5 if pass_ == 1 else 1.0), LOOK_MAX[bone])
				await st.settle(1)
	return saved


func _unlook(saved: Dictionary) -> void:
	for r in saved:
		for i in saved[r]:
			r.skeleton.set_bone_pose_rotation(i, saved[r][i])


## A world point to look at, or null.
func _look_goal(r: CharacterRig):
	var at = looks.get(r.character_id, "")
	if at is String and at == "none":
		return null
	if at is Array:
		return r.bone_world_transform("Head").origin + _flat_basis(r) * _local3(at) * 3.0
	if at is String and at != "":
		var q := _part(at)
		var t := scene.get_character(q[0])
		return t.bone_world_transform(q[1] if q[1] != "" else "Head").origin if t else null
	# The partner: Tori looks at the first Uke, everyone else at Tori.
	var partner: CharacterRig = null
	for o: CharacterRig in scene.characters:
		if o != r and o.visible and (o.role == "Tori") != (r.role == "Tori"):
			partner = o
			break
	if partner == null:
		return null
	var face: Vector3 = partner.bone_world_transform("Head").origin
	var to := face - r.global_position
	to.y = 0.0
	var ahead := _flat_basis(r) * Vector3(0, 0, 1)
	if to.length() > 0.05 and rad_to_deg(ahead.angle_to(to.normalized())) > LOOK_FIELD:
		return null
	return face


## Turns `bone` by `share` of the angle between where the face points and `goal`, about the bone.
## Where the face points is the body's forward carried through the head's turn from rest.
func _turn_toward(r: CharacterRig, bone: String, goal: Vector3, share: float, max_deg: float) -> void:
	var sk := r.skeleton
	var i := sk.find_bone(bone)
	var head := r.bone_world_transform("Head")
	var rest_head := sk.global_transform.basis * sk.get_bone_global_rest(sk.find_bone("Head")).basis
	var forward: Vector3 = (head.basis.orthonormalized() * (rest_head.orthonormalized().inverse() * r.global_transform.basis.z.normalized())).normalized()
	var eyes: Vector3 = head.origin + head.basis.y.normalized() * 0.08
	var want: Vector3 = (goal - eyes).normalized()
	if want.length() < 0.5 or forward.dot(want) > 0.9995:
		return
	var axis := forward.cross(want).normalized()
	var angle := forward.angle_to(want) * share
	# What this bone has already been turned by a look this pose, against its cap.
	var key := "%s/%s" % [r.character_id, bone]
	var used: float = _look_used.get(key, 0.0)
	angle = clampf(angle, 0.0, maxf(0.0, deg_to_rad(max_deg) - used))
	_look_used[key] = used + angle
	var parent := sk.get_bone_parent(i)
	var p_basis := r.bone_world_transform(sk.get_bone_name(parent)).basis.orthonormalized()
	var local := Basis(sk.get_bone_pose_rotation(i))
	var turned := (p_basis.inverse() * Basis(axis, angle) * p_basis * local).orthonormalized()
	sk.set_bone_pose_rotation(i, turned.get_rotation_quaternion())


# ---------------------------------------------------------------- helpers

func _rig(id: String) -> CharacterRig:
	var r := scene.get_character(id)
	if r == null:
		report["errors"].append("no character %s" % id)
		push_error("TechniqueScript: no character %s" % id)
	return r


## "tori.Right" -> ["tori", "Right"]; "uke1.LeftLowerArm" -> ["uke1", "LeftLowerArm"]; "tori" -> ["tori", ""].
func _part(s: String) -> Array:
	var i := s.find(".")
	return [s, ""] if i < 0 else [s.substr(0, i), s.substr(i + 1)]


## The figure's frame turned only about the vertical: a figure that is leaning or falling still
## has "forward" along the mat. The heading is read from the sideways axis, which a pitch does
## not move: past 90° of pitch (any backward roll) the Euler yaw in `rotation.y` flips by 180°,
## and "back" would send a rolling Uke forward into Tori.
func _flat_basis(r: CharacterRig) -> Basis:
	return Basis(Vector3.UP, _heading(r))


## How far a fallen figure's hips are from its root, along the mat. The root is at the feet, and
## a body turned over in a fall has its feet a body's length from where the body is, and to the
## side of it once the roll is tilted toward a shoulder; getting up there stood Uke up a metre
## beside his own roll. A figure gets up where its hips are, so a fall travels exactly as far as
## the script's moves say.
func _fall_aside(r: CharacterRig) -> Vector3:
	if not r.has_meta("fall_heading") or r.global_transform.basis.y.normalized().y >= 0.95:
		return Vector3.ZERO
	var off: Vector3 = r.bone_world_transform("Hips").origin - r.position
	off.y = 0.0
	return off


func _heading(r: CharacterRig) -> float:
	# A figure in a fall is tilted toward the shoulder it rolls over as well as turned over, so
	# its sideways axis no longer says which way it is heading, and the Euler angles read back
	# from a body turned past 90° are an equivalent but different triple. The fall keeps the
	# heading it was shaped on (set in the "ukemi" move), and that is the answer while the body is
	# off its feet.
	if r.has_meta("fall_heading") and r.global_transform.basis.y.normalized().y < 0.95:
		return float(r.get_meta("fall_heading"))
	var x := r.global_transform.basis.x
	return atan2(-x.z, x.x)


## [right, forward] -> engine local (x runs to the figure's left).
func _local2(a: Array) -> Vector3:
	return Vector3(-float(a[0]), 0.0, float(a[1]))


## [right, up, forward] -> engine local.
func _local3(a: Array) -> Vector3:
	return Vector3(-float(a[0]), float(a[1]), float(a[2]))


## "where": prints where everyone's main parts are, as [right, up, forward] metres from the root
## of the figure named (its "of", default the figure itself) in that figure's frame, and each
## figure's heading relative to it. For writing a script: what is beside whom, which way is up.
func _where(m: Dictionary) -> void:
	var ref := _rig(m.get("of", m["where"]))
	var b := _flat_basis(ref).inverse()
	var o := ref.global_position
	print("  where (from %s, [right, up, forward]):" % ref.character_id)
	for r: CharacterRig in scene.characters:
		var parts := PackedStringArray()
		for bone in ["Hips", "Head", "RightShoulder", "RightHand", "LeftHand", "RightFoot", "LeftFoot"]:
			var v: Vector3 = b * (r.bone_world_transform(bone).origin - o)
			parts.append("%s [%.2f, %.2f, %.2f]" % [bone, -v.x, v.y, v.z])
		var root: Vector3 = b * (r.global_position - o)
		print("    %s root [%.2f, %.2f, %.2f] facing %.0f°: %s" % [r.character_id, -root.x, root.y, root.z,
			rad_to_deg(wrapf(_heading(r) - _heading(ref), -PI, PI)), ", ".join(parts)])


## Puts the legs back to standing under the hips where the figure is: Stance.kneel squares each
## foot from the way it stands, so kneeling again from seiza into kiza (or kneeling after a fall)
## read feet that were already folded under, and turned them inside out.
func _stand_legs(r: CharacterRig) -> void:
	var sk := r.skeleton
	for side in ["Right", "Left"]:
		var limb: Limb = r.limbs[side + "Leg"]
		limb.set_orient_to_target(false)
		r.set_limb_mode(side + "Leg", Limb.Mode.FK)
		for bone in [side + "UpperLeg", side + "LowerLeg", side + "Foot", side + "Toes"]:
			var i := sk.find_bone(bone)
			sk.set_bone_pose_rotation(i, sk.get_bone_rest(i).basis.get_rotation_quaternion())
	var aside := _fall_aside(r)
	ctrl.set_root(r, Vector3(r.position.x, 0.0, r.position.z) + aside, _heading(r))
	await st.settle(2)
	for side in ["Right", "Left"]:
		(r.limbs[side + "Leg"] as Limb).reset_target_to_pose()
	await st.settle(1)


## Points each planted leg's knee out over its own toes. A leg's pole is otherwise set from the
## body's frame, so once the body tips (a lean) or a foot is turned out (the rear foot of hanmi),
## the knee aims somewhere the foot does not, and the ankle twists to make up the difference.
func _knees_over_toes(r: CharacterRig) -> void:
	for side in ["Right", "Left"]:
		var limb: Limb = r.limbs[side + "Leg"]
		if limb.mode != Limb.Mode.IK:
			continue
		var toes: Vector3 = r.bone_world_transform(side + "Toes").origin - r.bone_world_transform(side + "Foot").origin
		toes.y = 0.0
		if toes.length() < 1e-4:
			continue
		var hip: Vector3 = r.bone_world_transform(side + "UpperLeg").origin
		var mid: Vector3 = (hip + limb.target.global_position) * 0.5
		limb.pole.global_position = mid + toes.normalized() * 0.6


func _ensure_legs(id: String) -> void:
	var r := _rig(id)
	for side in ["Right", "Left"]:
		if r.limbs[side + "Leg"].mode != Limb.Mode.IK:
			await ctrl.set_limb_mode(r, side + "Leg", Limb.Mode.IK)
	await st.settle(2)


func _note(text: String) -> void:
	print("  ", text)
	if not report.has("notes"):
		report["notes"] = []
	report["notes"].append(text)
