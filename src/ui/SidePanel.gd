class_name SidePanel
extends PanelContainer
## Right-hand dock: characters, selected joint, root placement, export.

signal export_requested(transparent: bool)

var controller: PoseController
var scene: PosingScene

var _char_list: ItemList
var _joint_label: Label
var _euler: Array[HSlider] = []
var _euler_vals: Array[Label] = []
var _root_x: SpinBox
var _root_z: SpinBox
var _root_yaw: SpinBox
var _updating := false
var _slider_old_q := Quaternion.IDENTITY
var _root_old := {}


func setup(ctrl: PoseController, posing_scene: PosingScene) -> void:
	controller = ctrl
	scene = posing_scene
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
	controller.pose_changed.connect(_refresh_values)
	scene.characters_changed.connect(_refresh_characters)
	_refresh_characters()
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
	_refresh_values()


func _on_selection_changed(rig: CharacterRig, bone_name: String) -> void:
	if rig:
		var i := scene.characters.find(rig)
		if i >= 0 and not _char_list.is_selected(i):
			_char_list.select(i)
	_joint_label.text = ("%s: %s" % [rig.display_name, _pretty(bone_name)]) if (rig and bone_name != "") else ("%s: whole body" % rig.display_name if rig else "Click a body part")
	_set_joint_enabled(rig != null and bone_name != "")
	_refresh_values()


func _set_joint_enabled(on: bool) -> void:
	for s in _euler:
		s.editable = on


func _refresh_values() -> void:
	_updating = true
	var rig := controller.selected_rig
	if rig:
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
