#!/usr/bin/env python3
"""
Step 4: Draft pose JSON -> Godot-schema technique sequence

The Godot build spec (godot_posing_machine_spec.md, section 5.5) defines a
pose as: full bone-rotation state for both skeletons + grip attachments +
optional camera, and a sequence as a named ordered list of poses each with
a transition/hold duration. 03_build_pose_json.py's draft output is flatter
than that (a handful of joint angles, no explicit bone hierarchy, no real
timing). This script closes some of that gap:

  - Computes a direction vector for each major bone segment (upper arm,
    forearm, thigh, shin, spine, neck) from MediaPipe's world landmarks,
    instead of just the single-joint angles used in the draft.
  - Computes REAL transition durations between poses from the source
    video's fps and each frame's position, when you provide that info
    via --fps/--offset — replacing guessed default timings with actual
    elapsed time from the footage.
  - Writes grip_attachment in the explicit
    {from_character, from_bone, to_character, to_hand, active} shape the
    spec's grip system needs, instead of a free-text note.

IMPORTANT — what this does NOT do:
  - It does NOT produce literal Godot bone.rotation values (Euler/quaternion
    in a specific rig's local bone space). MediaPipe's world-landmark axes
    are not verified to match the Mixamo rig's bind-pose bone axes, and
    doing that conversion correctly needs the actual rig file (bone rest
    orientations), not just landmark positions. What you get instead is a
    normalized direction vector per bone segment ("this forearm points
    roughly this way in world space") -- a strong hint for hand-posing in
    Godot, not a drop-in value. Whoever wires this into the Godot importer
    (Claude Code, most likely) will need to do the actual rig-space
    conversion, ideally by matching these direction vectors against known
    rest-pose bone directions for the specific Mixamo skeleton in use.
  - Finger curls: not available. MediaPipe Pose doesn't track fingers.
  - Hold durations (how long a pose is held once reached, as opposed to
    the transition into it): can't be derived from a single still frame.
    Left as an estimated default (0.4s) with a flag, not real data.

Usage:
    python3 04_to_godot_sequence.py draft_pose.json godot_sequence.json \\
        --fps 6 --offset-seconds 0
"""
import argparse
import json
from pathlib import Path

BONE_SEGMENTS = {
    "upper_arm_L": ("left_shoulder", "left_elbow"),
    "forearm_L": ("left_elbow", "left_wrist"),
    "upper_arm_R": ("right_shoulder", "right_elbow"),
    "forearm_R": ("right_elbow", "right_wrist"),
    "thigh_L": ("left_hip", "left_knee"),
    "shin_L": ("left_knee", "left_ankle"),
    "thigh_R": ("right_hip", "right_knee"),
    "shin_R": ("right_knee", "right_ankle"),
}

DEFAULT_HOLD_S = 0.4  # can't derive from a still frame -- flagged as estimate, not measured


def normalize(v):
    length = sum(c * c for c in v) ** 0.5
    if length < 1e-6:
        return None
    return [round(c / length, 4) for c in v]


def vec(a, b):
    return [b[i] - a[i] for i in range(3)]


def midpoint(a, b):
    return [(a[i] + b[i]) / 2 for i in range(3)]


def bone_directions(world_landmarks: dict):
    def pt(name):
        lm = world_landmarks.get(name)
        return (lm["x"], lm["y"], lm["z"]) if lm else None

    out = {}
    for bone, (a_name, b_name) in BONE_SEGMENTS.items():
        a, b = pt(a_name), pt(b_name)
        if a and b:
            d = normalize(vec(a, b))
            if d:
                out[bone] = d

    # spine: mid-hip -> mid-shoulder ; neck: mid-shoulder -> nose
    lh, rh = pt("left_hip"), pt("right_hip")
    ls, rs = pt("left_shoulder"), pt("right_shoulder")
    nose = pt("nose")
    if lh and rh and ls and rs:
        mid_hip = midpoint(lh, rh)
        mid_shoulder = midpoint(ls, rs)
        d = normalize(vec(mid_hip, mid_shoulder))
        if d:
            out["spine"] = d
        if nose:
            d2 = normalize(vec(mid_shoulder, nose))
            if d2:
                out["neck"] = d2
    return out


def convert_figure(fig: dict):
    if "raw_world_landmarks" not in fig:
        return {
            "bone_directions": None,
            "note": fig.get("description") or fig.get("_TODO") or "no landmark data available (manual/missing frame)",
            "source": fig.get("source", "unknown"),
        }
    return {
        "bone_directions": bone_directions(fig["raw_world_landmarks"]),
        "bone_direction_axis_note": (
            "Vectors are in MediaPipe's world-landmark frame (origin ~hip center, "
            "units arbitrary/metric-ish). NOT verified against the Mixamo rig's bind-pose "
            "axes -- treat as directional hints for hand-posing, not literal bone.rotation "
            "values. See script docstring."
        ),
        "low_confidence_landmarks": fig.get("low_confidence_landmarks", []),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("draft_json")
    parser.add_argument("output_json")
    parser.add_argument("--fps", type=float, default=None,
                         help="fps used when extracting the source frames, for real transition timing")
    parser.add_argument("--offset-seconds", type=float, default=0.0,
                         help="video timestamp (seconds) that frame_0001 corresponds to, if extraction started mid-clip")
    parser.add_argument("--source-frames", action="append", default=[],
                         help="phase=frame_number, e.g. Grepp=32, repeatable, in the same order as --frame was "
                              "given to 03_build_pose_json.py. Needed only if you want real transition timing.")
    args = parser.parse_args()

    d = json.loads(Path(args.draft_json).read_text())

    frame_numbers = {}
    for spec in args.source_frames:
        phase, num = spec.split("=")
        frame_numbers[phase] = int(num)

    def frame_time(n):
        if args.fps is None:
            return None
        return round(args.offset_seconds + (n - 1) / args.fps, 3)

    sequence = []
    prev_time = None
    for pose in d["sequence"]:
        phase = pose["phase"]
        entry = {
            "pose_name": phase,
            "figures": {label: convert_figure(fig) for label, fig in pose["figures"].items()},
        }

        t = frame_time(frame_numbers[phase]) if phase in frame_numbers else None
        if t is not None and prev_time is not None:
            entry["transition_duration_s"] = round(t - prev_time, 3)
            entry["transition_duration_source"] = "measured from source video fps/timestamps"
        else:
            entry["transition_duration_s"] = 0.6
            entry["transition_duration_source"] = "ESTIMATED DEFAULT -- not measured, no --source-frames/--fps given"
        entry["hold_duration_s"] = DEFAULT_HOLD_S
        entry["hold_duration_source"] = "ESTIMATED DEFAULT -- cannot be derived from a still frame"

        # carry over grip info if present, reshaped toward the spec's explicit fields where we can
        grip = pose.get("grip_attachment", {})
        entry["grip_attachment"] = {
            "active": bool(grip) and "_TODO" not in grip,
            "raw": grip,
            "schema_note": (
                "Spec wants {from_character, from_bone, to_character, to_hand, active} explicitly, "
                "and notes the attachment direction can flip mid-sequence (e.g. Shihonage: uke grips "
                "tori in Grepp/Kuzushi, tori grips uke's wrist in Kake). The 'raw' field above has "
                "whatever this pipeline could determine in free-text form -- turning it into the exact "
                "four fields needs a human decision per pose, not just reformatting."
            ),
        }

        if t is not None:
            prev_time = t
        sequence.append(entry)

    out = {
        "technique": d.get("technique"),
        "terminology_note": d.get("terminology_note"),
        "role_correction_note": d.get("role_correction_note"),
        "godot_spec_reference": "See godot_posing_machine_spec.md section 5.5 (pose/sequence data model) and 5.3 (grip attachment)",
        "sequence": sequence,
    }
    Path(args.output_json).write_text(json.dumps(out, indent=2))
    print(f"Wrote {len(sequence)}-pose Godot-schema sequence to {args.output_json}")


if __name__ == "__main__":
    main()
