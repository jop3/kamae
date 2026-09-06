extends SceneTree
## Wrists, fingers and body collision: a gripping hand's wrist can be turned and the grip keeps
## the new angle; a phalanx can be posed on its own under a curl and survives save/load; a grip
## on the neck lands on the neck's surface and stays out of the rest of that body.

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)

var scene: PosingScene
var ctrl: PoseController
var director: GripDirector


func _initialize() -> void:
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	scene = PosingScene.new(); world.add_child(scene); scene.setup_default()
	var cam := Camera3D.new(); world.add_child(cam)
	cam.position = Vector3(0, 1.0, 3.0); cam.look_at(Vector3(0, 0.9, 0))
	var gizmo := RotationGizmo.new(); world.add_child(gizmo)
	ctrl = PoseController.new(); world.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	director = GripDirector.new(); world.add_child(director); director.setup(scene, ctrl)
	await physics_frame
	var tori: CharacterRig = scene.get_character("tori")
	var uke: CharacterRig = scene.get_character("uke1")
	ctrl.set_root(tori, Vector3(0, 0, -0.22), 0.0)
	ctrl.set_root(uke, Vector3(0, 0, 0.22), PI)
	await settle()

	# --- a wrist on a plain IK arm is an ordinary bone ---------------------
	await ctrl.set_limb_mode(tori, "RightArm", Limb.Mode.IK)
	tori.limbs["RightArm"].target.global_position = tori.bone_world_transform("RightUpperArm").origin + Vector3(0, -0.14, 0.22)
	await settle()
	check(ctrl.target_driven_limb(tori, "RightHand") == null, "an IK arm without 'turn' leaves the wrist to FK")
	var q0 := ctrl.get_bone_rotation(tori, "RightHand")
	ctrl.select(tori, "RightHand")
	ctrl.rotate_selected_world(Vector3.UP, deg_to_rad(30))
	await settle()
	check(rad_to_deg(ctrl.get_bone_rotation(tori, "RightHand").angle_to(q0)) > 25.0, "the gizmo turns a wrist on an IK arm")
	ctrl.set_bone_rotation(tori, "RightHand", q0)
	await settle()

	# --- a gripping hand's wrist turns through the target ------------------
	await ctrl.set_limb_mode(uke, "LeftArm", Limb.Mode.IK)
	uke.limbs["LeftArm"].target.global_position = tori.bone_world_transform("RightLowerArm").origin + Vector3(0, 0.06, 0.12)
	await settle(3)
	var grip := director.attach_wrapped(uke, "Left", tori, "RightLowerArm")
	await settle(3)
	check(ctrl.target_driven_limb(uke, "LeftHand") != null, "a gripping hand is target-driven")
	var forearm: Vector3 = (tori.bone_world_transform("RightHand").origin - tori.bone_world_transform("RightLowerArm").origin).normalized()
	var hand_before: Basis = uke.bone_world_transform("LeftHand").basis.orthonormalized()
	var offset_before: Transform3D = grip.offset
	ctrl.select(uke, "LeftHand")
	ctrl.rotate_selected_world(forearm, deg_to_rad(40))
	await settle(3)
	var hand_after: Basis = uke.bone_world_transform("LeftHand").basis.orthonormalized()
	var turned := rad_to_deg(hand_before.get_rotation_quaternion().angle_to(hand_after.get_rotation_quaternion()))
	check(turned > 30.0 and turned < 50.0, "the gizmo turns a gripping wrist about the gripped forearm (%.0f deg)" % turned)
	check(not grip.offset.is_equal_approx(offset_before), "the grip offset was re-captured with the new wrist angle")
	check(director.worst_error() < 0.003, "the grip is still exact after the turn (%.4f m)" % director.worst_error())
	# The new angle is what the grip keeps when the gripped arm moves.
	var rel_before := (hand_after.inverse() * tori.bone_world_transform("RightLowerArm").basis.orthonormalized())
	tori.limbs["RightArm"].target.global_position += Vector3(0.05, 0.10, 0.0)
	await settle(3)
	var rel_now := (uke.bone_world_transform("LeftHand").basis.orthonormalized().inverse() * tori.bone_world_transform("RightLowerArm").basis.orthonormalized())
	var drift := rad_to_deg(rel_before.get_rotation_quaternion().angle_to(rel_now.get_rotation_quaternion()))
	check(drift < 2.0, "the turned wrist follows the forearm rigidly (%.1f deg drift)" % drift)
	# Sliders read and write the same wrist.
	var shown := ctrl.get_bone_rotation(uke, "LeftHand")
	var live := (uke.bone_world_transform("LeftLowerArm").basis.orthonormalized().inverse() * uke.bone_world_transform("LeftHand").basis.orthonormalized()).get_rotation_quaternion()
	check(rad_to_deg(shown.angle_to(live)) < 0.5, "the joint sliders show the solved wrist angle")
	var undo_from := uke.bone_world_transform("LeftHand").basis.orthonormalized()
	ctrl.commit_bone_rotation(uke, "LeftHand", shown, shown * Quaternion(Vector3(1, 0, 0), deg_to_rad(20)))
	ctrl.set_bone_rotation(uke, "LeftHand", shown * Quaternion(Vector3(1, 0, 0), deg_to_rad(20)))
	await settle(3)
	ctrl.undo.undo()
	await settle(3)
	var back := rad_to_deg(undo_from.get_rotation_quaternion().angle_to(uke.bone_world_transform("LeftHand").basis.orthonormalized().get_rotation_quaternion()))
	check(back < 1.5, "undo restores the gripping wrist (%.1f deg off)" % back)
	director._remove(grip)
	await settle()

	# --- a phalanx posed on its own, with a curl on top ---------------------
	var sk := tori.skeleton
	var idx_prox := sk.find_bone("RightIndexProximal")
	var rest_q := sk.get_bone_rest(idx_prox).basis.get_rotation_quaternion()
	var spread := rest_q * Quaternion(Vector3(0, 1, 0), deg_to_rad(25))
	ctrl.set_bone_rotation(tori, "RightIndexProximal", spread)
	await settle()
	var tip_open: Vector3 = tori.bone_world_transform("RightIndexDistal").origin
	ctrl.set_finger_curl(tori, "Right", "Index", 1.0)
	await settle()
	var tip_curled: Vector3 = tori.bone_world_transform("RightIndexDistal").origin
	check(tip_open.distance_to(tip_curled) > 0.03, "the curl still closes a finger that was posed by hand (%.3f m)" % tip_open.distance_to(tip_curled))
	check(sk.get_bone_pose_rotation(idx_prox).is_equal_approx(spread), "the authored phalanx rotation is kept under the curl")
	var data: Dictionary = await PoseFile.capture_baked(scene, director, null, "wrist test")
	var saved: Quaternion = PoseFile.array_to_quat(data["characters"][0]["bones"]["RightIndexProximal"])
	check(saved.is_equal_approx(spread), "the pose file stores the authored phalanx rotation, not the curled one")
	PoseFile.apply(data, scene, director)
	await settle(3)
	tori = scene.get_character("tori"); uke = scene.get_character("uke1")
	var tip_loaded: Vector3 = tori.bone_world_transform("RightIndexDistal").origin
	check(tip_loaded.distance_to(tip_curled) < 0.003, "a reloaded curl is applied once (%.4f m off)" % tip_loaded.distance_to(tip_curled))
	ctrl.set_finger_curl(tori, "Right", "Index", 0.0)
	ctrl.set_bone_rotation(tori, "RightIndexProximal", rest_q)

	# --- a grip on the neck lands on the neck, not through it ---------------
	await ctrl.set_limb_mode(tori, "RightArm", Limb.Mode.IK)
	tori.limbs["RightArm"].target.global_position = uke.bone_world_transform("Neck").origin + Vector3(-0.10, 0.02, -0.08)
	await settle(3)
	var neck_grip := director.attach_wrapped(tori, "Right", uke, "Neck")
	await settle(3)
	var neck_a: Vector3 = uke.bone_world_transform("Neck").origin
	var neck_b: Vector3 = uke.bone_world_transform("Head").origin
	var palm: Vector3 = tori.bone_world_transform("RightHand") * Weapon.palm_centre(tori, "Right")
	var off := palm.distance_to(BodyCapsules.closest_on_segment(palm, neck_a, neck_b))
	check(director.worst_error() < 0.003, "the neck grip is exact (%.4f m)" % director.worst_error())
	check(absf(off - GripDirector.hold_radius("Neck")) < 0.006, "the palm sits at the neck's radius (%.3f m off the axis, wanted %.3f)" % [off, GripDirector.hold_radius("Neck")])
	check(GripDirector.hold_radius("Neck") > GripDirector.WRAP_RADIUS, "a neck is held on its surface, not wrapped like a wrist")
	check(GripDirector.curl_for_bone("Neck") < GripDirector.curl_for_bone("RightLowerArm"), "fingers close less on a neck than on a wrist")
	var exempt := BodyCapsules.neighbours(uke, "Neck")
	check(BodyCapsules.penetration(palm, GripDirector.HAND_RADIUS, uke, exempt) < 0.006, "the hand is clear of the rest of Uke's body")
	# Uke turns and leans; the hand rides on the surface and is pushed out of whatever comes.
	var worst_pen := 0.0
	for step in 6:
		ctrl.set_root(uke, uke.position + Vector3(0.02, 0, -0.02), uke.rotation.y + deg_to_rad(15))
		uke.skeleton.set_bone_pose_rotation(uke.skeleton.find_bone("Spine"), Quaternion(Vector3(1, 0, 0), deg_to_rad(8 * (step + 1))) * uke.skeleton.get_bone_rest(uke.skeleton.find_bone("Spine")).basis.get_rotation_quaternion())
		await settle(3)
		var p: Vector3 = tori.bone_world_transform("RightHand") * Weapon.palm_centre(tori, "Right")
		worst_pen = maxf(worst_pen, BodyCapsules.penetration(p, GripDirector.HAND_RADIUS, uke, exempt) - (director.error_for(neck_grip)))
	check(worst_pen < 0.012, "while Uke moves the hand never sinks into the body (worst %.3f m beyond the grip's own shortfall)" % worst_pen)
	director._remove(neck_grip)
	await settle()

	# --- a dragged hand stops at the other body -----------------------------
	var chest: Vector3 = uke.bone_world_transform("Chest").origin
	var handle: LimbHandle = tori.limbs["RightArm"].target
	var pushed := ctrl.keep_out_of_other_bodies(handle, chest)
	var pen := BodyCapsules.penetration(pushed, GripDirector.HAND_RADIUS, uke)
	check(pen < 0.006, "a hand target dragged into Uke's chest stops at the skin (%.3f m in)" % pen)
	ctrl.set_root(uke, Vector3(0, 0, 1.5), PI)   # well clear of Tori
	await settle()
	var own := ctrl.keep_out_of_other_bodies(handle, tori.bone_world_transform("Chest").origin)
	check(own.is_equal_approx(tori.bone_world_transform("Chest").origin), "a character's own body does not block its own hand")

	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


func settle(frames: int = 2) -> void:
	for i in frames:
		await process_frame
