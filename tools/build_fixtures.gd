extends SceneTree
## Builds the acceptance techniques (spec §8) as saved poses and sequences in poses/ and
## sequences/. Run headless: godot --headless -s tools/build_fixtures.gd
##
## The poses are schematic first drafts made with the tool's own API, so the instructor opens
## them in the tool and corrects them; what this script guarantees is the mechanics the spec
## tests (grips that track, reversals, handovers, reach shortfalls) and predictable file names.

const POSES := "res://poses"
const SEQUENCES := "res://sequences"

var scene: PosingScene
var ctrl: PoseController
var director: GripDirector
var cam: OrbitCamera
var written: Array = []


func _initialize() -> void:
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	scene = PosingScene.new(); world.add_child(scene)
	cam = OrbitCamera.new(); world.add_child(cam)
	var gizmo := RotationGizmo.new(); world.add_child(gizmo)
	ctrl = PoseController.new(); world.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	director = GripDirector.new(); world.add_child(director); director.setup(scene, ctrl)
	await physics_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(POSES))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SEQUENCES))

	await katatedori_ikkyo()
	await ushiro_ryotedori_zenponage()
	await katatedori_shihonage_irimi()
	await three_person()
	await tachi_dori()
	await jo_dori()
	await kumitachi()
	await kumijo()

	print("wrote %d files" % written.size())
	for w in written:
		print("  ", w)
	quit(0)


# ---------------------------------------------------------------- helpers

func reset(ids: Array = [["tori", "Tori", "Tori"], ["uke1", "Uke", "Uke"]]) -> void:
	director.clear()
	for w in scene.weapons.duplicate():
		scene.remove_weapon(w.weapon_id)
	for c in scene.characters.duplicate():
		scene.remove_character(c.character_id)
	await settle()
	for entry in ids:
		scene.add_character(entry[0], entry[1], entry[2])
	await settle()


func rig(id: String) -> CharacterRig:
	return scene.get_character(id)


func stance(id: String, x: float, z: float, yaw_deg: float) -> void:
	ctrl.set_root(rig(id), Vector3(x, 0, z), deg_to_rad(yaw_deg))


## Puts a hand at an offset from its own shoulder, in the character's frame (x right-to-left,
## y up, z forward for a character at yaw 0).
func hand_at(id: String, side: String, local_offset: Vector3) -> void:
	var r := rig(id)
	if r.limbs[side + "Arm"].mode != Limb.Mode.IK:
		await ctrl.set_limb_mode(r, side + "Arm", Limb.Mode.IK)
	var shoulder: Vector3 = r.bone_world_transform(side + "UpperArm").origin
	r.limbs[side + "Arm"].target.global_position = shoulder + r.global_transform.basis * local_offset
	r.limbs[side + "Arm"].reset_pole()


func arm_fk(id: String, side: String) -> void:
	var r := rig(id)
	if r.limbs[side + "Arm"].mode != Limb.Mode.FK:
		await ctrl.set_limb_mode(r, side + "Arm", Limb.Mode.FK)


## Rotates a bone about the character's own right axis so the part swings forward by `deg`
## (negative swings back). The sign is found by trying, since it depends on the bone's frame.
func bend_forward(id: String, bone: String, deg: float) -> void:
	var r := rig(id)
	var probe := "Head" if bone in ["Hips", "Spine", "Chest", "UpperChest", "Neck"] else bone
	var before: Vector3 = r.bone_world_transform(probe).origin
	ctrl.select(r, bone)
	var axis: Vector3 = r.global_transform.basis.x
	ctrl.rotate_selected_world(axis, deg_to_rad(deg))
	await settle()
	var moved: Vector3 = r.bone_world_transform(probe).origin - before
	if moved.dot(r.global_transform.basis.z) * signf(deg) < 0.0:
		ctrl.rotate_selected_world(axis, -2.0 * deg_to_rad(deg))
		await settle()
	ctrl.select(null, "")


func fingers(id: String, side: String, curl: float) -> void:
	rig(id).fingers.set_hand_curl(side, curl)


func grab(gripper: String, hand: String, target: String, bone: String, approach_offset: Vector3 = Vector3(0, 0.06, 0)) -> void:
	var g := rig(gripper)
	if g.limbs[hand + "Arm"].mode != Limb.Mode.IK:
		await ctrl.set_limb_mode(g, hand + "Arm", Limb.Mode.IK)
	g.limbs[hand + "Arm"].target.global_position = rig(target).bone_world_transform(bone).origin + approach_offset
	await settle()
	director.attach_wrapped(g, hand, rig(target), bone)
	fingers(gripper, hand, 0.6)
	await settle(3)


func release_all(gripper: String) -> void:
	for grip in director.grips_for(gripper):
		director._remove(grip)
		fingers(gripper, grip.hand, 0.0)
	await settle()


## Saves the pose after making sure every gripping hand reaches its point: a gripper that is
## short steps in horizontally by the shortfall, which is what a person does. `allow_short`
## keeps a deliberate out-of-reach pose (spec 8.2) as it is.
func save_pose(name: String, allow_short: bool = false) -> Dictionary:
	await settle(3)
	if not allow_short:
		for attempt in 12:
			var moves := {}   # gripper id -> [sum of directions, worst error]
			for grip in director.grips:
				var e := director.error_for(grip)
				if e < 0.008:
					continue
				var g := rig(grip.gripper_id)
				var shoulder: Vector3 = g.bone_world_transform(grip.hand + "UpperArm").origin
				var toward: Vector3 = grip.desired_hand_transform().origin - shoulder
				toward.y = 0.0
				if not moves.has(grip.gripper_id):
					moves[grip.gripper_id] = [Vector3.ZERO, 0.0]
				moves[grip.gripper_id][0] += toward.normalized()
				moves[grip.gripper_id][1] = maxf(moves[grip.gripper_id][1], e)
			if moves.is_empty():
				break
			for id in moves:
				var dir: Vector3 = moves[id][0]
				if dir.length() > 1e-4:
					rig(id).position += dir.normalized() * (moves[id][1] * 0.8 + 0.01)
			await settle(3)
	var data: Dictionary = await PoseFile.capture_baked(scene, director, cam, name)
	var path := PoseFile.pose_path(POSES, name)
	var err := PoseFile.save(path, data)
	assert(err == OK, "could not write %s" % path)
	written.append(path)
	print("pose %s: grips %d, worst grip error %.4f" % [name, director.grips.size(), director.worst_error()])
	return data


func save_sequence(name: String, steps: Array, camera: String = "Side") -> void:
	var seq := Sequence.new()
	seq.name = name
	seq.camera = camera
	for i in steps.size():
		var st: Array = steps[i]   # [pose name, transition, hold]
		seq.steps.append({"pose": PoseFile.slugify(st[0]), "transition": st[1], "hold": st[2]})
	var path := Sequence.sequence_path(SEQUENCES, name)
	assert(seq.save(path) == OK)
	written.append(path)


func settle(frames: int = 2) -> void:
	for i in frames:
		await process_frame


# ---------------------------------------------------------------- 8.1 Katatedori Ikkyo

func katatedori_ikkyo() -> void:
	await reset()
	stance("tori", 0, -0.22, 0)
	stance("uke1", 0, 0.22, 180)
	await settle()
	await hand_at("tori", "Right", Vector3(0, -0.14, 0.22))
	await settle(3)
	await grab("uke1", "Left", "tori", "RightLowerArm")
	await save_pose("Katatedori Ikkyo Grepp")

	rig("tori").limbs["RightArm"].target.global_position += Vector3(0.05, 0.18, 0.05)
	stance("tori", 0.08, -0.26, 15)
	await save_pose("Katatedori Ikkyo Kuzushi")

	# Kake: Uke's grip is off, Uke bends forward, Tori holds Uke's arm at wrist and elbow.
	await release_all("uke1")
	await bend_forward("uke1", "Spine", 40)
	await hand_at("uke1", "Left", Vector3(-0.42, -0.08, 0.20))
	stance("tori", 0.55, -0.30, 145)
	await settle(3)
	await grab("tori", "Right", "uke1", "LeftLowerArm", Vector3(0, 0.06, 0))
	await grab("tori", "Left", "uke1", "LeftUpperArm", Vector3(0, 0.06, 0))
	await save_pose("Katatedori Ikkyo Kake")
	save_sequence("Katatedori Ikkyo", [["Katatedori Ikkyo Grepp", 0.0, 0.5], ["Katatedori Ikkyo Kuzushi", 0.6, 0.3], ["Katatedori Ikkyo Kake", 0.6, 1.0]])


# ---------------------------------------------------------------- 8.2 Ushiro Ryotedori Zenponage

func ushiro_ryotedori_zenponage() -> void:
	await reset()
	stance("tori", 0, 0, 0)
	stance("uke1", 0, -0.36, 0)   # behind Tori, facing the same way
	await settle()
	await hand_at("tori", "Right", Vector3(0.04, -0.36, -0.06))
	await hand_at("tori", "Left", Vector3(-0.04, -0.36, -0.06))
	await settle(3)
	await grab("uke1", "Right", "tori", "RightLowerArm", Vector3(0, 0.05, -0.04))
	await grab("uke1", "Left", "tori", "LeftLowerArm", Vector3(0, 0.05, -0.04))
	await save_pose("Ushiro Ryotedori Zenponage Grepp")

	await hand_at("tori", "Right", Vector3(0.02, 0.12, 0.30))
	await hand_at("tori", "Left", Vector3(-0.02, 0.12, 0.30))
	stance("uke1", 0, -0.25, 0)
	await save_pose("Ushiro Ryotedori Zenponage Kuzushi")

	# Kake: Tori extends forward-down; Uke, still holding, is thrown well beyond arm's reach,
	# which is exactly what the reach warning is for (spec 8.2).
	await hand_at("tori", "Right", Vector3(0.05, -0.35, 0.42))
	await hand_at("tori", "Left", Vector3(-0.05, -0.35, 0.42))
	stance("uke1", 0, 1.3, 0)
	await save_pose("Ushiro Ryotedori Zenponage Kake", true)
	save_sequence("Ushiro Ryotedori Zenponage", [["Ushiro Ryotedori Zenponage Grepp", 0.0, 0.5], ["Ushiro Ryotedori Zenponage Kuzushi", 0.6, 0.3], ["Ushiro Ryotedori Zenponage Kake", 0.8, 1.0]])


# ---------------------------------------------------------------- 8.3 Katatedori Shihonage irimi

func katatedori_shihonage_irimi() -> void:
	# Grepp is literally the Ikkyo file; rebuild that state to continue from it.
	await reset()
	var grepp := PoseFile.load(PoseFile.pose_path(POSES, "Katatedori Ikkyo Grepp"))
	PoseFile.apply(grepp, scene, director, ctrl)
	await settle(3)
	# Kuzushi: Tori steps in beside Uke and raises the gripped arm high.
	stance("tori", 0.30, 0.05, 80)
	await hand_at("tori", "Right", Vector3(-0.35, 0.40, 0.10))
	await save_pose("Katatedori Shihonage Kuzushi")
	# Kake: the grip reverses. Uke's hand is off; Tori has turned and holds Uke's wrist, the arm
	# folded back over Uke's shoulder.
	await release_all("uke1")
	await hand_at("uke1", "Left", Vector3(-0.15, 0.30, -0.30))
	stance("tori", 0.40, 0.55, 200)
	await settle(3)
	await grab("tori", "Left", "uke1", "LeftLowerArm", Vector3(0, 0.06, 0))
	await grab("tori", "Right", "uke1", "LeftHand", Vector3(0, 0.05, 0))
	await save_pose("Katatedori Shihonage Kake")
	save_sequence("Katatedori Shihonage irimi", [["Katatedori Ikkyo Grepp", 0.0, 0.5], ["Katatedori Shihonage Kuzushi", 0.7, 0.3], ["Katatedori Shihonage Kake", 0.7, 1.0]])


# ---------------------------------------------------------------- 8.4 three-person fixture

func three_person() -> void:
	await reset([["tori", "Tori", "Tori"], ["uke1", "Uke 1", "Uke"], ["uke2", "Uke 2", "Uke"]])
	stance("tori", 0, 0, 0)
	stance("uke1", -0.40, 0.40, 180)
	stance("uke2", 0.40, 0.40, 180)
	await settle()
	await hand_at("tori", "Right", Vector3(0.05, -0.14, 0.25))
	await hand_at("tori", "Left", Vector3(-0.05, -0.14, 0.25))
	await settle(3)
	await grab("uke1", "Left", "tori", "RightLowerArm")
	await grab("uke2", "Right", "tori", "LeftLowerArm")
	await save_pose("Ryotemochi Grepp")
	await hand_at("tori", "Right", Vector3(0.05, 0.15, 0.30))
	await hand_at("tori", "Left", Vector3(-0.05, 0.15, 0.30))
	await save_pose("Ryotemochi Kuzushi")
	save_sequence("Ryotemochi", [["Ryotemochi Grepp", 0.0, 0.5], ["Ryotemochi Kuzushi", 0.7, 1.0]])


# ---------------------------------------------------------------- weapons: shared

## Places a weapon in front of a character in chudan and snaps both hands onto it.
func chudan(id: String, weapon: Weapon, t_front: float, t_back: float, forward: float = 0.25, height: float = 1.02) -> void:
	var r := rig(id)
	var b := r.global_transform.basis
	weapon.drive = "weapon"
	var along: Vector3 = (b * Vector3(0, 0.45, 0.9)).normalized()
	var up: Vector3 = (b * Vector3(0, 0.9, -0.45)).normalized()
	weapon.global_transform = Transform3D(Basis(along.cross(up), along, up), r.global_position + b * Vector3(0.0, height, forward))
	director.attach_to_weapon(r, "Left", weapon, t_back, true)
	director.attach_to_weapon(r, "Right", weapon, t_front, true)
	r.fingers.apply_grip_preset("Right")
	r.fingers.apply_grip_preset("Left")
	await settle(3)


func place_weapon(weapon: Weapon, origin: Vector3, along: Vector3, up_hint: Vector3) -> void:
	along = along.normalized()
	var up := (up_hint - along * up_hint.dot(along)).normalized()
	weapon.global_transform = Transform3D(Basis(along.cross(up), along, up), origin)
	await settle(2)


# ---------------------------------------------------------------- 8.5 tachi dori

func tachi_dori() -> void:
	await reset()
	stance("uke1", 0, 0.55, 180)
	stance("tori", 0, -0.75, 0)
	await settle()
	var bokken := scene.add_weapon("bokken1", "bokken")
	await chudan("uke1", bokken, 0.17, 0.04)
	await save_pose("Tachi dori Kamae")
	# The cut: bokken raised overhead (weapon-driven, hands follow) then brought down.
	var u := rig("uke1")
	await place_weapon(bokken, u.global_position + u.global_transform.basis * Vector3(0, 1.55, -0.05), u.global_transform.basis * Vector3(0, 0.6, -0.8), Vector3.UP)
	await save_pose("Tachi dori Furikaburi")
	await place_weapon(bokken, u.global_position + u.global_transform.basis * Vector3(0, 1.05, 0.30), u.global_transform.basis * Vector3(0, 0.2, 1.0), Vector3.UP)
	stance("tori", 0.35, -0.10, 40)
	await grab("tori", "Right", "uke1", "RightLowerArm", Vector3(0, 0.05, 0))
	await save_pose("Tachi dori Irimi")
	# Tori takes the sword: the hold names Tori; Uke lets go and is moved off.
	await release_all("uke1")
	director.hold_weapon(rig("tori"), "Right", bokken, 0.12, 0.0, true)
	await settle(2)
	rig("tori").fingers.apply_grip_preset("Right")
	await arm_fk("uke1", "Right")
	await arm_fk("uke1", "Left")
	stance("uke1", 0.45, 0.85, 220)
	await save_pose("Tachi dori Kake")
	save_sequence("Tachi dori", [["Tachi dori Kamae", 0.0, 0.5], ["Tachi dori Furikaburi", 0.6, 0.2], ["Tachi dori Irimi", 0.6, 0.4], ["Tachi dori Kake", 0.7, 1.0]])


# ---------------------------------------------------------------- 8.6 jo dori

func jo_dori() -> void:
	await reset()
	stance("uke1", 0, 0.75, 180)
	stance("tori", 0, -0.75, 0)
	await settle()
	var jo := scene.add_weapon("jo1", "jo")
	var u := rig("uke1")
	# Thrust: jo level at chest height, tip toward Tori, hands at 0.30 and 0.55 along it.
	jo.drive = "weapon"
	await place_weapon(jo, u.global_position + u.global_transform.basis * Vector3(0.05, 1.12, -0.40), u.global_transform.basis * Vector3(0, 0.05, 1.0), Vector3.UP)
	director.attach_to_weapon(u, "Left", jo, 0.28, true)
	director.attach_to_weapon(u, "Right", jo, 0.52, true)
	u.fingers.apply_grip_preset("Right"); u.fingers.apply_grip_preset("Left")
	await save_pose("Jo dori Tsuki")
	# Deflect and take hold of the staff near its tip.
	stance("tori", 0.30, -0.35, 20)
	director.attach_to_weapon(rig("tori"), "Right", jo, 0.80, true)
	rig("tori").fingers.apply_grip_preset("Right")
	await save_pose("Jo dori Uke")
	# Tori holds the jo; Uke lets go.
	await release_all("uke1")
	director.hold_weapon(rig("tori"), "Right", jo, 0.80, 0.0, true)
	await settle(2)
	await arm_fk("uke1", "Right")
	await arm_fk("uke1", "Left")
	stance("uke1", -0.3, 0.9, 150)
	await save_pose("Jo dori Kake")
	save_sequence("Jo dori", [["Jo dori Tsuki", 0.0, 0.5], ["Jo dori Uke", 0.7, 0.3], ["Jo dori Kake", 0.7, 1.0]])


# ---------------------------------------------------------------- 8.7 kumitachi

func kumitachi() -> void:
	await reset()
	stance("tori", 0, -0.62, 0)
	stance("uke1", 0, 0.62, 180)
	await settle()
	var a := scene.add_weapon("bokken1", "bokken")
	var b := scene.add_weapon("bokken2", "bokken")
	await chudan("tori", a, 0.17, 0.04)
	await chudan("uke1", b, 0.17, 0.04)
	var gap := director.contact_gap(a, 0.72, b, 0.72)
	director.close_gap(a, 0.72, b, 0.72, b)
	await settle(3)
	scene.weapon_contacts = [{"a": "bokken1", "t_a": 0.72, "b": "bokken2", "t_b": 0.72}]
	print("kumitachi contact gap %.3f -> %.4f m" % [gap, director.contact_gap(a, 0.72, b, 0.72)])
	await save_pose("Kumitachi Awase")
	# Second phase: Tori's blade rises over Uke's.
	await place_weapon(a, a.global_position + Vector3(0, 0.12, 0), a.global_transform.basis.y.rotated(rig("tori").global_transform.basis.x, -0.25), Vector3.UP)
	scene.weapon_contacts = []   # the blades part here; the indicator is not a constraint
	await save_pose("Kumitachi Uchi")
	save_sequence("Kumitachi", [["Kumitachi Awase", 0.0, 0.6], ["Kumitachi Uchi", 0.6, 1.0]])


# ---------------------------------------------------------------- 8.8 kumijo

func kumijo() -> void:
	await reset()
	stance("tori", 0, -0.75, 0)
	stance("uke1", 0, 0.75, 180)
	await settle()
	var a := scene.add_weapon("jo1", "jo")
	var b := scene.add_weapon("jo2", "jo")
	for entry in [["tori", a], ["uke1", b]]:
		var r := rig(entry[0])
		var jo: Weapon = entry[1]
		jo.drive = "weapon"
		await place_weapon(jo, r.global_position + r.global_transform.basis * Vector3(0.05, 1.12, -0.40), r.global_transform.basis * Vector3(0, 0.05, 1.0), Vector3.UP)
		director.attach_to_weapon(r, "Left", jo, 0.28, true)
		director.attach_to_weapon(r, "Right", jo, 0.52, true)
		r.fingers.apply_grip_preset("Right"); r.fingers.apply_grip_preset("Left")
	await settle(3)
	await save_pose("Kumijo Kamae")
	# Tori thrusts: both hands slide along the staff toward the tip, the same grips at new t.
	for grip in director.grips_for("tori"):
		grip.target.t = 0.40 if grip.hand == "Left" else 0.64
	director.refresh_hand_driven()
	await settle(3)
	await save_pose("Kumijo Tsuki")
	save_sequence("Kumijo", [["Kumijo Kamae", 0.0, 0.5], ["Kumijo Tsuki", 0.8, 1.0]])
