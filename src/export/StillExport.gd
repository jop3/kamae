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


## Captures the 3D world seen by `viewport`'s camera to `path` at OUTPUT_SIZE, rendered at
## SUPERSAMPLE times that size through a SubViewport that shares the world and downscaled with a
## Lanczos filter (spec §5.8: 2× supersampled then downscaled to soften edges). The
## Compatibility renderer ignores `scaling_3d_scale`, so the extra resolution has to come from a
## viewport of its own; that also makes the still independent of the window size.
##
## `hide_always` (UI overlay, gizmos, handles) is hidden for every export; `hide_for_transparent`
## (floor, backdrop) only when a transparent background is requested. Everything is restored
## afterwards on every path.
##
## Two constraints, both found by testing on Godot 4.6:
##  * A display is required. Under --headless the render callback never arrives and the await hangs,
##    so we refuse early instead.
##  * Overlapping captures would record each other's hidden state as the one to restore, so a
##    second call while one is pending is refused with ERR_BUSY.
const OUTPUT_SIZE := Vector2i(1920, 1080)
const SUPERSAMPLE := 2

static var _busy := false


static func capture(
		viewport: Viewport,
		path: String,
		transparent: bool,
		hide_always: Array[Node] = [],
		hide_for_transparent: Array[Node] = []) -> Error:
	if DisplayServer.get_name() == "headless":
		push_error("StillExport.capture needs a display; run without --headless (use xvfb-run on a server).")
		return ERR_UNAVAILABLE
	if _busy:
		return ERR_BUSY
	_busy = true
	var camera := viewport.get_camera_3d()
	if camera == null:
		_busy = false
		return ERR_UNCONFIGURED
	var hidden: Array[Node] = hide_always.duplicate()
	if transparent:
		hidden.append_array(hide_for_transparent)
	var was_visible := []
	for n in hidden:
		was_visible.append(n.visible)
		n.visible = false
		if n is RotationGizmo:
			n.suppressed = true
	# A private viewport on the same world, at supersampled size, with a copy of the camera.
	var sub := SubViewport.new()
	sub.size = OUTPUT_SIZE * SUPERSAMPLE
	sub.world_3d = viewport.world_3d
	sub.transparent_bg = transparent
	sub.msaa_3d = viewport.msaa_3d
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam2 := Camera3D.new()
	sub.add_child(cam2)
	viewport.add_child(sub)
	cam2.global_transform = camera.global_transform
	cam2.fov = camera.fov
	cam2.projection = camera.projection
	cam2.size = camera.size
	cam2.near = camera.near
	cam2.far = camera.far
	cam2.current = true
	# Two frames: one to apply the visibility changes, one to render the clean image.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()
	sub.queue_free()
	for i in hidden.size():
		if is_instance_valid(hidden[i]):
			if hidden[i] is RotationGizmo:
				hidden[i].suppressed = false
			hidden[i].visible = was_visible[i]
	_busy = false
	if img == null:
		return ERR_CANT_CREATE
	img.resize(OUTPUT_SIZE.x, OUTPUT_SIZE.y, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return img.save_png(path)
