extends SceneTree
## The plausibility checker itself (src/rig/Anatomy.gd) on deliberate poses: a natural pose
## passes, and each kind of impossible pose is reported. Also two mechanics invariants: the
## IK solver never bends an elbow or knee the wrong way for a reachable target with the default
## pole, and a hand-driven weapon never runs through its holder.

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)

var scene: PosingScene
var ctrl: PoseController
var director: GripDirector
var tori: CharacterRig
var uke: CharacterRig


func _initialize() -> void:
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	scene = PosingScene.new(); world.add_child(scene)
	var cam := Camera3D.new(); world.add_child(cam)
	var gizmo := RotationGizmo.new(); world.add_child(gizmo)
	ctrl = PoseController.new(); world.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	director = GripDirector.new(); world.add_child(director); director.setup(scene, ctrl)
	await physics_frame
	scene.add_character("tori", "Tori", "Tori")
	scene.add_character("uke1", "Uke", "Uke")
	tori = scene.get_character("tori"); uke = scene.get_character("uke1")
	ctrl.set_root(uke, Vector3(0, 0, 1.2), PI)
	await settle(3)

	# --- the rest pose is plausible -------------------------------------------
	var probs := Anatomy.scene_problems(scene, director)
	check(probs.is_empty(), "rest pose has no problems (%s)" % ", ".join(probs))
	var stats := {}
	var skin := Anatomy.skin_problems(tori, stats)
	check(skin.is_empty() and stats.size() >= 15, "rest skin sits at its rest radius everywhere (%d bones, %s)" % [stats.size(), ", ".join(skin)])
	check(absf(stats["RightLowerArm"][1] - 1.0) < 0.02, "median forearm radius ratio is 1 at rest (%.3f)" % stats["RightLowerArm"][1])

	# --- elbows: natural reach vs a pole in front of the body ----------------
	var arm: Limb = tori.limbs["RightArm"]
	ctrl.set_limb_mode(tori, "RightArm", Limb.Mode.IK)
	var shoulder: Vector3 = tori.bone_world_transform("RightUpperArm").origin
	arm.target.global_position = shoulder + Vector3(-0.05, -0.15, 0.30)   # hand in front, elbow bent
	arm.reset_pole()
	await settle(3)
	var flex := Anatomy.flexion_deg(tori, "RightArm")
	check(flex > 40.0 and flex < 150.0, "reaching forward bends the elbow (%.0f°)" % flex)
	var align := Anatomy.bend_direction(tori, "RightArm").dot(Anatomy.allowed_bend_direction(tori, "RightArm"))
	check(align > 0.5, "with the default pole the elbow bends the natural way (alignment %.2f)" % align)
	check(Anatomy.joint_problems(tori).is_empty(), "no joint problem reported (%s)" % ", ".join(Anatomy.joint_problems(tori)))
	# Pole in front of and above the arm: the bare solver would fold the elbow forward through
	# the skin; TwistFollow turns the humerus instead so the crease faces the fold, and the hand
	# stays put.
	var hand_before: Vector3 = tori.bone_world_transform("RightHand").origin
	arm.pole.global_position = shoulder + Vector3(-0.05, 0.3, 0.6)
	await settle(3)
	var twisted: float = arm.twist.last_twist_deg
	check(absf(twisted) > 30.0, "the humerus twisted to follow the fold (%.0f°)" % twisted)
	check(Anatomy.joint_problems(tori).is_empty(), "with the twist the elbow still bends the natural way (%s)" % ", ".join(Anatomy.joint_problems(tori)))
	check(tori.bone_world_transform("RightHand").origin.distance_to(hand_before) < 0.02, "the hand did not move when the humerus twisted (%.3f m)" % tori.bone_world_transform("RightHand").origin.distance_to(hand_before))
	# With the twist switched off the same pose is reported.
	arm.twist.enabled = false
	await settle(3)
	var bad := Anatomy.joint_problems(tori)
	check(bad.size() >= 1 and bad[0].begins_with("RightArm bends the wrong way"), "without it, the backwards elbow is reported (%s)" % ", ".join(bad))
	arm.twist.enabled = true
	arm.reset_pole()
	await settle(3)
	check(Anatomy.joint_problems(tori).is_empty(), "restoring the pole clears it")
	check(absf(arm.twist.last_twist_deg) < 25.0, "the default pole needs little twist (%.0f°)" % arm.twist.last_twist_deg)

	# --- knees --------------------------------------------------------------
	var leg: Limb = tori.limbs["LeftLeg"]
	ctrl.set_limb_mode(tori, "LeftLeg", Limb.Mode.IK)
	var hip: Vector3 = tori.bone_world_transform("LeftUpperLeg").origin
	leg.target.global_transform = Transform3D(leg.target.global_transform.basis, hip + Vector3(0.0, -0.55, 0.30))  # foot forward and up: knee bends
	leg.reset_pole()
	await settle(3)
	var kflex := Anatomy.flexion_deg(tori, "LeftLeg")
	check(kflex > 30.0, "lifting the foot bends the knee (%.0f°)" % kflex)
	check(Anatomy.joint_problems(tori).is_empty(), "the knee bends backwards as a knee should (%s)" % ", ".join(Anatomy.joint_problems(tori)))
	leg.pole.global_position = hip + Vector3(0, -0.4, -0.8)   # pole behind: knee folds forward
	leg.twist.enabled = false
	await settle(3)
	var kbad := Anatomy.joint_problems(tori)
	check(kbad.size() >= 1 and kbad[0].begins_with("LeftLeg bends the wrong way"), "a knee folded forward is reported (%s)" % ", ".join(kbad))
	leg.twist.enabled = true
	leg.reset_pole()
	ctrl.set_limb_mode(tori, "LeftLeg", Limb.Mode.FK)
	await settle(3)

	# --- self-intersection: hand into own chest -------------------------------
	arm.target.global_position = tori.bone_world_transform("Chest").origin
	await settle(3)
	var selfp := Anatomy.self_intersections(tori)
	var hits_chest := false
	for p in selfp:
		if "LowerArm" in p and ("Chest" in p or "Spine" in p):
			hits_chest = true
	check(hits_chest, "a forearm pushed into the chest is reported (%s)" % ", ".join(selfp))
	arm.target.global_position = shoulder + Vector3(-0.05, -0.15, 0.30)
	await settle(3)
	check(Anatomy.self_intersections(tori).is_empty(), "moved back out, nothing reported")

	# --- two bodies ---------------------------------------------------------
	check(Anatomy.body_intersections(tori, uke, director).is_empty(), "two figures 1.2 m apart do not intersect")
	ctrl.set_root(uke, Vector3(0.05, 0, 0.1), PI)
	await settle(3)
	var both := Anatomy.body_intersections(tori, uke, director)
	check(both.size() >= 3, "figures standing in the same place are reported (%d overlaps)" % both.size())
	ctrl.set_root(uke, Vector3(0, 0, 1.2), PI)
	await settle(3)
	# A gripping hand overlapping the wrist it holds is not an intersection.
	ctrl.set_root(uke, Vector3(0, 0, 0.7), PI)
	await settle(3)
	ctrl.set_limb_mode(uke, "LeftArm", Limb.Mode.IK)
	uke.limbs["LeftArm"].target.global_position = tori.bone_world_transform("RightHand").origin
	await settle(2)
	director.attach_wrapped(uke, "Left", tori, "RightLowerArm")
	await settle(3)
	var gripped := Anatomy.body_intersections(tori, uke, director)
	check(director.error_for(director.grips[0]) < 0.01, "the wrist grip is exact (%.3f)" % director.error_for(director.grips[0]))
	check(gripped.is_empty(), "a fist closed on a wrist is not an intersection (%s)" % ", ".join(gripped))

	# --- weapons ------------------------------------------------------------
	director.detach(director.grips[0])
	ctrl.set_root(uke, Vector3(0, 0, 1.2), PI)
	await settle(3)
	var bokken := scene.add_weapon("bokken1", "bokken")
	director.hold_weapon(tori, "Right", bokken, 0.15)
	await settle(3)
	var wp := Anatomy.weapon_intersections(bokken, scene, director)
	check(wp.is_empty(), "a bokken held in the right hand in front does not run through the holder (%s)" % ", ".join(wp))
	bokken.drive = "weapon"
	bokken.global_transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), tori.bone_world_transform("Chest").origin + Vector3(0, 0, -0.3))
	await settle(3)
	wp = Anatomy.weapon_intersections(bokken, scene, director)
	check(wp.size() >= 1, "a bokken stuck through the chest is reported (%s)" % ", ".join(wp))

	# --- bone scale ---------------------------------------------------------
	tori.skeleton.set_bone_pose_scale(tori.skeleton.find_bone("LeftLowerArm"), Vector3(1.5, 1.5, 1.5))
	await settle(2)
	var scaled := Anatomy.bone_scale_problems(tori)
	check(scaled.size() >= 1, "a scaled bone is reported (%s)" % ", ".join(scaled))
	var thick := Anatomy.skin_problems(tori)
	var thick_hit := false
	for p in thick:
		if p.begins_with("LeftHand") or p.begins_with("LeftLowerArm"):
			thick_hit = true
	check(thick_hit, "the swollen forearm skin is reported (%s)" % ", ".join(thick))

	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


func settle(frames: int = 2) -> void:
	for i in frames:
		await process_frame
