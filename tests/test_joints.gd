extends SceneTree
## The joints (src/rig/Joints.gd, JointLimits.gd, LimbTurn.gd): every joint knows what it is,
## measures itself in a physiotherapist's terms, stops where a real one stops, and the rest of
## the limb takes up what a joint cannot — the forearm rolls, the shoulder turns the elbow
## round, the hip turns the knee with the foot — so a hand stays where it was put whenever a
## body could put it there, and says so when it could not.

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)

var scene: PosingScene
var ctrl: PoseController
var director: GripDirector
var tori: CharacterRig
var uke: CharacterRig
const POSE := "res://poses/katatedori_ikkyo_grepp.json"


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
	var j: Joints = tori.joints
	var sk := tori.skeleton

	# --- the catalogue --------------------------------------------------------------------
	check(j.order.size() == sk.get_bone_count() - 1, "every bone but the root is a joint (%d of %d)" % [j.order.size(), sk.get_bone_count()])
	check(j.spec("RightLowerArm")["kind"] == "hinge" and j.spec("RightUpperArm")["kind"] == "ball" and j.spec("RightHand")["kind"] == "condyloid" and j.spec("RightThumbMetacarpal")["kind"] == "saddle",
		"an elbow is a hinge, a shoulder a ball, a wrist condyloid, the thumb base a saddle")
	check(j.order.find("RightUpperArm") < j.order.find("RightLowerArm") and j.order.find("RightLowerArm") < j.order.find("RightHand"), "parents come before children")
	var elbow := Joints.angles(j.spec("RightLowerArm"), sk.get_bone_rest(sk.find_bone("RightLowerArm")).basis.get_rotation_quaternion())
	check(absf(elbow["flex"] - 43.0) < 3.0 and absf(elbow["abd"]) < 1.0 and absf(elbow["twist"]) < 1.0, "the rest elbow reads as 43° of flexion and nothing else (%s)" % Joints.readout(j.spec("RightLowerArm"), elbow))
	var shoulder := Joints.angles(j.spec("RightUpperArm"), sk.get_bone_rest(sk.find_bone("RightUpperArm")).basis.get_rotation_quaternion())
	check(absf(shoulder["abd"] - 42.0) < 3.0 and absf(shoulder["flex"]) < 3.0, "the rest shoulder reads as 42° of abduction, the A-pose (%s)" % Joints.readout(j.spec("RightUpperArm"), shoulder))
	for bone in ["LeftHand", "RightFoot", "Spine", "LeftIndexProximal"]:
		var a := Joints.angles(j.spec(bone), sk.get_bone_rest(sk.find_bone(bone)).basis.get_rotation_quaternion())
		check(absf(a["flex"]) < 7.0 and absf(a["abd"]) < 4.0 and absf(a["twist"]) < 1.0, "%s rests near neutral (%s)" % [bone, Joints.readout(j.spec(bone), a)])
	check(j.spec("RightLowerArm")["names"]["twist"].has("pronation") and j.spec("LeftFoot")["names"]["twist"].has("inversion"), "twists are named for what they are")

	# --- the arithmetic ---------------------------------------------------------------------
	var worst := 0.0
	for bone in ["RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "Spine", "RightIndexProximal", "LeftThumbMetacarpal"]:
		var spec := j.spec(bone)
		for angles in [[20.0, 5.0, 10.0], [-10.0, -5.0, -20.0], [60.0, 0.0, 0.0], [0.0, 15.0, 0.0]]:
			var q := Joints.rotation(spec, angles[0], angles[1], angles[2])
			var back := Joints.angles(spec, q)
			worst = maxf(worst, maxf(absf(back["flex"] - angles[0]), maxf(absf(back["abd"] - angles[1]), absf(back["twist"] - angles[2]))))
	check(worst < 0.01, "angles → rotation → angles round-trips on nine joints (worst %.4f°)" % worst)
	var over := Joints.clamp_angles(j.spec("RightHand"), {"flex": 120.0, "abd": -40.0, "twist": 0.0})
	check(is_equal_approx(over["flex"], 80.0) and is_equal_approx(over["abd"], -20.0), "a wrist asked for 120° flexion and 40° radial deviation is held at 80° and 20°")
	check(Joints.describe(j.spec("RightHand"), {"flex": 120.0, "abd": -40.0, "twist": 0.0}) == "wrist flexion 120°, past 80°; radial deviation 40°, past 20°", "and says so in words: %s" % Joints.describe(j.spec("RightHand"), {"flex": 120.0, "abd": -40.0, "twist": 0.0}))
	check(is_equal_approx(Joints.clamp_angles(j.spec("RightUpperArm"), {"flex": -175.0, "abd": 0.0, "twist": 0.0})["flex"], 180.0), "an arm 5° past straight up is 5° past, not 115° behind")

	# --- which way is which -----------------------------------------------------------------
	var palmward: Vector3 = tori.bone_world_transform("RightHand").basis * tori.fingers.palm_normal("Right")
	var tip_before: Vector3 = tori.bone_world_transform("RightMiddleDistal").origin
	ctrl.set_joint_angles(tori, "RightHand", 40.0, 0.0, 0.0)
	await settle(2)
	var moved: Vector3 = tori.bone_world_transform("RightMiddleDistal").origin - tip_before
	check(moved.dot(palmward) > 0.03, "wrist flexion folds the hand toward the palm (%.3f m palmward)" % moved.dot(palmward))
	ctrl.reset_bone(tori, "RightHand")
	ctrl.set_joint_angles(tori, "RightUpperArm", 90.0, 0.0, 0.0)
	await settle(2)
	var hand: Vector3 = tori.bone_world_transform("RightHand").origin - tori.bone_world_transform("RightUpperArm").origin
	check(hand.dot(tori.global_transform.basis.z) > 0.25, "shoulder flexion raises the arm forward (%.2f m ahead)" % hand.dot(tori.global_transform.basis.z))
	ctrl.set_joint_angles(tori, "RightUpperArm", 0.0, 90.0, 0.0)
	await settle(2)
	hand = tori.bone_world_transform("RightHand").origin - tori.bone_world_transform("RightUpperArm").origin
	check(hand.dot(-tori.global_transform.basis.x) > 0.25, "shoulder abduction raises it out to the side (%.2f m out)" % hand.dot(-tori.global_transform.basis.x))
	ctrl.reset_bone(tori, "RightUpperArm")
	ctrl.set_joint_angles(tori, "RightUpperLeg", 60.0, 0.0, 0.0)
	await settle(2)
	var knee: Vector3 = tori.bone_world_transform("RightLowerLeg").origin - tori.bone_world_transform("RightUpperLeg").origin
	check(knee.dot(tori.global_transform.basis.z) > 0.2, "hip flexion brings the knee forward (%.2f m)" % knee.dot(tori.global_transform.basis.z))
	ctrl.reset_bone(tori, "RightUpperLeg")
	ctrl.set_joint_angles(tori, "RightLowerLeg", 90.0, 0.0, 0.0)
	await settle(2)
	var heel: Vector3 = tori.bone_world_transform("RightFoot").origin - tori.bone_world_transform("RightLowerLeg").origin
	check(heel.dot(tori.global_transform.basis.z) < -0.2 and Anatomy.joint_problems(tori).is_empty(), "knee flexion folds the heel back (%.2f m) and the older bend check agrees" % heel.dot(tori.global_transform.basis.z))
	ctrl.reset_bone(tori, "RightLowerLeg")
	await settle(2)

	# --- the edge, three ways in ------------------------------------------------------------
	# Through the controller (the rings and sliders): the joint stops at its range.
	ctrl.set_joint_angles(tori, "RightHand", 120.0, 0.0, 0.0)
	await settle(2)
	check(absf(ctrl.get_joint_angles(tori, "RightHand")["flex"] - 80.0) < 0.5, "a slider asked for 120° flexion gives 80° (%s)" % Joints.readout(j.spec("RightHand"), ctrl.get_joint_angles(tori, "RightHand")))
	check(tori.joint_limits.refused.is_empty(), "and nothing had to be refused on screen")
	ctrl.select(tori, "RightHand")
	var flex_axis: Vector3 = tori.bone_world_transform("RightLowerArm").basis * j.spec("RightHand")["f"]
	ctrl.rotate_selected_world(flex_axis, deg_to_rad(60.0))
	await settle(2)
	check(absf(ctrl.get_joint_angles(tori, "RightHand")["flex"] - 80.0) < 0.5, "a ring dragged past the range stops at it (%.0f°)" % ctrl.get_joint_angles(tori, "RightHand")["flex"])
	ctrl.rotate_selected_world(flex_axis, deg_to_rad(-30.0))
	await settle(2)
	check(absf(ctrl.get_joint_angles(tori, "RightHand")["flex"] - 50.0) < 0.5, "and comes back off it (%.0f°)" % ctrl.get_joint_angles(tori, "RightHand")["flex"])
	ctrl.reset_bone(tori, "RightHand")
	# Written straight into the skeleton (a loaded file, a script): held on screen, reported.
	sk.set_bone_pose_rotation(sk.find_bone("RightHand"), Joints.rotation(j.spec("RightHand"), 120.0, 0.0, 0.0))
	await settle(2)
	check(absf(Anatomy.joint_angles(tori, "RightHand")["flex"] - 80.0) < 0.5, "a pose file asking 120° shows 80° (%.0f°)" % Anatomy.joint_angles(tori, "RightHand")["flex"])
	var report := tori.joint_limits.report()
	check(report.size() == 1 and report[0] == "RightHand: wrist flexion 120°, past 80°", "and the refusal is reported: %s" % ", ".join(report))
	check(Anatomy.joint_problems(tori).has(report[0]), "Anatomy carries the same report")
	tori.joint_limits.enabled = false
	await settle(2)
	check(absf(Anatomy.joint_angles(tori, "RightHand")["flex"] - 120.0) < 0.5 and Anatomy.joint_problems(tori).has("RightHand: wrist flexion 120°, past 80°"), "with the limits off the pose is shown and Anatomy measures it instead")
	tori.joint_limits.enabled = true
	ctrl.reset_bone(tori, "RightHand")
	await settle(2)

	# --- joints that depend on themselves -------------------------------------------------
	var knee_spec := j.spec("RightLowerLeg")
	check(is_equal_approx(Joints.limits(knee_spec, {"flex": 0.0, "abd": 0.0, "twist": 0.0})["twist"][1], 5.0) and Joints.limits(knee_spec, {"flex": 90.0, "abd": 0.0, "twist": 0.0})["twist"][1] > 30.0, "a straight knee barely turns, a bent one does")
	var mcp := j.spec("RightIndexProximal")
	check(is_equal_approx(Joints.limits(mcp, {"flex": 0.0, "abd": 0.0, "twist": 0.0})["abd"][1], 20.0) and Joints.limits(mcp, {"flex": 80.0, "abd": 0.0, "twist": 0.0})["abd"][1] < 4.0, "an open finger spreads, a curled one cannot")
	tori.fingers.set_hand_curl("Right", 1.0)
	await settle(2)
	check(tori.joint_limits.refused.is_empty(), "a closed fist is within every finger joint's range (%s)" % ", ".join(tori.joint_limits.report()))
	tori.fingers.set_hand_curl("Right", 0.0)

	# --- the rest of the limb takes up what a joint cannot -------------------------------
	# An elbow steered where the humerus cannot twist: the shoulder turns the arm about the
	# shoulder-to-wrist line instead, the hand stays put, no joint is broken.
	var arm: Limb = tori.limbs["RightArm"]
	ctrl.set_limb_mode(tori, "RightArm", Limb.Mode.IK)
	var shoulder_at: Vector3 = tori.bone_world_transform("RightUpperArm").origin
	arm.target.global_position = shoulder_at + Vector3(-0.05, -0.15, 0.30)
	arm.reset_pole()
	await settle(3)
	var hand_was: Vector3 = tori.bone_world_transform("RightHand").origin
	arm.pole.global_position = shoulder_at + Vector3(-0.05, 0.3, 0.6)
	await settle(3)
	check(absf(arm.twist.last_turn_deg) > 3.0, "the pole asked for a humerus twist the shoulder has not got, so the arm turned %.0f° about its line instead" % arm.twist.last_turn_deg)
	check(tori.bone_world_transform("RightHand").origin.distance_to(hand_was) < 0.005, "and the hand stayed where it was (%.3f m)" % tori.bone_world_transform("RightHand").origin.distance_to(hand_was))
	check(Anatomy.joint_problems(tori).is_empty(), "with no joint out of range (%s)" % ", ".join(Anatomy.joint_problems(tori)))
	arm.reset_pole()
	await settle(3)
	# A hand orientation that needs a roll: the forearm pronates, the wrist does not roll.
	arm.reset_target_to_pose()   # the target takes the hand's orientation as solved now
	arm.set_orient_to_target(true)
	var axis: Vector3 = (tori.bone_world_transform("RightHand").origin - tori.bone_world_transform("RightLowerArm").origin).normalized()
	arm.target.global_basis = (Basis(axis, deg_to_rad(50)) * arm.target.global_basis).orthonormalized()
	await settle(3)
	check(absf(arm.hand_orient.last_middle_twist_deg) > 30.0, "a hand rolled 50° gets it from the forearm (%.0f°)" % arm.hand_orient.last_middle_twist_deg)
	check(absf(Anatomy.joint_angles(tori, "RightHand")["twist"]) < 15.0, "not from the wrist (%.0f°)" % Anatomy.joint_angles(tori, "RightHand")["twist"])
	check(tori.joint_limits.refused.is_empty() and tori.bone_world_transform("RightHand").basis.orthonormalized().get_rotation_quaternion().angle_to(arm.target.global_basis.orthonormalized().get_rotation_quaternion()) < deg_to_rad(1.0), "and the hand is exactly as asked")
	arm.set_orient_to_target(false)
	ctrl.set_limb_mode(tori, "RightArm", Limb.Mode.FK)
	await settle(3)

	# --- legs: the hip turns the knee with the foot, the ankle is not asked to yaw ----------
	PoseFile.apply(PoseFile.load(POSE), scene, director, ctrl)
	await settle(4)
	tori = scene.get_character("tori")
	var was := Anatomy.joint_angles(tori, "LeftUpperLeg")
	Stance.turn_foot(tori, "Left", 30.0)
	await settle(4)
	var now := Anatomy.joint_angles(tori, "LeftUpperLeg")
	var knee_twist: float = absf(Anatomy.joint_angles(tori, "LeftLowerLeg")["twist"])
	var knee_lim: Dictionary = Joints.limits(j.spec("LeftLowerLeg"), Anatomy.joint_angles(tori, "LeftLowerLeg"))
	check(absf(now["twist"] - was["twist"]) > 15.0, "turning the foot out 30° turns the thigh at the hip (%.0f° to %.0f°)" % [was["twist"], now["twist"]])
	check(knee_twist <= knee_lim["twist"][1] + 0.5, "and the knee is not asked to turn past its %.0f° (%.0f°)" % [knee_lim["twist"][1], knee_twist])
	check(tori.joint_limits.refused.is_empty(), "nothing refused in the turned-out stance (%s)" % ", ".join(tori.joint_limits.report()))
	# Kneeling plantarflexes the ankle, most of the way but not past it.
	Stance.kneel(ctrl, tori, Stance.Kneel.SEIZA)
	await settle(6)
	var ankle := Anatomy.joint_angles(tori, "RightFoot")
	check(ankle["flex"] > 30.0 and ankle["flex"] <= 65.5, "seiza points the foot back with %.0f° of plantarflexion" % ankle["flex"])
	check(tori.joint_limits.refused.is_empty(), "within the ankle's range (%s)" % ", ".join(tori.joint_limits.report()))
	# A tuck flexes the hips toward the chest, never past straight behind.
	PoseFile.apply(PoseFile.load(POSE), scene, director, ctrl)
	await settle(4)
	uke = scene.get_character("uke1")
	Ukemi.shape(uke, Ukemi.Kind.FORWARD, 0.5)
	await settle(3)
	var hip := Anatomy.joint_angles(uke, "LeftUpperLeg")
	check(hip["flex"] > 40.0, "a forward roll tucks the hips into flexion (%.0f°)" % hip["flex"])
	check(uke.joint_limits.refused.is_empty(), "the tuck is inside every joint's range (%s)" % ", ".join(uke.joint_limits.report()))

	# --- a grip a wrist cannot make is short of its orientation, and says so -------------
	PoseFile.apply(PoseFile.load(POSE), scene, director, ctrl)
	await settle(4)
	uke = scene.get_character("uke1")
	tori = scene.get_character("tori")
	var g: Grip = director.grip_on_limb("uke1", "LeftArm")
	check(g != null and uke.joint_limits.refused.has("LeftHand"), "Uke's katatedori in the committed pose asks a wrist for more than it has (%s)" % ", ".join(uke.joint_limits.report()))
	var off := rad_to_deg(uke.bone_world_transform("LeftHand").basis.orthonormalized().get_rotation_quaternion().angle_to(uke.limbs["LeftArm"].target.global_basis.orthonormalized().get_rotation_quaternion()))
	check(off > 0.5 and director.error_for(g) < 0.005, "so the hand is on the wrist (%.3f m) but %.1f° short of the orientation asked" % [director.error_for(g), off])

	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


func settle(frames: int = 2) -> void:
	for i in frames:
		await process_frame
