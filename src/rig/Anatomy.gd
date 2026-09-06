class_name Anatomy
extends RefCounted
## Plausibility checks on a posed character: joint ranges, bend directions, self-intersection,
## weapons through bodies, and the skinned mesh itself. Everything here reads the solved pose
## through CharacterRig.bone_world_transform(), so it is valid outside skeleton_updated.
##
## The checks are deliberately coarse. They are meant to catch a pose that could not be a human
## (an elbow bent backwards, a forearm through the chest, a shin folded through the thigh, a mesh
## that shears into strands), not to judge whether a technique is performed well.

## Approximate body radii per bone, metres, for intersection tests. Segments touching is fine;
## a segment more than PENETRATION deeper than touching is reported.
const RADII := {
	"Hips": 0.11, "Spine": 0.10, "Chest": 0.10, "UpperChest": 0.10, "Neck": 0.05, "Head": 0.10,
	"RightShoulder": 0.05, "LeftShoulder": 0.05,
	"RightUpperArm": 0.045, "LeftUpperArm": 0.045, "RightLowerArm": 0.04, "LeftLowerArm": 0.04,
	"RightHand": 0.03, "LeftHand": 0.03,
	"RightUpperLeg": 0.075, "LeftUpperLeg": 0.075, "RightLowerLeg": 0.05, "LeftLowerLeg": 0.05,
	"RightFoot": 0.035, "LeftFoot": 0.035,
}
const PENETRATION := 0.035
const WEAPON_RADIUS := 0.015

## Joint flexion limits in degrees: [min, max] of the angle between the two bone directions.
## 0 is straight. Elbows and knees do not hyperextend on this mannequin's rest pose.
const FLEXION := {
	"RightArm": [0.0, 160.0], "LeftArm": [0.0, 160.0],
	"RightLeg": [0.0, 150.0], "LeftLeg": [0.0, 150.0],
}
## Beyond this flexion the bend direction is unambiguous enough to check.
const BEND_CHECK_FROM := 12.0

## The head and neck: angle between the neck bone direction and the chest direction.
const NECK_MAX := 70.0

## Named limb pairs that may legitimately touch and are not tested against each other:
## adjacent bones, both bones of a hand on its own forearm, both legs at the crotch.
static func _skip_pair(a: String, b: String, parent_of: Dictionary) -> bool:
	if parent_of.get(a, "") == b or parent_of.get(b, "") == a:
		return true
	if parent_of.get(a, "") == parent_of.get(b, "x"):
		return true
	var torso := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "RightShoulder", "LeftShoulder"]
	if a in torso and b in torso:
		return true
	# Hands and forearms against each other: two-handed holds stack the hands and lay the
	# forearms side by side, crossed arms cross them.
	var ends := ["RightHand", "LeftHand", "RightLowerArm", "LeftLowerArm"]
	if a in ends and b in ends:
		return true
	# Shoulders sit inside the chest; upper arms start there.
	for side: String in ["Right", "Left"]:
		var s: String = side + "Shoulder"
		var u: String = side + "UpperArm"
		if (a == s or a == u) and b in torso: return true
		if (b == s or b == u) and a in torso: return true
	# The thighs meet at the hips.
	if a.ends_with("UpperLeg") and b.ends_with("UpperLeg"): return true
	if (a.ends_with("UpperLeg") and b == "Hips") or (b.ends_with("UpperLeg") and a == "Hips"): return true
	if (a.ends_with("UpperLeg") and b == "Spine") or (b.ends_with("UpperLeg") and a == "Spine"): return true
	return false


## Runs every check on one character. Returns a list of problem strings; empty means plausible.
static func problems(rig: CharacterRig) -> PackedStringArray:
	var out := PackedStringArray()
	out.append_array(joint_problems(rig))
	out.append_array(self_intersections(rig))
	out.append_array(bone_scale_problems(rig))
	return out


## Every character against itself, every pair of characters, and every weapon against every
## character. Hands and forearms holding a weapon are exempt from that weapon.
static func scene_problems(scene: PosingScene, director: GripDirector = null) -> PackedStringArray:
	var out := PackedStringArray()
	for rig in scene.characters:
		if not rig.visible:
			continue
		for p in problems(rig):
			out.append("%s: %s" % [rig.character_id, p])
	for i in scene.characters.size():
		for j in range(i + 1, scene.characters.size()):
			var a: CharacterRig = scene.characters[i]
			var b: CharacterRig = scene.characters[j]
			if a.visible and b.visible:
				out.append_array(body_intersections(a, b, director))
	for w in scene.weapons:
		out.append_array(weapon_intersections(w, scene, director))
	return out


# --- joints ----------------------------------------------------------------------------------

static func flexion_deg(rig: CharacterRig, limb_key: String) -> float:
	var chain := _chain(limb_key)
	var p0 := rig.bone_world_transform(chain[0]).origin
	var p1 := rig.bone_world_transform(chain[1]).origin
	var p2 := rig.bone_world_transform(chain[2]).origin
	return rad_to_deg((p1 - p0).angle_to(p2 - p1))


## Which way the middle joint bends, unit vector perpendicular to the upper segment; zero when
## the limb is straight.
static func bend_direction(rig: CharacterRig, limb_key: String) -> Vector3:
	var chain := _chain(limb_key)
	var p0 := rig.bone_world_transform(chain[0]).origin
	var p1 := rig.bone_world_transform(chain[1]).origin
	var p2 := rig.bone_world_transform(chain[2]).origin
	var d1 := (p1 - p0).normalized()
	var d2 := (p2 - p1).normalized()
	var n := d2 - d1 * d2.dot(d1)
	return n.normalized() if n.length_squared() > 1e-8 else Vector3.ZERO


## The direction a joint folds toward at rest, in the root bone's own frame: the mannequin's rest
## elbows are already flexed about 45° forward, which tells the flexion side; knees fold
## backwards, i.e. away from the foot's toes. Carried in the root bone's frame so a rotated or
## twisted upper arm rotates its allowed bend with it. Used by TwistFollow and by the checks.
static func rest_bend_local(sk: Skeleton3D, limb_key: String) -> Vector3:
	var chain := _chain(limb_key)
	var i0 := sk.find_bone(chain[0]); var i1 := sk.find_bone(chain[1]); var i2 := sk.find_bone(chain[2])
	var r0 := sk.get_bone_global_rest(i0); var r1 := sk.get_bone_global_rest(i1); var r2 := sk.get_bone_global_rest(i2)
	var d1 := (r1.origin - r0.origin).normalized()
	var n: Vector3
	if limb_key.ends_with("Arm"):
		var d2 := (r2.origin - r1.origin).normalized()
		n = d2 - d1 * d2.dot(d1)
	else:
		var toes := sk.get_bone_global_rest(sk.find_bone(limb_key.replace("Leg", "") + "Toes")).origin
		var forward := toes - r2.origin
		n = -(forward - d1 * forward.dot(d1))
	return (r0.basis.orthonormalized().inverse() * n.normalized()).normalized()


## The rest fold direction carried by the posed root bone, world space, perpendicular to it.
static func allowed_bend_direction(rig: CharacterRig, limb_key: String) -> Vector3:
	var chain := _chain(limb_key)
	var root := rig.bone_world_transform(chain[0])
	var d1 := (rig.bone_world_transform(chain[1]).origin - root.origin).normalized()
	var a := root.basis.orthonormalized() * rest_bend_local(rig.skeleton, limb_key)
	a -= d1 * a.dot(d1)
	return a.normalized()


static func joint_problems(rig: CharacterRig) -> PackedStringArray:
	var out := PackedStringArray()
	for key: String in FLEXION:
		var f := flexion_deg(rig, key)
		var lim: Array = FLEXION[key]
		if f < lim[0] - 1.0 or f > lim[1] + 1.0:
			out.append("%s flexion %.0f° outside %.0f–%.0f°" % [key, f, lim[0], lim[1]])
		if f > BEND_CHECK_FROM:
			var d := bend_direction(rig, key).dot(allowed_bend_direction(rig, key))
			if d < -0.2:
				out.append("%s bends the wrong way (%.0f°, alignment %.2f)" % [key, f, d])
	var neck := rig.bone_world_transform("Head").origin - rig.bone_world_transform("Neck").origin
	var chest := rig.bone_world_transform("Neck").origin - rig.bone_world_transform("Chest").origin
	var neck_deg := rad_to_deg(neck.angle_to(chest))
	if neck_deg > NECK_MAX:
		out.append("neck folded %.0f° against the chest" % neck_deg)
	return out


static func _chain(limb_key: String) -> Array:
	for c in CharacterRig.LIMB_CHAINS:
		if c[0] == limb_key:
			return [c[1], c[2], c[3]]
	assert(false, "unknown limb " + limb_key)
	return []


# --- bone scale ------------------------------------------------------------------------------

## Any non-unit scale in a solved bone pose stretches the mesh (docs/engine-notes.md).
static func bone_scale_problems(rig: CharacterRig) -> PackedStringArray:
	var out := PackedStringArray()
	for name: String in RADII:
		var s := rig.bone_world_transform(name).basis.get_scale()
		if not s.is_equal_approx(Vector3.ONE) and (s - Vector3.ONE).length() > 0.01:
			out.append("%s carries scale %s" % [name, s])
	return out


# --- intersections ---------------------------------------------------------------------------

## Segments (start, end, radius) for the bones in RADII. A bone runs from its origin to its
## child's origin (mean of children), leaves get a short stub along their axis.
static func segments(rig: CharacterRig) -> Dictionary:
	var sk := rig.skeleton
	var out := {}
	for name: String in RADII:
		var i := sk.find_bone(name)
		if i < 0:
			continue
		var a := rig.bone_world_transform(name).origin
		var children := sk.get_bone_children(i)
		var b: Vector3
		if children.size() > 0:
			b = Vector3.ZERO
			for c in children:
				b += rig.bone_world_transform(sk.get_bone_name(c)).origin
			b /= children.size()
		else:
			b = a + rig.bone_world_transform(name).basis.y * 0.08
		out[name] = [a, b, RADII[name]]
	return out


static func _parents(rig: CharacterRig) -> Dictionary:
	var sk := rig.skeleton
	var out := {}
	for name: String in RADII:
		var i := sk.find_bone(name)
		var p := sk.get_bone_parent(i)
		out[name] = sk.get_bone_name(p) if p >= 0 else ""
	return out


static func self_intersections(rig: CharacterRig) -> PackedStringArray:
	var out := PackedStringArray()
	var segs := segments(rig)
	var parents := _parents(rig)
	var names := segs.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: String = names[i]; var b: String = names[j]
			if _skip_pair(a, b, parents):
				continue
			var depth := _penetration(segs[a], segs[b])
			if depth > PENETRATION:
				out.append("%s passes through %s (%.1f cm deep)" % [a, b, depth * 100.0])
	return out


## Two characters: any segment of one deeper than PENETRATION into any of the other, except a
## gripping hand against the limb it grips (a hand closed on a wrist overlaps it by design).
static func body_intersections(a: CharacterRig, b: CharacterRig, director: GripDirector = null) -> PackedStringArray:
	var out := PackedStringArray()
	var sa := segments(a); var sb := segments(b)
	var exempt := {}
	if director:
		for g in director.grips:
			if g.target.kind == GripTarget.Kind.BONE:
				# The gripped bone and its neighbours: a fist on a wrist overlaps the hand too.
				var target_rig := a if g.target.character_id == a.character_id else b
				var sk := target_rig.skeleton
				var ti := sk.find_bone(g.target.bone_name)
				var near := [g.target.bone_name]
				if sk.get_bone_parent(ti) >= 0:
					near.append(sk.get_bone_name(sk.get_bone_parent(ti)))
				for c in sk.get_bone_children(ti):
					near.append(sk.get_bone_name(c))
				for n in near:
					exempt["%s/%sHand|%s/%s" % [g.gripper_id, g.hand, g.target.character_id, n]] = true
					exempt["%s/%sLowerArm|%s/%s" % [g.gripper_id, g.hand, g.target.character_id, n]] = true
	for na in sa:
		for nb in sb:
			if exempt.has("%s/%s|%s/%s" % [a.character_id, na, b.character_id, nb]) or exempt.has("%s/%s|%s/%s" % [b.character_id, nb, a.character_id, na]):
				continue
			var depth := _penetration(sa[na], sb[nb])
			if depth > PENETRATION:
				out.append("%s %s passes through %s %s (%.1f cm deep)" % [a.character_id, na, b.character_id, nb, depth * 100.0])
	return out


## A weapon's shaft against every character. The holder's hands and forearms are exempt (the
## shaft runs through the fist), and so is any hand gripping the weapon.
static func weapon_intersections(w: Weapon, scene: PosingScene, director: GripDirector = null) -> PackedStringArray:
	var out := PackedStringArray()
	var butt := w.anchor_transform(0.0).origin
	var tip := w.anchor_transform(1.0).origin
	var exempt := {}
	if not w.hold.is_empty():
		exempt["%s/%sHand" % [w.hold["character"], w.hold["hand"]]] = true
		exempt["%s/%sLowerArm" % [w.hold["character"], w.hold["hand"]]] = true
	if director:
		for g in director.grips:
			if g.target.kind == GripTarget.Kind.WEAPON and g.target.weapon_id == w.weapon_id:
				exempt["%s/%sHand" % [g.gripper_id, g.hand]] = true
				exempt["%s/%sLowerArm" % [g.gripper_id, g.hand]] = true
	for rig in scene.characters:
		if not rig.visible:
			continue
		var segs := segments(rig)
		for name: String in segs:
			if exempt.has("%s/%s" % [rig.character_id, name]):
				continue
			var depth := _penetration([butt, tip, WEAPON_RADIUS], segs[name])
			if depth > PENETRATION:
				out.append("%s passes through %s %s (%.1f cm deep)" % [w.weapon_id, rig.character_id, name, depth * 100.0])
	return out


## How far two capsules overlap beyond touching, metres; 0 or less when apart.
static func _penetration(s1: Array, s2: Array) -> float:
	var d := _segment_distance(s1[0], s1[1], s2[0], s2[1])
	return (s1[2] + s2[2]) - d


static func _segment_distance(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1; var d2 := q2 - p2; var r := p1 - p2
	var a := d1.dot(d1); var e := d2.dot(d2); var f := d2.dot(r)
	var s := 0.0; var t := 0.0
	if a <= 1e-9 and e <= 1e-9:
		return r.length()
	if a <= 1e-9:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-9:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			if denom > 1e-9:
				s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0; s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0; s = clampf((b - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)


# --- skinned mesh ----------------------------------------------------------------------------

## Skins the body mesh on the CPU with the solved pose and reports where the skin misbehaves:
## for each bone, the vertices it mostly owns should keep about their rest distance from the
## bone's axis. A candy-wrapper collapse at a twisted wrist, a limb stretched into strands, or a
## mesh left behind by its bones all show up as a large spread of that ratio. `stats` receives
## per-bone median and 5th/95th percentile ratios for calibration.
static func skin_problems(rig: CharacterRig, stats: Dictionary = {}) -> PackedStringArray:
	var out := PackedStringArray()
	var mesh: Mesh = rig.body.mesh
	var skin: Skin = rig.body.skin
	var sk := rig.skeleton
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per_vertex := bones.size() / verts.size()
	# skin matrix per bind: posed global * bind pose (bind pose = inverse global rest).
	var bind_bone := PackedInt32Array()
	var skin_xf: Array[Transform3D] = []
	var mesh_to_world := rig.body.global_transform
	var world_to_mesh := mesh_to_world.affine_inverse()
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = sk.find_bone(skin.get_bind_name(b))
		bind_bone.append(bone)
		skin_xf.append(world_to_mesh * rig.bone_world_transform(sk.get_bone_name(bone)) * skin.get_bind_pose(b))
	# Rest and posed axis per bone, in mesh space.
	var axis_rest := {}; var axis_posed := {}
	for name: String in RADII:
		var i := sk.find_bone(name)
		var children := sk.get_bone_children(i)
		var a_r := sk.get_bone_global_rest(i).origin
		var a_p: Vector3 = world_to_mesh * rig.bone_world_transform(name).origin
		var b_r: Vector3; var b_p: Vector3
		if children.size() > 0:
			b_r = Vector3.ZERO; b_p = Vector3.ZERO
			for c in children:
				b_r += sk.get_bone_global_rest(c).origin
				b_p += world_to_mesh * rig.bone_world_transform(sk.get_bone_name(c)).origin
			b_r /= children.size(); b_p /= children.size()
		else:
			b_r = a_r + sk.get_bone_global_rest(i).basis.y * 0.08
			b_p = a_p + (world_to_mesh * rig.bone_world_transform(name)).basis.y * 0.08
		axis_rest[i] = [a_r, b_r]; axis_posed[i] = [a_p, b_p]
	var ratios := {}
	for v in verts.size():
		var best := -1; var best_w := 0.0
		var posed := Vector3.ZERO
		for k in per_vertex:
			var w := weights[v * per_vertex + k]
			if w <= 0.0:
				continue
			var bind := bones[v * per_vertex + k]
			posed += skin_xf[bind] * verts[v] * w
			if w > best_w:
				best_w = w; best = bind_bone[bind]
		if best < 0 or best_w < 0.6 or not axis_rest.has(best):
			continue
		var r_rest := _point_segment_distance(verts[v], axis_rest[best][0], axis_rest[best][1])
		if r_rest < 0.01:
			continue
		var r_posed := _point_segment_distance(posed, axis_posed[best][0], axis_posed[best][1])
		if not ratios.has(best):
			ratios[best] = PackedFloat32Array()
		ratios[best].append(r_posed / r_rest)
	for bone: int in ratios:
		var arr: PackedFloat32Array = ratios[bone]
		arr.sort()
		var n := arr.size()
		if n < 20:
			continue
		var p05 := arr[int(n * 0.05)]; var p50 := arr[n / 2]; var p95 := arr[int(n * 0.95)]
		var name := sk.get_bone_name(bone)
		stats[name] = [p05, p50, p95, n]
		if p50 < 0.7 or p50 > 1.4:
			out.append("%s skin sits %.0f%% of its rest distance from the bone (median)" % [name, p50 * 100.0])
		elif p05 < 0.35 or p95 > 2.0:
			out.append("%s skin distorted (5%%..95%% of rest radius: %.2f..%.2f)" % [name, p05, p95])
	return out


static func _point_segment_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-12:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
