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

What it does: creates the default (gender-neutral, average) MakeHuman body at metre scale with feet
on the ground, adds the Mixamo-layout skeleton with finger bones and skin weights, deletes MakeHuman's
invisible helper geometry, adds the eyes, eyebrows, eyelashes and five hair styles as proxies
weighted from the body (before the bones are renamed, since weights are copied by bone name),
renames bones to Godot humanoid names, assigns one flat material and exports
a GLB with skins. Body proportions can be changed through `macro_detail_dict` in `create_human`.

## Technique tools

- `technique.sh` + `build_technique.gd` — build a technique script (`techniques/*.json`) into
  poses, a sequence, stills, a contact sheet and an MP4; see `docs/technique-scripts.md`.
- `video_frames.sh` — a video as time-stamped contact sheets to read; see
  `docs/video-to-technique.md`.
