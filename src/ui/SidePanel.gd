class_name SidePanel
extends PanelContainer
## Right-hand dock: characters, selected joint, root placement, export.

signal export_requested(transparent: bool)

var controller: PoseController
var scene: PosingScene
var grips: GripDirector

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


func setup(ctrl: PoseController, posing_scene: PosingScene, grip_director: GripDirector = null) -> void:
	controller = ctrl
	scene = posing_scene
	grips = grip_director
	custom_minimum_size.x = 300
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	add_child(vb)

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
	if grips:
		grips.grips_changed.connect(_refresh_grips)
	_refresh_characters()
	_refresh_grips()
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
