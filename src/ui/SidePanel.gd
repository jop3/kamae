class_name SidePanel
extends PanelContainer
## Right-hand dock: characters, selected joint, root placement, export.

signal export_requested(transparent: bool)

var controller: PoseController
var scene: PosingScene
var grips: GripDirector
var camera: OrbitCamera

var _char_list: ItemList
var _joint_label: Label
var _euler: Array[HSlider] = []
var _euler_vals: Array[Label] = []
var _root_x: SpinBox
var _root_z: SpinBox
var _root_yaw: SpinBox
var _limb_buttons: Dictionary = {}   ## limb key -> CheckButton
var _limb_warnings: Dictionary = {}  ## limb key -> Label
var _limb_orient: Dictionary = {}    ## limb key -> CheckBox
var _grip_target_label: Label
var _grip_who: OptionButton
var _grip_hand: OptionButton
var _grip_list: ItemList
var _finger_sliders: Dictionary = {} ## finger -> HSlider
var _finger_side := "Right"
var _finger_side_button: OptionButton
var _finger_old := 0.0
var _updating := false
var _slider_old_q := Quaternion.IDENTITY
var _root_old := {}
var _weapon_type: OptionButton
var _weapon_list: ItemList
var _weapon_holder: OptionButton
var _weapon_hand: OptionButton
var _weapon_t: SpinBox
var _weapon_roll: SpinBox
var _weapon_drive: CheckButton
var _weapon_x: SpinBox
var _weapon_z: SpinBox
var _weapon_yaw: SpinBox
var _pose_name: LineEdit
var _pose_list: ItemList
const POSES_DIR := "user://poses"


func setup(ctrl: PoseController, posing_scene: PosingScene, grip_director: GripDirector = null, orbit_camera: OrbitCamera = null) -> void:
	controller = ctrl
	scene = posing_scene
	grips = grip_director
	camera = orbit_camera
	custom_minimum_size.x = 300
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	vb.add_child(_header("Characters"))
	_char_list = ItemList.new()
	_char_list.custom_minimum_size.y = 110
	_char_list.item_selected.connect(func(i): controller.select(scene.characters[i], ""))
	vb.add_child(_char_list)

	vb.add_child(_header("Place character"))
	var g := GridContainer.new(); g.columns = 2; vb.add_child(g)
	_root_x = _spin(g, "X (m)", -5, 5, 0.01)
	_root_z = _spin(g, "Z (m)", -5, 5, 0.01)
	_root_yaw = _spin(g, "Turn (°)", -360, 360, 1)
	for sb in [_root_x, _root_z, _root_yaw]:
		sb.value_changed.connect(_on_root_changed)
	var turn := Button.new(); turn.text = "Turn 180°"
	turn.pressed.connect(func(): if controller.selected_rig: _root_yaw.value = wrapf(_root_yaw.value + 180.0, -180.0, 180.0))
	vb.add_child(turn)

	vb.add_child(_header("Selected joint"))
	_joint_label = Label.new(); _joint_label.text = "Click a body part"; vb.add_child(_joint_label)
	for i in 3:
		var row := HBoxContainer.new(); vb.add_child(row)
		var l := Label.new(); l.text = ["X", "Y", "Z"][i]; l.custom_minimum_size.x = 16; row.add_child(l)
		var s := HSlider.new(); s.min_value = -180; s.max_value = 180; s.step = 0.5
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.value_changed.connect(_on_euler_changed)
		s.drag_started.connect(_on_euler_drag_started)
		s.drag_ended.connect(_on_euler_drag_ended)
		row.add_child(s); _euler.append(s)
		var v := Label.new(); v.custom_minimum_size.x = 48; v.text = "0°"; row.add_child(v); _euler_vals.append(v)
	var reset := Button.new(); reset.text = "Reset joint"
	reset.pressed.connect(func(): if controller.selected_bone != "": controller.reset_bone(controller.selected_rig, controller.selected_bone))
	vb.add_child(reset)

	vb.add_child(_header("Arms and legs"))
	var hint := Label.new()
	hint.text = "IK: drag the blue ball to place the hand or foot,\nthe grey ball steers the elbow or knee."
	hint.add_theme_font_size_override("font_size", 11)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hint)
	for limb_key in ["RightArm", "LeftArm", "RightLeg", "LeftLeg"]:
		var row := HBoxContainer.new(); vb.add_child(row)
		var cb := CheckButton.new()
		cb.text = _limb_label(limb_key)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.toggled.connect(_on_limb_toggled.bind(limb_key))
		row.add_child(cb)
		_limb_buttons[limb_key] = cb
		var orient := CheckBox.new()
		orient.text = "turn"
		orient.tooltip_text = "Hand or foot also takes the target's rotation"
		orient.toggled.connect(func(pressed: bool):
			if not _updating and controller.selected_rig:
				controller.selected_rig.limbs[limb_key].set_orient_to_target(pressed))
		row.add_child(orient)
		_limb_orient[limb_key] = orient
		var warn := Label.new()
		warn.add_theme_color_override("font_color", Color(0.85, 0.15, 0.15))
		warn.add_theme_font_size_override("font_size", 11)
		warn.custom_minimum_size.x = 70
		row.add_child(warn)
		_limb_warnings[limb_key] = warn

	vb.add_child(_header("Grips"))
	var grip_hint := Label.new()
	grip_hint.text = "Click the body part to be gripped, pick who grips it, then Attach."
	grip_hint.add_theme_font_size_override("font_size", 11)
	grip_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(grip_hint)
	_grip_target_label = Label.new()
	_grip_target_label.text = "No body part selected"
	vb.add_child(_grip_target_label)
	var grip_row := HBoxContainer.new(); vb.add_child(grip_row)
	_grip_who = OptionButton.new(); grip_row.add_child(_grip_who)
	_grip_hand = OptionButton.new()
	_grip_hand.add_item("right hand"); _grip_hand.add_item("left hand")
	grip_row.add_child(_grip_hand)
	var attach := Button.new(); attach.text = "Attach"
	attach.pressed.connect(_on_attach_pressed)
	vb.add_child(attach)
	_grip_list = ItemList.new()
	_grip_list.custom_minimum_size.y = 70
	vb.add_child(_grip_list)
	var release := Button.new(); release.text = "Release selected grip"
	release.pressed.connect(_on_release_pressed)
	vb.add_child(release)

	vb.add_child(_header("Fingers"))
	_finger_side_button = OptionButton.new()
	_finger_side_button.add_item("Right hand")
	_finger_side_button.add_item("Left hand")
	_finger_side_button.item_selected.connect(func(i: int):
		_finger_side = "Right" if i == 0 else "Left"
		_refresh_values())
	vb.add_child(_finger_side_button)
	for finger in FingerCurl.FINGERS:
		var row := HBoxContainer.new(); vb.add_child(row)
		var l := Label.new(); l.text = finger; l.custom_minimum_size.x = 52; row.add_child(l)
		var sl := HSlider.new(); sl.min_value = 0.0; sl.max_value = 1.0; sl.step = 0.01
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.value_changed.connect(_on_finger_changed.bind(finger))
		sl.drag_started.connect(func(): _finger_old = controller.selected_rig.fingers.get_curl(_finger_side, finger) if controller.selected_rig else 0.0)
		sl.drag_ended.connect(func(changed: bool):
			if changed and controller.selected_rig:
				controller.commit_finger_curl(controller.selected_rig, _finger_side, finger, _finger_old, sl.value))
		row.add_child(sl)
		_finger_sliders[finger] = sl
	var finger_buttons := HBoxContainer.new(); vb.add_child(finger_buttons)
	var grip := Button.new(); grip.text = "Grip"
	grip.pressed.connect(func():
		if controller.selected_rig:
			controller.apply_grip_preset(controller.selected_rig, _finger_side)
			_refresh_values())
	finger_buttons.add_child(grip)
	var open_hand := Button.new(); open_hand.text = "Open"
	open_hand.pressed.connect(func():
		if controller.selected_rig:
			for f in FingerCurl.FINGERS:
				controller.set_finger_curl(controller.selected_rig, _finger_side, f, 0.0)
			_refresh_values())
	finger_buttons.add_child(open_hand)

	vb.add_child(_header("Weapons"))
	var wrow := HBoxContainer.new(); vb.add_child(wrow)
	_weapon_type = OptionButton.new()
	for t in ["bokken", "jo", "tanto"]:
		_weapon_type.add_item(t)
	wrow.add_child(_weapon_type)
	var add_w := Button.new(); add_w.text = "Add weapon"
	add_w.pressed.connect(func():
		var type: String = _weapon_type.get_item_text(_weapon_type.selected)
		scene.add_weapon(scene.next_free_id(type), type))
	wrow.add_child(add_w)
	_weapon_list = ItemList.new()
	_weapon_list.custom_minimum_size.y = 60
	_weapon_list.item_selected.connect(func(_i): _refresh_weapon_values())
	vb.add_child(_weapon_list)
	var hrow := HBoxContainer.new(); vb.add_child(hrow)
	_weapon_holder = OptionButton.new(); hrow.add_child(_weapon_holder)
	_weapon_hand = OptionButton.new()
	_weapon_hand.add_item("right hand"); _weapon_hand.add_item("left hand")
	hrow.add_child(_weapon_hand)
	var wg := GridContainer.new(); wg.columns = 2; vb.add_child(wg)
	_weapon_t = _spin(wg, "t (0..1)", 0.0, 1.0, 0.01)
	_weapon_t.allow_greater = false; _weapon_t.allow_lesser = false
	_weapon_roll = _spin(wg, "Roll (°)", -180, 180, 1)
	var hold := Button.new(); hold.text = "Hold"
	hold.pressed.connect(_on_hold_pressed)
	vb.add_child(hold)
	var attach_other := Button.new(); attach_other.text = "Attach selected character's other hand at t"
	attach_other.pressed.connect(_on_attach_weapon_pressed)
	vb.add_child(attach_other)
	_weapon_drive = CheckButton.new(); _weapon_drive.text = "Weapon-driven"
	_weapon_drive.toggled.connect(_on_weapon_drive_toggled)
	vb.add_child(_weapon_drive)
	var wpg := GridContainer.new(); wpg.columns = 2; vb.add_child(wpg)
	_weapon_x = _spin(wpg, "Weapon X (m)", -5, 5, 0.01)
	_weapon_z = _spin(wpg, "Weapon Z (m)", -5, 5, 0.01)
	_weapon_yaw = _spin(wpg, "Weapon turn (°)", -360, 360, 1)
	for sb in [_weapon_x, _weapon_z, _weapon_yaw]:
		sb.value_changed.connect(_on_weapon_pos_changed)
	var remove_w := Button.new(); remove_w.text = "Remove weapon"
	remove_w.pressed.connect(func():
		var w := _selected_weapon()
		if w: scene.remove_weapon(w.weapon_id))
	vb.add_child(remove_w)

	vb.add_child(_header("Camera"))
	var crow := HBoxContainer.new(); vb.add_child(crow)
	var cam_front := Button.new(); cam_front.text = "Front"
	cam_front.pressed.connect(func(): if camera: camera.apply_preset(CameraPresets.front(scene)))
	crow.add_child(cam_front)
	var cam_side := Button.new(); cam_side.text = "Side"
	cam_side.pressed.connect(func(): if camera: camera.apply_preset(CameraPresets.side(scene)))
	crow.add_child(cam_side)

	vb.add_child(_header("Poses"))
	_pose_name = LineEdit.new(); _pose_name.placeholder_text = "Pose name"
	vb.add_child(_pose_name)
	var save_pose := Button.new(); save_pose.text = "Save pose"
	save_pose.pressed.connect(_on_save_pose_pressed)
	vb.add_child(save_pose)
	_pose_list = ItemList.new()
	_pose_list.custom_minimum_size.y = 70
	vb.add_child(_pose_list)
	var load_pose := Button.new(); load_pose.text = "Load pose"
	load_pose.pressed.connect(_on_load_pose_pressed)
	vb.add_child(load_pose)

	vb.add_child(_header("Edit"))
	var ur := HBoxContainer.new(); vb.add_child(ur)
	var u := Button.new(); u.text = "Undo (Ctrl+Z)"; u.pressed.connect(func(): controller.undo.undo(); controller.pose_changed.emit()); ur.add_child(u)
	var r := Button.new(); r.text = "Redo (Ctrl+Y)"; r.pressed.connect(func(): controller.undo.redo(); controller.pose_changed.emit()); ur.add_child(r)

	vb.add_child(_header("Export"))
	var transparent := CheckBox.new(); transparent.text = "Transparent background"; vb.add_child(transparent)
	var ex := Button.new(); ex.text = "Export still (PNG)"
	ex.pressed.connect(func(): export_requested.emit(transparent.button_pressed))
	vb.add_child(ex)

	controller.selection_changed.connect(_on_selection_changed)
	controller.limb_changed.connect(func(_r, _k): _refresh_values())
	controller.pose_changed.connect(_refresh_values)
	scene.characters_changed.connect(_refresh_characters)
	scene.weapons_changed.connect(_refresh_weapons)
	if grips:
		grips.grips_changed.connect(_refresh_grips)
	_refresh_characters()
	_refresh_grips()
	_refresh_weapons()
	_refresh_poses()
	_set_joint_enabled(false)


func _header(t: String) -> Label:
	var l := Label.new(); l.text = t
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.25, 0.25, 0.25))
	return l


func _spin(parent: Node, label: String, lo: float, hi: float, step: float) -> SpinBox:
	var l := Label.new(); l.text = label; parent.add_child(l)
	var sb := SpinBox.new(); sb.min_value = lo; sb.max_value = hi; sb.step = step; sb.allow_greater = true; sb.allow_lesser = true
	parent.add_child(sb)
	return sb


func _refresh_characters() -> void:
	_char_list.clear()
	for c in scene.characters:
		_char_list.add_item("%s  (%s)" % [c.display_name, c.role])
		_char_list.set_item_icon_modulate(_char_list.item_count - 1, c.get_skin_color())
	if _grip_who:
		_grip_who.clear()
		for c in scene.characters:
			_grip_who.add_item(c.display_name)
	if _weapon_holder:
		_weapon_holder.clear()
		for c in scene.characters:
			_weapon_holder.add_item(c.display_name)
	_refresh_values()


func _refresh_grips() -> void:
	if grips == null or _grip_list == null:
		return
	_grip_list.clear()
	for grip in grips.grips:
		_grip_list.add_item(grip.describe())


func _on_attach_pressed() -> void:
	if grips == null or controller.selected_rig == null or controller.selected_bone == "":
		return
	var gripper: CharacterRig = scene.characters[_grip_who.selected] if _grip_who.selected >= 0 else null
	if gripper == null or gripper == controller.selected_rig:
		return   # a hand cannot grip its own body
	var hand := "Right" if _grip_hand.selected == 0 else "Left"
	grips.attach(gripper, hand, GripTarget.for_bone(scene, controller.selected_rig.character_id, controller.selected_bone))


func _on_release_pressed() -> void:
	if grips == null:
		return
	var selected := _grip_list.get_selected_items()
	if selected.is_empty():
		return
	grips.detach(grips.grips[selected[0]])


func _on_selection_changed(rig: CharacterRig, bone_name: String) -> void:
	if rig:
		var i := scene.characters.find(rig)
		if i >= 0 and not _char_list.is_selected(i):
			_char_list.select(i)
	if _grip_target_label:
		_grip_target_label.text = ("Selected: %s %s" % [rig.display_name, _pretty(bone_name)]) if (rig and bone_name != "") else "No body part selected"
	_joint_label.text = ("%s: %s" % [rig.display_name, _pretty(bone_name)]) if (rig and bone_name != "") else ("%s: whole body" % rig.display_name if rig else "Click a body part")
	_set_joint_enabled(rig != null and bone_name != "")
	_refresh_values()


func _set_joint_enabled(on: bool) -> void:
	for s in _euler:
		s.editable = on


func _process(_delta: float) -> void:
	# Reach warnings change as the instructor drags a target, so they are polled rather than
	# recomputed only on discrete edits.
	var rig := controller.selected_rig
	for limb_key in _limb_warnings:
		var label: Label = _limb_warnings[limb_key]
		if rig == null:
			label.text = ""
			continue
		var limb: Limb = rig.limbs[limb_key]
		var shortfall := limb.reach_shortfall() if limb.mode == Limb.Mode.IK else 0.0
		label.text = "%.0f cm short" % (shortfall * 100.0) if shortfall > 0.005 else ""


func _refresh_values() -> void:
	_updating = true
	var rig := controller.selected_rig
	if rig:
		for limb_key in _limb_buttons:
			var limb: Limb = rig.limbs[limb_key]
			_limb_buttons[limb_key].button_pressed = limb.mode == Limb.Mode.IK
			_limb_orient[limb_key].button_pressed = limb.orient_to_target
		for finger in _finger_sliders:
			_finger_sliders[finger].value = rig.fingers.get_curl(_finger_side, finger)
		_root_x.value = rig.position.x
		_root_z.value = rig.position.z
		_root_yaw.value = rad_to_deg(rig.rotation.y)
		if controller.selected_bone != "":
			var e := controller.get_bone_rotation(rig, controller.selected_bone).get_euler()
			for i in 3:
				_euler[i].value = rad_to_deg(e[i])
				_euler_vals[i].text = "%.0f°" % rad_to_deg(e[i])
	_updating = false


func _on_euler_changed(_v: float) -> void:
	if _updating or controller.selected_bone == "":
		return
	var q := Quaternion.from_euler(Vector3(deg_to_rad(_euler[0].value), deg_to_rad(_euler[1].value), deg_to_rad(_euler[2].value)))
	controller.set_bone_rotation(controller.selected_rig, controller.selected_bone, q)
	for i in 3:
		_euler_vals[i].text = "%.0f°" % _euler[i].value


func _on_euler_drag_started() -> void:
	if controller.selected_bone != "":
		_slider_old_q = controller.get_bone_rotation(controller.selected_rig, controller.selected_bone)


func _on_euler_drag_ended(changed: bool) -> void:
	if changed and controller.selected_bone != "":
		controller.commit_bone_rotation(controller.selected_rig, controller.selected_bone, _slider_old_q, controller.get_bone_rotation(controller.selected_rig, controller.selected_bone))


func _on_root_changed(_v: float) -> void:
	if _updating or controller.selected_rig == null:
		return
	var rig := controller.selected_rig
	var old_pos := rig.position
	var old_yaw := rig.rotation.y
	var new_pos := Vector3(_root_x.value, 0, _root_z.value)
	var new_yaw := deg_to_rad(_root_yaw.value)
	controller.set_root(rig, new_pos, new_yaw)
	controller.commit_root(rig, old_pos, old_yaw, new_pos, new_yaw)


static func _pretty(bone: String) -> String:
	var s := bone
	for pair in [["Left", "left "], ["Right", "right "], ["UpperArm", "upper arm"], ["LowerArm", "forearm"], ["UpperLeg", "thigh"], ["LowerLeg", "shin"], ["UpperChest", "upper chest"], ["Metacarpal", " base"], ["Proximal", " 1"], ["Intermediate", " 2"], ["Distal", " tip"], ["Little", "pinky"]]:
		s = s.replace(pair[0], pair[1])
	return s.to_lower()


func _on_limb_toggled(pressed: bool, limb_key: String) -> void:
	if _updating or controller.selected_rig == null:
		return
	controller.set_limb_mode(controller.selected_rig, limb_key, Limb.Mode.IK if pressed else Limb.Mode.FK)


func _on_finger_changed(value: float, finger: String) -> void:
	if _updating or controller.selected_rig == null:
		return
	controller.set_finger_curl(controller.selected_rig, _finger_side, finger, value)


static func _limb_label(limb_key: String) -> String:
	match limb_key:
		"RightArm": return "Right arm IK"
		"LeftArm": return "Left arm IK"
		"RightLeg": return "Right leg IK"
		_: return "Left leg IK"


# ---------------------------------------------------------------- weapons

func _selected_weapon() -> Weapon:
	if _weapon_list == null:
		return null
	var sel := _weapon_list.get_selected_items()
	if sel.is_empty() or sel[0] >= scene.weapons.size():
		return null
	return scene.weapons[sel[0]]


func _refresh_weapons() -> void:
	if _weapon_list == null:
		return
	var prev := _weapon_list.get_selected_items()
	_weapon_list.clear()
	for w in scene.weapons:
		_weapon_list.add_item("%s  (%s%s)" % [w.weapon_id, w.type, ", weapon-driven" if w.drive == "weapon" else ""])
	if not prev.is_empty() and prev[0] < _weapon_list.item_count:
		_weapon_list.select(prev[0])
	elif _weapon_list.item_count > 0:
		_weapon_list.select(_weapon_list.item_count - 1)
	_refresh_weapon_values()


func _refresh_weapon_values() -> void:
	var w := _selected_weapon()
	_updating = true
	var driven := w != null and w.drive == "weapon"
	_weapon_drive.button_pressed = driven
	for sb in [_weapon_x, _weapon_z, _weapon_yaw]:
		sb.editable = driven
	if w:
		_weapon_x.value = w.global_position.x
		_weapon_z.value = w.global_position.z
		_weapon_yaw.value = rad_to_deg(w.global_rotation.y)
		if not w.hold.is_empty():
			_weapon_t.value = w.hold.get("t", _weapon_t.value)
			_weapon_roll.value = w.hold.get("roll_deg", _weapon_roll.value)
	_updating = false


func _holder_rig() -> CharacterRig:
	return scene.characters[_weapon_holder.selected] if _weapon_holder.selected >= 0 and _weapon_holder.selected < scene.characters.size() else null


func _on_hold_pressed() -> void:
	var w := _selected_weapon()
	var rig := _holder_rig()
	if grips == null or w == null or rig == null:
		return
	var hand := "Right" if _weapon_hand.selected == 0 else "Left"
	grips.hold_weapon(rig, hand, w, _weapon_t.value, _weapon_roll.value)
	controller.pose_changed.emit()
	_refresh_weapons()


func _on_attach_weapon_pressed() -> void:
	var w := _selected_weapon()
	var rig := controller.selected_rig
	if grips == null or w == null or rig == null:
		return
	var other := "Left" if _weapon_hand.selected == 0 else "Right"
	if not w.hold.is_empty() and w.hold.get("character", "") == rig.character_id:
		other = "Left" if w.hold.get("hand", "Right") == "Right" else "Right"
	grips.attach_to_weapon(rig, other, w, _weapon_t.value)
	controller.pose_changed.emit()


func _on_weapon_drive_toggled(pressed: bool) -> void:
	if _updating:
		return
	var w := _selected_weapon()
	if grips == null or w == null:
		return
	grips.set_weapon_drive(w, "weapon" if pressed else "hand")
	controller.pose_changed.emit()
	_refresh_weapons()


func _on_weapon_pos_changed(_v: float) -> void:
	if _updating:
		return
	var w := _selected_weapon()
	if w == null or w.drive != "weapon":
		return
	w.global_position = Vector3(_weapon_x.value, w.global_position.y, _weapon_z.value)
	w.global_rotation.y = deg_to_rad(_weapon_yaw.value)
	if grips:
		grips.refresh_hand_driven()
	controller.pose_changed.emit()


# ---------------------------------------------------------------- poses

func _refresh_poses() -> void:
	if _pose_list == null:
		return
	_pose_list.clear()
	var names: Array[String] = []
	var d := DirAccess.open(POSES_DIR)
	if d:
		for f in d.get_files():
			if f.get_extension() == "json":
				names.append(f.get_basename())
	names.sort()
	for n in names:
		_pose_list.add_item(n)


func _on_save_pose_pressed() -> void:
	var name := _pose_name.text.strip_edges()
	if name == "":
		name = "pose"
	var data: Dictionary = await PoseFile.capture_baked(scene, grips, camera, name)
	var err := PoseFile.save(PoseFile.pose_path(POSES_DIR, name), data)
	if err != OK:
		push_error("SidePanel: could not save pose (%s)" % error_string(err))
	_refresh_poses()


func _on_load_pose_pressed() -> void:
	var sel := _pose_list.get_selected_items()
	if sel.is_empty():
		return
	var path := POSES_DIR.path_join(_pose_list.get_item_text(sel[0]) + ".json")
	var data := PoseFile.load(path)
	if data.is_empty():
		return
	PoseFile.apply(data, scene, grips, controller)
	_pose_name.text = str(data.get("name", _pose_list.get_item_text(sel[0])))
	controller.pose_changed.emit()
	_refresh_weapons()
	_refresh_grips()
