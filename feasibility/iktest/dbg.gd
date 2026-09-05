extends Node3D
var sk: Skeleton3D; var ik; var tgt: Marker3D; var frame := 0
func _ready():
	sk = Skeleton3D.new(); add_child(sk)
	var r := sk.add_bone("A"); sk.set_bone_rest(r, Transform3D(Basis(), Vector3(0,1,0)))
	var m := sk.add_bone("B"); sk.set_bone_parent(m, r); sk.set_bone_rest(m, Transform3D(Basis(), Vector3(0,0.3,0)))
	var e := sk.add_bone("C"); sk.set_bone_parent(e, m); sk.set_bone_rest(e, Transform3D(Basis(), Vector3(0,0.3,0)))
	sk.reset_bone_poses()
	tgt = Marker3D.new(); add_child(tgt); tgt.global_position = Vector3(0.3, 1.3, 0.1)
	var pole := Marker3D.new(); add_child(pole); pole.global_position = Vector3(0, 1.3, -1)
	var which := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "two"
	if which == "two":
		ik = TwoBoneIK3D.new(); sk.add_child(ik); ik.setting_count = 1
		ik.set_root_bone_name(0,"A"); ik.set_middle_bone_name(0,"B"); ik.set_end_bone_name(0,"C")
		ik.set_target_node(0, ik.get_path_to(tgt)); ik.set_pole_node(0, ik.get_path_to(pole))
		print("target path=", ik.get_target_node(0), " resolves=", ik.get_node_or_null(ik.get_target_node(0)))
		print("props: ", ik.get_property_list().filter(func(p): return p.name.begins_with("settings") or p.name.begins_with("setting")).map(func(p): return p.name))
	elif which == "fabrik":
		ik = FABRIK3D.new(); sk.add_child(ik)
		print("FABRIK props: ", ik.get_property_list().map(func(p): return p.name).filter(func(n): return not n.begins_with("_")))
	ik.modification_processed.connect(func(): print("  modification_processed f", frame, " active=", ik.active, " influence=", ik.influence, " C=", sk.get_bone_global_pose(2).origin))
	sk.skeleton_updated.connect(func(): print("  skeleton_updated f", frame, " C=", sk.get_bone_global_pose(2).origin))
func _process(_d):
	frame += 1
	print("process f", frame, " C=", sk.get_bone_global_pose(2).origin, " modifier_mode=", sk.modifier_callback_mode_process)
	if frame == 4: get_tree().quit()
