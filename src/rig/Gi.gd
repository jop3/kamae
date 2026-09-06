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
const SLEEVE_OFFSET := 0.030
const TROUSER_OFFSET := 0.014
## Rest-pose heights, metres, on this mannequin (hips joint at 0.91, waist just above it).
const BELT_Y := 0.985
const BELT_HEIGHT := 0.045
const BELT_THICKNESS := 0.010
const JACKET_HEM_Y := 0.76
const TROUSER_HEM_Y := 0.15
## The sleeve ends this far along the forearm (elbow 0 → wrist 1); the trouser leg this far
## along the shin (knee 0 → ankle 1).
const SLEEVE_END := 0.62
const LEG_END := 0.82
## The jacket's V: half-width of the opening at the collar bone, closing at the belt.
const V_TOP_Y := 1.40
const V_HALF_WIDTH := 0.075

var rig: CharacterRig
var jacket: MeshInstance3D
var trousers: MeshInstance3D
var belt: MeshInstance3D
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
	var body: MeshInstance3D = rig.body
	var arrays: Array = body.mesh.surface_get_arrays(0)
	var dominant := _dominant_bones(arrays)
	jacket = _shell(arrays, dominant, "jacket", cloth_material)
	trousers = _shell(arrays, dominant, "trousers", trouser_material)
	belt = _belt(arrays, dominant)
	for m in [jacket, trousers, belt]:
		m.skin = body.skin
		m.cast_shadow = body.cast_shadow
		rig.skeleton.add_child(m)


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
			if kind == "sashiko":
				# Grains on a diamond lattice, 16 mm across, staggered every other row.
				var cell := TEX / 3.2   # about 25 mm
				var row := floorf(y / cell)
				var sx := fmod(x + (cell * 0.5 if int(row) % 2 == 1 else 0.0), cell) / cell - 0.5
				var sy := fmod(float(y), cell) / cell - 0.5
				var d := sqrt(sx * sx * 1.2 + sy * sy * 5.0)
				var grain := clampf(1.0 - d * 2.2, 0.0, 1.0)
				v = weave * 0.5 + grain * 0.7
			else:
				v = weave
			h.set_pixel(x, y, Color(v, v, v))
	var albedo := Image.create(TEX, TEX, false, Image.FORMAT_RGB8)
	for y in TEX:
		for x in TEX:
			var v := 0.74 + 0.26 * h.get_pixel(x, y).r
			albedo.set_pixel(x, y, Color(v, v, v))
	var normal := h.duplicate()
	normal.convert(Image.FORMAT_RGB8)
	normal.bump_map_to_normal_map(5.0 if kind == "sashiko" else 2.5)
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
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3.ONE * (1.0 / TILE_M)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


func set_belt_color(c: Color) -> void:
	belt_material.albedo_color = c


func set_visible(on: bool) -> void:
	for m in [jacket, trousers, belt]:
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
		for v in tri:
			ins += inside[v]
			if is_nan(clamped[v].x):
				usable = false
		if ins == 0 or not usable:
			continue
		for v in tri:
			if remap[v] < 0:
				remap[v] = nv.size()
				nv.append(clamped[v] + normals[v] * _offset_for(piece, dominant[v]))
				nn.append(normals[v])
				for k in per:
					nb.append(bones[v * per + k])
					nw.append(weights[v * per + k])
			ni.append(remap[v])
	var mesh := ArrayMesh.new()
	if ni.size() > 0:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = nv
		a[Mesh.ARRAY_NORMAL] = nn
		a[Mesh.ARRAY_BONES] = nb
		a[Mesh.ARRAY_WEIGHTS] = nw
		a[Mesh.ARRAY_INDEX] = ni
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.name = "Gi_" + piece
	mi.mesh = mesh
	return mi


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
