extends SceneTree
## The attack catalogue (data/attacks.json, src/posing/Attacks.gd): every attack has its names
## and its geometry, and every one stages into a pose whose grips are on their points and whose
## gripping arms the joints allow. ATTACKS_VERBOSE=1 prints where each Uke ended up, which is
## where the numbers in docs/attacks.md come from.

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)

var scene: PosingScene
var ctrl: PoseController
var director: GripDirector
const STYLES := ["short", "aikikai", "iwama", "yoshinkan", "ki", "tomiki", "english", "swedish"]


func _initialize() -> void:
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	scene = PosingScene.new(); world.add_child(scene)
	var cam := Camera3D.new(); world.add_child(cam)
	var gizmo := RotationGizmo.new(); world.add_child(gizmo)
	ctrl = PoseController.new(); world.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	director = GripDirector.new(); world.add_child(director); director.setup(scene, ctrl)
	await physics_frame
	scene.add_character("tori", "Tori", "Tori")
	scene.add_character("uke1", "Uke", "Uke")
	await process_frame
	var st := Staging.new(self, scene, director, ctrl)
	var verbose := OS.get_environment("ATTACKS_VERBOSE") == "1"

	check(Attacks.keys().size() >= 21, "the catalogue has the attacks a syllabus starts from (%d)" % Attacks.keys().size())
	for key in Attacks.keys():
		var e := Attacks.entry(key)
		var complete := true
		for s in STYLES:
			if not e.get("names", {}).has(s):
				complete = false
		check(complete and e.has("tori") and e.has("uke") and e.has("grips") and e.has("description"), "%s: named in every school and fully described" % key)
	var only := OS.get_environment("ATTACK")
	for key in Attacks.keys():
		if only != "" and key != only:
			continue
		for mirror in [false, true]:
			if mirror and key != "katatedori":
				continue   # one attack checked on both sides is enough to show mirroring works
			var report: Dictionary = await Attacks.stage(st, key, {"mirror": mirror})
			var tori: CharacterRig = scene.get_character("tori")
			var uke: CharacterRig = scene.get_character("uke1")
			var label: String = key + (" (mirror)" if mirror else "")
			var grips := director.grips_for("uke1")
			var e := Attacks.entry(key)
			check(grips.size() == e["grips"].size(), "%s: %d grip(s) attached" % [label, grips.size()])
			if not grips.is_empty():
				check(report["grip_error"] < 0.012, "%s: every gripping hand is on its point (worst %.3f m)" % [label, report["grip_error"]])
				check(report["refused"].is_empty(), "%s: the gripping arms are within their joints (%s)" % [label, ", ".join(report["refused"])])
			var uke_hands_ok := true
			for line in uke.joint_limits.report():
				if "Hand" in line or "Arm" in line:
					uke_hands_ok = false
			check(uke_hands_ok, "%s: nothing refused in Uke's arms (%s)" % [label, ", ".join(uke.joint_limits.report())])
			if e["uke"].has("weapons"):
				check(scene.weapons.size() == e["uke"]["weapons"].size() and director.worst_error() < 0.012, "%s: the weapon is in Uke's hand (%d weapons, error %.3f)" % [label, scene.weapons.size(), director.worst_error()])
			if e["uke"].has("feet"):
				var lifted := false
				for side in e["uke"]["feet"]:
					if uke.bone_world_transform(side + "Foot").origin.y > 0.25:
						lifted = true
				check(lifted, "%s: the kicking foot is up" % label)
			var through := PackedStringArray()
			for p in Anatomy.scene_problems(scene, director):
				# A choke's forearm lies across the throat and the shoulder by design, and a hand in
				# the collar has its forearm on the shoulder.
				var by_design: bool = key in ["ushiro_kubishime", "eridori", "ushiro_eridori"] and ("Neck" in p or "Shoulder" in p)
				if "passes through" in p and not by_design:
					through.append(p)
			check(through.is_empty(), "%s: nobody passes through anybody (%s)" % [label, ", ".join(through)])
			for r in [tori, uke]:
				var feet_ok := true
				for side in ["Right", "Left"]:
					if r == uke and e["uke"].get("feet", {}).has(side):
						continue   # a kicking foot is off the mat by design
					var y: float = r.bone_world_transform(side + "Toes").origin.y
					if y < -0.02 or y > 0.08:
						feet_ok = false
				check(feet_ok, "%s: %s stands on the mat" % [label, r.character_id])
			if verbose:
				var d: float = uke.global_position.distance_to(tori.global_position)
				print("  %s: Uke at (%.2f, %.2f), %.2f m from Tori, moved %.2f m; grips %d, worst %.3f; refused %s"
					% [label, report["uke_position"].x, report["uke_position"].z, d, report["uke_offset"], grips.size(), report["grip_error"], report["refused"]])
	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)
