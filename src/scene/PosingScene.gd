class_name PosingScene
extends Node3D
## Owns the list of characters in the scene. 2–5 characters, each a CharacterRig.

signal characters_changed

const MAX_CHARACTERS := 5
const MIN_CHARACTERS := 1

var characters: Array[CharacterRig] = []


func add_character(id: String, display_name: String, role: String, color: Color = Color.TRANSPARENT) -> CharacterRig:
	assert(characters.size() < MAX_CHARACTERS, "At most %d characters" % MAX_CHARACTERS)
	assert(get_character(id) == null, "Duplicate character id %s" % id)
	var rig := CharacterRig.new()
	rig.name = id
	rig.character_id = id
	rig.display_name = display_name
	rig.role = role
	add_child(rig)
	rig.setup()
	rig.set_skin_color(color if color != Color.TRANSPARENT else Palette.color_for_index(characters.size()))
	characters.append(rig)
	characters_changed.emit()
	return rig


func remove_character(id: String) -> void:
	var rig := get_character(id)
	if rig == null:
		return
	characters.erase(rig)
	rig.queue_free()
	characters_changed.emit()


func get_character(id: String) -> CharacterRig:
	for c in characters:
		if c.character_id == id:
			return c
	return null


func next_free_id(prefix: String) -> String:
	var n := 1
	while get_character("%s%d" % [prefix, n]) != null:
		n += 1
	return "%s%d" % [prefix, n]


## Default two-person setup: Tori facing +Z, Uke one metre in front facing Tori.
func setup_default() -> void:
	var tori := add_character("tori", "Tori", "Tori")
	tori.position = Vector3(0, 0, -0.5)
	var uke := add_character("uke1", "Uke", "Uke")
	uke.position = Vector3(0, 0, 0.5)
	uke.rotation.y = PI


## Line from Tori to the primary Uke, used by camera presets. Falls back to world Z.
func tori_uke_axis() -> Dictionary:
	var tori: CharacterRig = null
	var uke: CharacterRig = null
	for c in characters:
		if c.role == "Tori" and tori == null:
			tori = c
		elif c.role == "Uke" and uke == null:
			uke = c
	var a := tori.global_position if tori else Vector3.ZERO
	var b := uke.global_position if uke else a + Vector3(0, 0, 1)
	return {"from": a, "to": b, "center": (a + b) * 0.5}
