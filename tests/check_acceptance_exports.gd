extends SceneTree
## After tests/run.sh has rendered every acceptance sequence: each technique has Front and Side
## stills for every phase at full size with predictable names, and a frame sequence (plus an
## MP4 when ffmpeg was available) whose length matches the sequence.

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)

var EXPORTS := ProjectSettings.globalize_path("res://exports")
## Main.gd has no class_name (it is the scene root script); its phase-naming rule is static.
const MAIN := preload("res://src/app/Main.gd")


func _initialize() -> void:
	var d := DirAccess.open("res://sequences")
	var files := []
	for f in d.get_files():
		if f.ends_with(".json"):
			files.append(f)
	files.sort()
	var have_ffmpeg := MovieExport.has_ffmpeg()
	for f in files:
		var seq := Sequence.load("res://sequences/" + f)
		var slug := seq.slug()
		var phases: Array = MAIN._phase_names(seq)
		for i in seq.steps.size():
			for view in ["front", "side"]:
				var p := EXPORTS.path_join("%s_%s_%s.png" % [slug, phases[i], view])
				var img := Image.load_from_file(p)
				check(img != null and img.get_width() == MovieExport.WIDTH, "%s: %s" % [slug, p.get_file()])
		var frames := 0
		var fd := DirAccess.open(EXPORTS.path_join(slug + "_frames"))
		if fd:
			for g in fd.get_files():
				if g.ends_with(".png"):
					frames += 1
		var expected := int(round(seq.duration() * MovieExport.FPS))
		check(frames >= expected and frames <= expected + 12, "%s: %d video frames for %.1f s" % [slug, frames, seq.duration()])
		if have_ffmpeg:
			check(FileAccess.file_exists(EXPORTS.path_join(slug + ".mp4")), "%s: mp4 written" % slug)
	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)
