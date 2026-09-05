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


func _ready() -> void:
	posing_scene.setup_default()
	controller.setup(posing_scene, camera, gizmo)
	grip_director.setup(posing_scene, controller)
	panel.setup(controller, posing_scene, grip_director, camera)
	panel.export_requested.connect(_on_export_requested)
	frame_all()
	var args := OS.get_cmdline_user_args()
	if args.has("--demo-still"):
		await _render_demo_still(args[args.find("--demo-still") + 1])
		return
	if args.has("--demo-weapon"):
		await _render_demo_weapon(args[args.find("--demo-weapon") + 1])
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


func frame_all() -> void:
	camera.fov = CameraPresets.FOV_DEG
	camera.apply_preset(CameraPresets.side(posing_scene))


func _on_export_requested(transparent: bool) -> void:
	var name := StillExport.slugify("pose_%s" % Time.get_datetime_string_from_system().replace(":", "-"))
	var path := ProjectSettings.globalize_path(export_dir).path_join(name + ".png")
	var err: Error = await StillExport.capture(get_viewport(), path, transparent, _hide_always(), _hide_for_transparent())
	print("Exported %s (%s)" % [path, error_string(err)])


## Never part of an exported image: the UI dock, the rotation gizmo and every IK handle.
func _hide_always() -> Array[Node]:
	var out: Array[Node] = [ui_layer, gizmo]
	for rig in posing_scene.characters:
		out.append_array(rig.handles())
	return out


## Only hidden when exporting on a transparent background.
func _hide_for_transparent() -> Array[Node]:
	return [floor_grid]


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
	grip_director.attach_to_weapon(tori, "Left", w, 0.04, true)
	grip_director.attach_to_weapon(tori, "Right", w, 0.17, true)
	tori.fingers.apply_grip_preset("Right")
	tori.fingers.apply_grip_preset("Left")
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
