import bpy, sys, os, json
bpy.ops.preferences.addon_enable(module="bl_ext.user_default.mpfb")
from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.objectservice import ObjectService

out = sys.argv[sys.argv.index("--")+1]
bpy.ops.wm.read_factory_settings(use_empty=True)
# detailed_helpers must stay True: MPFB fits the rig's bones to the helper geometry, and without it
# the arm and hand bones land up to 47 cm away from the body, so every arm pose tears the mesh.
# The helpers are excluded from the exported mesh by the Mask modifier, not by deleting vertices.
basemesh = HumanService.create_human(mask_helpers=True, detailed_helpers=True, extra_vertex_groups=False, feet_on_ground=True, scale=0.1)
print("basemesh", basemesh.name, "verts", len(basemesh.data.vertices), "modifiers", [m.type for m in basemesh.modifiers])
arm = HumanService.add_builtin_rig(basemesh, "mixamo", import_weights=True)
print("armature", arm.name, "bones", len(arm.data.bones))

# MakeHuman's helper geometry (clothes/joint cubes) is excluded by the Mask modifier MPFB sets up
# for the 'body' vertex group. Leave that modifier in place and let the glTF exporter apply it
# (export_apply=True): deleting the vertices by hand with bmesh detaches the skin weights from their
# vertices, which leaves finger weights on hip vertices and tears the mesh apart when a bone rotates.
print("mesh verts (before mask):", len(basemesh.data.vertices), "modifiers:", [m.type for m in basemesh.modifiers])

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

# Guard against broken skin weights: rotating one finger phalanx may only move vertices close to it.
import math
from mathutils import Quaternion
dg = bpy.context.evaluated_depsgraph_get()
before = [v.co.copy() for v in basemesh.evaluated_get(dg).to_mesh().vertices]
pb = arm.pose.bones["RightIndexProximal"]; pb.rotation_mode = 'QUATERNION'
pb.rotation_quaternion = Quaternion((0, 0, 1), math.radians(70))
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
after_co = [v.co.copy() for v in basemesh.evaluated_get(dg).to_mesh().vertices]
worst = max((a - b).length for a, b in zip(after_co, before))
pb.rotation_quaternion = Quaternion()
bpy.context.view_layer.update()
print("weight check: worst vertex displacement from a 70 deg finger bend = %.4f m" % worst)
body_idx = basemesh.vertex_groups["body"].index
body_co = [v.co for v in basemesh.data.vertices if any(g.group == body_idx and g.weight > 0.5 for g in v.groups)]
worst_fit = 0.0
worst_bone = ""
for bone in arm.data.bones:
    gap = min((bone.head_local - co).length for co in body_co)
    if gap > worst_fit:
        worst_fit, worst_bone = gap, bone.name
print("bone fit check: furthest bone from the body is %s at %.3f m" % (worst_bone, worst_fit))
# Joint centres sit inside the body, so a bone is allowed to be a little away from the nearest
# surface vertex; anything beyond ~10 cm means the rig was not fitted to this mesh.
assert worst_fit < 0.12, "rig is not fitted to the mesh: %s sits %.3f m away" % (worst_bone, worst_fit)
# A 70 deg bend of a ~7.5 cm finger sweeps the tip about 8.6 cm, so anything far beyond that means
# weights are attached to the wrong vertices.
assert worst < 0.12, "skin weights look wrong: one finger bend moves geometry by %.3f m" % worst

bpy.ops.object.select_all(action='DESELECT'); basemesh.select_set(True); arm.select_set(True)
bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_format='GLB', export_apply=True, export_skins=True, export_animations=False, export_yup=True, export_texcoords=True, export_normals=True, export_materials='EXPORT')
print("exported", out, os.path.getsize(out))
