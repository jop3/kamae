extends SceneTree
## Re-seats the hands in poses that are already committed, without rebuilding the technique.
##
##   godot --headless -s tools/refit_grips.gd -- <pose slug> [<pose slug> ...]
##
## build_fixtures.gd rebuilds a technique from its script, which is right while the technique is
## being authored and wrong once a pose has been corrected by hand: ushiro ryotedori zenponage's
## Tenkan and the ryotemochi poses carry corrections the script does not have, and rebuilding
## them puts the figures back inside each other (docs/handoff.md). This loads the pose as saved,
## re-takes each hand that holds a bone with whatever the grip code does now — the seat and the
## finger curl — and writes the pose back with everything else where it was.
var scene: PosingScene
var ctrl: PoseController
var director: GripDirector
var st: Staging
const POSES := "res://poses"


func settle(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	scene = PosingScene.new(); world.add_child(scene)
	var cam := Camera3D.new(); world.add_child(cam)
	var gizmo := RotationGizmo.new(); world.add_child(gizmo)
	ctrl = PoseController.new(); world.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	director = GripDirector.new(); world.add_child(director); director.setup(scene, ctrl)
	st = Staging.new(self, scene, director, ctrl)
	await physics_frame
	for slug in OS.get_cmdline_user_args():
		var path := "%s/%s.json" % [POSES, slug]
		var data := PoseFile.load(path)
		if data.is_empty():
			push_error("cannot read %s" % path)
			continue
		PoseFile.apply(data, scene, director, ctrl)
		await settle(4)
		var refit := 0
		for grip in director.grips.duplicate():
			if grip.target.kind != GripTarget.Kind.BONE:
				continue
			var g := scene.get_character(grip.gripper_id)
			var t := scene.get_character(grip.target.character_id)
			if g == null or t == null:
				continue
			var bone: String = grip.target.bone_name
			# Where along the bone the hand is now, so the hand goes back where it was.
			var a: Vector3 = t.bone_world_transform(bone).origin
			var kids := t.skeleton.get_bone_children(t.skeleton.find_bone(bone))
			var b: Vector3 = t.bone_world_transform(t.skeleton.get_bone_name(kids[0])).origin if kids.size() > 0 else a + t.bone_world_transform(bone).basis.y * 0.2
			var palm: Vector3 = g.bone_world_transform(grip.hand + "Hand") * Weapon.palm_centre(g, grip.hand)
			var along: float = clampf((palm - a).dot(b - a) / maxf((b - a).length_squared(), 1e-9), 0.0, 1.0)
			var before: Transform3D = g.bone_world_transform(grip.hand + "Hand")
			director._remove(grip)
			# The same search a fresh grab does — which side of the bone, which way round, how
			# far the fingers close — from where this pose has already put the two bodies. A
			# hand simply re-attached where it was keeps whatever the old seat made of it.
			var new_grip := await st.grab(grip.gripper_id, grip.hand, grip.target.character_id, bone, Vector3.ZERO, along)
			await settle(4)
			refit += 1
			print("  %s %s/%s on %s %s at %.2f along: the hand moved %.1f cm"
				% [slug, grip.gripper_id, grip.hand, grip.target.character_id, bone, along,
					before.origin.distance_to(g.bone_world_transform(grip.hand + "Hand").origin) * 100.0])
			if new_grip == null:
				push_error("could not re-take %s" % grip.describe())
		await settle(4)
		var out: Dictionary = await PoseFile.capture_baked(scene, director, null, data.get("name", slug))
		var err := PoseFile.save(path, out)
		assert(err == OK, "could not write %s" % path)
		print("%s: %d grips re-seated, worst grip error %.4f" % [slug, refit, director.worst_error()])
	quit(0)
