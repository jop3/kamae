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

## Which way the palm faces and which way it runs are measured from the rig by FingerCurl
## (hand-local: +Y is wrist -> fingers). Hand-typed constants were tried first; the left hand's
## normal came out with the wrong sign and the shaft ended up on the back of the hand.
## Where the shaft runs through the closed hand, in hand-local metres: the hand bone's origin is
## the wrist joint, but the shaft sits in the middle of the palm, about 6 cm toward the fingers
## and 2 cm out from the palm surface (inside the curled fingers). Without this the weapon passes
## through the wrist and the fingers close on air.
const PALM_ALONG := 0.06
const PALM_OUT := 0.02

var weapon_id: String = ""
var type: String = "bokken"
var length: float = 1.02
var tsuka: float = 0.24
var drive: String = "hand"        ## "hand" | "weapon"
## {character, hand, t, roll_deg, offset} while a hand drives it; empty otherwise.
var hold: Dictionary = {}

var scene: Node                   ## PosingScene, to find a hold's character again after loading
## Sequence playback: where the weapon would be if nobody held it, and how much the hold counts.
## At influence 1 (always, outside playback) the hold places the weapon fully.
var free_transform := Transform3D()
var hold_influence := 1.0
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


## The anchor in the weapon's own frame, for callers that predict where the weapon will be.
func anchor_local(t: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0, t * length, 0) + _curve_offset(t))


func _curve_offset(t: float) -> Vector3:
	if type != "bokken":
		return Vector3.ZERO
	return Vector3(0, 0, BOKKEN_CURVE * t * t)


# ---------------------------------------------------------------- hand-driven hold mapping

## Weapon frame expressed in the hand bone frame for the canonical hold: axis along the palm
## width (little finger -> thumb side, so the tip is on the thumb side), edge into the palm.
static func canonical_basis(rig: CharacterRig, hand: String) -> Basis:
	var y: Vector3 = rig.fingers.palm_width(hand).normalized()
	var edge: Vector3 = rig.fingers.palm_normal(hand)
	var z: Vector3 = -(edge - y * edge.dot(y)).normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


## The point in the hand that the shaft passes through, in the hand bone's frame.
static func palm_centre(rig: CharacterRig, hand: String) -> Vector3:
	return Vector3(0, PALM_ALONG, 0) + rig.fingers.palm_normal(hand).normalized() * PALM_OUT


## hand_world * hold_offset(t, roll) = weapon_world: anchor(t) lands on the palm centre.
func hold_offset(rig: CharacterRig, hand: String, t: float, roll_deg: float) -> Transform3D:
	var cb := canonical_basis(rig, hand)
	var b := cb.rotated(cb.y, deg_to_rad(roll_deg))
	return Transform3D(b, palm_centre(rig, hand)) * Transform3D(Basis.IDENTITY, -(Vector3(0, t * length, 0) + _curve_offset(t)))


## Where a hand goes by default, {t, roll_deg}. Bokken: the right hand in front just below where
## the tsuba would be, the left at the back against the kashira, each palm turned inward and
## down so the hands take the tsuka from their own sides (backs of the hands up and out) as in
## aiki-ken. Jo: the same grip, right hand forward, about a forearm apart, as the usual starting
## hold before the hands slide for the technique. Tanto: one hand on the short handle.
## Roll is about the weapon axis: 0 puts the palm on the edge side, negative turns the right
## palm inward, positive the left.
const HAND_HALF_WIDTH := 0.045

func default_hold(hand: String) -> Dictionary:
	var roll := -45.0 if hand == "Right" else 45.0
	match type:
		"bokken":
			var front := (tsuka - HAND_HALF_WIDTH - 0.01) / length
			return {"t": front if hand == "Right" else HAND_HALF_WIDTH / length, "roll_deg": roll}
		"jo":
			return {"t": 0.50 if hand == "Right" else 0.28, "roll_deg": roll}
		_:
			return {"t": clampf(0.05 / length, 0.0, 1.0), "roll_deg": roll}


## Sets the hold so the weapon hangs off `rig`'s `hand` at the canonical pose.
func set_hold(rig: CharacterRig, hand: String, t: float, roll_deg: float = 0.0) -> void:
	hold = {"character": rig.character_id, "hand": hand, "t": t, "roll_deg": roll_deg,
		"offset": hold_offset(rig, hand, t, roll_deg)}


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
			var rig: CharacterRig = scene.get_character(hold["character"]) if scene else null
			hold["offset"] = hold_offset(rig, hold["hand"], float(hold["t"]), float(hold.get("roll_deg", 0.0))) if rig else Transform3D()
	if d.has("transform"):
		global_transform = PoseFile.array_to_transform(d["transform"])
	# A loaded pose is a whole state, never the middle of a playback blend.
	hold_influence = 1.0
	free_transform = global_transform


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
