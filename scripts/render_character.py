#!/usr/bin/env python3
"""Render the authored farmer in isolation for character-art inspection."""
from pathlib import Path
import bpy
from mathutils import Vector

root = Path(__file__).resolve().parents[1]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(root/"game/assets/characters/farmer.glb"))
for obj in bpy.context.scene.objects:
    if obj.type == "MESH":
        world = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
        print("MODEL_BOUNDS", obj.name, tuple(round(min(p[i] for p in world), 3) for i in range(3)),
              tuple(round(max(p[i] for p in world), 3) for i in range(3)))
camera_data = bpy.data.cameras.new("Preview camera")
camera = bpy.data.objects.new("Preview camera", camera_data)
bpy.context.collection.objects.link(camera)
camera.location = (2.6, -4.5, 2.0)
target = Vector((0, 0, 0.94))
camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
camera_data.type = "ORTHO"
camera_data.ortho_scale = 2.7
bpy.context.scene.camera = camera
for pos, energy in [((2, -2, 4), 700), ((-3, 1, 3), 520)]:
    light = bpy.data.objects.new("Preview light", bpy.data.lights.new("Preview light", "AREA"))
    bpy.context.collection.objects.link(light)
    light.location = pos
    light.data.energy = energy
    light.rotation_euler = (target - light.location).to_track_quat("-Z", "Y").to_euler()
bpy.context.scene.render.engine = "CYCLES"
bpy.context.scene.cycles.samples = 16
bpy.context.view_layer.cycles.use_denoising = False
bpy.context.scene.render.resolution_x = 700
bpy.context.scene.render.resolution_y = 900
bpy.context.scene.render.resolution_percentage = 100
bpy.context.scene.render.image_settings.file_format = "PNG"
bpy.context.scene.render.filepath = "/tmp/living-world-character-preview.png"
bpy.ops.render.render(write_still=True)
