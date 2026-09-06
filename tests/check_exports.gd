extends SceneTree
## Verifies the rendered stills produced by tests/run.sh: correct alpha, and no UI or gizmo baked in.

var failures := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)


func _initialize() -> void:
	# tests/out carries a .gdignore so Godot's importer leaves the rendered files alone;
	# they are therefore read from disk by absolute path, not as res:// resources.
	var dir := ProjectSettings.globalize_path("res://tests/out")
	var transparent := Image.load_from_file(dir.path_join("m1_transparent.png"))
	var flat := Image.load_from_file(dir.path_join("m1_flat.png"))
	check(transparent != null and flat != null, "both stills exist")
	if transparent == null or flat == null:
		quit(1); return
	var w := transparent.get_width()
	var h := transparent.get_height()
	check(transparent.get_pixel(5, 5).a == 0.0, "transparent still: background is fully transparent")
	# The side panel occupies the right 300 px; nothing from it may survive an export.
	var panel_opaque := 0
	for x in range(w - 290, w, 7):
		for y in range(0, h, 7):
			if transparent.get_pixel(x, y).a > 0.0:
				panel_opaque += 1
	check(panel_opaque == 0, "transparent still: no UI panel pixels (%d opaque samples)" % panel_opaque)
	# The gizmo rings are saturated red/green/blue; the mannequins are teal and amber.
	var gizmo_px := 0
	for x in range(0, w, 3):
		for y in range(0, h, 3):
			var c := transparent.get_pixel(x, y)
			if c.a > 0.5 and (c.r > 0.8 and c.g < 0.4 and c.b < 0.4) or (c.a > 0.5 and c.b > 0.85 and c.r < 0.4 and c.g < 0.6):
				gizmo_px += 1
	check(gizmo_px == 0, "transparent still: no gizmo ring pixels (%d samples)" % gizmo_px)
	check(flat.get_pixel(5, 5).a == 1.0, "flat still: background is opaque")
	check(flat.get_width() == StillExport.OUTPUT_SIZE.x and flat.get_height() == StillExport.OUTPUT_SIZE.y, "still is rendered at the export size %dx%d regardless of the window (%dx%d)" % [StillExport.OUTPUT_SIZE.x, StillExport.OUTPUT_SIZE.y, flat.get_width(), flat.get_height()])
	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)
