extends SceneTree
## Are the hands actually holding what they hold?
##
## Nothing measured this until now. A gripping hand is exempt from the intersection checks — a
## held shaft runs through the fist by design (Anatomy.weapon_intersections), and so does a
## gripped forearm — so a hand could close beside what it held, or through it, and every other
## check passed. Both were happening: the close-up renders showed fists shut past the tsuka and
## fingers straight through a forearm, and this is what says so in numbers.
##
## For every grip in every committed pose, each finger joint is measured against the surface of
## what the hand holds: the shaft's own half-width for a weapon, the mesh's own radius there for
## a bone (CharacterRig.skin_radius, not the coarse collision capsule). A finger resting on
## something sits about its own thickness outside it. Too far in and the finger is through it;
## too far out and the hand is holding air.
##
## GRIPS_VERBOSE=1 prints every joint of every grip.

var failures := 0
var seen := {}
func check(cond: bool, msg: String) -> void:
	if cond: print("PASS ", msg)
	else: failures += 1; print("FAIL ", msg)


## Drops a problem this grip is known to have and still fails if a known one has gone away, so a
## fix lands with its entry removed rather than silently.
func check_grip(cond: bool, key: String, msg: String) -> void:
	if OUTSTANDING.has(key):
		if cond:
			return   # it may be the other rule on the same hand that is outstanding
		seen[key] = true
		print("KNOWN ", msg, " — ", OUTSTANDING[key])
		return
	check(cond, msg)

## A finger bone's own radius: the middle of the finger sits this far out when it rests on
## something, so clearances are measured against it.
const FINGER := 0.011
## How far a joint may be inside the surface (the mesh is not a cylinder, and a finger presses
## into an arm), and how far out the nearest joint of a hand may be before it is holding air.
const INSIDE := 0.012
const OUTSIDE := 0.030
## Fingers that reach nothing at all (a hand laid on a thigh, a thumb that cannot span a jo) do
## not count against the hand: the rule is that a hand has a grip, not that every finger does.
const NEEDED := 2

## What this still finds, as the poses stand today, with what each one is. Like the other checks'
## lists, an entry that stops happening fails and asks to be removed, so these cannot quietly rot.
## Matched as "<slug>: <gripper> <hand>" against the start of the message.
const OUTSTANDING := {
	## The thumb comes over the far side of a forearm and the fit cannot clear it: the curl it
	## needs is not a curl at all — the metacarpal has to swing across the palm first
	## (FingerCurl's thumb chain), which nothing asks it to do yet.
	"katatedori_ikkyo_kake: tori left": "thumb, and a middle finger 16 mm into an upper arm",
	"katatedori_shihonage_kuzushi: uke1 left": "thumb",
	"ryotemochi_kuzushi: uke1 right": "thumb",
	"ryotemochi_kuzushi: uke2 left": "thumb",
	"ushiro_ryotedori_zenponage_grepp: uke1 right": "thumb",
	"ushiro_ryotedori_zenponage_grepp: uke1 left": "thumb",
	"ushiro_ryotedori_zenponage_kuzushi: uke1 right": "thumb",
	"ushiro_ryotedori_zenponage_kuzushi: uke1 left": "thumb",
	## An index finger that reaches round a forearm and meets the thumb's side of it. The jo's
	## were the same fault and went when the weapon fit started weighing the fingers too
	## (Staging.fingers_through_shaft).
	"ryotemochi_grepp: uke1 right": "index finger round a forearm",
	"ryotemochi_grepp: uke2 left": "index finger round a forearm",
	## Tori takes Uke's forearm and then the sword is refitted in Uke's hands, which moves that
	## forearm out from under the hand already on it. The grab would have to be re-taken after
	## the weapon fit, or the fit told not to move a limb someone is holding.
	"tachi_dori_irimi: tori right": "the arm moves after the hand takes it",
	## The instructor's, both of them: Uke's hands are nowhere near Tori's arms in the Kake, and
	## barely on them in the Tenkan. Re-seating those two put a hand out of reach altogether
	## (tools/refit_grips.gd), so they are still the old seat; docs/handoff.md.
	"ushiro_ryotedori_zenponage_kake: uke1 right": "the hand is half a metre from the arm it holds",
	"ushiro_ryotedori_zenponage_kake: uke1 left": "the hand is a third of a metre from the arm it holds",
	"ushiro_ryotedori_zenponage_tenkan: uke1 right": "a little finger through a forearm",
	"ushiro_ryotedori_zenponage_tenkan: uke1 left": "the hand is 5 cm off the arm it holds",
	## Tori's hand is pressed into Uke's forearm as the grip turns it — the same shihonage
	## question the other checks record (tests/check_anatomy.gd).
	"katatedori_shihonage_kake: tori left": "the hand is pressed into the forearm it turns",
}

const POSES := "res://poses"
var scene: PosingScene
var ctrl: PoseController
var director: GripDirector


func settle(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	await process_frame
	var world := Node3D.new(); root.add_child(world)
	scene = PosingScene.new(); world.add_child(scene)
	var cam := Camera3D.new(); world.add_child(cam)
	var gizmo := RotationGizmo.new(); world.add_child(gizmo)
	ctrl = PoseController.new(); world.add_child(ctrl); ctrl.setup(scene, cam, gizmo)
	director = GripDirector.new(); world.add_child(director); director.setup(scene, ctrl)
	await physics_frame
	var verbose := OS.get_environment("GRIPS_VERBOSE") == "1"
	for f in _files(POSES):
		var slug: String = f.get_basename()
		var data := PoseFile.load(POSES.path_join(f))
		if data.is_empty():
			continue
		PoseFile.apply(data, scene, director, ctrl)
		await settle(4)
		for grip in director.grips:
			var g := scene.get_character(grip.gripper_id)
			if g == null:
				continue
			var axis := _held_axis(grip)
			if axis.is_empty():
				continue
			var inside := PackedStringArray()
			var nearest := INF
			for finger in FingerCurl.FINGERS:
				for part: String in FingerCurl.SEGMENTS[finger]:
					var bone: String = "%s%s%s" % [grip.hand, finger, part]
					if g.skeleton.find_bone(bone) < 0:
						continue
					var p: Vector3 = g.bone_world_transform(bone).origin
					var gap: float = p.distance_to(BodyCapsules.closest_on_segment(p, axis["a"], axis["b"])) - float(axis["r"]) - FINGER
					nearest = minf(nearest, absf(gap))
					if verbose:
						print("   %s %s %s: %+.0f mm" % [slug, grip.describe(), bone, gap * 1000.0])
					if gap < -INSIDE:
						inside.append("%s %.0f mm in" % [bone, -gap * 1000.0])
			var key := "%s: %s %s" % [slug, grip.gripper_id, grip.hand.to_lower()]
			check_grip(inside.is_empty(), key, "%s: %s — no finger through %s%s" % [slug, grip.describe(), axis["what"],
				"" if inside.is_empty() else " — " + ", ".join(inside)])
			check_grip(nearest <= OUTSIDE, key, "%s: %s — the hand is on %s (nearest finger %.0f mm off)" % [slug, grip.describe(), axis["what"], nearest * 1000.0])
	for key: String in OUTSTANDING:
		if not seen.has(key):
			check(false, "%s is listed as outstanding (%s) and does not happen: drop it from OUTSTANDING" % [key, OUTSTANDING[key]])
	print("RESULT %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


## The axis of whatever `grip` holds, with its radius there and a name for the message.
func _held_axis(grip: Grip) -> Dictionary:
	if grip.target.kind == GripTarget.Kind.WEAPON:
		var w := scene.get_weapon(grip.target.weapon_id)
		if w == null:
			return {}
		return {"a": w.anchor_transform(0.0).origin, "b": w.anchor_transform(1.0).origin, "r": w.shaft_half(), "what": w.weapon_id}
	var t := scene.get_character(grip.target.character_id)
	if t == null:
		return {}
	var bone: String = grip.target.bone_name
	var a: Vector3 = t.bone_world_transform(bone).origin
	var kids := t.skeleton.get_bone_children(t.skeleton.find_bone(bone))
	var b: Vector3 = a + t.bone_world_transform(bone).basis.y * 0.2
	if kids.size() > 0:
		b = t.bone_world_transform(t.skeleton.get_bone_name(kids[0])).origin
	var palm: Vector3 = scene.get_character(grip.gripper_id).bone_world_transform(grip.hand + "Hand").origin
	var along: float = clampf((palm - a).dot(b - a) / maxf((b - a).length_squared(), 1e-9), 0.0, 1.0)
	return {"a": a, "b": b, "r": t.skin_radius(bone, along), "what": "%s's %s" % [t.character_id, bone]}


func _files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".json"):
			out.append(f)
	out.sort()
	return out
