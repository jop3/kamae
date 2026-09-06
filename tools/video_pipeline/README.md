# Video → pose JSON pipeline

Four scripts, run in order, per technique clip.

## Setup (one-time)

```
pip install "mediapipe==0.10.14" opencv-python-headless --break-system-packages
```

**Important version note:** mediapipe 0.10.3x+ dropped the legacy `solutions.pose`
API in favor of a Tasks API that downloads its model file from
`storage.googleapis.com` on first use. That domain isn't reachable from a
locked-down sandbox (and may not be reachable from a restricted work network
either). `0.10.14` still ships the old `solutions.pose` API with the
"full" model (`model_complexity=1`) bundled inside the pip package itself —
no network call at runtime. Only `model_complexity=0` ("lite") or `2`
("heavy") try to download extra weights; the scripts here are pinned to `1`
on purpose. If you upgrade mediapipe later, check this still holds.

`ffmpeg` is required for step 1 (already on most systems; `apt install ffmpeg`
if not).

## Usage

```bash
# 1. Video -> screenshots
python3 01_extract_frames.py katatedori_ikkyo.mp4 frames/katatedori_ikkyo --fps 4

# look through frames/katatedori_ikkyo/ and note which frame files look
# like the Grepp / Kuzushi / Kake moments

# 2. Screenshots -> raw keypoints (per person, via bounding boxes)
python3 02_extract_pose.py frames/katatedori_ikkyo landmarks.json \
    --bbox tori=0.0,0.0,0.55,1.0 \
    --bbox uke=0.45,0.0,1.0,1.0

# 3. Raw keypoints -> draft pose JSON, for the frames you picked
python3 03_build_pose_json.py landmarks.json katatedori_ikkyo_draft.json \
    --technique "Katatedori Ikkyo" \
    --frame frame_0006.jpg=Grepp \
    --frame frame_0014.jpg=Kuzushi \
    --frame frame_0022.jpg=Kake

# 4. Draft JSON -> actual Godot-schema sequence (per-bone direction vectors,
#    explicit grip_attachment fields, REAL transition timing from source fps)
python3 04_to_godot_sequence.py katatedori_ikkyo_draft.json katatedori_ikkyo_godot.json \
    --fps 6 --offset-seconds 0 \
    --source-frames Grepp=6 --source-frames Kuzushi=14 --source-frames Kake=22
```

Step 4's `--source-frames`/`--fps`/`--offset-seconds` are optional but worth
providing — without them, transition timing falls back to a guessed 0.6s
default instead of real elapsed time from the footage. Match the frame
numbers to whatever you passed `03_build_pose_json.py --frame` (the number
before `.jpg`), and `--fps`/`--offset-seconds` to whatever `01_extract_frames.py`
(or the raw ffmpeg command, if you extracted a sub-clip with `-ss`) actually used.

### What step 4 gives you that step 3 doesn't

- **Per-bone direction vectors** (upper arm, forearm, thigh, shin, spine,
  neck) computed from MediaPipe's 3D world landmarks, instead of just the
  single-joint angles in the draft. Still not literal Godot `bone.rotation`
  values — see the script's docstring for why (axis convention isn't
  verified against the Mixamo rig's bind pose) — but a stronger starting
  hint than a flat angle list.
- **Real transition timing** between poses, measured from the source
  video's fps/timestamps rather than a guessed default. Hold durations
  are still guessed (can't be derived from a still frame).
- **Explicit grip_attachment shape** matching what the spec's grip system
  actually needs (`from_character`/`from_bone`/`to_character`/`to_hand`/
  `active`), with a note that direction can flip mid-sequence (e.g.
  Shihonage: uke grips tori through Grepp/Kuzushi, tori grips uke by Kake)
  — that flip has to be a human decision per pose, not something inferred.

## What this pipeline gives you, and what it doesn't

**Gives you:** a rough numeric starting pose per figure per phase (joint
angles at elbow/shoulder/hip/knee, derived from MediaPipe's 3D world
landmarks) instead of starting from a blank T-pose in Godot every time.

**Does not give you:** grip location. Two bodies in contact with
overlapping hands is exactly the case markerless pose estimation struggles
with — this is a known open problem, not a gap in these scripts. Every
`grip_attachment` block in the output JSON is a placeholder
(`gripper`/`gripper_hand`/`grip_target`/`grip_bone`) for you to fill in by
eye, or to describe to Claude from a still frame so it can fill in a
best-guess draft for you to correct.

**Also does not give you:** finger poses. MediaPipe Pose tracks body
joints only, not individual fingers. If finger detail matters for a given
technique image, that stays fully manual in the Godot tool.

**Role labeling (`tori` vs `uke`) is not the same as screen position.**
Found this the hard way: labeling boxes "tori = left side, uke = right side"
by convenience, without checking who actually initiates the grab, silently
produces a fully self-consistent but backwards dataset — every joint angle
and grip field ends up swapped, and nothing in the output looks wrong. The
rule (per Aikido convention): whoever grabs/attacks is uke; whoever performs
the technique is tori/nage. Confirm this by watching the approach/grip
moment once per clip before assigning box labels, and re-check per
repetition — partners commonly swap uke/tori roles between reps in kihon
practice, so a label that's correct for rep 1 may be backwards for rep 2.
For paired-weapons kata (jo-to-jo, kumitachi) the correct roles are
**uchidachi** (打太刀, initiates the attack) and **shidachi** (仕太刀,
receives/executes the technique) — not tori/uke. The exchange within a
kata is back-and-forth (both partners strike and parry in turn), but the
uchidachi/shidachi assignment is still fixed for a given performance, so
this isn't a "no roles apply" situation, just a different role structure
than a grab-and-throw technique. Same rule applies: confirm who initiates
by watching the footage, don't assume from screen position.

**Per-person cropping (`--bbox`) is the practical workaround** for
MediaPipe Pose being single-person-per-pass — it's not true two-person
pose estimation, just "run single-person detection twice, once per rough
region." Works fine when tori and uke are roughly separated left/right or
front/back in frame; degrades when they're fully overlapping (which,
inconveniently, is often exactly the Kake moment of a throw). For those
frames, treat the pose numbers as a rougher starting guess and lean more
on manual correction in Godot.

## Files

- `01_extract_frames.py` — ffmpeg wrapper, video → JPEG frames
- `02_extract_pose.py` — MediaPipe Pose on frames (single- or per-person-crop), → landmarks.json
- `03_build_pose_json.py` — landmarks.json + your frame/phase picks → draft pose JSON
- `04_to_godot_sequence.py` — draft JSON → Godot-schema sequence (bone direction vectors, real timing, explicit grip fields)
