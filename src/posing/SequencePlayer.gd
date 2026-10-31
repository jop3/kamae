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
func prepare() -> void:
	solved = []
	if sequence == null:
		return
	var tree := get_tree()
	var found := []
	for i in sequence.steps.size():
		apply_time(sequence.step_start(i))
		for _f in 4:
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
	if camera != null and sequence.camera == "per_pose":
		var ca = a.get("camera")
		var cb = b.get("camera")
		if ca is Dictionary or cb is Dictionary:
			camera.apply_state(OrbitCamera.blend_state(ca if ca is Dictionary else {}, cb if cb is Dictionary else {}, st["u"]))


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
	"root": [1.0, 0.0, 0.06],
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
		var p: Array = CHANNEL_TIMING[c] if OS.get_environment("KAMAE_SYNC") != "1" else [0.0, 0.0, 0.0]
		var s0 := leave
		var s1: float = start[k]
		if rest_a:
			s0 += -float(p[0]) * minf(hold_a, LEAD) + float(p[1]) * trans
		if rest_b:
			s1 -= float(p[2]) * trans
		var r := 1.0 if s1 - s0 <= 1e-6 else clampf((t - s0) / (s1 - s0), 0.0, 1.0)
		if t - s0 < 1e-6:
			r = 0.0
		channels[c] = Sequence.ease_motion(r, rest_a, rest_b)
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
