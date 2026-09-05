class_name StillExport
extends RefCounted
## Saves the current view as PNG with either the scene background or a transparent one.

static func slugify(text: String) -> String:
	var s := text.to_lower()
	for pair in [["å", "a"], ["ä", "a"], ["ö", "o"], ["é", "e"], ["ü", "u"]]:
		s = s.replace(pair[0], pair[1])
	var out := ""
	var last_us := false
	for ch in s:
		var ok := (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9")
		if ok:
			out += ch
			last_us = false
		elif not last_us:
			out += "_"
			last_us = true
	return out.trim_prefix("_").trim_suffix("_")


## Captures `viewport` to `path`.
## `hide_always` (UI overlay, gizmos) is hidden for every export; `hide_for_transparent`
## (floor, backdrop) only when a transparent background is requested.
## Nodes are hidden for the whole capture and restored afterwards, so nothing the instructor
## sees on screen leaks into the exported image.
##
## Two constraints, both found by testing on Godot 4.6:
##  * A display is required. Under --headless the render callback never arrives and the await hangs,
##    so we refuse early instead.
##  * The UI CanvasLayer must be among the hidden nodes. Capturing with it visible deadlocks the
##    same way, and a UI-free image is what the handout needs anyway.
static func capture(
		viewport: Viewport,
		path: String,
		transparent: bool,
		hide_always: Array[Node] = [],
		hide_for_transparent: Array[Node] = []) -> Error:
	if DisplayServer.get_name() == "headless":
		push_error("StillExport.capture needs a display; run without --headless (use xvfb-run on a server).")
		return ERR_UNAVAILABLE
	var prev_bg := viewport.transparent_bg
	var hidden: Array[Node] = hide_always.duplicate()
	if transparent:
		viewport.transparent_bg = true
		hidden.append_array(hide_for_transparent)
	var was_visible := []
	for n in hidden:
		was_visible.append(n.visible)
		n.visible = false
		if n is RotationGizmo:
			n.suppressed = true
	# Two frames: one to apply the visibility changes, one to render the clean image.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := viewport.get_texture().get_image()
	viewport.transparent_bg = prev_bg
	for i in hidden.size():
		if hidden[i] is RotationGizmo:
			hidden[i].suppressed = false
		hidden[i].visible = was_visible[i]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return img.save_png(path)
