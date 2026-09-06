extends SceneTree
## Inserts an intermediate pose into a technique at a chosen moment.
##
##   godot --headless -s tools/add_step.gd -- <sequence slug> <seconds> [options]
##     --name <pose name>       what to call the new pose (default "<Technique> Mellan")
##     --poses-dir <dir>        where poses are read and the new one is written
##     --sequences-dir <dir>    where the sequence is read and written
##
## Some things a blend cannot fix. A gripping hand is carried across to its next hold in a
## straight line, and MotionClearance will not push it aside because the grip owns it; if that
## line crosses the partner, only saying where the hand actually travels will do, and that is a
## keyframe. This bakes the pose the technique is already showing at `seconds` — solved, with the
## clearance applied — and splits the transition around it, so the instructor starts from what
## is there and moves the offending limb rather than building a pose from nothing.
##
## The sequence keeps its total length: the new step takes its transition out of the one it
## splits, and holds for nothing until someone gives it a hold.

var scene: PosingScene
var ctrl: PoseController
var director: GripDirector
var player: SequencePlayer
var cam: OrbitCamera


func _initialize() -> void:
	var args := _args()
	if args.size() < 2:
		push_error("usage: add_step.gd -- <sequence slug> <seconds> [--name N] [--poses-dir D] [--sequences-dir D]")
		quit(1)
		return
	var slug: String = args[0]
	var at := float(args[1])
	var poses_dir := _opt(args, "--poses-dir", "res://poses")
	var seqs_dir := _opt(args, "--sequences-dir", "res://sequences")
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	scene = PosingScene.new(); world.add_child(scene)
	cam = OrbitCamera.new(); world.add_child(cam)
	var gizmo := RotationGizmo.new(); world.add_child(gizmo)
	ctrl = PoseController.new(); world.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	director = GripDirector.new(); world.add_child(director); director.setup(scene, ctrl)
	player = SequencePlayer.new(); world.add_child(player); player.setup(scene, director)
	await physics_frame

	var seq_path := seqs_dir.path_join(slug + ".json")
	var seq := Sequence.load(seq_path)
	if seq == null:
		push_error("Cannot read %s" % seq_path)
		quit(1)
		return
	var missing: Array = player.load_sequence(seq, poses_dir)
	if not missing.is_empty():
		push_error("%s names poses that are not saved: %s" % [slug, missing])
		quit(1)
		return
	var st := seq.state_at(at)
	if st["from"] == st["to"]:
		push_error("%.2f s is on a hold, not in a transition: nothing to split" % at)
		quit(1)
		return
	if seq.steps.size() >= Sequence.MAX_STEPS:
		push_error("%s already has the %d steps a technique may have" % [slug, Sequence.MAX_STEPS])
		quit(1)
		return

	PoseFile.apply(player.poses[seq.steps[0]["pose"]], scene, director, ctrl)
	await _settle(4)
	player.seek(at)
	await _settle(6)   # the IK, the grips and the clearance all settle before the pose is read

	var name := _opt(args, "--name", "%s Mellan" % seq.name)
	var data: Dictionary = await PoseFile.capture_baked(scene, director, cam, name)
	var pose_slug := PoseFile.slugify(name)
	var pose_path := poses_dir.path_join(pose_slug + ".json")
	if PoseFile.save(pose_path, data) != OK:
		push_error("Could not write %s" % pose_path)
		quit(1)
		return

	# The new step takes its transition out of the one it splits, so the technique still runs for
	# as long as it did.
	var to: int = st["to"]
	var whole := float(seq.steps[to].get("transition", 0.0))
	var before: float = at - (seq.step_start(to) - whole)
	seq.steps[to]["transition"] = maxf(whole - before, 0.0)
	seq.steps.insert(to, {"pose": pose_slug, "transition": before, "hold": 0.0})
	if seq.save(seq_path) != OK:
		push_error("Could not write %s" % seq_path)
		quit(1)
		return
	print("wrote %s and split the transition into step %d (%.2f s + %.2f s)"
		% [pose_path, to + 1, before, seq.steps[to + 1]["transition"]])
	print("open it in the tool, move what the blend could not, and save the pose again")
	quit()


func _args() -> Array:
	var raw := OS.get_cmdline_user_args()
	var out := []
	for a in raw:
		out.append(a)
	return out


func _opt(args: Array, flag: String, fallback: String) -> String:
	var i := args.find(flag)
	return str(args[i + 1]) if i >= 0 and i + 1 < args.size() else fallback


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame
