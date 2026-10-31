extends SceneTree
## Falls (src/rig/Ukemi.gd): a forward roll, a backward roll, and being laid face down.
##
## What makes a roll read as a roll is that the body stays *on* the mat all the way through it:
## a body turning about its root sinks through the floor and then rises off it, which is what a
## felled tree does. So that is what this measures, frame by frame, along with the body staying
## plausible while it is curled.

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)

var scene: PosingScene
var ctrl: PoseController
var director: GripDirector
const STEPS := 12
## How far off the mat the lowest part of the body may be, either way.
const ON_THE_MAT := 0.02


func _initialize() -> void:
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	scene = PosingScene.new(); world.add_child(scene)
	var cam := Camera3D.new(); world.add_child(cam)
	var gizmo := RotationGizmo.new(); world.add_child(gizmo)
	ctrl = PoseController.new(); world.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	director = GripDirector.new(); world.add_child(director); director.setup(scene, ctrl)
	await physics_frame
	scene.add_character("uke1", "Uke", "Uke")
	await settle(3)
	var rig: CharacterRig = scene.get_character("uke1")
	check(rig != null, "a character to throw")
	if rig == null:
		quit(1)
		return

	for kind in [Ukemi.Kind.FORWARD, Ukemi.Kind.BACKWARD, Ukemi.Kind.PRONE]:
		var name: String = ["forward roll", "backward roll", "face down"][kind]
		var worst_gap := 0.0
		var deepest := 0.0
		var problems := PackedStringArray()
		var turned := 0.0
		for i in STEPS + 1:
			var t := float(i) / STEPS
			Ukemi.shape(rig, kind, t)
			await settle(3)
			Ukemi.ground(rig)
			await settle(2)
			var lowest := _lowest(rig)
			worst_gap = maxf(worst_gap, absf(lowest - Ukemi.MAT_Y))
			deepest = minf(deepest, lowest - Ukemi.MAT_Y)
			turned = maxf(turned, absf(rad_to_deg(rig.rotation.x)))
			for p in Anatomy.problems(rig):
				if not problems.has(p):
					problems.append(p)
		check(worst_gap < ON_THE_MAT, "%s: the body is on the mat the whole way (worst %.3f m off)" % [name, worst_gap])
		check(deepest > -ON_THE_MAT, "%s: nothing sinks through the mat (deepest %.3f m)" % [name, deepest])
		check(problems.is_empty(), "%s: the body stays plausible while it is curled%s"
			% [name, "" if problems.is_empty() else " — " + "; ".join(problems)])
		var expected: float = 360.0 if kind != Ukemi.Kind.PRONE else 90.0
		check(absf(turned - expected) < 1.0, "%s: the body turns %.0f°, not %.0f°" % [name, turned, expected])

	# A shape asked for twice is the same shape: bends are set, not added up.
	Ukemi.shape(rig, Ukemi.Kind.FORWARD, 0.5)
	await settle(3)
	var once := rig.bone_world_transform("Head").origin - rig.position
	Ukemi.shape(rig, Ukemi.Kind.FORWARD, 0.5)
	await settle(3)
	var twice := rig.bone_world_transform("Head").origin - rig.position
	check(once.distance_to(twice) < 0.001, "asking for the same shape twice gives the same shape (%.4f m apart)" % once.distance_to(twice))

	await _blended_falls(rig)
	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


## The lowest point of what the body rests on (capsules, skull, toes, soles).
func _lowest(rig: CharacterRig) -> float:
	return Ukemi.resting_lowest(rig)


## A fall in a video is a blend between a few of its shapes (a technique saves one pose per
## phase). Blended about the root at the feet, the middle of a roll went more than a metre under
## the mat; this blends standing -> fall -> further -> standing up again, the way a technique
## does, and checks every frame is on the mat, the poses are reached exactly, and getting up
## finishes the roll instead of unrolling it.
func _blended_falls(rig: CharacterRig) -> void:
	check(is_equal_approx(PoseBlend.continue_turn(deg_to_rad(252.0), 0.0), TAU),
		"getting up from 252° of a roll goes on to 360°, not back to 0°")
	check(is_equal_approx(PoseBlend.continue_turn(0.0, TAU), TAU),
		"a whole roll written as 0° to 360° stays a whole roll")
	for kind in [Ukemi.Kind.FORWARD, Ukemi.Kind.BACKWARD]:
		var name: String = ["forward", "backward"][kind]
		var poses := []
		for t in [0.0, 0.35, 0.7, -1.0]:
			PoseFile.apply({"characters": [{"id": "uke1", "name": "Uke", "role": "Uke",
				"root": {"pos": [0, 0, 0], "yaw": 0.0}}]}, scene, director, ctrl)
			rig.skeleton.reset_bone_poses()
			for arm in ["RightArm", "LeftArm"]:
				ctrl.set_limb_mode(rig, arm, Limb.Mode.FK)
			await settle(3)
			for leg in ["RightLeg", "LeftLeg"]:
				ctrl.set_limb_mode(rig, leg, Limb.Mode.IK)
			await settle(3)
			if t > 0.0:
				rig.position = Vector3(0.0, 0.0, 0.4 * poses.size() * (1.0 if kind == Ukemi.Kind.FORWARD else -1.0))
				Ukemi.shape(rig, kind, t)
				rig.fall = {"kind": name, "t": t}
				await settle(4)
				Ukemi.ground(rig)
				await settle(2)
			elif t < 0.0:
				rig.position = Vector3(0.0, 0.0, 1.2 * (1.0 if kind == Ukemi.Kind.FORWARD else -1.0))
			poses.append(PoseFile.capture(scene, director))
		var deepest := 0.0
		var highest := 0.0
		var off_at_keys := 0.0
		for i in range(1, poses.size()):
			for k in 11:
				var u := k / 10.0
				PoseBlend.apply(scene, director, poses[i - 1], poses[i], u)
				await settle(3)
				var low := Ukemi.lowest_point(rig)
				deepest = minf(deepest, low)
				if OS.get_environment("UKEMI_VERBOSE") == "1":
					print("  %s %d u=%.1f rest-low %.3f low %.3f pitch %.0f pos %s" % [name, i, u, Ukemi.resting_lowest(rig), low, rad_to_deg(rig.rotation.x), rig.position])
				if i < poses.size() - 1 or u < 1.0:
					highest = maxf(highest, Ukemi.resting_lowest(rig))
				if k == 10:
					var saved: Dictionary = poses[i]["characters"][0]["root"]
					off_at_keys = maxf(off_at_keys, rig.position.distance_to(PoseFile.array_to_vec(saved["pos"])))
		check(deepest > -0.02, "%s fall, blended: nothing under the mat on any frame (deepest %.3f m)" % [name, deepest])
		check(highest < 0.06, "%s fall, blended: the body stays on the mat, not over it (highest %.3f m)" % [name, highest])
		check(off_at_keys < 0.001, "%s fall, blended: each pose is reached exactly (%.4f m off)" % [name, off_at_keys])


func settle(frames: int = 2) -> void:
	for i in frames:
		await process_frame
