extends SceneTree
## M4 headless test: pose save/load round trip — baked bones, root, skin, grips, limbs, fingers.

const OUT := "/home/user/kamae/tests/out/pose_roundtrip.json"

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

	check(PoseFile.slugify("Katatedori Ikkyō — Grepp") == "katatedori_ikkyo_grepp",
		"slugify: %s" % PoseFile.slugify("Katatedori Ikkyō — Grepp"))

	# --- fixture (M3 stance) --------------------------------------------------
	var tori: CharacterRig = scene.get_character("tori")
	var uke: CharacterRig = scene.get_character("uke1")
	ctrl.set_root(tori, Vector3(0, 0, -0.22), 0.0)
	ctrl.set_root(uke, Vector3(0, 0, 0.22), PI)
	tori.set_skin_color(Color("#1f8a8a"))
	uke.set_skin_color(Color("#e0a030"))
	await process_frame
	ctrl.set_bone_rotation(tori, "Head", Quaternion(Vector3.UP, 0.3))
	await ctrl.set_limb_mode(tori, "RightArm", Limb.Mode.IK)
	var shoulder: Vector3 = tori.bone_world_transform("RightUpperArm").origin
	tori.limbs["RightArm"].target.global_position = shoulder + Vector3(0, -0.14, 0.22)
	await settle()
	await ctrl.set_limb_mode(uke, "LeftArm", Limb.Mode.IK)
	uke.limbs["LeftArm"].target.global_position = tori.bone_world_transform("RightLowerArm").origin + Vector3(0, 0.03, 0)
	await settle()
	director.attach(uke, "Left", GripTarget.for_bone(scene, "tori", "RightLowerArm"))
	uke.fingers.apply_grip_preset("Left")
	tori.fingers.set_curl("Right", "Index", 0.4)
	await settle()
	var bokken := scene.add_weapon("bokken1", "bokken")
	director.hold_weapon(tori, "Right", bokken, 0.1)
	await settle()
	await ctrl.set_limb_mode(uke, "RightArm", Limb.Mode.IK)
	director.attach_to_weapon(uke, "Right", bokken, 0.2)
	await settle()
	var hold_before: Vector3 = bokken.anchor_transform(0.1).origin

	# --- capture + save --------------------------------------------------------
	var data: Dictionary = await PoseFile.capture_baked(scene, director, null, "Katatedori Ikkyō — Grepp")
	check(data["format"] == 1 and data["characters"].size() == 2, "captured two characters")
	check(data["grips"].size() == 2, "captured two grips (bone + weapon)")
	check(data["weapons"].size() == 1 and data["weapons"][0]["id"] == "bokken1", "captured the bokken")
	var ik_before: Dictionary = data["characters"][0]["ik"]
	check(ik_before["RightArm"]["mode"] == "ik" and ik_before["LeftArm"]["mode"] == "fk", "captured limb modes")
	check(PoseFile.save(OUT, data) == OK, "saved to %s" % OUT)
	var loaded := PoseFile.load(OUT)
	check(not loaded.is_empty(), "loaded file")

	# --- mutate -----------------------------------------------------------------
	director.clear()
	ctrl.set_root(tori, Vector3(0.5, 0, 0.1), 0.7)
	ctrl.set_root(uke, Vector3(-0.3, 0, -0.4), 2.0)
	tori.set_skin_color(Color.WHITE); uke.set_skin_color(Color.WHITE)
	tori.set_limb_mode("RightArm", Limb.Mode.FK)
	uke.set_limb_mode("LeftArm", Limb.Mode.FK)
	tori.set_limb_mode("LeftLeg", Limb.Mode.IK)
	for r in [tori, uke]:
		for side in FingerCurl.SIDES:
			r.fingers.set_hand_curl(side, 0.0)
		for i in r.skeleton.get_bone_count():
			r.skeleton.set_bone_pose_rotation(i, Quaternion(Vector3.RIGHT, 0.2) * r.skeleton.get_bone_rest(i).basis.get_rotation_quaternion())
	scene.add_character("uke2", "Uke", "Uke")
	scene.remove_weapon("bokken1")
	scene.add_weapon("jo1", "jo")
	await settle()

	# --- reload -----------------------------------------------------------------
	PoseFile.apply(loaded, scene, director, ctrl)
	await settle(2)
	check(scene.characters.size() == 2 and scene.get_character("uke2") == null, "extra character removed")
	var again: Dictionary = await PoseFile.capture_baked(scene, director, null, "x")

	for i in loaded["characters"].size():
		var a: Dictionary = loaded["characters"][i]
		var b: Dictionary = again["characters"][i]
		check(a["id"] == b["id"], "character %s present" % a["id"])
		var worst := 0.0
		var worst_bone := ""
		for bone in a["bones"]:
			var qa := PoseFile.array_to_quat(a["bones"][bone])
			var qb := PoseFile.array_to_quat(b["bones"][bone])
			if qa.dot(qb) < 0.0:   # same rotation, opposite sign
				qb = -qb
			var d := maxf(maxf(absf(qa.x - qb.x), absf(qa.y - qb.y)), maxf(absf(qa.z - qb.z), absf(qa.w - qb.w)))
			if d > worst:
				worst = d; worst_bone = bone
		check(worst < 1e-4, "%s: every bone within 1e-4 of file (worst %.6f at %s)" % [a["id"], worst, worst_bone])
		var pa := PoseFile.array_to_vec(a["root"]["pos"]); var pb := PoseFile.array_to_vec(b["root"]["pos"])
		check(pa.distance_to(pb) < 1e-5 and absf(a["root"]["yaw"] - b["root"]["yaw"]) < 1e-5, "%s: root restored" % a["id"])
		check(a["skin_color"] == b["skin_color"], "%s: skin colour %s restored" % [a["id"], a["skin_color"]])
		for key in a["ik"]:
			check(a["ik"][key]["mode"] == b["ik"][key]["mode"] and a["ik"][key]["orient"] == b["ik"][key]["orient"],
				"%s: limb %s mode %s restored" % [a["id"], key, a["ik"][key]["mode"]])
			var ta := PoseFile.array_to_transform(a["ik"][key]["target"]); var tb := PoseFile.array_to_transform(b["ik"][key]["target"])
			check(ta.origin.distance_to(tb.origin) < 1e-4, "%s: limb %s target restored" % [a["id"], key])
		for side in a["fingers"]:
			for finger in a["fingers"][side]:
				check(absf(a["fingers"][side][finger] - b["fingers"][side][finger]) < 1e-6,
					"%s: %s %s curl %.2f restored" % [a["id"], side, finger, a["fingers"][side][finger]])

	check(director.grips.size() == loaded["grips"].size(), "grip count restored (%d)" % director.grips.size())
	for i in mini(director.grips.size(), loaded["grips"].size()):
		var g: Grip = director.grips[i]
		var d: Dictionary = loaded["grips"][i]
		var off := PoseFile.array_to_transform(d["offset"])
		check(g.gripper_id == d["gripper"] and g.hand == d["hand"] and g.target.to_dict() == d["target"], "grip %d identity restored" % i)
		check(g.offset.origin.distance_to(off.origin) < 1e-5 and (g.offset.basis.x - off.basis.x).length() < 1e-5, "grip %d offset restored" % i)
	check(director.worst_error() < 0.002, "grip hand sits on target after reload (%.4f m)" % director.worst_error())
	var bk: Weapon = scene.get_weapon("bokken1")
	check(bk != null and scene.get_weapon("jo1") == null and scene.weapons.size() == 1, "weapon set restored")
	if bk:
		check(bk.drive == "hand" and bk.hold.get("character", "") == "tori" and bk.hold.get("hand", "") == "Right", "hold restored")
		var herr := bk.anchor_transform(0.1).origin.distance_to(tori.bone_world_transform("RightHand").origin)
		check(herr < 1e-3, "weapon anchor sits on holder's hand after reload (%.4f m)" % herr)
		check(bk.anchor_transform(0.1).origin.distance_to(hold_before) < 1e-3, "weapon anchor back where it was saved")
		var wgrips := 0
		for g in director.grips:
			if g.target.kind == GripTarget.Kind.WEAPON and g.target.weapon_id == "bokken1":
				wgrips += 1
		check(wgrips == 1, "weapon grip restored")

	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(0 if failures == 0 else 1)


func settle(frames: int = 2) -> void:
	for i in frames:
		await process_frame
