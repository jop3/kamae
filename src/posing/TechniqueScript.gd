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

const DEFAULT_SKEWS := [0.0, 30.0, -30.0, 45.0, -45.0]
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
	var seq := Sequence.new()
	seq.name = name
	seq.camera = script.get("camera", "Side")
	for phase: Dictionary in script.get("phases", []):
		var phase_name: String = phase.get("name", "Phase %d" % (seq.steps.size() + 1))
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
		Stance.kneel(ctrl, r, Stance.Kneel.KIZA if m.get("kind", "seiza") == "kiza" else Stance.Kneel.SEIZA)
		await st.settle(4)
		Ukemi.ground(r)
		await st.settle(2)
	elif m.has("stand"):
		var r := _rig(m["stand"])
		await st.rest_limbs(m["stand"])
		ctrl.set_root(r, Vector3(r.position.x, 0.0, r.position.z), r.rotation.y)
		await st.settle(2)
	elif m.has("lean"):
		var r := _rig(m["lean"])
		ctrl.set_root(r, r.position, r.rotation.y, deg_to_rad(m.get("forward", 0.0)), deg_to_rad(-m.get("side", 0.0)), Stance.BOTH_LEGS)
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
		var kinds := {"forward": Ukemi.Kind.FORWARD, "backward": Ukemi.Kind.BACKWARD, "prone": Ukemi.Kind.PRONE}
		Ukemi.shape(r, kinds.get(m.get("kind", "forward"), Ukemi.Kind.FORWARD), m.get("t", 0.5))
		await st.settle(4)
		Ukemi.ground(r)
		await st.settle(2)
	elif m.has("ground"):
		Ukemi.ground(_rig(m["ground"]))
		await st.settle(2)
	elif m.has("weapon"):
		await _weapon(m)
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
		var ref: Transform3D = attack_origin if m["of"] == "attack" else _rig(m["of"]).global_transform
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
	r.limbs[p[1] + "Arm"].target.global_position = goal
	r.limbs[p[1] + "Arm"].reset_pole()
	if m.has("curl"):
		st.fingers(p[0], p[1], m["curl"])
	await st.settle(3)


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


## Feet onto the mat, gripping hands onto their points (the gripper steps in by what it is
## short, as a person would; `allow_short` keeps a deliberate reach), then the pose is saved and
## what the joints refused is noted for the report.
func _save_pose(dir: String, pose_name: String, allow_short: bool) -> void:
	await st.settle(3)
	await st.feet_on_floor()
	if not allow_short:
		await _step_in_to_grips()
	var data: Dictionary = await PoseFile.capture_baked(scene, director, cam, pose_name)
	var path := PoseFile.pose_path(dir, pose_name)
	PoseFile.save(path, data)
	var probs := Anatomy.scene_problems(scene, director)
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
			if _closest_trunk(r, r.position + step) < MIN_TRUNK_GAP:
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


func _heading(r: CharacterRig) -> float:
	var x := r.global_transform.basis.x
	return atan2(-x.z, x.x)


## [right, forward] -> engine local (x runs to the figure's left).
func _local2(a: Array) -> Vector3:
	return Vector3(-float(a[0]), 0.0, float(a[1]))


## [right, up, forward] -> engine local.
func _local3(a: Array) -> Vector3:
	return Vector3(-float(a[0]), float(a[1]), float(a[2]))


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
