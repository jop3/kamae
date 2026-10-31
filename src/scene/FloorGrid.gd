class_name FloorGrid
extends MeshInstance3D
## 1 m grid on the floor with a darker centre cross, on a mat the colour of tatami, so a white gi
## stands out against the floor the way it does in a dojo.

@export var half_extent: int = 5


func _ready() -> void:
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for i in range(-half_extent, half_extent + 1):
		var c := Color(0.58, 0.62, 0.52) if i != 0 else Color(0.42, 0.46, 0.38)
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(i, 0.001, -half_extent))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(i, 0.001, half_extent))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(-half_extent, 0.001, i))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(half_extent, 0.001, i))
	im.surface_end()
	mesh = im
	var plane := MeshInstance3D.new()
	plane.mesh = PlaneMesh.new()
	plane.mesh.size = Vector2(half_extent * 2, half_extent * 2)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.60, 0.66, 0.53)
	pm.roughness = 0.95
	plane.material_override = pm
	add_child(plane)
