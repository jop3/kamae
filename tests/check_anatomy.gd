extends SceneTree
## Plausibility of every committed pose (poses/): no joint out of range or bent the wrong way,
## no limb through a body, no weapon through anyone, no bone scale, and a CPU-skinned mesh
## that keeps its shape. Headless and fast. See src/rig/Anatomy.gd for the rules.

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)

## What the committed poses still get wrong, pose by pose, so the measurement stays on and nothing
## new or worse can slip in. An entry that stops happening is itself a failure, so this cannot rot:
## a fix lands with its entry removed.
##
## Every entry is a joint asked for more than it has (src/rig/Joints.gd). Each is *held* at its
## range on screen by JointLimits, so none of these is drawn; what is drawn is a hand short of
## the orientation its grip or hold asked for, by exactly what the wrist could not give. Nearly
## all are wrists, and they are one thing, not thirty: a hand placed on a weapon or wrapped round
## a wrist has its position and its orientation both decided for it, and the arm now does all it
## anatomically can — the forearm rolls, the elbow goes round (LimbTurn) — before the wrist is
## asked for the rest. What is left is where no elbow position helps: Uke standing so far from
## Tori that his arm is straight (a katatedori needs the forearm across the wrist, so the elbow
## out), or a two-handed hold rolled about the shaft to an angle no wrist reaches. Those are
## decisions about the technique — where Uke stands, how the weapon is held — and the
## instructor's to make; see docs/handoff.md. The shoulders are the same: an arm behind the
## back (ushiro) or across the body further than a shoulder goes. Shihonage was re-authored
## (the arm raised forward past the face, the hand folded down behind the shoulder) and lost
## most of its entries; what is left is Uke's forearm rolled as the grip turns it.
const OUTSTANDING := {
	"jo_dori_kake": ["uke1: LeftUpperArm: shoulder internal rotation"],
	"jo_dori_tsuki": ["uke1: LeftHand: wrist extension"],
	"jo_dori_uke": ["tori: RightHand: wrist extension", "uke1: LeftHand: wrist extension"],
	"katatedori_ikkyo_grepp": ["uke1: LeftHand: wrist flexion"],
	"katatedori_ikkyo_kake": ["tori: LeftUpperArm: shoulder adduction", "tori: LeftHand: wrist extension"],
	"katatedori_shihonage_kake": ["tori: LeftHand: wrist radial deviation", "uke1: LeftUpperArm: shoulder adduction", "uke1: LeftLowerArm: elbow supination"],
	"katatedori_shihonage_kuzushi": ["uke1: LeftLowerArm: elbow pronation"],
	"kumijo_kamae": ["tori: LeftHand: wrist extension", "uke1: LeftHand: wrist extension"],
	"kumijo_tsuki": ["tori: LeftUpperArm: shoulder adduction", "tori: LeftHand: wrist extension", "uke1: LeftHand: wrist extension"],
	"kumitachi_awase": ["tori: LeftHand: wrist extension", "tori: RightHand: wrist extension", "uke1: LeftHand: wrist extension", "uke1: RightHand: wrist extension"],
	"kumitachi_uchi": ["tori: LeftHand: wrist extension", "tori: RightHand: wrist extension", "uke1: LeftHand: wrist extension", "uke1: RightHand: wrist extension"],
	"ryotemochi_grepp": ["uke1: RightHand: wrist flexion", "uke2: LeftHand: wrist flexion"],
	"tachi_dori_irimi": ["uke1: LeftHand: wrist extension", "uke1: RightHand: wrist extension"],
	"tachi_dori_kamae": ["uke1: LeftHand: wrist extension", "uke1: RightHand: wrist extension"],
	"ushiro_ryotedori_zenponage_grepp": ["uke1: LeftHand: wrist flexion", "uke1: RightHand: wrist flexion"],
	"ushiro_ryotedori_zenponage_kake": ["uke1: LeftUpperArm: shoulder extension", "uke1: RightUpperArm: shoulder extension", "uke1: RightHand: wrist extension"],
	"ushiro_ryotedori_zenponage_kuzushi": ["uke1: LeftHand: wrist radial deviation", "uke1: RightHand: wrist radial deviation"],
	"ushiro_ryotedori_zenponage_tenkan": ["uke1: LeftUpperArm: shoulder extension", "uke1: RightUpperArm: shoulder extension", "uke1: LeftLowerArm: elbow supination", "uke1: LeftHand: wrist ulnar deviation", "uke1: RightHand: wrist flexion"],
}

var scene: PosingScene
var ctrl: PoseController
var director: GripDirector
const POSES := "res://poses"


func _initialize() -> void:
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	scene = PosingScene.new(); world.add_child(scene)
	var cam := Camera3D.new(); world.add_child(cam)
	var gizmo := RotationGizmo.new(); world.add_child(gizmo)
	ctrl = PoseController.new(); world.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	director = GripDirector.new(); world.add_child(director); director.setup(scene, ctrl)
	await physics_frame
	for f in _files(POSES):
		var slug: String = f.get_basename()
		var data := PoseFile.load(POSES.path_join(f))
		if data.is_empty():
			check(false, "%s loads" % f)
			continue
		PoseFile.apply(data, scene, director, ctrl)
		await settle(4)
		var probs := _unresolved(slug, Anatomy.scene_problems(scene, director))
		check(probs.is_empty(), "%s: bodies plausible%s" % [slug, "" if probs.is_empty() else " — " + "; ".join(probs)])
		var skin := PackedStringArray()
		for rig in scene.characters:
			if rig.visible:
				var stats := {}
				for p in Anatomy.skin_problems(rig, stats):
					skin.append("%s: %s" % [rig.character_id, p])
				if OS.get_environment("ANATOMY_STATS") == "1":
					for b in stats:
						print("  %s %s %s p05 %.2f p50 %.2f p95 %.2f (%d)" % [slug, rig.character_id, b, stats[b][0], stats[b][1], stats[b][2], stats[b][3]])
		check(skin.is_empty(), "%s: skin keeps its shape%s" % [slug, "" if skin.is_empty() else " — " + "; ".join(skin)])
	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


## Drops the problems this pose is known to have and still fails if one of them has gone away,
## so a fix lands with its entry removed rather than silently.
func _unresolved(slug: String, probs: PackedStringArray) -> PackedStringArray:
	var known: Array = OUTSTANDING.get(slug, [])
	var out := PackedStringArray()
	var seen := {}
	for p in probs:
		var matched := ""
		for k: String in known:
			if p.begins_with(k):
				matched = k
				break
		if matched == "":
			out.append(p)
		else:
			seen[matched] = true
	for k: String in known:
		if not seen.has(k):
			out.append("'%s' no longer happens: drop it from OUTSTANDING" % k)
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
