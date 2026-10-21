#!/usr/bin/env python3
"""Export edited .blend files without regenerating or overwriting the source art.

blender -b --python scripts/export_blender_sources.py -- --group all
"""
import argparse
import math
from pathlib import Path
import sys

import bpy

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'game/assets'


def export(path, animated=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB',
                             use_selection=True, export_yup=True,
                             export_animations=animated, export_animation_mode='ACTIONS',
                             export_nla_strips=True, export_force_sampling=True)
    print('SOURCE_EXPORT', path)


def characters():
    for role in ('farmer', 'merchant', 'healer', 'guard'):
        bpy.ops.wm.open_mainfile(filepath=str(ROOT / 'art/characters' / (role + '.blend')))
        rig = next(obj for obj in bpy.context.scene.objects if obj.type == 'ARMATURE')
        # The source faces Blender -Y. Normalize only this in-memory export to Godot -Z.
        rig.rotation_euler.z += math.pi
        bpy.ops.object.select_all(action='DESELECT')
        for obj in bpy.context.scene.objects:
            obj.select_set(obj.type in ('MESH', 'ARMATURE'))
        bpy.context.view_layer.objects.active = rig
        export(ASSETS / 'characters' / (role + '.glb'), animated=True)


def village():
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / 'art/village/village_kit.blend'))
    output = ASSETS / 'village'
    output.mkdir(parents=True, exist_ok=True)
    # Ground textures are used by Godot directly; all maps are also packed in the source.
    for image in bpy.data.images:
        if image.type == 'IMAGE' and image.has_data:
            image.filepath_raw = str(output / (image.name + '.png'))
            image.file_format = 'PNG'
            image.save()
    for name in ('cottage', 'workshop', 'townhouse', 'crate', 'well', 'market_stall', 'handcart', 'oak', 'barrel'):
        obj = bpy.context.scene.objects[name]
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        original_location = obj.location.copy()
        obj.location = (0, 0, 0)
        export(output / (name + '.glb'))
        obj.location = original_location


def equipment():
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / 'art/equipment/sword.blend'))
    bpy.ops.object.select_all(action='DESELECT')
    for obj in bpy.context.scene.objects:
        obj.select_set(obj.type == 'MESH')
    export(ASSETS / 'equipment/sword.glb')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--group', choices=('all', 'characters', 'village', 'equipment'), default='all')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    for name, function in [('characters', characters), ('village', village), ('equipment', equipment)]:
        if args.group in ('all', name): function()
