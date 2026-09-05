import bpy, sys, os, json
bpy.ops.preferences.addon_enable(module="bl_ext.user_default.mpfb")
from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.objectservice import ObjectService

out = sys.argv[sys.argv.index("--")+1]
bpy.ops.wm.read_factory_settings(use_empty=True)
basemesh = HumanService.create_human(mask_helpers=True, detailed_helpers=False, extra_vertex_groups=False, feet_on_ground=True, scale=0.1)
print("basemesh", basemesh.name, "verts", len(basemesh.data.vertices), "modifiers", [m.type for m in basemesh.modifiers])
arm = HumanService.add_builtin_rig(basemesh, "mixamo", import_weights=True)
print("armature", arm.name, "bones", len(arm.data.bones))

# Delete everything that is not in the 'body' vertex group (MakeHuman helper geometry + joint cubes).
body_idx = basemesh.vertex_groups['body'].index
keep = set()
for v in basemesh.data.vertices:
    for g in v.groups:
        if g.group == body_idx and g.weight > 0.5: keep.add(v.index); break
import bmesh
bm = bmesh.new(); bm.from_mesh(basemesh.data); bm.verts.ensure_lookup_table()
bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index not in keep], context='VERTS')
bm.to_mesh(basemesh.data); bm.free()
for m in list(basemesh.modifiers):
    if m.type == 'MASK': basemesh.modifiers.remove(m)
print("after helper removal verts", len(basemesh.data.vertices), "faces", len(basemesh.data.polygons))

# Rename bones mixamorig:* -> Godot SkeletonProfileHumanoid names
m = {"Hips":"Hips","Spine":"Spine","Spine1":"Chest","Spine2":"UpperChest","Neck":"Neck","Head":"Head","HeadTop_End":None,
     "Shoulder":"Shoulder","Arm":"UpperArm","ForeArm":"LowerArm","Hand":"Hand",
     "HandThumb1":"ThumbMetacarpal","HandThumb2":"ThumbProximal","HandThumb3":"ThumbDistal","HandThumb4":None,
     "HandIndex1":"IndexProximal","HandIndex2":"IndexIntermediate","HandIndex3":"IndexDistal","HandIndex4":None,
     "HandMiddle1":"MiddleProximal","HandMiddle2":"MiddleIntermediate","HandMiddle3":"MiddleDistal","HandMiddle4":None,
     "HandRing1":"RingProximal","HandRing2":"RingIntermediate","HandRing3":"RingDistal","HandRing4":None,
     "HandPinky1":"LittleProximal","HandPinky2":"LittleIntermediate","HandPinky3":"LittleDistal","HandPinky4":None,
     "UpLeg":"UpperLeg","Leg":"LowerLeg","Foot":"Foot","ToeBase":"Toes","Toe_End":None}
unmapped=[]
for b in arm.data.bones:
    n = b.name.replace("mixamorig:", "")
    side = ""
    for s in ("Left","Right"):
        if n.startswith(s): side, n = s, n[len(s):]
    if n in m and m[n]: b.name = side + m[n]
    elif n in m: pass  # end bones keep name
    else: unmapped.append(b.name)
print("unmapped bones:", unmapped)
print("bones:", [b.name for b in arm.data.bones])

# Simple flat material
mat = bpy.data.materials.new("Skin"); mat.use_nodes = True
mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.8,0.8,0.8,1)
basemesh.data.materials.clear(); basemesh.data.materials.append(mat)
basemesh.name = "Body"; arm.name = "Skeleton"

bpy.ops.object.select_all(action='DESELECT'); basemesh.select_set(True); arm.select_set(True)
bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_format='GLB', export_apply=True, export_skins=True, export_animations=False, export_yup=True, export_texcoords=True, export_normals=True, export_materials='EXPORT')
print("exported", out, os.path.getsize(out))
