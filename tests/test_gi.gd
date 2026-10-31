extends SceneTree
## The gi (M9): built on demand from the mannequin, skinned with its weights, cut to the pieces
## a keikogi has, coloured belt, toggled per character and saved with the pose. And the hakama
## worn over it, on its own toggle, through a step, seiza and a roll (_hakama).

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)


func _initialize() -> void:
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	# The app's default scene dresses its figures (a gi on both, Tori in a hakama); this test
	# starts from two bare figures placed the same way, to dress and undress them itself.
	var dressed := PosingScene.new(); world.add_child(dressed); dressed.setup_default()
	check(dressed.get_character("tori").gi_visible and dressed.get_character("tori").hakama_visible
		and dressed.get_character("uke1").gi_visible and not dressed.get_character("uke1").hakama_visible,
		"the default scene dresses both in a gi and Tori in a hakama")
	dressed.free()
	var scene := PosingScene.new(); world.add_child(scene)
	scene.add_character("tori", "Tori", "Tori").position = Vector3(0, 0, -0.5)
	var bare_uke := scene.add_character("uke1", "Uke", "Uke")
	bare_uke.position = Vector3(0, 0, 0.5)
	bare_uke.rotation.y = PI
	var director := GripDirector.new(); world.add_child(director); director.setup(scene, null)
	await physics_frame
	var tori: CharacterRig = scene.get_character("tori")
	check(tori.gi == null and not tori.gi_visible, "a character starts without a gi")
	tori.set_gi_visible(true)
	check(tori.gi != null and tori.gi.jacket.visible, "asking for the gi builds and shows it")
	var jm: ArrayMesh = tori.gi.jacket.mesh
	var tm: ArrayMesh = tori.gi.trousers.mesh
	check(jm.get_surface_count() >= 1 and jm.surface_get_array_len(0) > 1000, "the jacket is a real mesh (%d vertices)" % (jm.surface_get_array_len(0) if jm.get_surface_count() > 0 else 0))
	check(tm.get_surface_count() == 1 and tm.surface_get_array_len(0) > 1000, "the trousers are a real mesh (%d vertices)" % (tm.surface_get_array_len(0) if tm.get_surface_count() > 0 else 0))
	check(tori.gi.jacket.skin == tori.body.skin, "the cloth shares the body's skin binds")
	check(jm.get_surface_count() == 2, "the jacket carries its collar band as a second surface (%d)" % jm.get_surface_count())
	var lm: ArrayMesh = tori.gi.lapel.mesh
	check(lm.get_surface_count() == 1 and lm.surface_get_array_len(0) > 100, "the lapel ribbons are a real mesh (%d vertices)" % (lm.surface_get_array_len(0) if lm.get_surface_count() > 0 else 0))
	# What the renderer actually uses: the mesh instance's skeleton path must resolve, or the
	# cloth is drawn in its rest pose whatever the bones do (a first version had it empty).
	for piece in [tori.gi.jacket, tori.gi.trousers, tori.gi.belt, tori.gi.lapel]:
		check(piece.get_node_or_null(piece.skeleton) == tori.skeleton, "%s is bound to the skeleton (path '%s')" % [piece.name, piece.skeleton])
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
	check(not tori.gi.jacket.visible and not tori.gi.belt.visible and not tori.gi.lapel.visible, "the gi can be hidden again")
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
	await _hakama(scene, director)
	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


## The hakama: toggled on its own, over the gi or without it, saved with the pose; long enough to
## cover the knees and short enough to show the feet; and worn through a step, bent knees and
## seiza without the legs coming through it or the cloth tearing.
func _hakama(scene: PosingScene, director: GripDirector) -> void:
	var tori: CharacterRig = scene.get_character("tori")
	var uke: CharacterRig = scene.get_character("uke1")
	check(not tori.hakama_visible and tori.gi.hakama == null, "a character starts without a hakama")
	tori.set_hakama_visible(true)
	var hk: MeshInstance3D = tori.gi.hakama
	check(hk != null and hk.visible and tori.gi.hakama_knot.visible, "asking for the hakama builds and shows it, the belt's knot in front of it")
	check(tori.gi.jacket.visible and tori.gi.trousers.visible and not tori.gi.belt.visible,
		"over the gi the jacket and trousers stay on and the belt under the hakama is hidden")
	var hm: ArrayMesh = hk.mesh
	check(hm.get_surface_count() >= 1 and hm.surface_get_array_len(0) > 2000, "the hakama is a real mesh (%d vertices)" % hm.surface_get_array_len(0))
	for piece in [hk, tori.gi.hakama_knot]:
		check(piece.skin == tori.body.skin and piece.get_node_or_null(piece.skeleton) == tori.skeleton, "%s is skinned to the body's skeleton" % piece.name)
	var arrays: Array = hm.surface_get_arrays(0)
	var hv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var hb: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var hw: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var sk := tori.skeleton
	var skin: Skin = tori.body.skin
	var to_leg := {"Left": 0, "Right": 0}
	for v in hv.size():
		for k in 4:
			var bone := sk.get_bone_name(skin.get_bind_bone(hb[v * 4 + k]))
			if hw[v * 4 + k] > 0.5 and bone.ends_with("Leg"):
				to_leg["Left" if bone.begins_with("Left") else "Right"] += 1
				break
	check(to_leg["Left"] > 500 and to_leg["Right"] > 500, "each leg of it is skinned to its own leg (%d left, %d right vertices)" % [to_leg["Left"], to_leg["Right"]])
	# Rest shape: the hem at the ankle bone, the top over the belt, the knees well inside.
	var lo := INF; var top_front := -INF; var top_back := -INF
	for v in hv:
		lo = minf(lo, v.y)
		if absf(v.x) < 0.05 and v.z > 0.12:
			top_front = maxf(top_front, v.y)
		elif absf(v.x) < 0.05 and v.z < -0.05:
			top_back = maxf(top_back, v.y)
	var ankle: float = sk.get_bone_global_rest(sk.find_bone("LeftFoot")).origin.y
	var toes: float = sk.get_bone_global_rest(sk.find_bone("LeftToes")).origin.y
	check(lo > ankle - 0.005 and lo < ankle + 0.08 and lo > toes + 0.04,
		"the hem is at the ankle bone, the feet showing below it (hem %.3f m, ankle %.3f, toes %.3f)" % [lo, ankle, toes])
	check(top_front >= Gi.BELT_Y + Gi.BELT_HEIGHT * 0.5 and top_back > top_front,
		"the front reaches over the belt and the back sits higher (%.3f and %.3f m)" % [top_front, top_back])
	for side in ["Left", "Right"]:
		var knee: Vector3 = sk.get_bone_global_rest(sk.find_bone(side + "LowerLeg")).origin
		var ext := [INF, -INF, INF, -INF]
		for v in hv:
			if absf(v.y - knee.y) < 0.03 and signf(v.x) == signf(knee.x):
				ext[0] = minf(ext[0], v.x); ext[1] = maxf(ext[1], v.x); ext[2] = minf(ext[2], v.z); ext[3] = maxf(ext[3], v.z)
		var clear := minf(minf(absf(knee.x - ext[0]), absf(ext[1] - knee.x)), minf(knee.z - ext[2], ext[3] - knee.z))
		check(clear > 0.10, "the %s knee is well inside the hakama (%.2f m to the cloth at its nearest)" % [side.to_lower(), clear])
	var bare: Array = await _exposed(tori)
	check(bare[0] == 0, "standing, no part of the legs or seat shows through it (%d of %d)" % [bare[0], bare[1]])
	var stray_rest := _stray(tori)
	# Toggles: off again gives the trousers and the belt back; on without the gi it stands alone.
	tori.set_hakama_visible(false)
	check(not hk.visible and tori.gi.belt.visible, "taking the hakama off shows the belt again")
	uke.set_hakama_visible(true)
	check(uke.gi.hakama.visible and not uke.gi.jacket.visible and not uke.gi.hakama_knot.visible, "a hakama can be worn without the gi (and then has no belt knot)")
	uke.set_hakama_visible(false)
	tori.set_hakama_visible(true)
	# Saved per character; a file from before the hakama loads without one.
	var data: Dictionary = await PoseFile.capture_baked(scene, director, null, "hakama test")
	check(data["characters"][0]["hakama"] == true and data["characters"][1]["hakama"] == false, "the hakama flag is saved per character")
	var old: Dictionary = data.duplicate(true)
	for c in old["characters"]:
		c.erase("hakama")
	PoseFile.apply(old, scene, director)
	await process_frame
	check(not scene.get_character("tori").hakama_visible, "a pose file without the flag loads with no hakama")
	PoseFile.apply(data, scene, director)
	await process_frame
	tori = scene.get_character("tori")
	check(tori.hakama_visible and tori.gi.hakama.visible and tori.gi_visible, "loading the pose puts the hakama back on, over the gi")
	# Motion: a deep hanmi with the knees bent, seiza, and the middle of a forward roll. In each
	# no leg or seat shows through, and no cloth strays from the body (a tear pulls a corner away);
	# in hanmi it also does not stretch, while seiza folds it over the knees, as cloth does.
	var cam := Camera3D.new(); root.add_child(cam)
	var gizmo := RotationGizmo.new(); root.add_child(gizmo)
	var ctrl := PoseController.new(); root.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	var staging := Staging.new(self, scene, director, ctrl)
	ctrl.set_root(tori, Vector3(0, 0, 0), 0.0)
	await staging.hanmi("tori", "Left", 0.40, 0.14, 0.10)
	await staging.settle(4)
	check(Anatomy.flexion_deg(tori, "LeftLeg") > 20.0, "hanmi bends the front knee (%.0f°)" % Anatomy.flexion_deg(tori, "LeftLeg"))
	bare = await _exposed(tori)
	check(bare[0] <= bare[1] * 0.002, "in hanmi the legs stay inside it (%d of %d vertices show)" % [bare[0], bare[1]])
	var stretch := _stretch(tori)
	check(stretch < 2.5, "in hanmi no part of it stretches much (%.2f times its length at most)" % stretch)
	var stray := _stray(tori)
	check(stray < stray_rest + 0.06, "in hanmi it stays on the body (%.2f m at most from it, %.2f standing)" % [stray, stray_rest])
	Stance.kneel(ctrl, tori, Stance.Kneel.SEIZA)
	await staging.settle(6)
	Ukemi.ground(tori)
	await staging.settle(3)
	check(Anatomy.flexion_deg(tori, "LeftLeg") > 120.0, "seiza folds the legs (%.0f°)" % Anatomy.flexion_deg(tori, "LeftLeg"))
	bare = await _exposed(tori)
	check(bare[0] <= bare[1] * 0.01, "in seiza the knees, thighs and seat stay inside it (%d of %d vertices show)" % [bare[0], bare[1]])
	stray = _stray(tori)
	check(stray < stray_rest + 0.06, "in seiza it stays on the body (%.2f m at most from it)" % stray)
	ctrl.set_root(tori, Vector3(0, 0, 0), 0.0)
	Ukemi.shape(tori, Ukemi.Kind.FORWARD, 0.5)
	await staging.settle(4)
	Ukemi.ground(tori)
	await staging.settle(3)
	stray = _stray(tori)
	check(stray < stray_rest + 0.10, "mid-roll it stays on the body (%.2f m at most from it)" % stray)


## Skins a mesh of `rig`'s on the CPU with the solved pose: [world positions, world normals].
func _posed(rig: CharacterRig, mesh: Mesh, surface: int = 0) -> Array:
	var arrays: Array = mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var skin: Skin = rig.body.skin
	var xf: Array[Transform3D] = []
	for b in skin.get_bind_count():
		xf.append(rig.bone_world_transform(rig.skeleton.get_bone_name(skin.get_bind_bone(b))) * skin.get_bind_pose(b))
	var pos := PackedVector3Array(); var nrm := PackedVector3Array()
	pos.resize(verts.size()); nrm.resize(verts.size())
	for v in verts.size():
		var p := Vector3.ZERO; var n := Vector3.ZERO
		for k in 4:
			var w := weights[v * 4 + k]
			if w > 0.0:
				p += xf[bones[v * 4 + k]] * verts[v] * w
				n += xf[bones[v * 4 + k]].basis * normals[v] * w
		pos[v] = p; nrm[v] = n.normalized()
	return [pos, nrm]


## How many of the leg and seat vertices under the hakama show, of the skin and (over the gi) the
## trousers: a ray out along the surface's normal that meets no cloth. Anything facing the mat is
## left out (the mat hides it, and in seiza the thighs rest on the calves); anything between folds
## the ray finds cloth beyond counts as covered, which it is. [showing, counted].
func _exposed(rig: CharacterRig) -> Array:
	var sk := rig.skeleton
	var skin: Skin = rig.body.skin
	var cloth: PackedVector3Array = _posed(rig, rig.gi.hakama.mesh)[0]
	var idx: PackedInt32Array = rig.gi.hakama.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var faces := PackedVector3Array()
	for i in idx:
		faces.append(cloth[i])
	if rig.gi_visible:
		# Over the gi, the jacket's skirt covers the hips where the side openings are.
		var jacket: PackedVector3Array = _posed(rig, rig.gi.jacket.mesh)[0]
		for i in rig.gi.jacket.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]:
			faces.append(jacket[i])
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var holder := StaticBody3D.new()
	holder.collision_layer = 1 << 19
	holder.collision_mask = 0
	var cs := CollisionShape3D.new(); cs.shape = shape; holder.add_child(cs)
	root.add_child(holder)
	await physics_frame
	await physics_frame
	var space := holder.get_world_3d().direct_space_state
	var shown := 0; var counted := 0
	var under: Array = [rig.body.mesh]
	if rig.gi_visible:
		under.append(rig.gi.trousers.mesh)   # worn under the hakama, and tested the same way
	for mesh: Mesh in under:
		var posed := _posed(rig, mesh)
		var arrays: Array = mesh.surface_get_arrays(0)
		var rest: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bb: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var bw: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for i in rest.size():
			var best_k := 0
			for k in 4:
				if bw[i * 4 + k] > bw[i * 4 + best_k]:
					best_k = k
			var bone := sk.get_bone_name(skin.get_bind_bone(bb[i * 4 + best_k]))
			var y := rest[i].y
			if not ((bone.ends_with("UpperLeg") or bone.ends_with("LowerLeg")) and y > Gi.HAKAMA_HEM_Y + 0.05 and y < 0.9) \
					and not (bone == "Hips" and y < 0.92):
				continue
			var p: Vector3 = posed[0][i]; var n: Vector3 = posed[1][i]
			if n.y < -0.5 or p.y < 0.03:
				continue
			counted += 1
			var q := PhysicsRayQueryParameters3D.create(p + n * 0.003, p + n * 0.6, 1 << 19)
			q.hit_back_faces = true
			q.hit_from_inside = true
			if space.intersect_ray(q).is_empty():
				shown += 1
				if OS.get_environment("HAKAMA_DEBUG") == "1":
					print("shows: %s %s rest %s" % [mesh.resource_name, bone, rest[i]])
	holder.queue_free()
	return [shown, counted]


## How far the hakama's furthest vertex is from the nearest skin: cloth torn off a limb by its
## weights would leave a corner hanging in the air.
func _stray(rig: CharacterRig) -> float:
	var cloth: PackedVector3Array = _posed(rig, rig.gi.hakama.mesh)[0]
	var body: PackedVector3Array = _posed(rig, rig.body.mesh)[0]
	var grid := {}
	for i in body.size():
		var key := Vector3i((body[i] / 0.1).floor())
		if not grid.has(key):
			grid[key] = PackedInt32Array()
		grid[key].append(i)
	var worst := 0.0
	for c in cloth:
		var key := Vector3i((c / 0.1).floor())
		var near := INF
		for reach in [1, 3]:
			for dx in range(-reach, reach + 1):
				for dy in range(-reach, reach + 1):
					for dz in range(-reach, reach + 1):
						for i in grid.get(key + Vector3i(dx, dy, dz), PackedInt32Array()):
							near = minf(near, body[i].distance_squared_to(c))
			if near < INF:
				break
		worst = maxf(worst, sqrt(near))
	return worst


## The most any edge of the hakama's tubes is stretched from its rest length, as a ratio.
func _stretch(rig: CharacterRig) -> float:
	var mesh: Mesh = rig.gi.hakama.mesh
	var posed: PackedVector3Array = _posed(rig, mesh)[0]
	var arrays: Array = mesh.surface_get_arrays(0)
	var rest: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var worst := 1.0
	for t in idx.size() / 3:
		for e in 3:
			var a := idx[t * 3 + e]; var b := idx[t * 3 + (e + 1) % 3]
			var r := rest[a].distance_to(rest[b])
			if r > 0.005:
				worst = maxf(worst, posed[a].distance_to(posed[b]) / r)
	return worst
