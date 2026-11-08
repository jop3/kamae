extends SceneTree
## Relaxes saved poses the way TechniqueScript relaxes a staged pose before saving it: the two
## bodies solved together at full strength a few times (ContactSolve), the feet put back on the
## mat, and the pose saved again as it then stands. For a committed pose that the body's surface
## (Anatomy.SHAPES) shows two figures pressed into each other in:
##   godot --headless -s tools/relax_pose.gd -- poses/katatedori_shihonage_kuzushi.json [...]
## Grips, the camera and everything else in the file are kept; the look of each figure too.


func _initialize() -> void:
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	var scene := PosingScene.new(); world.add_child(scene)
	var cam := OrbitCamera.new(); world.add_child(cam)
	var gizmo := RotationGizmo.new(); world.add_child(gizmo)
	var ctrl := PoseController.new(); world.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	var director := GripDirector.new(); world.add_child(director); director.setup(scene, ctrl)
	await physics_frame
	var st := Staging.new(self, scene, director, ctrl)
	for path: String in OS.get_cmdline_user_args():
		var full := path if path.is_absolute_path() else ProjectSettings.globalize_path("res://" + path)
		var data := PoseFile.load(full)
		if data.is_empty():
			push_error("cannot read %s" % path)
			continue
		PoseFile.apply(data, scene, director, ctrl, cam)
		await st.settle(6)
		var before := Anatomy.scene_problems(scene, director)
		for _round in TechniqueScript.RELAX_ROUNDS:
			ContactSolve.solve(scene, director, {"root": 1.0, "arms": 1.0, "legs": 1.0, "moved": ContactSolve.RELAX_MOVED})
			await st.settle(2)
		await st.feet_on_floor()
		await st.settle(4)
		var after := Anatomy.scene_problems(scene, director)
		var out: Dictionary = await PoseFile.capture_baked(scene, director, cam, data.get("name", ""))
		for key in data:   # anything the file carries that a capture does not write
			if not out.has(key):
				out[key] = data[key]
		PoseFile.save(full, out)
		print("%s: %d problems before, %d after%s" % [path, before.size(), after.size(),
			"" if after.is_empty() else "\n    " + "\n    ".join(after)])
	quit()
