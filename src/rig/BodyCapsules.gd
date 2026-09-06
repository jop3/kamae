class_name BodyCapsules
extends RefCounted
## The body as capsules, one per major bone, for collision: keeping a gripping hand on the
## surface of what it grips, stopping a dragged hand at another body, and the plausibility
## checks in Anatomy. One radius table for all of them (Anatomy.RADII), so a hand that the
## grip placed on the skin is exactly a hand the checks accept.

## Radius of a bone's capsule, metres. Fingers are thin; unknown bones get a forearm.
static func radius(bone_name: String) -> float:
	if Anatomy.RADII.has(bone_name):
		return Anatomy.RADII[bone_name]
	if FingerCurl.is_finger_bone(bone_name):
		return 0.011
	return 0.04


## Closest point to `p` on the segment a-b.
static func closest_on_segment(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-12:
		return a
	return a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0)


## Moves a sphere (centre `point`, radius `r`) out of `rig`'s capsules, ignoring the bones named
## in `exempt` (a gripped bone and its neighbours, where the hand overlaps by design). Only
## penetrations deeper than `slack` count, so a hand resting on the skin does not jitter.
## Returns the corrected centre; two passes settle a point caught between two capsules.
static func push_out(point: Vector3, r: float, rig: CharacterRig, exempt: Array = [], slack: float = 0.005) -> Vector3:
	var segs := Anatomy.segments(rig)
	var p := point
	for _round in 2:
		for name: String in segs:
			if name in exempt:
				continue
			var seg: Array = segs[name]
			var c := closest_on_segment(p, seg[0], seg[1])
			var away := p - c
			var d := away.length()
			var depth: float = (seg[2] + r) - d
			if depth <= slack:
				continue
			if d < 1e-4:
				away = rig.global_transform.basis.x   # dead centre: pick a side
				d = 1.0
			p += away / d * depth
	return p


## Deepest penetration of a sphere into `rig` (metres, 0 when clear), for tests and indicators.
static func penetration(point: Vector3, r: float, rig: CharacterRig, exempt: Array = []) -> float:
	var segs := Anatomy.segments(rig)
	var worst := 0.0
	for name: String in segs:
		if name in exempt:
			continue
		var seg: Array = segs[name]
		var d := point.distance_to(closest_on_segment(point, seg[0], seg[1]))
		worst = maxf(worst, (seg[2] + r) - d)
	return worst


## The gripped bone and its parent and children: a hand closed on a bone overlaps those.
static func neighbours(rig: CharacterRig, bone_name: String) -> Array:
	var sk := rig.skeleton
	var i := sk.find_bone(bone_name)
	var out := [bone_name]
	if i < 0:
		return out
	var p := sk.get_bone_parent(i)
	if p >= 0:
		out.append(sk.get_bone_name(p))
	for c in sk.get_bone_children(i):
		out.append(sk.get_bone_name(c))
	return out
