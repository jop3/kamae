extends Node3D
var f := 0
func _ready():
	var cam := Camera3D.new(); add_child(cam); cam.position = Vector3(0,1,3); cam.look_at(Vector3(0,1,0))
	var m := MeshInstance3D.new(); m.mesh = CapsuleMesh.new(); m.position = Vector3(0,1,0)
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.1,0.6,0.6); mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL; m.material_override = mat; add_child(m)
	var l := DirectionalLight3D.new(); add_child(l); l.rotation_degrees = Vector3(-45,30,0)
	get_viewport().transparent_bg = true
func _process(_d):
	f += 1
	$"MeshInstance3D".rotate_y(0.1) if has_node("MeshInstance3D") else null
	if f == 2:
		var img := get_viewport().get_texture().get_image(); img.save_png("user://still.png")
		print("still saved ", img.get_width(), "x", img.get_height(), " fmt=", img.get_format(), " corner_alpha=", img.get_pixel(2,2).a, " center_alpha=", img.get_pixel(320,180).a)
	if f == 15: get_tree().quit()
