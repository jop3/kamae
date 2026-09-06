extends SceneTree
## Plausibility of every committed pose (poses/): no joint out of range or bent the wrong way,
## no limb through a body, no weapon through anyone, no bone scale, and a CPU-skinned mesh
## that keeps its shape. Headless and fast. See src/rig/Anatomy.gd for the rules.

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)

## Wrists bent far past a real one, in poses that are committed today. Every entry is a hand
## forced onto a weapon or a grip while the forearm points somewhere else, so the wrist takes up
## the difference; the fix is to choose the elbow that leaves the wrist neutral when a hand is
## placed, and to rebuild the fixtures, which changes every weapon pose and wants the
## instructor's eye first (docs/handoff.md, "The wrists in weapon holds"). Listed here so the
## measurement stays on and nothing new or worse can slip in: an entry that stops happening is
## itself a failure, so this list cannot rot.
const OUTSTANDING := {
	"jo_dori_tsuki": ["uke1: LeftHand swung"],
	"jo_dori_uke": ["tori: RightHand swung", "uke1: LeftHand swung"],
	"katatedori_ikkyo_kake": ["tori: LeftHand swung"],
	"katatedori_shihonage_kake": ["tori: LeftHand swung"],
	"katatedori_shihonage_kuzushi": ["uke1: LeftHand swung"],
	"kumijo_kamae": ["tori: LeftHand swung", "uke1: LeftHand swung"],
	"kumijo_tsuki": ["tori: LeftHand swung", "uke1: LeftHand swung"],
	"kumitachi_awase": ["tori: RightHand swung", "tori: LeftHand swung",
		"uke1: RightHand swung", "uke1: LeftHand swung"],
	"kumitachi_uchi": ["tori: RightHand swung", "tori: LeftHand swung",
		"uke1: RightHand swung", "uke1: LeftHand swung"],
	"ryotemochi_grepp": ["uke1: RightHand swung", "uke2: LeftHand swung"],
	"tachi_dori_irimi": ["uke1: RightHand swung", "uke1: LeftHand swung"],
	"tachi_dori_kamae": ["uke1: RightHand swung", "uke1: LeftHand swung"],
	"ushiro_ryotedori_zenponage_grepp": ["uke1: RightHand swung", "uke1: LeftHand swung"],
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
