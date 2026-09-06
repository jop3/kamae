extends Node3D
## Application root: 3D view + posing controller + side panel.

@onready var posing_scene: PosingScene = $PosingScene
@onready var camera: OrbitCamera = $OrbitCamera
@onready var gizmo: RotationGizmo = $RotationGizmo
@onready var controller: PoseController = $PoseController
@onready var grip_director: GripDirector = $GripDirector
@onready var panel: SidePanel = $UI/SidePanel
@onready var floor_grid: Node3D = $FloorGrid
@onready var ui_layer: CanvasLayer = $UI

var export_dir := "user://exports"
var player: SequencePlayer
var movie_export: MovieExport


func _ready() -> void:
	# The project viewport is 1920x1080 because Movie Maker records at the configured size and
	# ignores --resolution. For interactive use open a window that fits a laptop screen.
	if not _is_render_child():
		var screen := DisplayServer.screen_get_size()
		if screen.x < 2000 or screen.y < 1150:
			get_window().size = Vector2i(1600, 900)
	posing_scene.setup_default()
	controller.setup(posing_scene, camera, gizmo)
	camera.moved.connect(func(before: Dictionary, after: Dictionary): controller.record_camera_move(camera, before, after))
	grip_director.setup(posing_scene, controller)
	player = SequencePlayer.new()
	player.name = "SequencePlayer"
	add_child(player)
	player.setup(posing_scene, grip_director)
	player.camera = camera
	panel.setup(controller, posing_scene, grip_director, camera, player)
	panel.export_requested.connect(_on_export_requested)
	movie_export = MovieExport.new()
	movie_export.name = "MovieExport"
	add_child(movie_export)
	movie_export.started.connect(func(job): panel.set_export_status("Rendering %s in a second window… (%s)" % [job["slug"], "MP4 via ffmpeg" if job["ffmpeg"] else "AVI: ffmpeg not found"]))
	movie_export.finished.connect(func(job): panel.set_export_status(job["message"] + ("\n%d stills alongside" % job["stills"].size() if job["ok"] else "")))
	panel.video_export_requested.connect(_on_video_export_requested)
	panel.stills_export_requested.connect(func(seq: Sequence, transparent: bool):
		var job := movie_export.export_stills(ProjectSettings.globalize_path(Sequence.sequence_path(SidePanel.SEQUENCES_DIR, seq.name)),
			ProjectSettings.globalize_path(SidePanel.POSES_DIR), ProjectSettings.globalize_path(export_dir), transparent)
		if job.is_empty():
			panel.set_export_status("An export is already running, or the sequence could not be read."))
	frame_all()
	var args := OS.get_cmdline_user_args()
	if args.has("--demo-still"):
		await _render_demo_still(args[args.find("--demo-still") + 1])
		return
	if args.has("--demo-weapon"):
		await _render_demo_weapon(args[args.find("--demo-weapon") + 1])
		return
	if args.has("--render-sequence"):
		await _render_sequence(args)
		return
	if args.has("--render-stills"):
		await _render_stills(args)
		return
	if args.has("--screenshot-ui"):
		# Development aid: the last drawn frame with the panel visible (exports never include it),
		# with a joint selected so the gizmo shows too.
		controller.select(posing_scene.get_character("tori"), "RightUpperArm")
		for i in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(args[args.find("--screenshot-ui") + 1])
		print("ui screenshot saved")
		get_tree().quit()
		return
	if args.has("--demo-gi"):
		await _render_demo_gi(args[args.find("--demo-gi") + 1])
		return
	if args.has("--demo-hand"):
		await _render_demo_hand(args[args.find("--demo-hand") + 1])
		return
	for flag in ["--screenshot", "--screenshot-transparent"]:
		if args.has(flag):
			await get_tree().process_frame
			await get_tree().process_frame
			var path: String = args[args.find(flag) + 1]
			if flag == "--screenshot-transparent":
				# Select a joint so the test proves the gizmo is kept out of the exported image.
				controller.select(posing_scene.get_character("tori"), "RightUpperArm")
				await get_tree().process_frame
			await StillExport.capture(get_viewport(), path, flag == "--screenshot-transparent", _hide_always(), _hide_for_transparent())
			print("screenshot saved: ", path)
			get_tree().quit()


## Keyboard shortcuts: 1 Front, 2 Side, Space play/pause the sequence, Home frames everything.
## Ctrl+Z / Ctrl+Y are handled by the pose controller.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1:
			camera.fov = CameraPresets.FOV_DEG
			camera.apply_preset(CameraPresets.front(posing_scene))
		KEY_2:
			camera.fov = CameraPresets.FOV_DEG
			camera.apply_preset(CameraPresets.side(posing_scene))
		KEY_HOME:
			frame_all()
		KEY_SPACE:
			if player and player.sequence:
				if player.playing:
					player.pause()
				else:
					player.play()
		_:
			return
	get_viewport().set_input_as_handled()


func frame_all() -> void:
	camera.fov = CameraPresets.FOV_DEG
	camera.apply_preset(CameraPresets.side(posing_scene))


func _on_export_requested(transparent: bool) -> void:
	var name := StillExport.slugify("pose_%s" % Time.get_datetime_string_from_system().replace(":", "-"))
	var path := ProjectSettings.globalize_path(export_dir).path_join(name + ".png")
	var err: Error = await StillExport.capture(get_viewport(), path, transparent, _hide_always(), _hide_for_transparent())
	print("Exported %s (%s)" % [path, error_string(err)])


## True in a second instance spawned to render (video frames or batch stills), where the window
## must keep the full export size.
static func _is_render_child() -> bool:
	var args := OS.get_cmdline_user_args()
	return OS.has_feature("movie") or args.has("--render-sequence") or args.has("--render-stills")


func _on_video_export_requested(seq: Sequence) -> void:
	var seq_path := ProjectSettings.globalize_path(Sequence.sequence_path(SidePanel.SEQUENCES_DIR, seq.name))
	var poses_dir := ProjectSettings.globalize_path(SidePanel.POSES_DIR)
	var out_dir := ProjectSettings.globalize_path(export_dir)
	var job := movie_export.export_sequence(seq_path, poses_dir, out_dir)
	if job.is_empty():
		panel.set_export_status("An export is already running, or the sequence could not be read.")


## Never part of an exported image: the UI dock, the rotation gizmo and every IK handle.
func _hide_always() -> Array[Node]:
	var out: Array[Node] = [ui_layer, gizmo]
	for rig in posing_scene.characters:
		out.append_array(rig.handles())
	return out


## Only hidden when exporting on a transparent background.
func _hide_for_transparent() -> Array[Node]:
	return [floor_grid]


## Child-process mode for video export (spec §5.8): plays a sequence under Movie Maker, which
## calls _process with a fixed 1/30 s delta and writes every frame, saves a still at the start
## of each phase, and quits when the sequence ends. Everything a still must not contain is hidden.
func _render_sequence(args: PackedStringArray) -> void:
	var seq_path: String = args[args.find("--render-sequence") + 1]
	var poses_dir: String = args[args.find("--poses-dir") + 1] if args.has("--poses-dir") else seq_path.get_base_dir()
	var stills_dir: String = args[args.find("--stills-dir") + 1] if args.has("--stills-dir") else ""
	var seq := Sequence.load(seq_path)
	if seq == null:
		push_error("Cannot read sequence %s" % seq_path)
		get_tree().quit(1)
		return
	var missing: Array = player.load_sequence(seq, poses_dir)
	if not missing.is_empty() or seq.steps.is_empty():
		push_error("Sequence %s has no steps or names poses that are not saved: %s" % [seq.name, missing])
		get_tree().quit(1)
		return
	posing_scene.show_handles = false
	for rig in posing_scene.characters:
		rig.set_show_handles(false)
	# The first pose defines the characters and weapons; the blend only moves what exists.
	PoseFile.apply(player.poses[seq.steps[0]["pose"]], posing_scene, grip_director)
	ui_layer.visible = false
	gizmo.suppressed = true
	await get_tree().process_frame
	await get_tree().process_frame
	_apply_sequence_camera(seq)
	player.seek(0.0)
	await get_tree().process_frame
	var phases := _phase_names(seq)
	var next_phase := 0
	player.play()
	while player.playing:
		await get_tree().process_frame
		# A still at the moment each phase is fully reached, named predictably for the handout.
		while next_phase < seq.steps.size() and player.time >= seq.step_start(next_phase) - 1e-4:
			if stills_dir != "":
				var img := get_viewport().get_texture().get_image()
				img.save_png(stills_dir.path_join("%s_%s.png" % [seq.slug(), phases[next_phase]]))
			next_phase += 1
	await get_tree().process_frame
	print("sequence rendered: %s, %.1f s" % [seq.name, seq.duration()])
	get_tree().quit()


## Child-process mode for "Export Front+Side": every phase of a sequence as two stills at full
## size, <slug>_<phase>_front.png and _side.png, on a flat or transparent background.
func _render_stills(args: PackedStringArray) -> void:
	var seq_path: String = args[args.find("--render-stills") + 1]
	var poses_dir: String = args[args.find("--poses-dir") + 1] if args.has("--poses-dir") else seq_path.get_base_dir()
	var stills_dir: String = args[args.find("--stills-dir") + 1] if args.has("--stills-dir") else seq_path.get_base_dir()
	var transparent := args.has("--transparent")
	var seq := Sequence.load(seq_path)
	if seq == null:
		push_error("Cannot read sequence %s" % seq_path)
		get_tree().quit(1)
		return
	var missing: Array = player.load_sequence(seq, poses_dir)
	if not missing.is_empty() or seq.steps.is_empty():
		push_error("Sequence %s has no steps or names poses that are not saved: %s" % [seq.name, missing])
		get_tree().quit(1)
		return
	posing_scene.show_handles = false
	for rig in posing_scene.characters:
		rig.set_show_handles(false)
	PoseFile.apply(player.poses[seq.steps[0]["pose"]], posing_scene, grip_director)
	await get_tree().process_frame
	var phases := _phase_names(seq)
	for i in seq.steps.size():
		player.seek(seq.step_start(i))
		for k in 3:
			await get_tree().process_frame
		for view in ["front", "side"]:
			camera.fov = CameraPresets.FOV_DEG
			camera.apply_preset(CameraPresets.front(posing_scene) if view == "front" else CameraPresets.side(posing_scene))
			var path := stills_dir.path_join("%s_%s_%s.png" % [seq.slug(), phases[i], view])
			await StillExport.capture(get_viewport(), path, transparent, _hide_always(), _hide_for_transparent())
			print("still saved: ", path)
	get_tree().quit()


func _apply_sequence_camera(seq: Sequence) -> void:
	camera.fov = CameraPresets.FOV_DEG
	match seq.camera:
		"Front":
			camera.apply_preset(CameraPresets.front(posing_scene))
		_:
			camera.apply_preset(CameraPresets.side(posing_scene))


## Phase slugs for filenames: the pose slug with the technique's own slug stripped off.
static func _phase_names(seq: Sequence) -> Array:
	var out := []
	var prefix: String = seq.slug() + "_"
	for i in seq.steps.size():
		var pose_slug: String = seq.steps[i]["pose"]
		# A pose reused from another technique (Shihonage starts from the Ikkyo Grepp) keeps
		# only its last word, so the file is <technique>_grepp.png like the others.
		var phase := pose_slug.trim_prefix(prefix) if pose_slug.begins_with(prefix) else pose_slug.get_slice("_", pose_slug.get_slice_count("_") - 1)
		if phase == "" or phase in out:
			phase = "%d" % (i + 1)
		out.append(phase)
	return out


## Test hook: a katatedori grip — Uke's hand wrapped around Tori's wrist, held by the grip system.
func _render_demo_still(path: String) -> void:
	var tori: CharacterRig = posing_scene.get_character("tori")
	var uke: CharacterRig = posing_scene.get_character("uke1")
	controller.set_root(tori, Vector3(0, 0, -0.22), 0.0)
	controller.set_root(uke, Vector3(0, 0, 0.22), PI)
	await get_tree().process_frame
	# Tori offers the right arm; Uke reaches for it with the facing (left) hand and takes hold.
	await controller.set_limb_mode(tori, "RightArm", Limb.Mode.IK)
	tori.limbs["RightArm"].target.global_position = tori.bone_world_transform("RightUpperArm").origin + Vector3(0, -0.14, 0.22)
	await controller.set_limb_mode(uke, "LeftArm", Limb.Mode.IK)
	for i in 3:
		await get_tree().process_frame
	# Uke's hand comes in from above the wrist; the wrap keeps it on that side.
	uke.limbs["LeftArm"].target.global_position = tori.bone_world_transform("RightLowerArm").origin + Vector3(0, 0.06, 0.12)
	for i in 3:
		await get_tree().process_frame
	grip_director.attach_wrapped(uke, "Left", tori, "RightLowerArm")
	for f in FingerCurl.FINGERS:
		uke.fingers.set_curl("Left", f, 0.55)
	uke.fingers.set_curl("Left", "Thumb", 0.7)
	# Now move Tori: the grip must hold without touching Uke again.
	controller.set_root(tori, Vector3(0.05, 0, -0.20), deg_to_rad(12))
	for i in 4:
		await get_tree().process_frame
	print("grip error after moving Tori: %.4f m" % grip_director.worst_error())
	var wrist: Vector3 = tori.bone_world_transform("RightHand").origin
	var views := {"": [Vector3(0.9, 0.30, 0.5), Vector3(0, 1.05, 0), 2.0],
		"_grip": [Vector3(-0.8, 0.3, 0.3), wrist, 0.45]}
	for suffix in views:
		var v: Array = views[suffix]
		camera.look_from(v[0], v[1], v[2])
		for i in 3:
			await get_tree().process_frame
		var p: String = path.get_basename() + str(suffix) + ".png"
		await StillExport.capture(get_viewport(), p, false, _hide_always(), _hide_for_transparent())
		print("demo still saved: ", p)
	get_tree().quit()


func _render_demo_weapon(path: String) -> void:
	# Chudan kamae with a bokken, built the way paired practice is meant to be authored: the weapon
	# is placed directly (weapon-driven) and both hands snap onto it at their canonical hold.
	var tori: CharacterRig = posing_scene.get_character("tori")
	var uke: CharacterRig = posing_scene.get_character("uke1")
	controller.set_root(tori, Vector3(0, 0, -0.6), 0.0)
	controller.set_root(uke, Vector3(0, 0, 0.9), PI)
	await get_tree().process_frame
	var w: Weapon = posing_scene.add_weapon("bokken1", "bokken")
	w.drive = "weapon"
	var along := Vector3(0, 0.45, 0.9).normalized()       # tip forward and up, toward the throat
	var up := Vector3(0, 0.9, -0.45).normalized()          # edge (-Z) faces down and forward
	w.global_transform = Transform3D(Basis(along.cross(up), along, up), tori.global_position + Vector3(0.0, 1.02, 0.25))
	grip_director.attach_default_hands(tori, w)
	for i in 4:
		await get_tree().process_frame
	print("weapon grip error: %.4f m (shortfall R %.3f, L %.3f)" % [grip_director.worst_error(),
		tori.limbs["RightArm"].reach_shortfall(), tori.limbs["LeftArm"].reach_shortfall()])
	var axis: Vector3 = w.global_transform.basis.y
	var edge: Vector3 = -w.global_transform.basis.z
	for side in ["Right", "Left"]:
		var hand: Transform3D = tori.bone_world_transform(side + "Hand")
		var palm: Vector3 = hand * Weapon.palm_centre(tori, side)
		var fingers: Vector3 = (tori.bone_world_transform(side + "MiddleProximal").origin - hand.origin).normalized()
		var tip: Vector3 = tori.bone_world_transform(side + "MiddleDistal").origin
		var thumb: Vector3 = tori.bone_world_transform(side + "ThumbDistal").origin
		var normal: Vector3 = hand.basis * tori.fingers.palm_normal(side)
		var to_axis := func(pt: Vector3) -> float:
			var rel: Vector3 = pt - w.global_position
			return (rel - axis * rel.dot(axis)).length()
		print("%s hand: fingers/axis angle %.0f deg, palm centre %.3f m from axis, middle tip %.3f m from axis, palm normal . edge %.2f, thumb along axis %.3f vs palm %.3f" % [
			side, rad_to_deg(acos(absf(fingers.dot(axis)))), to_axis.call(palm), to_axis.call(tip), normal.dot(edge),
			(thumb - w.global_position).dot(axis), (palm - w.global_position).dot(axis)])
	for side in ["Right", "Left"]:
		var limb: Limb = tori.limbs[side + "Arm"]
		print("%s arm: shoulder %s elbow %s pole %s target %s" % [side, tori.bone_world_transform(side + "UpperArm").origin, tori.bone_world_transform(side + "LowerArm").origin, limb.pole.global_position, limb.target.global_position])
	var hands: Vector3 = w.anchor_transform(0.1).origin
	var rh: Vector3 = tori.bone_world_transform("RightHand").origin
	var views := {
		"_rh_side": [Vector3(-1, 0.2, 0.3), rh, 0.35],
		"_rh_top": [Vector3(0, 1, 0.1), rh, 0.35],
		"_rh_tip": [axis, rh, 0.35],
		"": [Vector3(1, 0.3, 0.7), Vector3(0, 1.0, -0.2), 2.4],
		"_hands": [Vector3(1, 0.5, 0.4), hands, 0.6],
		"_hands_top": [Vector3(0.2, 1, 0.3), hands, 0.6],
		"_hands_front": [Vector3(0.1, 0.1, 1), hands, 0.6],
	}
	for suffix in views:
		var v: Array = views[suffix]
		camera.look_from(v[0], v[1], v[2])
		for i in 3:
			await get_tree().process_frame
		var p: String = path.get_basename() + str(suffix) + ".png"
		await StillExport.capture(get_viewport(), p, false, _hide_always(), _hide_for_transparent())
		print("weapon demo saved: ", p)
	get_tree().quit()


## Test hook: the right hand alone, open and closed, seen from the palm and from the thumb side.
func _render_demo_hand(path: String) -> void:
	var tori: CharacterRig = posing_scene.get_character("tori")
	posing_scene.remove_character("uke1")
	await get_tree().process_frame
	for curl in [0.0, 1.0]:
		tori.fingers.set_hand_curl("Right", curl)
		for i in 3:
			await get_tree().process_frame
		var hand: Transform3D = tori.bone_world_transform("RightHand")
		var normal: Vector3 = hand.basis * tori.fingers.palm_normal("Right")
		var width: Vector3 = hand.basis * tori.fingers.palm_width("Right")
		var centre: Vector3 = hand * Vector3(0, 0.07, 0)
		var joints := ["RightHand", "RightIndexProximal", "RightIndexIntermediate", "RightIndexDistal"]
		var pts: Array = []
		for j in joints:
			pts.append(tori.bone_world_transform(j).origin)
		var tip_dir: Vector3 = tori.bone_world_transform("RightIndexDistal").basis.y
		var angles := []
		for k in range(1, pts.size() - 1):
			var a: Vector3 = (pts[k] - pts[k - 1]).normalized()
			var b: Vector3 = (pts[k + 1] - pts[k]).normalized()
			angles.append("%.0f" % rad_to_deg(acos(clampf(a.dot(b), -1, 1))))
		print("curl %.1f: index joint bend angles %s deg; distal axis . palm normal %.2f; tip toward palm %.3f m" % [
			curl, angles, tip_dir.dot(normal), (pts[3] - pts[0]).dot(normal)])
		for view in [["palm", normal], ["thumb", width], ["edge", normal.cross(width)]]:
			camera.look_from(view[1], centre, 0.35)
			for i in 3:
				await get_tree().process_frame
			var p: String = "%s_%s_%.0f.png" % [path.get_basename(), view[0], curl]
			await StillExport.capture(get_viewport(), p, false, _hide_always(), _hide_for_transparent())
			print("hand demo saved: ", p)
	get_tree().quit()


## Test hook: both figures in gi, standing and in a katatedori with one arm raised, so the
## jacket, sleeves, trousers and belt can be looked at from the front, the side and up close.
func _render_demo_gi(path: String) -> void:
	var tori: CharacterRig = posing_scene.get_character("tori")
	var uke: CharacterRig = posing_scene.get_character("uke1")
	controller.set_root(tori, Vector3(-0.35, 0, -0.1), deg_to_rad(20))
	controller.set_root(uke, Vector3(0.35, 0, 0.1), deg_to_rad(-160))
	tori.set_gi_visible(true)
	uke.set_gi_visible(true)
	# Uke bends forward at the waist, so the render shows the cloth following the spine too.
	var uke_sk := uke.skeleton
	uke_sk.set_bone_pose_rotation(uke_sk.find_bone("Spine"), Quaternion(Vector3(1, 0, 0), deg_to_rad(35)) * uke_sk.get_bone_rest(uke_sk.find_bone("Spine")).basis.get_rotation_quaternion())
	await get_tree().process_frame
	await controller.set_limb_mode(tori, "RightArm", Limb.Mode.IK)
	tori.limbs["RightArm"].target.global_position = tori.bone_world_transform("RightUpperArm").origin + Vector3(0.1, 0.35, 0.25)
	tori.limbs["RightArm"].reset_pole()
	await controller.set_limb_mode(uke, "LeftArm", Limb.Mode.IK)
	uke.limbs["LeftArm"].target.global_position = uke.bone_world_transform("LeftUpperArm").origin + Vector3(0.0, -0.2, 0.3)
	uke.limbs["LeftArm"].reset_pole()
	for i in 4:
		await get_tree().process_frame
	var mid := Vector3(0, 0.95, 0)
	var views := {
		"_front": [Vector3(0.0, 0.3, 1.0), mid, 3.2],
		"_side": [Vector3(1.0, 0.3, 0.2), mid, 3.2],
		"_back": [Vector3(0.0, 0.3, -1.0), mid, 3.2],
		"_belt": [Vector3(0.3, 0.2, 1.0), tori.global_position + Vector3(0, 0.98, 0), 0.9],
		"_sleeve": [Vector3(0.2, 0.6, 1.0), tori.bone_world_transform("RightLowerArm").origin, 0.8],
		"_shoulder": [Vector3(-0.3, 0.1, 1.0), tori.bone_world_transform("RightUpperArm").origin, 0.7],
		"_collar": [Vector3(0.4, 0.6, 1.0), tori.bone_world_transform("Neck").origin + Vector3(0, -0.05, 0), 0.5],
		"_collar_back": [Vector3(0.2, 0.6, -1.0), tori.bone_world_transform("Neck").origin, 0.5],
	}
	for suffix in views:
		var v: Array = views[suffix]
		camera.look_from(v[0], v[1], v[2])
		for i in 3:
			await get_tree().process_frame
		var p: String = path.get_basename() + str(suffix) + ".png"
		await StillExport.capture(get_viewport(), p, false, _hide_always(), _hide_for_transparent())
		print("gi demo saved: ", p)
	get_tree().quit()
