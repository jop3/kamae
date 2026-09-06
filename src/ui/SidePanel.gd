class_name SidePanel
extends PanelContainer
## Right-hand dock: characters, selected joint, root placement, export.

signal export_requested(transparent: bool)
signal video_export_requested(sequence: Sequence)
signal stills_export_requested(sequence: Sequence, transparent: bool)

var controller: PoseController
var scene: PosingScene
var grips: GripDirector
var camera: OrbitCamera

var _char_list: ItemList
var _char_role: OptionButton
var _char_name: LineEdit
var _char_color: ColorPickerButton
var _copy_to: OptionButton
var _primary_uke: OptionButton
var _char_visible: CheckBox
var _char_gi: CheckBox
var _seq_camera: OptionButton
var _contact_a: OptionButton
var _contact_b: OptionButton
var _contact_ta: SpinBox
var _contact_tb: SpinBox
var _contact_gap: Label
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
var _collision_label: Label
var _collision_clock := 0.0
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
var player: SequencePlayer
var _seq_name: LineEdit
var _seq_list: ItemList
var _seq_files: ItemList
var _seq_transition: SpinBox
var _seq_hold: SpinBox
var _seq_scrub: HSlider
var _seq_time: Label
var _sequence: Sequence
var _export_status: Label
## Poses and sequences live in the project folder, next to the code, so the acceptance
## techniques ship with the repository and the instructor's own work is versioned with it.
## An exported build cannot write into res://, so it falls back to the user folder.
static var POSES_DIR := "res://poses"
static var SEQUENCES_DIR := "res://sequences"


## Picks writable data folders: the project's own when running from source, the user folder in
## an exported build where res:// is read-only. Called once at startup.
static func choose_data_dirs() -> void:
	var probe := "res://poses/.write_probe"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://poses"))
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f:
		f.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(probe))
		POSES_DIR = "res://poses"
		SEQUENCES_DIR = "res://sequences"
	else:
		POSES_DIR = "user://poses"
		SEQUENCES_DIR = "user://sequences"
	for d in [POSES_DIR, SEQUENCES_DIR]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))


func setup(ctrl: PoseController, posing_scene: PosingScene, grip_director: GripDirector = null, orbit_camera: OrbitCamera = null, sequence_player: SequencePlayer = null) -> void:
	controller = ctrl
	scene = posing_scene
	grips = grip_director
	camera = orbit_camera
	player = sequence_player
	choose_data_dirs()
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
	var char_row := HBoxContainer.new(); vb.add_child(char_row)
	_char_role = OptionButton.new()
	for role in ["Uke", "Tori", "Other"]:
		_char_role.add_item(role)
	char_row.add_child(_char_role)
	var add_char := Button.new(); add_char.text = "Add"; add_char.tooltip_text = "Add a character with this role (at most 5)"
	add_char.pressed.connect(_on_add_character_pressed); char_row.add_child(add_char)
	var dup_char := Button.new(); dup_char.text = "Duplicate"; dup_char.tooltip_text = "A copy of the selected character, same pose"
	dup_char.pressed.connect(_on_duplicate_character_pressed); char_row.add_child(dup_char)
	var rem_char := Button.new(); rem_char.text = "Remove"; rem_char.tooltip_text = "Remove the selected character; its grips are released"
	rem_char.pressed.connect(_on_remove_character_pressed); char_row.add_child(rem_char)
	var name_row := HBoxContainer.new(); vb.add_child(name_row)
	_char_name = LineEdit.new(); _char_name.placeholder_text = "Name"; _char_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_char_name.text_submitted.connect(func(t: String): _rename_selected(t))
	name_row.add_child(_char_name)
	_char_color = ColorPickerButton.new(); _char_color.custom_minimum_size.x = 44
	_char_color.tooltip_text = "Skin colour"
	_char_color.color_changed.connect(func(c: Color):
		if not _updating and controller.selected_rig:
			controller.selected_rig.set_skin_color(c)
			_refresh_characters())
	name_row.add_child(_char_color)
	_char_visible = CheckBox.new(); _char_visible.text = "shown"; _char_visible.button_pressed = true
	_char_visible.tooltip_text = "Hide a figure without removing it (saved with the pose)"
	_char_visible.toggled.connect(func(on: bool):
		if not _updating and controller.selected_rig:
			controller.selected_rig.visible = on)
	name_row.add_child(_char_visible)
	_char_gi = CheckBox.new(); _char_gi.text = "gi"
	_char_gi.tooltip_text = "Dress this character in a white gi with a belt in its colour (saved with the pose)"
	_char_gi.toggled.connect(func(on: bool):
		if not _updating and controller.selected_rig:
			controller.selected_rig.set_gi_visible(on))
	name_row.add_child(_char_gi)
	var pose_row := HBoxContainer.new(); vb.add_child(pose_row)
	var mirror := Button.new(); mirror.text = "Mirror pose"; mirror.tooltip_text = "Swap left and right on the selected character"
	mirror.pressed.connect(func(): if controller.selected_rig: controller.mirror_pose(controller.selected_rig))
	pose_row.add_child(mirror)
	_copy_to = OptionButton.new(); pose_row.add_child(_copy_to)
	var copy := Button.new(); copy.text = "Copy pose to"; copy.tooltip_text = "Give that character the selected character's pose"
	copy.pressed.connect(_on_copy_pose_pressed); pose_row.add_child(copy)

	vb.add_child(_header("Place character"))
	var g := GridContainer.new(); g.columns = 2; vb.add_child(g)
	_root_x = _spin(g, "X (m)", -5, 5, 0.01)
	_root_z = _spin(g, "Z (m)", -5, 5, 0.01)
	_root_yaw = _spin(g, "Turn (°)", -360, 360, 1)
	for sb in [_root_x, _root_z, _root_yaw]:
		sb.value_changed.connect(_on_root_changed)
	var turn := Button.new(); turn.text = "Turn 180°"
	turn.tooltip_text = "Face the other way"
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
	reset.tooltip_text = "Back to the rest rotation (Ctrl+Z undoes)"
	reset.pressed.connect(func(): if controller.selected_rig and controller.selected_bone != "": controller.reset_bone(controller.selected_rig, controller.selected_bone))
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
	grip_hint.text = "Click the body part to be gripped, pick who grips it, then Attach. On an arm or leg the hand wraps round the limb on the side it is on now."
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
	attach.tooltip_text = "Keeps the chosen hand on the selected body part while either figure moves"
	attach.pressed.connect(_on_attach_pressed)
	vb.add_child(attach)
	_grip_list = ItemList.new()
	_grip_list.custom_minimum_size.y = 70
	vb.add_child(_grip_list)
	var release := Button.new(); release.text = "Release selected grip"
	release.pressed.connect(_on_release_pressed)
	vb.add_child(release)
	_collision_label = Label.new()
	_collision_label.add_theme_font_size_override("font_size", 11)
	_collision_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_collision_label.tooltip_text = "Body parts passing through each other or through a weapon, checked as you pose"
	vb.add_child(_collision_label)

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
	var both := Button.new(); both.text = "Both hands, default hold"
	both.tooltip_text = "Right hand in front (just below the tsuba on a bokken), left at the back, palms turned in from the sides; the starting grip for bokken and jo"
	both.pressed.connect(_on_default_hold_pressed)
	vb.add_child(both)
	_weapon_hand.item_selected.connect(func(_i): _prefill_hold_defaults())
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

	vb.add_child(_header("Weapon contact"))
	var contact_hint := Label.new()
	contact_hint.text = "Two weapons meeting: the gap between two points is measured, not forced."
	contact_hint.add_theme_font_size_override("font_size", 11)
	contact_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(contact_hint)
	var c_row := HBoxContainer.new(); vb.add_child(c_row)
	_contact_a = OptionButton.new(); c_row.add_child(_contact_a)
	_contact_ta = SpinBox.new(); _contact_ta.min_value = 0; _contact_ta.max_value = 1; _contact_ta.step = 0.01; _contact_ta.value = 0.7; c_row.add_child(_contact_ta)
	var c_row2 := HBoxContainer.new(); vb.add_child(c_row2)
	_contact_b = OptionButton.new(); c_row2.add_child(_contact_b)
	_contact_tb = SpinBox.new(); _contact_tb.min_value = 0; _contact_tb.max_value = 1; _contact_tb.step = 0.01; _contact_tb.value = 0.7; c_row2.add_child(_contact_tb)
	_contact_gap = Label.new(); _contact_gap.text = ""; vb.add_child(_contact_gap)
	var c_buttons := HBoxContainer.new(); vb.add_child(c_buttons)
	var close_gap := Button.new(); close_gap.text = "Close the gap"
	close_gap.tooltip_text = "Moves the weapon-driven weapon (or the selected character's hand) until the two points touch"
	close_gap.pressed.connect(_on_close_gap_pressed); c_buttons.add_child(close_gap)
	var record := Button.new(); record.text = "Record contact"
	record.tooltip_text = "Saves this pair of points with the pose so the gap is shown again on load"
	record.pressed.connect(_on_record_contact_pressed); c_buttons.add_child(record)

	vb.add_child(_header("Camera"))
	var crow := HBoxContainer.new(); vb.add_child(crow)
	var cam_front := Button.new(); cam_front.text = "Front"
	cam_front.pressed.connect(func(): if camera: camera.apply_preset(CameraPresets.front(scene)))
	crow.add_child(cam_front)
	var cam_side := Button.new(); cam_side.text = "Side"
	cam_side.pressed.connect(func(): if camera: camera.apply_preset(CameraPresets.side(scene)))
	crow.add_child(cam_side)
	var puke_label := Label.new(); puke_label.text = "line up on"; crow.add_child(puke_label)
	_primary_uke = OptionButton.new()
	_primary_uke.tooltip_text = "Which Uke the Front and Side presets line up on"
	_primary_uke.item_selected.connect(func(i: int):
		scene.primary_uke_id = _primary_uke.get_item_metadata(i) if i >= 0 else "")
	crow.add_child(_primary_uke)

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

	vb.add_child(_header("Sequence"))
	var seq_hint := Label.new()
	seq_hint.text = "A technique is 2–5 saved poses with timings. Pose the scene, select a step and save the scene as that step's pose, then play."
	seq_hint.add_theme_font_size_override("font_size", 11)
	seq_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(seq_hint)
	var seq_name_row := HBoxContainer.new(); vb.add_child(seq_name_row)
	_seq_name = LineEdit.new(); _seq_name.placeholder_text = "Technique name"
	_seq_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seq_name.text_changed.connect(func(t: String): if _sequence: _sequence.name = t)
	seq_name_row.add_child(_seq_name)
	var new_seq := Button.new(); new_seq.text = "New"
	new_seq.tooltip_text = "Three steps: Grepp, Kuzushi, Kake"
	new_seq.pressed.connect(_on_new_sequence_pressed)
	seq_name_row.add_child(new_seq)
	_seq_camera = OptionButton.new()
	for mode in ["Side", "Front", "per_pose"]:
		_seq_camera.add_item(mode)
	_seq_camera.tooltip_text = "Camera for the video: a fixed preset, or each pose's own saved camera"
	_seq_camera.item_selected.connect(func(i: int): if _sequence: _sequence.camera = _seq_camera.get_item_text(i))
	seq_name_row.add_child(_seq_camera)
	_seq_list = ItemList.new()
	_seq_list.custom_minimum_size.y = 80
	_seq_list.item_selected.connect(func(_i): _refresh_sequence_step())
	vb.add_child(_seq_list)
	var step_row := HBoxContainer.new(); vb.add_child(step_row)
	var add_step := Button.new(); add_step.text = "Add step"
	add_step.tooltip_text = "Adds the pose selected in the Poses list, or a new phase named after the technique"
	add_step.pressed.connect(_on_add_step_pressed)
	step_row.add_child(add_step)
	var remove_step := Button.new(); remove_step.text = "Remove step"
	remove_step.pressed.connect(_on_remove_step_pressed)
	step_row.add_child(remove_step)
	var timing := GridContainer.new(); timing.columns = 2; vb.add_child(timing)
	_seq_transition = _spin(timing, "Transition (s)", 0, 5, 0.1)
	_seq_hold = _spin(timing, "Hold (s)", 0, 10, 0.1)
	_seq_transition.value_changed.connect(func(v: float): _set_step_timing("transition", v))
	_seq_hold.value_changed.connect(func(v: float): _set_step_timing("hold", v))
	var step_pose := Button.new(); step_pose.text = "Save scene as this step's pose"
	step_pose.pressed.connect(_on_save_step_pose_pressed)
	vb.add_child(step_pose)
	var play_row := HBoxContainer.new(); vb.add_child(play_row)
	var play := Button.new(); play.text = "Play"; play.pressed.connect(_on_play_pressed); play_row.add_child(play)
	var pause := Button.new(); pause.text = "Pause"; pause.pressed.connect(func(): if player: player.pause()); play_row.add_child(pause)
	var stop := Button.new(); stop.text = "Stop"; stop.pressed.connect(func(): if player: player.stop()); play_row.add_child(stop)
	_seq_time = Label.new(); _seq_time.text = "0.0 s"; _seq_time.custom_minimum_size.x = 50; play_row.add_child(_seq_time)
	_seq_scrub = HSlider.new(); _seq_scrub.min_value = 0.0; _seq_scrub.max_value = 1.0; _seq_scrub.step = 0.01
	_seq_scrub.value_changed.connect(_on_scrub_changed)
	vb.add_child(_seq_scrub)
	var seq_files_row := HBoxContainer.new(); vb.add_child(seq_files_row)
	var save_seq := Button.new(); save_seq.text = "Save sequence"; save_seq.pressed.connect(_on_save_sequence_pressed); seq_files_row.add_child(save_seq)
	var load_seq := Button.new(); load_seq.text = "Load sequence"; load_seq.pressed.connect(_on_load_sequence_pressed); seq_files_row.add_child(load_seq)
	_seq_files = ItemList.new()
	_seq_files.custom_minimum_size.y = 50
	vb.add_child(_seq_files)
	if player:
		player.time_changed.connect(_on_player_time)

	vb.add_child(_header("Edit"))
	var ur := HBoxContainer.new(); vb.add_child(ur)
	var u := Button.new(); u.text = "Undo (Ctrl+Z)"; u.pressed.connect(func(): controller.undo.undo(); controller.pose_changed.emit()); ur.add_child(u)
	var r := Button.new(); r.text = "Redo (Ctrl+Y)"; r.pressed.connect(func(): controller.undo.redo(); controller.pose_changed.emit()); ur.add_child(r)

	vb.add_child(_header("Export"))
	var transparent := CheckBox.new(); transparent.text = "Transparent background"; vb.add_child(transparent)
	var ex := Button.new(); ex.text = "Export still (PNG)"
	ex.pressed.connect(func(): export_requested.emit(transparent.button_pressed))
	vb.add_child(ex)
	var exs := Button.new(); exs.text = "Export Front+Side stills of the sequence"
	exs.tooltip_text = "Two stills per phase, front and side, at full size"
	exs.pressed.connect(func():
		if _sequence:
			_on_save_sequence_pressed()
			stills_export_requested.emit(_sequence, transparent.button_pressed))
	vb.add_child(exs)
	var exv := Button.new(); exv.text = "Export video of the sequence"
	exv.tooltip_text = "Renders every frame in a second window, then encodes MP4 with ffmpeg (AVI if ffmpeg is missing)"
	exv.pressed.connect(func():
		if _sequence:
			_on_save_sequence_pressed()
			video_export_requested.emit(_sequence))
	vb.add_child(exv)
	_export_status = Label.new()
	_export_status.add_theme_font_size_override("font_size", 11)
	_export_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_export_status)

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
	_refresh_sequence_files()
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
	if _copy_to:
		_copy_to.clear()
		for c in scene.characters:
			_copy_to.add_item(c.display_name)
	if _primary_uke:
		_primary_uke.clear()
		for c in scene.characters:
			if c.role == "Uke":
				_primary_uke.add_item(c.display_name)
				_primary_uke.set_item_metadata(_primary_uke.item_count - 1, c.character_id)
				if c.character_id == scene.primary_uke_id:
					_primary_uke.select(_primary_uke.item_count - 1)
	_refresh_character_fields()
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
	# The hand is wrapped round the bone at that bone's thickness: a fist on a wrist, a palm
	# laid on the neck or a thigh, and the fingers close as far as the part allows.
	var bone := controller.selected_bone
	grips.attach_wrapped(gripper, hand, controller.selected_rig, bone, true)
	var curl := GripDirector.curl_for_bone(bone)
	for finger in FingerCurl.FINGERS:
		var old: float = gripper.fingers.get_curl(hand, finger)
		var value := minf(curl + 0.1, 1.0) if finger == "Thumb" else curl
		controller.set_finger_curl(gripper, hand, finger, value)
		controller.commit_finger_curl(gripper, hand, finger, old, value)
	_refresh_values()


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
	_refresh_character_fields()
	_refresh_values()


func _set_joint_enabled(on: bool) -> void:
	for s in _euler:
		s.editable = on


func _process(_delta: float) -> void:
	if _contact_gap and grips:
		var pair := _contact_pair()
		if pair.is_empty():
			_contact_gap.text = "Add two weapons to measure a contact." if scene.weapons.size() < 2 else ""
		else:
			var gap: float = grips.contact_gap(pair[0], pair[1], pair[2], pair[3])
			_contact_gap.text = ("Touching (%.1f cm)" if gap < 0.01 else "Gap %.1f cm") % (gap * 100.0)
	# Bodies through each other are reported live, a few times a second (the check walks every
	# pair of body capsules, which is cheap but not free).
	_collision_clock += _delta
	if _collision_label and _collision_clock > 0.3:
		_collision_clock = 0.0
		var problems := Anatomy.scene_problems(scene, grips)
		var lines := PackedStringArray()
		for i in mini(problems.size(), 4):
			lines.append(problems[i])
		if problems.size() > 4:
			lines.append("… and %d more" % (problems.size() - 4))
		_collision_label.text = "\n".join(lines) if not lines.is_empty() else "No collisions"
		_collision_label.add_theme_color_override("font_color", Color(0.85, 0.15, 0.15) if not lines.is_empty() else Color(0.2, 0.55, 0.2))
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
	if _updating or controller.selected_rig == null or controller.selected_bone == "":
		return
	var q := Quaternion.from_euler(Vector3(deg_to_rad(_euler[0].value), deg_to_rad(_euler[1].value), deg_to_rad(_euler[2].value)))
	controller.set_bone_rotation(controller.selected_rig, controller.selected_bone, q)
	for i in 3:
		_euler_vals[i].text = "%.0f°" % _euler[i].value


func _on_euler_drag_started() -> void:
	if controller.selected_rig and controller.selected_bone != "":
		_slider_old_q = controller.get_bone_rotation(controller.selected_rig, controller.selected_bone)


func _on_euler_drag_ended(changed: bool) -> void:
	if changed and controller.selected_rig and controller.selected_bone != "":
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
	_refresh_contact_options()
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
		else:
			_prefill_hold_defaults()
	_updating = false


## The t and roll boxes start at the weapon's default for the chosen hand.
func _prefill_hold_defaults() -> void:
	var w := _selected_weapon()
	if w == null:
		return
	var d: Dictionary = w.default_hold("Right" if _weapon_hand.selected == 0 else "Left")
	_weapon_t.value = d["t"]
	_weapon_roll.value = d["roll_deg"]


func _on_default_hold_pressed() -> void:
	var w := _selected_weapon()
	var rig := _holder_rig()
	if grips == null or w == null or rig == null:
		return
	grips.attach_default_hands(rig, w)
	controller.pose_changed.emit()
	_refresh_weapons()


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
	grips.attach_to_weapon(rig, other, w, _weapon_t.value, true, _weapon_roll.value)
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
	var path := PoseFile.pose_path(POSES_DIR, name)
	if not await _confirm_overwrite(path):
		return
	var data: Dictionary = await PoseFile.capture_baked(scene, grips, camera, name)
	var err := PoseFile.save(path, data)
	if err != OK:
		push_error("SidePanel: could not save pose (%s)" % error_string(err))
	_refresh_poses()


## Asks before an existing pose file is replaced (spec §4). True when there is nothing to
## overwrite or the instructor confirmed.
func _confirm_overwrite(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	var dialog := ConfirmationDialog.new()
	dialog.title = "Replace pose?"
	dialog.dialog_text = "%s already exists.\nReplace it with the current scene?" % path.get_file()
	dialog.ok_button_text = "Replace"
	add_child(dialog)
	var box := {"ok": false}
	dialog.confirmed.connect(func(): box["ok"] = true)
	dialog.popup_centered()
	await dialog.visibility_changed   # closes on either button
	if dialog.visible:
		await dialog.visibility_changed
	dialog.queue_free()
	return box["ok"]


func _on_load_pose_pressed() -> void:
	var sel := _pose_list.get_selected_items()
	if sel.is_empty():
		return
	var path := POSES_DIR.path_join(_pose_list.get_item_text(sel[0]) + ".json")
	var data := PoseFile.load(path)
	if data.is_empty():
		return
	PoseFile.apply(data, scene, grips, controller, camera)
	_pose_name.text = str(data.get("name", _pose_list.get_item_text(sel[0])))
	controller.pose_changed.emit()
	_refresh_weapons()
	_refresh_grips()


# ---------------------------------------------------------------- sequences

func _selected_step() -> int:
	var sel := _seq_list.get_selected_items()
	return sel[0] if not sel.is_empty() else -1


func _refresh_sequence() -> void:
	_seq_list.clear()
	if _sequence == null:
		_seq_scrub.max_value = 1.0
		return
	for i in _sequence.steps.size():
		var st: Dictionary = _sequence.steps[i]
		var have := FileAccess.file_exists(POSES_DIR.path_join(str(st["pose"]) + ".json"))
		_seq_list.add_item("%d. %s%s   →%.1f s  hold %.1f s" % [i + 1, st["pose"], "" if have else " (no pose saved)", float(st.get("transition", 0.0)), float(st.get("hold", 0.0))])
	_seq_scrub.max_value = maxf(_sequence.duration(), 0.01)
	for i in _seq_camera.item_count:
		if _seq_camera.get_item_text(i) == _sequence.camera:
			_seq_camera.select(i)
	_refresh_sequence_step()


func _refresh_sequence_step() -> void:
	var i := _selected_step()
	_updating = true
	if _sequence and i >= 0:
		_seq_transition.value = float(_sequence.steps[i].get("transition", 0.0))
		_seq_hold.value = float(_sequence.steps[i].get("hold", 0.0))
		_seq_transition.editable = i > 0
	_updating = false


func _set_step_timing(key: String, value: float) -> void:
	var i := _selected_step()
	if _updating or _sequence == null or i < 0:
		return
	_sequence.steps[i][key] = value
	var keep := i
	_refresh_sequence()
	_seq_list.select(keep)


func _on_new_sequence_pressed() -> void:
	var name := _seq_name.text.strip_edges()
	if name == "":
		name = "Teknik"
		_seq_name.text = name
	_sequence = Sequence.new_default(name)
	_refresh_sequence()
	_reload_player()


func _on_add_step_pressed() -> void:
	if _sequence == null:
		_on_new_sequence_pressed()
		_sequence.steps.clear()
	if _sequence.steps.size() >= Sequence.MAX_STEPS:
		return
	var sel := _pose_list.get_selected_items()
	var slug: String
	if not sel.is_empty():
		slug = _pose_list.get_item_text(sel[0])
	else:
		slug = PoseFile.slugify("%s steg %d" % [_sequence.name, _sequence.steps.size() + 1])
	_sequence.steps.append({"pose": slug, "transition": 0.6, "hold": 0.5})
	_refresh_sequence()
	_seq_list.select(_sequence.steps.size() - 1)
	_refresh_sequence_step()
	_reload_player()


func _on_remove_step_pressed() -> void:
	var i := _selected_step()
	if _sequence == null or i < 0:
		return
	_sequence.steps.remove_at(i)
	_refresh_sequence()
	_reload_player()


## Writes the live scene into the selected step's pose file, so posing and sequencing are one loop.
func _on_save_step_pose_pressed() -> void:
	var i := _selected_step()
	if _sequence == null or i < 0 or grips == null:
		return
	var slug: String = _sequence.steps[i]["pose"]
	var path := POSES_DIR.path_join(slug + ".json")
	if not await _confirm_overwrite(path):
		return
	var data: Dictionary = await PoseFile.capture_baked(scene, grips, camera, slug)
	var err := PoseFile.save(path, data)
	if err != OK:
		push_error("Could not save pose %s: %s" % [slug, error_string(err)])
	_refresh_poses()
	_refresh_sequence()
	_seq_list.select(i)
	_reload_player()


func _reload_player() -> void:
	if player == null or _sequence == null:
		return
	player.load_sequence(_sequence, ProjectSettings.globalize_path(POSES_DIR))


func _on_play_pressed() -> void:
	if player == null or _sequence == null:
		return
	# Reload only when the player does not already hold this sequence, so Pause then Play resumes.
	if player.sequence != _sequence or player.poses.is_empty():
		_reload_player()
	if player.time >= player.duration():
		player.time = 0.0
	player.play()


func _on_scrub_changed(v: float) -> void:
	if _updating or player == null or _sequence == null:
		return
	if player.poses.is_empty():
		_reload_player()
	player.pause()
	player.seek(v)


func _on_player_time(t: float) -> void:
	_updating = true
	_seq_scrub.value = t
	_seq_time.text = "%.1f s" % t
	_updating = false


func _refresh_sequence_files() -> void:
	if _seq_files == null:
		return
	_seq_files.clear()
	var d := DirAccess.open(SEQUENCES_DIR)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".json"):
			_seq_files.add_item(f.get_basename())


func _on_save_sequence_pressed() -> void:
	if _sequence == null:
		return
	_sequence.name = _seq_name.text.strip_edges() if _seq_name.text.strip_edges() != "" else _sequence.name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SEQUENCES_DIR))
	var err := _sequence.save(Sequence.sequence_path(SEQUENCES_DIR, _sequence.name))
	if err != OK:
		push_error("Could not save sequence: %s" % error_string(err))
	_refresh_sequence_files()


func _on_load_sequence_pressed() -> void:
	var sel := _seq_files.get_selected_items()
	if sel.is_empty():
		return
	var seq := Sequence.load(SEQUENCES_DIR.path_join(_seq_files.get_item_text(sel[0]) + ".json"))
	if seq == null:
		return
	_sequence = seq
	_seq_name.text = seq.name
	_refresh_sequence()
	_reload_player()


func set_export_status(text: String) -> void:
	if _export_status:
		_export_status.text = text


# ---------------------------------------------------------------- characters

func _refresh_character_fields() -> void:
	if _char_name == null:
		return
	_updating = true
	var rig := controller.selected_rig
	_char_name.text = rig.display_name if rig else ""
	_char_color.color = rig.get_skin_color() if rig else Color.GRAY
	_char_visible.button_pressed = rig.visible if rig else true
	if _char_gi:
		_char_gi.button_pressed = rig.gi_visible if rig else false
	_updating = false


func _on_add_character_pressed() -> void:
	if scene.characters.size() >= PosingScene.MAX_CHARACTERS:
		return
	var role: String = _char_role.get_item_text(_char_role.selected)
	var prefix := role.to_lower()
	var id := scene.next_free_id(prefix)
	var count := 0
	for c in scene.characters:
		if c.role == role:
			count += 1
	var rig := scene.add_character(id, "%s %d" % [role, count + 1] if count > 0 else role, role)
	rig.position = Vector3(0.6 * (scene.characters.size() - 2), 0, 0.5)
	rig.rotation.y = PI
	controller.select(rig, "")


func _on_duplicate_character_pressed() -> void:
	var src := controller.selected_rig
	if src == null or scene.characters.size() >= PosingScene.MAX_CHARACTERS:
		return
	var rig := scene.add_character(scene.next_free_id(src.role.to_lower()), src.display_name + " copy", src.role)
	rig.position = src.position + Vector3(0.6, 0, 0)
	rig.rotation = src.rotation
	controller.copy_pose(src, rig)
	controller.select(rig, "")


func _on_remove_character_pressed() -> void:
	var rig := controller.selected_rig
	if rig == null or scene.characters.size() <= PosingScene.MIN_CHARACTERS:
		return
	var involved := 0
	if grips:
		for grip in grips.grips:
			if grip.gripper_id == rig.character_id or (grip.target.kind == GripTarget.Kind.BONE and grip.target.character_id == rig.character_id):
				involved += 1
	if involved > 0:
		var dialog := ConfirmationDialog.new()
		dialog.title = "Remove %s?" % rig.display_name
		dialog.dialog_text = "%s is part of %d grip(s). Removing the character releases them." % [rig.display_name, involved]
		dialog.ok_button_text = "Remove"
		add_child(dialog)
		var box := {"ok": false}
		dialog.confirmed.connect(func(): box["ok"] = true)
		dialog.popup_centered()
		await dialog.visibility_changed
		if dialog.visible:
			await dialog.visibility_changed
		dialog.queue_free()
		if not box["ok"]:
			return
	controller.select(null, "")
	scene.remove_character(rig.character_id)


func _rename_selected(text: String) -> void:
	var rig := controller.selected_rig
	if rig == null or text.strip_edges() == "":
		return
	rig.display_name = text.strip_edges()
	_refresh_characters()


func _on_copy_pose_pressed() -> void:
	var src := controller.selected_rig
	if src == null or _copy_to.selected < 0 or _copy_to.selected >= scene.characters.size():
		return
	var dst: CharacterRig = scene.characters[_copy_to.selected]
	if dst != src:
		controller.copy_pose(src, dst)


# ---------------------------------------------------------------- weapon contact

func _refresh_contact_options() -> void:
	if _contact_a == null:
		return
	for opt in [_contact_a, _contact_b]:
		var keep: int = opt.selected
		opt.clear()
		for w in scene.weapons:
			opt.add_item(w.weapon_id)
		if keep >= 0 and keep < opt.item_count:
			opt.select(keep)
	if _contact_b.item_count > 1 and _contact_b.selected == _contact_a.selected:
		_contact_b.select(1)


func _contact_pair() -> Array:
	if _contact_a == null or _contact_a.selected < 0 or _contact_b.selected < 0:
		return []
	var a: Weapon = scene.get_weapon(_contact_a.get_item_text(_contact_a.selected))
	var b: Weapon = scene.get_weapon(_contact_b.get_item_text(_contact_b.selected))
	if a == null or b == null or a == b:
		return []
	return [a, _contact_ta.value, b, _contact_tb.value]


func _on_close_gap_pressed() -> void:
	var pair := _contact_pair()
	if pair.is_empty() or grips == null:
		return
	grips.close_gap(pair[0], pair[1], pair[2], pair[3])


func _on_record_contact_pressed() -> void:
	var pair := _contact_pair()
	if pair.is_empty():
		return
	scene.weapon_contacts = [{"a": pair[0].weapon_id, "t_a": pair[1], "b": pair[2].weapon_id, "t_b": pair[3]}]
