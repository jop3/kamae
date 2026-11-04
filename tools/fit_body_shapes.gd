extends SceneTree
## Fits the collision shapes of the body (Anatomy.SHAPES) to the mannequin's rest mesh and prints
## them as GDScript, to paste over the table. Run after a change to the body mesh:
##   godot --headless -s tools/fit_body_shapes.gd
## Every shape is a capsule given by two points in the rest pose (character space, metres: +X
## the figure's left, +Z its front) and a radius; it moves with its bone. The trunk is a stack of
## capsules lying across the body, one per trunk bone, which fits a chest that is wider than it
## is deep and lies in front of the spine (the spine bones run down the back); the limbs and the
## head are a capsule along the bone moved onto the middle of the flesh around it.

const TRUNK := {"Hips": [0.86, 0.98], "Spine": [0.98, 1.12], "Chest": [1.12, 1.26], "UpperChest": [1.26, 1.40]}
## Share of a bone's vertices a limb capsule must hold.
const COVER := 0.9


func _initialize() -> void:
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	var scene := PosingScene.new(); world.add_child(scene)
	await physics_frame
	scene.add_character("tori", "Tori", "Tori")
	var rig: CharacterRig = scene.get_character("tori")
	for i in 3: await process_frame
	var sk := rig.skeleton
	var arrays := rig.body.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / verts.size()
	var skin: Skin = rig.body.skin
	var dom := PackedStringArray(); var dom_w := PackedFloat32Array()
	for v in verts.size():
		var best := -1; var bw := 0.0
		for k in per:
			var w := weights[v * per + k]
			if w > bw: bw = w; best = bones[v * per + k]
		var bi := skin.get_bind_bone(best)
		if bi < 0: bi = sk.find_bone(skin.get_bind_name(best))
		dom.append(sk.get_bone_name(bi)); dom_w.append(bw)
	var mesh_xf := sk.global_transform.affine_inverse() * rig.body.global_transform
	var lines := PackedStringArray()
	# The trunk: one capsule across the body per band of height.
	for bone: String in TRUNK:
		var band: Array = TRUNK[bone]
		var xs := []; var zs := []
		for v in verts.size():
			var p := mesh_xf * verts[v]
			if p.y < band[0] or p.y > band[1] or not _trunk_vertex(dom[v]):
				continue
			xs.append(absf(p.x)); zs.append(p.z)
		xs.sort(); zs.sort()
		var half_w: float = _q(xs, 0.98)
		var z0: float = _q(zs, 0.02); var z1: float = _q(zs, 0.98)
		var r := (z1 - z0) * 0.5
		var zc := (z1 + z0) * 0.5
		var yc: float = (float(band[0]) + float(band[1])) * 0.5
		var hl := maxf(half_w - r, 0.0)
		lines.append('\t"%s": [Vector3(%.3f, %.3f, %.3f), Vector3(%.3f, %.3f, %.3f), %.3f],' % [bone, -hl, yc, zc, hl, yc, zc, r])
	# The neck, the head and the limbs: the bone's own segment moved onto the flesh's middle.
	for bone: String in Anatomy.RADII:
		if TRUNK.has(bone):
			continue
		var i := sk.find_bone(bone)
		var seg := _rest_segment(sk, i)
		var a: Vector3 = seg[0]; var b: Vector3 = seg[1]
		var ax := (b - a).normalized(); var L := a.distance_to(b)
		var pts := []
		var lo := INF; var hi := -INF
		for v in verts.size():
			if dom[v] != bone or dom_w[v] < 0.5:
				continue
			var p := mesh_xf * verts[v]
			var t := (p - a).dot(ax)
			if bone != "Head" and (t < -0.02 or t > L + 0.02):
				continue
			pts.append(p); lo = minf(lo, t); hi = maxf(hi, t)
		if pts.size() < 10:
			continue
		# The middle of the flesh across the bone, as the middle of its extent both ways (a mean
		# would lean toward where the mesh is dense: the face, the fingers' roots).
		var u := ax.cross(Vector3.FORWARD if absf(ax.z) < 0.9 else Vector3.UP).normalized()
		var w := ax.cross(u).normalized()
		var us := []; var ws := []
		for p: Vector3 in pts:
			us.append((p - a).dot(u)); ws.append((p - a).dot(w))
		us.sort(); ws.sort()
		var centre: Vector3 = u * (_q(us, 0.03) + _q(us, 0.97)) * 0.5 + w * (_q(ws, 0.03) + _q(ws, 0.97)) * 0.5
		var a2 := a + centre; var b2 := b + centre
		if bone == "Head":   # a leaf: span the skull from the jaw to the crown
			a2 = a + centre + ax * (lo + 0.07); b2 = a + centre + ax * (hi - 0.07)
		var rads := []
		for p: Vector3 in pts:
			rads.append(p.distance_to(_closest(p, a2, b2)))
		rads.sort()
		var r: float = _q(rads, COVER)
		if OS.get_environment("FIT_BANDS") == "1":   # how the flesh tapers along the bone
			var bands := []
			for k in 5:
				var rr := []
				for p: Vector3 in pts:
					var t := (p - a2).dot(ax) / maxf(L, 1e-6)
					if t >= k * 0.2 and t < (k + 1) * 0.2:
						rr.append(p.distance_to(_closest(p, a2, b2)))
				rr.sort()
				bands.append("%.3f" % (_q(rr, COVER) if rr.size() > 3 else 0.0))
			print("# %s bands %s" % [bone, " ".join(bands)])
		if bone.ends_with("Foot"):
			# A foot is flat, and a capsule round all of it would reach under the sole: keep the
			# capsule's underside on the sole and let it be a little narrow.
			r = minf(r, 0.032)
			a2.y = r + 0.004; b2.y = r + 0.002   # the heel a little higher, as the ankle is
		lines.append('\t"%s": [Vector3(%.3f, %.3f, %.3f), Vector3(%.3f, %.3f, %.3f), %.3f],' % [bone, a2.x, a2.y, a2.z, b2.x, b2.y, b2.z, r])
	print("const SHAPES := {\n%s\n}" % "\n".join(lines))
	quit()


static func _trunk_vertex(bone: String) -> bool:
	return bone in ["Hips", "Spine", "Chest", "UpperChest", "RightShoulder", "LeftShoulder", "Neck"] or bone.ends_with("UpperLeg")


static func _rest_segment(sk: Skeleton3D, i: int) -> Array:
	var g := sk.get_bone_global_rest(i)
	var kids := sk.get_bone_children(i)
	if kids.is_empty():
		return [g.origin, g.origin + g.basis.y.normalized() * 0.08]
	var b := Vector3.ZERO
	for c in kids:
		b += sk.get_bone_global_rest(c).origin
	return [g.origin, b / kids.size()]


static func _closest(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a
	return a + ab * clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)


static func _q(arr: Array, f: float) -> float:
	return arr[clampi(int(arr.size() * f), 0, arr.size() - 1)]
