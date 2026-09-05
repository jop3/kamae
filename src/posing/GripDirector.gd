class_name GripDirector
extends Node
## Keeps every gripping hand on the thing it grips, every frame, exactly.
##
## A grip drives the gripper's IK target from the target's live world transform. Two rules make it
## exact rather than a frame behind (both verified, see docs/engine-notes.md):
##
##  1. The target's transform is read inside the *target* skeleton's `skeleton_updated` signal, where
##     the posed values are live. Reading it in `_process` returns the unposed pose.
##  2. Characters are ordered in the scene tree so that a grip's target is evaluated before its
##     gripper. Godot evaluates skeletons in tree order, so a chain (Uke 2 grips Uke 1 who grips
##     Tori) then resolves within one frame instead of one frame per link.

signal grips_changed

var scene: PosingScene
var controller: PoseController
var grips: Array[Grip] = []

var _connected: Dictionary = {}   ## character id -> Callable connected to its skeleton_updated


func setup(posing_scene: PosingScene, pose_controller: PoseController) -> void:
	scene = posing_scene
	controller = pose_controller
	scene.characters_changed.connect(_on_characters_changed)
	scene.weapons_changed.connect(_on_weapons_changed)
	# Weapon-driven grips are applied at frame start, before any skeleton solves.
	set_process_internal(true)
	process_priority = -10


# ---------------------------------------------------------------- editing

## Attaches a hand to a target, freezing the hand exactly where it is now.
func attach(gripper: CharacterRig, hand: String, target: GripTarget) -> Grip:
	var grip := Grip.new()
	grip.gripper_id = gripper.character_id
	grip.hand = hand
	grip.target = target
	grip.offset = target.world_transform().affine_inverse() * gripper.bone_world_transform(hand + "Hand")
	_add(grip)
	controller.undo.create_action("Grip %s" % grip.describe())
	controller.undo.add_do_method(_add.bind(grip))
	controller.undo.add_undo_method(_remove.bind(grip))
	controller.undo.commit_action(false)
	return grip


func detach(grip: Grip) -> void:
	controller.undo.create_action("Release %s" % grip.describe())
	controller.undo.add_do_method(_remove.bind(grip))
	controller.undo.add_undo_method(_add.bind(grip))
	controller.undo.commit_action()


## Puts a weapon in `gripper`'s hand: the weapon becomes hand-driven at `t`. With `snap` the hand
## keeps its place and the weapon moves to the canonical hold; otherwise the current geometry is
## kept as the hold offset.
func hold_weapon(gripper: CharacterRig, hand: String, weapon: Weapon, t: float, roll_deg: float = 0.0, snap := true) -> void:
	var before := _weapon_state(weapon)
	var dropped := _grips_on_hand(gripper.character_id, hand)
	_drop_grips_on(weapon, gripper.character_id, hand)
	weapon.drive = "hand"
	weapon.set_hold(gripper, hand, t, roll_deg)
	var hand_world := gripper.bone_world_transform(hand + "Hand")
	if snap:
		weapon.global_transform = hand_world * weapon.hold["offset"]
	else:
		weapon.set_hold_offset_from_current(hand_world)
	_rebuild()
	if controller:
		var after := _weapon_state(weapon)
		controller.undo.create_action("Hold %s" % weapon.weapon_id)
		controller.undo.add_do_method(_restore_weapon_state.bind(weapon, after))
		for g in dropped:
			controller.undo.add_do_method(_remove.bind(g))
		controller.undo.add_undo_method(_restore_weapon_state.bind(weapon, before))
		for g in dropped:
			controller.undo.add_undo_method(_add.bind(g))
		controller.undo.commit_action(false)


func _weapon_state(weapon: Weapon) -> Dictionary:
	return {"drive": weapon.drive, "hold": weapon.hold.duplicate(), "xf": weapon.global_transform}


func _restore_weapon_state(weapon: Weapon, state: Dictionary) -> void:
	if not is_instance_valid(weapon):
		return
	weapon.drive = state["drive"]
	weapon.hold = state["hold"].duplicate()
	weapon.global_transform = state["xf"]
	_rebuild()


## How far the palm centre sits off a gripped limb's axis: a fist closes to about 2.5 cm from
## its own axis and a wrist is about 4 cm across, so the palm rides just off the bone line.
const WRAP_RADIUS := 0.02

## Attaches a hand to a limb bone of another character with the hand wrapped around it, the
## way a real katatedori takes the wrist: the bone is treated as a shaft, the hand is placed at
## the point of the bone nearest to where it is now, on the same side of the bone it is on now,
## with the shaft across its palm and the fingers closing round it. With `snap` false this is
## an ordinary `attach` that freezes the hand wherever it is.
func attach_wrapped(gripper: CharacterRig, hand: String, target_rig: CharacterRig, bone: String, snap := true) -> Grip:
	var target := GripTarget.for_bone(scene, target_rig.character_id, bone)
	if not snap:
		return attach(gripper, hand, target)
	var hand_world := wrapped_hand_transform(gripper, hand, target_rig, bone)
	gripper.set_limb_mode(hand + "Arm", Limb.Mode.IK)
	var limb: Limb = gripper.limbs[hand + "Arm"]
	limb.target.global_transform = hand_world
	limb.reset_pole()
	var grip := Grip.new()
	grip.gripper_id = gripper.character_id
	grip.hand = hand
	grip.target = target
	grip.target.bind(scene)
	grip.offset = target.world_transform().affine_inverse() * hand_world
	_add(grip)
	if controller:
		controller.undo.create_action("Grip %s" % grip.describe())
		controller.undo.add_do_method(_add.bind(grip))
		controller.undo.add_undo_method(_remove.bind(grip))
		controller.undo.commit_action(false)
	return grip


## Where `gripper`'s `hand` should be to wrap around `bone` of `target_rig`, given where the
## hand is now (nearest point along the bone, same side of it).
func wrapped_hand_transform(gripper: CharacterRig, hand: String, target_rig: CharacterRig, bone: String) -> Transform3D:
	var bone_xf := target_rig.bone_world_transform(bone)
	var joint := bone_xf.origin
	var child := _child_joint(target_rig, bone)
	var axis := (child - joint).normalized()
	var length := joint.distance_to(child)
	var palm_now: Vector3 = gripper.bone_world_transform(hand + "Hand") * Weapon.palm_centre(gripper, hand)
	var t := clampf((palm_now - joint).dot(axis) / maxf(length, 1e-3), 0.25, 0.9)
	var on_axis := joint + axis * t * length
	var radial := palm_now - on_axis
	radial -= axis * radial.dot(axis)
	if radial.length() < 1e-3:
		radial = gripper.global_transform.basis.z
		radial -= axis * radial.dot(axis)
	radial = radial.normalized()
	# The shaft frame: +Y along the bone, the palm-facing side (-Z of a weapon) toward the bone.
	var width_now: Vector3 = gripper.bone_world_transform(hand + "Hand").basis * gripper.fingers.palm_width(hand)
	var y := axis if width_now.dot(axis) >= 0.0 else -axis
	var z := radial
	var x := y.cross(z).normalized()
	var shaft := Transform3D(Basis(x, y, z).orthonormalized(), on_axis + radial * WRAP_RADIUS)
	var hold := Transform3D(Weapon.canonical_basis(gripper, hand), Weapon.palm_centre(gripper, hand))
	return shaft * hold.affine_inverse()


func _child_joint(rig: CharacterRig, bone: String) -> Vector3:
	var sk := rig.skeleton
	var idx := sk.find_bone(bone)
	for i in sk.get_bone_count():
		if sk.get_bone_parent(i) == idx:
			return rig.bone_world_transform(sk.get_bone_name(i)).origin
	# A leaf bone: extend along its own +Y by its rest length guess.
	return rig.bone_world_transform(bone) * Vector3(0, 0.1, 0)


## Attaches a second (or any) hand to a weapon at `t`. With `snap`, the hand's IK target is first
## moved to the canonical hand pose for that point, so the grip is a real hold.
func attach_to_weapon(gripper: CharacterRig, hand: String, weapon: Weapon, t: float, snap := true) -> Grip:
	var grip := _attach_to_weapon_raw(gripper, hand, weapon, t, snap)
	if controller:
		controller.undo.create_action("Grip %s" % grip.describe())
		controller.undo.add_do_method(_add.bind(grip))
		controller.undo.add_undo_method(_remove.bind(grip))
		controller.undo.commit_action(false)
	return grip


func _attach_to_weapon_raw(gripper: CharacterRig, hand: String, weapon: Weapon, t: float, snap := true) -> Grip:
	if snap:
		gripper.set_limb_mode(hand + "Arm", Limb.Mode.IK)
		var limb: Limb = gripper.limbs[hand + "Arm"]
		limb.target.global_transform = weapon.global_transform * weapon.hold_offset(gripper, hand, t, 0.0).affine_inverse()
		limb.reset_pole()
	var grip := Grip.new()
	grip.gripper_id = gripper.character_id
	grip.hand = hand
	grip.target = GripTarget.for_weapon(scene, weapon.weapon_id, t)
	grip.target.bind(scene)
	if snap:
		grip.offset = grip.target.world_transform().affine_inverse() * (weapon.global_transform * weapon.hold_offset(gripper, hand, t, 0.0).affine_inverse())
	else:
		grip.offset = grip.target.world_transform().affine_inverse() * gripper.bone_world_transform(hand + "Hand")
	_add(grip)
	return grip


## Switches who drives whom without moving anything. "weapon": the holder's hand becomes an
## ordinary grip on the weapon at the hold's t. "hand": the weapon hangs off that hand again.
func set_weapon_drive(weapon: Weapon, mode: String) -> void:
	if weapon.drive == mode:
		return
	var before := _weapon_state(weapon)
	var grips_before := grips.duplicate()
	_set_weapon_drive(weapon, mode)
	if controller:
		var after := _weapon_state(weapon)
		var added: Array[Grip] = []
		var removed: Array[Grip] = []
		for g in grips:
			if not g in grips_before:
				added.append(g)
		for g in grips_before:
			if not g in grips:
				removed.append(g)
		controller.undo.create_action("Drive %s by %s" % [weapon.weapon_id, mode])
		controller.undo.add_do_method(_restore_weapon_state.bind(weapon, after))
		for g in added:
			controller.undo.add_do_method(_add.bind(g))
		for g in removed:
			controller.undo.add_do_method(_remove.bind(g))
		controller.undo.add_undo_method(_restore_weapon_state.bind(weapon, before))
		for g in added:
			controller.undo.add_undo_method(_remove.bind(g))
		for g in removed:
			controller.undo.add_undo_method(_add.bind(g))
		controller.undo.commit_action(false)


func _set_weapon_drive(weapon: Weapon, mode: String) -> void:
	if mode == "weapon":
		weapon.drive = "weapon"
		if not weapon.hold.is_empty():
			var holder := scene.get_character(weapon.hold["character"])
			if holder:
				_attach_to_weapon_raw(holder, weapon.hold["hand"], weapon, weapon.hold["t"], false)
	else:
		if weapon.hold.is_empty():
			return
		var holder := scene.get_character(weapon.hold["character"])
		if holder == null:
			return
		var existing := grip_on_limb(holder.character_id, weapon.hold["hand"] + "Arm")
		if existing and existing.target.kind == GripTarget.Kind.WEAPON and existing.target.weapon_id == weapon.weapon_id:
			_remove(existing)
		weapon.drive = "hand"
		weapon.set_hold_offset_from_current(holder.bone_world_transform(weapon.hold["hand"] + "Hand"))
	_rebuild()


## Distance between two anchor points on two weapons, in metres.
func contact_gap(a: Weapon, t_a: float, b: Weapon, t_b: float) -> float:
	return a.anchor_transform(t_a).origin.distance_to(b.anchor_transform(t_b).origin)


## Translates so the two anchor points touch: the weapon-driven weapon moves (b preferred), or
## if both are hand-driven, `mover`'s holder hand IK target moves.
func close_gap(a: Weapon, t_a: float, b: Weapon, t_b: float, mover: Weapon = null) -> void:
	var delta := a.anchor_transform(t_a).origin - b.anchor_transform(t_b).origin
	var target_weapon: Weapon = mover if mover else (b if b.drive == "weapon" else (a if a.drive == "weapon" else b))
	if target_weapon == a:
		delta = -delta
	if target_weapon.drive == "weapon" or target_weapon.hold.is_empty():
		target_weapon.global_position += delta
		return
	var holder := scene.get_character(target_weapon.hold["character"])
	if holder == null:
		return
	var limb: Limb = holder.limbs[target_weapon.hold["hand"] + "Arm"]
	holder.set_limb_mode(limb.key, Limb.Mode.IK)
	limb.target.global_position += delta


func _grips_on_hand(gripper_id: String, hand: String) -> Array[Grip]:
	var out: Array[Grip] = []
	for grip in grips:
		if grip.gripper_id == gripper_id and grip.hand == hand:
			out.append(grip)
	return out


func _drop_grips_on(weapon: Weapon, gripper_id: String, hand: String) -> void:
	for grip in grips.duplicate():
		if grip.gripper_id == gripper_id and grip.hand == hand:
			_remove(grip)


func _on_weapons_changed() -> void:
	for grip in grips.duplicate():
		if grip.target.kind == GripTarget.Kind.WEAPON and scene.get_weapon(grip.target.weapon_id) == null:
			_remove(grip)
	for weapon in scene.weapons:
		if not weapon.hold.is_empty() and scene.get_character(weapon.hold["character"]) == null:
			weapon.hold = {}
			weapon.drive = "weapon"
	_rebuild()


func grips_for(character_id: String) -> Array[Grip]:
	var out: Array[Grip] = []
	for grip in grips:
		if grip.gripper_id == character_id:
			out.append(grip)
	return out


func grip_on_limb(character_id: String, limb_key: String) -> Grip:
	for grip in grips:
		if grip.gripper_id == character_id and grip.limb_key() == limb_key:
			return grip
	return null


func clear() -> void:
	for grip in grips.duplicate():
		_remove(grip)


func _add(grip: Grip) -> void:
	if grip in grips:
		return
	grip.target.bind(scene)
	grips.append(grip)
	var gripper := scene.get_character(grip.gripper_id)
	if gripper:
		# A gripping hand is placed by its IK target, and takes the target's orientation too, so the
		# palm keeps the angle the instructor gave it when attaching.
		gripper.set_limb_mode(grip.limb_key(), Limb.Mode.IK)
		gripper.limbs[grip.limb_key()].set_orient_to_target(true)
	_rebuild()


func _remove(grip: Grip) -> void:
	if not grip in grips:
		return
	grips.erase(grip)
	var gripper := scene.get_character(grip.gripper_id)
	if gripper:
		# Leave the hand where the grip had it; the instructor carries on from there.
		gripper.limbs[grip.limb_key()].set_orient_to_target(false)
	_rebuild()


func _on_characters_changed() -> void:
	# Drop grips whose gripper or bone target no longer exists.
	for grip in grips.duplicate():
		var gripper := scene.get_character(grip.gripper_id)
		var target_alive: bool = grip.target.kind != GripTarget.Kind.BONE or scene.get_character(grip.target.character_id) != null
		if gripper == null or not target_alive:
			_remove(grip)
	_on_weapons_changed()


# ---------------------------------------------------------------- evaluation

func _rebuild() -> void:
	_reorder_characters()
	_reconnect()
	grips_changed.emit()


## Public entry for code that changed holds or drive modes behind the director's back
## (sequence playback): re-derives the evaluation order and signal connections.
func rebuild() -> void:
	_rebuild()


## Sorts characters so that every grip's target comes before its gripper in the scene tree.
## Cycles (A grips B and B grips A) are allowed: the edge that closes the cycle is dropped from the
## ordering and resolves one frame late, which is invisible at 30 fps and absent from baked stills.
func _reorder_characters() -> void:
	var ids: Array[String] = []
	for rig in scene.characters:
		ids.append(rig.character_id)
	var depends: Dictionary = {}   ## id -> ids it must come after
	for id in ids:
		depends[id] = []
	for grip in grips:
		var before: String = _target_owner_character(grip)
		if before in ids and grip.gripper_id in ids and before != grip.gripper_id:
			depends[grip.gripper_id].append(before)
	var ordered: Array[String] = []
	var guard := ids.size() + 1
	while ids.size() > 0 and guard > 0:
		guard -= 1
		var progressed := false
		for id in ids.duplicate():
			var ready := true
			for dep in depends[id]:
				if dep in ids:
					ready = false
					break
			if ready:
				ordered.append(id)
				ids.erase(id)
				progressed = true
		if not progressed:
			# A cycle: break it by taking the remaining characters in their current order.
			ordered.append_array(ids)
			break
	for i in ordered.size():
		var rig := scene.get_character(ordered[i])
		if rig:
			scene.move_child(rig, i)


## The character whose skeleton the grip's target hangs off: the bone's character, or the holder
## of a hand-driven weapon. Empty for weapon-driven weapons.
func _target_owner_character(grip: Grip) -> String:
	if grip.target.kind == GripTarget.Kind.BONE:
		return grip.target.character_id
	var weapon := scene.get_weapon(grip.target.weapon_id)
	if weapon and weapon.drive == "hand" and not weapon.hold.is_empty():
		return weapon.hold["character"]
	return ""


func _reconnect() -> void:
	for id in _connected.keys():
		var rig := scene.get_character(id)
		if rig and rig.skeleton.skeleton_updated.is_connected(_connected[id]):
			rig.skeleton.skeleton_updated.disconnect(_connected[id])
	_connected.clear()
	# One connection per character that something grips or that holds a hand-driven weapon,
	# firing while its pose is live.
	var ids: Array[String] = []
	for grip in grips:
		var owner := _target_owner_character(grip)
		if owner != "":
			ids.append(owner)
	for weapon in scene.weapons:
		if weapon.drive == "hand" and not weapon.hold.is_empty():
			ids.append(weapon.hold["character"])
	for id in ids:
		if _connected.has(id):
			continue
		var rig := scene.get_character(id)
		if rig == null:
			continue
		var callable := _apply_grips_targeting.bind(id)
		rig.skeleton.skeleton_updated.connect(callable)
		_connected[id] = callable


func _apply_grips_targeting(character_id: String) -> void:
	var rig := scene.get_character(character_id)
	# Hand-driven weapons follow their holder's hand first, so grips on them see the live weapon.
	for weapon in scene.weapons:
		if weapon.drive == "hand" and not weapon.hold.is_empty() and weapon.hold["character"] == character_id and rig:
			weapon.global_transform = _held_transform(weapon, rig.bone_world_transform(weapon.hold["hand"] + "Hand"))
	for grip in grips:
		if _target_owner_character(grip) == character_id:
			_apply(grip)


## Weapon-driven weapons have no skeleton to hang off, so their grips are refreshed at the start
## of every frame, before the skeletons solve.
func _notification(what: int) -> void:
	if what == NOTIFICATION_INTERNAL_PROCESS:
		for grip in grips:
			if grip.target.kind == GripTarget.Kind.WEAPON and _target_owner_character(grip) == "":
				_apply(grip)


## Where a hand-driven weapon goes for a given hand transform, honouring a partial hold during
## sequence playback (the weapon slides between its free transform and the hand).
func _held_transform(weapon: Weapon, hand_world: Transform3D) -> Transform3D:
	var held: Transform3D = hand_world * weapon.hold["offset"]
	if weapon.hold_influence >= 1.0:
		return held
	return weapon.free_transform.interpolate_with(held, weapon.hold_influence)


## Where the weapon currently hangs (hand-driven), refreshed for callers outside skeleton_updated.
func refresh_hand_driven() -> void:
	for weapon in scene.weapons:
		if weapon.drive == "hand" and not weapon.hold.is_empty():
			var rig := scene.get_character(weapon.hold["character"])
			if rig:
				weapon.global_transform = _held_transform(weapon, rig.bone_world_transform(weapon.hold["hand"] + "Hand"))


func _apply(grip: Grip) -> void:
	var gripper := scene.get_character(grip.gripper_id)
	if gripper == null:
		return
	var limb: Limb = gripper.limbs.get(grip.limb_key())
	if limb == null:
		return
	limb.target.global_transform = grip.desired_hand_transform()


# ---------------------------------------------------------------- reporting

## How far one gripping hand is from where its grip wants it, in metres. Non-zero means the arm
## cannot reach: the IK stops short rather than stretching.
func error_for(grip: Grip) -> float:
	var gripper := scene.get_character(grip.gripper_id)
	if gripper == null:
		return 0.0
	return grip.desired_hand_transform().origin.distance_to(gripper.bone_world_transform(grip.hand + "Hand").origin)


## The worst such error across every grip.
func worst_error() -> float:
	var worst := 0.0
	for grip in grips:
		worst = maxf(worst, error_for(grip))
	return worst
