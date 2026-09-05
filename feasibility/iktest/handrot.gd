extends Node3D
# Test: custom GDScript SkeletonModifier3D placed AFTER TwoBoneIK3D orients the end bone to a target's rotation.
var sk: Skeleton3D; var tgt: Marker3D; var frame := 0
class HandOrient extends SkeletonModifier3D:
	var bone := -1; var target: Node3D
	func _process_modification_with_delta(_delta: float) -> void:
		var s := get_skeleton()
		if s == null or bone < 0 or target == null: return
		var g := s.get_bone_global_pose(bone)
		var want_basis := (s.global_transform.affine_inverse() * target.global_transform).basis
		s.set_bone_global_pose(bone, Transform3D(want_basis, g.origin))
func _ready():
	sk = Skeleton3D.new(); add_child(sk)
	var r := sk.add_bone("A"); sk.set_bone_rest(r, Transform3D(Basis(), Vector3(0,1,0)))
	var m := sk.add_bone("B"); sk.set_bone_parent(m, r); sk.set_bone_rest(m, Transform3D(Basis(), Vector3(0,0.3,0)))
	var e := sk.add_bone("C"); sk.set_bone_parent(e, m); sk.set_bone_rest(e, Transform3D(Basis(), Vector3(0,0.3,0)))
	sk.reset_bone_poses()
	tgt = Marker3D.new(); add_child(tgt); tgt.global_position = Vector3(0.3,1.3,0.1); tgt.rotation_degrees = Vector3(0,0,90)
	var pole := Marker3D.new(); add_child(pole); pole.global_position = Vector3(0,1.3,-1)
	var ik := TwoBoneIK3D.new(); sk.add_child(ik); ik.setting_count = 1
	ik.set_root_bone_name(0,"A"); ik.set_middle_bone_name(0,"B"); ik.set_end_bone_name(0,"C")
	ik.set_target_node(0, ik.get_path_to(tgt)); ik.set_pole_node(0, ik.get_path_to(pole))
	var ho := HandOrient.new(); sk.add_child(ho); ho.bone = 2; ho.target = tgt
	var ct = CopyTransformModifier3D.new(); print("CopyTransformModifier3D props: ", ct.get_property_list().map(func(p): return p.name).filter(func(n): return n.begins_with("setting") or n.begins_with("amount") or n.begins_with("mode")))
	sk.skeleton_updated.connect(func():
		var g := sk.get_bone_global_pose(2)
		print("f%d C.origin=%s C.rot_deg=%s (want pos (0.3,1.3,0.1), rot z=90)" % [frame, g.origin, g.basis.get_euler()*57.2958]))
func _process(_d):
	frame += 1
	if frame == 3: get_tree().quit()
