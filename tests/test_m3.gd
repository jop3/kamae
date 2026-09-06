extends SceneTree
## M3 headless test: grip attachment between characters — exactness, independence, chains, reversal.

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
	var gizmo := RotationGizmo.new(); world.add_child(gizmo)
	ctrl = PoseController.new(); world.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	director = GripDirector.new(); world.add_child(director); director.setup(scene, ctrl)
	await physics_frame

	var tori: CharacterRig = scene.get_character("tori")
	var uke: CharacterRig = scene.get_character("uke1")
	# A katatedori stance: facing each other at arm's length, Tori's right arm offered forward.
	ctrl.set_root(tori, Vector3(0, 0, -0.22), 0.0)
	ctrl.set_root(uke, Vector3(0, 0, 0.22), PI)
	await process_frame
	# Tori offers both arms forward; Uke reaches out to both wrists. Grips are then captured as real
	# holds rather than freezing a hand half a metre from what it "grips".
	for side in ["Right", "Left"]:
		await ctrl.set_limb_mode(tori, side + "Arm", Limb.Mode.IK)
		var shoulder: Vector3 = tori.bone_world_transform(side + "UpperArm").origin
		tori.limbs[side + "Arm"].target.global_position = shoulder + Vector3(0, -0.14, 0.22)
	await settle()
	check(tori.limbs["RightArm"].reach_shortfall() < 0.001 and tori.limbs["LeftArm"].reach_shortfall() < 0.001,
		"Tori's offered arms are within reach")
	for side in ["Right", "Left"]:
		var facing := "Left" if side == "Right" else "Right"
		await ctrl.set_limb_mode(uke, side + "Arm", Limb.Mode.IK)
		uke.limbs[side + "Arm"].target.global_position = tori.bone_world_transform(facing + "LowerArm").origin + Vector3(0, 0.03, 0)
	await settle()
	check(uke.limbs["RightArm"].reach_shortfall() < 0.001 and uke.limbs["LeftArm"].reach_shortfall() < 0.001,
		"Uke can reach both of Tori's wrists from this distance (R %.3f, L %.3f)" % [
			uke.limbs["RightArm"].reach_shortfall(), uke.limbs["LeftArm"].reach_shortfall()])

	# --- Uke's right hand grips Tori's right forearm ------------------------
	var grip := director.attach(uke, "Right", GripTarget.for_bone(scene, "tori", "LeftLowerArm"))
	await settle()
	check(director.grips.size() == 1, "one grip registered")
	check(uke.limbs["RightArm"].mode == Limb.Mode.IK, "gripping arm switched to IK")
	check(uke.limbs["RightArm"].orient_to_target, "gripping hand takes the target's orientation")
	var err := director.worst_error()
	check(err < 0.002, "hand sits on the grip point (%.4f m off)" % err)

	# Move Tori's whole body: the grip must hold with no re-posing.
	var before_hand := uke.bone_world_transform("RightHand").origin
	ctrl.set_root(tori, Vector3(0.04, 0, -0.20), deg_to_rad(8))
	await settle()
	check(uke.bone_world_transform("RightHand").origin.distance_to(before_hand) > 0.03, "the gripping hand actually followed Tori")
	check(worst_shortfall() < 0.001, "the moved grip point is still within reach (%.4f m short)" % worst_shortfall())
	check(director.worst_error() < 0.002, "grip still exact after Tori moves (%.4f m)" % director.worst_error())

	# Move Tori's arm: same thing, one frame, no lag.
	ctrl.select(tori, "LeftUpperArm")
	ctrl.rotate_selected_world(Vector3.FORWARD, 0.12)
	await settle(1)
	check(grips_hold(), "grip holds one frame after Tori's arm rotates (error %.4f, shortfall %.4f)" % [director.worst_error(), worst_shortfall()])

	# --- a second, independent grip ----------------------------------------
	var grip2 := director.attach(uke, "Left", GripTarget.for_bone(scene, "tori", "RightLowerArm"))
	await settle()
	check(director.grips.size() == 2, "two concurrent grips")
	check(grips_hold(), "both grips hold together (error %.4f, shortfall %.4f)" % [director.worst_error(), worst_shortfall()])
	ctrl.select(tori, "RightUpperArm")
	ctrl.rotate_selected_world(Vector3.FORWARD, -0.12)
	await settle(1)
	check(grips_hold(), "moving one gripped arm does not disturb the other (error %.4f, shortfall %.4f)" % [director.worst_error(), worst_shortfall()])

	# --- a chain: uke2 grips uke1 who grips tori ----------------------------
	var uke2 := scene.add_character("uke2", "Uke 2", "Uke")
	ctrl.set_root(uke2, Vector3(0.30, 0, 0.50), deg_to_rad(205))
	await settle()
	director.attach(uke2, "Right", GripTarget.for_bone(scene, "uke1", "RightLowerArm"))
	await settle()
	var order := []
	for rig in scene.get_children():
		if rig is CharacterRig:
			order.append(rig.character_id)
	check(order.find("tori") < order.find("uke1") and order.find("uke1") < order.find("uke2"),
		"characters ordered so each grip's target updates first (%s)" % [order])
	ctrl.select(tori, "LeftUpperArm")
	ctrl.rotate_selected_world(Vector3.FORWARD, -0.08)
	await settle(1)
	check(grips_hold(), "a two-link chain resolves in one frame (error %.4f, shortfall %.4f)" % [director.worst_error(), worst_shortfall()])

	# --- reversing a grip mid-technique ------------------------------------
	director.detach(grip)
	await settle()
	check(director.grip_on_limb("uke1", "RightArm") == null, "released grip is gone")
	check(not uke.limbs["RightArm"].orient_to_target, "released hand stops taking the target's orientation")
	director.attach(tori, "Left", GripTarget.for_bone(scene, "uke1", "RightLowerArm"))
	await settle()
	check(grips_hold(), "the reversed grip holds (error %.4f, shortfall %.4f)" % [director.worst_error(), worst_shortfall()])

	# --- undo -------------------------------------------------------------
	var count := director.grips.size()
	ctrl.undo.undo()
	await settle()
	check(director.grips.size() == count - 1, "undo removes the last grip")
	ctrl.undo.redo()
	await settle()
	check(director.grips.size() == count, "redo restores it")

	# --- cycle: tori grips uke1 while uke1 grips tori ----------------------
	director.attach(uke, "Right", GripTarget.for_bone(scene, "tori", "LeftLowerArm"))
	await settle(4)
	check(grips_hold(0.01), "a mutual grip settles rather than oscillating (error %.4f, shortfall %.4f)" % [director.worst_error(), worst_shortfall()])

	# --- out of reach: the hand falls short by exactly the shortfall, and says so --------
	ctrl.set_root(tori, Vector3(0, 0, -1.6), 0.0)
	await settle()
	var shortfall: float = uke.limbs["RightArm"].reach_shortfall()
	var grip_now := director.grip_on_limb("uke1", "RightArm")
	check(shortfall > 0.3, "pulling the gripped body away reports a large shortfall (%.2f m)" % shortfall)
	check(grip_now == null or absf(director.error_for(grip_now) - shortfall) < 0.01,
		"the hand falls short by exactly the shortfall, it does not stretch")
	ctrl.set_root(tori, Vector3(0.05, 0, -0.24), deg_to_rad(8))
	await settle()

	# --- wrapping a hand round a wrist -----------------------------------
	# The attach used by the panel places the hand round the limb like a real katatedori: the
	# palm centre rides just off the forearm axis and the shaft runs across the palm.
	for g in director.grips.duplicate():
		director._remove(g)
	await settle()
	uke.limbs["LeftArm"].target.global_position = tori.bone_world_transform("RightLowerArm").origin + Vector3(0, 0.06, 0.10)
	await settle()
	director.attach_wrapped(uke, "Left", tori, "RightLowerArm")
	await settle(3)
	var elbow: Vector3 = tori.bone_world_transform("RightLowerArm").origin
	var wrist: Vector3 = tori.bone_world_transform("RightHand").origin
	var forearm_axis: Vector3 = (wrist - elbow).normalized()
	var palm: Vector3 = uke.bone_world_transform("LeftHand") * Weapon.palm_centre(uke, "Left")
	var rel: Vector3 = palm - elbow
	var off_axis: float = (rel - forearm_axis * rel.dot(forearm_axis)).length()
	var along: float = rel.dot(forearm_axis) / elbow.distance_to(wrist)
	var width_world: Vector3 = uke.bone_world_transform("LeftHand").basis * uke.fingers.palm_width("Left")
	check(grips_hold(), "the wrapped grip holds (error %.4f, shortfall %.4f)" % [director.worst_error(), worst_shortfall()])
	check(off_axis < 0.035, "the wrapped palm sits on the forearm (%.3f m off its axis)" % off_axis)
	check(along > 0.2 and along < 0.95, "the wrap is on the forearm, not beyond a joint (%.2f of its length)" % along)
	check(absf(width_world.normalized().dot(forearm_axis)) > 0.85, "the forearm runs across the palm (%.2f)" % absf(width_world.normalized().dot(forearm_axis)))

	# --- removing a character cleans up its grips --------------------------
	scene.remove_character("uke2")
	await settle()
	var dangling := 0
	for g in director.grips:
		if g.gripper_id == "uke2" or (g.target.kind == GripTarget.Kind.BONE and g.target.character_id == "uke2"):
			dangling += 1
	check(dangling == 0, "grips of a removed character are dropped")

	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


## True when every grip is either exactly on its point, or short by exactly the amount its arm
## cannot reach. Those are the only two legitimate outcomes: the IK never stretches, and nothing
## else may pull a gripping hand off its point.
func grips_hold(tolerance: float = 0.002) -> bool:
	for grip in director.grips:
		var rig: CharacterRig = scene.get_character(grip.gripper_id)
		if rig == null:
			continue
		var shortfall: float = rig.limbs[grip.limb_key()].reach_shortfall()
		if absf(director.error_for(grip) - shortfall) > tolerance:
			return false
	return true


func worst_shortfall() -> float:
	var worst := 0.0
	for grip in director.grips:
		var rig: CharacterRig = scene.get_character(grip.gripper_id)
		if rig:
			worst = maxf(worst, rig.limbs[grip.limb_key()].reach_shortfall())
	return worst


## Lets the skeletons re-evaluate. One frame is enough once the ordering is right; the default of
## two covers the extra frame a fresh connection needs.
func settle(frames: int = 2) -> void:
	for i in frames:
		await process_frame
