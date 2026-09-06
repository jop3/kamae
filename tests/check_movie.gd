extends SceneTree
## Checks the output of the video-export child run made by tests/run.sh (Movie Maker under Xvfb).

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)

const OUT := "/home/user/kamae/tests/out/m6"


func _initialize() -> void:
	var seq := Sequence.load("/home/user/kamae/tests/out/poses_m5/katatedori_ikkyo.sequence.json")
	check(seq != null, "the sequence written by test_m5 is readable")
	var expected := int(round(seq.duration() * MovieExport.FPS)) if seq else 0
	var frames := 0
	var d := DirAccess.open(OUT.path_join("frames"))
	if d:
		for f in d.get_files():
			if f.begins_with("f") and f.ends_with(".png"):
				frames += 1
	check(frames >= expected and frames <= expected + 12, "frame count matches duration x fps (%d frames for %.1f s, expected about %d)" % [frames, seq.duration() if seq else 0.0, expected])
	var img := Image.load_from_file(OUT.path_join("frames/f00000030.png"))
	check(img != null and img.get_width() == MovieExport.WIDTH and img.get_height() == MovieExport.HEIGHT, "frames are %dx%d" % [MovieExport.WIDTH, MovieExport.HEIGHT])
	if img:
		# No IK handle may leak into a frame: handles are pure blue or grey, skin is teal/amber.
		var blue := 0
		for y in range(0, img.get_height(), 4):
			for x in range(0, img.get_width(), 4):
				var c := img.get_pixel(x, y)
				if c.b > 0.8 and c.r < 0.3 and c.g < 0.55:
					blue += 1
		check(blue == 0, "no IK handle pixels in the frames (%d samples)" % blue)
	for phase in ["grepp", "kuzushi", "kake"]:
		var p := OUT.path_join("katatedori_ikkyo_%s.png" % phase)
		var still := Image.load_from_file(p)
		check(still != null and still.get_width() == MovieExport.WIDTH, "phase still %s exists at full size" % p.get_file())
	# Front+Side batch: two stills per phase from the --render-stills child.
	for phase in ["grepp", "kuzushi", "kake"]:
		for view in ["front", "side"]:
			var p := "/home/user/kamae/tests/out/m7/katatedori_ikkyo_%s_%s.png" % [phase, view]
			var still := Image.load_from_file(p)
			check(still != null and still.get_width() == MovieExport.WIDTH, "Front+Side still %s exists at full size" % p.get_file())
	# The exporter's own command lines, checked without spawning anything.
	var args := MovieExport.child_args("/s.json", "/poses", "/out/f.png", "/out")
	check("--write-movie" in args and "--fixed-fps" in args and "--render-sequence" in args and "--" in args, "child command line carries Movie Maker flags and the render request")
	var ff := MovieExport.ffmpeg_args("/out/frames", "/out/x.mp4")
	check("libx264" in ff and "yuv420p" in ff and "/out/frames/f%08d.png" in ff, "ffmpeg command encodes H.264 yuv420p from the frame pattern")
	print("ffmpeg on this machine: %s" % ("yes" if MovieExport.has_ffmpeg() else "no (AVI fallback would be used)"))
	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)
