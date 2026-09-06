#!/usr/bin/env python3
"""
Step 3: Raw keypoint JSON -> draft Godot pose-library JSON

Takes the output of 02_extract_pose.py and reshapes it into the pose
schema the Godot posing tool expects (named pose, per-limb angle hints,
a grip_attachment block). This is a DRAFT — grip point, phase name, and
technique name are placeholders you fill in or correct; body angles are
MediaPipe's best guess and should be checked in the Godot tool, not
trusted as final numbers.

Usage:
    python3 03_build_pose_json.py landmarks.json pose_draft.json \\
        --technique "Katatedori Ikkyo" \\
        --frame frame_0006.jpg=Grepp \\
        --frame frame_0014.jpg=Kuzushi \\
        --frame frame_0022.jpg=Kake

Only frames you tag with --frame are turned into named poses (that's
how you pick the Grepp/Kuzushi/Kake moments out of the many frames
01_extract_frames.py produced). Everything else in landmarks.json is
ignored.
"""
import argparse
import json
from pathlib import Path


def build_pose(frame_record: dict, phase_name: str) -> dict:
    people = frame_record.get("people", {})
    pose = {
        "phase": phase_name,
        "figures": {},
        "grip_attachment": {
            "_TODO": "Fill in manually: which hand grips which bone on the "
                     "other figure. MediaPipe cannot see grips reliably "
                     "(occlusion). e.g. "
                     "{'gripper': 'tori', 'gripper_hand': 'right_wrist', "
                     "'grip_target': 'uke', 'grip_bone': 'left_wrist'}"
        },
    }
    for label, data in people.items():
        if not data:
            pose["figures"][label] = {"_TODO": "No person detected in this crop — check bbox or frame."}
            continue
        angles = data.get("joint_angles_deg", {})
        world = data.get("world_landmarks", {})
        low_confidence = [
            name for name, lm in world.items()
            if lm.get("visibility", 1.0) < 0.5
        ]
        pose["figures"][label] = {
            "joint_angles_deg": angles,
            "low_confidence_landmarks": low_confidence,
            "raw_world_landmarks": world,
        }
    return pose


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("landmarks_json")
    parser.add_argument("output_json")
    parser.add_argument("--technique", required=True, help="e.g. 'Katatedori Ikkyo'")
    parser.add_argument("--frame", action="append", default=[], required=True,
                         help="frame_filename.jpg=PhaseName, repeatable, e.g. frame_0006.jpg=Grepp")
    args = parser.parse_args()

    records = {r["frame"]: r for r in json.loads(Path(args.landmarks_json).read_text())}

    frame_phase = []
    for spec in args.frame:
        fname, phase = spec.split("=")
        frame_phase.append((fname, phase))

    sequence = []
    for fname, phase in frame_phase:
        record = records.get(fname)
        if not record:
            print(f"WARNING: {fname} not found in {args.landmarks_json}, skipping")
            continue
        sequence.append(build_pose(record, phase))

    out = {
        "technique": args.technique,
        "source": "draft generated from MediaPipe Pose — verify every "
                   "angle and fill in every grip_attachment in the Godot tool "
                   "before treating this as final.",
        "sequence": sequence,
    }
    Path(args.output_json).write_text(json.dumps(out, indent=2))
    print(f"Wrote {len(sequence)}-pose draft sequence to {args.output_json}")


if __name__ == "__main__":
    main()
