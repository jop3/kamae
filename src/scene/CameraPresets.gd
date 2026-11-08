class_name CameraPresets
extends RefCounted
## Camera presets (spec §5.7): Front looks along the Tori→primary-Uke line, Side perpendicular to it.
## Both sit 1.4 m high and frame every visible character. Each returns
## {direction: Vector3, center: Vector3, distance: float} for OrbitCamera.apply_preset().

const HEIGHT := 1.4
const FOV_DEG := 50.0
const MARGIN := 1.25
## Front is swung this far off the Tori→Uke line. Exactly on the line (spec §5.7) the nearer
## figure hides the other completely, so the "front" view is a three-quarter front: still
## clearly from Tori's side of the line, but both figures visible. Raised with the instructor.
const FRONT_OFFSET_DEG := 35.0
## Bones whose world positions bound a character well enough for framing.
const FRAME_BONES := ["Hips", "Head", "RightHand", "LeftHand", "RightFoot", "LeftFoot"]


static func front(scene: PosingScene, points: Array[Vector3] = []) -> Dictionary:
	var axis: Dictionary = scene.tori_uke_axis()
	var along: Vector3 = axis["to"] - axis["from"]
	along.y = 0.0
	if along.length() < 0.001:
		along = Vector3(0, 0, 1)
	return _preset(scene, (-along.normalized()).rotated(Vector3.UP, deg_to_rad(FRONT_OFFSET_DEG)), points)


static func side(scene: PosingScene, points: Array[Vector3] = []) -> Dictionary:
	var axis: Dictionary = scene.tori_uke_axis()
	var along: Vector3 = axis["to"] - axis["from"]
	along.y = 0.0
	if along.length() < 0.001:
		along = Vector3(0, 0, 1)
	return _preset(scene, along.normalized().cross(Vector3.UP).normalized(), points)


## A chosen view, for matching a video: swung `yaw_deg` from the Side preset about the vertical
## (positive counter-clockwise seen from above), the camera at `height` metres, framing every
## point with `zoom` (above 1 closer, below 1 further).
static func view(scene: PosingScene, v: Dictionary, points: Array[Vector3] = []) -> Dictionary:
	var axis: Dictionary = scene.tori_uke_axis()
	var along: Vector3 = axis["to"] - axis["from"]
	along.y = 0.0
	if along.length() < 0.001:
		along = Vector3(0, 0, 1)
	var horizontal := along.normalized().cross(Vector3.UP).normalized().rotated(Vector3.UP, deg_to_rad(float(v.get("yaw", 0.0))))
	var sphere := bounding_sphere(scene, points)
	var center: Vector3 = sphere["center"]
	var distance := float(sphere["radius"]) / tan(deg_to_rad(FOV_DEG) * 0.5) * MARGIN / maxf(float(v.get("zoom", 1.0)), 0.1)
	var eye := center + horizontal * distance
	eye.y = float(v.get("height", HEIGHT))
	return {"direction": (eye - center).normalized(), "center": center, "distance": eye.distance_to(center)}


## Direction is the horizontal unit vector from the scene centre towards the camera.
static func _preset(scene: PosingScene, horizontal: Vector3, points: Array[Vector3] = []) -> Dictionary:
	var sphere := bounding_sphere(scene, points)
	var center: Vector3 = sphere["center"]
	var radius: float = sphere["radius"]
	var distance := radius / tan(deg_to_rad(FOV_DEG) * 0.5) * MARGIN
	# The camera sits at HEIGHT; aim at the sphere centre from there.
	var eye := center + horizontal * distance
	eye.y = HEIGHT
	var direction := (eye - center).normalized()
	return {"direction": direction, "center": center, "distance": eye.distance_to(center)}


## Bounding sphere over the framing bones of every visible character.
## `points` frames those instead of the scene as it stands: a technique is framed over all of its
## poses, or a figure thrown a long way leaves the picture.
static func bounding_sphere(scene: PosingScene, points: Array[Vector3] = []) -> Dictionary:
	if points.is_empty():
		points = frame_points(scene)
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


## Where every visible character is right now, as the handful of bones that bound it well enough.
## With `fk` the bones are read from the pose alone rather than from the last solve, which needs
## no frame to have been drawn: framing a whole technique means walking its poses, and waiting a
## frame on each would record those frames into the video being made.
static func frame_points(scene: PosingScene, fk := false) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for rig in scene.characters:
		if not rig.visible:
			continue
		for bone in FRAME_BONES:
			points.append((rig.fk_bone_transform(bone) if fk else rig.bone_world_transform(bone)).origin)
	return points


## Points that bound the figures as they are drawn on this frame (after the solve), for the film's
## following camera: the framing bones, the top of the head (hair) and both ends of every visible
## weapon.
static func film_points(scene: PosingScene) -> Array[Vector3]:
	var points := frame_points(scene)
	for rig in scene.characters:
		if rig.visible:
			points.append(rig.bone_world_transform("Head").origin + Vector3(0, 0.16, 0))
			for foot in ["RightFoot", "LeftFoot"]:   # the bone is the ankle: the sole is below it
				var a := rig.bone_world_transform(foot).origin
				points.append(Vector3(a.x, maxf(a.y - 0.1, 0.0), a.z))
	for w in scene.weapons:
		if w.visible:
			points.append(w.anchor_transform(0.0).origin)
			points.append(w.anchor_transform(1.0).origin)
	return points


## The film's lens (vertical field of view, degrees): longer than the stills', so a foot stepped
## towards the camera does not loom over the rest and the figures can fill the frame.
const FILM_FOV_DEG := 30.0
## Fraction of the half-frame the outermost point of the figures may reach in the film.
const FILM_FILL := 0.94
## Each film point stands for a joint with flesh, cloth and a hakama's flare round it (m).
const FILM_PAD := 0.07
## How slowly the film's camera follows: the spread (s) of the smoothing of where it looks, and of
## how far back it stands. Short enough to keep a thrown Uke in, long enough not to jitter.
const FILM_CENTER_SMOOTH := 0.35
const FILM_DISTANCE_SMOOTH := 0.15
## The camera stands back early for what is coming within this time (s), rather than zooming out
## after a limb has reached the edge.
const FILM_LOOKAHEAD := 0.3
## The least height (m) the film shows, so a figure crouched or lying is not filled to the edges.
const FILM_MIN_HEIGHT := 1.3


## The film's camera, one {center, distance} per frame: always looking the same way (`direction`,
## from the figures towards the camera, the sequence's own view), but moving with the figures and
## standing as close as frames them, smoothed so it glides. `samples[i]` are the points that must be
## in frame i (film_points). A camera framed once over the whole technique (bounding_sphere over
## every pose) left most of the picture empty, the more so when Uke walks in or is thrown.
static func follow_track(direction: Vector3, samples: Array, fps: float, aspect: float, fov_deg: float = FOV_DEG) -> Array:
	var back := direction.normalized()
	var right := Vector3.UP.cross(back).normalized()
	var up := back.cross(right).normalized()
	var tan_v := tan(deg_to_rad(fov_deg) * 0.5)
	var tan_h := tan_v * aspect
	var n := samples.size()
	if n == 0:
		return []
	# Where to look: the middle of the figures as the camera sees them. Begun at the middle of their
	# box (across, up and in depth), then moved until their outline in the picture is centred, with
	# the distance scaled to fit, a few times over: a foot nearer the camera shows lower and wider.
	var raw_center: Array[Vector3] = []
	for pts in samples:
		if pts.is_empty():
			raw_center.append(raw_center[-1] if not raw_center.is_empty() else Vector3(0, 0.9, 0))
			continue
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for p in pts:
			var c := Vector3(p.dot(right), p.dot(up), p.dot(back))
			lo = lo.min(c)
			hi = hi.max(c)
		var m := (lo + hi) * 0.5
		var c: Vector3 = right * m.x + up * m.y + back * m.z
		var d := maxf((hi.x - lo.x) / tan_h, (hi.y - lo.y) / tan_v) * 0.5 + (hi.z - lo.z)
		for _it in 6:
			var eye := c + back * d
			var u_lo := INF
			var u_hi := -INF
			var v_lo := INF
			var v_hi := -INF
			for p in pts:
				var r: Vector3 = p - eye
				var depth := maxf(-r.dot(back), 0.05)
				u_lo = minf(u_lo, r.dot(right) / depth / tan_h)
				u_hi = maxf(u_hi, r.dot(right) / depth / tan_h)
				v_lo = minf(v_lo, r.dot(up) / depth / tan_v)
				v_hi = maxf(v_hi, r.dot(up) / depth / tan_v)
			c += right * ((u_lo + u_hi) * 0.5 * tan_h * d) + up * ((v_lo + v_hi) * 0.5 * tan_v * d)
			d *= clampf(maxf(u_hi - u_lo, v_hi - v_lo) * 0.5, 0.5, 2.0)
		raw_center.append(c)
	var center := _smooth_vec(raw_center, FILM_CENTER_SMOOTH * fps)
	# How far back to stand so every point is inside FILM_FILL of the frame, looking at that centre:
	# a point nearer the camera (+back) by z needs the camera further by z.
	var need: Array[float] = []
	var least := FILM_MIN_HEIGHT * 0.5 / FILM_FILL / tan_v
	for i in n:
		var d := least
		for p in samples[i]:
			var r: Vector3 = p - center[i]
			var z := r.dot(back)
			d = maxf(d, (absf(r.dot(right)) + FILM_PAD) / (tan_h * FILM_FILL) + z + FILM_PAD)
			d = maxf(d, (absf(r.dot(up)) + FILM_PAD) / (tan_v * FILM_FILL) + z + FILM_PAD)
		need.append(d)
	# Stand back for what the next moments need, then glide; never closer than this frame needs.
	var reach := int(round(FILM_LOOKAHEAD * fps))
	var ahead: Array[float] = []
	for i in n:
		var d := need[i]
		for k in range(maxi(0, i - reach), mini(n, i + reach + 1)):
			d = maxf(d, need[k])
		ahead.append(d)
	var dist := _smooth_float(ahead, FILM_DISTANCE_SMOOTH * fps)
	var out := []
	for i in n:
		out.append({"center": center[i], "distance": maxf(dist[i], need[i]), "direction": back})
	return out


static func _gauss_weights(sigma: float) -> Array[float]:
	var w: Array[float] = []
	var r := int(ceil(sigma * 3.0))
	for k in range(-r, r + 1):
		w.append(exp(-0.5 * k * k / maxf(sigma * sigma, 1e-6)))
	return w


static func _smooth_vec(v: Array[Vector3], sigma: float) -> Array[Vector3]:
	var w := _gauss_weights(sigma)
	var r := (w.size() - 1) / 2
	var out: Array[Vector3] = []
	for i in v.size():
		var s := Vector3.ZERO
		var tw := 0.0
		for k in range(-r, r + 1):
			var j := clampi(i + k, 0, v.size() - 1)
			s += v[j] * w[k + r]
			tw += w[k + r]
		out.append(s / tw)
	return out


static func _smooth_float(v: Array[float], sigma: float) -> Array[float]:
	var w := _gauss_weights(sigma)
	var r := (w.size() - 1) / 2
	var out: Array[float] = []
	for i in v.size():
		var s := 0.0
		var tw := 0.0
		for k in range(-r, r + 1):
			var j := clampi(i + k, 0, v.size() - 1)
			s += v[j] * w[k + r]
			tw += w[k + r]
		out.append(s / tw)
	return out
