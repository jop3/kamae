class_name CharacterRig
extends Node3D
## One posable humanoid. Instanced once per character in the scene.
## Loads the shared mannequin GLB at runtime (no editor import step needed) and exposes
## the Skeleton3D, the body mesh and a per-instance skin material.

const MANNEQUIN_PATH := "res://assets/characters/mannequin.glb"
## Skin, iris, brow, lash and hair images for the realistic look (MakeHuman CC0, see LICENSE.md).
const TEXTURES := "res://assets/characters/textures/"
static var _cached_scene: PackedScene
static var _textures := {}

var character_id: String = ""
var display_name: String = ""
var role: String = "Other"  # Tori | Uke | Other
var skeleton: Skeleton3D
var body: MeshInstance3D
var skin_material: StandardMaterial3D
## The figure's identification colour: the skin itself in the mannequin look, the belt and the
## panel's swatch in the realistic one (spec §5.1's colour cue, kept once the skin is real).
var id_color := Color(0.8, 0.8, 0.8)
## How the figure looks (see set_appearance): "look" realistic | mannequin, "skin", "hair", "eyes".
var appearance := {}
## Eyes, brows and lashes, shown in the realistic look only.
var face_parts: Array[MeshInstance3D] = []
## Hair style name -> its mesh; at most one is shown.
var hair_meshes := {}
var fingers: FingerCurl
var arm_bridge: ArmBridge
## The white gi (spec §7.1), built on first use and toggled per character; saved with the pose.
var gi: Gi
var gi_visible := false
## The black hakama (the Gi node builds it), worn with or without the gi; saved with the pose.
var hakama_visible := false
## The anatomy of this body's joints (Joints), built once from the rest pose, and the modifier
## that holds every solved pose inside it (JointLimits), last in the stack.
var joints: Joints
var joint_limits: JointLimits
## Raises the clavicles with the arms (ShoulderGirdle), first in the stack so the arms solve
## from shoulders that have moved.
var girdle: ShoulderGirdle
## Bone global poses as the modifier stack left them, refreshed every skeleton_updated.
## Reading Skeleton3D directly outside that signal returns the *authored* pose, not the posed one
## (see docs/engine-notes.md), so everything that asks "where is this bone now" goes through here.
var _solved_poses: Array[Transform3D] = []
## bone -> the mesh's own radius along it, in BANDS bands from its joint to the next, measured
## from the rest pose (skin_radius).
var _skin_radii: Dictionary = {}
const BANDS := 4
## side -> the palm as a box in the hand bone's frame (palm_box).
var _palm_boxes: Dictionary = {}
## limb key ("RightArm", "LeftLeg", …) -> Limb
var limbs: Dictionary = {}
## False while rendering for export: IK handles stay hidden whatever the limb modes do.
var show_handles := true
## Set by PoseBlend for a figure blended into or out of a fall, between the two poses only: once
## the pose has solved, the figure is rested on the mat (Ukemi.keep_on_mat) — lifted out of it or
## lowered onto it. The blend grounds a fall from the pose alone, before the IK runs; this catches
## what only the solve shows: a hand put down by IK, a fingertip, the legs an IK stance lets go of.
var keep_on_mat := false
## The fall this figure is in, as Ukemi shaped it: {"kind": "forward"|"backward"|"prone",
## "t": 0..1}, empty when it is not falling. Saved with the pose; a blend between two poses
## of one fall follows the fall's own course between them (PoseBlend, Ukemi.blend_fall).
var fall := {}

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
	for mi in mannequin.find_children("*", "MeshInstance3D", true, false):
		if mi.name == "Body":
			body = mi
		elif String(mi.name).begins_with("Hair_"):
			hair_meshes[String(mi.name).trim_prefix("Hair_")] = mi
		else:
			face_parts.append(mi)
	skin_material = StandardMaterial3D.new()
	skin_material.roughness = 0.9
	body.material_override = skin_material
	set_skin_color(Color(0.8, 0.8, 0.8))
	set_appearance(Palette.appearance_for_index(0))
	_solved_poses.resize(skeleton.get_bone_count())
	_cache_solved_poses()          # seed with the rest pose so limbs can be built against it
	skeleton.skeleton_updated.connect(_cache_solved_poses)
	_build_limbs()


## Modifier order on the skeleton is child order: the shoulder girdle, finger curls, then each
## limb's IK solve followed by its twist and hand-orientation modifiers, and the joint limits last.
func _build_limbs() -> void:
	girdle = ShoulderGirdle.new()
	girdle.name = "ShoulderGirdle"
	girdle.rig = self
	skeleton.add_child(girdle)
	fingers = FingerCurl.new()
	fingers.name = "FingerCurl"
	fingers.rig = self
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
	joints = Joints.build(skeleton, fingers)
	joint_limits = JointLimits.new()
	joint_limits.name = "JointLimits"
	joint_limits.rig = self
	skeleton.add_child(joint_limits)   # last: whatever the limbs asked for, the joints decide


## Orders the modifiers so `key`'s arm solves first, then the bridge, then the other arm.
func put_arm_first(key: String) -> void:
	var other := "LeftArm" if key == "RightArm" else "RightArm"
	var first: Limb = limbs[key]
	var second: Limb = limbs[other]
	var i := fingers.get_index() + 1
	for node in [first.ik, first.twist, first.hand_orient, arm_bridge, second.ik, second.twist, second.hand_orient]:
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
	id_color = color
	if appearance.get("look", "mannequin") == "mannequin":
		skin_material.albedo_color = color
	if gi:
		gi.set_belt_color(color)   # the belt follows the character colour (spec §7.1)


## Sets how the figure looks. Keys, each optional (missing ones keep their current value):
##   look  "realistic" (textured skin, eyes, brows, hair) or "mannequin" (one flat colour)
##   skin  a texture under textures/ without its prefix: "middleage_caucasian_male", …
##   hair  a style exported in the GLB ("short02", "short04", "short01", "ponytail01", "bob02") or "none"
##   hair_color  an optional tint multiplied into the hair texture, "#rrggbb"
##   eyes  "brown", "blue", "grey", "green"
func set_appearance(a: Dictionary) -> void:
	for k in a:
		appearance[k] = a[k]
	var real: bool = appearance.get("look", "realistic") == "realistic"
	if real:
		skin_material.albedo_color = Color.WHITE
		skin_material.albedo_texture = _texture("skin_%s.jpg" % appearance.get("skin", "middleage_caucasian_male"))
		skin_material.roughness = 0.62
		skin_material.metallic_specular = 0.35
		# A soft rim stands in for the light that scatters through skin, which the
		# Compatibility renderer does not model; without it the skin reads as painted plaster.
		skin_material.rim_enabled = true
		skin_material.rim = 0.25
		skin_material.rim_tint = 0.6
	else:
		skin_material.albedo_texture = null
		skin_material.albedo_color = id_color
		skin_material.roughness = 0.9
		skin_material.metallic_specular = 0.5
		skin_material.rim_enabled = false
	for mi in face_parts:
		mi.visible = real
		if mi.material_override == null:
			mi.material_override = _part_material(String(mi.name))
	var eyes := _find_part("Eyes")
	if eyes:
		eyes.material_override.albedo_texture = _texture("eye_%s.png" % appearance.get("eyes", "brown"))
	var style: String = appearance.get("hair", "none")
	for h in hair_meshes:
		var mi: MeshInstance3D = hair_meshes[h]
		mi.visible = real and h == style
		if mi.visible:
			if mi.material_override == null:
				mi.material_override = _cutout_material("hair_%s.png" % h)
			mi.material_override.albedo_color = Color.html(appearance.get("hair_color", "#ffffff"))


func _find_part(part: String) -> MeshInstance3D:
	for mi in face_parts:
		if mi.name == part:
			return mi
	return null


func _part_material(part: String) -> StandardMaterial3D:
	match part:
		"Eyes":
			# The eye mesh has the eyeball and, in front of it, a cornea whose part of the image
			# is fully transparent: cut out, it shows the iris; drawn opaque, the eyes are black.
			var m := StandardMaterial3D.new()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.5
			m.roughness = 0.2
			m.metallic_specular = 0.7
			return m
		"Eyebrows":
			return _cutout_material("eyebrow001.png")
		"Eyelashes":
			return _cutout_material("eyelashes01.png")
	return StandardMaterial3D.new()


## Hair, brows and lashes are cards with an alpha image. Alpha scissor with antialiasing (alpha to
## coverage under the project's MSAA) keeps them sorted correctly against each other and the gi,
## which blended transparency does not.
func _cutout_material(file: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _texture(file)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.75
	m.metallic_specular = 0.3
	return m


## Images are loaded from the file at runtime, like the GLB, with mipmaps: a 2K skin seen at a
## few hundred pixels shimmers in a video without them, and the importer's defaults do not make them.
static func _texture(file: String) -> Texture2D:
	if _textures.has(file):
		return _textures[file]
	# Read as bytes rather than with Image.load_from_file, which warns about every file the
	# editor has also imported; export_presets.cfg ships the files themselves for an export.
	var bytes := FileAccess.get_file_as_bytes(TEXTURES + file)
	var img := Image.new()
	var err := img.load_jpg_from_buffer(bytes) if file.ends_with(".jpg") else img.load_png_from_buffer(bytes)
	assert(err == OK and not img.is_empty(), "Could not load texture %s" % file)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_textures[file] = tex
	return tex


## Dresses or undresses the character. The gi is built the first time it is asked for.
func set_gi_visible(on: bool) -> void:
	gi_visible = on
	if on:
		_build_gi()
	if gi:
		gi.set_visible(on)


## The black hakama, over the gi or on its own; toggled and saved apart from the gi.
func set_hakama_visible(on: bool) -> void:
	hakama_visible = on
	if on:
		_build_gi()   # the hakama is measured over the gi, so the gi is built (hidden) too
	if gi:
		gi.set_hakama_visible(on)


func _build_gi() -> void:
	if gi == null:
		gi = Gi.new()
		gi.name = "Gi"
		add_child(gi)
		gi.build(self)
		gi.set_visible(gi_visible)


func get_skin_color() -> Color:
	return id_color


## The radius of the *mesh* around `bone` in the rest pose, in metres: the median distance from
## the bone's axis of the vertices it mostly owns. This is what a hand holding that bone has to
## close around, and it is not `BodyCapsules.radius`, which is a deliberately coarse collision
## capsule — a forearm's capsule is 40 mm where the skin is 27 mm, and a grip seated on the
## capsule floats above the arm. Measured once per rig and kept.
## `along` is where on the bone (0 its own joint, 1 the next), because a limb tapers: this
## forearm is 35 mm at the elbow and 23 mm at the wrist, and a grip seated on the average of the
## two sinks into one end.
func skin_radius(bone_name: String, along: float = 0.5) -> float:
	if _skin_radii.is_empty():
		_measure_skin_radii()
	var bands: PackedFloat32Array = _skin_radii.get(bone_name, PackedFloat32Array())
	if bands.is_empty():
		return BodyCapsules.radius(bone_name)
	return bands[clampi(int(clampf(along, 0.0, 0.999) * bands.size()), 0, bands.size() - 1)]


func _measure_skin_radii() -> void:
	_skin_radii = {"": 0.0}   # never empty again, even if the mesh cannot be read
	if body == null or body.mesh == null or body.skin == null or skeleton == null:
		return
	var arrays: Array = body.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if verts.is_empty() or bones.is_empty():
		return
	var per_vertex := bones.size() / verts.size()
	var bind_bone := PackedInt32Array()
	for b in body.skin.get_bind_count():
		var bone := body.skin.get_bind_bone(b)
		if bone < 0:
			bone = skeleton.find_bone(body.skin.get_bind_name(b))
		bind_bone.append(bone)
	var axis := {}
	var by_bone := {}   # bone -> band -> distances
	for v in verts.size():
		var best := -1
		var best_w := 0.0
		for k in per_vertex:
			var w := weights[v * per_vertex + k]
			if w > best_w:
				best_w = w
				best = bind_bone[bones[v * per_vertex + k]]
		# A vertex shared between two bones says nothing about either one's thickness.
		if best < 0 or best_w < 0.6:
			continue
		if not axis.has(best):
			var kids := skeleton.get_bone_children(best)
			var a: Vector3 = skeleton.get_bone_global_rest(best).origin
			var b: Vector3 = a + skeleton.get_bone_global_rest(best).basis.y * 0.08
			if kids.size() > 0:
				b = skeleton.get_bone_global_rest(kids[0]).origin
			axis[best] = [a, b]
			by_bone[best] = []
			for band in BANDS:
				by_bone[best].append(PackedFloat32Array())
		var a0: Vector3 = axis[best][0]
		var ab: Vector3 = axis[best][1] - a0
		var along := clampf((verts[v] - a0).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 0.999)
		by_bone[best][int(along * BANDS)].append(verts[v].distance_to(BodyCapsules.closest_on_segment(verts[v], a0, axis[best][1])))
	for bone: int in by_bone:
		var bands := PackedFloat32Array()
		var ok := true
		for band: PackedFloat32Array in by_bone[bone]:
			if band.size() < 8:
				ok = false
				break
			band.sort()
			bands.append(band[band.size() / 2])
		if ok:
			_skin_radii[skeleton.get_bone_name(bone)] = bands


## The palm as a box in the hand bone's frame, measured off the rest mesh: how far it reaches
## along the hand (y), how deep it is from the back of the hand to the palm's own surface
## (along the palm normal) and how wide (along the palm width). This is what a finger closing
## has to stop at. Nothing told the curl the palm was there before, so a finger at full curl
## closed *into* the hand rather than onto it, and a fist was a smooth lump rather than four
## fingers (--demo-hands). Keys: y_min, y_max, back, front, half_width.
func palm_box(side: String) -> Dictionary:
	if _palm_boxes.is_empty():
		_measure_palm_boxes()
	return _palm_boxes.get(side, {})


func _measure_palm_boxes() -> void:
	_palm_boxes = {"": {}}
	if body == null or body.mesh == null or body.skin == null or skeleton == null or fingers == null:
		return
	var arrays: Array = body.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if verts.is_empty() or bones.is_empty():
		return
	var per_vertex := bones.size() / verts.size()
	var bind_bone := PackedInt32Array()
	for b in body.skin.get_bind_count():
		var bone := body.skin.get_bind_bone(b)
		if bone < 0:
			bone = skeleton.find_bone(body.skin.get_bind_name(b))
		bind_bone.append(bone)
	for side in ["Right", "Left"]:
		var hand := skeleton.find_bone(side + "Hand")
		if hand < 0:
			continue
		var to_hand: Transform3D = skeleton.get_bone_global_rest(hand).affine_inverse()
		var n: Vector3 = fingers.palm_normal(side).normalized()
		var w: Vector3 = fingers.palm_width(side).normalized()
		var along := PackedFloat32Array()
		var depth := PackedFloat32Array()
		var across := PackedFloat32Array()
		for v in verts.size():
			var best := -1
			var best_w := 0.0
			for k in per_vertex:
				var weight := weights[v * per_vertex + k]
				if weight > best_w:
					best_w = weight
					best = bind_bone[bones[v * per_vertex + k]]
			if best != hand or best_w < 0.6:
				continue
			var p: Vector3 = to_hand * verts[v]
			along.append(p.y)
			depth.append(p.dot(n))
			across.append(p.dot(w))
		if along.size() < 20:
			continue
		along.sort(); depth.sort(); across.sort()
		var pct := func(arr: PackedFloat32Array, f: float) -> float:
			return arr[clampi(int(arr.size() * f), 0, arr.size() - 1)]
		_palm_boxes[side] = {
			"y_min": pct.call(along, 0.05), "y_max": pct.call(along, 0.95),
			"back": pct.call(depth, 0.05), "front": pct.call(depth, 0.90),
			"half_width": maxf(absf(pct.call(across, 0.05)), absf(pct.call(across, 0.95))),
		}


func bone_names() -> PackedStringArray:
	var names := PackedStringArray()
	for i in skeleton.get_bone_count():
		names.append(skeleton.get_bone_name(i))
	return names


func _cache_solved_poses() -> void:
	for i in skeleton.get_bone_count():
		_solved_poses[i] = skeleton.get_bone_global_pose(i)
	if keep_on_mat:
		Ukemi.keep_on_mat(self)


## Where a bone actually is on screen, in world space, as of the last completed pose evaluation.
## Use this everywhere except inside skeleton_updated itself, where the live values are available
## and are one frame fresher (grip following needs that; UI and tests do not).
func bone_world_transform(bone_name: String) -> Transform3D:
	var idx := skeleton.find_bone(bone_name)
	assert(idx >= 0, "Unknown bone %s" % bone_name)
	return skeleton.global_transform * _solved_poses[idx]


## Where a bone would be under the pose alone, with every modifier ignored: the bone poses that
## were last set, walked up the chain to the root. IK, twist and hand orientation do not enter,
## so this is the only reading that does not depend on a solve having happened, and the only one
## a correction can be derived from without feeding its own output back in (MotionClearance).
func fk_bone_transform(bone_name: String) -> Transform3D:
	var idx := skeleton.find_bone(bone_name)
	assert(idx >= 0, "Unknown bone %s" % bone_name)
	var t := Transform3D.IDENTITY
	while idx >= 0:
		t = skeleton.get_bone_pose(idx) * t
		idx = skeleton.get_bone_parent(idx)
	return skeleton.global_transform * t


## Same value read live from the skeleton. Only correct inside skeleton_updated.
func bone_world_transform_live(bone_name: String) -> Transform3D:
	var idx := skeleton.find_bone(bone_name)
	assert(idx >= 0, "Unknown bone %s" % bone_name)
	return skeleton.global_transform * skeleton.get_bone_global_pose(idx)
