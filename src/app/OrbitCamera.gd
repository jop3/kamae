class_name OrbitCamera
extends Camera3D
## Mouse orbit (left drag on empty space), pan (middle drag / shift+drag), zoom (wheel).

var target := Vector3(0, 0.9, 0)
var distance := 4.0
var yaw := 0.0
var pitch := -0.25
var orbiting := false
var panning := false


func _ready() -> void:
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				orbiting = event.pressed
			MOUSE_BUTTON_MIDDLE:
				panning = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				distance = maxf(0.5, distance * 0.9)
				_apply()
			MOUSE_BUTTON_WHEEL_DOWN:
				distance = minf(20.0, distance / 0.9)
				_apply()
	elif event is InputEventMouseMotion:
		if orbiting and not event.shift_pressed:
			yaw -= event.relative.x * 0.01
			pitch = clampf(pitch - event.relative.y * 0.01, -1.5, 1.5)
			_apply()
		elif panning or (orbiting and event.shift_pressed):
			var right := global_transform.basis.x
			var up := global_transform.basis.y
			target += (-right * event.relative.x + up * event.relative.y) * 0.002 * distance
			_apply()


func look_from(direction: Vector3, center: Vector3, dist: float) -> void:
	target = center
	distance = dist
	var d := direction.normalized()
	yaw = atan2(d.x, d.z)
	pitch = asin(clampf(d.y, -1.0, 1.0))
	_apply()


## Apply a CameraPresets result: {direction, center, distance}.
func apply_preset(p: Dictionary) -> void:
	look_from(p["direction"], p["center"], p["distance"])


func _apply() -> void:
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	global_position = target + offset
	look_at(target, Vector3.UP)


## The orbit state as plain numbers, for saving with a pose.
func state() -> Dictionary:
	return {"target": [target.x, target.y, target.z], "distance": distance, "yaw": yaw, "pitch": pitch, "fov": fov}


func apply_state(d: Dictionary) -> void:
	if d.is_empty():
		return
	var t = d.get("target", null)
	if t is Array and t.size() >= 3:
		target = Vector3(t[0], t[1], t[2])
	distance = float(d.get("distance", distance))
	yaw = float(d.get("yaw", yaw))
	pitch = float(d.get("pitch", pitch))
	fov = float(d.get("fov", fov))
	_apply()


## Between two saved states; yaw goes the short way round.
static func blend_state(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	if a.is_empty():
		return b
	if b.is_empty():
		return a
	var ta: Array = a.get("target", [0, 0.9, 0])
	var tb: Array = b.get("target", [0, 0.9, 0])
	var t := Vector3(ta[0], ta[1], ta[2]).lerp(Vector3(tb[0], tb[1], tb[2]), u)
	return {"target": [t.x, t.y, t.z],
		"distance": lerpf(float(a.get("distance", 4.0)), float(b.get("distance", 4.0)), u),
		"yaw": lerp_angle(float(a.get("yaw", 0.0)), float(b.get("yaw", 0.0)), u),
		"pitch": lerpf(float(a.get("pitch", 0.0)), float(b.get("pitch", 0.0)), u),
		"fov": lerpf(float(a.get("fov", 50.0)), float(b.get("fov", 50.0)), u)}
