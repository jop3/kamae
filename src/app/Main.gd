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
	panel.setup(controller, posing_scene, grip_director)
	panel.export_requested.connect(_on_export_requested)
	frame_all()
	var args := OS.get_cmdline_user_args()
	if args.has("--demo-still"):
		await _render_demo_still(args[args.find("--demo-still") + 1])
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
	camera.apply_preset(CameraPresets.front(posing_scene))


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


## Test hook: a katatedori grip — Uke's hand attached to Tori's wrist, held by the grip system.
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
	uke.limbs["LeftArm"].target.global_position = tori.bone_world_transform("RightLowerArm").origin + Vector3(0, 0.03, 0)
	for i in 3:
		await get_tree().process_frame
	grip_director.attach(uke, "Left", GripTarget.for_bone(posing_scene, "tori", "RightLowerArm"))
	uke.fingers.apply_grip_preset("Left")
	# Now move Tori: the grip must hold without touching Uke again.
	controller.set_root(tori, Vector3(0.05, 0, -0.20), deg_to_rad(12))
	for i in 4:
		await get_tree().process_frame
	print("grip error after moving Tori: %.4f m" % grip_director.worst_error())
	camera.look_from(Vector3(0.9, 0.30, 0.5), Vector3(0, 1.05, 0), 2.0)
	for i in 3:
		await get_tree().process_frame
	await StillExport.capture(get_viewport(), path, false, _hide_always(), _hide_for_transparent())
	print("demo still saved: ", path)
	get_tree().quit()
