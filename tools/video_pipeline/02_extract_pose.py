#!/usr/bin/env python3
"""
Step 2: Screenshots -> raw keypoint JSON (MediaPipe Pose)

MediaPipe Pose tracks ONE person per pass. For a two-person technique
photo, tell it where each person roughly is in the frame with --bbox,
and it will crop to that region before running pose detection. This is
the standard workaround for MediaPipe's single-person limitation and
works well as long as the two people don't fully overlap in the crop.

Usage (single person, whole frame):
    python3 02_extract_pose.py frames/katatedori_ikkyo landmarks.json

Usage (two people, roughly left/right of frame):
    python3 02_extract_pose.py frames/katatedori_ikkyo landmarks.json \\
        --bbox tori=0.0,0.0,0.55,1.0 \\
        --bbox uke=0.45,0.0,1.0,1.0

--bbox values are fractions of image width/height: x1,y1,x2,y2 (top-left
to bottom-right, 0-1). Re-check/adjust per technique since people move
around the frame — a fixed box works for a static demo shot, less well
for a fast-moving sequence. For sequences, crop generously; MediaPipe
just needs the person mostly inside the box.

*** DO NOT label boxes "tori"/"uke" by screen position (e.g. "left = tori")
without checking the footage first. Screen position is not role. Confirmed
the hard way on real footage: the label needs to track WHO INITIATES THE
GRAB/ATTACK (= uke, per Aikido convention nage/tori performs, uke attacks),
not which side of frame someone starts on. Watch the approach/grip moment
once before assigning box labels, and re-check per repetition if partners
swap roles between reps (very common in kihon practice — the person who
was uke in rep 1 is often tori in rep 2). Getting this backwards silently
mislabels every joint-angle and grip field in the output with no error or
warning — it looks exactly as valid as correct data. ***

Output: one JSON record per (frame, person) with:
  - the 33 MediaPipe landmarks (image-space x,y and metric world x,y,z)
  - visibility score per landmark (low visibility = likely occluded,
    e.g. a gripped hand tucked behind the other person's arm)
  - a small set of derived joint angles (elbow, knee, shoulder, hip)
    as a convenience starting point for Godot bone rotations

This is NOT hand/finger tracking and does NOT know who is gripping
what — that part still needs a human eye. See 03_build_pose_json.py.
"""
import argparse
import json
import math
import sys
from pathlib import Path

import cv2
import mediapipe as mp

mp_pose = mp.solutions.pose

LANDMARK_NAMES = [lm.name.lower() for lm in mp_pose.PoseLandmark]


def parse_bbox(spec: str):
    # "label=x1,y1,x2,y2"
    label, coords = spec.split("=")
    x1, y1, x2, y2 = (float(v) for v in coords.split(","))
    return label, (x1, y1, x2, y2)


def angle_between(a, b, c):
    """Angle at point b, formed by points a-b-c, in degrees. Points are (x,y,z)."""
    v1 = [a[i] - b[i] for i in range(3)]
    v2 = [c[i] - b[i] for i in range(3)]
    dot = sum(v1[i] * v2[i] for i in range(3))
    n1 = math.sqrt(sum(v1[i] ** 2 for i in range(3)))
    n2 = math.sqrt(sum(v2[i] ** 2 for i in range(3)))
    if n1 == 0 or n2 == 0:
        return None
    cos_angle = max(-1.0, min(1.0, dot / (n1 * n2)))
    return math.degrees(math.acos(cos_angle))


def derived_angles(world_lm: dict):
    """A handful of joint angles useful as a first pass for Godot bone rotation."""
    def pt(name):
        lm = world_lm.get(name)
        return (lm["x"], lm["y"], lm["z"]) if lm else None

    pairs = {
        "left_elbow": ("left_shoulder", "left_elbow", "left_wrist"),
        "right_elbow": ("right_shoulder", "right_elbow", "right_wrist"),
        "left_shoulder": ("left_hip", "left_shoulder", "left_elbow"),
        "right_shoulder": ("right_hip", "right_shoulder", "right_elbow"),
        "left_knee": ("left_hip", "left_knee", "left_ankle"),
        "right_knee": ("right_hip", "right_knee", "right_ankle"),
        "left_hip": ("left_shoulder", "left_hip", "left_knee"),
        "right_hip": ("right_shoulder", "right_hip", "right_knee"),
    }
    out = {}
    for joint, (a_name, b_name, c_name) in pairs.items():
        a, b, c = pt(a_name), pt(b_name), pt(c_name)
        if a and b and c:
            out[joint] = round(angle_between(a, b, c), 1)
    return out


def process_frame(pose_models_by_conf, image, bbox=None):
    """Try detection at the default confidence first, then fall back to progressively
    lower thresholds if nothing is found. A clearly-visible person that the default
    threshold misses is a real, recoverable case (confirmed on real footage — an
    unusual overhead-arm pose was missed at 0.4 but found cleanly at 0.2), not
    something to just give up on."""
    h, w = image.shape[:2]
    if bbox:
        x1, y1, x2, y2 = bbox
        px1, py1, px2, py2 = int(x1 * w), int(y1 * h), int(x2 * w), int(y2 * h)
        crop = image[py1:py2, px1:px2]
    else:
        crop = image
        px1, py1 = 0, 0

    if crop.size == 0:
        return None

    rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
    result = None
    used_confidence = None
    for conf, pose_model in pose_models_by_conf:
        result = pose_model.process(rgb)
        if result.pose_landmarks:
            used_confidence = conf
            break
    if not result or not result.pose_landmarks:
        return None

    ch, cw = crop.shape[:2]
    image_lm = {}
    for name, lm in zip(LANDMARK_NAMES, result.pose_landmarks.landmark):
        # map back to full-image fractional coordinates
        abs_x = (px1 + lm.x * cw) / w
        abs_y = (py1 + lm.y * ch) / h
        image_lm[name] = {
            "x": round(abs_x, 4), "y": round(abs_y, 4),
            "visibility": round(lm.visibility, 3),
        }

    world_lm = {}
    if result.pose_world_landmarks:
        for name, lm in zip(LANDMARK_NAMES, result.pose_world_landmarks.landmark):
            world_lm[name] = {
                "x": round(lm.x, 4), "y": round(lm.y, 4), "z": round(lm.z, 4),
                "visibility": round(lm.visibility, 3),
            }

    return {
        "image_landmarks": image_lm,
        "world_landmarks": world_lm,
        "joint_angles_deg": derived_angles(world_lm),
        "detection_confidence_used": used_confidence,
        "detection_note": (
            None if used_confidence == pose_models_by_conf[0][0]
            else f"NOTE: default confidence (0.4) missed this person; recovered at "
                 f"{used_confidence}. Lower-confidence detections are somewhat more likely "
                 f"to have minor landmark inaccuracies -- worth a slightly closer look in Godot."
        ),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("frames_dir")
    parser.add_argument("output_json")
    parser.add_argument("--bbox", action="append", default=[],
                         help="label=x1,y1,x2,y2 (fractions 0-1). Repeatable, one per person.")
    args = parser.parse_args()

    frames_dir = Path(args.frames_dir)
    frame_paths = sorted(frames_dir.glob("frame_*.jpg"))
    if not frame_paths:
        sys.exit(f"No frame_*.jpg files found in {frames_dir} — run 01_extract_frames.py first.")

    bboxes = dict(parse_bbox(s) for s in args.bbox) if args.bbox else {"person": None}

    results = []
    # model_complexity=1 ("full") ships inside the mediapipe pip package.
    # complexity 0 ("lite") and 2 ("heavy") try to download extra weights
    # from storage.googleapis.com at first use, which this sandbox can't
    # reach — stick with 1 unless that changes.
    # Fallback chain: try the normal 0.4 confidence first, then retry at lower
    # thresholds for anyone still undetected -- confirmed on real footage that
    # this recovers genuinely-visible people the default threshold missed.
    confidences = [0.4, 0.25, 0.15]
    pose_models = [
        (c, mp_pose.Pose(static_image_mode=True, model_complexity=1,
                          enable_segmentation=False, min_detection_confidence=c))
        for c in confidences
    ]
    try:
        for frame_path in frame_paths:
            image = cv2.imread(str(frame_path))
            if image is None:
                continue
            frame_record = {"frame": frame_path.name, "people": {}}
            for label, bbox in bboxes.items():
                data = process_frame(pose_models, image, bbox)
                if data:
                    frame_record["people"][label] = data
                else:
                    frame_record["people"][label] = None
            results.append(frame_record)
    finally:
        for _, m in pose_models:
            m.close()

    Path(args.output_json).write_text(json.dumps(results, indent=2))
    detected = sum(1 for r in results for p in r["people"].values() if p)
    print(f"Processed {len(frame_paths)} frames, {len(bboxes)} person(s)/frame "
          f"-> {detected} person-detections. Wrote {args.output_json}")


if __name__ == "__main__":
    main()
