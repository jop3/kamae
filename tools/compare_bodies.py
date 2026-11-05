#!/usr/bin/env python3
"""Compares two generated characters: how far the body's vertices and the skeleton's joints moved,
each body's height, width and depth, and (with --silhouette OUT.png) the two bodies' front and side
silhouettes drawn over each other.

    python3 tools/compare_bodies.py assets/characters/mannequin.glb new.glb [--silhouette out.png]

A body that moves its joints moves every committed pose with them (tools/README.md).
"""
import json, struct, sys
import numpy as np


def load(path):
    f = open(path, 'rb').read()
    n = struct.unpack('<I', f[12:16])[0]
    j = json.loads(f[20:20 + n])
    blob = f[20 + n + 8:]

    def acc(i):
        a = j['accessors'][i]
        bv = j['bufferViews'][a['bufferView']]
        width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
        dt = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}[a['componentType']]
        r = np.frombuffer(blob, dtype=dt, count=a['count'] * width, offset=bv.get('byteOffset', 0) + a.get('byteOffset', 0))
        return r.reshape(a['count'], width) if width > 1 else r

    out = {'meshes': {}, 'joints': {}}
    for m in j['meshes']:
        pr = m['primitives'][0]
        out['meshes'][m['name']] = (acc(pr['attributes']['POSITION']), acc(pr['indices']).reshape(-1, 3))
    sk = j['skins'][0]
    ibm = acc(sk['inverseBindMatrices']).reshape(-1, 4, 4)
    for node, m in zip(sk['joints'], ibm):
        out['joints'][j['nodes'][node]['name']] = np.linalg.inv(m.T)[:3, 3]
    return out


def main():
    a, b = load(sys.argv[1]), load(sys.argv[2])
    for name, (pa, _) in a['meshes'].items():
        if name in b['meshes'] and b['meshes'][name][0].shape == pa.shape:
            d = np.linalg.norm(pa - b['meshes'][name][0], axis=1)
            print('%-14s %6d vertices  moved up to %.4f m (mean %.4f)%s' % (name, len(pa), d.max(), d.mean(), '  identical' if d.max() == 0 else ''))
    moved = sorted(((n, np.linalg.norm(a['joints'][n] - b['joints'][n])) for n in a['joints'] if n in b['joints']), key=lambda x: -x[1])
    print('joints moved most:', ', '.join('%s %.3f m' % m for m in moved[:6]))
    for label, x in (('A', a), ('B', b)):
        p = x['meshes']['base'][0]
        print('%s: height %.3f m, span %.3f m, depth %.3f m' % (label, np.ptp(p[:, 1]), np.ptp(p[:, 0]), np.ptp(p[:, 2])))
    if '--silhouette' in sys.argv:
        from PIL import Image, ImageDraw
        out = sys.argv[sys.argv.index('--silhouette') + 1]
        W, H, sc = 420, 560, 320
        sheet = Image.new('RGB', (W * 2, H + 30), 'white')
        for v, ax in enumerate([0, 2]):
            img = Image.new('RGBA', (W, H), (255, 255, 255, 255))
            for k, x in enumerate((a, b)):
                p, tris = x['meshes']['base']
                layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
                draw = ImageDraw.Draw(layer)
                colour = (60, 60, 60, 110) if k == 0 else (200, 60, 40, 110)
                for t in tris:
                    draw.polygon([(W / 2 + p[i, ax] * sc, H - 10 - p[i, 1] * sc) for i in t], fill=colour)
                img = Image.alpha_composite(img, layer)
            sheet.paste(img.convert('RGB'), (v * W, 30))
        ImageDraw.Draw(sheet).text((10, 8), 'grey = %s, red = %s' % (sys.argv[1], sys.argv[2]), fill=(0, 0, 0))
        sheet.save(out)
        print('silhouettes:', out)


if __name__ == '__main__':
    main()
