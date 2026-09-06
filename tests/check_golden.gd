extends SceneTree
## Golden-image regression on the rendered stills. Every still that run.sh renders is shrunk to
## a thumbnail and compared with the copy under tests/golden/; a still that moved more than a
## few percent of its pixels fails. Goldens are what a person looked at and accepted:
## regenerate them deliberately with UPDATE_GOLDEN=1 after checking the full-size renders.
##
## Thumbnails are compared rather than full frames so that anti-aliasing and driver noise
## between machines does not count, and so the goldens stay small in the repository.

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)

const GOLDEN := "res://tests/golden"
const THUMB_W := 192
const THUMB_H := 108
## A pixel counts as changed when any channel moves more than this (0..255).
const CHANNEL_TOLERANCE := 40
## Fraction of changed pixels a still may have before it fails.
const MAX_CHANGED := 0.02

## Stills to compare: [golden name, rendered file]. Acceptance exports are included only when
## they were rendered (RENDER_ACCEPTANCE=1 in run.sh).
func _stills() -> Array:
	var out := []
	var tests_out := ProjectSettings.globalize_path("res://tests/out")
	out.append(["m1_flat", tests_out.path_join("m1_flat.png")])
	out.append(["m1_transparent", tests_out.path_join("m1_transparent.png")])
	for phase in ["grepp", "kuzushi", "kake"]:
		for view in ["front", "side"]:
			out.append(["m7_katatedori_ikkyo_%s_%s" % [phase, view], tests_out.path_join("m7/katatedori_ikkyo_%s_%s.png" % [phase, view])])
	var exports := ProjectSettings.globalize_path("res://exports")
	var d := DirAccess.open(exports)
	if d and OS.get_environment("RENDER_ACCEPTANCE") != "0":
		var names := []
		for f in d.get_files():
			if f.ends_with("_front.png") or f.ends_with("_side.png"):
				names.append(f)
		names.sort()
		for f in names:
			out.append(["export_" + f.get_basename(), exports.path_join(f)])
	return out


func _initialize() -> void:
	var update := OS.get_environment("UPDATE_GOLDEN") == "1"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GOLDEN))
	var updated := 0
	for entry in _stills():
		var name: String = entry[0]
		var img := Image.load_from_file(entry[1])
		if img == null:
			check(false, "%s: rendered still %s exists" % [name, entry[1]])
			continue
		img.resize(THUMB_W, THUMB_H, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGBA8)
		var gpath := GOLDEN.path_join(name + ".png")
		if update or not FileAccess.file_exists(gpath):
			img.save_png(ProjectSettings.globalize_path(gpath))
			updated += 1
			print("PASS %s: golden written" % name)
			continue
		var gold := Image.load_from_file(ProjectSettings.globalize_path(gpath))
		if gold == null or gold.get_width() != THUMB_W or gold.get_height() != THUMB_H:
			check(false, "%s: golden is readable at %dx%d" % [name, THUMB_W, THUMB_H])
			continue
		gold.convert(Image.FORMAT_RGBA8)
		var changed := 0
		for y in THUMB_H:
			for x in THUMB_W:
				var a := img.get_pixel(x, y)
				var b := gold.get_pixel(x, y)
				if absf(a.r - b.r) * 255.0 > CHANNEL_TOLERANCE or absf(a.g - b.g) * 255.0 > CHANNEL_TOLERANCE \
						or absf(a.b - b.b) * 255.0 > CHANNEL_TOLERANCE or absf(a.a - b.a) * 255.0 > CHANNEL_TOLERANCE:
					changed += 1
		var frac := float(changed) / float(THUMB_W * THUMB_H)
		if frac > MAX_CHANGED:
			img.save_png(ProjectSettings.globalize_path("res://tests/out/golden_diff_%s.png" % name))
		check(frac <= MAX_CHANGED, "%s matches its golden (%.1f%% of pixels changed)" % [name, frac * 100.0])
	if updated > 0:
		print("%d golden thumbnails written to %s; look at the full-size renders before committing them" % [updated, GOLDEN])
	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)
