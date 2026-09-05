extends SceneTree
## M3W headless test: weapons — hand-driven hold, two-handed grip, handover, weapon-driven mode,
## contact gap, removal.

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
	ctrl.set_root(tori, Vector3(0, 0, -0.3), 0.0)
	ctrl.set_root(uke, Vector3(0, 0, 0.3), PI)
	await process_frame
	for rig in [tori, uke]:
		for side in ["Right", "Left"]:
			await ctrl.set_limb_mode(rig, side + "Arm", Limb.Mode.IK)
			var shoulder: Vector3 = rig.bone_world_transform(side + "UpperArm").origin
			rig.limbs[side + "Arm"].target.global_position = shoulder + rig.global_transform.basis * Vector3(0, -0.14, 0.22)
	await settle()

	# --- a bokken in Tori's right hand ------------------------------------
	var bokken := scene.add_weapon("bokken1", "bokken")
	check(scene.get_weapon("bokken1") == bokken and bokken.length > 1.0, "weapon added and looked up")
	director.hold_weapon(tori, "Right", bokken, 0.1)
	await settle()
	check(hold_error(bokken) < 1e-3, "anchor(t) sits at the holding hand origin (%.4f m)" % hold_error(bokken))
	var tip_before: Vector3 = bokken.anchor_transform(1.0).origin
	ctrl.select(tori, "RightUpperArm")
	tori.limbs["RightArm"].target.global_position += Vector3(0, 0.08, -0.05)
	tori.limbs["RightArm"].target.rotate_x(0.3)
	await settle(1)
	check(hold_error(bokken) < 1e-3, "weapon follows when the arm rotates (%.4f m)" % hold_error(bokken))
	check(bokken.anchor_transform(1.0).origin.distance_to(tip_before) > 0.05, "the tip actually moved")

	# --- second hand on the tsuka ----------------------------------------
	var grip2 := director.attach_to_weapon(tori, "Left", bokken, 0.2)
	await settle()
	check(director.grips.size() == 1, "second hand registered as a weapon grip")
	check(grips_hold(), "second hand tracks its anchor (error %.4f, shortfall %.4f)" % [director.error_for(grip2), tori.limbs["LeftArm"].reach_shortfall()])
	tori.limbs["RightArm"].target.rotate_x(-0.2)
	await settle(1)
	check(grips_hold(), "second hand still tracks after another rotation (error %.4f)" % director.error_for(grip2))
	check(hold_error(bokken) < 1e-3, "holding hand still exact")

	# --- handover to Uke ---------------------------------------------------
	director.detach(grip2)
	await settle()
	var before_xf: Transform3D = bokken.global_transform
	director.hold_weapon(uke, "Right", bokken, 0.1, 0.0, false)
	check(bokken.global_transform.origin.distance_to(before_xf.origin) < 1e-3, "handover without snap does not jump")
	await settle()
	check(bokken.hold["character"] == "uke1" and hold_offset_error(bokken) < 1e-3, "Uke now holds it with the captured offset (%.4f)" % hold_offset_error(bokken))
	check(bokken.global_transform.origin.distance_to(before_xf.origin) < 0.02, "weapon stays put across the switch (%.3f m)" % bokken.global_transform.origin.distance_to(before_xf.origin))

	# --- weapon-driven ------------------------------------------------------
	director.attach_to_weapon(uke, "Left", bokken, 0.2)
	await settle()
	var pos_before: Vector3 = bokken.global_position
	director.set_weapon_drive(bokken, "weapon")
	check(bokken.global_position.distance_to(pos_before) < 1e-4, "switching to weapon-driven keeps geometry")
	check(director.grips.size() == 2, "the holding hand became a grip")
	await settle()
	check(grips_hold(), "both hands on the weapon-driven weapon hold (error %.4f)" % director.worst_error())
	bokken.global_position += Vector3(0.05, 0.05, 0)
	await settle(1)
	check(grips_hold(), "both hands follow the moved weapon within a frame (error %.4f, shortfall %.4f)" % [director.worst_error(), worst_shortfall()])

	# --- contact gap --------------------------------------------------------
	var jo := scene.add_weapon("jo1", "jo")
	director.hold_weapon(tori, "Right", jo, 0.3)
	await settle()
	var gap := director.contact_gap(jo, 0.9, bokken, 0.8)
	check(gap > 0.0, "contact gap reported (%.3f m)" % gap)
	director.close_gap(jo, 0.9, bokken, 0.8)
	await settle()
	check(director.contact_gap(jo, 0.9, bokken, 0.8) < 0.01, "gap closes under 1 cm (%.4f)" % director.contact_gap(jo, 0.9, bokken, 0.8))

	# --- removal ------------------------------------------------------------
	scene.remove_weapon("bokken1")
	await settle()
	var dangling := 0
	for g in director.grips:
		if g.target.kind == GripTarget.Kind.WEAPON and g.target.weapon_id == "bokken1":
			dangling += 1
	check(dangling == 0 and scene.get_weapon("bokken1") == null, "removing a weapon drops its grips")

	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


func hold_error(weapon: Weapon) -> float:
	var rig: CharacterRig = scene.get_character(weapon.hold["character"])
	return weapon.anchor_transform(weapon.hold["t"]).origin.distance_to(rig.bone_world_transform(weapon.hold["hand"] + "Hand").origin)


func hold_offset_error(weapon: Weapon) -> float:
	var rig: CharacterRig = scene.get_character(weapon.hold["character"])
	var expected: Transform3D = rig.bone_world_transform(weapon.hold["hand"] + "Hand") * weapon.hold["offset"]
	return expected.origin.distance_to(weapon.global_transform.origin)


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


func settle(frames: int = 2) -> void:
	for i in frames:
		await process_frame
