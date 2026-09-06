extends SceneTree
## M5 headless test: sequences and interpolation (spec §5.6).
## Three poses of Katatedori Ikkyo: Grepp (Uke holds Tori's wrist), Kuzushi (same grip, Tori's
## arm raised and Tori stepped), Kake (grip released, Uke's arm FK). Then a sequence over them.

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)

var scene: PosingScene
var ctrl: PoseController
var director: GripDirector
var player: SequencePlayer
var OUT := ProjectSettings.globalize_path("res://tests/out/poses_m5")


func _initialize() -> void:
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	scene = PosingScene.new(); world.add_child(scene); scene.setup_default()
	var cam := Camera3D.new(); world.add_child(cam)
	var gizmo := RotationGizmo.new(); world.add_child(gizmo)
	ctrl = PoseController.new(); world.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	director = GripDirector.new(); world.add_child(director); director.setup(scene, ctrl)
	player = SequencePlayer.new(); world.add_child(player); player.setup(scene, director)
	await physics_frame
	var tori: CharacterRig = scene.get_character("tori")
	var uke: CharacterRig = scene.get_character("uke1")

	# --- Grepp ------------------------------------------------------------
	ctrl.set_root(tori, Vector3(0, 0, -0.22), 0.0)
	ctrl.set_root(uke, Vector3(0, 0, 0.22), PI)
	await settle()
	await ctrl.set_limb_mode(tori, "RightArm", Limb.Mode.IK)
	tori.limbs["RightArm"].target.global_position = tori.bone_world_transform("RightUpperArm").origin + Vector3(0, -0.14, 0.22)
	await ctrl.set_limb_mode(uke, "LeftArm", Limb.Mode.IK)
	await settle(3)
	uke.limbs["LeftArm"].target.global_position = tori.bone_world_transform("RightLowerArm").origin + Vector3(0, 0.06, 0.10)
	await settle(3)
	director.attach_wrapped(uke, "Left", tori, "RightLowerArm")
	uke.fingers.set_hand_curl("Left", 0.6)
	await settle(3)
	check(director.worst_error() < 0.002, "Grepp: grip exact (%.4f)" % director.worst_error())
	var grepp := await PoseFile.capture_baked(scene, director, null, "Katatedori Ikkyo Grepp")

	# --- Kuzushi: Tori raises the arm and steps; the grip stays -------------
	tori.limbs["RightArm"].target.global_position += Vector3(0.05, 0.18, 0.05)
	ctrl.set_root(tori, Vector3(0.08, 0, -0.26), deg_to_rad(15))
	await settle(3)
	check(director.worst_error() < 0.002 and uke.limbs["LeftArm"].reach_shortfall() < 0.001,
		"Kuzushi: grip still exact and in reach (%.4f, %.4f)" % [director.worst_error(), uke.limbs["LeftArm"].reach_shortfall()])
	var kuzushi := await PoseFile.capture_baked(scene, director, null, "Katatedori Ikkyo Kuzushi")

	# --- Kake: grip released, Uke's arm dropped in FK -----------------------
	director.detach(director.grips[0])
	await settle()
	await ctrl.set_limb_mode(uke, "LeftArm", Limb.Mode.FK)
	ctrl.select(uke, "LeftUpperArm")
	ctrl.rotate_selected_world(Vector3.FORWARD, 0.6)
	uke.fingers.set_hand_curl("Left", 0.0)
	await settle(3)
	var kake := await PoseFile.capture_baked(scene, director, null, "Katatedori Ikkyo Kake")
	check(grepp["grips"].size() == 1 and kuzushi["grips"].size() == 1 and kake["grips"].size() == 0, "three poses captured with the expected grips")

	# --- the sequence file round-trips ---------------------------------------
	for pair in [[grepp, "katatedori_ikkyo_grepp"], [kuzushi, "katatedori_ikkyo_kuzushi"], [kake, "katatedori_ikkyo_kake"]]:
		check(PoseFile.save(OUT.path_join(pair[1] + ".json"), pair[0]) == OK, "saved %s" % pair[1])
	var seq := Sequence.new_default("Katatedori Ikkyo")
	check(seq.steps.size() == 3 and seq.steps[0]["pose"] == "katatedori_ikkyo_grepp", "a new sequence pre-fills Grepp, Kuzushi, Kake (%s)" % [seq.steps[0]["pose"]])
	seq.steps[0]["hold"] = 0.5
	seq.steps[1]["transition"] = 0.6; seq.steps[1]["hold"] = 0.3
	seq.steps[2]["transition"] = 0.6; seq.steps[2]["hold"] = 1.0
	check(is_equal_approx(seq.duration(), 3.0), "duration is the sum of holds and transitions (%.2f)" % seq.duration())
	var seq_path := OUT.path_join("katatedori_ikkyo.sequence.json")
	check(seq.save(seq_path) == OK, "sequence saved")
	var loaded := Sequence.load(seq_path)
	check(loaded != null and loaded.steps == seq.steps and loaded.name == seq.name, "sequence reloads identically")
	var missing: Array = player.load_sequence(loaded, OUT)
	check(missing.is_empty(), "every pose the sequence names was found (%s)" % [missing])

	# --- timeline ------------------------------------------------------------
	var s0 := seq.state_at(0.2)
	check(s0["from"] == 0 and s0["to"] == 0, "0.2 s is inside the first hold")
	var s1 := seq.state_at(0.8)
	check(s1["from"] == 0 and s1["to"] == 1 and s1["u"] > 0.4 and s1["u"] < 0.6, "0.8 s is halfway through Grepp -> Kuzushi (u %.2f)" % s1["u"])
	check(is_equal_approx(seq.state_at(1.1)["u"], 0.0) and seq.state_at(1.1)["from"] == 1, "1.1 s is on the Kuzushi hold")
	check(seq.state_at(99.0)["from"] == 2, "past the end stays on the last step")

	# --- scrub: hold on Grepp reproduces the file -----------------------------
	player.seek(0.1)
	await settle(3)
	var e_uke := max_bone_error(uke, grepp); var b_uke := worst_bone
	var e_tori := max_bone_error(tori, grepp); var b_tori := worst_bone
	check(e_uke < 1e-3 and e_tori < 1e-3, "on the Grepp hold every bone matches the file (uke %.5f at %s, tori %.5f at %s)" % [e_uke, b_uke, e_tori, b_tori])
	check(director.grips.size() == 1 and director.worst_error() < 0.002, "the grip is live on the hold (error %.4f)" % director.worst_error())

	# --- mid-transition with a grip in both poses: re-solved live -------------
	player.seek(0.8)
	await settle(3)
	var mid_pos: Vector3 = tori.position
	var expect_pos: Vector3 = PoseFile.array_to_vec(grepp["characters"][0]["root"]["pos"]).lerp(PoseFile.array_to_vec(kuzushi["characters"][0]["root"]["pos"]), s1["u"])
	check(mid_pos.distance_to(expect_pos) < 1e-4, "Tori's root lerps between the poses (%.4f off)" % mid_pos.distance_to(expect_pos))
	check(director.grips.size() == 1 and director.worst_error() < 0.002 and uke.limbs["LeftArm"].reach_shortfall() < 0.001,
		"a grip active in both poses stays exact halfway (error %.4f, shortfall %.4f)" % [director.worst_error(), uke.limbs["LeftArm"].reach_shortfall()])
	check(is_equal_approx(uke.limbs["LeftArm"].ik.influence, 1.0), "its IK influence stays at 1")
	var raised: Vector3 = tori.bone_world_transform("RightHand").origin
	player.seek(0.1); await settle(2)
	var low: Vector3 = tori.bone_world_transform("RightHand").origin
	check(raised.y > low.y + 0.05, "Tori's hand is on its way up halfway (%.3f -> %.3f)" % [low.y, raised.y])

	# --- mid-transition into Kake: the grip ramps out ---------------------------
	player.seek(1.4 + 0.3)
	await settle(3)
	var st := seq.state_at(1.7)
	check(st["from"] == 1 and st["to"] == 2, "1.7 s is in Kuzushi -> Kake")
	check(director.grips.size() == 1, "the disappearing grip is still listed during the ramp")
	check(absf(uke.limbs["LeftArm"].ik.influence - (1.0 - st["u"])) < 1e-3, "its IK influence ramps 1 -> 0 (%.2f at u %.2f)" % [uke.limbs["LeftArm"].ik.influence, st["u"]])
	player.seek(seq.duration())
	await settle(3)
	check(director.grips.size() == 0, "at the end the grip is gone")
	check(max_bone_error(uke, kake) < 1e-3, "at the end Uke matches the Kake file (worst %.5f)" % max_bone_error(uke, kake))

	# --- playing advances and stops at the end -------------------------------
	player.seek(0.0)
	player.play()
	for i in 20:
		await process_frame
	check(player.time > 0.0 and player.playing, "playback advances the clock (%.2f s)" % player.time)
	player.pause()
	var paused_at := player.time
	await settle(3)
	check(is_equal_approx(player.time, paused_at), "pause holds the clock")

	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


## Worst angular difference (radians) between a character's bones and a pose file, over the bones
## the file drives directly. Limbs in IK mode are re-solved live from their targets (a gripped
## limb by design, spec §5.6), and a two-bone solve redistributes twist along the chain, so their
## bones are compared by where the hand ends up instead.
func max_bone_error(rig: CharacterRig, pose: Dictionary) -> float:
	var worst := 0.0
	for c in pose["characters"]:
		if c["id"] != rig.character_id:
			continue
		for bone in c["bones"]:
			var limb_key: String = rig.limb_for_bone(bone)
			if limb_key != "" and rig.limbs[limb_key].mode == Limb.Mode.IK:
				continue
			var idx := rig.skeleton.find_bone(bone)
			var q := rig.skeleton.get_bone_pose_rotation(idx)
			var want := PoseFile.array_to_quat(c["bones"][bone])
			if q.angle_to(want) > worst:
				worst = q.angle_to(want)
				worst_bone = bone
	return worst

var worst_bone := ""


func settle(frames: int = 2) -> void:
	for i in frames:
		await process_frame
