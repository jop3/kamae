# From a video to a technique

A technique video is turned into a technique script (`docs/technique-scripts.md`) by *reading* it:
looking at frames, naming the phases, and writing down where the feet go, what the hands hold and
how Uke moves. Pose estimation (MediaPipe, `tools/video_pipeline/`) helps where two people stand
apart and fails exactly where a technique happens — at contact, when one body hides the other —
so it is a supplement here, not the method.

## 1. Find the techniques in the clip

```sh
tools/video_frames.sh clip.mp4 /tmp/clip 2          # 2 frames/s, 20 per sheet, time-stamped
```

Read the sheets (`/tmp/clip/sheet_NN.jpg`). Title cards name the technique; black gaps and cuts
separate them (`ffmpeg -i clip.mp4 -vf blackdetect=d=0.3:pix_th=0.1 -an -f null -` lists the
gaps). Many clips repeat a technique several times (teacher first, then students, or tsuzuki
waza where Uke attacks again and again): pick the clearest repetition.

## 2. Read one repetition closely

```sh
tools/video_frames.sh clip.mp4 /tmp/rep 6 9.8 4.2 6 5   # 6 frames/s from 9.8 s for 4.2 s
```

Write down, with times:

- **The attack.** Which hand takes what (Uke's left on Tori's right wrist = gyaku hanmi
  katatedori), or which strike. This picks the catalogue entry (`docs/attacks.md`).
- **The phases**, each one a moment that would be a still in a handout: grip, entry (irimi),
  turn (tenkan), the raise or the cut, the moment of the throw, the fall, the pin.
- **Feet**, phase by phase: which foot steps where relative to Uke ("Tori's right foot beside
  Uke's left"), which foot is pivoted on and how far round, kneeling.
- **Hands**: what each holds, where a free hand is (at the face, on the elbow, extended).
- **Uke**: bent forward, leaning back, rising onto the toes, which way the fall goes and what
  kind of ukemi.
- **Who is Tori.** The one being grabbed and doing the throwing; in a clip where both wear
  hakama that is the only way to tell.

## 3. Write the script

One phase per moment, each with `"ref": <seconds>` — the time in the clip that phase shows.
`source` names the clip; the clip itself stays out of the repository unless its licence allows.

## 4. Build, compare, correct

```sh
REF_VIDEO=clip.mp4 tools/technique.sh techniques/<name>.json --no-video
```

`techniques/build/<slug>/compare_with_video.png` puts each phase's frame from the clip beside the
render. Look for: who is where on the mat, which way each faces, which foot is forward, how high
the hands are, how far Uke is bent. Fix the move that is wrong, rebuild (about 40 s), repeat;
then build without `--no-video` for the MP4.

Worked example: `techniques/katatedori_tenkan_kokyunage.json`, written from the teacher's
repetition (9.8–13.8 s) of "Aikido Tsuzuki Waza", Michael Winter und Schüler.

## Optional: landmarks

`tools/video_pipeline/` (MediaPipe 0.10.14, see its README) extracts 33 body landmarks per
person per frame and `src/data/PoseImport.gd` turns a draft into rough poses ("Import video
draft…" in the panel). It is worth running for phases where the two are apart — the approach,
a stance — to get joint angles a frame can't show by eye; for the contact phases, the script.
