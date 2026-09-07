extends SceneTree
## Sets up an attack from the catalogue (data/attacks.json) and saves it as a pose, so a
## technique starts from a grip that is placed and named rather than from two figures at rest.
##
##   godot --headless -s tools/stage_attack.gd -- <attack> [--mirror] [--name N] [--poses-dir D]
##   godot --headless -s tools/stage_attack.gd -- --list
##
## The pose is saved as "<Attack> Start" (slug attack_<key>_start) unless --name says otherwise.

var scene: PosingScene
var ctrl: PoseController
var director: GripDirector
var cam: OrbitCamera


func _initialize() -> void:
	var args := _args()
	if args.is_empty() or args[0] == "--list":
		for key in Attacks.keys():
			print("%-24s %s" % [key, Attacks.summary(key)])
		quit(0)
		return
	var key: String = args[0]
	if Attacks.entry(key).is_empty():
		push_error("unknown attack '%s'; --list shows them" % key)
		quit(1)
		return
	var mirror := "--mirror" in args
	var poses_dir := _opt(args, "--poses-dir", "res://poses")
	var name := _opt(args, "--name", "%s Start%s" % [Attacks.names(key).get("short", key), " (mirror)" if mirror else ""])
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	scene = PosingScene.new(); world.add_child(scene)
	cam = OrbitCamera.new(); world.add_child(cam)
	var gizmo := RotationGizmo.new(); world.add_child(gizmo)
	ctrl = PoseController.new(); world.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	director = GripDirector.new(); world.add_child(director); director.setup(scene, ctrl)
	await physics_frame
	scene.add_character("tori", "Tori", "Tori")
	scene.add_character("uke1", "Uke", "Uke")
	await process_frame
	var st := Staging.new(self, scene, director, ctrl)
	var report: Dictionary = await Attacks.stage(st, key, {"mirror": mirror})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(poses_dir))
	var data: Dictionary = await PoseFile.capture_baked(scene, director, cam, name)
	var path := PoseFile.pose_path(poses_dir, name)
	var err := PoseFile.save(path, data)
	if err != OK:
		push_error("could not write %s" % path)
		quit(1)
		return
	print("staged %s: Uke at (%.2f, %.2f), moved %.2f m from the catalogue's place; worst grip error %.3f m; refused %s"
		% [key, report["uke_position"].x, report["uke_position"].z, report["uke_offset"], report["grip_error"], report["refused"]])
	print("wrote ", path)
	quit(0)


func _args() -> Array:
	var out := []
	var seen := false
	for a in OS.get_cmdline_args():
		if seen:
			out.append(a)
		elif a == "--":
			seen = true
	if not seen:
		for a in OS.get_cmdline_user_args():
			out.append(a)
	return out


func _opt(args: Array, flag: String, fallback: String) -> String:
	var i := args.find(flag)
	return args[i + 1] if (i >= 0 and i + 1 < args.size()) else fallback
