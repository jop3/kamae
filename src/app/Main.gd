extends Node3D
## Application root: 3D view + posing controller + side panel.

@onready var posing_scene: PosingScene = $PosingScene
@onready var camera: OrbitCamera = $OrbitCamera
@onready var gizmo: RotationGizmo = $RotationGizmo
@onready var controller: PoseController = $PoseController
@onready var panel: SidePanel = $UI/SidePanel
@onready var floor_grid: Node3D = $FloorGrid
@onready var ui_layer: CanvasLayer = $UI

var export_dir := "user://exports"


func _ready() -> void:
	posing_scene.setup_default()
	controller.setup(posing_scene, camera, gizmo)
	panel.setup(controller, posing_scene)
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
	var axis: Dictionary = posing_scene.tori_uke_axis()
	var center: Vector3 = axis["center"] + Vector3(0, 0.9, 0)
	camera.look_from(Vector3(1, 0.35, 0.6), center, 4.0)


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


## Test hook: shows what M2 provides on one figure — an arm placed by IK with the hand oriented to
## the target, and fingers closed into a grip. Two-character grips arrive in M3.
func _render_demo_still(path: String) -> void:
	var tori: CharacterRig = posing_scene.get_character("tori")
	posing_scene.remove_character("uke1")
	controller.set_root(tori, Vector3.ZERO, deg_to_rad(200))
	await get_tree().process_frame
	await controller.set_limb_mode(tori, "RightArm", Limb.Mode.IK)
	var shoulder: Vector3 = tori.bone_world_transform("RightUpperArm").origin
	var arm: Limb = tori.limbs["RightArm"]
	# Forward and slightly up from the shoulder, well inside the arm's reach.
	arm.target.global_position = shoulder + Vector3(0.12, -0.02, 0.34)
	tori.fingers.apply_grip_preset("Right")
	camera.look_from(Vector3(0.8, 0.15, 0.6), Vector3(0.05, 1.15, 0.1), 1.5)
	for i in 4:
		await get_tree().process_frame
	await StillExport.capture(get_viewport(), path, false, _hide_always(), _hide_for_transparent())
	print("demo still saved: ", path)
	get_tree().quit()
