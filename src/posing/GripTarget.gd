class_name GripTarget
extends RefCounted
## What a hand is attached to: a bone on a character, or (from M3W) a point along a weapon.
##
## Everything downstream asks only for world_transform(), so adding weapons does not touch the
## grip logic, the dependency graph, saving or interpolation.

enum Kind { BONE, WEAPON }

var kind: int = Kind.BONE
var character_id: String = ""   ## Kind.BONE
var bone_name: String = ""      ## Kind.BONE
var weapon_id: String = ""      ## Kind.WEAPON
var t: float = 0.0              ## Kind.WEAPON: 0 at the butt, 1 at the tip

var _scene: Node                ## PosingScene, for resolving ids


static func for_bone(scene: Node, character_id_: String, bone: String) -> GripTarget:
	var target := GripTarget.new()
	target.kind = Kind.BONE
	target.character_id = character_id_
	target.bone_name = bone
	target._scene = scene
	return target


static func for_weapon(scene: Node, weapon_id_: String, along: float) -> GripTarget:
	var target := GripTarget.new()
	target.kind = Kind.WEAPON
	target.weapon_id = weapon_id_
	target.t = along
	target._scene = scene
	return target


func bind(scene: Node) -> void:
	_scene = scene


## The character or object this target belongs to, used to order updates.
func owner_id() -> String:
	return character_id if kind == Kind.BONE else weapon_id


## Where the target is right now, in world space.
##
## This reads the character's cached solved pose rather than the skeleton directly. Inside the
## target's own `skeleton_updated` the cache has already been refreshed for this frame, so the value
## is live; outside it, it is the last posed value, which is what capturing a grip offset needs.
## Reading the skeleton directly outside that signal would return the *unposed* rest pose and put
## the captured offset out by however far the limb was posed.
func world_transform() -> Transform3D:
	match kind:
		Kind.BONE:
			var rig = _scene.get_character(character_id)
			return rig.bone_world_transform(bone_name) if rig else Transform3D()
		Kind.WEAPON:
			var weapon = _scene.get_weapon(weapon_id) if _scene.has_method("get_weapon") else null
			return weapon.anchor_transform(t) if weapon else Transform3D()
	return Transform3D()


func describe() -> String:
	if kind == Kind.BONE:
		var rig = _scene.get_character(character_id) if _scene else null
		var who: String = rig.display_name if rig else character_id
		return "%s %s" % [who, bone_name]
	return "%s at %.0f%%" % [weapon_id, t * 100.0]


func to_dict() -> Dictionary:
	if kind == Kind.BONE:
		return {"kind": "bone", "character": character_id, "bone": bone_name}
	return {"kind": "weapon", "weapon": weapon_id, "t": t}


static func from_dict(scene: Node, data: Dictionary) -> GripTarget:
	if data.get("kind", "bone") == "weapon":
		return GripTarget.for_weapon(scene, data["weapon"], data.get("t", 0.0))
	return GripTarget.for_bone(scene, data["character"], data["bone"])
