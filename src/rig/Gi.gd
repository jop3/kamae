class_name Gi
extends Node
## A white keikogi built at runtime from the mannequin itself (spec §7.1, M9): the body mesh is
## pushed out along its normals into a loose shell, cut into a jacket and trousers, and skinned
## with the body's own weights, so it follows every pose without any extra rigging. The belt is
## a ring measured round the waist, with a knot and two hanging ends, in the character's own
## colour as a second identification cue. Hems, collar, sleeve ends and the V are straight
## lines: triangles across an edge are kept with their outside vertices moved onto it. The black
## hakama is built here too, on request and toggled on its own (see the hakama section below).

const WHITE := Color(0.90, 0.89, 0.85)
## How far the cloth stands off the skin, metres. The jacket is the loose one.
const JACKET_OFFSET := 0.022
const SLEEVE_OFFSET := 0.040
const TROUSER_OFFSET := 0.024
## Rest-pose heights, metres, on this mannequin (hips joint at 0.91, waist just above it).
const BELT_Y := 0.985
const BELT_HEIGHT := 0.045
const BELT_THICKNESS := 0.006
const JACKET_HEM_Y := 0.74
const TROUSER_HEM_Y := 0.15
## The sleeve ends this far along the forearm (elbow 0 → wrist 1); the trouser leg this far
## along the shin (knee 0 → ankle 1).
const SLEEVE_END := 0.55
const LEG_END := 0.82
## The jacket's V: half-width of the opening at the collar bone, closing at the belt.
const V_TOP_Y := 1.40
const V_HALF_WIDTH := 0.060
## The lapel band (eri): a thick stitched strip along both fronts and round the neck. The
## fronts overlap below the sternum, the character's left over the right as a gi is worn.
const LAPEL_WIDTH := 0.060
const LAPEL_THICKNESS := 0.010
const LAPEL_OVERLAP_X := 0.075

var rig: CharacterRig
var jacket: MeshInstance3D
var trousers: MeshInstance3D
var belt: MeshInstance3D
## The jacket below the belt, worn outside the trousers (see _skirt).
var skirt: MeshInstance3D
var lapel: MeshInstance3D
var lapel_material: StandardMaterial3D
var collar_material: StandardMaterial3D
## Body vertices bucketed by 5 cm cell, for finding the skin under a point (see _nearest).
var _grid: Dictionary = {}
var _grid_arrays: Array = []
var cloth_material: StandardMaterial3D
var trouser_material: StandardMaterial3D
var belt_material: StandardMaterial3D
## The black hakama (both legs, waist band and koshi-ita in one mesh) and the belt's knot shown
## in front of it; see _build_hakama.
var hakama: MeshInstance3D
var hakama_knot: MeshInstance3D
var hakama_material: StandardMaterial3D
## What the hakama is drawn with: hakama_material's look, with a hem that rests on the mat
## (resting_on_mat).
var hakama_shader_material: ShaderMaterial
var _dressed := true
var _hakama_on := false
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
	_covered = PackedByteArray()
	_covered.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	jacket = _shell(arrays, dominant, "jacket", cloth_material)
	trousers = _shell(arrays, dominant, "trousers", trouser_material)
	_bare_mesh = body.mesh
	_covered_mesh = _without_covered_skin(arrays, body.mesh)
	skirt = _skirt(arrays, dominant)
	belt = _belt(arrays, dominant)
	lapel = _lapel(arrays, dominant)
	for m in [jacket, trousers, skirt, belt, lapel]:
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
	# Half the depth the first gi had: at full strength every rice grain of the sashiko
	# caught the light and a close-up read as bubble wrap rather than cloth.
	m.normal_scale = 0.8 if kind == "sashiko" else 1.2
	m.roughness = 1.0
	if kind != "stitched":   # the lapel ribbon carries its own UVs, u along the band
		m.uv1_triplanar = true
		m.uv1_world_triplanar = false
		m.uv1_scale = Vector3.ONE * (1.0 / TILE_M)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


## The shader `resting_on_mat` draws with: StandardMaterial3D's object-space triplanar cloth
## (albedo and normal map, vertex colour as albedo), plus one thing a StandardMaterial3D cannot
## do — a vertex that the skinning puts under the mat is put on it. Without cloth simulation a
## hakama's hem follows the shin, so in a deep stance, kneeling or getting up from a fall the
## back of the hem went down through the tatami (11-14 cm in the technique videos); cloth that
## meets the mat lies on it. The shadow pass uses the same vertex function.
const RESTING_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec4 albedo : source_color;
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_normal : hint_roughness_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale;
uniform float roughness : hint_range(0.0, 1.0);
uniform vec3 uv1_scale;
uniform float mat_y = 0.0;
uniform float lift = 0.002;
varying vec3 uv1_triplanar_pos;
varying vec3 uv1_power_normal;

void vertex() {
	uv1_power_normal = abs(NORMAL);
	uv1_power_normal /= dot(uv1_power_normal, vec3(1.0));
	uv1_triplanar_pos = VERTEX * uv1_scale * vec3(1.0, -1.0, 1.0);
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	if (world.y < mat_y + lift) {
		world.y = mat_y + lift;
		VERTEX = (inverse(MODEL_MATRIX) * world).xyz;
	}
}

vec4 triplanar_texture(sampler2D p_sampler, vec3 p_weights, vec3 p_pos) {
	vec4 samp = vec4(0.0);
	samp += texture(p_sampler, p_pos.xy) * p_weights.z;
	samp += texture(p_sampler, p_pos.xz) * p_weights.y;
	samp += texture(p_sampler, p_pos.zy * vec2(-1.0, 1.0)) * p_weights.x;
	return samp;
}

void fragment() {
	vec4 albedo_tex = triplanar_texture(texture_albedo, uv1_power_normal, uv1_triplanar_pos) * COLOR;
	ALBEDO = albedo.rgb * albedo_tex.rgb;
	ROUGHNESS = roughness;
	SPECULAR = 0.5;
	NORMAL_MAP = triplanar_texture(texture_normal, uv1_power_normal, uv1_triplanar_pos).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
}
"""
static var _resting_shader: Shader


## `m` (a cloth material from _cloth_material, triplanar) as a ShaderMaterial whose vertices stay
## on or above the mat.
static func resting_on_mat(m: StandardMaterial3D) -> ShaderMaterial:
	if _resting_shader == null:
		_resting_shader = Shader.new()
		_resting_shader.code = RESTING_SHADER
	var out := ShaderMaterial.new()
	out.shader = _resting_shader
	out.set_shader_parameter("albedo", m.albedo_color)
	out.set_shader_parameter("texture_albedo", m.albedo_texture)
	out.set_shader_parameter("texture_normal", m.normal_texture)
	out.set_shader_parameter("normal_scale", m.normal_scale)
	out.set_shader_parameter("roughness", m.roughness)
	out.set_shader_parameter("uv1_scale", m.uv1_scale)
	out.set_shader_parameter("mat_y", Ukemi.MAT_Y)
	return out


func set_belt_color(c: Color) -> void:
	belt_material.albedo_color = c


func set_visible(on: bool) -> void:
	_dressed = on
	_apply_visibility()


## The hakama is worn with or without the gi and toggled on its own; built the first time.
func set_hakama_visible(on: bool) -> void:
	_hakama_on = on
	if on and hakama == null:
		_build_hakama()
	_apply_visibility()


## The belt is under the hakama when both are worn, so it is hidden rather than left to show
## through the cloth; its knot stays out in front as the colour cue. The trousers stay on: they
## are what shows through the side openings and under a lifted hem, as on a real figure.
func _apply_visibility() -> void:
	for m in [jacket, lapel, trousers]:
		if m:
			m.visible = _dressed
	if rig and _covered_mesh:
		rig.body.mesh = _covered_mesh if _dressed else _bare_mesh
	if belt:
		belt.visible = _dressed and not _hakama_on
	if skirt:   # under a hakama the jacket is tucked in, and the hakama hides it
		skirt.visible = _dressed and not _hakama_on
	if hakama:
		hakama.visible = _hakama_on
		hakama_knot.visible = _hakama_on and _dressed
	# What shows of the trousers under a hakama is seen through its side openings, inside the
	# cloth, where no light reaches; lit like the jacket it read as a white hole in the hakama.
	if trouser_material:
		trouser_material.albedo_color = WHITE * Color(0.38, 0.38, 0.40) if _hakama_on else WHITE


# ---------------------------------------------------------------- cut

const TORSO := ["Hips", "Spine", "Chest", "UpperChest", "LeftShoulder", "RightShoulder", "Neck"]
## The collar line: the jacket stops here at the neck.
const COLLAR_Y := 1.43
## Trousers reach this far up under the jacket.
const TROUSER_TOP_Y := BELT_Y + 0.03
## The V closes at the sternum; below it the jacket fronts overlap.
const V_BOTTOM_Y := 1.20

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


const DRAPE_SECTORS := 32
const DRAPE_BIN := 0.02
const DRAPE_AXIS_Z := 0.0
## How fast hanging cloth may narrow below a wide point, metres of radius per metre of height.
const DRAPE_TAPER := 0.35
## Below the belt the jacket's skirt hangs free of the body, widening a little toward the hem.
const SKIRT_FLARE := 0.0
## Above this the jacket narrows to the neck and is not draped; below it the trousers are legs.
const DRAPE_TOP_Y := 1.30
## The back of the jacket hangs from higher up, from the collar: a gi's back is one flat panel from
## the shoulders down, not a back with its shoulder blades. (The front and sides stop at
## DRAPE_TOP_Y, where the chest meets the shoulders and the arms hang beside the body.)
const DRAPE_BACK_TOP_Y := 1.40
const DRAPE_BOTTOM_Y := 0.70

## Per shell vertex on the torso (jacket) or hips (trousers): its draped rest position, on a
## radius no smaller than the body's widest radius in the same direction anywhere above it
## (up to the chest), plus the cloth offset. Vertices that already stand outside are left.
func _drape(piece: String, verts: PackedVector3Array, dominant: PackedStringArray, clamped: PackedVector3Array) -> Dictionary:
	var out := {}
	var draped_bones := ["Hips", "Spine", "Chest", "UpperChest", "LeftUpperLeg", "RightUpperLeg"] if piece == "jacket" else ["Hips"]
	var n := DRAPE_SECTORS
	var bins := int(ceil((DRAPE_BACK_TOP_Y - DRAPE_BOTTOM_Y) / DRAPE_BIN)) + 1
	var profile: Array = []
	for b in bins:
		var row := PackedFloat32Array(); row.resize(n); row.fill(0.0)
		profile.append(row)
	for i in verts.size():
		var v := verts[i]
		if v.y < DRAPE_BOTTOM_Y or v.y > DRAPE_BACK_TOP_Y or not (dominant[i] in TORSO):
			continue
		var d := Vector2(v.x, v.z - DRAPE_AXIS_Z)
		var k := int(floor(wrapf(d.angle(), 0.0, TAU) / TAU * n)) % n
		var b := int((v.y - DRAPE_BOTTOM_Y) / DRAPE_BIN)
		profile[b][k] = maxf(profile[b][k], d.length())
	# Hang: each bin takes the widest of itself and the bin above less a taper, so the cloth
	# falls from the chest and hips but narrows slowly rather than dropping as a barrel; at the
	# belt it is cinched to the body. Then smooth round.
	var belt_bin := int((BELT_Y - DRAPE_BOTTOM_Y) / DRAPE_BIN)
	for b in range(bins - 2, -1, -1):
		var y := DRAPE_BOTTOM_Y + b * DRAPE_BIN
		var cinch := absf(y - BELT_Y) < BELT_HEIGHT * 0.5 + 0.01
		for k in n:
			if piece == "jacket" and y < BELT_Y - BELT_HEIGHT * 0.5:
				# The skirt: a loose tube hanging from the belt, not the shape of the hips.
				profile[b][k] = maxf(profile[b][k], profile[belt_bin][k] + SKIRT_FLARE * (BELT_Y - y))
			elif not cinch:
				profile[b][k] = maxf(profile[b][k], profile[b + 1][k] - DRAPE_TAPER * DRAPE_BIN)
	for b in bins:
		var row: PackedFloat32Array = _hull_profile(profile[b])
		var smooth := PackedFloat32Array(); smooth.resize(n)
		for k in n:
			smooth[k] = (row[(k + n - 1) % n] + row[k] * 2.0 + row[(k + 1) % n]) / 4.0
		profile[b] = smooth
	for i in verts.size():
		var p := clamped[i]
		if is_nan(p.x) or p.y < DRAPE_BOTTOM_Y or not (dominant[i] in draped_bones or (piece == "jacket" and dominant[i].ends_with("Shoulder"))):
			continue
		# Above the chest only the back hangs: well behind the axis and inside the shoulders.
		var back := p.z < DRAPE_AXIS_Z - 0.02 and absf(p.x) < 0.16
		if p.y > (DRAPE_BACK_TOP_Y if back else DRAPE_TOP_Y) or (dominant[i].ends_with("Shoulder") and not back):
			continue
		var d := Vector2(p.x, p.z - DRAPE_AXIS_Z)
		if d.length() < 1e-4:
			continue
		var k := int(floor(wrapf(d.angle(), 0.0, TAU) / TAU * n)) % n
		var b := int((p.y - DRAPE_BOTTOM_Y) / DRAPE_BIN)
		var want: float = profile[b][k] + _offset_for(piece, dominant[i])
		if d.length() < want:
			var dir := d.normalized() * want
			out[i] = Vector3(dir.x, p.y, DRAPE_AXIS_Z + dir.y)
	return out


## Cloth is not skin pushed out: cotton this heavy lies on the high points of the body and spans
## the hollows between them. The shell as first made — every vertex pushed out along its normal —
## traced each muscle of the mannequin 2–4 cm out, which made a balloon of every shoulder, chest
## and upper arm. So the shell is smoothed over the mesh (Laplacian, positions welded across the
## UV seams) while held at least SHELL_GAP off the skin under it: where the body bulges the cloth
## rests near it, where it dips the cloth bridges over. Hems, cuffs, the collar band and the
## draped front and back (which already hang) stay where they were. The normals are taken from
## the smoothed surface, or the light would still draw the muscles on it.
## Returns {body vertex: [position, normal]} for the vertices it moved.
const SHELL_SMOOTHING := 80
## The jacket only: the trousers are already plain tubes round the legs, and smoothed they
## bridged out past the hakama's side openings at the hip.
const SHELL_GAP := {"jacket": 0.010, "sleeve": 0.022}


func _smoothed_shell(piece: String, verts: PackedVector3Array, normals: PackedVector3Array,
		indices: PackedInt32Array, dominant: PackedStringArray, clamped: PackedVector3Array,
		inside: PackedByteArray, draped: Dictionary, collar: PackedByteArray) -> Dictionary:
	# Welded: one point per position, so the two sides of a UV seam move together.
	var canon := PackedInt32Array(); canon.resize(verts.size()); canon.fill(-1)
	var key_to := {}
	var used := PackedByteArray(); used.resize(verts.size())
	for t in indices.size() / 3:
		var ins := 0
		var usable := true
		for k in 3:
			var v := indices[t * 3 + k]
			ins += inside[v]
			if is_nan(clamped[v].x):
				usable = false
		if ins == 0 or not usable:
			continue
		for k in 3:
			used[indices[t * 3 + k]] = 1
	var pts: Array[Vector3] = []
	var body: Array[Vector3] = []
	var nrm: Array[Vector3] = []
	var gap := PackedFloat32Array()
	var axis: Array[Vector3] = []
	var radius := PackedFloat32Array()
	var fixed := PackedByteArray()
	var members: Array = []
	for v in verts.size():
		if used[v] == 0:
			continue
		var key := Vector3i((verts[v] * 10000.0).round())
		var c: int = key_to.get(key, -1)
		if c < 0:
			c = pts.size()
			key_to[key] = c
			var start: Vector3 = draped[v] if draped.has(v) else clamped[v] + normals[v] * _offset_for(piece, dominant[v])
			var sleeve := piece == "jacket" and (dominant[v].ends_with("Arm") or dominant[v].ends_with("Hand"))
			var cone := _sleeve_cone(clamped[v], dominant[v]) if sleeve else []
			if not cone.is_empty():
				var out_dir: Vector3 = clamped[v] - (cone[0] as Vector3)
				start = (cone[0] as Vector3) + out_dir.normalized() * maxf(out_dir.length() + SLEEVE_MIN_GAP, float(cone[1]))
			pts.append(start); body.append(clamped[v]); nrm.append(normals[v])
			axis.append(cone[0] if not cone.is_empty() else Vector3.INF)
			radius.append(maxf((clamped[v] - (cone[0] as Vector3)).length() + SLEEVE_MIN_GAP, float(cone[1])) if not cone.is_empty() else 0.0)
			gap.append(SHELL_GAP["sleeve" if sleeve else piece])
			fixed.append(1 if (draped.has(v) or inside[v] == 0 or collar[v] == 1) else 0)
			members.append([v])
		else:
			(members[c] as Array).append(v)
			if draped.has(v) or inside[v] == 0 or collar[v] == 1:
				fixed[c] = 1
		canon[v] = c
	var n := pts.size()
	var nbrs: Array = []
	nbrs.resize(n)
	for i in n:
		nbrs[i] = []   # plain Arrays: a PackedInt32Array read out of `nbrs` is a copy
	var faces := []
	for t in indices.size() / 3:
		var a := canon[indices[t * 3]]; var b := canon[indices[t * 3 + 1]]; var c := canon[indices[t * 3 + 2]]
		if a < 0 or b < 0 or c < 0 or a == b or b == c or a == c:
			continue
		faces.append([a, b, c])
		for e in [[a, b], [b, c], [c, a]]:
			if not (nbrs[e[0]] as Array).has(e[1]):
				(nbrs[e[0]] as Array).append(e[1])
				(nbrs[e[1]] as Array).append(e[0])
	for _it in SHELL_SMOOTHING:
		var next := pts.duplicate()
		for i in n:
			var nb: Array = nbrs[i]
			if fixed[i] == 1 or nb.is_empty():
				continue
			var avg := Vector3.ZERO
			for j in nb:
				avg += pts[j]
			avg /= nb.size()
			var p := pts[i].lerp(avg, 0.6)
			# Never closer to the skin than the gap: the cloth rests on the high points. A sleeve
			# keeps its cone's width round the arm's axis.
			if axis[i] != Vector3.INF:
				var r := (p - axis[i]).length()
				if r < radius[i] and r > 1e-6:
					p = axis[i] + (p - axis[i]) / r * radius[i]
			else:
				var off := (p - body[i]).dot(nrm[i])
				if off < gap[i]:
					p += nrm[i] * (gap[i] - off)
			next[i] = p
		pts = next
	# Normals of the smoothed surface, turned to face the way the skin's did.
	var acc: Array[Vector3] = []
	acc.resize(n)
	acc.fill(Vector3.ZERO)
	for f: Array in faces:
		var fn: Vector3 = (pts[f[1]] - pts[f[0]]).cross(pts[f[2]] - pts[f[0]])
		for i in f:
			acc[i] += fn
	var out := {}
	for i in n:
		if fixed[i] == 1:
			continue
		var nn := acc[i].normalized() if acc[i].length() > 1e-9 else nrm[i]
		if nn.dot(nrm[i]) < 0.0:
			nn = -nn
		for v in members[i]:
			out[v] = [pts[i], nn]
	return out


## A keikogi sleeve is a wide straight tube, a little narrower at the cuff, that hangs off the
## arm rather than tracing the biceps: its radius round the bone, metres, at the shoulder and the
## elbow of the upper arm, and at the elbow and the cuff of the forearm; never closer to the arm
## than SLEEVE_MIN_GAP.
const SLEEVE_RADII := [0.080, 0.072, 0.068, 0.058]
const SLEEVE_MIN_GAP := 0.012


## The point on the arm's axis nearest `p` and the sleeve's radius there, for a vertex owned by
## `bone`; empty when it is not an arm's.
func _sleeve_cone(p: Vector3, bone: String) -> Array:
	if bone.ends_with("Hand") or FingerCurl.is_finger_bone(bone):
		bone = ("Left" if bone.begins_with("Left") else "Right") + "LowerArm"
	if not (bone.ends_with("UpperArm") or bone.ends_with("LowerArm")):
		return []
	var sk := rig.skeleton
	var i := sk.find_bone(bone)
	var kids := sk.get_bone_children(i)
	if i < 0 or kids.is_empty():
		return []
	var a := sk.get_bone_global_rest(i).origin
	var b := sk.get_bone_global_rest(kids[0]).origin
	var t := clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 1e-9), 0.0, 1.0)
	var r: float = lerpf(SLEEVE_RADII[0], SLEEVE_RADII[1], t) if bone.ends_with("UpperArm") \
		else lerpf(SLEEVE_RADII[2], SLEEVE_RADII[3], clampf(t / SLEEVE_END, 0.0, 1.0))
	return [a.lerp(b, t), r]


## A height slice of the drape as cloth wraps it: the convex hull of the body's outline. The
## outline per sector traced the spine's groove, the lats and the shoulder blades, and the back
## of the jacket came out as a bodybuilder's back in a leotard; cloth stretched round a body
## spans every hollow of it. `row` is a radius per sector round the drape's axis.
static func _hull_profile(row: PackedFloat32Array) -> PackedFloat32Array:
	var n := row.size()
	var pts: Array[Vector2] = []
	for k in n:
		if row[k] > 0.0:
			var a := (float(k) + 0.5) / n * TAU
			pts.append(Vector2(cos(a), sin(a)) * row[k])
	if pts.size() < 3:
		return row
	pts.sort_custom(func(p, q): return p.x < q.x or (p.x == q.x and p.y < q.y))
	var hull: Array[Vector2] = []
	for pass_ in 2:   # monotone chain: lower then upper half
		var start := hull.size()
		var seq := pts if pass_ == 0 else pts.duplicate()
		if pass_ == 1:
			seq.reverse()
		for p in seq:
			while hull.size() >= start + 2 and (hull[-1] - hull[-2]).cross(p - hull[-2]) <= 0.0:
				hull.pop_back()
			hull.append(p)
		hull.pop_back()
	var out := row.duplicate()
	for k in n:
		if row[k] <= 0.0:
			continue
		var a := (float(k) + 0.5) / n * TAU
		var dir := Vector2(cos(a), sin(a))
		for i in hull.size():
			var p: Vector2 = hull[i]
			var q: Vector2 = hull[(i + 1) % hull.size()]
			var e := q - p
			var den := dir.cross(e)
			if absf(den) < 1e-9:
				continue
			var t := p.cross(e) / den        # distance along the ray
			var u := p.cross(dir) / den      # where on the edge
			if t > 0.0 and u >= -1e-6 and u <= 1.0 + 1e-6:
				out[k] = maxf(row[k], t)
				break
	return out


func _offset_for(piece: String, bone: String) -> float:
	if piece == "trousers":
		return TROUSER_OFFSET
	return SLEEVE_OFFSET if bone.ends_with("Arm") else JACKET_OFFSET


# ---------------------------------------------------------------- the skin under the cloth

## Body vertices inside the jacket or the trousers (set while the shells are cut).
var _covered := PackedByteArray()
## The body as imported, and the same body without the skin the gi hides (see below).
var _bare_mesh: Mesh
var _covered_mesh: ArrayMesh
## How far back from the cloth's edges, metres, the skin is still drawn: what shows through a
## sleeve end, the V, past the lapels or under a hem is skin, not the inside of the cloth.
const COVER_MARGIN := 0.07


## The body mesh without the triangles the gi covers, worn while the gi is. A shell skinned with
## the body's own weights keeps its distance from the skin only while the bones it blends turn
## together: at a raised shoulder the upper arm turns 150° from the chest, the blend of the two
## pulls the offset in, and the skin came out through the jacket at the back of the shoulder and
## in the armpit. A person in a gi has no skin to show there, and now neither has the figure.
## Only the index list changes: the vertices, and everything that reads them (the checks, the
## skin radii, the shells themselves), are the imported body's.
func _without_covered_skin(arrays: Array, source: Mesh) -> ArrayMesh:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# Hidden: covered skin further than COVER_MARGIN from any skin the cloth leaves bare.
	var bare := {}
	for v in verts.size():
		if _covered[v] == 0:
			var key := Vector3i((verts[v] / COVER_MARGIN).floor())
			if not bare.has(key):
				bare[key] = PackedVector3Array()
			(bare[key] as PackedVector3Array).append(verts[v])
	var keep := PackedByteArray()
	keep.resize(verts.size())
	for v in verts.size():
		if _covered[v] == 0:
			continue
		var cell := Vector3i((verts[v] / COVER_MARGIN).floor())
		var near := false
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					for p: Vector3 in bare.get(cell + Vector3i(dx, dy, dz), PackedVector3Array()):
						if p.distance_squared_to(verts[v]) < COVER_MARGIN * COVER_MARGIN:
							near = true
							break
					if near: break
				if near: break
			if near: break
		keep[v] = 0 if near else 1
	var kept := PackedInt32Array()
	for t in indices.size() / 3:
		var a := indices[t * 3]; var b := indices[t * 3 + 1]; var c := indices[t * 3 + 2]
		if keep[a] == 1 and keep[b] == 1 and keep[c] == 1:
			continue
		kept.append(a); kept.append(b); kept.append(c)
	var out_arrays := arrays.duplicate()
	out_arrays[Mesh.ARRAY_INDEX] = kept
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
	mesh.surface_set_material(0, source.surface_get_material(0))
	mesh.resource_name = String(source.resource_name) + "_under_gi"
	return mesh


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
		if inside[v] == 1:
			_covered[v] = 1
	# Loose cloth hangs from the widest point above it: the shell's radius at any height on the
	# torso and hips is at least the body's widest radius above, so the front falls straight
	# from the chest and the hips hide the crotch instead of the cloth tracing every curve.
	var draped := _drape(piece, verts, dominant, clamped)
	# The jacket's collar (eri) is the shell itself along the neck and the V, standing proud of
	# the rest by the band's thickness, in the band's cloth: a rim that follows the body exactly.
	var collar := PackedByteArray()
	collar.resize(verts.size())
	for v in verts.size():
		collar[v] = 1 if (piece == "jacket" and _in_collar(clamped[v], dominant[v])) else 0
	var smooth := _smoothed_shell(piece, verts, normals, indices, dominant, clamped, inside, draped, collar) \
		if piece == "jacket" else {}
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
					if draped.has(v):
						var d: Vector3 = draped[v]   # already stands off the body; keep the band's extra
						nv.append(d + normals[v] * (LAPEL_THICKNESS if collar[v] == 1 else 0.0))
						var radial := Vector3(d.x, 0.0, d.z - DRAPE_AXIS_Z).normalized()
						nn.append((normals[v] * 0.35 + radial).normalized())
					elif smooth.has(v):
						var sm: Array = smooth[v]
						nv.append((sm[0] as Vector3) + (sm[1] as Vector3) * (LAPEL_THICKNESS if collar[v] == 1 else 0.0))
						nn.append(sm[1])
					else:
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


# ---------------------------------------------------------------- skirt

## The jacket's skirt: from under the belt to JACKET_HEM_Y, outside the trousers. A gi jacket is
## never tucked into the trousers; it hangs over them to the top of the thighs. The shell cut
## from the body could not do that: the seat and the tops of the thighs are the legs' vertices,
## so the jacket stopped at the hip joint and the trousers, cut from those vertices, covered the
## hips over it. This is a tube of its own, as wide all round as the body there (trunk and
## thighs) plus the trousers and SKIRT_GAP, falling straight from the belt and hanging rather
## than narrowing, and it hands over from the hips to each thigh going down, the front sooner
## than the back, so a thigh raised in a step or in seiza carries the cloth over it.
const SKIRT_SECTORS := 48
const SKIRT_RINGS := 14
const SKIRT_GAP := 0.012
## Where it starts, under the belt.
const SKIRT_TOP_Y := BELT_Y + 0.012
## How fast the skirt may narrow going down, metres of radius per metre (it hangs).
const SKIRT_TAPER := 0.25
## How much of a vertex follows its thigh at the hem: front, side, back.
const SKIRT_TO_LEG := [0.85, 0.6, 0.45]


func _skirt(arrays: Array, dominant: PackedStringArray) -> MeshInstance3D:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n := SKIRT_SECTORS
	var centre_z := 0.02
	# The body's radius per sector and ring: trunk and thighs, never the arms hanging beside.
	var ys := PackedFloat32Array()
	for j in SKIRT_RINGS + 1:
		ys.append(lerpf(SKIRT_TOP_Y, JACKET_HEM_Y, float(j) / SKIRT_RINGS))
	var radius: Array = []
	for j in ys.size():
		var row := PackedFloat32Array(); row.resize(n); row.fill(0.0)
		radius.append(row)
	for i in verts.size():
		var d: String = dominant[i]
		if not (d in TORSO or d.ends_with("UpperLeg")):
			continue
		var v := verts[i]
		if v.y > SKIRT_TOP_Y + 0.03 or v.y < JACKET_HEM_Y - 0.03:
			continue
		var flat := Vector2(v.x, v.z - centre_z)
		var k := int(floor(wrapf(flat.angle(), 0.0, TAU) / TAU * n)) % n
		for j in ys.size():
			if absf(v.y - ys[j]) < 0.03:
				radius[j][k] = maxf(radius[j][k], flat.length())
	for j in ys.size():
		var row: PackedFloat32Array = radius[j]
		# A sector no vertex fell into (between the thighs, low down) takes its neighbours'.
		for _pass in 4:
			for k in n:
				if row[k] <= 0.0:
					row[k] = maxf(row[(k + n - 1) % n], row[(k + 1) % n])
		var smooth := PackedFloat32Array(); smooth.resize(n)
		for k in n:
			smooth[k] = (row[(k + n - 2) % n] + row[(k + n - 1) % n] * 2.0 + row[k] * 3.0 + row[(k + 1) % n] * 2.0 + row[(k + 2) % n]) / 9.0
			# Close over the trousers at the waist, where the belt holds it, and the full gap
			# from a hand's breadth down.
			smooth[k] = maxf(smooth[k], row[k]) + TROUSER_OFFSET + lerpf(0.004, SKIRT_GAP, clampf((SKIRT_TOP_Y - ys[j]) / 0.06, 0.0, 1.0))
		if j > 0:   # cloth hangs: it narrows slowly below a wide point
			for k in n:
				smooth[k] = maxf(smooth[k], (radius[j - 1] as PackedFloat32Array)[k] - SKIRT_TAPER * (ys[j - 1] - ys[j]))
		radius[j] = smooth
	var nv := PackedVector3Array(); var nn := PackedVector3Array()
	var nb := PackedInt32Array(); var nw := PackedFloat32Array(); var ni := PackedInt32Array()
	var hips := _bind_index("Hips"); var spine := _bind_index("Spine")
	var left := _bind_index("LeftUpperLeg"); var right := _bind_index("RightUpperLeg")
	for j in ys.size():
		for k in n:
			var a := (float(k) + 0.5) / n * TAU
			var dir := Vector2(cos(a), sin(a))
			var r: float = radius[j][k]
			nv.append(Vector3(dir.x * r, ys[j], centre_z + dir.y * r))
			nn.append(Vector3(dir.x, 0.0, dir.y))
			# Front (+Z) follows its thigh most, the back least; across the middle the two
			# thighs share it.
			var along := dir.y
			var share: float = lerpf(SKIRT_TO_LEG[1], SKIRT_TO_LEG[0] if along > 0.0 else SKIRT_TO_LEG[2], absf(along))
			var to_leg := _ease_down(ys[j], SKIRT_TOP_Y - 0.05, JACKET_HEM_Y) * share
			var to_left := clampf(0.5 + dir.x * 2.0, 0.0, 1.0)
			var top := clampf((ys[j] - (SKIRT_TOP_Y - 0.04)) / 0.04, 0.0, 1.0) * 0.3
			var on_hips := 1.0 - to_leg
			nb.append_array(PackedInt32Array([hips, spine, left, right]))
			nw.append_array(PackedFloat32Array([on_hips * (1.0 - top), on_hips * top, to_leg * to_left, to_leg * (1.0 - to_left)]))
	for j in SKIRT_RINGS:
		for k in n:
			var a := j * n + k
			var b := j * n + (k + 1) % n
			ni.append_array(PackedInt32Array([a, a + n, b, b, a + n, b + n]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = nv
	arr[Mesh.ARRAY_NORMAL] = nn
	arr[Mesh.ARRAY_BONES] = nb
	arr[Mesh.ARRAY_WEIGHTS] = nw
	arr[Mesh.ARRAY_INDEX] = ni
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# Both sides drawn (the inside shows under the hem), and whatever of it a fall puts on the
	# mat laid on the mat, as the hakama is: carried by the hips, the back of the skirt went
	# 3 cm under it with Uke on his back.
	mesh.surface_set_material(0, resting_on_mat(cloth_material))
	var mi := MeshInstance3D.new()
	mi.name = "Gi_skirt"
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
	# On the jacket shell (built before the lapel), so the band lies on the draped cloth.
	var verts: PackedVector3Array = jacket.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] if jacket else _grid_arrays[Mesh.ARRAY_VERTEX]
	var z := -INF
	for i in verts.size():
		var v := verts[i]
		if v.z > 0.0 and absf(v.x - x) < 0.025 and absf(v.y - y) < 0.015 and v.z > z:
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
	# The overlapping front (the character's left, worn on top) runs from the hem up: straight
	# up the skirt beside the centre, under the belt, then across the chest to the collar. The
	# other front shows only above the belt, where it disappears under the first.
	var skirt_steps := 5
	for i in skirt_steps:
		var y := lerpf(JACKET_HEM_Y + 0.005, BELT_Y - BELT_HEIGHT * 0.5, float(i) / skirt_steps)
		var x := -LAPEL_OVERLAP_X
		left.append([Vector3(x, y, _front_z(x, y)), Vector3(1, 0, 0), 0.006])
	for i in steps + 1:
		# Up to just under the collar rim, which takes over from there round the neck.
		var y := lerpf(BELT_Y + BELT_HEIGHT * 0.5, V_TOP_Y - 0.04, float(i) / steps)
		var x := _front_edge_x(y)
		left.append([Vector3(x, y, _front_z(x, y)), Vector3(1, 0, 0), 0.006])
		right.append([Vector3(-x, y, _front_z(-x, y)), Vector3(-1, 0, 0), 0.002])
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
## The belt: a flat cotton band, two wraps of it, lying tight on the jacket at the waist where it
## holds the jacket closed, with a flat square knot in front and the two ends hanging from it.
## It used to be a ring as wide as the widest cloth anywhere near the waist — which took in the
## jacket's skirt flaring out below it — 1 cm thick and smooth-shaded all round, and it read as a
## hard coil standing off the body. Now it is measured on the cloth inside its own band only,
## stands BELT_THICKNESS off it, and its faces meet at edges, as a woven band's do.
func _belt(arrays: Array, dominant: PackedStringArray) -> MeshInstance3D:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n := 48
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
	# The cloth inside the band: the jacket's shell there, and the skirt's top edge under it.
	var shell: PackedVector3Array = jacket.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if skirt:
		shell.append_array(skirt.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	for v in shell:
		var d := Vector2(v.x - centre.x, v.z - centre.z)
		if absf(v.y - BELT_Y) < BELT_HEIGHT * 0.5 and d.length() < 0.22:
			var k := int(floor(wrapf(d.angle(), 0.0, TAU) / TAU * n)) % n
			radii[k] = maxf(radii[k], d.length())
	# Sectors no vertex fell into take their neighbours', then the band is drawn smooth round:
	# pulled tight, it does not follow every fold of the cloth under it.
	for _pass in 4:
		for k in n:
			if radii[k] <= 0.0:
				radii[k] = maxf(radii[(k + n - 1) % n], radii[(k + 1) % n])
	var smooth := PackedFloat32Array(); smooth.resize(n)
	for k in n:
		smooth[k] = maxf(radii[k], (radii[(k + n - 1) % n] + radii[k] * 2.0 + radii[(k + 1) % n]) / 4.0) + 0.002
	radii = smooth
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
	# The second wrap's edge: a shallow step a third of the way up the outer face.
	var seam_out: Array = ring.call(BELT_Y - BELT_HEIGHT * 0.17, BELT_THICKNESS * 0.75)
	var seam_hi: Array = ring.call(BELT_Y - BELT_HEIGHT * 0.17 + 0.002, BELT_THICKNESS)
	bind4.call(0.7)
	# Each face its own smoothing group: the band is round the body, but square in section.
	for k in n:
		var k2 := (k + 1) % n
		st.set_smooth_group(1)
		_quad(st, bot_out[k], bot_out[k2], seam_out[k2], seam_out[k])   # outer face, lower wrap
		_quad(st, seam_hi[k], seam_hi[k2], top_out[k2], top_out[k])     # outer face, upper wrap
		st.set_smooth_group(2)
		_quad(st, seam_out[k], seam_out[k2], seam_hi[k2], seam_hi[k])   # the step between them
		st.set_smooth_group(3)
		_quad(st, top_in[k], top_in[k2], bot_in[k2], bot_in[k])         # inner face (back-facing)
		st.set_smooth_group(4)
		_quad(st, top_out[k], top_out[k2], top_in[k2], top_in[k])       # top edge
		st.set_smooth_group(5)
		_quad(st, bot_in[k], bot_in[k2], bot_out[k2], bot_out[k])       # bottom edge
	# The knot: flat and square, a little proud of the band in front, and the two ends hanging
	# from under it, apart at the bottom.
	bind4.call(1.0)
	st.set_smooth_group(0xFFFFFFFF)
	var front_r: float = radii[int(n / 4)] + BELT_THICKNESS   # +Z is the front (angle π/2)
	var knot_c := centre + Vector3(0.0, -0.002, front_r + 0.007)
	_box(st, knot_c, Vector3(0.062, 0.048, 0.014))
	for side in [-1.0, 1.0]:
		var top_c := knot_c + Vector3(side * 0.012, -0.02, -0.002)
		var hang := Vector3(side * 0.06, -0.20, 0.012)
		_strap(st, top_c, top_c + hang, BELT_HEIGHT, 0.007)
	st.generate_normals()
	st.set_material(belt_material)
	var mi := MeshInstance3D.new()
	mi.name = "Gi_belt"
	mi.mesh = st.commit()
	# The belt holds the jacket in: the cloth under it is drawn in to just inside it.
	# The jacket within the band only: eased in above it too, its waist no longer covered the top
	# of a hakama's side openings.
	_cinch(jacket, centre, radii, 0.002, 0.0)
	_cinch(skirt, centre, radii, 0.002)
	# The trousers' waist is under the jacket's, a layer further in.
	_cinch(trousers, centre, radii, 0.008)
	return mi


## Pulls every vertex of `piece` within the belt's height (and, easing out, CINCH_EASE above it)
## in toward the waist until it lies inside the belt's inner face. Without it the jacket,
## measured on its own, stood a few millimetres proud of the tight band in places and showed over
## its edges, and the skirt flared out from under its bottom edge straight away.
const CINCH_EASE := 0.025


func _cinch(piece: MeshInstance3D, centre: Vector3, radii: PackedFloat32Array, inset: float, ease := CINCH_EASE) -> void:
	var n := radii.size()
	var old: ArrayMesh = piece.mesh
	var mesh := ArrayMesh.new()
	for si in old.get_surface_count():
		var a := old.surface_get_arrays(si)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		for i in vs.size():
			var v := vs[i]
			# Below the belt the cloth flares out again at once (the jacket's skirt over the hips,
			# which under a hakama is what covers its side openings); above it eases out.
			if v.y < BELT_Y - BELT_HEIGHT * 0.5:
				continue
			var dy := v.y - (BELT_Y + BELT_HEIGHT * 0.5)
			if dy > ease:
				continue
			var d := Vector2(v.x - centre.x, v.z - centre.z)
			var k := int(floor(wrapf(d.angle(), 0.0, TAU) / TAU * n)) % n
			var limit: float = radii[k] - inset
			if dy > 0.0:   # above or below the band: eased back to where the cloth was
				limit += (d.length() - limit) * smoothstep(0.0, ease, dy)
			if d.length() > limit and d.length() > 1e-4:
				d = d.normalized() * limit
				vs[i] = Vector3(centre.x + d.x, v.y, centre.z + d.y)
		a[Mesh.ARRAY_VERTEX] = vs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		mesh.surface_set_material(si, old.surface_get_material(si))
	piece.mesh = mesh


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


# ---------------------------------------------------------------- hakama

## A hakama is a divided skirt: each leg is a wide pleated tube of its own, and the two only read
## as one skirt while the legs are together. So it is built as two tubes, each a "D" in section:
## a flat inner wall on the midline (the two walls lie together there, unseen while standing)
## and a superellipse round the outside, half the waist at the top and flaring to the hem. It
## is not cut from the body like the gi, because cloth this wide has nothing to do with the
## shape of the skin under it; the body is only measured, so the tubes clear it (_hakama_room).
## Each tube is skinned from the hips down to the thigh and then the shin of its own leg, so a
## step, bent knees or seiza part the tubes instead of stretching a sheet between the knees.
const HAKAMA_BLACK := Color(0.055, 0.06, 0.085)
## Top edge: the front band just over the belt, a little higher behind under the koshi-ita.
const HAKAMA_TOP_FRONT_Y := BELT_Y + BELT_HEIGHT * 0.5 + 0.012
const HAKAMA_TOP_BACK_Y := 1.05
## The hem sits at the ankle bone (the ankle joint is at 0.07), the feet showing below it.
const HAKAMA_HEM_Y := 0.10
## Each leg's section at the waist and at the hem: x its reach out from the midline, y the
## front and z the back (the figure faces +z). Where the body or the gi under it would not
## clear, the measured shape pushes the cloth out further.
const HAKAMA_WAIST := Vector3(0.17, 0.172, -0.078)
const HAKAMA_HEM := Vector3(0.31, 0.23, -0.20)
## Squareness of the section (2 would be an ellipse): fuller at the sides, as cloth over hips.
const HAKAMA_ROUND := 2.6
## How far the cloth stands clear of the body, or of the gi when it is worn under.
const HAKAMA_CLEAR := 0.012
## Knife pleats: how far each fold steps out at the hem (less at the waist, where they are
## pressed flat), and how many on each leg: five in front (three on the character's right,
## two on the left) and one either side of the centre at the back.
const PLEAT_DEPTH := 0.02
const PLEATS_FRONT_RIGHT := 3
const PLEATS_FRONT_LEFT := 2
const PLEATS_BACK := 1
## The front pleats run from the centre round to this angle (90° straight ahead, 0 the side),
## the back pleat from the centre back to minus PLEAT_BACK_TO; the sides between are plain.
const PLEAT_FRONT_TO := 22.0
const PLEAT_BACK_TO := 50.0
## The side openings (hiwaki) between the front and back panels, where the gi shows: open this
## many degrees either side of the side seam at the top edge, closing to nothing at SLIT_BOTTOM_Y.
const SLIT_HALF_DEG := 10.0
const SLIT_BOTTOM_Y := 0.88
const HAKAMA_RINGS := 46
## Where the cloth hands over from the hips to the thigh and from the thigh to the shin, as
## rest heights: [hips down to, thigh from, thigh down to, shin from]. The front follows the
## thigh early, or a knee raised in seiza or a roll comes through it; the back hangs from the
## hips longer, or the seat comes through it when the thighs swing forward; and the front hands
## over below the knee, so the cloth folded over a bent knee stays outside the kneecap.
const HAKAMA_WEIGHTS_FRONT := [0.96, 0.80, 0.48, 0.28]
const HAKAMA_WEIGHTS_SIDE := [0.93, 0.72, 0.52, 0.32]
const HAKAMA_WEIGHTS_BACK := [0.82, 0.56, 0.54, 0.34]
## The himo wound over the top edge, and the koshi-ita, the stiff board at the back: half-widths
## at its foot and top, and how far it rises.
const HIMO_HEIGHT := 0.035
const HIMO_THICKNESS := 0.006
const KOSHI_ITA_BOTTOM := 0.13
const KOSHI_ITA_TOP := 0.10
const KOSHI_ITA_HEIGHT := 0.10
const KOSHI_ITA_THICKNESS := 0.012
## The character's right panel reaches this far past the midline and lies over the left one,
## lifted clear of its pleats, front and back: a step that parts the legs slides one panel off
## the other instead of opening a slit up the middle.
const HAKAMA_OVERLAP := 0.045
## Height bins for the room measurement, and angle sectors round each leg.
const ROOM_BIN := 0.02
const ROOM_SECTORS := 36

## Where the himo's front face is at the centre, for the knot.
var _himo_front_z := 0.0
## The top ring of each leg before pleating, for the himo and the koshi-ita: side (-1 right,
## +1 left) -> Array of [position, outward, along, the section's middle].
var _hakama_top: Dictionary = {}


func _build_hakama() -> void:
	hakama_material = _cloth_material("canvas", HAKAMA_BLACK)
	hakama_material.cull_mode = BaseMaterial3D.CULL_DISABLED   # the inside shows at the hem
	hakama_material.roughness = 0.75
	hakama_material.normal_scale = 1.0
	hakama_material.vertex_color_use_as_albedo = true   # the shade deep in each fold (_hakama_ring)
	hakama_shader_material = resting_on_mat(hakama_material)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _hakama_tubes())
	mesh.surface_set_material(0, hakama_shader_material)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)
	_himo(st)
	_koshi_ita(st)
	st.generate_normals()
	st.set_material(hakama_shader_material)
	st.commit(mesh)
	hakama = MeshInstance3D.new()
	hakama.name = "Hakama"
	hakama.mesh = mesh
	# The belt's knot, in front of the himo: the rest of the belt is under the hakama.
	var ks := SurfaceTool.new()
	ks.begin(Mesh.PRIMITIVE_TRIANGLES)
	ks.set_bones(PackedInt32Array([_bind_index("Hips"), _bind_index("Spine"), 0, 0]))
	ks.set_weights(PackedFloat32Array([0.7, 0.3, 0.0, 0.0]))
	_box_out(ks, Vector3(0.0, HAKAMA_TOP_FRONT_Y - HIMO_HEIGHT * 0.5, _himo_front_z + 0.012), Vector3(0.075, 0.042, 0.026))
	ks.generate_normals()
	ks.set_material(belt_material)
	hakama_knot = MeshInstance3D.new()
	hakama_knot.name = "Hakama_knot"
	hakama_knot.mesh = ks.commit()
	for m in [hakama, hakama_knot]:
		m.cast_shadow = rig.body.cast_shadow
		rig.skeleton.add_child(m)
		m.skeleton = m.get_path_to(rig.skeleton)   # see build(): a code-made mesh needs the path
		m.skin = rig.body.skin


## The section's size at rest height `y`: x reach from the midline, y front z, z back z.
static func _hakama_dims(y: float) -> Vector3:
	var t := clampf((HAKAMA_TOP_FRONT_Y - y) / (HAKAMA_TOP_FRONT_Y - HAKAMA_HEM_Y), 0.0, 1.0)
	return HAKAMA_WAIST.lerp(HAKAMA_HEM, t)


static func _hakama_centre_z(d: Vector3) -> float:
	return (d.y + d.z) * 0.5


## A point on the outside of one leg's section at unit scale, `phi` degrees round from the side
## (90 straight ahead, -90 straight back), as (lateral reach, z from the section's centre).
static func _hakama_section(phi: float, d: Vector3) -> Vector2:
	var c := cos(deg_to_rad(phi)); var s := sin(deg_to_rad(phi))
	var e := 2.0 / HAKAMA_ROUND
	return Vector2(d.x * signf(c) * pow(absf(c), e), (d.y - d.z) * 0.5 * signf(s) * pow(absf(s), e))


## The outward normal of the section at `phi`, in the figure's frame, for `side`.
static func _hakama_normal(phi: float, d: Vector3, side: float) -> Vector3:
	var c := cos(deg_to_rad(phi)); var s := sin(deg_to_rad(phi))
	var e := 2.0 * (HAKAMA_ROUND - 1.0) / HAKAMA_ROUND   # the gradient of |x/a|^n + |z/b|^n
	return Vector3(side * pow(absf(c), e) / d.x, 0.0, signf(s) * pow(absf(s), e) / ((d.y - d.z) * 0.5)).normalized()


## How much each leg's section must grow, per height bin and angle sector, to clear the body and
## the gi under it by HAKAMA_CLEAR. Measured on the rest mesh: the torso and that side's leg, and
## the jacket, its lapel and the trousers, which the hakama is worn over.
func _hakama_room(side: float, shift: float) -> Array:
	var bins := int(ceil((HAKAMA_TOP_BACK_Y - HAKAMA_HEM_Y) / ROOM_BIN)) + 1
	var need: Array = []
	for b in bins:
		var row := PackedFloat32Array(); row.resize(ROOM_SECTORS); row.fill(1.0)
		need.append(row)
	var points := PackedVector3Array()
	var body: Array = rig.body.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = body[Mesh.ARRAY_VERTEX]
	var dominant := _dominant_bones(body)
	var leg := "Left" if side > 0.0 else "Right"
	for i in verts.size():
		if dominant[i] in ["Hips", "Spine", leg + "UpperLeg", leg + "LowerLeg"]:
			points.append(verts[i])
	for m in [jacket, lapel, trousers]:
		for s in m.mesh.get_surface_count():
			points.append_array(m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
	var n := HAKAMA_ROUND
	for p in points:
		if p.y < HAKAMA_HEM_Y or p.y > HAKAMA_TOP_BACK_Y or p.x * side < -shift or absf(p.x) > 0.3:
			continue
		var d := _hakama_dims(p.y) + Vector3(shift, 0, 0)
		var u := (p.x * side + shift) / d.x
		var t := (p.z - _hakama_centre_z(d)) / ((d.y - d.z) * 0.5)
		var rho := pow(pow(u, n) + pow(absf(t), n), 1.0 / n)
		if rho < 1e-4:
			continue
		var phi := rad_to_deg(atan2(signf(t) * pow(absf(t) / rho, n * 0.5), pow(u / rho, n * 0.5)))
		var k := clampi(int((phi + 90.0) / 180.0 * ROOM_SECTORS), 0, ROOM_SECTORS - 1)
		var b := int((p.y - HAKAMA_HEM_Y) / ROOM_BIN)
		var r := _hakama_section(phi, d).length()
		need[b][k] = maxf(need[b][k], rho + HAKAMA_CLEAR / maxf(r, 0.05))
	# Spread each need to the neighbouring sectors and bins (cloth this stiff does not follow a
	# lapel's edge or one bin's bump), then let it hang: below a wide place it narrows back to its
	# own shape only slowly, the way the jacket's skirt does (_drape); then smooth what is left.
	var spread: Array = []
	for b in bins:
		var row := PackedFloat32Array(); row.resize(ROOM_SECTORS)
		for k in ROOM_SECTORS:
			var m := 1.0
			for db in range(-2, 3):
				for dk in range(-1, 2):
					m = maxf(m, need[clampi(b + db, 0, bins - 1)][clampi(k + dk, 0, ROOM_SECTORS - 1)])
			row[k] = m
		spread.append(row)
	need = spread
	for b in range(bins - 2, -1, -1):
		var d := _hakama_dims(HAKAMA_HEM_Y + b * ROOM_BIN) + Vector3(shift, 0, 0)
		var d_above := _hakama_dims(HAKAMA_HEM_Y + (b + 1) * ROOM_BIN) + Vector3(shift, 0, 0)
		for k in ROOM_SECTORS:
			var phi := -90.0 + (k + 0.5) * 180.0 / ROOM_SECTORS
			var r := _hakama_section(phi, d).length()
			var r_above := _hakama_section(phi, d_above).length()
			need[b][k] = maxf(need[b][k], (need[b + 1][k] * r_above - DRAPE_TAPER * ROOM_BIN) / maxf(r, 0.05))
	var smooth: Array = []
	for b in bins:
		var row := PackedFloat32Array(); row.resize(ROOM_SECTORS)
		for k in ROOM_SECTORS:
			row[k] = (need[maxi(b - 1, 0)][k] + need[b][k] * 2.0 + need[mini(b + 1, bins - 1)][k]) * 0.25
		smooth.append(row)
	return smooth


## Scale for a point of the section at height `y` and angle `phi`, read from the room table
## between bins so the cloth does not step.
static func _room_scale(need: Array, y: float, phi: float) -> float:
	var fb := clampf((y - HAKAMA_HEM_Y) / ROOM_BIN, 0.0, need.size() - 1.001)
	var b := int(fb)
	var k := clampi(int((phi + 90.0) / 180.0 * ROOM_SECTORS), 0, ROOM_SECTORS - 1)
	return lerpf(need[b][k], need[mini(b + 1, need.size() - 1)][k], fb - b)


## One ring's samples round a leg, the same at every height so the pleats run straight down:
## [phi, pleat offset 0..1, along, slit, shade], where along runs +1 at the centre front to -1
## at the centre back (for the weights and the slope of the top edge), slit marks the front (1)
## and back (-1) edges of the side opening and shade darkens the cloth deep in a fold. A pleat is a ramp in the offset ending in a step back at
## the same angle: the fold's edge. Then the inner wall, back to front, with NAN for phi and its
## fraction of the way in the offset slot.
static func _hakama_ring(front_pleats: int) -> Array:
	var out: Array = []
	var ramp: Array[float] = [0.0, 0.14, 0.28, 0.42, 0.56, 0.70, 0.84, 0.94, 1.0]
	for i in front_pleats:
		for u in ramp:
			var phi := 90.0 - (90.0 - PLEAT_FRONT_TO) * (i + u) / front_pleats
			out.append([phi, 1.0 - u, sin(deg_to_rad(phi)), 0, _fold_shade(1.0 - u)])
	# The plain side, with the slit's two edges at the side seam (they open apart toward the top).
	for phi in [(PLEAT_FRONT_TO + SLIT_HALF_DEG + 1.0) * 0.5, SLIT_HALF_DEG + 1.0]:
		out.append([phi, 0.0, sin(deg_to_rad(phi)), 0, 1.0])
	out.append([0.0, 0.0, 0.0, 1, 1.0])
	out.append([0.0, 0.0, 0.0, -1, 1.0])
	for i in 4:
		var phi := lerpf(-SLIT_HALF_DEG - 1.0, -PLEAT_BACK_TO, float(i) / 4)
		out.append([phi, 0.0, sin(deg_to_rad(phi)), 0, 1.0])
	for i in PLEATS_BACK:
		for u in ramp:
			var phi := -PLEAT_BACK_TO - (90.0 - PLEAT_BACK_TO) * (i + u) / PLEATS_BACK
			out.append([phi, u, sin(deg_to_rad(phi)), 0, _fold_shade(u)])
	var wall := 6
	for i in wall + 1:
		var f := float(i) / wall
		out.append([NAN, f, lerpf(-1.0, 1.0, f), 0, 0.7])
	return out


## How much light reaches the cloth at a pleat offset (1 at the fold's edge, 0 deep in it): the
## geometry alone makes the folds too faint on cloth this dark.
static func _fold_shade(offset: float) -> float:
	return 1.0 - 0.45 * pow(1.0 - offset, 3.0)


## How far each edge of the side slit stands from the side seam at rest height `y`, degrees.
static func _slit_half(y: float) -> float:
	return SLIT_HALF_DEG * clampf((y - SLIT_BOTTOM_Y) / (HAKAMA_TOP_FRONT_Y - SLIT_BOTTOM_Y), 0.0, 1.0)


## Bone weights for a point of the cloth at rest height `y`, `along` round its leg.
func _hakama_weights(y: float, along: float, leg: String) -> Array:
	var a: Array = HAKAMA_WEIGHTS_SIDE
	var b: Array = HAKAMA_WEIGHTS_FRONT if along > 0.0 else HAKAMA_WEIGHTS_BACK
	var w := []
	for i in 4:
		w.append(lerpf(a[i], b[i], absf(along)))
	var to_leg := _ease_down(y, w[0], w[1])
	var to_shin := _ease_down(y, w[2], w[3])
	var hips := 1.0 - to_leg
	# The top follows the waist as the spine bends, like the belt.
	var spine := hips * 0.35 * clampf((y - 0.95) / 0.08, 0.0, 1.0)
	return [
		PackedInt32Array([_bind_index("Hips"), _bind_index("Spine"), _bind_index(leg + "UpperLeg"), _bind_index(leg + "LowerLeg")]),
		PackedFloat32Array([hips - spine, spine, to_leg * (1.0 - to_shin), to_leg * to_shin]),
	]


## 0 above `top`, 1 below `bottom`, eased between.
static func _ease_down(y: float, top: float, bottom: float) -> float:
	var t := clampf((top - y) / maxf(top - bottom, 1e-4), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _hakama_top_y(along: float) -> float:
	return lerpf(HAKAMA_TOP_BACK_Y, HAKAMA_TOP_FRONT_Y, (along + 1.0) * 0.5)


## Both legs' tubes as mesh arrays: rings of the ring samples from the top edge to the hem.
func _hakama_tubes() -> Array:
	var nv := PackedVector3Array(); var nn := PackedVector3Array(); var nc := PackedColorArray()
	var nb := PackedInt32Array(); var nw := PackedFloat32Array(); var ni := PackedInt32Array()
	for side in [-1.0, 1.0]:
		var leg := "Left" if side > 0.0 else "Right"
		var shift := HAKAMA_OVERLAP if side < 0.0 else 0.0
		var need := _hakama_room(side, shift)
		var ring := _hakama_ring(PLEATS_FRONT_LEFT if side > 0.0 else PLEATS_FRONT_RIGHT)
		var k_count := ring.size()
		var base := nv.size()
		var grid: Array = []
		var top: Array = []
		for j in HAKAMA_RINGS + 1:
			var v := float(j) / HAKAMA_RINGS
			var row := PackedVector3Array()
			var corners := {}
			for s in ring:
				var y := lerpf(_hakama_top_y(s[2]), HAKAMA_HEM_Y, v)
				if is_nan(s[0]):
					# The wall runs straight between the arc's two corners at this height.
					var p: Vector3 = (corners[-1] as Vector3).lerp(corners[1], s[1])
					row.append(Vector3(p.x, y, p.z))
					continue
				var phi: float = s[0] + s[3] * _slit_half(y)
				var d := _hakama_dims(y) + Vector3(shift, 0, 0)
				var q := _hakama_section(phi, d) * _room_scale(need, y, phi)
				var p := Vector3(side * (q.x - shift), y, _hakama_centre_z(d) + q.y)
				var out := _hakama_normal(phi, d, side)
				var depth := PLEAT_DEPTH * (0.4 + 0.6 * v)
				if shift > 0.0:
					# Where it lies over the other panel, clear of that panel's deepest fold.
					p += out * (depth + 0.004) * clampf((side * -p.x + 0.02) / 0.03, 0.0, 1.0)
				if absf(phi) > 89.99:
					corners[int(signf(phi))] = p
				if j == 0:
					top.append([p, out, s[2], Vector3(side * (d.x * 0.45 - shift), y, _hakama_centre_z(d))])
				row.append(p + out * depth * s[1])
			grid.append(row)
		_hakama_top[side] = top
		for j in HAKAMA_RINGS + 1:
			for k in k_count:
				var p: Vector3 = grid[j][k]
				var across: Vector3 = grid[j][(k + 1) % k_count] - grid[j][(k + k_count - 1) % k_count]
				var down: Vector3 = grid[mini(j + 1, HAKAMA_RINGS)][k] - grid[maxi(j - 1, 0)][k]
				var normal := across.cross(down).normalized()
				# Outward is away from the middle of the leg's section at this height.
				var d := _hakama_dims(p.y) + Vector3(shift, 0, 0)
				if normal.dot(Vector3(p.x - side * (d.x * 0.45 - shift), 0.0, p.z - _hakama_centre_z(d))) < 0.0:
					normal = -normal
				nv.append(p); nn.append(normal)
				var shade: float = ring[k][4]
				nc.append(Color(shade, shade, shade))
				var w := _hakama_weights(p.y, ring[k][2], leg)
				nb.append_array(w[0]); nw.append_array(w[1])
		for j in HAKAMA_RINGS:
			for k in k_count:
				if ring[k][3] == 1:
					continue   # the side slit: its two edges share a column below where it opens
				var a := base + j * k_count + k
				var b := base + j * k_count + (k + 1) % k_count
				for tri in [[a, b, b + k_count], [a, b + k_count, a + k_count]]:
					var face: Vector3 = (nv[tri[1]] - nv[tri[0]]).cross(nv[tri[2]] - nv[tri[0]])
					if face.dot(nn[tri[0]] + nn[tri[1]] + nn[tri[2]]) > 0.0:
						ni.append_array(PackedInt32Array([tri[0], tri[2], tri[1]]))
					else:
						ni.append_array(PackedInt32Array([tri[0], tri[1], tri[2]]))
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = nv
	a[Mesh.ARRAY_NORMAL] = nn
	a[Mesh.ARRAY_COLOR] = nc
	a[Mesh.ARRAY_BONES] = nb
	a[Mesh.ARRAY_WEIGHTS] = nw
	a[Mesh.ARRAY_INDEX] = ni
	return a


## The himo: a band wound over the top edge, standing out past the pleats, with a lid from its
## top edge in to the waist so nothing shows between the cloth and the body from above.
func _himo(st: SurfaceTool) -> void:
	for side in _hakama_top:
		var leg := "Left" if side > 0.0 else "Right"
		var prev: Array = []
		for s in _hakama_top[side]:
			var p: Vector3 = s[0]; var out: Vector3 = s[1]
			var o := p + out * (PLEAT_DEPTH * 0.4 + HIMO_THICKNESS)
			var centre: Vector3 = s[3]
			var cur := [o + Vector3(0, 0.002, 0), o - Vector3(0, HIMO_HEIGHT, 0), centre.lerp(p, 0.8) + Vector3(0, 0.002, 0)]
			if s[2] > 0.999:
				_himo_front_z = maxf(_himo_front_z, o.z)
			if prev.size() > 0 and (prev[0] as Vector3).distance_to(cur[0]) > 1e-4:
				var w := _hakama_weights(p.y, s[2], leg)
				st.set_bones(w[0]); st.set_weights(w[1])
				_quad_out(st, prev[1], cur[1], cur[0], prev[0], out)          # face
				_quad_out(st, prev[0], cur[0], cur[2], prev[2], Vector3.UP)   # lid
			prev = cur


## A quad wound to face `want`, for SurfaceTool's generated normals: front faces wind the
## other way from _rq's (b - a) × (c - a), as the belt's quads do.
static func _quad_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3) -> void:
	if (b - a).cross(d - a).dot(want) <= 0.0:
		_quad(st, a, b, c, d)
	else:
		_quad(st, d, c, b, a)


## A box of `size` centred on `c`, every face wound outward.
static func _box_out(st: SurfaceTool, c: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	for axis in 3:
		for sgn in [-1.0, 1.0]:
			var n := Vector3.ZERO; n[axis] = sgn
			var u := Vector3.ZERO; u[(axis + 1) % 3] = 1.0
			var v := Vector3.ZERO; v[(axis + 2) % 3] = 1.0
			var f := c + n * h[axis]
			var du := u * h[(axis + 1) % 3]; var dv := v * h[(axis + 2) % 3]
			_quad_out(st, f - du - dv, f + du - dv, f + du + dv, f - du + dv, n)


## The koshi-ita: a stiff board at the back of the waist, standing from the himo and leaning in
## to the small of the back, a trapezoid wider at its foot.
func _koshi_ita(st: SurfaceTool) -> void:
	var cols := 8
	var shell := PackedVector3Array(jacket.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	var foot_y := HAKAMA_TOP_BACK_Y - HIMO_HEIGHT * 0.6
	var outer: Array = []; var inner: Array = []
	for i in cols + 1:
		var f := float(i) / cols * 2.0 - 1.0
		var row_o := []; var row_i := []
		for r in 2:
			var y := foot_y + KOSHI_ITA_HEIGHT * r
			var x := f * (KOSHI_ITA_BOTTOM if r == 0 else KOSHI_ITA_TOP)
			# Lie on whatever is behind there: the himo at the foot, the jacket's back above it.
			var z := 0.0
			for v in shell:
				if absf(v.x - x) < 0.03 and absf(v.y - y) < 0.02:
					z = minf(z, v.z)
			if r == 0:
				z = minf(z, _himo_back_z(x))
			z -= 0.004
			row_i.append(Vector3(x, y, z))
			row_o.append(Vector3(x, y, z - KOSHI_ITA_THICKNESS))
		outer.append(row_o); inner.append(row_i)
	st.set_bones(PackedInt32Array([_bind_index("Hips"), _bind_index("Spine"), 0, 0]))
	st.set_weights(PackedFloat32Array([0.45, 0.55, 0.0, 0.0]))
	for i in cols:
		_quad_out(st, outer[i][0], outer[i + 1][0], outer[i + 1][1], outer[i][1], Vector3.FORWARD)   # -z: the back
		_quad_out(st, inner[i][0], inner[i + 1][0], inner[i + 1][1], inner[i][1], Vector3.BACK)
		_quad_out(st, outer[i][1], outer[i + 1][1], inner[i + 1][1], inner[i][1], Vector3.UP)
	for e in [[0, -1.0], [cols, 1.0]]:
		var i: int = e[0]
		_quad_out(st, outer[i][0], inner[i][0], inner[i][1], outer[i][1], Vector3(e[1], 0, 0))


## The himo's outer face at the back, at `x`.
func _himo_back_z(x: float) -> float:
	var best := 0.0
	var best_dx := INF
	for side in _hakama_top:
		for s in _hakama_top[side]:
			var p: Vector3 = s[0]
			if p.z < 0.0 and absf(p.x - x) < best_dx:
				best_dx = absf(p.x - x)
				best = (p + (s[1] as Vector3) * (PLEAT_DEPTH * 0.4 + HIMO_THICKNESS)).z
	return best
