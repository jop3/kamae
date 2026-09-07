extends SceneTree
## Legs (src/rig/Stance.gd): bending the knees, pivoting on a foot, turning a foot out, kneeling.
##
## All four were impossible before, for one reason: a leg's IK target hangs under the character's
## root, so a foot went wherever the body went. Dropping the hips carried the feet down with them
## and the figure sank through the floor with its legs straight — `hanmi` has claimed to bend the
## knees since M0 and the deepest bend in any committed pose was zero degrees. So each of these
## checks that the foot stayed on the mat while the body did something.

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)

var scene: PosingScene
var ctrl: PoseController
var director: GripDirector
const POSE := "res://poses/katatedori_ikkyo_grepp.json"
## A planted foot may drift this far; the leg still solves, it is not nailed down.
const PLANTED := 0.02


func _initialize() -> void:
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	scene = PosingScene.new(); world.add_child(scene)
	var cam := Camera3D.new(); world.add_child(cam)
	var gizmo := RotationGizmo.new(); world.add_child(gizmo)
	ctrl = PoseController.new(); world.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	director = GripDirector.new(); world.add_child(director); director.setup(scene, ctrl)
	await physics_frame

	# Dropping the hips bends the knees, because the feet stay where they are.
	var rig := await _fresh()
	var straight := Anatomy.flexion_deg(rig, "RightLeg")
	var foot_was: Vector3 = rig.bone_world_transform("RightFoot").origin
	Stance.drop_hips(ctrl, rig, 0.12)   # 22 cm with the rear foot turned out asks 46° of an ankle
	await settle(5)
	var bent := Anatomy.flexion_deg(rig, "RightLeg")
	# The committed stances have bent knees now that hanmi drops the hips onto planted feet; before
	# that this pose started at exactly zero and there was no way to change it.
	check(straight > 15.0, "the committed stance already has the knee bent (%.0f°)" % straight)
	check(bent > straight + 20.0, "dropping the hips 12 cm bends it further (%.0f° to %.0f°)" % [straight, bent])
	check(foot_was.distance_to(rig.bone_world_transform("RightFoot").origin) < PLANTED,
		"the foot stayed on the mat while the hips dropped (%.3f m)"
		% foot_was.distance_to(rig.bone_world_transform("RightFoot").origin))
	check(Anatomy.problems(rig).is_empty(), "the bent stance is plausible (%s)" % ", ".join(Anatomy.problems(rig)))

	# Pivoting turns the body about one foot, and that foot stays put.
	rig = await _fresh()
	var planted_was: Vector3 = rig.bone_world_transform("RightFoot").origin
	var other_was: Vector3 = rig.bone_world_transform("LeftFoot").origin
	var yaw_was := rig.rotation.y
	Stance.pivot(ctrl, rig, "Right", 90.0)
	await settle(5)
	var planted_moved := planted_was.distance_to(rig.bone_world_transform("RightFoot").origin)
	var other_moved := other_was.distance_to(rig.bone_world_transform("LeftFoot").origin)
	check(planted_moved < PLANTED, "the pivot foot stays where it was (%.3f m)" % planted_moved)
	check(other_moved > 0.2, "the other foot swings round with the body (%.3f m)" % other_moved)
	check(absf(rad_to_deg(rig.rotation.y - yaw_was) - 90.0) < 1.0,
		"the body turned 90° (%.0f°)" % rad_to_deg(rig.rotation.y - yaw_was))

	# A foot turns out and in on the spot.
	rig = await _fresh()
	var turn_was := Stance.foot_turn(rig, "Left")
	var stood: Vector3 = rig.bone_world_transform("LeftFoot").origin
	Stance.turn_foot(rig, "Left", 30.0)
	await settle(4)
	check(absf(Stance.foot_turn(rig, "Left") - turn_was - 30.0) < 3.0,
		"turning the foot out 30° turns it 30° (%.0f° to %.0f°)" % [turn_was, Stance.foot_turn(rig, "Left")])
	check(stood.distance_to(rig.bone_world_transform("LeftFoot").origin) < PLANTED,
		"the foot turned without stepping (%.3f m)" % stood.distance_to(rig.bone_world_transform("LeftFoot").origin))
	Stance.turn_foot(rig, "Left", -30.0)
	await settle(4)
	check(absf(Stance.foot_turn(rig, "Left") - turn_was) < 3.0, "and turns back in again")

	# Kneeling: shins on the mat, hips down, and a body that still makes sense.
	for kind in [Stance.Kneel.SEIZA, Stance.Kneel.KIZA]:
		var name: String = "seiza" if kind == Stance.Kneel.SEIZA else "kiza"
		rig = await _fresh()
		Stance.kneel(ctrl, rig, kind)
		await settle(6)
		var knee: float = rig.bone_world_transform("RightLowerLeg").origin.y
		var toe: float = rig.bone_world_transform("RightToes").origin.y
		var hip: float = rig.bone_world_transform("RightUpperLeg").origin.y
		check(absf(knee) < 0.10, "%s: the knee is on the mat (%.3f m)" % [name, knee])
		check(absf(toe) < 0.10, "%s: the foot is on the mat (%.3f m)" % [name, toe])
		check(hip < 0.45, "%s: the hips are down (%.3f m, standing is about 0.87)" % [name, hip])
		check(Anatomy.flexion_deg(rig, "RightLeg") > 120.0,
			"%s: the leg is folded (%.0f°)" % [name, Anatomy.flexion_deg(rig, "RightLeg")])
		check(Anatomy.problems(rig).is_empty(), "%s: the kneeling body is plausible%s"
			% [name, "" if Anatomy.problems(rig).is_empty() else " — " + "; ".join(Anatomy.problems(rig))])
	check(Stance.kneel_hip_height(Stance.Kneel.SEIZA) < Stance.kneel_hip_height(Stance.Kneel.KIZA),
		"seiza sits lower than kiza")

	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


## A committed standing pose, reloaded, so each check starts from the same place.
func _fresh() -> CharacterRig:
	PoseFile.apply(PoseFile.load(POSE), scene, director, ctrl)
	await settle(4)
	return scene.get_character("tori")


func settle(frames: int = 2) -> void:
	for i in frames:
		await process_frame
