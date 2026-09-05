extends SceneTree
## Camera preset test: Front/Side frame every character and Front looks along the Tori→Uke line.

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)

var scene: PosingScene
var cam: OrbitCamera


func _initialize() -> void:
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	scene = PosingScene.new(); world.add_child(scene); scene.setup_default()
	var uke2: CharacterRig = scene.add_character("uke2", "Uke 2", "Uke")
	uke2.position = Vector3(1.2, 0, 0.3)
	cam = OrbitCamera.new(); world.add_child(cam); cam.make_current()
	cam.fov = CameraPresets.FOV_DEG
	root.size = Vector2i(1600, 900)
	await settle()

	for name in ["front", "side"]:
		var p: Dictionary = CameraPresets.front(scene) if name == "front" else CameraPresets.side(scene)
		cam.apply_preset(p)
		await settle()
		check(absf(cam.global_position.y - CameraPresets.HEIGHT) < 0.01, "%s camera is %.2f m high" % [name, cam.global_position.y])
		for rig in scene.characters:
			for bone in ["Head", "RightFoot", "LeftFoot"]:
				var pos: Vector3 = rig.bone_world_transform(bone).origin
				check(cam.is_position_in_frustum(pos), "%s: %s %s in frustum" % [name, rig.id, bone])

	var axis: Dictionary = scene.tori_uke_axis()
	var line: Vector3 = axis["to"] - axis["from"]
	line.y = 0.0
	cam.apply_preset(CameraPresets.front(scene))
	await settle()
	var view: Vector3 = -cam.global_transform.basis.z
	view.y = 0.0
	var angle := rad_to_deg(view.normalized().angle_to(line.normalized()))
	check(angle < 5.0, "front view is along the Tori→Uke line (%.1f°)" % angle)

	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


func settle(frames: int = 2) -> void:
	for i in frames:
		await process_frame
