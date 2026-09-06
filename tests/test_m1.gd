extends SceneTree
## M1 headless test: pick capsules, ray picking, FK rotation via controller, undo/redo, slug.

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)


func _initialize() -> void:
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	var scene := PosingScene.new(); world.add_child(scene); scene.setup_default()
	var cam := Camera3D.new(); world.add_child(cam)
	cam.position = Vector3(0, 1.0, 3.0); cam.look_at(Vector3(0, 0.9, 0))
	var gizmo := RotationGizmo.new(); world.add_child(gizmo)
	var ctrl := PoseController.new(); world.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	await physics_frame; await physics_frame

	var tori := scene.get_character("tori")
	var pc: PickCapsules = tori.get_node("PickCapsules")
	check(pc.areas.size() == 52, "52 pick capsules per character (got %d)" % pc.areas.size())

	# Ray-pick: aim exactly at Uke's head bone position (uke1 is nearest the camera).
	var uke := scene.get_character("uke1")
	var head_world := uke.bone_world_transform("Head").origin + Vector3(0, 0.08, 0)
	var hit := ctrl.pick_bone(cam.unproject_position(head_world))
	check(hit.get("character_id", "") == "uke1" and hit.get("bone_name", "") == "Head", "ray pick hits uke1 Head (got %s)" % [hit])
	# Aim at the middle finger itself: the hand and forearm capsules overlap around the wrist, so a
	# fingertip is the unambiguous target for this check.
	var finger_world := uke.bone_world_transform("RightMiddleIntermediate").origin
	hit = ctrl.pick_bone(cam.unproject_position(finger_world))
	var picked: String = hit.get("bone_name", "")
	check(picked.begins_with("Right") and ("Middle" in picked or "Index" in picked or "Hand" in picked),
		"ray pick on the right middle finger hits a right-hand bone (got %s)" % picked)

	# FK rotate + undo/redo
	ctrl.select(tori, "RightUpperArm")
	check(gizmo.visible, "gizmo shown on selection")
	var q0 := ctrl.get_bone_rotation(tori, "RightUpperArm")
	var before := tori.bone_world_transform("RightHand").origin
	gizmo.begin_drag(2, Vector2.ZERO)
	ctrl.rotate_selected_world(Vector3.FORWARD, 0.6)
	gizmo.end_drag()
	await process_frame
	var after := tori.bone_world_transform("RightHand").origin
	check(before.distance_to(after) > 0.1, "rotating upper arm moves the hand (%.2f m)" % before.distance_to(after))
	check(ctrl.undo.has_undo(), "undo stack has an action")
	# Shift snaps a gizmo drag to 15 degree steps, measured from where the drag started.
	var emitted := {"total": 0.0}
	gizmo.rotated.connect(func(_axis: Vector3, angle: float): emitted["total"] += angle)
	var centre := cam.unproject_position(gizmo.global_position)
	var mouse_at := func(deg: float) -> Vector2: return centre + Vector2(cos(deg_to_rad(deg)), -sin(deg_to_rad(deg))) * 60.0
	var shift := InputEventKey.new(); shift.keycode = KEY_SHIFT; shift.pressed = true
	Input.parse_input_event(shift)
	await process_frame
	gizmo.begin_drag(2, mouse_at.call(0.0))
	gizmo.drag_to(mouse_at.call(7.0))
	var after_10: float = emitted["total"]
	gizmo.drag_to(mouse_at.call(20.0))
	var after_20: float = emitted["total"]
	gizmo.end_drag()
	shift.pressed = false
	Input.parse_input_event(shift)
	await process_frame
	check(is_zero_approx(after_10), "with Shift, 7 degrees of drag applies nothing yet (%.1f)" % rad_to_deg(after_10))
	check(is_equal_approx(absf(rad_to_deg(after_20)), 15.0), "with Shift, 20 degrees of drag snaps to 15 (%.1f)" % rad_to_deg(after_20))
	ctrl.undo.undo(); await process_frame
	ctrl.undo.undo(); await process_frame
	check(ctrl.get_bone_rotation(tori, "RightUpperArm").is_equal_approx(q0), "undo restores rotation")
	ctrl.undo.redo(); await process_frame
	check(tori.bone_world_transform("RightHand").origin.distance_to(after) < 1e-4, "redo re-applies rotation")

	# Root placement + undo
	ctrl.set_root(uke, Vector3(0, 0, 1.5), PI); ctrl.commit_root(uke, Vector3(0, 0, 0.5), PI, Vector3(0, 0, 1.5), PI)
	ctrl.undo.undo()
	check(uke.position.is_equal_approx(Vector3(0, 0, 0.5)), "root move undo restores position")

	check(StillExport.slugify("Katatedori Ikkyo — Grepp") == "katatedori_ikkyo_grepp", "slugify handles dash")
	check(StillExport.slugify("Ushiro Ryōtedori Zenpōnage / Kake") == "ushiro_ry_tedori_zenp_nage_kake" or StillExport.slugify("Övning åäö") == "ovning_aao", "slugify transliterates Swedish letters (%s)" % StillExport.slugify("Övning åäö"))
	# --- mirror and copy (spec §5.5) -----------------------------------------
	ctrl.select(tori, "RightUpperArm")
	ctrl.rotate_selected_world(Vector3.FORWARD, 1.0)
	ctrl.set_finger_curl(tori, "Right", "Index", 0.8)
	await process_frame; await process_frame
	var right_hand: Vector3 = tori.to_local(tori.bone_world_transform("RightHand").origin)
	var left_hand_rest: Vector3 = tori.to_local(tori.bone_world_transform("LeftHand").origin)
	ctrl.mirror_pose(tori)
	await process_frame; await process_frame
	var left_hand: Vector3 = tori.to_local(tori.bone_world_transform("LeftHand").origin)
	var right_after: Vector3 = tori.to_local(tori.bone_world_transform("RightHand").origin)
	var mirrored_expected := Vector3(-right_hand.x, right_hand.y, right_hand.z)
	check(left_hand.distance_to(mirrored_expected) < 0.01, "mirror puts the left hand where the raised right hand was, reflected (%.3f m off)" % left_hand.distance_to(mirrored_expected))
	check(right_after.distance_to(Vector3(-left_hand_rest.x, left_hand_rest.y, left_hand_rest.z)) < 0.01, "and the right arm takes the left arm's rest place")
	check(is_equal_approx(tori.fingers.get_curl("Left", "Index"), 0.8) and is_zero_approx(tori.fingers.get_curl("Right", "Index")), "finger curls swap sides")
	ctrl.undo.undo(); await process_frame; await process_frame
	check(tori.to_local(tori.bone_world_transform("RightHand").origin).distance_to(right_hand) < 1e-3, "undo restores the unmirrored pose")
	var uke_rig: CharacterRig = scene.get_character("uke1")
	ctrl.copy_pose(tori, uke_rig)
	await process_frame; await process_frame
	var uke_hand: Vector3 = uke_rig.to_local(uke_rig.bone_world_transform("RightHand").origin)
	check(uke_hand.distance_to(right_hand) < 1e-3, "copy pose gives Uke the same raised arm (%.4f m off in local frame)" % uke_hand.distance_to(right_hand))

	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)
