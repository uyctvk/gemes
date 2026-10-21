#!/usr/bin/env python3
"""Render the exported GLB, including an optional authored animation pose.

blender -b --factory-startup --python scripts/render_character.py -- --kind farmer
Use --view front|side|three_quarter and --clip Walk --frame 8 to inspect deformation.
"""
from pathlib import Path
import argparse
import sys
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--kind',default='farmer',choices=['farmer','merchant','healer','guard'])
parser.add_argument('--view',default='three_quarter',choices=['front','side','three_quarter'])
parser.add_argument('--clip',default='')
parser.add_argument('--frame',type=int,default=1)
parser.add_argument('--output',default='')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'game/assets/characters'/f'{args.kind}.glb'))
rig=next(obj for obj in bpy.context.scene.objects if obj.type=='ARMATURE')
if rig.animation_data:
    for track in rig.animation_data.nla_tracks: track.mute=True
    rig.animation_data.action=None
    if args.clip:
        action=next((a for a in bpy.data.actions if a.name==args.clip or a.name.startswith(args.clip+'_')),None)
        if action is None: raise RuntimeError(f'Missing {args.clip}; available {[a.name for a in bpy.data.actions]}')
        rig.animation_data.action=action
bpy.context.scene.frame_set(args.frame)
for obj in bpy.context.scene.objects:
    if obj.type=='MESH':
        world=[obj.matrix_world@vertex.co for vertex in obj.data.vertices]
        print('MODEL_BOUNDS',obj.name,tuple(round(min(p[i] for p in world),3) for i in range(3)),tuple(round(max(p[i] for p in world),3) for i in range(3)))
camera_data=bpy.data.cameras.new('Portrait camera')
camera=bpy.data.objects.new('Portrait camera',camera_data); bpy.context.collection.objects.link(camera)
# Export is Godot -Z front, hence +Y front when imported back into Blender.
camera.location={'front':(0,5,1.05),'side':(5,0,1.05),'three_quarter':(2.6,5.4,2.0)}[args.view]
target=Vector((0,0,.95))
camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
camera_data.type='ORTHO'; camera_data.ortho_scale=2.06
scene=bpy.context.scene; scene.camera=camera
for index,(point,power,size) in enumerate([((2,3,4),420,4),((-3,2,2),260,3),((1,-2,3),450,2)]):
    light=bpy.data.objects.new('Studio light '+str(index),bpy.data.lights.new('Studio light '+str(index),'AREA'))
    bpy.context.collection.objects.link(light); light.location=point; light.data.energy=power; light.data.shape='DISK'; light.data.size=size
    light.rotation_euler=(target-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,0))
plane=bpy.context.object
mat=bpy.data.materials.new('Studio ground'); mat.diffuse_color=(.12,.14,.15,1); mat.use_nodes=True
mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.12,.14,.15,1)
plane.data.materials.append(mat)
scene.world.color=(.15,.15,.15)
scene.render.engine='CYCLES'; scene.cycles.samples=32
bpy.context.view_layer.cycles.use_denoising=False
scene.render.resolution_x=840; scene.render.resolution_y=1050; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.view_settings.view_transform='AgX'
output=Path(args.output) if args.output else ROOT/'art/characters/previews'/f'{args.kind}-{args.view}{"-"+args.clip if args.clip else ""}.png'
output.parent.mkdir(parents=True,exist_ok=True)
scene.render.filepath=str(output)
bpy.ops.render.render(write_still=True)
print('CHARACTER_PREVIEW',output)
