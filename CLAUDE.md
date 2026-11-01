# Kamae — notes for Claude

Kamae illustrates aikido techniques with posable, realistic human figures (Godot 4.6). Read
`docs/handoff.md` for where the work stands; this file is how to *use* it.

## Setup in a fresh session

```sh
curl -sSL -o /tmp/godot.zip https://github.com/godotengine/godot-builds/releases/download/4.6-stable/Godot_v4.6-stable_linux.x86_64.zip
unzip -o /tmp/godot.zip -d /tmp && export GODOT=/tmp/Godot_v4.6-stable_linux.x86_64
$GODOT --headless --import >/dev/null 2>&1      # once, before anything else
```

`xvfb-run` and `ffmpeg` are needed for stills and video (both present on the agent machines).

## Illustrating a technique someone asks for

1. Write `techniques/<slug>.json` — the reference is `docs/technique-scripts.md`, the examples
   are `techniques/*.json`. Start from an attack in `data/attacks.json`; place everything
   after it relative to Uke; one phase per moment a handout would show. `"approach": "static"`
   or `"moving"` on the `attack` move has Uke come in (kamae, the step, the hand raised or
   reaching; walked in from ~2.5 m) before the attack's own pose — `techniques/attack_*.json`
   are every attack that way, and `docs/attacks.md` ("In motion") is how an attack's stages
   are written.
2. `tools/technique.sh techniques/<slug>.json --no-video` (≈40 s). Read
   `techniques/build/<slug>/contact_sheet.png` and the problems printed per phase. Fix, rebuild.
   `motion.txt` and `floor.txt` in the build list the video frames where a body is implausible
   or anything of it is under the mat; `smooth.txt` scores how smoothly it moves
   (`tests/check_smooth.gd`: jerk, frozen frames, joints that flip, keyframes shown as saved).
3. When it reads right, build without `--no-video` for `techniques/build/<slug>/<slug>.mp4`
   (≈2–4 min). Send the user the contact sheet, the stills they want and the MP4.
4. Commit the script (the build directory is not committed). To make it part of the tool's
   library, copy its poses and sequence into `poses/` and `sequences/` — but then
   `tests/check_anatomy.gd` and `tests/check_motion.gd` judge it too.

`tools/build_all.sh` rebuilds every script (about 3–4 minutes each with video) and
`python3 tools/gallery.py` makes the browsable page of all of them (`techniques/build/gallery/`),
the falls (`techniques/ukemi_*.json`, Uke on his own) first.

Things learned the hard way, all in `docs/technique-scripts.md`: use `where` instead of guessing
from a camera; give a script a `view` that shows the key moment; `refit` a grip after the held
arm turns; pins rest the hands (`hand` … `to`), never `grab`; for a backward fall Uke faces the
way he falls from. A fall is phases of `ukemi` with rising `t` (0.35, then 0.7–0.75); the pose
remembers the fall, and the video between its phases follows the fall's own course on the mat.

Conventions that are easy to get wrong: directions are `[right, up, forward]` in the figure's
own frame; turns are positive toward the figure's **left** (counter-clockwise from above);
`tori`/`uke1` are the default ids; Tori wears a hakama by default, Uke does not.

## From a video

`docs/video-to-technique.md`. In short: `tools/video_frames.sh clip.mp4 OUT 2` and read the
sheets; pick a repetition and read it at 6 fps; write the script with a `ref` time per phase;
`REF_VIDEO=clip.mp4 tools/technique.sh … --no-video` and compare
`compare_with_video.png`. Keep uploaded clips out of the repository.

## Tests

Test what you changed, not everything: run the test files and checks that cover the code you
touched, alone — `$GODOT --headless -s tests/<name>.gd` (seconds to a few minutes), and
`MOTION_SEQ=<slug>` / `FLOOR_SEQ=<slug>` to check one sequence. The full
`GODOT=$GODOT tests/run.sh` takes about an hour on the agent machines (`RENDER_ACCEPTANCE=0`
halves it); run it only when asked. Rendered stills are compared with `tests/golden/`; refresh deliberately
with `UPDATE_GOLDEN=1` after a change that is meant to change the look, and look at them first.
The `OUTSTANDING` lists in `check_anatomy.gd`/`check_motion.gd` may only shrink.

## The character

`assets/characters/mannequin.glb` is generated (`tools/generate_mannequin.py`, see
`tools/README.md`): the MakeHuman body and rig plus eyes, brows, lashes and five hair styles.
Textures are in `assets/characters/textures/`; `CharacterRig.set_appearance()` picks skin, hair
and eyes per character, `Palette.APPEARANCES` the defaults. The body mesh and skeleton must stay
byte-identical across regenerations, or every committed pose moves.
