class_name Stance
extends RefCounted
## What a body does with its legs: bending the knees, pivoting on a foot, turning a foot out or
## in, and kneeling.
##
## All of it rests on one thing. A leg's IK target hangs under the character's root, so a foot
## follows the body wherever it goes. That is right when a figure walks across the mat and wrong
## for everything else: dropping the hips carries the feet down with them, so the knees never
## bend and the figure sinks through the floor instead; turning the body drags both feet round,
## so nobody can pivot. `PoseController.set_root` takes a list of limbs to leave on the mat, and
## every function here is that idea applied to one movement.

const BOTH_LEGS := ["RightLeg", "LeftLeg"]

## Kneeling: seiza sits back on the heels, kiza is up on the toes and ready to move. Both put the
## shins on the mat, which is what makes them kneeling rather than a deep squat.
enum Kneel { SEIZA, KIZA }

## Where the ankle goes when kneeling, behind and below the hips in the body's own frame, and
## where the knee is steered to. Found by trying: the leg is a two-bone chain, so the ankle
## placement sets how far the shin lies back and the pole decides which way the knee folds.
const SEIZA_ANKLE := Vector3(0.0, 0.05, -0.08)
const KIZA_ANKLE := Vector3(0.0, 0.06, -0.10)
const KNEEL_WIDTH := 0.10
const KNEEL_POLE_FORWARD := 0.60
## How the foot is turned at the ankle when kneeling, in degrees about the body's sideways axis.
## Seiza lies the instep flat on the mat behind the knee; kiza stands on the ball of the foot with
## the heel up. Without this the foot simply follows the shin and points down through the floor.
const SEIZA_FOOT_PITCH := -45.0
const KIZA_FOOT_PITCH := -45.0
## How far the hips sit above the mat when kneeling.
const SEIZA_HIP_HEIGHT := 0.25
const KIZA_HIP_HEIGHT := 0.33


## Lowers the hips by `metres`, leaving both feet on the mat, which is what bends the knees.
## This is the movement every aikido stance is built on and the rig could not do it: `hanmi`
## dropped the root and took the feet with it, so every committed pose has straight legs.
static func drop_hips(ctrl: PoseController, rig: CharacterRig, metres: float) -> void:
	ctrl.set_root(rig, rig.position - Vector3(0.0, metres, 0.0), rig.rotation.y,
		rig.rotation.x, rig.rotation.z, BOTH_LEGS)


## Turns the body `degrees` about the vertical through one foot, leaving that foot where it is.
## The other foot swings round with the body, which is what a pivot is.
static func pivot(ctrl: PoseController, rig: CharacterRig, foot: String, degrees: float) -> void:
	var here: Vector3 = rig.limbs[foot + "Leg"].target.global_position
	here.y = 0.0
	var offset := rig.global_position - here
	offset.y = 0.0
	var turned := offset.rotated(Vector3.UP, deg_to_rad(degrees))
	ctrl.set_root(rig, here + turned + Vector3(0.0, rig.position.y, 0.0),
		rig.rotation.y + deg_to_rad(degrees), rig.rotation.x, rig.rotation.z, [foot + "Leg"])


## Turns one foot out (positive) or in, about the vertical, without moving where it stands.
static func turn_foot(rig: CharacterRig, side: String, degrees: float) -> void:
	var limb: Limb = rig.limbs[side + "Leg"]
	var t := limb.target.global_transform
	limb.target.global_transform = Transform3D(t.basis.rotated(Vector3.UP, deg_to_rad(degrees)), t.origin)
	limb.set_orient_to_target(true)


## How far a foot is turned out from the way the body faces, in degrees.
static func foot_turn(rig: CharacterRig, side: String) -> float:
	var facing: Vector3 = rig.global_transform.basis.z
	var along: Vector3 = rig.bone_world_transform(side + "Foot").basis.y   # the foot's own axis
	facing.y = 0.0
	along.y = 0.0
	if facing.length() < 1e-4 or along.length() < 1e-4:
		return 0.0
	return rad_to_deg(facing.normalized().signed_angle_to(along.normalized(), Vector3.UP))


## Kneels the figure where it stands: shins down on the mat, hips over the heels. As with a fall,
## settle and then `Ukemi.ground()` to rest the body on the mat — the hip heights here are what a
## kneeling body measures, and grounding is what puts the shins exactly on the floor rather than
## a centimetre through it.
static func kneel(ctrl: PoseController, rig: CharacterRig, kind: int = Kneel.SEIZA) -> void:
	var ankle: Vector3 = SEIZA_ANKLE if kind == Kneel.SEIZA else KIZA_ANKLE
	var hip_height: float = SEIZA_HIP_HEIGHT if kind == Kneel.SEIZA else KIZA_HIP_HEIGHT
	var basis := rig.global_transform.basis
	var ground := Vector3(rig.global_position.x, 0.0, rig.global_position.z)
	for side in ["Right", "Left"]:
		var limb: Limb = rig.limbs[side + "Leg"]
		rig.set_limb_mode(side + "Leg", Limb.Mode.IK)
		var lateral := -KNEEL_WIDTH if side == "Right" else KNEEL_WIDTH
		# The foot keeps the flat orientation it had while standing. Left to follow the shin it
		# would carry on past it and point through the floor; held flat, the instep lies on the
		# mat, which is what kneeling on it means. Use turn_foot() to point it out or in.
		limb.target.global_transform = Transform3D(rig.bone_world_transform(side + "Foot").basis,
			ground + basis * (ankle + Vector3(lateral, 0.0, 0.0)))
		limb.pole.global_position = ground + basis * Vector3(lateral, 0.0, KNEEL_POLE_FORWARD)
		limb.set_orient_to_target(true)
	# The hips drop to sitting height with the ankles left on the mat, so the legs fold under.
	ctrl.set_root(rig, Vector3(ground.x, hip_height - hip_rest_height(rig), ground.z),
		rig.rotation.y, 0.0, 0.0, BOTH_LEGS)


## How high the hip joint sits above the root when the figure is standing at rest.
static func hip_rest_height(rig: CharacterRig) -> float:
	var sk := rig.skeleton
	var i := sk.find_bone("RightUpperLeg")
	return sk.get_bone_global_rest(i).origin.y if i >= 0 else 0.87


## How high the hips sit when kneeling this way, in metres above the mat.
static func kneel_hip_height(kind: int) -> float:
	return SEIZA_HIP_HEIGHT if kind == Kneel.SEIZA else KIZA_HIP_HEIGHT
