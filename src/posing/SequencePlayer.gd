class_name SequencePlayer
extends Node
## Plays a Sequence on the scene: keeps a clock, looks up the two poses around it and asks
## PoseBlend to put the scene there. Scrubbing is the same call with a chosen time.

signal time_changed(time: float)
signal finished

var scene: PosingScene
var director: GripDirector
var camera: Node        ## OrbitCamera, only used when the sequence's camera is "per_pose"
var sequence: Sequence
var poses: Dictionary = {}     ## slug -> pose dictionary
var time := 0.0
var playing := false
var loop := false
var _entities_ready := false
## Per step, where every limb's middle joint and end really were when that step's pose was shown
## (prepare): {character id: {limb key: {"mid": Vector3, "end": Vector3}}}, in the figure's frame.
var solved: Array = []


func setup(posing_scene: PosingScene, grip_director: GripDirector) -> void:
	scene = posing_scene
	director = grip_director


## Loads every pose the sequence names from `poses_dir`. Returns the slugs that were missing.
func load_sequence(seq: Sequence, poses_dir: String) -> Array:
	sequence = seq
	poses.clear()
	var missing := []
	for step in seq.steps:
		var slug: String = step["pose"]
		if poses.has(slug):
			continue
		var data := PoseFile.load(poses_dir.path_join(slug + ".json"))
		if data.is_empty():
			missing.append(slug)
		else:
			poses[slug] = data
	time = 0.0
	_entities_ready = false
	solved = []
	return missing


## Shows every step's pose once and notes where each limb's elbow or knee and hand or foot ended
## up after the solve, so the blends between them can steer each joint from one keyframe's shape
## to the next (PoseBlend.steered_pole). A few frames per step; call it after loading, before
## playing or filming. Leaves the scene where the clock is.
const PREPARE_FRAMES := 4


func prepare() -> void:
	solved = []
	if sequence == null:
		return
	var tree := get_tree()
	var found := []
	for i in sequence.steps.size():
		apply_time(sequence.step_start(i))
		for _f in PREPARE_FRAMES:
			await tree.process_frame
		var per := {}
		for rig in scene.characters:
			if not rig.visible:
				continue
			var inv := rig.global_transform.affine_inverse()
			var limbs := {}
			for key in rig.limbs:
				var limb: Limb = rig.limbs[key]
				limbs[key] = {"mid": inv * rig.bone_world_transform(limb.middle_bone).origin,
					"end": inv * rig.bone_world_transform(limb.end_bone).origin}
			per[rig.character_id] = limbs
		found.append(per)
	solved = found
	apply_time(time)


func set_pose_data(slug: String, data: Dictionary) -> void:
	poses[slug] = data


func duration() -> float:
	return sequence.duration() if sequence else 0.0


func play() -> void:
	if sequence == null:
		return
	if time >= duration():
		time = 0.0
	playing = true


func pause() -> void:
	playing = false


func stop() -> void:
	playing = false
	seek(0.0)


func seek(t: float) -> void:
	time = clampf(t, 0.0, duration())
	apply_time(time)
	time_changed.emit(time)


func _process(delta: float) -> void:
	if not playing:
		return
	time += delta
	if time >= duration():
		if loop:
			time = fmod(time, maxf(duration(), 1e-3))
		else:
			time = duration()
			playing = false
			apply_time(time)
			time_changed.emit(time)
			finished.emit()
			return
	apply_time(time)
	time_changed.emit(time)


## Puts the scene at `t` without touching the clock.
func apply_time(t: float) -> void:
	if sequence == null or sequence.steps.is_empty():
		return
	if not _entities_ready:
		PoseBlend.ensure_entities(scene, poses.values())
		_entities_ready = true
	var st := timing(sequence, t)
	var a: Dictionary = poses.get(sequence.steps[st["from"]]["pose"], {})
	var b: Dictionary = poses.get(sequence.steps[st["to"]]["pose"], a)
	if a.is_empty():
		return
	if st["from"] == st["to"]:
		PoseBlend.apply(scene, director, a, a, 0.0)
	else:
		var ctx := {"u": st["channels"], "times": st["times"], "fall_u": st["fall_u"]}
		if solved.size() == sequence.steps.size():
			ctx["solved_a"] = solved[st["from"]]
			ctx["solved_b"] = solved[st["to"]]
		ctx["rest"] = [st["rest_a"], st["rest_b"]]
		PoseBlend.apply(scene, director, a, b, st["u"], _step_pose(st["from"] - 1), _step_pose(st["to"] + 1), ctx)
	_alive(t, st)
	if camera != null and sequence.camera == "per_pose":
		var ca = a.get("camera")
		var cb = b.get("camera")
		if ca is Dictionary or cb is Dictionary:
			camera.apply_state(OrbitCamera.blend_state(ca if ca is Dictionary else {}, cb if cb is Dictionary else {}, st["u"]))


## A body standing on a pose is not a statue. Two small movements on top of the blend, both nothing
## at all at any pose's own time (the stills are taken there, and the pose is shown as saved):
##   settle — the hips arrive at a pose the technique rests on still moving (SETTLE of the move's
##     even speed), carry on past it and come back, as a body's weight settles after a step or a
##     turn: s·e^(−s/SETTLE_TIME) of that arriving speed, s seconds after the pose;
##   breath — the chest rises and falls, faded in away from every pose.
## Not for a figure in a fall, which has its own course.
const SETTLE := 0.35
const SETTLE_TIME := 0.12
const BREATH_DEG := 0.8
const BREATH_PERIOD := 3.2
const BREATH_FADE := 0.5


func _alive(t: float, st: Dictionary) -> void:
	var n := sequence.steps.size()
	var nearest := INF
	var k := -1
	for i in n:
		var ti := sequence.step_start(i)
		nearest = minf(nearest, absf(t - ti))
		if ti <= t + 1e-9:
			k = i
	nearest = minf(nearest, absf(sequence.duration() - t))   # a film ends on its last pose
	var moved := false
	for rig in scene.characters:
		if not rig.visible or rig.keep_on_mat or PoseBlend.is_fall(rig.rotation) or not rig.fall.is_empty():
			continue
		moved = moved or nearest > 1e-6
		var breath := BREATH_DEG * smoothstep(0.0, BREATH_FADE, nearest) * sin(TAU * t / BREATH_PERIOD + float(rig.get_index()))
		if st["from"] == st["to"] and nearest > 1e-6:
			_steady_limbs(rig, st["from"])
		if absf(breath) > 1e-4:
			Ukemi.turn_bone(rig, "Chest", rig.global_transform.basis.x, -breath * 0.5)
			Ukemi.turn_bone(rig, "UpperChest", rig.global_transform.basis.x, -breath * 0.5)
	if k >= 1:
		var s := t - sequence.step_start(k)
		if s > 1e-6 and s < 8.0 * SETTLE_TIME:
			var bump := s * exp(-s / SETTLE_TIME)
			for group in _joined(k):
				_settle_group(group, k, bump)
	# A pose held while it breathes and settles is kept clear of bodies as a blend is, the correction
	# faded in from the pose's own time (where the pose is shown exactly as saved).
	if moved and st["from"] == st["to"]:
		var w := smoothstep(0.0, 0.3, nearest)
		MotionClearance.resolve(scene, director, {"root": w, "arms": w, "legs": w})


## The figures at step `k` in groups held together by grips (each figure alone when it holds no
## one and no one holds it).
func _joined(k: int) -> Array:
	var group := {}
	for rig in scene.characters:
		group[rig.character_id] = rig.character_id
	var find := func(x: String, g: Dictionary) -> String:
		while g[x] != x:
			x = g[x]
		return x
	for grip in _step_pose(k).get("grips", []):
		var a: String = grip.get("gripper", "")
		var b: String = grip.get("target", {}).get("character", "")
		if group.has(a) and group.has(b):
			group[find.call(a, group)] = find.call(b, group)
	var out := {}
	for rig in scene.characters:
		var r: String = find.call(rig.character_id, group)
		if not out.has(r):
			out[r] = []
		out[r].append(rig)
	return out.values()


## Settles a group of figures by `bump` seconds of their arrival speed. A figure alone carries on
## along its own way and turn; figures joined by a grip carry on together, by the mean of their
## ways and without turning (a turn about each one's own feet would drive the arm that joins them
## into the other).
func _settle_group(group: Array, k: int, bump: float) -> void:
	var pos := Vector3.ZERO
	var yaw := 0.0
	var n := 0
	for rig: CharacterRig in group:
		if not rig.visible or rig.keep_on_mat or PoseBlend.is_fall(rig.rotation) or not rig.fall.is_empty():
			return
		var v := _arrival_speed(k, rig.character_id)
		if v.is_empty():
			continue
		pos += v["pos"]
		yaw += v["yaw"]
		n += 1
	if n == 0:
		return
	for rig: CharacterRig in group:
		rig.position += pos / n * bump
		if group.size() == 1:
			rig.rotation.y += yaw * bump


## On a pose that is breathing and settling, each limb stays in the shape the pose was solved in:
## the pole goes where that solve had the elbow or knee and the limb's turn is searched locally, as
## between two poses (PoseBlend.steered_pole, Limb.set_blending). Searched afresh every frame, a
## gripping arm whose best and second-best elbow are nearly as good flips between them with a
## breath.
func _steady_limbs(rig: CharacterRig, k: int) -> void:
	if solved.size() != sequence.steps.size():
		return
	var mine: Dictionary = solved[k].get(rig.character_id, {})
	for key in rig.limbs:
		var limb: Limb = rig.limbs[key]
		if limb.mode != Limb.Mode.IK or not mine.has(key):
			continue
		limb.set_blending(true)
		limb.pole.global_position = PoseBlend.steered_pole(rig, limb, mine[key], mine[key], 0.0, limb.pole.global_position)


## How fast a figure's root was going as it reached step `k` (SETTLE of the blend's even speed),
## in metres and radians per second, or {} when it did not rest there or was falling into it.
func _arrival_speed(k: int, id: String) -> Dictionary:
	var hold := float(sequence.steps[k].get("hold", 0.0))
	if hold <= 0.0 and k < sequence.steps.size() - 1:
		return {}
	var st := timing(sequence, sequence.step_start(k) - 1e-3)
	if st["from"] != k - 1 or st["to"] != k:
		return {}
	var ca := _character(_step_pose(k - 1), id)
	var cb := _character(_step_pose(k), id)
	if ca.is_empty() or cb.is_empty() or not ca.get("fall", {}).is_empty() or not cb.get("fall", {}).is_empty():
		return {}
	var ea := PoseBlend.root_euler(ca.get("root", {}))
	var eb := PoseBlend.root_euler(cb.get("root", {}))
	if PoseBlend.is_fall(ea) or PoseBlend.is_fall(eb):
		return {}
	# The root's own clock: from when it left (the lead into the hold before) to the pose.
	var trans := float(sequence.steps[k].get("transition", 0.0))
	var hold_a := float(sequence.steps[k - 1].get("hold", 0.0))
	var rest_a := hold_a > 0.0 or k - 1 == 0
	var span := trans + (float(CHANNEL_TIMING["root"][0]) * minf(hold_a, LEAD) if rest_a else 0.0)
	if span <= 1e-6:
		return {}
	var rate := SETTLE / span
	# The root's curve ends on the straight way from the pose before (rest_b: no neighbour after).
	var p1 := PoseFile.array_to_vec(ca["root"].get("pos", [0, 0, 0]))
	var p2 := PoseFile.array_to_vec(cb["root"].get("pos", [0, 0, 0]))
	var times: Array = st["times"]
	var p0 := p1
	if not rest_a:
		var cp := _character(_step_pose(k - 2), id)
		if not cp.is_empty():
			p0 = PoseFile.array_to_vec(cp["root"].get("pos", [0, 0, 0]))
	var at := func(w: float) -> Vector3: return p1.cubic_interpolate_in_time(p2, p0, p2, w, times[1], times[0], times[2])
	var dpos: Vector3 = (at.call(1.0) - at.call(0.999)) / 0.001
	return {"pos": dpos * rate, "yaw": PoseBlend.yaw_turn(ea.y, eb.y) * rate}


func _character(pose: Dictionary, id: String) -> Dictionary:
	for c in pose.get("characters", []):
		if c.get("id") == id:
			return c
	return {}


## Each part of a body on its own clock (PoseBlend.CHANNELS). A person does not move all of a piece:
## the hips start first — into the end of the hold before, while the hands are still where the
## pose left them — and the spine and head go with them; the feet step a little later and are down
## before the body has settled over them; the arms follow the body and arrive last, the fingers
## last of all. Each part eases on a minimum-jerk course (Sequence.ease_motion), so nothing starts
## or stops with a jolt. Waypoints (steps held for no time) are passed through at speed by every
## part together, and every part is exactly on every pose at that pose's time.
##   [lead, delay, early]: how much of the hold before (up to LEAD seconds) a part starts in; how
##   late it starts, and how early it arrives, as shares of the transition. Only next to a pose the
##   technique rests on.
const LEAD := 0.12
const CHANNEL_TIMING := {
	"root": [1.0, 0.0, 0.0],
	"spine": [0.7, 0.0, 0.04],
	"head": [0.8, 0.0, 0.08],
	"legs": [0.3, 0.06, 0.14],
	"arms": [0.0, 0.10, 0.0],
	"hands": [0.0, 0.16, 0.0],
}


## Where the timeline is at `time`: {"from", "to", "u" (the blend as one), "channels": {part: u},
## "times": [prev, to, next] seconds from the pose `from` was reached}. On a pose that nothing has
## left yet, from == to.
static func timing(seq: Sequence, time: float) -> Dictionary:
	var n := seq.steps.size()
	var t := maxf(time, 0.0)
	var start := []
	for i in n:
		start.append(seq.step_start(i))
	if n < 2 or t >= start[n - 1] - 1e-6:
		return {"from": n - 1, "to": n - 1, "u": 0.0, "channels": {}, "times": []}
	var k := 1
	while k < n - 1 and t >= start[k] - 1e-6:
		k += 1
	var hold_a := float(seq.steps[k - 1].get("hold", 0.0))
	var hold_b := float(seq.steps[k].get("hold", 0.0))
	var trans := float(seq.steps[k].get("transition", 0.0))
	var leave: float = start[k - 1] + hold_a       # when the plain blend leaves pose a
	var rest_a := hold_a > 0.0 or k - 1 == 0
	var rest_b := hold_b > 0.0 or k == n - 1
	var raw := 1.0 if trans <= 0.0 else clampf((t - leave) / trans, 0.0, 1.0)
	if t - leave < 1e-6:
		raw = 0.0
	var channels := {}
	var any := raw > 0.0
	for c in CHANNEL_TIMING:
		var p: Array = CHANNEL_TIMING[c]
		var s0 := leave
		var s1: float = start[k]
		if rest_a:
			s0 += -float(p[0]) * minf(hold_a, LEAD) + float(p[1]) * trans
		if rest_b:
			s1 -= float(p[2]) * trans
		var r := 1.0 if s1 - s0 <= 1e-6 else clampf((t - s0) / (s1 - s0), 0.0, 1.0)
		if t - s0 < 1e-6:
			r = 0.0
		channels[c] = Sequence.ease_motion(r, rest_a, rest_b, SETTLE if c == "root" else 0.0)
		any = any or channels[c] > 0.0
	if not any:
		return {"from": k - 1, "to": k - 1, "u": 0.0, "channels": {}, "times": []}
	var t_b: float = start[k] - start[k - 1]
	var t_pre: float = -(start[k - 1] - start[k - 2]) if k >= 2 else -t_b
	var t_post: float = t_b + (start[k + 1] - start[k]) if k + 1 < n else 2.0 * t_b
	return {"from": k - 1, "to": k, "u": Sequence.ease_motion(raw, rest_a, rest_b), "channels": channels,
		"times": [t_pre, t_b, t_post], "rest_a": rest_a, "rest_b": rest_b,
		"fall_u": Sequence.ease_through(raw, rest_a, rest_b)}


## The pose of step `i`, or an empty dictionary past either end of the technique. The blend uses
## the steps on either side of a transition to curve the root through it.
func _step_pose(i: int) -> Dictionary:
	if sequence == null or i < 0 or i >= sequence.steps.size():
		return {}
	return poses.get(sequence.steps[i]["pose"], {})
