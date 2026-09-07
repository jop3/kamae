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

	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


## The lowest point of any of the body's capsules.
func _lowest(rig: CharacterRig) -> float:
	var lowest := INF
	for seg: Array in Anatomy.segments(rig).values():
		lowest = minf(lowest, minf(seg[0].y, seg[1].y) - seg[2])
	return lowest


func settle(frames: int = 2) -> void:
	for i in frames:
		await process_frame
