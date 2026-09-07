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

## Frames that are still not plausible, per sequence, as the number that are wrong today. The
## count may only go down: a sequence that beats its number fails and asks for the number to be
## lowered, so this cannot quietly rot. MOTION_VERBOSE=1 lists every frame.
##
## Most are a *gripping* arm during a re-grip: the grip ramps out, the hand slerps across to its
## next hold, and the straight line it takes crosses the partner. MotionClearance deliberately
## will not move a gripping hand — that would tear it off what it holds — so these are fixed by
## giving the technique an intermediate pose that says where the hand travels (tools/add_step.gd,
## docs/handoff.md).
##
## The numbers changed when the joints got their anatomy (src/rig/Joints.gd), in both directions,
## and for two reasons worth knowing. A joint carried past its range *between* two poses is now
## counted (kumijo's supinated forearm, kumitachi's shoulder), where before every wrist message
## was dropped wholesale; only joints already refused at the keyframes are left to
## check_anatomy.gd. And an elbow now goes where the shoulder and wrist allow rather than where
## the pole put it, so the sweep of an arm between two poses is not the sweep it was: ikkyo lost
## a frame, jo dori and shihonage gained several, mostly a re-gripping forearm through the
## partner while its wrist is refused. Every one of them is listed by MOTION_VERBOSE=1, and each
## is a pose to author, not a rule to loosen.
const OUTSTANDING := {
	"jo_dori": 18,
	"katatedori_ikkyo": 9,   ## the grip is the catalogue's now; two frames of a wrist at its edge as the arm is raised
	"katatedori_shihonage_irimi": 18,   ## re-authored after the shoulder girdle: 26 before it, 51 with it, 18 now
	"kumijo": 9,
	"kumitachi": 2,
	"tachi_dori": 11,
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
## A joint a blend carries this far past its range, degrees, is a frame worth fixing; less is
## a joint riding its edge between two poses that both sit on it, held there on screen anyway.
const SLACK := 3.0
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
		var known: Dictionary = await _keyframe_refusals(seq)
		PoseFile.apply(player.poses[seq.steps[0]["pose"]], scene, director, ctrl)
		await settle(4)
		var bad := []                  # ["t=1.60 <problem>; <problem>", ...]
		for i in int(round(seq.duration() * FPS)) + 1:
			var t := float(i) / FPS
			player.seek(t)
			await settle(3)
			var probs := _without_keyframe_refusals(Anatomy.scene_problems(scene, director), known)
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


## A joint asked for more than it has in a keyframe (a wrist bent 130° onto a jo) is a fault in
## that pose, tracked pose by pose in tests/check_anatomy.gd; a blend between two poses with
## the same bent wrist has it on every frame and would swamp what this check is for. So the
## joints refused in any keyframe of the sequence are collected first, and a refusal of one of
## those joints is not counted here. A joint refused only *between* the poses still is.
func _keyframe_refusals(seq: Sequence) -> Dictionary:
	var known := {}
	for step in seq.steps:
		PoseFile.apply(player.poses[step["pose"]], scene, director, ctrl)
		await settle(4)
		for rig in scene.characters:
			if rig.visible and rig.joint_limits:
				for bone in rig.joint_limits.refused:
					known["%s: %s" % [rig.character_id, bone]] = true
	return known


func _without_keyframe_refusals(probs: PackedStringArray, known: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for p in probs:
		var is_refusal := p.contains(", past ")
		if is_refusal:
			var head := p.substr(0, p.find(":", p.find(":") + 1))   # "uke1: LeftHand"
			if known.has(head):
				continue
			var rig: CharacterRig = scene.get_character(head.get_slice(": ", 0))
			var bone := head.get_slice(": ", 1)
			if rig and rig.joint_limits and rig.joint_limits.refused.has(bone):
				var r: Dictionary = rig.joint_limits.refused[bone]
				var e := Joints.excess(rig.joints.specs[bone], r["wanted"])
				if maxf(e["flex"], maxf(e["abd"], e["twist"])) < SLACK:
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
