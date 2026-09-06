extends SceneTree
## Importing a video draft (tools/video_pipeline): the landmarks become a rough but complete
## scene, with facing, IK limbs, feet on the floor, the grip the file names, saved poses and a
## sequence with the file's timings. It is a draft, so the checks are about plausibility.

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)


func _initialize() -> void:
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	var scene := PosingScene.new(); world.add_child(scene); scene.setup_default()
	var cam := Camera3D.new(); world.add_child(cam)
	var gizmo := RotationGizmo.new(); world.add_child(gizmo)
	var ctrl := PoseController.new(); world.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	var director := GripDirector.new(); world.add_child(director); director.setup(scene, ctrl)
	await physics_frame
	var out := ProjectSettings.globalize_path("res://tests/out/import_test")
	DirAccess.make_dir_recursive_absolute(out.path_join("poses"))
	DirAccess.make_dir_recursive_absolute(out.path_join("sequences"))
	var draft := ProjectSettings.globalize_path("res://imports/katatedori_tenkan.json")
	var result: Dictionary = await PoseImport.import_draft(draft, scene, director, ctrl, null, out.path_join("poses"), out.path_join("sequences"))
	check(not result.has("error"), "the draft imports (%s)" % str(result.get("error", "")))
	if result.has("error"):
		quit(1); return
	check(result["poses"].size() == 3, "three phases become three poses (%d)" % result["poses"].size())
	var seq: Sequence = result["sequence"]
	check(seq.steps.size() == 3 and seq.name == "Katatedori Tenkan", "the sequence carries the technique's name and steps")
	check(FileAccess.file_exists(result["sequence_path"]), "the sequence is saved")
	# The scene after the last phase: two characters, roles from the figure names.
	var tori := scene.get_character("tori"); var uke := scene.get_character("uke1")
	check(tori != null and uke != null and tori.role == "Tori" and uke.role == "Uke", "tori and uke exist with their roles")
	# Load the Grepp pose back and look at it.
	PoseFile.apply(PoseFile.load(result["poses"][0]), scene, director)
	for i in 4:
		await process_frame
	tori = scene.get_character("tori"); uke = scene.get_character("uke1")
	for rig in [tori, uke]:
		for key in ["RightArm", "LeftArm", "RightLeg", "LeftLeg"]:
			check(rig.limbs[key].mode == Limb.Mode.IK, "%s %s is posed by IK" % [rig.character_id, key])
		for foot in ["RightFoot", "LeftFoot"]:
			var y: float = rig.bone_world_transform(foot).origin.y
			check(y > -0.02 and y < 0.20, "%s %s is near the floor (%.2f m)" % [rig.character_id, foot, y])
	# Facing comes from the shoulders: in the grab the two face roughly each other.
	var f_t: Vector3 = tori.global_transform.basis.z; var f_u: Vector3 = uke.global_transform.basis.z
	check(f_t.dot(f_u) < 0.3, "tori and uke do not face the same way (dot %.2f)" % f_t.dot(f_u))
	# The grip the file names: uke's hand on tori's forearm, reached.
	var grips := director.grips_for("uke1")
	check(grips.size() == 1 and grips[0].target.character_id == "tori" and grips[0].target.bone_name.ends_with("LowerArm"), "uke grips tori's forearm in Grepp")
	check(director.worst_error() < 0.02, "the grip is reached after stepping in (%.3f m)" % director.worst_error())
	var problems := Anatomy.scene_problems(scene, director)
	print("anatomy on the imported Grepp: %d problems %s" % [problems.size(), problems])
	check(Anatomy.joint_problems(tori).is_empty() and Anatomy.joint_problems(uke).is_empty(), "no joint bends the wrong way")
	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)
