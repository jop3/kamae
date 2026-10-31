extends SceneTree
## Technique scripts (src/posing/TechniqueScript.gd): a technique written as data builds into
## poses and a sequence, and each move does what its name says in the figure's own frame —
## a step lands where it was sent, a pivot turns the body and the planted foot with it, a grip
## holds, a fall ends on the mat. Also the realistic look (CharacterRig.set_appearance) and that
## it survives a save and load.

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)

const OUT := "res://tests/out/technique_script"


func _initialize() -> void:
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	var scene := PosingScene.new(); world.add_child(scene)
	var cam := Camera3D.new(); world.add_child(cam)
	var gizmo := RotationGizmo.new(); world.add_child(gizmo)
	var ctrl := PoseController.new(); world.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	var director := GripDirector.new(); world.add_child(director); director.setup(scene, ctrl)
	await physics_frame
	var ts := TechniqueScript.new(self, scene, director, ctrl)

	# Every committed script parses and names only moves the interpreter knows.
	var d := DirAccess.open("res://techniques")
	var scripts := []
	for f in d.get_files():
		if f.ends_with(".json"):
			scripts.append(f)
	check(scripts.size() >= 2, "techniques/ has scripts (%d)" % scripts.size())
	var verbs := ["attack", "from_pose", "place", "move", "pivot", "turn_foot", "step", "hanmi", "drop_hips",
		"kneel", "stand", "lean", "bend", "straighten", "hand", "elbow", "arm_down", "grab", "release",
		"fingers", "ukemi", "ground", "weapon", "settle"]
	for f in scripts:
		var s := TechniqueScript.load_file("res://techniques".path_join(f))
		var unknown := []
		for ph: Dictionary in s.get("phases", []):
			for m: Dictionary in ph.get("do", []):
				if not verbs.any(func(v): return m.has(v)):
					unknown.append(JSON.stringify(m))
		check(not s.is_empty() and s.has("name") and unknown.is_empty(), "%s parses, every move known %s" % [f, unknown])

	var script := {
		"name": "Test Tenkan",
		"phases": [
			{"name": "Grepp", "do": [{"attack": "katatedori"}]},
			{"name": "Irimi", "do": [{"step": "tori.Right", "to": "uke1.LeftFoot", "offset": [-0.18, 0.05], "weight": 0.75}]},
			{"name": "Tenkan", "do": [{"pivot": "tori", "foot": "Right", "deg": 180}]},
			{"name": "Ukemi", "allow_short": true, "do": [{"release": "uke1"}, {"ukemi": "uke1", "kind": "backward", "t": 0.5}]},
		],
	}
	var tori_yaw_before := 0.0
	var report: Dictionary = await ts.run(script, OUT)
	check(report["errors"].is_empty(), "built without errors %s" % [report["errors"]])
	check(report["phases"].size() == 4, "a pose per phase")
	var seq := Sequence.load(report["sequence"])
	check(seq != null and seq.steps.size() == 4, "a sequence of the four poses")

	var poses := {}
	for ph in report["phases"]:
		poses[ph["pose"]] = PoseFile.load(ph["path"])
	var grepp: Dictionary = poses["Test Tenkan Grepp"]
	var irimi: Dictionary = poses["Test Tenkan Irimi"]
	var tenkan: Dictionary = poses["Test Tenkan Tenkan"]
	check(grepp["grips"].size() == 1, "Grepp: Uke holds Tori's wrist")
	check(tenkan["grips"].size() == 1, "Tenkan: the grip is kept through the turn")

	# Faces: each saved pose has the two looking at each other, within the neck's range.
	PoseFile.apply(grepp, scene, director, ctrl)
	await settle(4)
	for pair in [["tori", "uke1"], ["uke1", "tori"]]:
		var a := scene.get_character(pair[0])
		var b := scene.get_character(pair[1])
		var h := a.bone_world_transform("Head")
		var rest := a.skeleton.global_transform.basis * a.skeleton.get_bone_global_rest(a.skeleton.find_bone("Head")).basis
		var face: Vector3 = h.basis.orthonormalized() * (rest.orthonormalized().inverse() * a.global_transform.basis.z.normalized())
		var to: Vector3 = (b.bone_world_transform("Head").origin - h.origin).normalized()
		check(rad_to_deg(face.angle_to(to)) < 25.0, "Grepp: %s looks at %s (%.0f° off)" % [pair[0], pair[1], rad_to_deg(face.angle_to(to))])
	var necks := Array(Anatomy.scene_problems(scene, director)).filter(func(p: String): return p.contains("Neck") or p.contains(": Head:"))
	check(necks.is_empty(), "Grepp: the look stays inside the neck's range %s" % [necks])

	# The step lands beside Uke's front foot, and the pivot turns Tori half round on it.
	PoseFile.apply(irimi, scene, director, ctrl)
	await settle(4)
	var tori := scene.get_character("tori")
	var uke := scene.get_character("uke1")
	var foot: Vector3 = tori.bone_world_transform("RightFoot").origin
	var uke_foot: Vector3 = uke.bone_world_transform("LeftFoot").origin
	var gap := Vector2(foot.x - uke_foot.x, foot.z - uke_foot.z).length()
	check(gap > 0.08 and gap < 0.35, "Irimi: Tori's right foot beside Uke's left (%.2f m)" % gap)
	tori_yaw_before = tori.rotation.y
	var planted := foot
	PoseFile.apply(tenkan, scene, director, ctrl)
	await settle(4)
	var turned := absf(wrapf(tori.rotation.y - tori_yaw_before, -PI, PI))
	check(absf(turned - PI) < 0.05, "Tenkan: Tori turned 180° (%.0f°)" % rad_to_deg(turned))
	var foot_after: Vector3 = tori.bone_world_transform("RightFoot").origin
	check(Vector2(foot_after.x - planted.x, foot_after.z - planted.z).length() < 0.08, "Tenkan: the pivot foot stayed where it was")
	var probs := Anatomy.scene_problems(scene, director)
	var ankles := Array(probs).filter(func(p: String): return p.contains("tori: RightFoot"))
	check(ankles.is_empty(), "Tenkan: the pivot foot turned with the body, no twisted ankle %s" % [ankles])
	# Both now face the way Uke faces.
	var facing := absf(wrapf(tori.rotation.y - uke.rotation.y, -PI, PI))
	check(facing < deg_to_rad(40), "Tenkan: Tori faces the way Uke does (%.0f° apart)" % rad_to_deg(facing))

	PoseFile.apply(poses["Test Tenkan Ukemi"], scene, director, ctrl)
	await settle(4)
	check(director.grips.is_empty(), "Ukemi: the grip is released")
	var lowest := INF
	for seg: Array in Anatomy.segments(uke).values():
		lowest = minf(lowest, minf(seg[0].y, seg[1].y) - seg[2])
	check(absf(lowest) < 0.03, "Ukemi: Uke rests on the mat (lowest %.3f m)" % lowest)

	# Directions are in the figure's frame: "right" is the figure's right whichever way it faces.
	await ts.do_move({"place": "tori", "at": [0.0, 0.0], "yaw": 90})
	await ts.do_move({"place": "uke1", "of": "tori", "at": [1.0, 0.0], "facing": 180})
	await settle(3)
	var right_of_tori: Vector3 = -tori.global_transform.basis.x
	var to_uke: Vector3 = uke.global_position - tori.global_position
	to_uke.y = 0.0
	check(to_uke.normalized().dot(right_of_tori.normalized()) > 0.99, "place: [1, 0] is a metre to the figure's right")
	check(absf(wrapf(uke.rotation.y - tori.rotation.y - PI, -PI, PI)) < 0.01, "place: facing 180 turns Uke against Tori")

	# The realistic look: textured skin, eyes and one hair style; the mannequin look hides them.
	check(tori.skin_material.albedo_texture != null, "realistic look: the skin is a texture")
	var hair_shown := tori.hair_meshes.values().filter(func(m): return m.visible).size()
	check(hair_shown == 1, "realistic look: one hair style shown (%d)" % hair_shown)
	check(tori.face_parts.size() == 3 and tori.face_parts.all(func(m): return m.visible), "realistic look: eyes, brows and lashes shown")
	tori.set_appearance({"hair": "bob02", "skin": "old_caucasian_male"})
	var saved := PoseFile.capture(scene, director)
	tori.set_appearance({"look": "mannequin"})
	check(tori.skin_material.albedo_texture == null and tori.face_parts.all(func(m): return not m.visible), "mannequin look: flat skin, no face parts")
	check(tori.skin_material.albedo_color == tori.get_skin_color(), "mannequin look: the skin is the identification colour")
	PoseFile.apply(saved, scene, director, ctrl)
	await settle(2)
	check(tori.appearance.get("look") == "realistic" and tori.appearance.get("hair") == "bob02", "the look is saved with the pose and restored")
	check(tori.hair_meshes["bob02"].visible, "restored hair style shown")

	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


func settle(frames: int = 2) -> void:
	for i in frames:
		await process_frame
