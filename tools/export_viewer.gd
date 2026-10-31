extends SceneTree
## Exports a built technique for the 3D viewer in the gallery (tools/gallery.py): the motion of
## every figure, frame by frame as the film plays it, and — with --characters — each figure as a
## skinned glTF model at rest.
##
##   godot --headless -s tools/export_viewer.gd -- <sequence.json> <poses dir> <out dir> [--characters]
##
## <out dir>/<slug>.motion.bin is the motion, little-endian float32: a header of 4 numbers
## [fps, frames, characters, bones], then per character its id's index (see the .json), then per
## frame per character the skeleton's transform (position xyz, rotation quaternion xyzw) and every
## bone's rotation in its parent (quaternion xyzw) in the order <slug>.motion.json lists them,
## and the positions of the bones it lists as moving. The .json carries the names, the frame rate,
## the phases and their times. Everything is what the solve put on screen (IK, grips, the
## blend's settling), read after it, so the viewer only has to set the bones.
##
## <out dir>/<id>.glb is the figure: its skeleton and every visible mesh on it (body, eyes, hair,
## gi, belt, hakama), materials as glTF PBR. Nothing of the posing machinery goes with it.

const FPS := float(MovieExport.FPS)

var scene: PosingScene
var director: GripDirector
var ctrl: PoseController
var player: SequencePlayer


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("usage: -- <sequence.json> <poses dir> <out dir> [--characters]")
		quit(1)
		return
	var world := Node3D.new(); root.add_child(world)
	scene = PosingScene.new(); world.add_child(scene)
	var cam := Camera3D.new(); world.add_child(cam)
	var gizmo := RotationGizmo.new(); world.add_child(gizmo)
	ctrl = PoseController.new(); world.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	director = GripDirector.new(); world.add_child(director); director.setup(scene, ctrl)
	player = SequencePlayer.new(); world.add_child(player); player.setup(scene, director)
	await physics_frame
	var seq := Sequence.load(args[0])
	if seq == null or not player.load_sequence(seq, args[1]).is_empty():
		push_error("cannot load %s with its poses" % args[0])
		quit(1)
		return
	var out: String = args[2]
	DirAccess.make_dir_recursive_absolute(out)
	PoseFile.apply(player.poses[seq.steps[0]["pose"]], scene, director, ctrl)
	for i in 4:
		await process_frame
	scene.show_handles = false
	for rig in scene.characters:
		rig.set_show_handles(false)
	if args.has("--characters"):
		for rig in scene.characters:
			if rig.visible:
				var path := out.path_join(rig.character_id + ".glb")
				print("character: ", path, " ", _export_character(rig, path))
	await player.prepare()
	await _export_motion(seq, out)
	quit()


func _export_motion(seq: Sequence, out: String) -> void:
	var rigs: Array[CharacterRig] = []
	for rig in scene.characters:
		if rig.visible:
			rigs.append(rig)
	var sk0 := rigs[0].skeleton
	var bones := PackedStringArray()
	for i in sk0.get_bone_count():
		bones.append(sk0.get_bone_name(i))
	var n := int(round(seq.duration() * FPS)) + 1
	var frames := []   # per frame: per rig: [root xf, PackedFloat32Array of locals]
	var moved := {}    # bone index -> true where its position leaves the rest
	for f in n:
		player.apply_time(float(f) / FPS)
		for _k in 2:
			await process_frame
		var per := []
		for rig in rigs:
			var sk := rig.skeleton
			var rots := PackedFloat32Array()
			var poss := []
			for i in sk.get_bone_count():
				var g: Transform3D = rig._solved_poses[i]
				var p := sk.get_bone_parent(i)
				var local: Transform3D = g if p < 0 else (rig._solved_poses[p] as Transform3D).affine_inverse() * g
				var q := local.basis.orthonormalized().get_rotation_quaternion()
				rots.append_array([q.x, q.y, q.z, q.w])
				poss.append(local.origin)
				if local.origin.distance_to(sk.get_bone_rest(i).origin) > 1e-4:
					moved[i] = true
			per.append([sk.global_transform, rots, poss])
		frames.append(per)
	var moving: Array = moved.keys()
	moving.sort()
	var data := PackedFloat32Array([FPS, n, rigs.size(), bones.size()])
	for f in n:
		for r in rigs.size():
			var xf: Transform3D = frames[f][r][0]
			var q := xf.basis.orthonormalized().get_rotation_quaternion()
			data.append_array([xf.origin.x, xf.origin.y, xf.origin.z, q.x, q.y, q.z, q.w])
			data.append_array(frames[f][r][1])
			for i: int in moving:
				var p: Vector3 = frames[f][r][2][i]
				data.append_array([p.x, p.y, p.z])
	var slug := seq.slug()
	var bin := FileAccess.open(out.path_join(slug + ".motion.bin"), FileAccess.WRITE)
	bin.store_buffer(data.to_byte_array())
	bin.close()
	var phases := []
	for i in seq.steps.size():
		phases.append({"pose": seq.steps[i]["pose"], "t": seq.step_start(i)})
	var ids := []
	for rig in rigs:
		ids.append(rig.character_id)
	var moving_names := []
	for i: int in moving:
		moving_names.append(bones[i])
	var meta := {"fps": FPS, "frames": n, "duration": seq.duration(), "characters": ids,
		"bones": Array(bones), "moving": moving_names, "phases": phases}
	var js := FileAccess.open(out.path_join(slug + ".motion.json"), FileAccess.WRITE)
	js.store_string(JSON.stringify(meta))
	js.close()
	print("motion: %s (%d frames, %d figures, %d bones, %d moving)" % [out.path_join(slug + ".motion.bin"), n, rigs.size(), bones.size(), moving.size()])


## A clean copy of the figure — a skeleton at rest and the visible meshes skinned to it — written
## as glTF. The live rig carries IK, picking capsules and handles that are no part of a figure.
func _export_character(rig: CharacterRig, path: String) -> Error:
	var src := rig.skeleton
	var top := Node3D.new()
	top.name = rig.character_id
	var sk := Skeleton3D.new()
	sk.name = "Skeleton"
	top.add_child(sk)
	for i in src.get_bone_count():
		sk.add_bone(src.get_bone_name(i))
	for i in src.get_bone_count():
		sk.set_bone_parent(i, src.get_bone_parent(i))
		sk.set_bone_rest(i, src.get_bone_rest(i))
		sk.set_bone_pose(i, src.get_bone_rest(i))
	for child in src.get_children():
		if not (child is MeshInstance3D) or not child.visible or child.mesh == null:
			continue
		var m := MeshInstance3D.new()
		m.name = child.name
		m.mesh = child.mesh
		m.skin = child.skin
		for s in child.mesh.get_surface_count():
			var mat: Material = child.get_active_material(s)
			if mat is ShaderMaterial and rig.gi and rig.gi.hakama_material:
				mat = rig.gi.hakama_material   # the hakama's resting-on-the-mat shader has no glTF form
			m.set_surface_override_material(s, mat)
		sk.add_child(m)
		m.skeleton = NodePath("..")
	root.add_child(top)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(top, state)
	if err == OK:
		err = doc.write_to_filesystem(state, path)
	top.queue_free()
	return err
