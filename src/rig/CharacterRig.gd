class_name CharacterRig
extends Node3D
## One posable humanoid. Instanced once per character in the scene.
## Loads the shared mannequin GLB at runtime (no editor import step needed) and exposes
## the Skeleton3D, the body mesh and a per-instance skin material.

const MANNEQUIN_PATH := "res://assets/characters/mannequin.glb"
static var _cached_scene: PackedScene

var character_id: String = ""
var display_name: String = ""
var role: String = "Other"  # Tori | Uke | Other
var skeleton: Skeleton3D
var body: MeshInstance3D
var skin_material: StandardMaterial3D


static func load_mannequin_scene() -> PackedScene:
	if _cached_scene:
		return _cached_scene
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(MANNEQUIN_PATH, state)
	assert(err == OK, "Could not load mannequin: %s" % error_string(err))
	var root := doc.generate_scene(state)
	root.name = "Mannequin"
	var packed := PackedScene.new()
	# generate_scene returns nodes with no owner; set owners so pack() keeps the whole tree.
	_set_owner_recursive(root, root)
	packed.pack(root)
	root.free()
	_cached_scene = packed
	return packed


static func _set_owner_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_set_owner_recursive(child, owner)


func _ready() -> void:
	if skeleton == null:
		setup()


func setup() -> void:
	if skeleton != null:
		return
	var mannequin := load_mannequin_scene().instantiate()
	add_child(mannequin)
	skeleton = mannequin.find_children("*", "Skeleton3D", true, false)[0]
	body = mannequin.find_children("*", "MeshInstance3D", true, false)[0]
	skin_material = StandardMaterial3D.new()
	skin_material.roughness = 0.9
	body.material_override = skin_material
	set_skin_color(Color(0.8, 0.8, 0.8))


func set_skin_color(color: Color) -> void:
	skin_material.albedo_color = color


func get_skin_color() -> Color:
	return skin_material.albedo_color


func bone_names() -> PackedStringArray:
	var names := PackedStringArray()
	for i in skeleton.get_bone_count():
		names.append(skeleton.get_bone_name(i))
	return names


## World-space transform of a bone, valid after skeleton_updated for the current frame.
func bone_world_transform(bone_name: String) -> Transform3D:
	var idx := skeleton.find_bone(bone_name)
	assert(idx >= 0, "Unknown bone %s" % bone_name)
	return skeleton.global_transform * skeleton.get_bone_global_pose(idx)
