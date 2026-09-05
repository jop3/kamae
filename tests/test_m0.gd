extends SceneTree
## M0 headless test: instantiate 5 characters, check bones and colours.

const EXPECTED_BONES := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"LeftThumbMetacarpal", "LeftThumbProximal", "LeftThumbDistal",
	"LeftIndexProximal", "LeftIndexIntermediate", "LeftIndexDistal",
	"LeftMiddleProximal", "LeftMiddleIntermediate", "LeftMiddleDistal",
	"LeftRingProximal", "LeftRingIntermediate", "LeftRingDistal",
	"LeftLittleProximal", "LeftLittleIntermediate", "LeftLittleDistal",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"RightThumbMetacarpal", "RightThumbProximal", "RightThumbDistal",
	"RightIndexProximal", "RightIndexIntermediate", "RightIndexDistal",
	"RightMiddleProximal", "RightMiddleIntermediate", "RightMiddleDistal",
	"RightRingProximal", "RightRingIntermediate", "RightRingDistal",
	"RightLittleProximal", "RightLittleIntermediate", "RightLittleDistal",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS ", msg)
	else:
		failures += 1
		print("FAIL ", msg)


func _initialize() -> void:
	await process_frame
	var scene := PosingScene.new()
	root.add_child(scene)
	scene.setup_default()
	for i in 3:
		scene.add_character(scene.next_free_id("uke"), "Uke %d" % (i + 2), "Uke")
	check(scene.characters.size() == 5, "five characters instantiated")
	var colors := {}
	for c in scene.characters:
		var names := c.bone_names()
		var missing := []
		for b in EXPECTED_BONES:
			if not names.has(b):
				missing.append(b)
		check(missing.is_empty(), "%s has all %d humanoid bones (missing: %s)" % [c.character_id, EXPECTED_BONES.size(), missing])
		check(c.bone_names().size() == 52, "%s has exactly 52 bones" % c.character_id)
		colors[c.get_skin_color().to_html()] = true
		var head := c.bone_world_transform("Head").origin
		check(head.y > 1.3 and head.y < 1.8, "%s head height plausible (%.2f m)" % [c.character_id, head.y])
	check(colors.size() == 5, "five distinct default skin colours")
	var bad_id := scene.next_free_id("uke")
	check(bad_id == "uke5", "next free id is uke5 (got %s)" % bad_id)
	scene.remove_character("uke4")
	check(scene.characters.size() == 4 and scene.get_character("uke4") == null, "remove_character works")
	check(scene.tori_uke_axis()["to"].distance_to(scene.tori_uke_axis()["from"]) > 0.9, "tori→uke axis spans the default 1 m gap")
	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)
