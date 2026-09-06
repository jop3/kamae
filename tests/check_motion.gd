extends SceneTree
## Plausibility of the motion, not only of the poses (src/rig/Anatomy.gd, tests/check_anatomy.gd).
##
## check_anatomy.gd checks every committed pose. A sequence is played as a blend between those
## poses, and a blend between two plausible poses is not itself plausible: a limb can sweep
## straight through a body on its way from one keyframe to the next, and the video shows every
## one of those frames. This walks each sequence at the export frame rate and runs the same
## checks on every frame, so an in-between that breaks a body fails the build.
##
## MOTION_SEQ=<slug> checks one sequence; MOTION_VERBOSE=1 lists every offending frame.

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)

## Frames that are still not plausible, per sequence, as the number that are wrong today.
## Every one of them is a *gripping* arm during a re-grip: the grip ramps out, the hand slerps
## across to its next hold, and the straight line it takes crosses the partner. MotionClearance
## deliberately will not move a gripping hand — that would tear it off what it holds — so these
## are fixed by giving the technique an intermediate pose that says where the hand travels
## (tools/add_step.gd, docs/handoff.md). One frame of jo_dori is a different fault: the arm is
## IK, and the solver rolls the humerus 178° on its way between two poses that are both fine, so
## the fix is in the IK path and not in the blend. The count may only go down: a sequence that
## beats its number fails and asks for the number to be lowered, so this cannot quietly rot.
const OUTSTANDING := {
	"jo_dori": 8,   ## seven of them; the eighth is an IK-driven shoulder rolled 178°, below
	"katatedori_ikkyo": 6,
	"katatedori_shihonage_irimi": 12,
	"tachi_dori": 10,
	## Uke now goes round Tori instead of through him, which is the technique; what is left is
	## his arms tangling with Tori's body as he is led round still holding both wrists. That is
	## the authoring question this fixture has never answered: when the grip goes, and whether
	## Uke goes down (docs/handoff.md).
	"ushiro_ryotedori_zenponage": 11,
}

var scene: PosingScene
var ctrl: PoseController
var director: GripDirector
var player: SequencePlayer
const SEQS := "res://sequences"
const POSES := "res://poses"
## The export frame rate: every frame the video shows is a frame the checks see.
const FPS := float(MovieExport.FPS)
## Frames whose problems are listed in the summary before it says "and N more".
const LISTED := 4


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
	var only := OS.get_environment("MOTION_SEQ")
	var verbose := OS.get_environment("MOTION_VERBOSE") == "1"
	for f in _files(SEQS):
		var slug: String = f.get_basename()
		if only != "" and slug != only:
			continue
		var seq := Sequence.load(SEQS.path_join(f))
		if seq == null:
			check(false, "%s loads" % f)
			continue
		var missing: Array = player.load_sequence(seq, POSES)
		if not missing.is_empty():
			check(false, "%s names poses that are saved (missing %s)" % [slug, missing])
			continue
		# The first pose defines the cast; the blend only moves what already exists.
		PoseFile.apply(player.poses[seq.steps[0]["pose"]], scene, director, ctrl)
		await settle(4)
		var bad := []                  # ["t=1.60 <problem>; <problem>", ...]
		for i in int(round(seq.duration() * FPS)) + 1:
			var t := float(i) / FPS
			player.seek(t)
			await settle(3)
			var probs := _without_tracked_wrists(Anatomy.scene_problems(scene, director))
			if not probs.is_empty():
				bad.append("t=%.2f %s" % [t, "; ".join(probs)])
				if verbose:
					print("      ", bad[-1])
		var budget: int = OUTSTANDING.get(slug, 0)
		var detail := ""
		if bad.size() > budget:
			detail = " — " + "\n      ".join(bad.slice(0, LISTED))
			if bad.size() > LISTED:
				detail += "\n      and %d more frames" % (bad.size() - LISTED)
		elif bad.size() < budget:
			detail = " — better than the %d frames on record: lower it in OUTSTANDING" % budget
		check(bad.size() == budget, "%s: %d of %d frames not plausible, %d on record%s"
			% [slug, bad.size(), int(round(seq.duration() * FPS)) + 1, budget, detail])
	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


## The wrists bent past their limit are a fault in the poses themselves, tracked pose by pose in
## tests/check_anatomy.gd; a blend between two poses with the same bent wrist has it on every
## frame and would swamp what this check is for. Every other joint problem still counts here.
func _without_tracked_wrists(probs: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for p in probs:
		if p.contains("Hand swung") or p.contains("Hand twisted"):
			continue
		out.append(p)
	return out


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
