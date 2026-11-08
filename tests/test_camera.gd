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
				check(cam.is_position_in_frustum(pos), "%s: %s %s in frustum" % [name, rig.character_id, bone])

	var axis: Dictionary = scene.tori_uke_axis()
	var line: Vector3 = axis["to"] - axis["from"]
	line.y = 0.0
	cam.apply_preset(CameraPresets.front(scene))
	await settle()
	var view: Vector3 = -cam.global_transform.basis.z
	view.y = 0.0
	var angle := rad_to_deg(view.normalized().angle_to(line.normalized()))
	check(absf(angle - CameraPresets.FRONT_OFFSET_DEG) < 5.0, "front view is a three-quarter front, %.0f° off the Tori→Uke line (%.1f°)" % [CameraPresets.FRONT_OFFSET_DEG, angle])

	# The film's following camera: a figure walking in from 2.5 m stays in frame on every frame, the
	# camera comes closer as the gap closes, fills the picture with the two of them at the end, and
	# never jumps between frames.
	var tori: CharacterRig = scene.get_character("tori")
	var uke: CharacterRig = scene.get_character("uke1")
	uke2.visible = false
	var uke_end := uke.position
	var walk_from := uke_end + (uke_end - tori.position).normalized() * 2.5
	var samples := []
	var n := 60
	for i in n:
		uke.position = walk_from.lerp(uke_end, clampf(float(i) / 40.0, 0.0, 1.0))
		await settle(1)
		samples.append(CameraPresets.film_points(scene))
	cam.fov = CameraPresets.FILM_FOV_DEG
	cam.apply_preset(CameraPresets.side(scene))
	var dir := cam.global_transform.basis.z
	var track := CameraPresets.follow_track(dir, samples, 30.0, 1600.0 / 900.0, cam.fov)
	check(track.size() == n, "one camera per frame (%d)" % track.size())
	var outside := 0
	var biggest_jump := 0.0
	var fill_end := 0.0
	for i in n:
		cam.look_from(track[i]["direction"], track[i]["center"], track[i]["distance"])
		for pt in samples[i]:
			if not cam.is_position_in_frustum(pt):
				outside += 1
		if i > 0:
			biggest_jump = maxf(biggest_jump, (track[i]["center"] as Vector3).distance_to(track[i - 1]["center"]))
			biggest_jump = maxf(biggest_jump, absf(float(track[i]["distance"]) - float(track[i - 1]["distance"])))
		if i == n - 1:
			var top := INF
			var bottom := -INF
			for pt in samples[i]:
				var px := cam.unproject_position(pt)
				top = minf(top, px.y)
				bottom = maxf(bottom, px.y)
			fill_end = (bottom - top) / 900.0
	check(outside == 0, "the film keeps every point of the figures in frame (%d outside)" % outside)
	check(float(track[0]["distance"]) > float(track[n - 1]["distance"]) + 0.5, "the camera comes in as Uke does (%.2f m → %.2f m)" % [track[0]["distance"], track[n - 1]["distance"]])
	check(fill_end > 0.7, "the two figures fill the film's height at the end (%.0f%%)" % (fill_end * 100.0))
	check(biggest_jump < 0.1, "the camera glides, at most %.3f m from one frame to the next" % biggest_jump)

	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


func settle(frames: int = 2) -> void:
	for i in frames:
		await process_frame
