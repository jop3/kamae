extends SceneTree
## The mat, frame by frame: how far anything of a figure goes below it while a sequence plays.
##
## check_motion.gd judges joints and bodies against each other; nothing there knows the floor is
## solid, and a fall blended between two grounded poses swung Uke's whole body under the mat in
## the middle of the roll (the root is at the feet, and the pitch was turned about it). This walks
## each sequence at the export frame rate, skins the body and the gi on the CPU with
## the solved pose, and reports the deepest vertex per frame. The hakama is not counted: its
## shader lays any of it that reaches the mat on the mat (Gi.resting_on_mat), which is what
## cloth does and what skinning alone cannot.
##
##   FLOOR_SEQS_DIR=<dir> FLOOR_POSES_DIR=<dir> godot --headless -s tests/check_floor.gd
##
## Defaults to the committed sequences. FLOOR_SEQ=<slug> checks one; FLOOR_VERBOSE=1 lists every
## frame. FLOOR_REPORT=1 reports instead of judging (tools/technique.sh writes floor.txt with it).

## A vertex this far under the mat, metres, is a frame worth reporting: the mat hides a sole
## pressed a few millimetres into it, it does not hide a shoulder.
const DEPTH := 0.02
## Every n-th vertex is skinned; the meshes are dense enough that a dip shows in a sample.
const STRIDE := 3
const FPS := float(MovieExport.FPS)

## Frames still under the mat, per committed sequence. May only go down, like check_motion's.
## None today: the last (Uke's stepping foot in shihonage irimi) went with the refit grips.
const OUTSTANDING := {}

var failures := 0
var scene: PosingScene
var ctrl: PoseController
var director: GripDirector
var player: SequencePlayer
var _mesh_cache := {}


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
	var seqs_dir: String = env.call("FLOOR_SEQS_DIR", "res://sequences")
	var poses_dir: String = env.call("FLOOR_POSES_DIR", "res://poses")
	var only: String = env.call("FLOOR_SEQ", "")
	var verbose: bool = env.call("FLOOR_VERBOSE", "0") == "1"
	var report: bool = env.call("FLOOR_REPORT", "0") == "1"
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
		await player.prepare()   # as the video does: the blends steer each limb between its solves
		var bad := []
		var worst := 0.0
		var n := int(round(seq.duration() * FPS)) + 1
		for i in n:
			var t := float(i) / FPS
			player.seek(t)
			await settle(3)
			var parts := []
			for rig in scene.characters:
				if not rig.visible:
					continue
				var low := lowest(rig)
				var depth: float = -low["y"]
				if depth > DEPTH:
					parts.append("%s %s %.1f cm under the mat" % [rig.character_id, low["what"], depth * 100.0])
					worst = maxf(worst, depth)
			if not parts.is_empty():
				bad.append("t=%.2f %s" % [t, "; ".join(parts)])
				if verbose:
					print("      ", bad[-1])
		var line := "FLOOR %s: %d of %d frames below the mat, deepest %.1f cm" % [slug, bad.size(), n, worst * 100.0]
		if report:
			print(line)
			for l in bad.slice(0, 6):
				print("    ", l)
			if bad.size() > 6:
				print("    and %d more frames" % (bad.size() - 6))
		else:
			var budget: int = OUTSTANDING.get(slug, 0)
			var detail := ""
			if bad.size() > budget:
				detail = " — " + "\n      ".join(bad.slice(0, 4))
			elif bad.size() < budget:
				detail = " — better than the %d on record: lower it in OUTSTANDING" % budget
			check(bad.size() == budget, line + ", %d on record%s" % [budget, detail])
	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


## The lowest skinned vertex of a figure, world y, and which mesh and bone it belongs to.
func lowest(rig: CharacterRig) -> Dictionary:
	var best := {"y": INF, "what": ""}
	var meshes: Array = [[rig.body, "skin"]]
	if rig.gi and rig.gi_visible:
		meshes.append([rig.gi.jacket, "gi"])
		meshes.append([rig.gi.trousers, "trousers"])
	for m in meshes:
		var mi: MeshInstance3D = m[0]
		if mi == null or not mi.visible or mi.mesh == null or mi.skin == null:
			continue
		var r := _lowest_in(rig, mi)
		var y: float = r["y"]
		if y < best["y"]:
			best = {"y": y, "what": "%s (%s)" % [m[1], r["bone"]]}
	return best


func _lowest_in(rig: CharacterRig, mi: MeshInstance3D) -> Dictionary:
	var sk := rig.skeleton
	var skin: Skin = mi.skin
	if not _mesh_cache.has(mi):
		var arrays := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		_mesh_cache[mi] = [verts, arrays[Mesh.ARRAY_BONES], arrays[Mesh.ARRAY_WEIGHTS],
			arrays[Mesh.ARRAY_BONES].size() / verts.size()]
	var c: Array = _mesh_cache[mi]
	var verts: PackedVector3Array = c[0]
	var bones: PackedInt32Array = c[1]
	var weights: PackedFloat32Array = c[2]
	var per: int = c[3]
	var xf: Array[Transform3D] = []
	var bind_bone := PackedInt32Array()
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = sk.find_bone(skin.get_bind_name(b))
		bind_bone.append(bone)
		xf.append(rig.bone_world_transform(sk.get_bone_name(bone)) * skin.get_bind_pose(b))
	var low := INF
	var low_bone := -1
	var v := 0
	while v < verts.size():
		var p := Vector3.ZERO
		var top := 0.0
		var top_bone := -1
		for k in per:
			var w := weights[v * per + k]
			if w <= 0.0:
				continue
			var bind := bones[v * per + k]
			p += (xf[bind] * verts[v]) * w
			if w > top:
				top = w; top_bone = bind_bone[bind]
		if p.y < low:
			low = p.y; low_bone = top_bone
		v += STRIDE
	return {"y": low, "bone": sk.get_bone_name(low_bone) if low_bone >= 0 else "?"}


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
