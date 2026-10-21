#!/usr/bin/env python3
"""Author and export an original tempered-steel sword with an editable Blender file.

blender -b --factory-startup --python scripts/generate_equipment.py
The origin is the hand grip; blade points along Blender +Z / Godot +Y.
"""
from pathlib import Path
import math
import bpy

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'game/assets/equipment'
SOURCE = ROOT / 'art/equipment'
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)


def material(name, color, metallic, roughness):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    return mat


steel = material('Tempered steel', (.41, .48, .52), .92, .27)
edge = material('Honed edges', (.70, .75, .76), .96, .19)
fuller = material('Recessed steel', (.18, .23, .25), .83, .34)
brass = material('Aged brass', (.39, .27, .10), .78, .36)
leather = material('Oxhide wrapping', (.085, .043, .025), .0, .82)

# The blade cross section includes an actual recessed fuller and two bevelled edges.
section = [(-1, 0), (-.58, -.015), (-.23, -.010), (.23, -.010),
           (.58, -.015), (1, 0), (.58, .015), (.23, .010),
           (-.23, .010), (-.58, .015)]
rings = [(.13, .043), (.22, .043), (.77, .031), (.96, .020), (1.08, .0007)]
verts = [(x * width, y * max(.1, width / .043), z) for z, width in rings for x, y in section]
faces = []
for row in range(len(rings) - 1):
    for col in range(len(section)):
        a = row * len(section) + col
        b = row * len(section) + (col + 1) % len(section)
        faces.append((a, b, b + len(section), a + len(section)))
mesh = bpy.data.meshes.new('Forged blade section')
mesh.from_pydata(verts, [], faces)
mesh.materials.clear()
for mat in [steel, edge, fuller]: mesh.materials.append(mat)
blade = bpy.data.objects.new('Blade with recessed fuller', mesh)
bpy.context.collection.objects.link(blade)
for poly in mesh.polygons:
    col = poly.index % len(section)
    poly.material_index = 1 if col in (0, 4, 5, 9) else 2 if col in (2, 7) else 0


def cylinder(name, radius, depth, z, mat, vertices=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=(0, 0, z))
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    bevel = obj.modifiers.new('Rounded tooling', 'BEVEL')
    bevel.width, bevel.segments = .003, 2
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


cylinder('Leather grip', .023, .23, -.015, leather)
for z in [-.13, .103]: cylinder('Brass ferrule', .027, .022, z, brass)
for i in range(13):
    bpy.ops.mesh.primitive_torus_add(major_radius=.023, minor_radius=.0025,
                                   major_segments=24, minor_segments=6,
                                   location=(0, 0, -.113 + i * .017))
    obj = bpy.context.object
    obj.name = 'Leather grip seam'
    obj.rotation_euler.x = .16
    obj.data.materials.append(leather)

# Down-curved quillons are real geometry, not a screen-space weapon overlay.
for side in [-1, 1]:
    bpy.ops.mesh.primitive_cube_add(size=1, location=(side * .092, 0, .13))
    obj = bpy.context.object
    obj.name = 'Curved crossguard'
    obj.scale = (.205, .035, .034)
    obj.rotation_euler.y = side * .2
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(brass)
    bevel = obj.modifiers.new('Forged edges', 'BEVEL')
    bevel.width, bevel.segments = .008, 3
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    cylinder('Guard stud', .016, .04, .145, steel)

cylinder('Pommel neck', .021, .036, -.151, brass)
bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, location=(0, 0, -.181))
pommel = bpy.context.object
pommel.name = 'Faceted pommel'
pommel.scale = (.036, .022, .04)
pommel.data.materials.append(brass)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = blade
bpy.ops.object.join()
blade.name = 'Village longsword'
blade['grip_origin'] = 'Origin is grip center; +Z is blade direction'
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / 'sword.blend'))
bpy.ops.export_scene.gltf(filepath=str(OUT / 'sword.glb'), export_format='GLB',
                         use_selection=True, export_animations=False, export_yup=True)
print('EQUIPMENT_EXPORT', OUT / 'sword.glb')
