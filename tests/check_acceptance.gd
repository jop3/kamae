extends SceneTree
## Acceptance checks over the committed poses/ and sequences/ (spec §8), headless. Loads every
## pose, lets the grips settle and asserts the mechanics the spec names. Visual judgement of
## the techniques themselves is the instructor's.

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)

var scene: PosingScene
var ctrl: PoseController
var director: GripDirector
const POSES := "res://poses"
const SEQUENCES := "res://sequences"
## Poses where a gripping hand is meant to be out of reach (spec 8.2: the reach warning case).
const EXPECTED_SHORT := ["ushiro_ryotedori_zenponage_kake"]


func _initialize() -> void:
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	scene = PosingScene.new(); world.add_child(scene)
	var cam := Camera3D.new(); world.add_child(cam)
	var gizmo := RotationGizmo.new(); world.add_child(gizmo)
	ctrl = PoseController.new(); world.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	director = GripDirector.new(); world.add_child(director); director.setup(scene, ctrl)
	await physics_frame

	var seq_files := _files(SEQUENCES)
	check(seq_files.size() >= 8, "eight acceptance sequences are committed (%d)" % seq_files.size())
	var referenced := {}
	for f in seq_files:
		var seq := Sequence.load(SEQUENCES.path_join(f))
		check(seq != null and seq.steps.size() >= 2 and seq.steps.size() <= 5, "%s has 2-5 steps" % f)
		if seq:
			for st in seq.steps:
				referenced[st["pose"]] = referenced.get(st["pose"], 0) + 1
				check(FileAccess.file_exists(POSES.path_join(st["pose"] + ".json")), "%s: pose %s exists" % [f, st["pose"]])
	check(referenced.get("katatedori_ikkyo_grepp", 0) >= 2, "Grepp is literally reused by Ikkyo and Shihonage (%d references)" % referenced.get("katatedori_ikkyo_grepp", 0))

	for f in _files(POSES):
		var slug: String = f.get_basename()
		var data := PoseFile.load(POSES.path_join(f))
		if data.is_empty():
			check(false, "%s loads" % f)
			continue
		PoseFile.apply(data, scene, director, ctrl)
		await settle(4)
		# Every character in a grip has a colour distinct from the one it grips.
		var colours_ok := true
		for grip in director.grips:
			if grip.target.kind == GripTarget.Kind.BONE:
				var a := scene.get_character(grip.gripper_id).get_skin_color()
				var b := scene.get_character(grip.target.character_id).get_skin_color()
				if a.is_equal_approx(b):
					colours_ok = false
		# Grips are exact unless the pose is the deliberate out-of-reach case.
		var worst := 0.0
		var worst_desc := ""
		for grip in director.grips:
			var e := director.error_for(grip)
			if e > worst:
				worst = e
				worst_desc = grip.describe()
		if slug in EXPECTED_SHORT:
			check(worst > 0.2, "%s: the thrown Uke is out of reach and the warning would show (%.2f m short)" % [slug, worst])
		else:
			check(worst < 0.012, "%s: every gripping hand is on its point (worst %.3f m, %s)" % [slug, worst, worst_desc])
		check(colours_ok, "%s: gripping hand and gripped limb have different colours" % slug)
		# Hand-driven weapons sit in their holder's palm.
		for w in scene.weapons:
			if w.drive == "hand" and not w.hold.is_empty():
				var holder := scene.get_character(w.hold["character"])
				var palm: Vector3 = holder.bone_world_transform(w.hold["hand"] + "Hand") * Weapon.palm_centre(holder, w.hold["hand"])
				check(w.anchor_transform(w.hold["t"]).origin.distance_to(palm) < 0.06, "%s: %s is in %s's palm (%.3f m)" % [slug, w.weapon_id, w.hold["character"], w.anchor_transform(w.hold["t"]).origin.distance_to(palm)])
		for c in scene.weapon_contacts:
			var a: Weapon = scene.get_weapon(c["a"]); var b: Weapon = scene.get_weapon(c["b"])
			if a and b:
				var gap := director.contact_gap(a, c["t_a"], b, c["t_b"])
				check(gap < 0.01, "%s: weapon contact gap under 1 cm (%.4f m)" % [slug, gap])
		if slug.begins_with("jo_dori") or slug.begins_with("kumijo"):
			var jo: Weapon = scene.get_weapon("jo1")
			var chin: float = scene.get_character("tori").bone_world_transform("Neck").origin.y
			check(jo != null and absf(jo.length - chin) < 0.15, "%s: the jo stood on end reaches about chin height (jo %.2f m, chin %.2f m)" % [slug, jo.length if jo else 0.0, chin])

	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


func _files(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d:
		for f in d.get_files():
			if f.ends_with(".json"):
				out.append(f)
	out.sort()
	return out


func settle(frames: int = 2) -> void:
	for i in frames:
		await process_frame
