class_name SequencePlayer
extends Node
## Plays a Sequence on the scene: keeps a clock, looks up the two poses around it and asks
## PoseBlend to put the scene there. Scrubbing is the same call with a chosen time.

signal time_changed(time: float)
signal finished

var scene: PosingScene
var director: GripDirector
var camera: Node        ## OrbitCamera, only used when the sequence's camera is "per_pose"
var sequence: Sequence
var poses: Dictionary = {}     ## slug -> pose dictionary
var time := 0.0
var playing := false
var loop := false
var _entities_ready := false


func setup(posing_scene: PosingScene, grip_director: GripDirector) -> void:
	scene = posing_scene
	director = grip_director


## Loads every pose the sequence names from `poses_dir`. Returns the slugs that were missing.
func load_sequence(seq: Sequence, poses_dir: String) -> Array:
	sequence = seq
	poses.clear()
	var missing := []
	for step in seq.steps:
		var slug: String = step["pose"]
		if poses.has(slug):
			continue
		var data := PoseFile.load(poses_dir.path_join(slug + ".json"))
		if data.is_empty():
			missing.append(slug)
		else:
			poses[slug] = data
	time = 0.0
	_entities_ready = false
	return missing


func set_pose_data(slug: String, data: Dictionary) -> void:
	poses[slug] = data


func duration() -> float:
	return sequence.duration() if sequence else 0.0


func play() -> void:
	if sequence == null:
		return
	if time >= duration():
		time = 0.0
	playing = true


func pause() -> void:
	playing = false


func stop() -> void:
	playing = false
	seek(0.0)


func seek(t: float) -> void:
	time = clampf(t, 0.0, duration())
	apply_time(time)
	time_changed.emit(time)


func _process(delta: float) -> void:
	if not playing:
		return
	time += delta
	if time >= duration():
		if loop:
			time = fmod(time, maxf(duration(), 1e-3))
		else:
			time = duration()
			playing = false
			apply_time(time)
			time_changed.emit(time)
			finished.emit()
			return
	apply_time(time)
	time_changed.emit(time)


## Puts the scene at `t` without touching the clock.
func apply_time(t: float) -> void:
	if sequence == null or sequence.steps.is_empty():
		return
	if not _entities_ready:
		PoseBlend.ensure_entities(scene, poses.values())
		_entities_ready = true
	var st := sequence.state_at(t)
	var a: Dictionary = poses.get(sequence.steps[st["from"]]["pose"], {})
	var b: Dictionary = poses.get(sequence.steps[st["to"]]["pose"], a)
	if a.is_empty():
		return
	if st["from"] == st["to"]:
		PoseBlend.apply(scene, director, a, a, 0.0)
	else:
		PoseBlend.apply(scene, director, a, b, st["u"])
	if camera != null and sequence.camera == "per_pose":
		var ca = a.get("camera")
		var cb = b.get("camera")
		if ca is Dictionary or cb is Dictionary:
			camera.apply_state(OrbitCamera.blend_state(ca if ca is Dictionary else {}, cb if cb is Dictionary else {}, st["u"]))
