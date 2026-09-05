class_name LimbHandle
extends Node3D
## Draggable ball for an IK target or pole. Turns red when the limb cannot reach the target.

const TARGET_RADIUS := 0.045
const POLE_RADIUS := 0.028
const COLOR_TARGET := Color(0.15, 0.45, 0.95)
const COLOR_POLE := Color(0.55, 0.55, 0.6)
const COLOR_UNREACHABLE := Color(0.9, 0.2, 0.2)
const PICK_LAYER := 4

var is_pole: bool
var mesh_instance: MeshInstance3D
var material: StandardMaterial3D


func _init(character_id: String, limb_key: String, pole: bool) -> void:
	is_pole = pole
	name = ("Pole_" if pole else "Target_") + limb_key
	var sphere := SphereMesh.new()
	var r := POLE_RADIUS if pole else TARGET_RADIUS
	sphere.radius = r
	sphere.height = r * 2.0
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = sphere
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = COLOR_POLE if pole else COLOR_TARGET
	material.no_depth_test = true
	material.render_priority = 5
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	var area := Area3D.new()
	area.collision_layer = PICK_LAYER
	area.collision_mask = 0
	area.input_ray_pickable = false
	area.set_meta("character_id", character_id)
	area.set_meta("limb_key", limb_key)
	area.set_meta("is_pole", pole)
	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = r * 1.6   # a little forgiving to click
	shape.shape = sphere_shape
	area.add_child(shape)
	add_child(area)


func set_unreachable(unreachable: bool) -> void:
	if is_pole:
		return
	material.albedo_color = COLOR_UNREACHABLE if unreachable else COLOR_TARGET
