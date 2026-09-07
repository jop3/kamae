class_name LimbTurn
extends RefCounted
## The one freedom a placed limb has left, and how it is spent.
##
## With the shoulder and the hand both fixed, the elbow can still be anywhere on a circle
## between them: turning the whole arm about the line from shoulder to wrist moves the elbow
## round that circle and leaves the hand exactly where it was. (The knee, hip and ankle are the
## same.) That turn is what a body uses when a joint is asked for more than it has: the humerus
## cannot twist far enough for the elbow to face where the pole put it, so the elbow goes round
## instead; the wrist cannot bend 90° sideways to take a grip, so the elbow comes out and the
## forearm arrives across the wrist. TwistFollow and HandOrient both spend it, each with its own
## cost; this is the search they share, and the arithmetic of what a joint is over by.
##
## The search knows joints, not bodies: an elbow can be turned into a chest to straighten a
## wrist. Keeping it out was tried with the character's own trunk as walls and changed nothing
## measurable (tests/check_motion.gd counts are the same with and without), and with the other
## characters as walls it made a reloaded pose settle somewhere other than where it was saved,
## since where they are is only known from the previous frame. So bodies stay the poses' and
## MotionClearance's business, and Anatomy reports a limb through a body as it always did.

## Angles searched at first, degrees apart; the best is then refined by halving.
const COARSE_STEP := 30.0
const REFINE_STEPS := 4
## Turning away from where the pole put the elbow costs this much per degree, so of two turns
## that both satisfy the joints the smaller wins and the elbow stays where it was steered.
const TURN_COST_PER_DEG := 0.05


## The turn, in degrees, with the lowest `cost` (a Callable taking degrees and returning a
## float). 0 wins outright when it costs nothing, which is every frame of a plausible pose.
static func search(cost: Callable) -> float:
	var at_zero: float = cost.call(0.0)
	if at_zero <= 1e-6:
		return 0.0
	var best := 0.0
	var best_cost := at_zero
	var phi := -180.0 + COARSE_STEP
	while phi <= 180.0:
		if absf(phi) > 1e-6:
			var c: float = cost.call(phi)
			if c < best_cost:
				best = phi; best_cost = c
		phi += COARSE_STEP
	var step := COARSE_STEP * 0.5
	for _i in REFINE_STEPS:
		for cand in [best - step, best + step]:
			var c: float = cost.call(cand)
			if c < best_cost:
				best = cand; best_cost = c
		step *= 0.5
	return best


## How many degrees the joint's angles lie outside its range, all three added together.
static func excess(spec: Dictionary, a: Dictionary) -> float:
	var e := Joints.excess(spec, a)
	return e["flex"] + e["abd"] + e["twist"]


## The angles a bone would have against its parent with the given world bases.
static func angles_of(spec: Dictionary, parent_basis: Basis, basis: Basis) -> Dictionary:
	return Joints.angles(spec, (parent_basis.orthonormalized().inverse() * basis.orthonormalized()).orthonormalized().get_rotation_quaternion())


## The component, radians, about `axis` of the rotation taking basis `from` onto `to`.
static func twist_between(from: Basis, to: Basis, axis: Vector3) -> float:
	var delta := (to.orthonormalized() * from.orthonormalized().inverse()).get_rotation_quaternion().normalized()
	if delta.w < 0.0:
		delta = -delta
	var proj := Vector3(delta.x, delta.y, delta.z).dot(axis.normalized())
	return wrapf(2.0 * atan2(proj, delta.w), -PI, PI)


## How much of a roll of `want` radians a bone can take about `axis` before any of its angles
## leaves its range: the whole of it, part, or none. Each angle is taken to run linearly with
## the roll, exact for a roll about the bone's own axis.
static func roll_within(spec: Dictionary, parent_basis: Basis, basis: Basis, axis: Vector3, want: float) -> float:
	var a_now := angles_of(spec, parent_basis, basis)
	var a_all := angles_of(spec, parent_basis, Basis(axis.normalized(), want) * basis)
	var lim := Joints.limits(spec, a_now)
	var fraction := 1.0
	for key in ["flex", "abd", "twist"]:
		var v0: float = a_now[key]
		var v1: float = a_all[key]
		if key == "flex":
			v0 = Joints._nearest_turn(v0, lim[key][0], lim[key][1])
			v1 = Joints._nearest_turn(v1, lim[key][0], lim[key][1])
		if v1 >= lim[key][0] - 0.01 and v1 <= lim[key][1] + 0.01:
			continue
		var room: float = (lim[key][1] - v0) if v1 > v0 else (lim[key][0] - v0)
		var span := v1 - v0
		if absf(span) < 1e-6:
			continue
		fraction = minf(fraction, clampf(room / span, 0.0, 1.0))
	return want * fraction


## Writes a world basis for bone `i` as a local pose rotation against its parent. Descendants
## keep their local poses, so everything below turns rigidly with it: about the bone's own
## axis that leaves the next joint where it was; about the line from this joint to the end
## bone it leaves the end bone where it was and swings the joint between them round.
static func set_world_basis(sk: Skeleton3D, i: int, basis: Basis) -> void:
	var parent := sk.get_bone_parent(i)
	var parent_basis := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(i, (parent_basis.inverse() * basis.orthonormalized()).orthonormalized().get_rotation_quaternion())
