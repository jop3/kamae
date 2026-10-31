#!/usr/bin/env python3
"""Makes a figure exported by tools/export_viewer.gd lighter for the web viewer.

Godot writes every texture as PNG: the skin, a photograph, comes out at 2.6 MB. Textures of opaque
materials are re-encoded as JPEG (the hair, lashes and brows are cut out by their alpha and stay
PNG). The cloth's normal maps, and the weave on cloth without UVs, are dropped: in Godot they are laid on triplanar, which glTF has no
form for, so on the mesh's own UVs they would only streak.

    python3 tools/slim_glb.py in.glb out.glb
"""
import io
import json
import struct
import sys

from PIL import Image

TINY_PNG = None


def tiny_png():
    global TINY_PNG
    if TINY_PNG is None:
        buf = io.BytesIO()
        Image.new("RGB", (1, 1), (128, 128, 255)).save(buf, "PNG")
        TINY_PNG = buf.getvalue()
    return TINY_PNG


def main(src, dst):
    data = open(src, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + jlen])
    bstart = 20 + jlen
    blen = struct.unpack("<I", data[bstart:bstart + 4])[0]
    binary = data[bstart + 8:bstart + 8 + blen]
    views = gltf["bufferViews"]
    textures = gltf.get("textures", [])
    images = gltf.get("images", [])

    def image_of(tex_ref):
        return textures[tex_ref["index"]]["source"]

    # The cloth carries no UVs (its weave is laid on triplanar in Godot): a texture there samples
    # one texel and drowns the cloth's colour, so those materials keep their colour only.
    no_uv = set()
    with_uv = set()
    for mesh in gltf.get("meshes", []):
        for prim in mesh["primitives"]:
            if "material" in prim:
                (with_uv if "TEXCOORD_0" in prim["attributes"] else no_uv).add(prim["material"])
    for i in no_uv - with_uv:
        m = gltf["materials"][i]
        m.get("pbrMetallicRoughness", {}).pop("baseColorTexture", None)
        m.pop("normalTexture", None)
    opaque, cutout, dropped = set(), set(), set()
    used = set()
    for m in gltf.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        if "baseColorTexture" in pbr:
            (cutout if m.get("alphaMode") in ("MASK", "BLEND") else opaque).add(image_of(pbr["baseColorTexture"]))
        if "normalTexture" in m:
            dropped.add(image_of(m.pop("normalTexture")))
    for m in gltf.get("materials", []):
        for ref in [m.get("pbrMetallicRoughness", {}).get("baseColorTexture"), m.get("normalTexture")]:
            if ref:
                used.add(image_of(ref))
    replace = {}
    for i, img in enumerate(images):
        if i not in used:
            dropped.add(i)
        view = img["bufferView"]
        raw = binary[views[view]["byteOffset"]:views[view]["byteOffset"] + views[view]["byteLength"]]
        if i in dropped and i not in opaque and i not in cutout:
            replace[view] = tiny_png()
            img["mimeType"] = "image/png"
        elif i in opaque and i not in cutout:
            buf = io.BytesIO()
            Image.open(io.BytesIO(raw)).convert("RGB").save(buf, "JPEG", quality=85, optimize=True)
            if len(buf.getvalue()) < len(raw):
                replace[view] = buf.getvalue()
                img["mimeType"] = "image/jpeg"
    out = bytearray()
    for i, v in enumerate(views):
        chunk = replace.get(i, binary[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]])
        while len(out) % 4:
            out.append(0)
        v["byteOffset"] = len(out)
        v["byteLength"] = len(chunk)
        out += chunk
    while len(out) % 4:
        out.append(0)
    gltf["buffers"][0]["byteLength"] = len(out)
    js = json.dumps(gltf, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    total = 12 + 8 + len(js) + 8 + len(out)
    with open(dst, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(out), 0x004E4942) + bytes(out))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
