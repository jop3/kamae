class_name FloorGrid
extends MeshInstance3D
## 1 m grid on the floor with a brighter centre cross.

@export var half_extent: int = 5


func _ready() -> void:
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for i in range(-half_extent, half_extent + 1):
		var c := Color(0.55, 0.55, 0.55) if i != 0 else Color(0.3, 0.3, 0.3)
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
	pm.albedo_color = Color(0.93, 0.93, 0.93)
	plane.material_override = pm
	add_child(plane)
