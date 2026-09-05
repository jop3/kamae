extends Node3D
var tori: Skeleton3D; var uke: Skeleton3D; var attach: BoneAttachment3D
var target: Marker3D; var pole: Marker3D; var ik: TwoBoneIK3D
var frame := 0; var mode := "process"; var order := "uke_first"; var errs := []
var tori_wrist_world := Vector3.ZERO

func make_arm(n: String, pos: Vector3) -> Skeleton3D:
	var sk := Skeleton3D.new(); sk.name = n; sk.position = pos; add_child(sk)
	var root := sk.add_bone("Hips"); sk.set_bone_rest(root, Transform3D(Basis(), Vector3(0,1,0)))
	var sh := sk.add_bone("RightArm"); sk.set_bone_parent(sh, root); sk.set_bone_rest(sh, Transform3D(Basis(), Vector3(0.2,0.4,0)))
	var el := sk.add_bone("RightForeArm"); sk.set_bone_parent(el, sh); sk.set_bone_rest(el, Transform3D(Basis(), Vector3(0.3,0,0)))
	var ha := sk.add_bone("RightHand"); sk.set_bone_parent(ha, el); sk.set_bone_rest(ha, Transform3D(Basis(), Vector3(0.3,0,0)))
	sk.reset_bone_poses(); return sk

func _ready():
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: mode = a[0]
	if a.size() > 1: order = a[1]
	if order == "uke_first":
		uke = make_arm("Uke", Vector3(0.55,0,0)); tori = make_arm("Tori", Vector3.ZERO)
	else:
		tori = make_arm("Tori", Vector3.ZERO); uke = make_arm("Uke", Vector3(0.55,0,0))
	attach = BoneAttachment3D.new(); tori.add_child(attach); attach.bone_name = "RightHand"
	target = Marker3D.new(); add_child(target)
	pole = Marker3D.new(); add_child(pole); pole.global_position = Vector3(0.6, 1.0, -0.5)
	ik = TwoBoneIK3D.new(); uke.add_child(ik); ik.setting_count = 1
	ik.set_root_bone_name(0,"RightArm"); ik.set_middle_bone_name(0,"RightForeArm"); ik.set_end_bone_name(0,"RightHand")
	ik.set_target_node(0, ik.get_path_to(target)); ik.set_pole_node(0, ik.get_path_to(pole))
	# record truth from Tori at its skeleton_updated; measure Uke at its skeleton_updated
	tori.skeleton_updated.connect(func():
		tori_wrist_world = tori.global_transform * tori.get_bone_global_pose(tori.find_bone("RightHand")).origin
		if mode == "signal": target.global_transform = attach.global_transform
		if mode == "signal_direct": target.global_transform = tori.global_transform * tori.get_bone_global_pose(tori.find_bone("RightHand"))
		if frame == 5: print("  [tori updated] wrist=%s attach=%s diff=%.4f" % [tori_wrist_world, attach.global_position, tori_wrist_world.distance_to(attach.global_position)]))
	uke.skeleton_updated.connect(func():
		var uh: Vector3 = uke.global_transform * uke.get_bone_global_pose(uke.find_bone("RightHand")).origin
		if frame >= 3: errs.append(uh.distance_to(tori_wrist_world)))
	if mode.begins_with("manual"):
		tori.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
		uke.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL

func _process(d):
	frame += 1
	tori.set_bone_pose_rotation(tori.find_bone("RightArm"), Quaternion(Vector3(0,0,1), sin(frame*0.3)*0.8))
	if mode == "process": target.global_transform = attach.global_transform
	if mode == "manual":
		tori.advance(d); target.global_transform = attach.global_transform; uke.advance(d)
	if mode == "manual_direct":
		tori.advance(d); target.global_transform = tori.global_transform * tori.get_bone_global_pose(tori.find_bone("RightHand")); uke.advance(d)
	if mode == "manual_direct_wait":
		tori.advance(d); await get_tree().process_frame
	if frame == 12:
		print("RESULT mode=%-8s order=%-10s max_err=%.3f mm" % [mode, order, errs.max()*1000.0]); get_tree().quit()
