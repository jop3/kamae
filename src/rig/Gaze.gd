class_name Gaze
extends RefCounted
## Where a figure looks, and the head and eyes that follow it.
##
## Two people doing a technique watch each other. TechniqueScript turns each figure's neck and
## head toward its partner before a pose is saved, and that look used to be all there was: between
## two poses the head's rotation was blended like any other bone's, so as soon as either body
## turned the faces drifted apart, and the eyes, which have no bones in this rig, stared straight
## out of the head. A figure's `look` (CharacterRig.look, saved with each pose) now says what it
## watches — its partner, a part of someone, a direction, or nothing — and:
##   - between two poses the neck and head take up whatever the blend left between the face and
##     what it watches (turn_head, faded to nothing at the poses themselves, which are shown as
##     saved);
##   - on every frame the eyes take up what the neck and head could not, within their own range
##     (aim_eyes, a vertex shader on the eye mesh: each eyeball turns about its own centre).
## A figure with no `look` (a pose written before this) is left as it was, eyes and all.

## How far off the way the body faces a partner may be and still be looked at, degrees: someone
## beside you is watched out of the corner of the eye, not by craning round. The turn fades out
## over FIELD_FADE either side of it, so a partner walking round does not snap the head.
const FIELD := 100.0
const FIELD_FADE := 15.0
## How a turn is shared between the neck and the head, and the most each is turned by a look:
## inside their ranges (Joints: neck 70°, head 30° of rotation) with some to spare.
const SHARE := {"Neck": 0.6, "Head": 1.0}
const MOST := {"Neck": 40.0, "Head": 22.0}
## How far an eye turns in its socket before the lids would cover the iris, degrees.
const EYE_SIDE := 25.0
const EYE_UP := 15.0
const EYE_DOWN := 20.0
## The eyeballs' centres in the rest pose (character space, metres), measured from the eye mesh:
## the front of each eyeball less its radius.
const EYE_CENTRE := Vector3(0.0289, 1.553, 0.1226)
## Between the eyes, a little in front of them: what a look is measured from.
const EYES := Vector3(0.0, 1.553, 0.13)

const EYE_SHADER := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
// The eye mesh (eyeball and cornea), each eyeball turned about its own centre in the skinned
// mesh's space: Gaze.aim_eyes sets where the centres are and how each eye is turned this frame.
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 centre_right = vec3(-0.0289, 1.553, 0.1226);
uniform vec3 centre_left = vec3(0.0289, 1.553, 0.1226);
uniform mat3 turn_right = mat3(1.0);
uniform mat3 turn_left = mat3(1.0);
void vertex() {
	bool right = distance(VERTEX, centre_right) < distance(VERTEX, centre_left);
	vec3 c = right ? centre_right : centre_left;
	mat3 m = right ? turn_right : turn_left;
	VERTEX = c + m * (VERTEX - c);
	NORMAL = m * NORMAL;
	TANGENT = m * TANGENT;
	BINORMAL = m * BINORMAL;
}
void fragment() {
	vec4 a = texture(albedo_texture, UV);
	ALBEDO = a.rgb;
	ALPHA = a.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.2;
	SPECULAR = 0.7;
}
"""
static var _eye_shader: Shader


## A ShaderMaterial for the eye mesh (CharacterRig sets its texture).
static func eye_material() -> ShaderMaterial:
	if _eye_shader == null:
		_eye_shader = Shader.new()
		_eye_shader.code = EYE_SHADER
	var m := ShaderMaterial.new()
	m.shader = _eye_shader
	return m


## Whom `rig` watches by default: Tori the first Uke, everyone else Tori.
static func partner(scene: PosingScene, rig: CharacterRig) -> CharacterRig:
	for o: CharacterRig in scene.characters:
		if o != rig and o.visible and (o.role == "Tori") != (rig.role == "Tori"):
			return o
	return null


## Where `rig`'s eyes are, world space: from its solved pose, or with `fk` from the pose alone.
static func eyes(rig: CharacterRig, fk := false) -> Vector3:
	return _head_rest_to_world(rig, fk) * EYES


## The world point `rig` watches, or null: `spec` is CharacterRig.look ("partner", "none",
## "<id>.<Bone>", or [right, up, forward] in the figure's frame).
static func goal(scene: PosingScene, rig: CharacterRig, spec, fk := false):
	if spec == null or (spec is String and spec == "none"):
		return null
	if spec is Array and spec.size() == 3:
		var heading := Basis(Vector3.UP, rig.rotation.y)
		return eyes(rig, fk) + heading * Vector3(-float(spec[0]), float(spec[1]), float(spec[2])) * 3.0
	if spec is String and spec != "" and spec != "partner":
		var dot: int = spec.find(".")
		var who := scene.get_character(spec.substr(0, dot) if dot >= 0 else spec)
		if who == null:
			return null
		var bone: String = spec.substr(dot + 1) if dot >= 0 else "Head"
		if bone == "Head":
			return eyes(who, fk)
		return (who.fk_bone_transform(bone) if fk else who.bone_world_transform(bone)).origin
	var p := partner(scene, rig)
	return eyes(p, fk) if p else null


## How much of a look at `at` the head should give, 0..1: none for someone behind the figure.
static func in_field(rig: CharacterRig, at: Vector3) -> float:
	var to := at - rig.global_position
	to.y = 0.0
	if to.length() < 0.05:
		return 1.0
	var ahead := Basis(Vector3.UP, rig.rotation.y) * Vector3(0, 0, 1)
	var off := rad_to_deg(ahead.angle_to(to.normalized()))
	return 1.0 - smoothstep(FIELD - FIELD_FADE, FIELD + FIELD_FADE, off)


## Between two poses: turns the neck and head (their pose rotations, before the solve) by
## `strength` of what separates where the face points from what the figure watches. Upright
## figures only: a fall shapes its own neck.
static func turn_head(scene: PosingScene, rig: CharacterRig, strength: float) -> void:
	if strength <= 0.0 or not rig.visible or absf(rig.rotation.x) > 0.5 or absf(rig.rotation.z) > 0.5 \
			or not rig.fall.is_empty():
		return
	var at = goal(scene, rig, rig.look, true)
	if at == null:
		return
	var k := strength * in_field(rig, at)
	if k <= 0.0:
		return
	var used := {}
	for bone: String in SHARE:
		_turn_toward(rig, bone, at, SHARE[bone] * k, MOST[bone], used)


## Turns `bone` by `share` of the angle between where the face points and `at`, up to `most`
## degrees for this look. Read from the pose alone (fk_bone_transform), so it can run before the
## frame's solve.
static func _turn_toward(rig: CharacterRig, bone: String, at: Vector3, share: float, most: float, used: Dictionary) -> void:
	var sk := rig.skeleton
	var i := sk.find_bone(bone)
	var head := _head_rest_to_world(rig, true)
	var forward := (head.basis * Vector3(0, 0, 1)).normalized()
	var want := (at - head * EYES).normalized()
	if want.length() < 0.5 or forward.dot(want) > 0.9995:
		return
	var axis := forward.cross(want).normalized()
	var angle := clampf(forward.angle_to(want) * share, 0.0, maxf(0.0, deg_to_rad(most) - float(used.get(bone, 0.0))))
	used[bone] = float(used.get(bone, 0.0)) + angle
	var parent := sk.get_bone_parent(i)
	var p_basis := rig.fk_bone_transform(sk.get_bone_name(parent)).basis.orthonormalized()
	var local := Basis(sk.get_bone_pose_rotation(i))
	var turned := (p_basis.inverse() * Basis(axis, angle) * p_basis * local).orthonormalized()
	var q := turned.get_rotation_quaternion()
	if rig.joints and rig.joints.has(bone):   # a look turns a neck as far as it goes, no further
		q = Joints.clamp_rotation(rig.joints.spec(bone), q)
	sk.set_bone_pose_rotation(i, q)


## Turns the eyes toward what the figure watches, as far as they go (or back to straight ahead
## when it watches nothing). Called once the frame is solved (CharacterRig).
static func aim_eyes(scene: PosingScene, rig: CharacterRig, material: ShaderMaterial) -> void:
	var at = goal(scene, rig, rig.look) if rig.look != null else null
	var head := _head_rest_to_world(rig, false)
	var to_mesh := rig.face_mesh_inverse()
	var to_local := (to_mesh * head)
	for side: String in ["right", "left"]:
		var centre_rest := EYE_CENTRE * Vector3(-1.0 if side == "right" else 1.0, 1.0, 1.0)
		var turn := Basis.IDENTITY
		if at != null:
			# The way to the target in the head's rest frame, as a turn of the eye from looking
			# straight ahead (+Z): sideways about the vertical, then up or down.
			var d: Vector3 = (head.affine_inverse() * (at as Vector3) - centre_rest).normalized()
			var side_deg := clampf(rad_to_deg(atan2(d.x, d.z)), -EYE_SIDE, EYE_SIDE)
			var up_deg := clampf(rad_to_deg(asin(clampf(d.y, -1.0, 1.0))), -EYE_DOWN, EYE_UP)
			turn = Basis(Vector3.UP, deg_to_rad(side_deg)) * Basis(Vector3.RIGHT, deg_to_rad(-up_deg))
		var b := to_local.basis.orthonormalized()
		material.set_shader_parameter("centre_" + side, to_local * centre_rest)
		material.set_shader_parameter("turn_" + side, b * turn * b.inverse())


## The head bone's transform from the rest pose's character space to the world, as posed: a
## point given in the rest pose (EYES, EYE_CENTRE) carried by the head.
static func _head_rest_to_world(rig: CharacterRig, fk: bool) -> Transform3D:
	var sk := rig.skeleton
	var i := sk.find_bone("Head")
	var here := rig.fk_bone_transform("Head") if fk else rig.bone_world_transform("Head")
	here = Transform3D(here.basis.orthonormalized(), here.origin)
	return here * sk.get_bone_global_rest(i).affine_inverse()
