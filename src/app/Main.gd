extends Node3D
## Application root. M0: scene with N characters, floor, light, orbit camera.

@onready var posing_scene: PosingScene = $PosingScene
@onready var camera: OrbitCamera = $OrbitCamera


func _ready() -> void:
	posing_scene.setup_default()
	frame_all()


func frame_all() -> void:
	var axis: Dictionary = posing_scene.tori_uke_axis()
	var center: Vector3 = axis["center"] + Vector3(0, 0.9, 0)
	camera.look_from(Vector3(1, 0.35, 0.6), center, 4.0)


## Command line: `-- --screenshot path.png` renders one frame and quits (used by tests).
func _process(_delta: float) -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--screenshot")
	if i >= 0 and Engine.get_process_frames() == 3:
		var img := get_viewport().get_texture().get_image()
		img.save_png(args[i + 1])
		print("screenshot saved: ", args[i + 1])
		get_tree().quit()
