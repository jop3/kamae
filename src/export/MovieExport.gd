class_name MovieExport
extends Node
## Video export (spec §5.8): a second instance of this program renders the sequence frame by
## frame with Godot's Movie Maker, then ffmpeg encodes the PNG frames to MP4 (H.264, yuv420p,
## 30 fps). Without ffmpeg the child writes an MJPEG AVI directly and the tool says so.
##
## Movie Maker does not create its output directory, so it is created here first. The frames are
## kept unless `keep_frames` is off: they double as stills.

signal started(job: Dictionary)
signal finished(job: Dictionary)

const FPS := 30
const WIDTH := 1920
const HEIGHT := 1080

var keep_frames := true
var _pid := -1
var _job: Dictionary = {}


## True when an ffmpeg binary answers on PATH.
static func has_ffmpeg() -> bool:
	var out := []
	return OS.execute("ffmpeg", ["-version"], out, false) == 0


## Starts rendering `sequence_path` (a sequence JSON) with poses from `poses_dir` into `out_dir`.
## Returns the job description or an empty dictionary when a job is already running.
func export_sequence(sequence_path: String, poses_dir: String, out_dir: String) -> Dictionary:
	if _pid >= 0:
		return {}
	var seq := Sequence.load(sequence_path)
	if seq == null:
		push_error("MovieExport: cannot read %s" % sequence_path)
		return {}
	var slug := seq.slug()
	var use_ffmpeg := has_ffmpeg()
	var frames_dir := out_dir.path_join(slug + "_frames")
	DirAccess.make_dir_recursive_absolute(out_dir)
	DirAccess.make_dir_recursive_absolute(frames_dir)
	var movie_target := frames_dir.path_join("f.png") if use_ffmpeg else out_dir.path_join(slug + ".avi")
	_job = {
		"slug": slug,
		"sequence": sequence_path,
		"poses_dir": poses_dir,
		"out_dir": out_dir,
		"frames_dir": frames_dir,
		"movie_target": movie_target,
		"ffmpeg": use_ffmpeg,
		"output": out_dir.path_join(slug + (".mp4" if use_ffmpeg else ".avi")),
		"stills": [],
		"ok": false,
		"message": "",
	}
	var args := child_args(sequence_path, poses_dir, movie_target, out_dir)
	_pid = OS.create_process(OS.get_executable_path(), args)
	if _pid < 0:
		_job["message"] = "Could not start the render process"
		var failed := _job
		_job = {}
		finished.emit(failed)
		return failed
	started.emit(_job)
	return _job


## Starts a child that writes Front and Side stills for every phase of the sequence.
func export_stills(sequence_path: String, poses_dir: String, out_dir: String, transparent := false) -> Dictionary:
	if _pid >= 0:
		return {}
	var seq := Sequence.load(sequence_path)
	if seq == null:
		return {}
	DirAccess.make_dir_recursive_absolute(out_dir)
	_job = {"slug": seq.slug(), "sequence": sequence_path, "poses_dir": poses_dir, "out_dir": out_dir,
		"frames_dir": "", "movie_target": "", "ffmpeg": false, "stills_only": true,
		"output": out_dir, "stills": [], "ok": false, "message": ""}
	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--resolution", "%dx%d" % [WIDTH, HEIGHT], "--",
		"--render-stills", sequence_path, "--poses-dir", poses_dir, "--stills-dir", out_dir])
	if transparent:
		args.append("--transparent")
	_pid = OS.create_process(OS.get_executable_path(), args)
	if _pid < 0:
		_job = {}
		return {}
	started.emit(_job)
	return _job


## Command line for the child render, kept in one place so tests can check it.
static func child_args(sequence_path: String, poses_dir: String, movie_target: String, stills_dir: String) -> PackedStringArray:
	return PackedStringArray([
		"--path", ProjectSettings.globalize_path("res://"),
		"--write-movie", movie_target,
		"--fixed-fps", str(FPS),
		"--resolution", "%dx%d" % [WIDTH, HEIGHT],
		"--",
		"--render-sequence", sequence_path,
		"--poses-dir", poses_dir,
		"--stills-dir", stills_dir,
	])


static func ffmpeg_args(frames_dir: String, output: String) -> PackedStringArray:
	return PackedStringArray([
		"-y", "-framerate", str(FPS), "-i", frames_dir.path_join("f%08d.png"),
		"-c:v", "libx264", "-pix_fmt", "yuv420p", output,
	])


func is_running() -> bool:
	return _pid >= 0


func _process(_delta: float) -> void:
	if _pid < 0:
		return
	if OS.is_process_running(_pid):
		return
	_pid = -1
	var job := _job
	_job = {}
	if job.get("stills_only", false):
		job["stills"] = _list_pngs(job["out_dir"], job["slug"])
		job["ok"] = not job["stills"].is_empty()
		job["message"] = "%d stills written to %s" % [job["stills"].size(), job["out_dir"]] if job["ok"] else "No stills were written"
		finished.emit(job)
		return
	if job["ffmpeg"]:
		var out := []
		var code := OS.execute("ffmpeg", ffmpeg_args(job["frames_dir"], job["output"]), out, true)
		job["ok"] = code == 0 and FileAccess.file_exists(job["output"])
		job["message"] = "MP4 written to %s" % job["output"] if job["ok"] else "ffmpeg failed (%d): %s" % [code, "".join(out).right(400)]
		if job["ok"] and not keep_frames:
			_remove_dir(job["frames_dir"])
	else:
		job["ok"] = FileAccess.file_exists(job["output"])
		job["message"] = ("AVI written to %s (ffmpeg not found, so no MP4; install ffmpeg for H.264)" % job["output"]) if job["ok"] else "The render produced no file"
	job["stills"] = _list_pngs(job["out_dir"], job["slug"])
	finished.emit(job)


static func _list_pngs(dir: String, prefix: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.begins_with(prefix + "_") and f.ends_with(".png"):
			out.append(dir.path_join(f))
	out.sort()
	return out


static func _remove_dir(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(dir)
