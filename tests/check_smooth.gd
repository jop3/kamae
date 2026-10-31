extends SceneTree
## How smoothly the figures move: the blends measured as motion, not as poses.
##
## check_motion.gd asks whether each frame is a plausible body and check_floor.gd whether it is
## above the mat. Neither sees a figure that is plausible on every frame and still moves like a
## machine: every joint starting and stopping at once, velocities that jump at each keyframe,
## hands on straight lines, holds frozen solid. This plays a sequence the way the video does (one
## frame at a time, at the export frame rate), reads where every joint actually is after the
## solve, and scores the motion:
##
##   jerk     RMS jerk of the tracked joints' positions, m/s³ — the standard smoothness measure
##            (people minimise it; a velocity that jumps between two frames is a spike of it)
##   rot      RMS angular jerk of the joints' own rotations (each bone in its parent), rad/s³
##   jolts    frames on which some joint's jerk is over JOLT (or its angular jerk over JOLT_ROT):
##            a visible jolt, as a count of frames
##   still    share of frames on which nothing at all moves (a frozen hold)
##   spread   per transition, how far apart in time the body's parts pass the middle of their
##            travel, seconds (0: everything moves in lockstep)
##   lead     per transition, how much earlier the hips pass the middle of their travel than the
##            hands, seconds (people move from the centre: positive)
##   arc      per hand move longer than ARC_MIN, the path's greatest distance from the straight
##            line between its ends as a share of that line (0: a ruler-straight hand)
##
## It also checks that every keyframe is reached exactly: at each step's time, the bones and the
## root are the saved pose's (the stills are taken there, and the handout shows the saved pose).
##
##   SMOOTH_SEQS_DIR=<dir> SMOOTH_POSES_DIR=<dir> godot --headless -s tests/check_smooth.gd
##
## Defaults to the committed sequences. SMOOTH_SEQ=<slug> checks one, SMOOTH_VERBOSE=1 lists the
## jolts frame by frame, SMOOTH_CSV=<path> writes every joint's track for plotting.

const FPS := float(MovieExport.FPS)
## Jerk above which a frame is a jolt, m/s³. A hand reaching 40 cm in half a second on a
## minimum-jerk course peaks at about 240; a velocity that jumps by 0.5 m/s between two frames
## at 30 fps is 450 and more.
const JOLT := 400.0
## The same for a joint's own rotation, rad/s³ (a forearm turning 90° in half a second on a
## minimum-jerk course peaks near 90).
const JOLT_ROT := 250.0
## A frame on which no joint moves more than this, m/s and rad/s, is frozen.
const STILL_SPEED := 0.01
const STILL_TURN := 0.02
## A part that travels less than this in a transition is not counted in its spread, metres.
const MOVES := 0.04
## Hand moves shorter than this are not judged for their arc, metres.
const ARC_MIN := 0.15
## A keyframe is exact when every joint is within this of where the saved pose puts it, metres.
const KEY_POS := 1e-3

const JOINTS := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"RightShoulder", "LeftShoulder", "RightUpperArm", "LeftUpperArm", "RightLowerArm", "LeftLowerArm",
	"RightHand", "LeftHand", "RightUpperLeg", "LeftUpperLeg", "RightLowerLeg", "LeftLowerLeg",
	"RightFoot", "LeftFoot"]
## The parts whose timing within a transition is compared (spread, lead).
const PARTS := ["Hips", "UpperChest", "Head", "RightHand", "LeftHand", "RightFoot", "LeftFoot"]

var failures := 0
var scene: PosingScene
var ctrl: PoseController
var director: GripDirector
var player: SequencePlayer


func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)


func _initialize() -> void:
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	scene = PosingScene.new(); world.add_child(scene)
	var cam := Camera3D.new(); world.add_child(cam)
	var gizmo := RotationGizmo.new(); world.add_child(gizmo)
	ctrl = PoseController.new(); world.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	director = GripDirector.new(); world.add_child(director); director.setup(scene, ctrl)
	player = SequencePlayer.new(); world.add_child(player); player.setup(scene, director)
	await physics_frame
	var env := func(k: String, d: String) -> String: return OS.get_environment(k) if OS.get_environment(k) != "" else d
	var seqs_dir: String = env.call("SMOOTH_SEQS_DIR", "res://sequences")
	var poses_dir: String = env.call("SMOOTH_POSES_DIR", "res://poses")
	var only: String = env.call("SMOOTH_SEQ", "")
	var verbose: bool = env.call("SMOOTH_VERBOSE", "0") == "1"
	var csv: String = env.call("SMOOTH_CSV", "")
	for f in _files(seqs_dir):
		var slug: String = f.get_basename()
		if only != "" and slug != only:
			continue
		var seq := Sequence.load(seqs_dir.path_join(f))
		if seq == null or not player.load_sequence(seq, poses_dir).is_empty():
			check(false, "%s loads with its poses" % slug)
			continue
		PoseFile.apply(player.poses[seq.steps[0]["pose"]], scene, director, ctrl)
		await settle(4)
		var key_err: Dictionary = await _keyframe_error(seq)
		check(key_err["pos"] < KEY_POS and key_err["root"] < KEY_POS,
			"%s: every keyframe is shown as saved (worst joint %.4f m at %s, root %.4f m)"
			% [slug, key_err["pos"], key_err["where"], key_err["root"]])
		PoseFile.apply(player.poses[seq.steps[0]["pose"]], scene, director, ctrl)
		await settle(4)
		var tracks: Dictionary = await _record(seq)
		var s := score(tracks, seq)
		print("SMOOTH %s: jerk %.0f m/s³, rot %.0f rad/s³, jolts %d of %d frames, still %.0f%%, spread %.3f s, lead %+.3f s, arc %.3f"
			% [slug, s["jerk"], s["rot"], s["jolts"].size(), s["frames"], s["still"] * 100.0,
				s["spread"], s["lead"], s["arc"]])
		for line in (s["jolts"] if verbose else s["jolts"].slice(0, 6)):
			print("    ", line)
		if not verbose and s["jolts"].size() > 6:
			print("    and %d more frames" % (s["jolts"].size() - 6))
		if csv != "":
			_write_csv(csv.replace("{slug}", slug), tracks)
	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


## Plays the sequence frame by frame the way the movie export does (one apply per frame, the
## solve and the grips following in that frame) and records, per character and joint, the world
## position and the rotation in its parent after the solve.
func _record(seq: Sequence) -> Dictionary:
	var n := int(round(seq.duration() * FPS)) + 1
	var tracks := {}     # "id/Joint" -> {"pos": [Vector3], "rot": [Quaternion]}
	for i in n:
		player.apply_time(float(i) / FPS)
		await settle(2)
		for rig in scene.characters:
			if not rig.visible:
				continue
			for j: String in JOINTS:
				if rig.skeleton.find_bone(j) < 0:
					continue
				var key := "%s/%s" % [rig.character_id, j]
				if not tracks.has(key):
					tracks[key] = {"pos": [], "rot": []}
				var xf := rig.bone_world_transform(j)
				var parent := rig.skeleton.get_bone_parent(rig.skeleton.find_bone(j))
				var local := xf.basis
				if parent >= 0:
					local = rig.bone_world_transform(rig.skeleton.get_bone_name(parent)).basis.inverse() * xf.basis
				tracks[key]["pos"].append(xf.origin)
				tracks[key]["rot"].append(local.get_rotation_quaternion())
	return tracks


## The scores of one sequence's tracks (see the top of the file).
static func score(tracks: Dictionary, seq: Sequence) -> Dictionary:
	var sum_j := 0.0
	var count_j := 0
	var sum_r := 0.0
	var count_r := 0
	var frames := 0
	var jolt_at := {}       # frame -> [description]
	var moving := {}        # frame -> true
	for key: String in tracks:
		var p: Array = tracks[key]["pos"]
		var q: Array = tracks[key]["rot"]
		frames = p.size()
		var v := []
		var w := []
		for i in p.size() - 1:
			v.append((p[i + 1] - p[i]) * FPS)
			var dq: Quaternion = q[i + 1] * q[i].inverse()
			if dq.w < 0.0:
				dq = -dq
			w.append(dq.get_axis() * dq.get_angle() * FPS if dq.get_angle() > 1e-6 else Vector3.ZERO)
			if v[-1].length() > STILL_SPEED or w[-1].length() > STILL_TURN:
				moving[i] = true
		for i in range(2, v.size() - 1):
			# Jerk at frame i from four positions: the third difference.
			var jerk: Vector3 = (v[i + 1] - 2.0 * v[i] + v[i - 1]) * FPS * FPS
			var jrot: Vector3 = (w[i + 1] - 2.0 * w[i] + w[i - 1]) * FPS * FPS
			sum_j += jerk.length_squared(); count_j += 1
			sum_r += jrot.length_squared(); count_r += 1
			if jerk.length() > JOLT or jrot.length() > JOLT_ROT:
				if not jolt_at.has(i):
					jolt_at[i] = []
				jolt_at[i].append("%s %.0f%s" % [key, jerk.length() if jerk.length() > JOLT else jrot.length(),
					" m/s³" if jerk.length() > JOLT else " rad/s³"])
	var jolts := []
	var at: Array = jolt_at.keys()
	at.sort()
	for i: int in at:
		var l: Array = jolt_at[i]
		jolts.append("t=%.2f %s%s" % [float(i) / FPS, ", ".join(l.slice(0, 3)), " and %d more" % (l.size() - 3) if l.size() > 3 else ""])
	# Timing within each transition: from the previous keyframe to this one.
	var spreads := []
	var leads := []
	var arcs := []
	var ids := {}
	for key: String in tracks:
		ids[key.get_slice("/", 0)] = true
	for k in range(1, seq.steps.size()):
		var i0 := int(round(seq.step_start(k - 1) * FPS))
		var i1 := mini(int(round(seq.step_start(k) * FPS)), frames - 1)
		if i1 - i0 < 3:
			continue
		for id: String in ids:
			var half := {}
			for part: String in PARTS:
				var key := "%s/%s" % [id, part]
				if not tracks.has(key):
					continue
				var p: Array = tracks[key]["pos"]
				var cum := [0.0]
				for i in range(i0, i1):
					cum.append(cum[-1] + (p[i + 1] - p[i]).length())
				if cum[-1] < MOVES:
					continue
				for i in cum.size():
					if cum[i] >= cum[-1] * 0.5:
						# Linear within the frame that crosses the half.
						var f: float = 0.0 if i == 0 else (cum[-1] * 0.5 - cum[i - 1]) / maxf(cum[i] - cum[i - 1], 1e-9)
						half[part] = (float(i0 + i - 1) + f) / FPS
						break
				if part.ends_with("Hand"):
					var chord: Vector3 = p[i1] - p[i0]
					if chord.length() >= ARC_MIN:
						var dev := 0.0
						for i in range(i0, i1 + 1):
							var r: Vector3 = p[i] - p[i0]
							dev = maxf(dev, (r - chord.normalized() * r.dot(chord.normalized())).length())
						arcs.append(dev / chord.length())
			if half.size() >= 2:
				var lo := INF
				var hi := -INF
				for part in half:
					lo = minf(lo, half[part]); hi = maxf(hi, half[part])
				spreads.append(hi - lo)
			if half.has("Hips"):
				for hand in ["RightHand", "LeftHand"]:
					if half.has(hand):
						leads.append(half[hand] - half["Hips"])
	var mean := func(a: Array) -> float:
		var s := 0.0
		for x in a: s += x
		return s / a.size() if a.size() > 0 else 0.0
	return {
		"jerk": sqrt(sum_j / maxf(count_j, 1)), "rot": sqrt(sum_r / maxf(count_r, 1)),
		"jolts": jolts, "frames": frames, "still": 1.0 - float(moving.size()) / maxf(frames - 1, 1),
		"spread": mean.call(spreads), "lead": mean.call(leads), "arc": mean.call(arcs),
	}


## The worst difference between what the player shows at each step's time and the saved pose
## applied on its own: every tracked joint, after the solve, by how far it is from where the
## pose puts it (metres), and the worst root.
func _keyframe_error(seq: Sequence) -> Dictionary:
	var worst := {"pos": 0.0, "root": 0.0, "where": ""}
	for k in seq.steps.size():
		var pose: Dictionary = player.poses[seq.steps[k]["pose"]]
		PoseFile.apply(pose, scene, director, ctrl)
		await settle(4)
		var want := _joint_positions()
		player.seek(seq.step_start(k))
		await settle(4)
		var got := _joint_positions()
		for key: String in want:
			var d: float = want[key].distance_to(got.get(key, want[key]))
			if d > worst["pos"]:
				worst["pos"] = d
				worst["where"] = "%s %s" % [seq.steps[k]["pose"], key]
		for c in pose.get("characters", []):
			var rig: CharacterRig = scene.get_character(c["id"])
			if rig != null and rig.visible:
				worst["root"] = maxf(worst["root"], rig.position.distance_to(PoseFile.array_to_vec(c["root"]["pos"])))
	return worst


func _joint_positions() -> Dictionary:
	var out := {}
	for rig in scene.characters:
		if not rig.visible:
			continue
		for j: String in JOINTS:
			if rig.skeleton.find_bone(j) >= 0:
				out["%s/%s" % [rig.character_id, j]] = rig.bone_world_transform(j).origin
	return out


func _write_csv(path: String, tracks: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("track,frame,x,y,z,qx,qy,qz,qw")
	for key: String in tracks:
		var p: Array = tracks[key]["pos"]
		var q: Array = tracks[key]["rot"]
		for i in p.size():
			f.store_line("%s,%d,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f" % [key, i, p[i].x, p[i].y, p[i].z, q[i].x, q[i].y, q[i].z, q[i].w])
	f.close()


func _files(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d:
		for f in d.get_files():
			if f.ends_with(".json"):
				out.append(f)
	out.sort()
	return out


func settle(frames: int = 2) -> void:
	for i in frames:
		await process_frame
