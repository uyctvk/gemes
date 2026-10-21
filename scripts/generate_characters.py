#!/usr/bin/env python3
"""Build original, rigged village characters as glTF with Blender 4.x.

Run: blender -b --factory-startup --python scripts/generate_characters.py
Each visible part is modeled, assigned to an armature bone and exported as GLB.
No third-party character mesh, texture or trademark is used.
"""
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "game" / "assets" / "characters"
OUT.mkdir(parents=True, exist_ok=True)
RIG = None


def material(name, rgb, roughness=0.88, metallic=0.0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return m


def skin(obj, bone):
    obj.name = obj.name.replace(".", "_")
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    modifier = obj.modifiers.new("Articulated body", "ARMATURE")
    modifier.object = RIG
    obj.parent = RIG
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def oval(name, point, scale, mat, bone, detail=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=detail, ring_count=10, location=point)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.data.materials.append(mat)
    return skin(obj, bone)


def tapered(name, start, end, radius_a, radius_b, mat, bone, sides=14):
    vector = Vector(end) - Vector(start)
    bpy.ops.mesh.primitive_cone_add(
        vertices=sides, radius1=radius_a, radius2=radius_b,
        depth=vector.length, location=(Vector(start) + Vector(end)) / 2,
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = vector.to_track_quat("Z", "Y").to_euler()
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.data.materials.append(mat)
    return skin(obj, bone)


def cloth(name, rings, mat, bone, folds=8):
    vertices = []
    faces = []
    sides = 18
    for z, rx, ry in rings:
        for j in range(sides):
            angle = math.tau * j / sides
            fold = 1 + 0.035 * math.sin(angle * folds + z * 4)
            vertices.append((rx * math.cos(angle) * fold, ry * math.sin(angle) * fold, z))
    for k in range(len(rings) - 1):
        for j in range(sides):
            a = k * sides + j
            b = k * sides + (j + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    faces.append(tuple(reversed(tuple(range(sides)))))
    faces.append(tuple((len(rings)-1)*sides+j for j in range(sides)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return skin(obj, bone)


def armature():
    global RIG
    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    RIG = bpy.context.object
    RIG.name = "VillageHumanRig"
    bones = RIG.data.edit_bones
    root = bones[0]
    root.name = "Root"
    root.head = (0, 0, 0)
    root.tail = (0, 0, 1.0)
    parts = {
        "Torso": ("Root", (0, 0, 1.0), (0, 0, 1.49)),
        "Head": ("Torso", (0, 0, 1.49), (0, 0, 1.83)),
        "UpperArm_L": ("Torso", (-0.265, 0, 1.43), (-0.48, 0, 1.19)),
        "Forearm_L": ("UpperArm_L", (-0.48, 0, 1.19), (-0.48, 0, 0.99)),
        "UpperArm_R": ("Torso", (0.265, 0, 1.43), (0.48, 0, 1.19)),
        "Forearm_R": ("UpperArm_R", (0.48, 0, 1.19), (0.48, 0, 0.99)),
        "Thigh_L": ("Root", (-0.14, 0, 0.98), (-0.14, 0, 0.57)),
        "Shin_L": ("Thigh_L", (-0.14, 0, 0.57), (-0.14, 0, 0.12)),
        "Thigh_R": ("Root", (0.14, 0, 0.98), (0.14, 0, 0.57)),
        "Shin_R": ("Thigh_R", (0.14, 0, 0.57), (0.14, 0, 0.12)),
    }
    for name, (parent, head, tail) in parts.items():
        bone = bones.new(name)
        bone.head, bone.tail = head, tail
        bone.parent = bones[parent]
        bone.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")


def build(kind, palette):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    armature()
    skin_mat = material(kind + "_skin", palette["skin"])
    blush = material(kind + "_lips", palette["lips"])
    hair = material(kind + "_hair", palette["hair"])
    shirt = material(kind + "_cloth", palette["cloth"])
    hem = material(kind + "_cloth_trim", palette["trim"])
    leather = material(kind + "_leather", palette["leather"])
    dark = material(kind + "_boots", (0.11, 0.105, 0.085))
    eyes = material(kind + "_eye_white", (0.87, 0.84, 0.75), 0.55)
    iris = material(kind + "_eyes", palette["eyes"], 0.28)
    black = material(kind + "_pupil", (0.025, 0.03, 0.027), 0.2)
    metal = material(kind + "_metal", (0.47, 0.49, 0.43), 0.36, 0.68)

    # Correct adult proportions: 1.78 m tall, head ~1/8 body height.
    oval("skull", (0, -0.004, 1.657), (0.145, 0.116, 0.19), skin_mat, "Head", 24)
    oval("jaw", (0, -0.038, 1.578), (0.116, 0.096, 0.095), skin_mat, "Head", 20)
    oval("nose_bridge", (0, -0.122, 1.675), (0.029, 0.027, 0.066), skin_mat, "Head", 12)
    oval("nose_tip", (0, -0.149, 1.636), (0.037, 0.030, 0.022), skin_mat, "Head", 12)
    oval("lower_lip", (0, -0.136, 1.592), (0.045, 0.012, 0.008), blush, "Head", 12)
    for side in (-1, 1):
        oval("ear", (side*0.143, 0.012, 1.65), (0.027, 0.016, 0.054), skin_mat, "Head", 12)
        oval("eyeball", (side*0.064, -0.105, 1.705), (0.031, 0.013, 0.016), eyes, "Head", 12)
        oval("iris", (side*0.064, -0.119, 1.705), (0.012, 0.004, 0.014), iris, "Head", 12)
        oval("pupil", (side*0.064, -0.124, 1.705), (0.006, 0.003, 0.009), black, "Head", 12)
        oval("brow", (side*0.067, -0.116, 1.734), (0.045, 0.009, 0.009), hair, "Head", 12)
        oval("cheek", (side*0.09, -0.080, 1.63), (0.055, 0.049, 0.037), skin_mat, "Head", 12)
    oval("hair_cap", (0, 0.014, 1.785), (0.148, 0.118, 0.09), hair, "Head", 24)
    for side in (-1, 1):
        for n in range(3):
            oval("hair_lock", (side*(0.075+n*0.026), -0.081+n*0.016, 1.797-n*0.019),
                 (0.026, 0.042, 0.046), hair, "Head", 10)
    if kind in ("farmer", "guard"):
        # Short loose hair and sideburns; different faces remain visible.
        for side in (-1, 1):
            oval("sideburn", (side*0.137, -0.02, 1.726), (0.018, 0.046, 0.065), hair, "Head", 12)
    else:
        for side in (-1, 1):
            oval("long_hair", (side*0.115, 0.035, 1.594), (0.052, 0.061, 0.18), hair, "Head", 12)

    tapered("neck", (0, 0, 1.47), (0, 0, 1.58), 0.069, 0.064, skin_mat, "Torso")
    cloth("woven_tunic", [(0.94, .21, .145), (1.05, .22, .15), (1.3, .235, .15),
                            (1.48, .285, .155), (1.51, .15, .11)], shirt, "Torso")
    cloth("tunic_lower_hem", [(0.91, .224, .155), (0.945, .217, .148)], hem, "Torso")
    cloth("collar", [(1.47, .16, .12), (1.52, .115, .097)], hem, "Torso")
    cloth("belt", [(1.04, .228, .162), (1.12, .232, .164)], leather, "Torso", 1)
    oval("belt_buckle", (0, -.167, 1.08), (.04, .013, .034), metal, "Torso", 12)
    if kind in ("farmer", "merchant"):
        cloth("work_apron", [(0.82, .18, .145), (.98, .18, .145), (1.16, .15, .145)], leather, "Torso")
        oval("pouch", (.22, -.07, 1.06), (.073, .042, .082), leather, "Torso", 12)
    elif kind == "healer":
        cloth("healer_robe", [(0.72, .29, .23), (.82, .245, .19), (1.03, .22, .16)], shirt, "Torso")
        tapered("satchel_strap", (-.22, -.13, 1.45), (.2, -.16, 1.02), .016, .016, leather, "Torso")
    elif kind == "guard":
        oval("breastplate", (0, -.104, 1.31), (.213, .057, .16), leather, "Torso", 20)
        for side in (-1, 1):
            oval("shoulder_plate", (side*.28, -.01, 1.455), (.102, .132, .052), metal, "Torso", 16)

    for side, tag in [(-1, "L"), (1, "R")]:
        x = side*.14
        tapered("trousers_"+tag, (x, 0, .92), (x, 0, .55), .13, .092, hem, "Thigh_"+tag)
        tapered("lower_trousers_"+tag, (x, 0, .59), (x, 0, .20), .095, .079, hem, "Shin_"+tag)
        oval("leather_boot_"+tag, (x, -.047, .113), (.098, .166, .108), dark, "Shin_"+tag, 16)
        tapered("boot_cuff_"+tag, (x, 0, .21), (x, 0, .32), .107, .098, leather, "Shin_"+tag)
        ax = side*.32
        tapered("upper_sleeve_"+tag, (ax, 0, 1.435), (side*.46, 0, 1.19), .12, .087, shirt, "UpperArm_"+tag)
        tapered("lower_sleeve_"+tag, (side*.46, 0, 1.2), (side*.47, 0, 1.02), .086, .068, shirt, "Forearm_"+tag)
        tapered("sleeve_cuff_"+tag, (side*.47, 0, 1.06), (side*.47, 0, 1.0), .073, .068, hem, "Forearm_"+tag)
        oval("hand_"+tag, (side*.47, -.012, .958), (.055, .045, .067), skin_mat, "Forearm_"+tag, 12)
        for finger in range(4):
            oval("finger_"+tag, (side*.47 + (finger-1.5)*.024, -.023, .900),
                 (.011, .018, .034), skin_mat, "Forearm_"+tag, 10)

    # Combine the many modeled parts into one skinned draw source per person.
    # Blender merges vertex groups/material slots while retaining their bone weights.
    bpy.ops.object.select_all(action="DESELECT")
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    bpy.context.object.name = kind + "_body"
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.context.scene.objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = RIG
    target = OUT / (kind + ".glb")
    bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLB", use_selection=True,
                              export_animations=False, export_yup=True)
    print("CHARACTER_EXPORT", kind, target.stat().st_size)


PALETTES = {
    "farmer": dict(skin=(.61, .39, .27), lips=(.44, .24, .21), hair=(.19, .14, .11),
                   cloth=(.31, .43, .31), trim=(.74, .66, .47), leather=(.29, .20, .13), eyes=(.20, .26, .19)),
    "merchant": dict(skin=(.83, .59, .41), lips=(.57, .31, .28), hair=(.28, .17, .11),
                     cloth=(.39, .30, .40), trim=(.76, .62, .38), leather=(.41, .25, .17), eyes=(.22, .31, .35)),
    "healer": dict(skin=(.76, .48, .34), lips=(.58, .30, .27), hair=(.16, .12, .12),
                   cloth=(.32, .43, .47), trim=(.70, .69, .55), leather=(.33, .25, .19), eyes=(.28, .25, .20)),
    "guard": dict(skin=(.52, .32, .24), lips=(.38, .20, .18), hair=(.10, .10, .09),
                  cloth=(.35, .39, .34), trim=(.62, .51, .35), leather=(.28, .18, .13), eyes=(.18, .23, .23)),
}

for variant, palette in PALETTES.items():
    build(variant, palette)
