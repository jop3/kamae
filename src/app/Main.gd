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


## Never part of an exported image: the UI dock and the posing gizmo.
func _hide_always() -> Array[Node]:
	return [ui_layer, gizmo]


## Only hidden when exporting on a transparent background.
func _hide_for_transparent() -> Array[Node]:
	return [floor_grid]
