class_name PoseFile
extends RefCounted
## Pose save/load (spec §5.5). Static helpers that turn the live scene into the JSON dictionary
## and back. Bone rotations are baked: `capture_baked` reads them inside each skeleton's
## skeleton_updated so the file holds what is on screen, IK and finger curls included.

const FORMAT := 1


## Romanised Japanese carries macrons (ō, ū) that StillExport does not fold; strip them first.
static func slugify(text: String) -> String:
	var s := text
	for pair in [["ō", "o"], ["ū", "u"], ["ā", "a"], ["ē", "e"], ["ī", "i"], ["Ō", "o"], ["Ū", "u"]]:
		s = s.replace(pair[0], pair[1])
	return StillExport.slugify(s)


static func pose_path(dir: String, name: String) -> String:
	return dir.path_join(slugify(name) + ".json")


# ---------------------------------------------------------------- transforms

static func transform_to_array(t: Transform3D) -> Array:
	var b := t.basis
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, t.origin.x, t.origin.y, t.origin.z]


static func array_to_transform(a) -> Transform3D:
	if a is Transform3D:
		return a
	if a == null or a.size() < 12:
		return Transform3D()
	return Transform3D(
		Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]),
		Vector3(a[9], a[10], a[11]))


static func vec_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func array_to_vec(a) -> Vector3:
	if a is Vector3:
		return a
	return Vector3(a[0], a[1], a[2]) if a != null and a.size() >= 3 else Vector3.ZERO


static func quat_to_array(q: Quaternion) -> Array:
	return [q.x, q.y, q.z, q.w]


static func array_to_quat(a) -> Quaternion:
	if a is Quaternion:
		return a
	return Quaternion(a[0], a[1], a[2], a[3]).normalized()


# ---------------------------------------------------------------- capture

## Synchronous capture. Bone rotations are the *authored* pose (what the instructor set in FK);
## limbs in IK mode and curled fingers are not baked. Use `capture_baked` for a file that
## reproduces the screen.
static func capture(scene: PosingScene, director: GripDirector, camera = null, name: String = "") -> Dictionary:
	var rotations := {}
	for rig in scene.characters:
		rotations[rig.character_id] = _read_rotations(rig.skeleton)
	return _assemble(scene, director, camera, name, rotations)


## Capture with rotations read post-modifier, inside each skeleton's skeleton_updated.
##
## Resumes the caller only after the next frame boundary. Reading inside the signal leaves the
## caller running inside the skeleton's update, where any bone pose it then writes is undone by
## the skeleton's pose restore (docs/engine-notes.md); a caller that captured a pose and went
## straight on to apply another would silently lose that write.
static func capture_baked(scene: PosingScene, director: GripDirector, camera = null, name: String = "") -> Dictionary:
	var rotations := {}
	for rig in scene.characters:
		rotations[rig.character_id] = await _read_rotations_baked(rig.skeleton)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		await tree.process_frame
	return _assemble(scene, director, camera, name, rotations)


static func _read_rotations(sk: Skeleton3D) -> Dictionary:
	var out := {}
	for i in sk.get_bone_count():
		out[sk.get_bone_name(i)] = sk.get_bone_pose_rotation(i)
	return out


static func _read_rotations_baked(sk: Skeleton3D) -> Dictionary:
	# Lambdas capture locals by value; write into a Dictionary (see docs/engine-notes.md).
	var box := {}
	var grab := func(): box["rot"] = _read_rotations(sk)
	sk.skeleton_updated.connect(grab, CONNECT_ONE_SHOT)
	await sk.skeleton_updated
	return box.get("rot", {})


static func _assemble(scene: PosingScene, director: GripDirector, camera, name: String, rotations: Dictionary) -> Dictionary:
	var characters := []
	for rig in scene.characters:
		var bones := {}
		var rots: Dictionary = rotations.get(rig.character_id, {})
		for bone in rots:
			bones[bone] = quat_to_array(rots[bone])
		var ik := {}
		for key in rig.limbs:
			var limb: Limb = rig.limbs[key]
			ik[key] = {
				"mode": "ik" if limb.mode == Limb.Mode.IK else "fk",
				"target": transform_to_array(limb.target.global_transform),
				"pole": vec_to_array(limb.pole.global_position),
				"orient": limb.orient_to_target,
			}
		var fingers := {}
		for side in FingerCurl.SIDES:
			fingers[side] = rig.fingers.curls[side].duplicate()
		characters.append({
			"id": rig.character_id,
			"name": rig.display_name,
			"role": rig.role,
			"skin_color": "#" + rig.get_skin_color().to_html(false),
			"visible": rig.visible,
			"root": {"pos": vec_to_array(rig.position), "yaw": rig.rotation.y},
			"bones": bones,
			"ik": ik,
			"fingers": fingers,
		})
	var grips := []
	if director:
		for grip in director.grips:
			var d: Dictionary = grip.to_dict()
			d["offset"] = transform_to_array(grip.offset)
			grips.append(d)
	var weapons := []
	if "weapons" in scene:
		for w in scene.get("weapons"):
			if w != null and w.has_method("to_dict"):
				weapons.append(w.to_dict())
	return {
		"format": FORMAT,
		"name": name,
		"characters": characters,
		"weapons": weapons,
		"grips": grips,
		"camera": camera.state() if camera != null and camera.has_method("state") else null,
	}


# ---------------------------------------------------------------- apply

## Rebuilds the scene from `data`. Must be called from ordinary code (not inside
## skeleton_updated), since bone writes made during the signal are undone by the pose restore.
static func apply(data: Dictionary, scene: PosingScene, director: GripDirector, _controller: PoseController = null, camera = null) -> void:
	if camera != null and camera.has_method("apply_state") and data.get("camera") is Dictionary:
		camera.apply_state(data["camera"])
	var chars: Array = data.get("characters", [])
	var wanted := {}
	for c in chars:
		wanted[c["id"]] = true
	if director:
		director.clear()
	for rig in scene.characters.duplicate():
		if not wanted.has(rig.character_id):
			scene.remove_character(rig.character_id)
	for c in chars:
		var rig: CharacterRig = scene.get_character(c["id"])
		if rig == null:
			rig = scene.add_character(c["id"], c.get("name", c["id"]), c.get("role", "Other"))
		rig.display_name = c.get("name", rig.display_name)
		rig.role = c.get("role", rig.role)
		if c.has("skin_color"):
			rig.set_skin_color(Color.html(c["skin_color"]))
		rig.visible = c.get("visible", true)
		var root: Dictionary = c.get("root", {})
		rig.position = array_to_vec(root.get("pos", [0, 0, 0]))
		rig.rotation = Vector3(0, root.get("yaw", 0.0), 0)
		var sk := rig.skeleton
		var bones: Dictionary = c.get("bones", {})
		for bone in bones:
			var idx := sk.find_bone(bone)
			if idx >= 0:
				sk.set_bone_pose_rotation(idx, array_to_quat(bones[bone]))
		var fingers: Dictionary = c.get("fingers", {})
		for side in fingers:
			for finger in fingers[side]:
				rig.fingers.set_curl(side, finger, fingers[side][finger])
		var ik: Dictionary = c.get("ik", {})
		for key in ik:
			if not rig.limbs.has(key):
				continue
			var limb: Limb = rig.limbs[key]
			var entry: Dictionary = ik[key]
			var mode := Limb.Mode.IK if entry.get("mode", "fk") == "ik" else Limb.Mode.FK
			rig.set_limb_mode(key, mode)
			if entry.has("target"):
				limb.target.global_transform = array_to_transform(entry["target"])
			if entry.has("pole"):
				limb.pole.global_position = array_to_vec(entry["pole"])
			limb.set_orient_to_target(entry.get("orient", false))
	# Weapons before grips, so weapon-kind grips resolve their target.
	var weapons_data: Array = data.get("weapons", [])
	var wanted_weapons := {}
	for wd in weapons_data:
		wanted_weapons[wd["id"]] = true
	for w in scene.weapons.duplicate():
		if not wanted_weapons.has(w.weapon_id):
			scene.remove_weapon(w.weapon_id)
	for wd in weapons_data:
		var weapon: Weapon = scene.get_weapon(wd["id"])
		if weapon == null:
			weapon = scene.add_weapon(wd["id"], wd.get("type", "bokken"))
		weapon.apply_dict(wd)
	if director:
		director.refresh_hand_driven()
		for g in data.get("grips", []):
			var d: Dictionary = g.duplicate()
			d["offset"] = array_to_transform(d.get("offset", null))
			director._add(Grip.from_dict(scene, d))


# ---------------------------------------------------------------- files

static func save(path: String, data: Dictionary) -> Error:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			return err
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return OK


## Empty dictionary on any failure.
static func load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("PoseFile: cannot open %s" % path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		push_error("PoseFile: %s is not a pose file" % path)
		return {}
	if int(parsed.get("format", 0)) != FORMAT:
		push_error("PoseFile: unsupported format %s" % str(parsed.get("format")))
		return {}
	return parsed
