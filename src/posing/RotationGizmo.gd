class_name RotationGizmo
extends Node3D
## Three draggable rings around the selected joint. Screen-space picking and dragging,
## so it works with any camera. Emits rotation deltas about a world-space axis.

signal drag_started
signal rotated(axis_world: Vector3, angle: float)
signal drag_ended

const SCREEN_RADIUS_PX := 70.0
const PICK_PX := 10.0
const AXIS_COLORS := [Color(0.9, 0.25, 0.25), Color(0.3, 0.8, 0.3), Color(0.3, 0.5, 0.95)]

var camera: Camera3D
var rings: Array[MeshInstance3D] = []
var active_axis := -1
var hover_axis := -1
var suppressed := false  ## while true the gizmo stays hidden (used during export)
var _last_angle := 0.0
var _basis_world := Basis.IDENTITY


func _ready() -> void:
	for i in 3:
		var mi := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.96
		torus.outer_radius = 1.0
		torus.rings = 48
		mi.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = AXIS_COLORS[i]
		mat.no_depth_test = true
		mat.render_priority = 10
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# TorusMesh lies in the XZ plane (normal Y). Rotate so ring i has normal along axis i.
		match i:
			0: mi.rotation = Vector3(0, 0, PI / 2)   # normal X
			1: mi.rotation = Vector3.ZERO           # normal Y
			2: mi.rotation = Vector3(PI / 2, 0, 0)   # normal Z
		add_child(mi)
		rings.append(mi)
	visible = false


## Place at a world position with a world basis (axes of the joint).
func attach(pos: Vector3, basis_world: Basis) -> void:
	_basis_world = basis_world.orthonormalized()
	global_transform = Transform3D(_basis_world, pos)
	visible = not suppressed


func detach() -> void:
	visible = false
	active_axis = -1


func _process(_d: float) -> void:
	if not visible or camera == null:
		return
	# Keep a constant on-screen size.
	var dist := camera.global_position.distance_to(global_position)
	var world_per_px := _world_per_pixel(dist)
	var s := SCREEN_RADIUS_PX * world_per_px
	global_transform = Transform3D(_basis_world.scaled(Vector3.ONE * s), global_position)
	for i in 3:
		var mat: StandardMaterial3D = rings[i].material_override
		var lit := (i == active_axis) or (active_axis < 0 and i == hover_axis)
		mat.albedo_color = AXIS_COLORS[i].lightened(0.45) if lit else AXIS_COLORS[i]


func _world_per_pixel(dist: float) -> float:
	var vp := get_viewport().get_visible_rect().size
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return camera.size / vp.y
	return 2.0 * dist * tan(deg_to_rad(camera.fov) * 0.5) / vp.y


func axis_world(i: int) -> Vector3:
	return _basis_world[i].normalized()


## Returns the ring index under the mouse or -1.
func pick(mouse: Vector2) -> int:
	if not visible or camera == null:
		return -1
	var best := -1
	var best_d := PICK_PX
	var radius := global_transform.basis.get_scale().x
	for i in 3:
		var a := axis_world(i)
		var u := _basis_world[(i + 1) % 3].normalized()
		var v := a.cross(u).normalized()
		for k in 64:
			var t := TAU * k / 64.0
			var p := global_position + (u * cos(t) + v * sin(t)) * radius
			if camera.is_position_behind(p):
				continue
			var d := camera.unproject_position(p).distance_to(mouse)
			if d < best_d:
				best_d = d
				best = i
	return best


func begin_drag(axis: int, mouse: Vector2) -> void:
	active_axis = axis
	_last_angle = _screen_angle(mouse)
	drag_started.emit()


func drag_to(mouse: Vector2) -> void:
	if active_axis < 0:
		return
	var ang := _screen_angle(mouse)
	var delta := wrapf(ang - _last_angle, -PI, PI)
	_last_angle = ang
	# Ring seen from its front side rotates counter-clockwise for positive angle; flip otherwise.
	var a := axis_world(active_axis)
	var to_cam := (camera.global_position - global_position).normalized()
	if a.dot(to_cam) < 0.0:
		delta = -delta
	rotated.emit(a, delta)


func end_drag() -> void:
	if active_axis >= 0:
		active_axis = -1
		drag_ended.emit()


func _screen_angle(mouse: Vector2) -> float:
	var c := camera.unproject_position(global_position)
	var d := mouse - c
	return atan2(-d.y, d.x)
