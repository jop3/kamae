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
var fingers: FingerCurl
var arm_bridge: ArmBridge
## Bone global poses as the modifier stack left them, refreshed every skeleton_updated.
## Reading Skeleton3D directly outside that signal returns the *authored* pose, not the posed one
## (see docs/engine-notes.md), so everything that asks "where is this bone now" goes through here.
var _solved_poses: Array[Transform3D] = []
## limb key ("RightArm", "LeftLeg", …) -> Limb
var limbs: Dictionary = {}
## False while rendering for export: IK handles stay hidden whatever the limb modes do.
var show_handles := true

## The four IK-able chains, in the order their nodes are added to the skeleton.
const LIMB_CHAINS := [
	["RightArm", "RightUpperArm", "RightLowerArm", "RightHand", true],
	["LeftArm", "LeftUpperArm", "LeftLowerArm", "LeftHand", true],
	["RightLeg", "RightUpperLeg", "RightLowerLeg", "RightFoot", false],
	["LeftLeg", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", false],
]


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


## Keeps target colours honest: a target the limb cannot reach is drawn red.
func _process(_delta: float) -> void:
	for key in limbs:
		var limb: Limb = limbs[key]
		if limb.mode == Limb.Mode.IK:
			limb.target.set_unreachable(limb.reach_shortfall() > 0.001)


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
	_solved_poses.resize(skeleton.get_bone_count())
	_cache_solved_poses()          # seed with the rest pose so limbs can be built against it
	skeleton.skeleton_updated.connect(_cache_solved_poses)
	_build_limbs()


## Modifier order on the skeleton is child order: finger curls first, then each limb's
## IK solve followed by its hand-orientation modifier.
func _build_limbs() -> void:
	fingers = FingerCurl.new()
	fingers.name = "FingerCurl"
	skeleton.add_child(fingers)
	fingers.calibrate()
	for chain in LIMB_CHAINS:
		var limb := Limb.new(chain[0], chain[1], chain[2], chain[3], chain[4])
		var target := LimbHandle.new(character_id, limb.key, false)
		var pole := LimbHandle.new(character_id, limb.key, true)
		add_child(target)
		add_child(pole)
		limb.build(self, skeleton, target, pole)
		limbs[limb.key] = limb
		_set_handles_visible(limb, false)
		if limb.key == "RightArm":
			arm_bridge = ArmBridge.new()
			arm_bridge.name = "ArmBridge"
			skeleton.add_child(arm_bridge)   # between the two arms' solvers


## Orders the modifiers so `key`'s arm solves first, then the bridge, then the other arm.
func put_arm_first(key: String) -> void:
	var other := "LeftArm" if key == "RightArm" else "RightArm"
	var first: Limb = limbs[key]
	var second: Limb = limbs[other]
	var i := fingers.get_index() + 1
	for node in [first.ik, first.hand_orient, arm_bridge, second.ik, second.hand_orient]:
		skeleton.move_child(node, i)
		i += 1


func set_limb_mode(limb_key: String, mode: int) -> void:
	var limb: Limb = limbs[limb_key]
	limb.set_mode(mode)
	_set_handles_visible(limb, mode == Limb.Mode.IK)


func _set_handles_visible(limb: Limb, visible_handles: bool) -> void:
	limb.target.visible = visible_handles and show_handles
	limb.pole.visible = visible_handles and show_handles


func set_show_handles(show: bool) -> void:
	show_handles = show
	for key in limbs:
		var limb: Limb = limbs[key]
		_set_handles_visible(limb, limb.mode == Limb.Mode.IK)


## Limb whose end bone (or a descendant of it) is `bone_name`, or "" when the bone is not on a limb.
## The IK target and pole balls. They are posing aids, never part of an exported image.
func handles() -> Array[Node]:
	var out: Array[Node] = []
	for key in limbs:
		var limb: Limb = limbs[key]
		out.append(limb.target)
		out.append(limb.pole)
	return out


func limb_for_bone(bone_name: String) -> String:
	for key in limbs:
		var limb: Limb = limbs[key]
		if bone_name in [limb.root_bone, limb.middle_bone, limb.end_bone]:
			return key
	return ""


func set_skin_color(color: Color) -> void:
	skin_material.albedo_color = color


func get_skin_color() -> Color:
	return skin_material.albedo_color


func bone_names() -> PackedStringArray:
	var names := PackedStringArray()
	for i in skeleton.get_bone_count():
		names.append(skeleton.get_bone_name(i))
	return names


func _cache_solved_poses() -> void:
	for i in skeleton.get_bone_count():
		_solved_poses[i] = skeleton.get_bone_global_pose(i)


## Where a bone actually is on screen, in world space, as of the last completed pose evaluation.
## Use this everywhere except inside skeleton_updated itself, where the live values are available
## and are one frame fresher (grip following needs that; UI and tests do not).
func bone_world_transform(bone_name: String) -> Transform3D:
	var idx := skeleton.find_bone(bone_name)
	assert(idx >= 0, "Unknown bone %s" % bone_name)
	return skeleton.global_transform * _solved_poses[idx]


## Same value read live from the skeleton. Only correct inside skeleton_updated.
func bone_world_transform_live(bone_name: String) -> Transform3D:
	var idx := skeleton.find_bone(bone_name)
	assert(idx >= 0, "Unknown bone %s" % bone_name)
	return skeleton.global_transform * skeleton.get_bone_global_pose(idx)
