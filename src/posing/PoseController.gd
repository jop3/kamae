class_name PoseController
extends Node
## Selection, FK rotation (gizmo + sliders), root placement and undo/redo.

signal selection_changed(rig: CharacterRig, bone_name: String)
signal limb_changed(rig: CharacterRig, limb_key: String)
signal pose_changed

const HANDLE_PICK_LAYER := 4
const BONE_PICK_LAYER := 2

var scene: PosingScene
var camera: Camera3D
var gizmo: RotationGizmo
var undo := UndoRedo.new()

var selected_rig: CharacterRig
var _known_characters := 0
var _mode_change_pending: Dictionary = {}   ## "id/limb" -> true while an IK/FK bake is in flight
var selected_bone := ""
var selected_limb := ""      ## limb key while an IK handle is selected, else ""
var _drag_old_rot := Quaternion.IDENTITY
var _dragging_handle: LimbHandle
var _drag_plane := Plane()
var _drag_handle_start := Vector3.ZERO


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
	# A removed rig is only queue_free'd, so is_instance_valid still says yes here; ask the scene.
	if selected_rig and not scene.characters.has(selected_rig):
		select(null, "")
	# Undo entries bind rig objects; once a rig is gone every older entry would touch a freed
	# node, so the history is dropped with it.
	var alive := scene.characters.size()
	if alive < _known_characters:
		undo.clear_history()
	_known_characters = alive


# ---------------------------------------------------------------- selection

func select(rig: CharacterRig, bone_name: String) -> void:
	selected_rig = rig
	selected_bone = bone_name
	selected_limb = rig.limb_for_bone(bone_name) if (rig and bone_name != "") else ""
	if rig and bone_name != "":
		_place_gizmo()
	else:
		gizmo.detach()
	selection_changed.emit(rig, bone_name)


func pick_bone(mouse: Vector2) -> Dictionary:
	var area := _raycast_area(mouse, BONE_PICK_LAYER)
	if area == null:
		return {}
	return {"character_id": area.get_meta("character_id"), "bone_name": area.get_meta("bone_name")}


## IK target / pole ball under the mouse, or null.
func pick_handle(mouse: Vector2) -> LimbHandle:
	var area := _raycast_area(mouse, HANDLE_PICK_LAYER)
	if area == null:
		return null
	var handle := area.get_parent()
	# Area3Ds collide whether or not they are drawn; a hidden ball must not steal the click.
	return handle if handle is LimbHandle and handle.is_visible_in_tree() else null


func _raycast_area(mouse: Vector2, layer: int) -> Node:
	var space := camera.get_world_3d().direct_space_state
	var from := camera.project_ray_origin(mouse)
	var to := from + camera.project_ray_normal(mouse) * 100.0
	var q := PhysicsRayQueryParameters3D.create(from, to, layer)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := space.intersect_ray(q)
	return hit["collider"] if not hit.is_empty() else null


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
			var handle := pick_handle(event.position)
			if handle:
				begin_handle_drag(handle, event.position)
				get_viewport().set_input_as_handled()
				return
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
			if _dragging_handle:
				end_handle_drag()
				get_viewport().set_input_as_handled()
			elif gizmo.active_axis >= 0:
				gizmo.end_drag()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _dragging_handle:
			drag_handle_to(event.position)
			get_viewport().set_input_as_handled()
		elif gizmo.active_axis >= 0:
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
	if selected_rig and selected_bone != "" and gizmo.active_axis < 0 and _dragging_handle == null:
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


# ---------------------------------------------------------------- IK handles

## Drags a target or pole in the plane that faces the camera through the ball's current position,
## which is the most predictable mapping from 2D mouse movement to 3D placement.
func begin_handle_drag(handle: LimbHandle, mouse: Vector2) -> void:
	_dragging_handle = handle
	_drag_handle_start = handle.global_position
	_drag_plane = Plane(-camera.global_basis.z, handle.global_position)
	var rig := scene.get_character(handle.get_child(1).get_meta("character_id"))
	var limb_key: String = handle.get_child(1).get_meta("limb_key")
	if rig:
		select(rig, rig.limbs[limb_key].end_bone)


func drag_handle_to(mouse: Vector2) -> void:
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	var hit = _drag_plane.intersects_ray(from, dir)
	if hit != null:
		_dragging_handle.global_position = hit
		pose_changed.emit()


func end_handle_drag() -> void:
	var handle := _dragging_handle
	_dragging_handle = null
	commit_handle_move(handle, _drag_handle_start, handle.global_position)


func set_handle_position(handle: LimbHandle, pos: Vector3) -> void:
	handle.global_position = pos
	pose_changed.emit()


func commit_handle_move(handle: LimbHandle, old_pos: Vector3, new_pos: Vector3) -> void:
	if old_pos.is_equal_approx(new_pos):
		return
	undo.create_action("Move %s" % handle.name)
	undo.add_do_method(set_handle_position.bind(handle, new_pos))
	undo.add_undo_method(set_handle_position.bind(handle, old_pos))
	undo.commit_action(false)


# ---------------------------------------------------------------- IK / FK mode

## Switches a limb between IK and FK without letting it jump.
## Going to FK bakes the solved rotations, which can only be read while the skeleton reports the
## solved pose, so this waits one skeleton_updated before switching the modifier off.
func set_limb_mode(rig: CharacterRig, limb_key: String, mode: int) -> void:
	var limb: Limb = rig.limbs[limb_key]
	if limb.mode == mode:
		return
	var pending_key := "%s/%s" % [rig.character_id, limb_key]
	if _mode_change_pending.get(pending_key, false):
		return   # a bake for this limb is already in flight; a second click must not double it
	var before := limb.capture_solved_rotations()
	if mode == Limb.Mode.FK:
		_mode_change_pending[pending_key] = true
		var solved := await capture_solved_rotations(limb)
		# The solved values are captured inside skeleton_updated, but writing them there is
		# pointless: Skeleton3D restores the authored pose right after the modifiers run. Wait for
		# the frame boundary, then write, so the baked rotations survive.
		await get_tree().process_frame
		_mode_change_pending.erase(pending_key)
		if not is_instance_valid(rig) or not scene.characters.has(rig) or limb.mode == mode:
			return   # the rig went away, or the mode already changed, while we waited
		rig.set_limb_mode(limb_key, Limb.Mode.FK)
		limb.apply_rotations(solved)
		_record_mode_change(rig, limb_key, Limb.Mode.IK, Limb.Mode.FK, before, solved)
	else:
		rig.set_limb_mode(limb_key, Limb.Mode.IK)
		_record_mode_change(rig, limb_key, Limb.Mode.FK, Limb.Mode.IK, before, before)
	limb_changed.emit(rig, limb_key)
	pose_changed.emit()


## Reads the limb's rotations as the IK solver leaves them, from inside skeleton_updated.
func capture_solved_rotations(limb: Limb) -> Dictionary:
	# The callback writes into a dictionary rather than a local: GDScript lambdas capture locals
	# by value, so assigning to one inside the callback would never reach the caller.
	var box := {}
	var grab := func(): box["rotations"] = limb.capture_solved_rotations()
	limb.skeleton.skeleton_updated.connect(grab, CONNECT_ONE_SHOT)
	await limb.skeleton.skeleton_updated
	return box.get("rotations", {})


func _record_mode_change(rig: CharacterRig, limb_key: String, from_mode: int, to_mode: int, old_rot: Dictionary, new_rot: Dictionary) -> void:
	undo.create_action("%s %s" % ["FK" if to_mode == Limb.Mode.FK else "IK", limb_key])
	undo.add_do_method(_apply_mode.bind(rig, limb_key, to_mode, new_rot))
	undo.add_undo_method(_apply_mode.bind(rig, limb_key, from_mode, old_rot))
	undo.commit_action(false)


func _apply_mode(rig: CharacterRig, limb_key: String, mode: int, rotations: Dictionary) -> void:
	rig.set_limb_mode(limb_key, mode)
	if mode == Limb.Mode.FK:
		rig.limbs[limb_key].apply_rotations(rotations)
	limb_changed.emit(rig, limb_key)
	pose_changed.emit()


# ---------------------------------------------------------------- fingers

func set_finger_curl(rig: CharacterRig, side: String, finger: String, value: float) -> void:
	rig.fingers.set_curl(side, finger, value)
	pose_changed.emit()


func commit_finger_curl(rig: CharacterRig, side: String, finger: String, old_value: float, new_value: float) -> void:
	if is_equal_approx(old_value, new_value):
		return
	undo.create_action("Curl %s %s" % [side, finger])
	undo.add_do_method(set_finger_curl.bind(rig, side, finger, new_value))
	undo.add_undo_method(set_finger_curl.bind(rig, side, finger, old_value))
	undo.commit_action(false)


func apply_grip_preset(rig: CharacterRig, side: String) -> void:
	var old: Dictionary = rig.fingers.curls[side].duplicate()
	rig.fingers.apply_grip_preset(side)
	var new_values: Dictionary = rig.fingers.curls[side].duplicate()
	undo.create_action("Grip preset %s" % side)
	undo.add_do_method(_apply_curls.bind(rig, side, new_values))
	undo.add_undo_method(_apply_curls.bind(rig, side, old))
	undo.commit_action(false)
	pose_changed.emit()


func _apply_curls(rig: CharacterRig, side: String, values: Dictionary) -> void:
	for finger in values:
		rig.fingers.set_curl(side, finger, values[finger])
	pose_changed.emit()


# ---------------------------------------------------------------- camera

## One undo entry per orbit or pan gesture (spec §5.2 lists the camera among undoable things).
func record_camera_move(cam: Node, before: Dictionary, after: Dictionary) -> void:
	undo.create_action("Move camera")
	undo.add_do_method(cam.apply_state.bind(after))
	undo.add_undo_method(cam.apply_state.bind(before))
	undo.commit_action(false)


# ---------------------------------------------------------------- copy and mirror (spec §5.5)

## Copies every bone rotation, finger curl and limb state from one character to another. Both
## share the rig, so names map one to one. Grips are left alone: they belong to the pair.
func copy_pose(from: CharacterRig, to: CharacterRig) -> void:
	var before := _snapshot(to)
	_apply_snapshot(to, _snapshot(from))
	var after := _snapshot(to)
	_record_snapshot_change("Copy pose to %s" % to.display_name, to, before, after)


## Mirrors a character's pose across its own left-right plane: Left and Right bones swap, and
## each rotation is reflected. Works on the world-space rotation relative to rest, so it holds
## for any rig whose left and right bones are mirror images in the character's frame.
func mirror_pose(rig: CharacterRig) -> void:
	var before := _snapshot(rig)
	var mirrored := _mirror_snapshot(rig, before)
	_apply_snapshot(rig, mirrored)
	_record_snapshot_change("Mirror %s" % rig.display_name, rig, before, _snapshot(rig))


func _snapshot(rig: CharacterRig) -> Dictionary:
	var sk := rig.skeleton
	var bones := {}
	for i in sk.get_bone_count():
		bones[sk.get_bone_name(i)] = sk.get_bone_pose_rotation(i)
	var limbs := {}
	for key in rig.limbs:
		var limb: Limb = rig.limbs[key]
		limbs[key] = {"mode": limb.mode, "target": rig.global_transform.affine_inverse() * limb.target.global_transform,
			"pole": rig.to_local(limb.pole.global_position), "orient": limb.orient_to_target}
	var fingers := {}
	for side in FingerCurl.SIDES:
		fingers[side] = rig.fingers.curls[side].duplicate()
	return {"bones": bones, "limbs": limbs, "fingers": fingers}


func _apply_snapshot(rig: CharacterRig, snap: Dictionary) -> void:
	var sk := rig.skeleton
	for bone in snap["bones"]:
		var idx := sk.find_bone(bone)
		if idx >= 0:
			sk.set_bone_pose_rotation(idx, snap["bones"][bone])
	for key in snap["limbs"]:
		if not rig.limbs.has(key):
			continue
		var limb: Limb = rig.limbs[key]
		var entry: Dictionary = snap["limbs"][key]
		rig.set_limb_mode(key, entry["mode"])
		limb.target.global_transform = rig.global_transform * entry["target"]
		limb.pole.global_position = rig.to_global(entry["pole"])
		limb.set_orient_to_target(entry["orient"])
	for side in snap["fingers"]:
		for finger in snap["fingers"][side]:
			rig.fingers.set_curl(side, finger, snap["fingers"][side][finger])
	pose_changed.emit()


static func _mirror_name(bone: String) -> String:
	if bone.begins_with("Left"):
		return "Right" + bone.trim_prefix("Left")
	if bone.begins_with("Right"):
		return "Left" + bone.trim_prefix("Right")
	return bone


func _mirror_snapshot(rig: CharacterRig, snap: Dictionary) -> Dictionary:
	var sk := rig.skeleton
	var mirror := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))   # x -> -x in the rig frame
	var bones := {}
	for bone in snap["bones"]:
		var src_idx := sk.find_bone(bone)
		var dst_name := _mirror_name(bone)
		var dst_idx := sk.find_bone(dst_name)
		if src_idx < 0 or dst_idx < 0:
			continue
		# Rotation relative to rest, taken to the rig frame, reflected, brought into the mirror
		# bone's rest frame. G = global rest basis of the bone (rig frame).
		var g_src: Basis = sk.get_bone_global_rest(src_idx).basis
		var g_dst: Basis = sk.get_bone_global_rest(dst_idx).basis
		var rest_src: Basis = sk.get_bone_rest(src_idx).basis
		var rest_dst: Basis = sk.get_bone_rest(dst_idx).basis
		var delta_local: Basis = rest_src.inverse() * Basis(snap["bones"][bone])
		var delta_rig: Basis = g_src * delta_local * g_src.inverse()
		var delta_mirrored: Basis = mirror * delta_rig * mirror
		var delta_dst: Basis = g_dst.inverse() * delta_mirrored * g_dst
		bones[dst_name] = (rest_dst * delta_dst).orthonormalized().get_rotation_quaternion()
	var limbs := {}
	for key in snap["limbs"]:
		var entry: Dictionary = snap["limbs"][key]
		var t: Transform3D = entry["target"]
		var mt := Transform3D((mirror * t.basis * mirror).orthonormalized(), mirror * t.origin)
		limbs[_mirror_name(key)] = {"mode": entry["mode"], "target": mt, "pole": mirror * entry["pole"], "orient": entry["orient"]}
	var fingers := {}
	for side in snap["fingers"]:
		fingers[_mirror_name(side)] = snap["fingers"][side].duplicate()
	return {"bones": bones, "limbs": limbs, "fingers": fingers}


func _record_snapshot_change(label: String, rig: CharacterRig, before: Dictionary, after: Dictionary) -> void:
	undo.create_action(label)
	undo.add_do_method(_apply_snapshot.bind(rig, after))
	undo.add_undo_method(_apply_snapshot.bind(rig, before))
	undo.commit_action(false)
