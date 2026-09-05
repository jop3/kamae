class_name CameraPresets
extends RefCounted
## Camera presets (spec §5.7): Front looks along the Tori→primary-Uke line, Side perpendicular to it.
## Both sit 1.4 m high and frame every visible character. Each returns
## {direction: Vector3, center: Vector3, distance: float} for OrbitCamera.apply_preset().

const HEIGHT := 1.4
const FOV_DEG := 50.0
const MARGIN := 1.25
## Bones whose world positions bound a character well enough for framing.
const FRAME_BONES := ["Hips", "Head", "RightHand", "LeftHand", "RightFoot", "LeftFoot"]


static func front(scene: PosingScene) -> Dictionary:
	var axis: Dictionary = scene.tori_uke_axis()
	var along: Vector3 = axis["to"] - axis["from"]
	along.y = 0.0
	if along.length() < 0.001:
		along = Vector3(0, 0, 1)
	return _preset(scene, -along.normalized())


static func side(scene: PosingScene) -> Dictionary:
	var axis: Dictionary = scene.tori_uke_axis()
	var along: Vector3 = axis["to"] - axis["from"]
	along.y = 0.0
	if along.length() < 0.001:
		along = Vector3(0, 0, 1)
	return _preset(scene, along.normalized().cross(Vector3.UP).normalized())


## Direction is the horizontal unit vector from the scene centre towards the camera.
static func _preset(scene: PosingScene, horizontal: Vector3) -> Dictionary:
	var sphere := bounding_sphere(scene)
	var center: Vector3 = sphere["center"]
	var radius: float = sphere["radius"]
	var distance := radius / tan(deg_to_rad(FOV_DEG) * 0.5) * MARGIN
	# The camera sits at HEIGHT; aim at the sphere centre from there.
	var eye := center + horizontal * distance
	eye.y = HEIGHT
	var direction := (eye - center).normalized()
	return {"direction": direction, "center": center, "distance": eye.distance_to(center)}


## Bounding sphere over the framing bones of every visible character.
static func bounding_sphere(scene: PosingScene) -> Dictionary:
	var points: Array[Vector3] = []
	for rig in scene.characters:
		if not rig.visible:
			continue
		for bone in FRAME_BONES:
			points.append(rig.bone_world_transform(bone).origin)
	if points.is_empty():
		return {"center": Vector3(0, 0.9, 0), "radius": 1.0}
	var sum := Vector3.ZERO
	for p in points:
		sum += p
	var center := sum / points.size()
	var radius := 0.0
	for p in points:
		radius = maxf(radius, center.distance_to(p))
	return {"center": center, "radius": maxf(radius, 0.5)}
