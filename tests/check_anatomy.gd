extends SceneTree
## Plausibility of every committed pose (poses/): no joint out of range or bent the wrong way,
## no limb through a body, no weapon through anyone, no bone scale, and a CPU-skinned mesh
## that keeps its shape. Headless and fast. See src/rig/Anatomy.gd for the rules.

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)

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
		var probs := Anatomy.scene_problems(scene, director)
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
