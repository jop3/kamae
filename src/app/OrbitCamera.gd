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


func _apply() -> void:
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	global_position = target + offset
	look_at(target, Vector3.UP)
