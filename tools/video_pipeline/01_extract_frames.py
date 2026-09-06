#!/usr/bin/env python3
"""
Step 1: Video -> screenshots

Pulls frames from an uploaded technique video at a fixed interval, so you
can pick out the Grepp / Kuzushi / Kake moments by eye afterwards.

Usage:
    python3 01_extract_frames.py <input_video> <output_dir> [--fps N]

Example:
    python3 01_extract_frames.py katatedori_ikkyo.mp4 frames/katatedori_ikkyo --fps 4

--fps controls how many frames per second of source video are kept.
Aikido techniques are fast (often under 2 seconds for the throw itself),
so 4-8 fps is usually enough to catch grip / kuzushi / kake without
producing hundreds of near-duplicate frames. Raise it for a technique
you want to inspect frame-by-frame.
"""
import argparse
import subprocess
import sys
from pathlib import Path


def extract_frames(input_video: str, output_dir: str, fps: float) -> list[Path]:
    in_path = Path(input_video)
    out_dir = Path(output_dir)
    if not in_path.exists():
        sys.exit(f"Input video not found: {in_path}")
    out_dir.mkdir(parents=True, exist_ok=True)

    pattern = str(out_dir / "frame_%04d.jpg")
    cmd = [
        "ffmpeg", "-y",
        "-i", str(in_path),
        "-vf", f"fps={fps}",
        "-q:v", "2",  # high JPEG quality
        pattern,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"ffmpeg failed:\n{result.stderr}")

    frames = sorted(out_dir.glob("frame_*.jpg"))
    print(f"Extracted {len(frames)} frames to {out_dir} (at {fps} fps)")
    return frames


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_video")
    parser.add_argument("output_dir")
    parser.add_argument("--fps", type=float, default=4.0)
    args = parser.parse_args()
    extract_frames(args.input_video, args.output_dir, args.fps)
