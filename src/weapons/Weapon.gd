class_name Weapon
extends Node3D
## A training weapon (bokken, jo, tanto) with a procedural mesh. Local +Y runs from the butt
## (t = 0) to the tip (t = 1); the edge, where there is one, faces -Z.
##
## Either a hand drives the weapon ("hand": the weapon hangs off its holder's hand bone through
## `hold`) or the weapon drives the hands ("weapon": the weapon is placed freely and every hand on
## it, the holder's included, is an ordinary weapon grip).

const DEFAULTS := {
	"bokken": {"length": 1.02, "tsuka": 0.24},
	"jo": {"length": 1.28, "tsuka": 0.30},
	"tanto": {"length": 0.30, "tsuka": 0.12},
}
const WOOD := Color("a0703a")
const BOKKEN_CURVE := 0.02

## Hand-local axes measured on the mannequin: +Y wrist -> fingers; palm width little -> index;
## palm normal back -> palm.
const PALM_WIDTH := {"Right": Vector3(0.48, 0.13, 0.87), "Left": Vector3(-0.66, 0.10, 0.75)}
const PALM_NORMAL := {"Right": Vector3(-0.88, 0.10, 0.47), "Left": Vector3(-0.75, -0.06, -0.65)}

var weapon_id: String = ""
var type: String = "bokken"
var length: float = 1.02
var tsuka: float = 0.24
var drive: String = "hand"        ## "hand" | "weapon"
## {character, hand, t, roll_deg, offset} while a hand drives it; empty otherwise.
var hold: Dictionary = {}

var _mesh_instance: MeshInstance3D


func setup(id: String, weapon_type: String) -> void:
	weapon_id = id
	name = id
	type = weapon_type
	var d: Dictionary = DEFAULTS.get(type, DEFAULTS["bokken"])
	length = d["length"]
	tsuka = d["tsuka"]
	_build_mesh()


## Point along the weapon, world space, +Y aligned with the weapon axis.
func anchor_transform(t: float) -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(0, t * length, 0) + _curve_offset(t))


func _curve_offset(t: float) -> Vector3:
	if type != "bokken":
		return Vector3.ZERO
	return Vector3(0, 0, BOKKEN_CURVE * t * t)


# ---------------------------------------------------------------- hand-driven hold mapping

## Weapon frame expressed in the hand bone frame for the canonical hold: axis along the palm
## width (little finger -> thumb side), edge into the palm.
static func canonical_basis(hand: String) -> Basis:
	var y: Vector3 = (PALM_WIDTH[hand] as Vector3).normalized()
	var edge: Vector3 = PALM_NORMAL[hand]
	var z: Vector3 = -(edge - y * edge.dot(y)).normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


## hand_world * hold_offset(t, roll) = weapon_world.
func hold_offset(hand: String, t: float, roll_deg: float) -> Transform3D:
	var b := canonical_basis(hand).rotated(canonical_basis(hand).y, deg_to_rad(roll_deg))
	return Transform3D(b, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -(Vector3(0, t * length, 0) + _curve_offset(t)))


## Sets the hold so the weapon hangs off `character`'s `hand` at the canonical pose.
func set_hold(character: String, hand: String, t: float, roll_deg: float = 0.0) -> void:
	hold = {"character": character, "hand": hand, "t": t, "roll_deg": roll_deg,
		"offset": hold_offset(hand, t, roll_deg)}


## Keeps the weapon where it is relative to the holder's hand (for mode switching).
func set_hold_offset_from_current(hand_world: Transform3D) -> void:
	if hold.is_empty():
		return
	hold["offset"] = hand_world.affine_inverse() * global_transform


func to_dict() -> Dictionary:
	var h := hold.duplicate()
	if h.has("offset"):
		h["offset"] = PoseFile.transform_to_array(h["offset"])
	return {"id": weapon_id, "type": type, "length": length, "tsuka": tsuka, "drive": drive, "hold": h,
		"transform": PoseFile.transform_to_array(global_transform)}


## Restores everything `to_dict` wrote (geometry included). Does not touch grips.
func apply_dict(d: Dictionary) -> void:
	var new_type: String = d.get("type", type)
	var new_length: float = float(d.get("length", length))
	var new_tsuka: float = float(d.get("tsuka", tsuka))
	if new_type != type or not is_equal_approx(new_length, length) or not is_equal_approx(new_tsuka, tsuka):
		type = new_type
		length = new_length
		tsuka = new_tsuka
		_build_mesh()
	drive = d.get("drive", drive)
	var h: Dictionary = d.get("hold", {})
	if h.is_empty():
		hold = {}
	else:
		hold = h.duplicate()
		if hold.has("offset"):
			hold["offset"] = PoseFile.array_to_transform(hold["offset"])
		else:
			hold["offset"] = hold_offset(hold["hand"], float(hold["t"]), float(hold.get("roll_deg", 0.0)))
	if d.has("transform"):
		global_transform = PoseFile.array_to_transform(d["transform"])


# ---------------------------------------------------------------- mesh

func _build_mesh() -> void:
	if _mesh_instance:
		_mesh_instance.queue_free()
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	var segments := 12
	match type:
		"jo":
			for i in segments + 1:
				var t := float(i) / segments
				rings.append(_ring_round(t, lerpf(0.012, 0.010, t), 10))
		"tanto":
			for i in segments + 1:
				var t := float(i) / segments
				rings.append(_ring_box(t, 0.0125 * (1.0 if t < 0.9 else (1.0 - t) * 10.0), 0.006))
		_:
			for i in segments + 1:
				var t := float(i) / segments
				var w := 0.015 if t < 0.95 else 0.015 * (1.0 - t) * 20.0
				rings.append(_ring_box(t, w, 0.010))
	for r in rings.size() - 1:
		var a: Array = rings[r]
		var b: Array = rings[r + 1]
		var n: int = a.size()
		for k in n:
			var k2: int = (k + 1) % n
			st.add_vertex(a[k]); st.add_vertex(b[k]); st.add_vertex(b[k2])
			st.add_vertex(a[k]); st.add_vertex(b[k2]); st.add_vertex(a[k2])
	# caps
	for cap in [rings[0], rings[rings.size() - 1]]:
		var c := Vector3.ZERO
		for v in cap: c += v
		c /= cap.size()
		for k in cap.size():
			var k2: int = (k + 1) % cap.size()
			if cap == rings[0]:
				st.add_vertex(c); st.add_vertex(cap[k2]); st.add_vertex(cap[k])
			else:
				st.add_vertex(c); st.add_vertex(cap[k]); st.add_vertex(cap[k2])
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WOOD
	mat.roughness = 0.7
	st.set_material(mat)
	_mesh_instance.mesh = st.commit()


func _ring_box(t: float, half_x: float, half_z: float) -> Array:
	var c := Vector3(0, t * length, 0) + _curve_offset(t)
	# Edge on -Z: pinch the -Z side for the bokken.
	var zn := half_z if type != "bokken" else half_z * 0.3
	return [c + Vector3(-half_x, 0, -zn), c + Vector3(half_x, 0, -zn), c + Vector3(half_x, 0, half_z), c + Vector3(-half_x, 0, half_z)]


func _ring_round(t: float, radius: float, n: int) -> Array:
	var out := []
	var c := Vector3(0, t * length, 0)
	for i in n:
		var a := TAU * i / n
		out.append(c + Vector3(cos(a) * radius, 0, sin(a) * radius))
	return out
