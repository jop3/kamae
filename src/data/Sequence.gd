class_name Sequence
extends RefCounted
## A technique as an ordered list of saved poses with timings (spec §5.5, §5.6).
##
## steps: [{pose: slug, transition: seconds to blend into this step from the previous one,
##          hold: seconds to stay on it}]. The first step's transition is ignored.

const FORMAT := 1
const MIN_STEPS := 2
## The spec asked for 2-5 poses. A technique that ends in a fall needs more than five: the throw
## itself is four, and going down, over and back up is three more.
## Technique scripts route a movement through waypoints (a foot round the partner's foot, a
## body round an arm), each a step held for no time, so the limit is wider than the handout needs.
const MAX_STEPS := 16
const DEFAULT_PHASES := ["Grepp", "Kuzushi", "Kake"]

var name: String = ""
var camera: String = "Side"       ## "Front" | "Side" | "per_pose"
## An optional chosen view (CameraPresets.view): {"yaw": degrees swung from Side, "height": metres,
## "zoom": framing factor}. Set, it is what the video is filmed from and a third still per phase.
var view: Dictionary = {}
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
			# A step's own time (step_start, a sum of the same floats) is on the pose, not a
			# rounding error short of it in the transition.
			if t < trans - 1e-6:
				var raw := t / trans if trans > 0.0 else 1.0
				if t < 1e-6:
					raw = 0.0   # on the pose before, to the same rounding
				# Ease away from a pose only when the technique actually rests on it. A step held
				# for no time is a waypoint being passed through, and easing to a stop at every
				# one of them is what makes a sequence move in lurches.
				var rest_before := float(steps[i - 1].get("hold", 0.0)) > 0.0
				var rest_after := float(steps[i].get("hold", 0.0)) > 0.0
				return {"from": i - 1, "to": i, "u": ease_through(raw, rest_before, rest_after), "raw": raw}
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
	var d := {"format": FORMAT, "name": name, "camera": camera, "steps": steps.duplicate(true)}
	if not view.is_empty():
		d["view"] = view.duplicate()
	return d


static func from_dict(d: Dictionary) -> Sequence:
	var seq := Sequence.new()
	seq.name = d.get("name", "")
	seq.camera = d.get("camera", "Side")
	seq.view = d.get("view", {}) if d.get("view") is Dictionary else {}
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


## Eases `t` (0..1) into and out of rest. A cubic with zero slope at an end holds still there;
## with unit slope it passes through at speed. Both ends at rest is the smoothstep this used
## everywhere before waypoints existed.
static func ease_through(t: float, rest_at_start: bool, rest_at_end: bool) -> float:
	var m0 := 0.0 if rest_at_start else 1.0
	var m1 := 0.0 if rest_at_end else 1.0
	var t2 := t * t
	var t3 := t2 * t
	return (t3 - 2.0 * t2 + t) * m0 + (-2.0 * t3 + 3.0 * t2) + (t3 - t2) * m1


## The course a movement takes over its time `t` (0..1): from rest it starts and stops on the
## minimum-jerk profile people move on (10t³ − 15t⁴ + 6t⁵: no step in acceleration at either
## end, where the cubic above starts with one); through a waypoint it passes at its even speed.
## The quintic Hermite with zero acceleration at both ends and the end speeds 0 (rest) or 1.
## `settle` is the speed (as a share of the even speed) a movement still has as it reaches a pose
## it rests on, carried on past the pose and back by the player (SequencePlayer settle): hips that
## stop dead read as a machine.
static func ease_motion(t: float, rest_at_start: bool, rest_at_end: bool, settle := 0.0) -> float:
	t = clampf(t, 0.0, 1.0)
	var v0 := 0.0 if rest_at_start else 1.0
	var v1 := settle if rest_at_end else 1.0
	var t3 := t * t * t
	var t4 := t3 * t
	var t5 := t4 * t
	return (10.0 * t3 - 15.0 * t4 + 6.0 * t5) + v0 * (t - 6.0 * t3 + 8.0 * t4 - 3.0 * t5) \
		+ v1 * (-4.0 * t3 + 7.0 * t4 - 3.0 * t5)

