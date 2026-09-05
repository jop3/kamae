extends SceneTree
## M2 headless test: IK reaching, pole control, IK/FK baking, reach warning, finger curls.

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
	await physics_frame

	var tori: CharacterRig = scene.get_character("tori")
	check(tori.limbs.size() == 4, "four IK limbs built (got %d)" % tori.limbs.size())
	var arm: Limb = tori.limbs["RightArm"]
	check(arm.mode == Limb.Mode.FK, "limbs start in FK so nothing moves until asked")
	check(not arm.target.visible, "IK handles hidden while the limb is in FK")

	# --- IK reaching -------------------------------------------------------
	await ctrl.set_limb_mode(tori, "RightArm", Limb.Mode.IK)
	check(arm.target.visible and arm.pole.visible, "handles shown in IK mode")
	var reachable := tori.bone_world_transform("RightUpperArm").origin + Vector3(0.05, -0.1, 0.30)
	arm.target.global_position = reachable
	await process_frame; await process_frame
	var hand := tori.bone_world_transform("RightHand").origin
	check(hand.distance_to(reachable) < 0.002, "hand reaches a reachable target (%.4f m off)" % hand.distance_to(reachable))
	check(arm.reach_shortfall() == 0.0, "no shortfall reported for a reachable target")

	# hand orientation follows the target when asked, which plain TwoBoneIK3D never does
	check(not arm.hand_orient.enabled, "hand orientation is off by default")
	arm.set_orient_to_target(true)
	arm.target.rotation = Vector3(0, 0, deg_to_rad(50))
	await process_frame; await process_frame
	var hand_basis := tori.bone_world_transform("RightHand").basis.orthonormalized()
	var want_basis := arm.target.global_basis.orthonormalized()
	var angle_off := rad_to_deg(hand_basis.get_rotation_quaternion().angle_to(want_basis.get_rotation_quaternion()))
	check(angle_off < 1.0, "hand orientation follows the target (%.2f deg off)" % angle_off)

	# --- the rig must never stretch --------------------------------------
	# Orienting the hand used to shear the bone and pull the mesh into a ribbon, so bone lengths
	# are checked against the rest pose while IK and hand orientation are both active.
	var rest_upper := tori.skeleton.get_bone_global_rest(tori.skeleton.find_bone("RightUpperArm")).origin.distance_to(
		tori.skeleton.get_bone_global_rest(tori.skeleton.find_bone("RightLowerArm")).origin)
	var rest_lower := tori.skeleton.get_bone_global_rest(tori.skeleton.find_bone("RightLowerArm")).origin.distance_to(
		tori.skeleton.get_bone_global_rest(tori.skeleton.find_bone("RightHand")).origin)
	var posed_upper := tori.bone_world_transform("RightUpperArm").origin.distance_to(tori.bone_world_transform("RightLowerArm").origin)
	var posed_lower := tori.bone_world_transform("RightLowerArm").origin.distance_to(tori.bone_world_transform("RightHand").origin)
	check(absf(posed_upper - rest_upper) < 0.001 and absf(posed_lower - rest_lower) < 0.001,
		"posed arm keeps its bone lengths (%.3f/%.3f vs rest %.3f/%.3f)" % [posed_upper, posed_lower, rest_upper, rest_lower])
	var hand_scale := tori.bone_world_transform("RightHand").basis.get_scale()
	check(hand_scale.distance_to(Vector3.ONE) < 0.01, "hand bone carries no scale after orientation (%s)" % hand_scale)

	# --- pole moves the elbow without moving the hand ----------------------
	var elbow_before := tori.bone_world_transform("RightLowerArm").origin
	arm.pole.global_position = arm.pole.global_position + Vector3(0, 0.9, 0.2)
	await process_frame; await process_frame
	var elbow_after := tori.bone_world_transform("RightLowerArm").origin
	var hand_after := tori.bone_world_transform("RightHand").origin
	check(elbow_before.distance_to(elbow_after) > 0.02, "pole moves the elbow (%.3f m)" % elbow_before.distance_to(elbow_after))
	check(hand_after.distance_to(reachable) < 0.002, "pole does not move the hand off target")

	# --- out of reach ------------------------------------------------------
	var far := tori.bone_world_transform("RightUpperArm").origin + Vector3(0, 0, 1.5)
	arm.target.global_position = far
	await process_frame; await process_frame
	var shortfall := arm.reach_shortfall()
	check(shortfall > 0.5, "out-of-reach target reports a shortfall (%.2f m)" % shortfall)
	var stopped_short := tori.bone_world_transform("RightHand").origin.distance_to(far)
	check(absf(stopped_short - shortfall) < 0.02, "hand stops short by exactly the shortfall (%.3f vs %.3f)" % [stopped_short, shortfall])
	arm.target.global_position = reachable
	await process_frame; await process_frame

	# --- IK -> FK bakes ----------------------------------------------------
	var before_bake := tori.bone_world_transform("RightHand").origin
	await ctrl.set_limb_mode(tori, "RightArm", Limb.Mode.FK)
	await process_frame
	var after_bake := tori.bone_world_transform("RightHand").origin
	check(before_bake.distance_to(after_bake) < 0.002, "switching to FK keeps the arm where it was (%.4f m drift)" % before_bake.distance_to(after_bake))
	check(not arm.ik.active, "IK modifier is off in FK mode")
	# and the frozen pose survives the target being moved away
	arm.target.global_position = far
	await process_frame; await process_frame
	check(tori.bone_world_transform("RightHand").origin.distance_to(after_bake) < 0.002, "FK arm ignores the IK target")

	# --- FK -> IK does not jump -------------------------------------------
	await ctrl.set_limb_mode(tori, "RightArm", Limb.Mode.IK)
	await process_frame; await process_frame
	check(tori.bone_world_transform("RightHand").origin.distance_to(after_bake) < 0.005, "switching back to IK does not move the hand")

	# --- undo restores the mode -------------------------------------------
	ctrl.undo.undo()
	await process_frame
	check(arm.mode == Limb.Mode.FK, "undo returns the limb to FK")

	# --- fingers -----------------------------------------------------------
	var open_tip := tori.bone_world_transform("RightIndexDistal").origin
	var palm := tori.bone_world_transform("RightHand").origin
	var open_dist := palm.distance_to(open_tip)
	ctrl.set_finger_curl(tori, "Right", "Index", 1.0)
	await process_frame; await process_frame
	var closed_tip := tori.bone_world_transform("RightIndexDistal").origin
	var closed_dist := palm.distance_to(closed_tip)
	check(closed_dist < open_dist * 0.72, "full curl brings the index fingertip toward the wrist (%.3f -> %.3f m)" % [open_dist, closed_dist])
	# A finger that bends sideways across the palm also shortens that distance, so check the
	# direction too. The middle knuckle is the clean probe: it moves out through the palm by about
	# the length of the proximal segment, while the fingertip swings back toward the wrist and ends
	# near the palm plane again. Measured in an orthonormal hand frame so the backward motion does
	# not leak into the sideways reading.
	ctrl.set_finger_curl(tori, "Right", "Index", 0.0)
	await process_frame; await process_frame
	var hand_xf := tori.bone_world_transform("RightHand")
	var along: Vector3 = hand_xf.basis.y.normalized()
	var width: Vector3 = hand_xf.basis * tori.fingers.palm_width("Right")
	width = (width - along * width.dot(along)).normalized()
	var palm_normal: Vector3 = along.cross(width)
	if palm_normal.dot(hand_xf.basis * tori.fingers.palm_normal("Right")) < 0.0:
		palm_normal = -palm_normal
	var open_knuckle := tori.bone_world_transform("RightIndexIntermediate").origin
	ctrl.set_finger_curl(tori, "Right", "Index", 1.0)
	await process_frame; await process_frame
	var moved := tori.bone_world_transform("RightIndexIntermediate").origin - open_knuckle
	var moved_palmward := moved.dot(palm_normal)
	var moved_sideways := absf(moved.dot(width))
	check(moved_palmward > 0.015 and moved_palmward > moved_sideways * 3.0,
		"the finger bends out through the palm rather than sideways (palmward %.3f m, sideways %.3f m)" % [moved_palmward, moved_sideways])
	# Curling must not stretch the finger: every phalanx keeps its rest length.
	var seg_ok := true
	var worst := 0.0
	for pair in [["RightIndexProximal", "RightIndexIntermediate"], ["RightIndexIntermediate", "RightIndexDistal"],
			["RightThumbMetacarpal", "RightThumbProximal"], ["RightHand", "RightMiddleProximal"]]:
		var rest_len: float = tori.skeleton.get_bone_global_rest(tori.skeleton.find_bone(pair[0])).origin.distance_to(
			tori.skeleton.get_bone_global_rest(tori.skeleton.find_bone(pair[1])).origin)
		var posed_len: float = tori.bone_world_transform(pair[0]).origin.distance_to(tori.bone_world_transform(pair[1]).origin)
		worst = maxf(worst, absf(posed_len - rest_len))
		if absf(posed_len - rest_len) > 0.0005:
			seg_ok = false
	check(seg_ok, "curled fingers keep their bone lengths (worst %.4f m)" % worst)
	var curled_scale := tori.bone_world_transform("RightIndexIntermediate").basis.get_scale()
	check(curled_scale.distance_to(Vector3.ONE) < 0.01, "curled finger bones carry no scale (%s)" % curled_scale)
	ctrl.set_finger_curl(tori, "Right", "Index", 0.0)
	await process_frame; await process_frame
	check(absf(palm.distance_to(tori.bone_world_transform("RightIndexDistal").origin) - open_dist) < 0.002, "curl 0 restores the open hand")
	var left_tip := tori.bone_world_transform("LeftIndexDistal").origin
	ctrl.set_finger_curl(tori, "Right", "Middle", 1.0)
	await process_frame; await process_frame
	check(tori.bone_world_transform("LeftIndexDistal").origin.distance_to(left_tip) < 0.001, "hands curl independently")
	ctrl.apply_grip_preset(tori, "Right")
	await process_frame; await process_frame
	var gripped := 0
	for f in FingerCurl.FINGERS:
		if tori.fingers.get_curl("Right", f) > 0.5:
			gripped += 1
	check(gripped == 5, "grip preset closes all five fingers")
	ctrl.undo.undo()
	await process_frame
	check(tori.fingers.get_curl("Right", "Ring") < 0.01, "undo restores the grip preset")

	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)
