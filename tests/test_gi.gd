extends SceneTree
## The gi (M9): built on demand from the mannequin, skinned with its weights, cut to the pieces
## a keikogi has, coloured belt, toggled per character and saved with the pose.

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)


func _initialize() -> void:
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	var scene := PosingScene.new(); world.add_child(scene); scene.setup_default()
	var director := GripDirector.new(); world.add_child(director); director.setup(scene, null)
	await physics_frame
	var tori: CharacterRig = scene.get_character("tori")
	check(tori.gi == null and not tori.gi_visible, "a character starts without a gi")
	tori.set_gi_visible(true)
	check(tori.gi != null and tori.gi.jacket.visible, "asking for the gi builds and shows it")
	var jm: ArrayMesh = tori.gi.jacket.mesh
	var tm: ArrayMesh = tori.gi.trousers.mesh
	check(jm.get_surface_count() == 1 and jm.surface_get_array_len(0) > 1000, "the jacket is a real mesh (%d vertices)" % (jm.surface_get_array_len(0) if jm.get_surface_count() > 0 else 0))
	check(tm.get_surface_count() == 1 and tm.surface_get_array_len(0) > 1000, "the trousers are a real mesh (%d vertices)" % (tm.surface_get_array_len(0) if tm.get_surface_count() > 0 else 0))
	check(tori.gi.jacket.skin == tori.body.skin, "the cloth shares the body's skin binds")
	# Every jacket vertex stands off the body: within the cloth offsets of the mannequin's
	# rest surface, never below the hem or above the collar.
	var jv: PackedVector3Array = jm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lo := INF; var hi := -INF
	for v in jv:
		lo = minf(lo, v.y); hi = maxf(hi, v.y)
	check(lo > Gi.JACKET_HEM_Y - 0.035 and hi < Gi.COLLAR_Y + 0.035, "the jacket runs from its hem to the collar (%.2f..%.2f m)" % [lo, hi])
	var tv: PackedVector3Array = tm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	lo = INF; hi = -INF
	for v in tv:
		lo = minf(lo, v.y); hi = maxf(hi, v.y)
	check(lo > Gi.TROUSER_HEM_Y - 0.02 and hi < Gi.TROUSER_TOP_Y + 0.02, "the trousers run from the ankle hem to the waist (%.2f..%.2f m)" % [lo, hi])
	# Nothing on the head, hands or feet.
	var bare := 0
	for v in jv:
		if v.y > Gi.COLLAR_Y + 0.03:
			bare += 1
	check(bare == 0, "the head stays bare")
	# The belt is the character's colour and follows a colour change.
	check(tori.gi.belt_material.albedo_color.is_equal_approx(tori.get_skin_color()), "the belt takes the character's colour")
	tori.set_skin_color(Color.RED)
	check(tori.gi.belt_material.albedo_color.is_equal_approx(Color.RED), "the belt follows a colour change")
	# The gi follows the pose: raise an arm and the sleeve's vertices move with it.
	var aabb_before: AABB = tori.gi.jacket.get_aabb()
	tori.set_limb_mode("RightArm", Limb.Mode.IK)
	tori.limbs["RightArm"].target.global_position = tori.bone_world_transform("RightUpperArm").origin + Vector3(0.1, 0.4, 0.1)
	await process_frame; await process_frame; await process_frame
	# The skinned AABB is not updated by the renderer on the CPU; probe the cloth by skinning one
	# sleeve vertex ourselves against the solved pose.
	var arrays: Array = jm.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var skin: Skin = tori.body.skin
	var sk := tori.skeleton
	var hand_bind := -1
	for b in skin.get_bind_count():
		if sk.get_bone_name(skin.get_bind_bone(b)) == "RightLowerArm":
			hand_bind = b
	var probe := -1
	for v in jv.size():
		if bones[v * 4] == hand_bind and weights[v * 4] > 0.8:
			probe = v; break
	check(probe >= 0, "a sleeve vertex is bound to the forearm")
	if probe >= 0:
		var posed := Vector3.ZERO
		for k in 4:
			var w := weights[probe * 4 + k]
			if w > 0.0:
				var bind := bones[probe * 4 + k]
				posed += (tori.bone_world_transform(sk.get_bone_name(skin.get_bind_bone(bind))) * skin.get_bind_pose(bind)) * jv[probe] * w
		var forearm: Vector3 = tori.bone_world_transform("RightLowerArm").origin
		check(posed.distance_to(forearm) < 0.35 and posed.y > 1.3, "the sleeve follows the raised forearm (vertex at y %.2f, %.2f m from the elbow)" % [posed.y, posed.distance_to(forearm)])
	# Toggle and save/load.
	tori.set_gi_visible(false)
	check(not tori.gi.jacket.visible and not tori.gi.belt.visible, "the gi can be hidden again")
	tori.set_gi_visible(true)
	var data: Dictionary = await PoseFile.capture_baked(scene, director, null, "gi test")
	check(data["characters"][0]["gi"] == true and data["characters"][1]["gi"] == false, "the gi flag is saved per character")
	tori.set_gi_visible(false)
	PoseFile.apply(data, scene, director)
	await process_frame
	tori = scene.get_character("tori")
	check(tori.gi_visible and tori.gi.jacket.visible, "loading a pose dresses the character again")
	check(not scene.get_character("uke1").gi_visible, "and leaves the other bare")
	# The plausibility checks read the body mesh, not the cloth.
	check(Anatomy.skin_problems(tori).is_empty(), "the skin check still passes with the gi on")
	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)
