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
python3 tools/generate_mannequin.py -- "$PWD/assets/characters/mannequin.glb"
```

What it does: creates the default (gender-neutral, average) MakeHuman body at metre scale with feet
on the ground, adds the Mixamo-layout skeleton with finger bones and skin weights, deletes MakeHuman's
invisible helper geometry, renames bones to Godot humanoid names, assigns one flat material and exports
a GLB with skins. Body proportions can be changed through `macro_detail_dict` in `create_human`.
