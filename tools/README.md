# tools

## generate_mannequin.py

Regenerates `assets/characters/mannequin.glb` headlessly, without a Blender GUI.

```sh
pip install bpy==4.2.0            # Blender as a Python module (~520 MB), Python 3.11
# install MPFB 2.0.17 into the bpy user extensions repo once:
python3 - <<'PY'
import bpy, urllib.request
url = "https://extensions.blender.org/download/sha256:4f0a879d64a39bf646fbf5f53601ac678855da329d650617dca5737548239a87/add-on-mpfb-v2.0.17.zip"
urllib.request.urlretrieve(url, "mpfb.zip")
bpy.ops.extensions.package_install_files(filepath="mpfb.zip", repo="user_default", enable_on_install=True)
PY
# the MakeHuman CC0 system assets (eyes, brows, lashes, hair, skins) into MPFB's user data, once:
curl -sSL -o mh.zip http://files.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip
unzip -q mh.zip -d ~/.config/blender/4.2/extensions/.user/user_default/mpfb/data/
python3 tools/generate_mannequin.py -- "$PWD/assets/characters/mannequin.glb"
```

The body mesh and the skeleton must come out byte-identical to the committed file (every saved
pose depends on them); compare the Body mesh's accessors and the skin's inverse bind matrices
before committing a regenerated GLB. The textures in `assets/characters/textures/` are copied
from the same asset pack (skins as 2K JPEG, hair at 1K, eyes as RGBA PNG — the eye's cornea is
the transparent part of its image, and without the alpha the eyes render black).

What it does: creates a MakeHuman body (the `MACRO` sliders: a lean, average man) at metre scale with feet
on the ground, adds the Mixamo-layout skeleton with finger bones and skin weights, deletes MakeHuman's
invisible helper geometry, adds the eyes, eyebrows, eyelashes and five hair styles as proxies
weighted from the body (before the bones are renamed, since weights are copied by bone name),
renames bones to Godot humanoid names, assigns one flat material and exports
a GLB with skins. Body proportions can be changed through `macro_detail_dict` in `create_human`.

### Changing the body

The body's shape is MakeHuman's macro sliders, `MACRO` at the top of the generator (gender, age,
muscle, weight, proportions, height; 0.5 is the average). `--macro '{"weight": 0.3}'` tries
another value without editing the file:

```sh
python3 tools/generate_mannequin.py -- /tmp/try.glb --macro '{"muscle": 0.2, "weight": 0.2}'
python3 tools/compare_bodies.py assets/characters/mannequin.glb /tmp/try.glb --silhouette /tmp/try.png
```

`compare_bodies.py` says how far the vertices and the joints moved and draws the two silhouettes
over each other. A new body moves every committed pose with its joints, so after one:
`tools/fit_body_shapes.gd` for `Anatomy.SHAPES`; the eye centres in `Gaze` (`EYE_CENTRE`, `EYES`,
measured off the eye mesh); the kneeling hip heights in `Stance`; then the tests that judge the
library (`check_anatomy`, `check_grips`, `check_motion`), `tools/refit_grips.gd` for poses whose
grips land differently, and every golden. The body chosen on 2026-11-05 (gender 0.85, muscle
0.25, weight 0.2, height 0.40) did all of that.

## Technique tools

- `technique.sh` + `build_technique.gd` — build a technique script (`techniques/*.json`) into
  poses, a sequence, stills, a contact sheet and an MP4; see `docs/technique-scripts.md`.
- `video_frames.sh` — a video as time-stamped contact sheets to read; see
  `docs/video-to-technique.md`.
- `review_frames.sh <slug> [every | --at t1,t2]` — close-ups of a built technique *between* its
  keyframes, from four sides, framed tight on the two figures (`FOCUS=uke1.Head` for one part):
  the film's wide shot is too far away to show an elbow, a face or two bodies in contact.
  `techniques/build/<slug>/review/sheet_t<time>.png`.
- `relax_pose.gd` — runs the contact solve over saved poses and saves them again, as a technique
  script does before saving a pose.

## fit_body_shapes.gd

Prints `Anatomy.SHAPES`, the body's surface as capsules fitted to the mannequin's rest mesh (the
trunk as a capsule across the body per trunk bone, each limb's capsule on the middle of its
flesh). Run it after the body mesh changes and paste the table over the old one; `FIT_BANDS=1`
also prints how each limb tapers.
