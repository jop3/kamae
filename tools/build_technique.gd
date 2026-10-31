extends SceneTree
## Builds a technique script (techniques/*.json, see docs/technique-scripts.md) into poses and a
## sequence, and writes what the joints refused into report.json next to them:
##
##   godot --headless -s tools/build_technique.gd -- techniques/shomenuchi_iriminage.json [--out DIR]
##
## DIR defaults to techniques/build/<slug>. tools/technique.sh runs this and then renders the
## stills, the video and a contact sheet.


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <technique.json> [--out DIR]")
		quit(2)
		return
	var path: String = args[0]
	var script := TechniqueScript.load_file(path)
	if script.is_empty():
		quit(2)
		return
	var out: String = args[args.find("--out") + 1] if args.has("--out") else \
		"res://techniques/build".path_join(PoseFile.slugify(script.get("name", path.get_file().get_basename())))
	var world := Node3D.new(); root.add_child(world)
	var scene := PosingScene.new(); world.add_child(scene)
	var cam := OrbitCamera.new(); world.add_child(cam)
	var gizmo := RotationGizmo.new(); world.add_child(gizmo)
	var ctrl := PoseController.new(); world.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	var director := GripDirector.new(); world.add_child(director); director.setup(scene, ctrl)
	await physics_frame
	var ts := TechniqueScript.new(self, scene, director, ctrl, cam)
	var report: Dictionary = await ts.run(script, out)
	var f := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("sequence: ", ProjectSettings.globalize_path(report.get("sequence", "")))
	if not report["errors"].is_empty():
		print("ERRORS:\n  ", "\n  ".join(report["errors"]))
	quit(1 if not report["errors"].is_empty() else 0)
