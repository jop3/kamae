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
	_rebuild()


# ---------------------------------------------------------------- evaluation

func _rebuild() -> void:
	_reorder_characters()
	_reconnect()
	grips_changed.emit()


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
		if grip.target.kind != GripTarget.Kind.BONE:
			continue
		var before: String = grip.target.character_id
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


func _reconnect() -> void:
	for id in _connected.keys():
		var rig := scene.get_character(id)
		if rig and rig.skeleton.skeleton_updated.is_connected(_connected[id]):
			rig.skeleton.skeleton_updated.disconnect(_connected[id])
	_connected.clear()
	# One connection per character that something grips, firing while its pose is live.
	for grip in grips:
		if grip.target.kind != GripTarget.Kind.BONE:
			continue
		var id: String = grip.target.character_id
		if _connected.has(id):
			continue
		var rig := scene.get_character(id)
		if rig == null:
			continue
		var callable := _apply_grips_targeting.bind(id)
		rig.skeleton.skeleton_updated.connect(callable)
		_connected[id] = callable


func _apply_grips_targeting(character_id: String) -> void:
	for grip in grips:
		if grip.target.kind == GripTarget.Kind.BONE and grip.target.character_id == character_id:
			_apply(grip)


## Weapon-anchored grips have no skeleton to hang off, so they are refreshed every frame.
func _process(_delta: float) -> void:
	for grip in grips:
		if grip.target.kind != GripTarget.Kind.BONE:
			_apply(grip)


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
