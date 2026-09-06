class_name MotionClearance
extends RefCounted
## Keeps the motion between two poses physical.
##
## Two saved poses can both be plausible while the straight line between them is not. The root
## position lerps, so a figure that ends up on the other side of its partner travels through it;
## a bone rotation slerps the short way round, so an arm crosses a chest instead of going round
## it. Nothing in the poses is wrong — the in-between is — and the video shows every one of those
## frames. `tests/check_motion.gd` is the measurement; this is the correction.
##
## Two mechanisms, applied in this order after every blend:
##
##  1. **Bodies apart.** Trunk against trunk, the two roots are pushed apart horizontally, so one
##     figure goes round another rather than through it. Only trunks count: an arm reaching
##     across a partner is a limb problem and moving a whole body would be the wrong answer.
##  2. **Limbs clear.** A hand or elbow inside a body is solved by IK to a cleared target, with
##     the IK influence ramped by how far it had to move, so the arm is pure FK again the moment
##     it no longer needs help.
##
## Every correction is derived from `CharacterRig.fk_bone_transform` — where the bones are under
## the blended pose alone, before any modifier runs. That matters twice over: the reading does
## not lag a frame behind the solve, and the correction cannot feed back into its own input and
## oscillate. It also makes the correction exactly zero whenever the pose is already plausible,
## which is what keeps a keyframe untouched: `PoseBlend` only calls this strictly between two
## poses, and a hold still shows the pose exactly as it was saved.
##
## A gripping arm is left alone. The grip owns that hand and pushing it away would tear it off
## what it holds; a grip that drags a hand through a body is a pose to fix, and check_motion.gd
## goes on reporting it.

## Cleared by this much beyond the tolerance the checks allow, so a correction that lands a
## frame before the deepest moment still holds.
const MARGIN := 0.01
## How many times a limb is pushed before the frame gives up; a limb caught between two bodies
## needs more than one.
const ROUNDS := 3
## A correction this large ramps an arm fully into IK; smaller ones blend in from FK.
const FULL_IK_AT := 0.03
## How far past the cleared elbow the pole is placed, as a multiple of the push it needed.
const POLE_LEVER := 2.0
## Bodies are moved apart for these bones only.
const TRUNK := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"RightShoulder", "LeftShoulder"]


## Corrects the blend the scene is currently showing. Call it after PoseBlend.apply.
static func resolve(scene: PosingScene, director: GripDirector) -> void:
	_bodies_apart(scene, director)
	_limbs_clear(scene, director)


## Pushes two trunks that overlap apart along the horizontal, half the distance each, by moving
## their roots. Zero when the trunks are clear, so it does nothing on a keyframe.
static func _bodies_apart(scene: PosingScene, director: GripDirector) -> void:
	for i in scene.characters.size():
		for j in range(i + 1, scene.characters.size()):
			var a: CharacterRig = scene.characters[i]
			var b: CharacterRig = scene.characters[j]
			if not (a.visible and b.visible):
				continue
			var worst := {}
			for o in Anatomy.body_overlaps(a, b, director, true):
				if not (o["a"] in TRUNK and o["b"] in TRUNK):
					continue
				if worst.is_empty() or o["depth"] > worst["depth"]:
					worst = o
			if worst.is_empty():
				continue
			var away: Vector3 = worst["pa"] - worst["pb"]
			away.y = 0.0
			if away.length() < 1e-4:
				away = a.global_position - b.global_position
				away.y = 0.0
			if away.length() < 1e-4:
				away = Vector3.RIGHT   # exactly on top of each other: pick a side
			away = away.normalized()
			var push: float = (worst["depth"] - Anatomy.PENETRATION + MARGIN) * 0.5
			a.position += away * push
			b.position -= away * push


## Moves a limb the blend put inside a body out to the skin, and hands it to IK for as long as
## it needs the help. A limb is cleared as a pair of capsules, not as two points: an arm can
## cross a chest with its elbow and its hand both outside the body.
static func _limbs_clear(scene: PosingScene, director: GripDirector) -> void:
	for rig in scene.characters:
		if not rig.visible:
			continue
		var obstacles := _obstacles(scene, rig)
		for key: String in rig.limbs:
			var limb: Limb = rig.limbs[key]
			if director and director.grip_on_limb(rig.character_id, key) != null:
				continue   # the grip owns this hand
			var walls: Array = obstacles + _own_obstacles(rig, limb)
			var ik := limb.mode == Limb.Mode.IK
			# Where the limb is about to be. An IK limb is at its target, which PoseBlend has
			# just lerped; an FK limb is wherever the blended rotations put it.
			var root := rig.fk_bone_transform(limb.root_bone).origin
			var mid: Vector3 = rig.bone_world_transform(limb.middle_bone).origin if ik \
				else rig.fk_bone_transform(limb.middle_bone).origin
			var end: Vector3 = limb.target.global_position if ik \
				else rig.fk_bone_transform(limb.end_bone).origin
			var moved_mid := mid
			var moved_end := end
			var depth := _worst_depth(root, moved_mid, moved_end, limb, walls)
			for _round in ROUNDS:
				var push := _push_out_of(root, moved_mid, moved_end, limb, walls)
				if push == Vector3.ZERO:
					break
				var after := _worst_depth(root, moved_mid + push, moved_end + push, limb, walls)
				if after >= depth:
					break   # out of one body and into another: leave it to the poses
				depth = after
				moved_mid += push
				moved_end += push
			var moved := moved_end - end
			if moved.length() < 1e-4 and (moved_mid - mid).length() < 1e-4:
				continue
			limb.target.global_position = moved_end
			limb.pole.global_position += (moved_mid - mid) * POLE_LEVER
			if not ik:
				# An FK limb is handed to IK only as far as it needed moving, so it is pure FK
				# again the moment the blend stops pushing it through something.
				rig.set_limb_mode(key, Limb.Mode.IK)
				limb.set_orient_to_target(false)
				limb.pole.global_position = moved_mid + (moved_mid - mid) * POLE_LEVER
				limb.set_influence(clampf(moved.length() / FULL_IK_AT, 0.0, 1.0))


## The deepest wall the limb is in at these positions, or 0 when it is clear.
static func _worst_depth(root: Vector3, mid: Vector3, end: Vector3, limb: Limb, walls: Array) -> float:
	var hit := _worst_overlap(root, mid, end, limb, walls)
	return 0.0 if hit.is_empty() else hit["depth"]


## The deepest overlap between either of the limb's capsules and any wall.
static func _worst_overlap(root: Vector3, mid: Vector3, end: Vector3, limb: Limb, walls: Array) -> Dictionary:
	var upper := [root, mid, Anatomy.RADII[limb.root_bone]]
	var lower := [mid, end, Anatomy.RADII[limb.middle_bone]]
	var worst := {}
	for seg in [upper, lower]:
		for wall: Array in walls:
			var hit := Anatomy._overlap(seg, wall)
			if hit["depth"] > Anatomy.PENETRATION and (worst.is_empty() or hit["depth"] > worst["depth"]):
				worst = hit
	return worst


## How far the limb's two capsules have to move to come out of the deepest wall they are in.
static func _push_out_of(root: Vector3, mid: Vector3, end: Vector3, limb: Limb, walls: Array) -> Vector3:
	var worst := _worst_overlap(root, mid, end, limb, walls)
	if worst.is_empty():
		return Vector3.ZERO
	var away: Vector3 = worst["pa"] - worst["pb"]
	if away.length() < 1e-4:
		return Vector3.ZERO
	return away.normalized() * (worst["depth"] - Anatomy.PENETRATION + MARGIN)


## Every capsule of every other body, as [a, b, radius].
static func _obstacles(scene: PosingScene, rig: CharacterRig) -> Array:
	var out := []
	for other in scene.characters:
		if other == rig or not other.visible:
			continue
		for seg in Anatomy.segments(other, true).values():
			out.append(seg)
	return out


## The character's own capsules, minus the ones this limb touches by design.
static func _own_obstacles(rig: CharacterRig, limb: Limb) -> Array:
	var parents := Anatomy.parents_of(rig)
	var mine := [limb.root_bone, limb.middle_bone, limb.end_bone]
	var segs := Anatomy.segments(rig, true)
	var out := []
	for name: String in segs:
		if name in mine:
			continue
		var skip := false
		for bone: String in mine:
			if Anatomy.touching_by_design(bone, name, parents):
				skip = true
				break
		if not skip:
			out.append(segs[name])
	return out
