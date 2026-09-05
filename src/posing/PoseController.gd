class_name PoseController
extends Node
## Selection, FK rotation (gizmo + sliders), root placement and undo/redo.

signal selection_changed(rig: CharacterRig, bone_name: String)
signal pose_changed

var scene: PosingScene
var camera: Camera3D
var gizmo: RotationGizmo
var undo := UndoRedo.new()

var selected_rig: CharacterRig
var selected_bone := ""
var _drag_old_rot := Quaternion.IDENTITY
var _highlight: MeshInstance3D


func setup(posing_scene: PosingScene, cam: Camera3D, giz: RotationGizmo) -> void:
	scene = posing_scene
	camera = cam
	gizmo = giz
	gizmo.camera = cam
	gizmo.drag_started.connect(_on_gizmo_drag_started)
	gizmo.rotated.connect(_on_gizmo_rotated)
	gizmo.drag_ended.connect(_on_gizmo_drag_ended)
	scene.characters_changed.connect(_on_characters_changed)
	_on_characters_changed()


func _on_characters_changed() -> void:
	for rig in scene.characters:
		if not rig.has_node("PickCapsules"):
			var pc := PickCapsules.new()
			pc.name = "PickCapsules"
			rig.add_child(pc)
			pc.build(rig)
	if selected_rig and not is_instance_valid(selected_rig):
		select(null, "")


# ---------------------------------------------------------------- selection

func select(rig: CharacterRig, bone_name: String) -> void:
	selected_rig = rig
	selected_bone = bone_name
	if rig and bone_name != "":
		_place_gizmo()
	else:
		gizmo.detach()
	selection_changed.emit(rig, bone_name)


func pick_bone(mouse: Vector2) -> Dictionary:
	var space := camera.get_world_3d().direct_space_state
	var from := camera.project_ray_origin(mouse)
	var to := from + camera.project_ray_normal(mouse) * 100.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 2)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {}
	var area: Node = hit["collider"]
	return {"character_id": area.get_meta("character_id"), "bone_name": area.get_meta("bone_name")}


func _place_gizmo() -> void:
	var sk := selected_rig.skeleton
	var idx := sk.find_bone(selected_bone)
	var g := sk.global_transform * sk.get_bone_global_pose(idx)
	gizmo.attach(g.origin, g.basis)


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var ring := gizmo.pick(event.position)
			if ring >= 0:
				gizmo.begin_drag(ring, event.position)
				get_viewport().set_input_as_handled()
				return
			var hit := pick_bone(event.position)
			if not hit.is_empty():
				select(scene.get_character(hit["character_id"]), hit["bone_name"])
				get_viewport().set_input_as_handled()
		else:
			if gizmo.active_axis >= 0:
				gizmo.end_drag()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if gizmo.active_axis >= 0:
			gizmo.drag_to(event.position)
			get_viewport().set_input_as_handled()
		else:
			gizmo.hover_axis = gizmo.pick(event.position)
	elif event is InputEventKey and event.pressed and event.ctrl_pressed:
		if event.keycode == KEY_Z and not event.shift_pressed:
			undo.undo(); pose_changed.emit(); _refresh_gizmo()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_Y or (event.keycode == KEY_Z and event.shift_pressed):
			undo.redo(); pose_changed.emit(); _refresh_gizmo()
			get_viewport().set_input_as_handled()


func _process(_d: float) -> void:
	if selected_rig and selected_bone != "" and gizmo.active_axis < 0:
		_place_gizmo()


func _refresh_gizmo() -> void:
	if selected_rig and selected_bone != "":
		_place_gizmo()


# ---------------------------------------------------------------- FK editing

func get_bone_rotation(rig: CharacterRig, bone_name: String) -> Quaternion:
	return rig.skeleton.get_bone_pose_rotation(rig.skeleton.find_bone(bone_name))


func set_bone_rotation(rig: CharacterRig, bone_name: String, q: Quaternion) -> void:
	rig.skeleton.set_bone_pose_rotation(rig.skeleton.find_bone(bone_name), q.normalized())
	pose_changed.emit()


## Rotate the selected bone about a world-space axis (used by the gizmo).
func rotate_selected_world(axis_world: Vector3, angle: float) -> void:
	var sk := selected_rig.skeleton
	var idx := sk.find_bone(selected_bone)
	var axis_skel := (sk.global_transform.basis.inverse() * axis_world).normalized()
	var g := sk.get_bone_global_pose(idx)
	var new_basis := Basis(axis_skel, angle) * g.basis
	var parent := sk.get_bone_parent(idx)
	var parent_basis := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var local := (parent_basis.inverse() * new_basis).orthonormalized()
	sk.set_bone_pose_rotation(idx, local.get_rotation_quaternion())
	pose_changed.emit()


func _on_gizmo_drag_started() -> void:
	_drag_old_rot = get_bone_rotation(selected_rig, selected_bone)


func _on_gizmo_rotated(axis_world: Vector3, angle: float) -> void:
	rotate_selected_world(axis_world, angle)


func _on_gizmo_drag_ended() -> void:
	commit_bone_rotation(selected_rig, selected_bone, _drag_old_rot, get_bone_rotation(selected_rig, selected_bone))


## Record an undoable rotation change (the new value is already applied).
func commit_bone_rotation(rig: CharacterRig, bone_name: String, old_q: Quaternion, new_q: Quaternion) -> void:
	if old_q.is_equal_approx(new_q):
		return
	undo.create_action("Rotate %s" % bone_name)
	undo.add_do_method(set_bone_rotation.bind(rig, bone_name, new_q))
	undo.add_undo_method(set_bone_rotation.bind(rig, bone_name, old_q))
	undo.commit_action(false)


func reset_bone(rig: CharacterRig, bone_name: String) -> void:
	var sk := rig.skeleton
	var idx := sk.find_bone(bone_name)
	var old_q := sk.get_bone_pose_rotation(idx)
	var rest_q := sk.get_bone_rest(idx).basis.get_rotation_quaternion()
	set_bone_rotation(rig, bone_name, rest_q)
	commit_bone_rotation(rig, bone_name, old_q, rest_q)


# ---------------------------------------------------------------- root placement

func set_root(rig: CharacterRig, pos: Vector3, yaw: float) -> void:
	rig.position = pos
	rig.rotation = Vector3(0, yaw, 0)
	pose_changed.emit()


func commit_root(rig: CharacterRig, old_pos: Vector3, old_yaw: float, new_pos: Vector3, new_yaw: float) -> void:
	if old_pos.is_equal_approx(new_pos) and is_equal_approx(old_yaw, new_yaw):
		return
	undo.create_action("Move %s" % rig.display_name)
	undo.add_do_method(set_root.bind(rig, new_pos, new_yaw))
	undo.add_undo_method(set_root.bind(rig, old_pos, old_yaw))
	undo.commit_action(false)
