class_name Sequence
extends RefCounted
## A technique as an ordered list of saved poses with timings (spec §5.5, §5.6).
##
## steps: [{pose: slug, transition: seconds to blend into this step from the previous one,
##          hold: seconds to stay on it}]. The first step's transition is ignored.

const FORMAT := 1
const MIN_STEPS := 2
const MAX_STEPS := 5
const DEFAULT_PHASES := ["Grepp", "Kuzushi", "Kake"]

var name: String = ""
var camera: String = "Side"       ## "Front" | "Side" | "per_pose"
var steps: Array = []


static func new_default(technique: String) -> Sequence:
	var seq := Sequence.new()
	seq.name = technique
	for i in DEFAULT_PHASES.size():
		seq.steps.append({
			"pose": PoseFile.slugify("%s %s" % [technique, DEFAULT_PHASES[i]]),
			"transition": 0.0 if i == 0 else 0.6,
			"hold": 0.5 if i < DEFAULT_PHASES.size() - 1 else 1.0,
		})
	return seq


func slug() -> String:
	return PoseFile.slugify(name)


func duration() -> float:
	var total := 0.0
	for i in steps.size():
		total += float(steps[i].get("hold", 0.0))
		if i > 0:
			total += float(steps[i].get("transition", 0.0))
	return total


## Where the timeline is at `time`: {"from": step index, "to": step index, "u": 0..1 eased}.
## During a hold, from == to and u == 0. Times past the end stay on the last step.
func state_at(time: float) -> Dictionary:
	var t := maxf(time, 0.0)
	for i in steps.size():
		if i > 0:
			var trans := float(steps[i].get("transition", 0.0))
			if t < trans:
				var raw := t / trans if trans > 0.0 else 1.0
				return {"from": i - 1, "to": i, "u": smoothstep(0.0, 1.0, raw), "raw": raw}
			t -= trans
		var hold := float(steps[i].get("hold", 0.0))
		if t < hold or i == steps.size() - 1:
			return {"from": i, "to": i, "u": 0.0, "raw": 0.0}
		t -= hold
	return {"from": steps.size() - 1, "to": steps.size() - 1, "u": 0.0, "raw": 0.0}


## Time at which step `i` is fully reached (end of its transition).
func step_start(i: int) -> float:
	var t := 0.0
	for k in range(0, i + 1):
		if k > 0:
			t += float(steps[k].get("transition", 0.0))
		if k < i:
			t += float(steps[k].get("hold", 0.0))
	return t


func to_dict() -> Dictionary:
	return {"format": FORMAT, "name": name, "camera": camera, "steps": steps.duplicate(true)}


static func from_dict(d: Dictionary) -> Sequence:
	var seq := Sequence.new()
	seq.name = d.get("name", "")
	seq.camera = d.get("camera", "Side")
	seq.steps = d.get("steps", []).duplicate(true)
	return seq


static func sequence_path(dir: String, seq_name: String) -> String:
	return dir.path_join(PoseFile.slugify(seq_name) + ".json")


func save(path: String) -> Error:
	return PoseFile.save(path, to_dict())


static func load(path: String) -> Sequence:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary or int(parsed.get("format", 0)) != FORMAT:
		return null
	return Sequence.from_dict(parsed)
