class_name Gi
extends Node
## A white keikogi built at runtime from the mannequin itself (spec §7.1, M9): the body mesh is
## pushed out along its normals into a loose shell, cut into a jacket and trousers, and skinned
## with the body's own weights, so it follows every pose without any extra rigging. The belt is
## a ring measured round the waist, with a knot and two hanging ends, in the character's own
## colour as a second identification cue. Hems, collar, sleeve ends and the V are straight
## lines: triangles across an edge are kept with their outside vertices moved onto it.

const WHITE := Color(0.90, 0.89, 0.85)
## How far the cloth stands off the skin, metres. The jacket is the loose one.
const JACKET_OFFSET := 0.022
const SLEEVE_OFFSET := 0.040
const TROUSER_OFFSET := 0.014
## Rest-pose heights, metres, on this mannequin (hips joint at 0.91, waist just above it).
const BELT_Y := 0.985
const BELT_HEIGHT := 0.045
const BELT_THICKNESS := 0.010
const JACKET_HEM_Y := 0.76
const TROUSER_HEM_Y := 0.15
## The sleeve ends this far along the forearm (elbow 0 → wrist 1); the trouser leg this far
## along the shin (knee 0 → ankle 1).
const SLEEVE_END := 0.55
const LEG_END := 0.82
## The jacket's V: half-width of the opening at the collar bone, closing at the belt.
const V_TOP_Y := 1.40
const V_HALF_WIDTH := 0.075
## The lapel band (eri): a thick stitched strip along both fronts and round the neck. The
## fronts overlap below the sternum, the character's left over the right as a gi is worn.
const LAPEL_WIDTH := 0.060
const LAPEL_THICKNESS := 0.010
const LAPEL_OVERLAP_X := 0.075

var rig: CharacterRig
var jacket: MeshInstance3D
var trousers: MeshInstance3D
var belt: MeshInstance3D
var lapel: MeshInstance3D
var lapel_material: StandardMaterial3D
var collar_material: StandardMaterial3D
## Body vertices bucketed by 5 cm cell, for finding the skin under a point (see _nearest).
var _grid: Dictionary = {}
var _grid_arrays: Array = []
var cloth_material: StandardMaterial3D
var trouser_material: StandardMaterial3D
var belt_material: StandardMaterial3D
## Generated once per process and shared: the weave images are the same for every character.
static var _textures: Dictionary = {}


func build(for_rig: CharacterRig) -> void:
	rig = for_rig
	cloth_material = _cloth_material("sashiko", WHITE)
	trouser_material = _cloth_material("canvas", WHITE)
	belt_material = _cloth_material("canvas", rig.get_skin_color())
	lapel_material = _cloth_material("stitched", WHITE)
	collar_material = _cloth_material("canvas", WHITE)
	var body: MeshInstance3D = rig.body
	var arrays: Array = body.mesh.surface_get_arrays(0)
	var dominant := _dominant_bones(arrays)
	_build_grid(arrays)
	jacket = _shell(arrays, dominant, "jacket", cloth_material)
	trousers = _shell(arrays, dominant, "trousers", trouser_material)
	belt = _belt(arrays, dominant)
	lapel = _lapel(arrays, dominant)
	for m in [jacket, trousers, belt, lapel]:
		m.cast_shadow = body.cast_shadow
		rig.skeleton.add_child(m)
		# A MeshInstance3D made in code has an empty skeleton path, not the ".." the importer
		# writes, so without this the cloth stays in its rest pose while the body moves.
		m.skeleton = m.get_path_to(rig.skeleton)
		m.skin = body.skin


# ---------------------------------------------------------------- cloth

## Tiling weave textures, made in code so the gi carries no asset: "sashiko" is the rice-grain
## quilting of a heavy jacket (a diamond lattice of raised grains over a coarse weave),
## "canvas" the plain weave of trousers and belt. Height maps become normal maps for relief;
## the albedo carries the same pattern faintly so it reads in flat light too. Mapped triplanar
## in world metres (one tile is TILE_M), since the shell has no seams of its own.
const TEX := 256
const TILE_M := 0.08

static func _cloth_textures(kind: String) -> Array:
	if _textures.has(kind):
		return _textures[kind]
	var h := Image.create(TEX, TEX, false, Image.FORMAT_RF)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# A little per-thread noise so the weave is not perfectly regular.
	var noise := PackedFloat32Array()
	noise.resize(TEX * TEX)
	for i in TEX * TEX:
		noise[i] = rng.randf()
	for y in TEX:
		for x in TEX:
			var v := 0.0
			var weave_x := 0.5 + 0.5 * sin(TAU * x / 8.0)   # threads every 2.5 mm
			var weave_y := 0.5 + 0.5 * sin(TAU * y / 8.0)
			var weave := maxf(weave_x, weave_y) * 0.35 + noise[y * TEX + x] * 0.12
			match kind:
				"sashiko":
					# Rice grains on a diamond lattice, about 6 mm across, staggered rows: the
					# fine relief of a heavy judo-style jacket, read up close.
					var cell := TEX / 12.0
					var row := floorf(y / cell)
					var sx := fmod(x + (cell * 0.5 if int(row) % 2 == 1 else 0.0), cell) / cell - 0.5
					var sy := fmod(float(y), cell) / cell - 0.5
					var d := sqrt(sx * sx * 1.5 + sy * sy * 4.0)
					var grain := clampf(1.0 - d * 2.0, 0.0, 1.0)
					v = weave * 0.5 + grain * 0.6
				"stitched":
					# The lapel: dense canvas with rows of stitching along its length (u).
					v = weave * 0.6
					for line in [0.14, 0.28, 0.42, 0.58, 0.72, 0.86]:
						var dl := absf(float(y) / TEX - line) * TEX
						if dl < 1.5:
							v = 0.15 + 0.15 * (0.5 + 0.5 * sin(TAU * x / 5.0))   # a running stitch
				_:
					v = weave
			h.set_pixel(x, y, Color(v, v, v))
	var albedo := Image.create(TEX, TEX, false, Image.FORMAT_RGB8)
	for y in TEX:
		for x in TEX:
			var v := 0.80 + 0.20 * h.get_pixel(x, y).r
			albedo.set_pixel(x, y, Color(v, v, v))
	var normal := h.duplicate()
	normal.convert(Image.FORMAT_RGB8)
	normal.bump_map_to_normal_map(4.0 if kind != "canvas" else 2.5)
	albedo.generate_mipmaps()
	normal.generate_mipmaps()
	var out := [ImageTexture.create_from_image(albedo), ImageTexture.create_from_image(normal)]
	_textures[kind] = out
	return out


static func _cloth_material(kind: String, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tex := _cloth_textures(kind)
	m.albedo_color = tint
	m.albedo_texture = tex[0]
	m.normal_enabled = true
	m.normal_texture = tex[1]
	m.normal_scale = 2.0
	m.roughness = 1.0
	if kind != "stitched":   # the lapel ribbon carries its own UVs, u along the band
		m.uv1_triplanar = true
		m.uv1_world_triplanar = false
		m.uv1_scale = Vector3.ONE * (1.0 / TILE_M)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


func set_belt_color(c: Color) -> void:
	belt_material.albedo_color = c


func set_visible(on: bool) -> void:
	for m in [jacket, trousers, belt, lapel]:
		if m:
			m.visible = on


# ---------------------------------------------------------------- cut

const TORSO := ["Hips", "Spine", "Chest", "UpperChest", "LeftShoulder", "RightShoulder", "Neck"]
## The collar line: the jacket stops here at the neck.
const COLLAR_Y := 1.43
## Trousers reach this far up under the jacket.
const TROUSER_TOP_Y := BELT_Y + 0.03
## The V closes at the sternum; below it the jacket fronts overlap.
const V_BOTTOM_Y := 1.16

## Which bone owns most of each vertex, by name.
func _dominant_bones(arrays: Array) -> PackedStringArray:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / verts.size()
	var skin: Skin = rig.body.skin
	var sk := rig.skeleton
	var bind_name := PackedStringArray()
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		bind_name.append(sk.get_bone_name(bone) if bone >= 0 else skin.get_bind_name(b))
	var out := PackedStringArray()
	out.resize(verts.size())
	for v in verts.size():
		var best := ""
		var best_w := 0.0
		for k in per:
			var w := weights[v * per + k]
			if w > best_w:
				best_w = w
				best = bind_name[bones[v * per + k]]
		out[v] = best
	return out


## Where a rest vertex would have to move to lie inside `piece`: itself when it already does,
## otherwise the nearest point on the piece's edge (a hem, the collar, the sleeve end, the V).
## Triangles that straddle an edge keep their outside vertices moved onto it, so hems come out
## as straight lines instead of following the mesh's triangles. Empty (NAN) when the vertex has
## nothing to do with the piece at all.
func _clamp_to(piece: String, p: Vector3, bone: String) -> Vector3:
	var q := p
	if piece == "jacket":
		if bone == "Head":
			bone = "Neck"
		if bone.ends_with("Hand") or FingerCurl.is_finger_bone(bone):
			bone = ("Left" if bone.begins_with("Left") else "Right") + "LowerArm"
		if bone.ends_with("LowerArm"):
			return _clamp_along(p, bone, SLEEVE_END)
		if bone.ends_with("UpperArm"):
			return p
		if not bone in TORSO:
			return Vector3(NAN, NAN, NAN)
		q.y = clampf(q.y, JACKET_HEM_Y, COLLAR_Y)
		if _in_v(q):
			var half := _v_half(q.y)
			q.x = signf(q.x) * half if q.x != 0.0 else half
			if q.y < V_BOTTOM_Y + 0.001:
				q.y = V_BOTTOM_Y
		return q
	# trousers
	if bone.ends_with("Foot") or bone.ends_with("Toes"):
		bone = ("Left" if bone.begins_with("Left") else "Right") + "LowerLeg"
	if bone.ends_with("LowerLeg"):
		return _clamp_along(p, bone, LEG_END)
	if bone.ends_with("UpperLeg"):
		q.y = maxf(q.y, TROUSER_HEM_Y)
		return q
	if bone == "Hips" or bone == "Spine":
		q.y = clampf(q.y, TROUSER_HEM_Y, TROUSER_TOP_Y)
		return q
	return Vector3(NAN, NAN, NAN)


## Clamps a point to lie no further than `limit` along the bone (0 at the joint, 1 at the child).
func _clamp_along(p: Vector3, bone: String, limit: float) -> Vector3:
	var sk := rig.skeleton
	var i := sk.find_bone(bone)
	var a := sk.get_bone_global_rest(i).origin
	var children := sk.get_bone_children(i)
	if children.is_empty():
		return p
	var b := sk.get_bone_global_rest(children[0]).origin
	var ab := b - a
	var t := (p - a).dot(ab) / maxf(ab.length_squared(), 1e-6)
	if t <= limit:
		return p
	return p - ab * (t - limit)


func _v_half(y: float) -> float:
	return V_HALF_WIDTH * clampf((y - V_BOTTOM_Y) / (V_TOP_Y - V_BOTTOM_Y), 0.0, 1.0)


## The character faces +Z; the opening narrows from the collar bones down to the sternum.
func _in_v(p: Vector3) -> bool:
	if p.z < 0.0 or p.y < V_BOTTOM_Y:
		return false
	return absf(p.x) < _v_half(p.y)


## The band of the jacket that is the collar: LAPEL_WIDTH below the collar line round the
## neck, and LAPEL_WIDTH outside the V's edges down the fronts.
func _in_collar(p: Vector3, bone: String) -> bool:
	if not (bone in TORSO or bone == "Neck" or bone == "Head"):
		return false
	if p.y > COLLAR_Y - LAPEL_WIDTH and Vector2(p.x, p.z).length() < 0.16:
		return true
	if p.z > 0.0 and p.y > V_BOTTOM_Y - 0.02 and p.y <= V_TOP_Y + 0.01:
		var edge := _v_half(p.y)
		return absf(p.x) >= edge - 0.001 and absf(p.x) < edge + LAPEL_WIDTH
	return false


func _offset_for(piece: String, bone: String) -> float:
	if piece == "trousers":
		return TROUSER_OFFSET
	return SLEEVE_OFFSET if bone.ends_with("Arm") else JACKET_OFFSET


# ---------------------------------------------------------------- shells

func _shell(arrays: Array, dominant: PackedStringArray, piece: String, material: Material) -> MeshInstance3D:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var per := bones.size() / verts.size()
	var clamped := PackedVector3Array()
	var inside := PackedByteArray()
	clamped.resize(verts.size()); inside.resize(verts.size())
	for v in verts.size():
		var c := _clamp_to(piece, verts[v], dominant[v])
		clamped[v] = c
		inside[v] = 1 if (not is_nan(c.x) and c.distance_squared_to(verts[v]) < 1e-10) else 0
	# The jacket's collar (eri) is the shell itself along the neck and the V, standing proud of
	# the rest by the band's thickness, in the band's cloth: a rim that follows the body exactly.
	var collar := PackedByteArray()
	collar.resize(verts.size())
	for v in verts.size():
		collar[v] = 1 if (piece == "jacket" and _in_collar(clamped[v], dominant[v])) else 0
	var mesh := ArrayMesh.new()
	for surface in ([0, 1] if piece == "jacket" else [0]):
		var remap := PackedInt32Array()
		remap.resize(verts.size())
		remap.fill(-1)
		var nv := PackedVector3Array()
		var nn := PackedVector3Array()
		var nb := PackedInt32Array()
		var nw := PackedFloat32Array()
		var ni := PackedInt32Array()
		for t in indices.size() / 3:
			var tri := [indices[t * 3], indices[t * 3 + 1], indices[t * 3 + 2]]
			var ins := 0
			var usable := true
			var band := 0
			for v in tri:
				ins += inside[v]
				band += collar[v]
				if is_nan(clamped[v].x):
					usable = false
			if ins == 0 or not usable:
				continue
			# Triangles touching the band belong to it and bevel from the raised band vertices
			# down to the plain ones, so the two surfaces meet without a slit between them.
			if (band >= 1) != (surface == 1):
				continue
			for v in tri:
				if remap[v] < 0:
					remap[v] = nv.size()
					var offset := _offset_for(piece, dominant[v]) + (LAPEL_THICKNESS if collar[v] == 1 else 0.0)
					nv.append(clamped[v] + normals[v] * offset)
					nn.append(normals[v])
					for k in per:
						nb.append(bones[v * per + k])
						nw.append(weights[v * per + k])
				ni.append(remap[v])
		if ni.size() > 0:
			var a := []
			a.resize(Mesh.ARRAY_MAX)
			a[Mesh.ARRAY_VERTEX] = nv
			a[Mesh.ARRAY_NORMAL] = nn
			a[Mesh.ARRAY_BONES] = nb
			a[Mesh.ARRAY_WEIGHTS] = nw
			a[Mesh.ARRAY_INDEX] = ni
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			mesh.surface_set_material(mesh.get_surface_count() - 1, material if surface == 0 else collar_material)
	var mi := MeshInstance3D.new()
	mi.name = "Gi_" + piece
	mi.mesh = mesh
	return mi


# ---------------------------------------------------------------- lapel

const GRID_CELL := 0.05

func _build_grid(arrays: Array) -> void:
	_grid_arrays = arrays
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	_grid.clear()
	for i in verts.size():
		var key := _cell_key(verts[i])
		if not _grid.has(key):
			_grid[key] = PackedInt32Array()
		_grid[key].append(i)


static func _cell_key(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / GRID_CELL), floori(p.y / GRID_CELL), floori(p.z / GRID_CELL))


## Index of the rest vertex nearest to `p` (within about a cell), or -1.
func _nearest(p: Vector3) -> int:
	var verts: PackedVector3Array = _grid_arrays[Mesh.ARRAY_VERTEX]
	var c := _cell_key(p)
	var best := -1
	var best_d := INF
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var key := c + Vector3i(dx, dy, dz)
				if not _grid.has(key):
					continue
				for i in _grid[key]:
					var d := verts[i].distance_squared_to(p)
					if d < best_d:
						best_d = d; best = i
	return best


## The skin surface under a point on the front of the chest: the frontmost vertex near (x, y).
func _front_z(x: float, y: float) -> float:
	var verts: PackedVector3Array = _grid_arrays[Mesh.ARRAY_VERTEX]
	var z := -INF
	for i in verts.size():
		var v := verts[i]
		if v.z > 0.0 and absf(v.x - x) < 0.02 and absf(v.y - y) < 0.015 and v.z > z:
			z = v.z
	return z if z > -INF else 0.1


## Where the jacket's edge runs on one front at height `y`, x for the character's left front
## (mirror for the right): the V above the sternum, crossing over below it.
func _front_edge_x(y: float) -> float:
	return clampf(V_HALF_WIDTH * (y - V_BOTTOM_Y) / (V_TOP_Y - V_BOTTOM_Y), -LAPEL_OVERLAP_X, V_HALF_WIDTH)


## Radius of the body round the neck centre per angle sector at height `y`, for the collar.
func _radius_profile(verts: PackedVector3Array, dominant: PackedStringArray, centre: Vector3, y: float, n: int) -> PackedFloat32Array:
	var radii := PackedFloat32Array(); radii.resize(n); radii.fill(0.0)
	for i in verts.size():
		var v := verts[i]
		if absf(v.y - y) < 0.02 and (dominant.is_empty() or dominant[i] in TORSO or dominant[i] == "Neck" or dominant[i] == "Head"):
			var d := Vector2(v.x - centre.x, v.z - centre.z)
			if d.length() > 0.20:
				continue   # the shoulders proper; the collar lies on the slope inside them
			var k := int(floor(wrapf(d.angle(), 0.0, TAU) / TAU * n)) % n
			radii[k] = maxf(radii[k], d.length())
	for k in n:
		if radii[k] <= 0.0:
			radii[k] = maxf(radii[(k + n - 1) % n], radii[(k + 1) % n])
	return radii


## The lapel band (eri): two ribbons up the fronts, from the belt, crossing below the sternum
## (the character's left on top, as a gi is worn) to the collar bones, and a collar between
## them round the back of the neck that lies on the neck and the slope of the shoulders.
func _lapel(arrays: Array, dominant: PackedStringArray) -> MeshInstance3D:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var steps := 14
	var left: Array = []
	var right: Array = []
	for i in steps + 1:
		# Up to just under the collar rim, which takes over from there round the neck.
		var y := lerpf(BELT_Y + BELT_HEIGHT * 0.5, V_TOP_Y - 0.04, float(i) / steps)
		var x := _front_edge_x(y)
		left.append([Vector3(x, y, _front_z(x, y)), Vector3(1, 0, 0), JACKET_OFFSET + 0.006])
		right.append([Vector3(-x, y, _front_z(-x, y)), Vector3(-1, 0, 0), JACKET_OFFSET + 0.002])
	return _ribbon([left, right], [], arrays)


## Builds the band along `path` and skins every vertex like the skin vertex nearest to it,
## so the band moves with the chest, the shoulders and the neck without any weights of its own.
func _ribbon(paths: Array, rows: Array, arrays: Array) -> MeshInstance3D:
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var per := bones.size() / verts.size()
	var nv := PackedVector3Array(); var nn := PackedVector3Array(); var uv := PackedVector2Array()
	var nb := PackedInt32Array(); var nw := PackedFloat32Array(); var ni := PackedInt32Array()
	for path in paths:
		_ribbon_path(path, nv, nn, uv, ni)
	# The collar surface: quads between rows, u round the neck, v down the band.
	for r in rows.size() - 1:
		var top: Array = rows[r]; var bot: Array = rows[r + 1]
		for i in top.size() - 1:
			var c: Vector3 = (top[i] + bot[i + 1]) * 0.5
			var out := Vector3(c.x, 0.0, c.z).normalized()
			var u0 := float(i) / 3.0; var u1 := float(i + 1) / 3.0
			var v0 := float(r) / (rows.size() - 1); var v1 := float(r + 1) / (rows.size() - 1)
			_rq(nv, nn, uv, ni, [top[i], top[i + 1], bot[i + 1], bot[i]], [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)], out)
	for v in nv:
		var near := _nearest(v)
		if near < 0:
			near = 0
		for k in per:
			nb.append(bones[near * per + k])
			nw.append(weights[near * per + k])
	var mesh := ArrayMesh.new()
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = nv
	a[Mesh.ARRAY_NORMAL] = nn
	a[Mesh.ARRAY_TEX_UV] = uv
	a[Mesh.ARRAY_BONES] = nb
	a[Mesh.ARRAY_WEIGHTS] = nw
	a[Mesh.ARRAY_INDEX] = ni
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	mesh.surface_set_material(0, lapel_material)
	var mi := MeshInstance3D.new()
	mi.name = "Gi_lapel"
	mi.mesh = mesh
	return mi


func _ribbon_path(path: Array, nv: PackedVector3Array, nn: PackedVector3Array, uv: PackedVector2Array, ni: PackedInt32Array) -> void:
	var u := 0.0
	var sections: Array = []
	for i in path.size():
		var c: Vector3 = path[i][0]
		var prev: Vector3 = path[maxi(i - 1, 0)][0]
		var next: Vector3 = path[mini(i + 1, path.size() - 1)][0]
		var t := (next - prev).normalized()
		var radial := Vector3(c.x, 0.0, c.z).normalized()   # out of the torso
		var normal := (radial - t * radial.dot(t)).normalized()
		var side: Vector3 = path[i][1]
		var w := (side - t * side.dot(t)).normalized()
		if w.dot(side) < 0.0:
			w = -w
		var lift: float = path[i][2]
		var inner := c + normal * lift
		var outer := c + w * LAPEL_WIDTH + normal * lift
		if i > 0:
			u += c.distance_to(prev)
		sections.append([inner, outer, normal, u])
	# Faces: top surface, the two long sides, as quads between sections.
	for i in sections.size() - 1:
		var a: Array = sections[i]; var b: Array = sections[i + 1]
		var ua: float = a[3] / 0.10; var ub: float = b[3] / 0.10
		var na: Vector3 = a[2]; var nbn: Vector3 = b[2]
		var a_in_top: Vector3 = a[0] + na * LAPEL_THICKNESS; var a_out_top: Vector3 = a[1] + na * LAPEL_THICKNESS
		var b_in_top: Vector3 = b[0] + nbn * LAPEL_THICKNESS; var b_out_top: Vector3 = b[1] + nbn * LAPEL_THICKNESS
		var w_dir: Vector3 = (a[1] - a[0]).normalized()
		_rq(nv, nn, uv, ni, [a_in_top, b_in_top, b_out_top, a_out_top], [Vector2(ua, 0), Vector2(ub, 0), Vector2(ub, 1), Vector2(ua, 1)], na)
		_rq(nv, nn, uv, ni, [a[0], a_in_top, b_in_top, b[0]], [Vector2(ua, 0), Vector2(ua, 0.1), Vector2(ub, 0.1), Vector2(ub, 0)], -w_dir)
		_rq(nv, nn, uv, ni, [a_out_top, b_out_top, b[1], a[1]], [Vector2(ua, 1), Vector2(ub, 1), Vector2(ub, 0.9), Vector2(ua, 0.9)], w_dir)


## A quad with its own four vertices, wound so that it faces `want` (the outside of the band).
static func _rq(nv: PackedVector3Array, nn: PackedVector3Array, uv: PackedVector2Array, ni: PackedInt32Array, p: Array, t: Array, want: Vector3) -> void:
	var normal: Vector3 = (p[1] - p[0]).cross(p[3] - p[0]).normalized()
	var flip := normal.dot(want) < 0.0
	if flip:
		normal = -normal
	var base := nv.size()
	for k in 4:
		nv.append(p[k]); nn.append(normal); uv.append(t[k])
	if flip:
		ni.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	else:
		ni.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


# ---------------------------------------------------------------- belt

## A band measured round the waist of the rest mesh, a knot in front and two ends hanging.
func _belt(arrays: Array, dominant: PackedStringArray) -> MeshInstance3D:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n := 32
	var centre := Vector3.ZERO
	var count := 0
	# Torso vertices only: the hands hang at waist height in the rest pose.
	for i in verts.size():
		var v := verts[i]
		if absf(v.y - BELT_Y) < BELT_HEIGHT and dominant[i] in TORSO:
			centre += v; count += 1
	centre = centre / maxf(count, 1)
	centre.y = BELT_Y
	var radii := PackedFloat32Array()
	radii.resize(n)
	radii.fill(0.0)
	for i in verts.size():
		var v := verts[i]
		if absf(v.y - BELT_Y) < BELT_HEIGHT * 0.75 and dominant[i] in TORSO:
			var d := Vector2(v.x - centre.x, v.z - centre.z)
			var k := int(floor(wrapf(d.angle(), 0.0, TAU) / TAU * n)) % n
			radii[k] = maxf(radii[k], d.length())
	# Fill sectors that no vertex fell into from their neighbours, then pad for the trousers.
	for k in n:
		if radii[k] <= 0.0:
			radii[k] = maxf(radii[(k + n - 1) % n], radii[(k + 1) % n])
	for k in n:
		radii[k] += JACKET_OFFSET + 0.004   # over the jacket skirt
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hips := _bind_index("Hips")
	var spine := _bind_index("Spine")
	var bind4 := func(w_hips: float) -> void:
		st.set_bones(PackedInt32Array([hips, spine, 0, 0]))
		st.set_weights(PackedFloat32Array([w_hips, 1.0 - w_hips, 0.0, 0.0]))
	var ring := func(y: float, pad: float) -> Array:
		var out := []
		for k in n:
			var ang := TAU * k / n
			out.append(centre + Vector3(cos(ang) * (radii[k] + pad), y - BELT_Y, sin(ang) * (radii[k] + pad)))
		return out
	var top_out: Array = ring.call(BELT_Y + BELT_HEIGHT * 0.5, BELT_THICKNESS)
	var bot_out: Array = ring.call(BELT_Y - BELT_HEIGHT * 0.5, BELT_THICKNESS)
	var top_in: Array = ring.call(BELT_Y + BELT_HEIGHT * 0.5, 0.0)
	var bot_in: Array = ring.call(BELT_Y - BELT_HEIGHT * 0.5, 0.0)
	bind4.call(0.7)
	for k in n:
		var k2 := (k + 1) % n
		_quad(st, bot_out[k], bot_out[k2], top_out[k2], top_out[k])   # outer face
		_quad(st, top_in[k], top_in[k2], bot_in[k2], bot_in[k])       # inner face (back-facing)
		_quad(st, top_out[k], top_out[k2], top_in[k2], top_in[k])     # top
		_quad(st, bot_in[k], bot_in[k2], bot_out[k2], bot_out[k])     # bottom
	# The knot: a box in front, where the two ends cross, and the ends hanging from it.
	bind4.call(1.0)
	var front_r: float = radii[int(n / 4)] + BELT_THICKNESS   # +Z is the front (angle π/2)
	var knot_c := centre + Vector3(0.0, 0.0, front_r + 0.012)
	_box(st, knot_c, Vector3(0.075, 0.05, 0.035))
	for side in [-1.0, 1.0]:
		var hang := Vector3(side * 0.05, -0.15, 0.0)
		var top_c := knot_c + Vector3(side * 0.02, -0.03, -0.004)
		_strap(st, top_c, top_c + hang, 0.04, 0.008)
	st.generate_normals()
	st.set_material(belt_material)
	var mi := MeshInstance3D.new()
	mi.name = "Gi_belt"
	mi.mesh = st.commit()
	return mi


func _bind_index(bone_name: String) -> int:
	var skin: Skin = rig.body.skin
	var idx := rig.skeleton.find_bone(bone_name)
	for b in skin.get_bind_count():
		if skin.get_bind_bone(b) == idx or skin.get_bind_name(b) == bone_name:
			return b
	return 0


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)


static func _box(st: SurfaceTool, c: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var p := []
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				p.append(c + Vector3(sx * h.x, sy * h.y, sz * h.z))
	# p index = sx*4 + sy*2 + sz with -1 -> 0
	_quad(st, p[1], p[5], p[7], p[3])   # +z
	_quad(st, p[4], p[0], p[2], p[6])   # -z
	_quad(st, p[5], p[4], p[6], p[7])   # +x
	_quad(st, p[0], p[1], p[3], p[2])   # -x
	_quad(st, p[3], p[7], p[6], p[2])   # +y
	_quad(st, p[0], p[4], p[5], p[1])   # -y


## A flat strap from `a` to `b`, `width` across x, `thick` along z.
static func _strap(st: SurfaceTool, a: Vector3, b: Vector3, width: float, thick: float) -> void:
	var dir := (b - a).normalized()
	var across := Vector3(1, 0, 0) * width * 0.5
	var out := dir.cross(Vector3(1, 0, 0)).normalized() * thick * 0.5
	if out.z < 0.0:
		out = -out
	var a0 := a - across + out; var a1 := a + across + out; var a2 := a + across - out; var a3 := a - across - out
	var b0 := b - across + out; var b1 := b + across + out; var b2 := b + across - out; var b3 := b - across - out
	_quad(st, a0, a1, b1, b0)   # front
	_quad(st, a2, a3, b3, b2)   # back
	_quad(st, a1, a2, b2, b1)   # side
	_quad(st, a3, a0, b0, b3)   # side
	_quad(st, b0, b1, b2, b3)   # end
