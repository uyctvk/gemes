# Blender character sources

The four original adult humanoids are editable Blender 4.3 sources. Each source includes the armature, weighted mesh, four actions and packed image textures. The GLB files consumed by Godot are under `game/assets/characters/`.

- `farmer.blend`: fitted tunic, leather work apron and belt purse.
- `merchant.blend`: layered waistcoat, braid/buttons and tied hair.
- `healer.blend`: shoulder satchel and ceramic herb vials.
- `guard.blend`: steel cuirass, layered shoulder plates and bracers.

The head and garments use continuous modeled surfaces; sleeves and trousers blend joint weights. Cloth, leather, skin, hair and aged metal have generated UV image maps. These are authored game assets with a stylized finish, not photorealistic scans.

Source front is Blender **-Y**, feet near Z=0, height approximately 1.83 m. The exporter rotates only the export root so the Godot front is **-Z**. Source files remain in the conventional Blender orientation.

Actions are `Idle`, `Walk`, `Run` and `Attack` (30 fps). The first three are loops; Attack returns to a resting pose. Walk and Run use hip/knee/ankle articulation and vertical root compensation to keep the supporting sole near ground. Godot must set loop modes after importing; the runtime handles state transitions.

`Hand_R` / `Hand_L` are attachment bones. For the project's sword with its blade pointing along local +Y, position `(0, 0.04, 0)` and rotation `(-35, 0, 0)` degrees relative to `Hand_R` holds it forward/down from the palm.

Regenerate:

```bash
blender -b --factory-startup --python scripts/generate_characters.py
blender -b --factory-startup --python scripts/render_character.py -- --kind farmer
blender -b --factory-startup --python scripts/render_character.py -- --kind farmer --view side --clip Walk --frame 8
```

The generator requires Blender's bundled NumPy. The previews render the exported GLB after reimport, which also exercises export compatibility. The current manifest records geometry counts, dimensions and clips.
