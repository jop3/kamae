class_name PoseBlend
extends RefCounted
## Puts the scene at a point between two saved poses (spec §5.6).
##
## Rules, in the spec's words: root position lerps and yaw slerps; FK bones slerp; finger curls
## lerp; weapon transforms lerp and slerp and a hold's t and roll lerp; a limb whose grip is
## active in both poses stays in IK and is re-solved live from the moving grip; a grip present
## in only one pose ramps its IK influence 0→1 (appearing) or 1→0 (disappearing) while the FK
## rotations slerp underneath. Nothing here touches undo: a preview is not an edit.


## Applies the blend for `u` in 0..1 between pose dictionaries `a` and `b` (PoseFile format).
## Characters and weapons are matched by id; both poses are expected to contain the same ids.
static func apply(scene: PosingScene, director: GripDirector, a: Dictionary, b: Dictionary, u: float) -> void:
	u = clampf(u, 0.0, 1.0)
	var chars_a := _by_id(a.get("characters", []))
	var chars_b := _by_id(b.get("characters", []))
	var grips_a := _grips_by_key(a)
	var grips_b := _grips_by_key(b)
	for id in _union(chars_a.keys(), chars_b.keys()):
		var rig: CharacterRig = scene.get_character(id)
		if rig == null:
			continue
		var ca: Dictionary = chars_a.get(id, chars_b.get(id))
		var cb: Dictionary = chars_b.get(id, chars_a.get(id))
		_apply_character(rig, ca, cb, u, grips_a, grips_b)
	var holds_before := _hold_signature(scene)
	_apply_weapons(scene, a, b, u)
	_apply_grips(scene, director, a, b, u, grips_a, grips_b)
	if director and _hold_signature(scene) != holds_before:
		director.rebuild()
	if director:
		director.refresh_hand_driven()


## Makes sure every character and weapon named by any of `poses` exists in the scene, so a
## figure or weapon that first appears in a later step is there to be blended into.
static func ensure_entities(scene: PosingScene, poses: Array) -> void:
	for pose in poses:
		for c in pose.get("characters", []):
			if scene.get_character(c["id"]) == null and scene.characters.size() < PosingScene.MAX_CHARACTERS:
				var rig := scene.add_character(c["id"], c.get("name", c["id"]), c.get("role", "Other"))
				if c.has("skin_color"):
					rig.set_skin_color(Color.html(c["skin_color"]))
		for wd in pose.get("weapons", []):
			if scene.get_weapon(wd["id"]) == null:
				var w := scene.add_weapon(wd["id"], wd.get("type", "bokken"))
				w.apply_dict(wd)


## Who holds what: when this changes the director must re-derive its order and connections.
static func _hold_signature(scene: PosingScene) -> Array:
	var sig := []
	for w in scene.weapons:
		sig.append([w.weapon_id, w.drive, w.hold.get("character", ""), w.hold.get("hand", "")])
	return sig


static func _apply_character(rig: CharacterRig, ca: Dictionary, cb: Dictionary, u: float, grips_a: Dictionary, grips_b: Dictionary) -> void:
	var ra: Dictionary = ca.get("root", {})
	var rb: Dictionary = cb.get("root", {})
	rig.position = PoseFile.array_to_vec(ra.get("pos", [0, 0, 0])).lerp(PoseFile.array_to_vec(rb.get("pos", [0, 0, 0])), u)
	rig.rotation = Vector3(0, lerp_angle(float(ra.get("yaw", 0.0)), float(rb.get("yaw", 0.0)), u), 0)
	var sk := rig.skeleton
	var bones_a: Dictionary = ca.get("bones", {})
	var bones_b: Dictionary = cb.get("bones", {})
	for bone in _union(bones_a.keys(), bones_b.keys()):
		var idx := sk.find_bone(bone)
		if idx < 0:
			continue
		var qa := PoseFile.array_to_quat(bones_a.get(bone, bones_b.get(bone)))
		var qb := PoseFile.array_to_quat(bones_b.get(bone, bones_a.get(bone)))
		sk.set_bone_pose_rotation(idx, qa.slerp(qb, u).normalized())
	var fa: Dictionary = ca.get("fingers", {})
	var fb: Dictionary = cb.get("fingers", {})
	for side in FingerCurl.SIDES:
		for finger in FingerCurl.FINGERS:
			var va: float = float(fa.get(side, {}).get(finger, 0.0))
			var vb: float = float(fb.get(side, {}).get(finger, 0.0))
			rig.fingers.set_curl(side, finger, lerpf(va, vb, u))
	# Limbs. A gripped limb is handled by the grip rules; otherwise blend the IK state.
	var ik_a: Dictionary = ca.get("ik", {})
	var ik_b: Dictionary = cb.get("ik", {})
	for key in rig.limbs:
		var limb: Limb = rig.limbs[key]
		var grip_key := "%s/%s" % [rig.character_id, key.trim_suffix("Arm")]
		var in_a := grips_a.has(grip_key)
		var in_b := grips_b.has(grip_key)
		if in_a or in_b:
			# The grip director drives the target. Ramp the influence for a one-sided grip; a
			# grip that changes target between the poses is a release and a new grip, so it
			# ramps out and back in while the FK slerp carries the hand across.
			rig.set_limb_mode(key, Limb.Mode.IK)
			limb.set_orient_to_target(true)
			var influence := 1.0
			if in_a and in_b:
				if not _same_target(grips_a[grip_key], grips_b[grip_key]):
					influence = absf(2.0 * u - 1.0)
			else:
				influence = 1.0 - u if in_a else u
			limb.set_influence(influence)
			continue
		var ea: Dictionary = ik_a.get(key, {})
		var eb: Dictionary = ik_b.get(key, {})
		var ik_in_a: bool = ea.get("mode", "fk") == "ik"
		var ik_in_b: bool = eb.get("mode", "fk") == "ik"
		if not ik_in_a and not ik_in_b:
			rig.set_limb_mode(key, Limb.Mode.FK)
			limb.set_influence(1.0)
			continue
		rig.set_limb_mode(key, Limb.Mode.IK)
		var ta := PoseFile.array_to_transform(ea.get("target", eb.get("target")))
		var tb := PoseFile.array_to_transform(eb.get("target", ea.get("target")))
		limb.target.global_transform = ta.interpolate_with(tb, u)
		var pa := PoseFile.array_to_vec(ea.get("pole", eb.get("pole", [0, 0, 0])))
		var pb := PoseFile.array_to_vec(eb.get("pole", ea.get("pole", [0, 0, 0])))
		limb.pole.global_position = pa.lerp(pb, u)
		limb.set_orient_to_target(bool(ea.get("orient", eb.get("orient", false))))
		limb.set_influence(1.0 if (ik_in_a and ik_in_b) else (1.0 - u if ik_in_a else u))


static func _apply_weapons(scene: PosingScene, a: Dictionary, b: Dictionary, u: float) -> void:
	var wa := _by_id(a.get("weapons", []))
	var wb := _by_id(b.get("weapons", []))
	for id in _union(wa.keys(), wb.keys()):
		var weapon: Weapon = scene.get_weapon(id)
		if weapon == null:
			continue
		var da: Dictionary = wa.get(id, wb.get(id))
		var db: Dictionary = wb.get(id, wa.get(id))
		var xa := PoseFile.array_to_transform(da.get("transform"))
		var xb := PoseFile.array_to_transform(db.get("transform"))
		weapon.free_transform = xa.interpolate_with(xb, u)
		var ha: Dictionary = da.get("hold", {})
		var hb: Dictionary = db.get("hold", {})
		var held_a: bool = da.get("drive", "hand") == "hand" and not ha.is_empty()
		var held_b: bool = db.get("drive", "hand") == "hand" and not hb.is_empty()
		var same_holder: bool = held_a and held_b and ha.get("character") == hb.get("character") and ha.get("hand") == hb.get("hand")
		if same_holder:
			weapon.drive = "hand"
			var rig: CharacterRig = scene.get_character(ha["character"])
			var oa := PoseFile.array_to_transform(ha.get("offset"))
			var ob := PoseFile.array_to_transform(hb.get("offset"))
			weapon.hold = {"character": ha["character"], "hand": ha["hand"],
				"t": lerpf(float(ha.get("t", 0.0)), float(hb.get("t", 0.0)), u),
				"roll_deg": lerpf(float(ha.get("roll_deg", 0.0)), float(hb.get("roll_deg", 0.0)), u),
				"offset": oa.interpolate_with(ob, u)}
			weapon.hold_influence = 1.0
			if rig == null:
				weapon.drive = "weapon"
		elif held_a and held_b:
			# Handed from one hand to another: the first hold lets go over the first half, the
			# second takes over during the second half, the free transform bridging between.
			var h: Dictionary = ha if u < 0.5 else hb
			weapon.drive = "hand"
			weapon.hold = h.duplicate()
			weapon.hold["offset"] = PoseFile.array_to_transform(h.get("offset"))
			weapon.hold_influence = absf(2.0 * u - 1.0)
		elif held_a or held_b:
			# Held in one pose only (a disarm, a hand-over to nobody): the hand's influence ramps.
			var h: Dictionary = ha if held_a else hb
			weapon.drive = "hand"
			weapon.hold = h.duplicate()
			weapon.hold["offset"] = PoseFile.array_to_transform(h.get("offset"))
			weapon.hold_influence = 1.0 - u if held_a else u
		else:
			weapon.drive = "weapon"
			weapon.hold = {}
			weapon.hold_influence = 1.0
			weapon.global_transform = weapon.free_transform


## Keeps the director's grip list equal to the union of both poses' grips. Grips in both keep
## pose a's target and blend their offsets; one-sided grips keep their own.
static func _apply_grips(scene: PosingScene, director: GripDirector, a: Dictionary, b: Dictionary, u: float, grips_a: Dictionary, grips_b: Dictionary) -> void:
	if director == null:
		return
	var wanted := {}
	for key in _union(grips_a.keys(), grips_b.keys()):
		var ga: Dictionary = grips_a.get(key, {})
		var gb: Dictionary = grips_b.get(key, {})
		var src: Dictionary = ga if not ga.is_empty() else gb
		var d: Dictionary = src.duplicate(true)
		if not ga.is_empty() and not gb.is_empty() and _same_target(ga, gb):
			d["offset"] = PoseFile.array_to_transform(ga.get("offset")).interpolate_with(PoseFile.array_to_transform(gb.get("offset")), u)
		elif not ga.is_empty() and not gb.is_empty():
			d = (ga if u < 0.5 else gb).duplicate(true)
			d["offset"] = PoseFile.array_to_transform(d.get("offset"))
		else:
			d["offset"] = PoseFile.array_to_transform(d.get("offset"))
		wanted[key] = d
	# Reuse existing grip objects where the key matches, so the director is not rebuilt per frame.
	var existing := {}
	for grip in director.grips:
		existing["%s/%s" % [grip.gripper_id, grip.hand]] = grip
	for key in existing:
		if not wanted.has(key):
			director._remove(existing[key])
	for key in wanted:
		var d: Dictionary = wanted[key]
		var grip: Grip = existing.get(key)
		if grip and grip.target.to_dict() == d["target"]:
			grip.offset = d["offset"]
		else:
			if grip:
				director._remove(grip)
			director._add(Grip.from_dict(scene, d))


static func _same_target(ga: Dictionary, gb: Dictionary) -> bool:
	return ga.get("target") == gb.get("target")


static func _grips_by_key(pose: Dictionary) -> Dictionary:
	var out := {}
	for g in pose.get("grips", []):
		out["%s/%s" % [g.get("gripper"), g.get("hand")]] = g
	return out


static func _by_id(list: Array) -> Dictionary:
	var out := {}
	for item in list:
		out[item.get("id")] = item
	return out


static func _union(x: Array, y: Array) -> Array:
	var out: Array = x.duplicate()
	for item in y:
		if not item in out:
			out.append(item)
	return out
