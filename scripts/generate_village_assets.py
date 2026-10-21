#!/usr/bin/env python3
"""Author the original Elm village kit in Blender and export embedded glTF assets.

Run: blender -b --factory-startup --python scripts/generate_village_assets.py
The editable library is art/village/village_kit.blend. No downloaded assets.
"""
import math
import random
from pathlib import Path

import bpy
import numpy as np
from mathutils import Euler, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'game/assets/village'
ART = ROOT / 'art/village'
OUT.mkdir(parents=True, exist_ok=True)
ART.mkdir(parents=True, exist_ok=True)
random.seed(1519)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
MATERIALS = []


def texture(name, base, kind):
    n = 256
    yy, xx = np.mgrid[0:n, 0:n] / n
    rng = np.random.default_rng(19)
    noise = rng.normal(0, 1, (n, n))
    if kind == 'wood':
        wave = np.sin(xx * 150 + np.sin(yy*19)*1.7 + np.sin(xx*25)*2)
        height = .45 + .12*wave + .025*noise
        detail = .89 + .10*wave + .025*noise
    elif kind == 'plaster':
        height = .5 + .045*noise + .04*np.sin(xx*27)*np.sin(yy*41)
        detail = .91 + .07*noise + .045*np.sin(xx*17)*np.sin(yy*19)
    elif kind == 'grass':
        height = .5 + .12*noise
        detail = .80 + .16*noise + .14*np.sin(xx*31)*np.sin(yy*23)
    elif kind == 'cobble':
        row = np.floor(yy*8)
        dx = np.mod(xx*6+(row%2)*.5, 1)
        dy = np.mod(yy*8, 1)
        rim = np.minimum(np.minimum(dx, 1-dx),np.minimum(dy,1-dy))
        mortar = np.clip(rim/.09,0,1)
        height = .2 + .5*mortar + .035*noise
        detail = .48 + .43*mortar + .05*noise + .08*np.sin(np.floor(xx*6)*7+row*11)
    else:
        height = .5 + .07*noise + .06*np.sin(xx*27)*np.sin(yy*21)
        detail = .90 + .08*noise + .07*np.sin(xx*17)*np.sin(yy*25)
    rgba = np.ones((n,n,4), np.float32)
    rgba[:,:,:3] = np.clip(detail[:,:,None]*np.array(base)[None,None,:],0,1)
    img = bpy.data.images.new(name+'_albedo',width=n,height=n)
    img.pixels.foreach_set(rgba.ravel())
    img.filepath_raw = str(OUT/(name+'_albedo.png'))
    img.file_format = 'PNG'
    img.save()
    img.pack()
    dx = np.roll(height, -1,1)-np.roll(height,1,1)
    dy = np.roll(height,-1,0)-np.roll(height,1,0)
    normal = np.stack((-dx*1.4,-dy*1.4,np.ones_like(height)),axis=-1)
    normal /= np.linalg.norm(normal,axis=-1)[:,:,None]
    rgba[:,:,:3] = normal*.5+.5
    norm = bpy.data.images.new(name+'_normal',width=n,height=n)
    norm.colorspace_settings.name='Non-Color'
    norm.pixels.foreach_set(rgba.ravel())
    norm.filepath_raw=str(OUT/(name+'_normal.png'))
    norm.file_format='PNG'
    norm.save()
    norm.pack()
    return img,norm


def material(name, color, kind=None, metallic=0, rough=.8):
    m=bpy.data.materials.new(name)
    m.diffuse_color=(*color,1)
    m.use_nodes=True
    bsdf=m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value=(*color,1)
    bsdf.inputs['Metallic'].default_value=metallic
    bsdf.inputs['Roughness'].default_value=rough
    if kind:
        albedo,normal=texture(name,color,kind)
        for image,socket in [(albedo,'Base Color'),(normal,'Normal')]:
            node=m.node_tree.nodes.new('ShaderNodeTexImage')
            node.image=image
            if socket=='Normal':
                decode=m.node_tree.nodes.new('ShaderNodeNormalMap')
                decode.inputs['Strength'].default_value=.5
                m.node_tree.links.new(node.outputs['Color'],decode.inputs['Color'])
                m.node_tree.links.new(decode.outputs['Normal'],bsdf.inputs[socket])
            else: m.node_tree.links.new(node.outputs['Color'],bsdf.inputs[socket])
    MATERIALS.append(m)
    return len(MATERIALS)-1

WOOD=material('weathered_oak',(.28,.18,.095),'wood')
LIGHTWOOD=material('cut_wood',(.43,.29,.14),'wood')
PLASTER=material('lime_plaster',(.65,.59,.46),'plaster')
STONE=material('limestone',(.40,.42,.38),'stone')
ROOF=material('red_shingles',(.34,.16,.095),'stone')
SLATE=material('slate_tiles',(.19,.27,.29),'stone')
METAL=material('forged_iron',(.12,.14,.14),metallic=.68,rough=.45)
GLASS=material('amber_window',(.25,.26,.18),rough=.3)
CLOTH=material('canvas_sage',(.33,.42,.29),'plaster')
CLOTH_LIGHT=material('canvas_linen',(.66,.58,.39),'plaster')
LEAF=material('oak_leaf',(.16,.29,.12),'grass')
LEAF_LIGHT=material('oak_sunlit_leaf',(.25,.38,.16),'grass')
FRUIT=material('apples',(.45,.18,.07),rough=.55)
WATER=material('well_water',(.09,.18,.19),metallic=.25,rough=.2)
# Ground textures are also consumed directly by Godot's triplanar materials.
texture('grass_ground',(.24,.32,.17),'grass')
texture('cobble_ground',(.48,.45,.37),'cobble')


class Builder:
    def __init__(self,name): self.name=name; self.v=[]; self.f=[]; self.m=[]; self.uv=[]; self.smooth=[]
    def face(self, ids, mat, uv=None, smooth=False):
        self.f.append(ids); self.m.append(mat); self.smooth.append(smooth)
        self.uv.append(uv or [(0,0),(1,0),(1,1),(0,1)][:len(ids)])
    def block(self, p, s, mat, rot=(0,0,0)):
        start=len(self.v); matrix=Euler(rot).to_matrix(); p=Vector(p)
        for x,y,z in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]:
            self.v.append(tuple(p+matrix@Vector((x*s[0]/2,y*s[1]/2,z*s[2]/2))))
        for ids in [(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)]:
            self.face(tuple(start+i for i in ids),mat)
    def beam(self,a,b,width,mat):
        vec=Vector(b)-Vector(a)
        self.block((Vector(a)+Vector(b))/2,(width,width,vec.length),mat,vec.to_track_quat('Z','Y').to_euler())
    def tube(self,p,r1,r2,height,mat,n=16,rot=(0,0,0)):
        start=len(self.v); matrix=Euler(rot).to_matrix(); p=Vector(p)
        for z,r in [(-height/2,r1),(height/2,r2)]:
            for i in range(n):
                a=i*math.tau/n
                self.v.append(tuple(p+matrix@Vector((math.cos(a)*r,math.sin(a)*r,z))))
        for i in range(n):
            self.face((start+i,start+(i+1)%n,start+(i+1)%n+n,start+i+n),mat,[(i/n,0),((i+1)/n,0),((i+1)/n,1),(i/n,1)],True)
        self.face(tuple(start+i for i in reversed(range(n))),mat,[(.5+math.cos(i*math.tau/n)*.5,.5+math.sin(i*math.tau/n)*.5) for i in reversed(range(n))])
        self.face(tuple(start+n+i for i in range(n)),mat,[(.5+math.cos(i*math.tau/n)*.5,.5+math.sin(i*math.tau/n)*.5) for i in range(n)])
    def ellipsoid(self,p,s,mat,n=12,rings=7):
        start=len(self.v)
        for j in range(rings+1):
            a=math.pi*j/rings
            for i in range(n):
                b=math.tau*i/n
                jitter=1+.055*math.sin(i*7+j*4)
                self.v.append((p[0]+math.sin(a)*math.cos(b)*s[0]*jitter,p[1]+math.sin(a)*math.sin(b)*s[1]*jitter,p[2]+math.cos(a)*s[2]*jitter))
        for j in range(rings):
            for i in range(n):
                self.face((start+j*n+i,start+j*n+(i+1)%n,start+(j+1)*n+(i+1)%n,start+(j+1)*n+i),mat,smooth=True)
    def object(self,bevel=0):
        mesh=bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.v,[],self.f); mesh.update()
        obj=bpy.data.objects.new(self.name,mesh); bpy.context.collection.objects.link(obj)
        for m in MATERIALS: mesh.materials.append(m)
        uv=mesh.uv_layers.new(name='UVMap')
        for i,poly in enumerate(mesh.polygons):
            poly.material_index=self.m[i]; poly.use_smooth=self.smooth[i]
            for k,loop in enumerate(poly.loop_indices): uv.data[loop].uv=self.uv[i][k]
        if bevel:
            bpy.context.view_layer.objects.active=obj
            mod=obj.modifiers.new('Soft worked edges','BEVEL'); mod.width=bevel; mod.segments=1; mod.affect='EDGES'
            bpy.ops.object.modifier_apply(modifier=mod.name)
        return obj


def window(b,x,y,z,w=.85,h=1):
    b.block((x,y,z),(w,.06,h),METAL)
    for dx in [-w/4,w/4]:
        for dz in [-h/4,h/4]: b.block((x+dx,y-.04,z+dz),(w/2-.045,.025,h/2-.045),GLASS)
    for dx in [-w/2-.055,0,w/2+.055]: b.block((x+dx,y-.08,z),(.085,.14,h+.18),WOOD)
    for dz in [-h/2-.05,0,h/2+.05]: b.block((x,y-.08,z+dz),(w+.2,.14,.085),WOOD)
    for side in [-1,1]:
        sx=x+side*(w/2+.24)
        for n in range(3): b.block((sx+side*n*.095,y-.03,z),(.09,.09,h),LIGHTWOOD)
        for dz in [-h*.32,h*.32]: b.block((sx+side*.095,y-.095,z+dz),(.33,.06,.06),METAL)
    b.block((x,y-.16,z-h/2-.13),(w+.45,.38,.12),STONE)


def house(name,w=5,d=4,h=3.2,roof_mat=ROOF,upper=False,porch=False):
    b=Builder(name)
    b.block((0,0,h/2+.25),(w,d,h-.5),PLASTER)
    # Stone courses with offset mortar joints.
    for row in range(3):
        for side in [-1,1]:
            for x in np.arange(-w/2+.28,w/2,.55):
                b.block((float(x)+(row%2)*.08,side*(d/2+.015),.12+row*.19),(.51,.22,.175),STONE)
            for y in np.arange(-d/2+.28,d/2,.55): b.block((side*(w/2+.015),float(y),.12+row*.19),(.22,.51,.175),STONE)
    for y in [-d/2-.07,d/2+.07]:
        for x in [-w/2,-w/4,0,w/4,w/2]: b.block((x,y,h/2),(.16,.17,h),WOOD)
        for z in [.65,2.65,h-.07]: b.block((0,y,z),(w+.15,.19,.17),WOOD)
        for side in [-1,1]:
            b.beam((side*w*.47,y,.75),(side*w*.27,y,2.55),.12,WOOD)
    for x in [-w/2-.06,w/2+.06]:
        for y in [-d/2,0,d/2]: b.block((x,y,h/2),(.17,.16,h),WOOD)
        for z in [.65,2.65,h-.07]: b.block((x,0,z),(.19,d+.15,.17),WOOD)
        for side in [-1,1]: b.beam((x,side*d*.46,.72),(x,side*d*.04,2.55),.12,WOOD)
    rise=w*.38; ridge=h+rise
    # Gable triangles filled by vertical plaster boards and exposed timber.
    for y in [-d/2-.02,d/2+.02]:
        for x in np.arange(-w/2+.08,w/2,.16):
            top=ridge-abs(float(x))*rise/(w/2)
            if top>h: b.block((float(x),y,(top+h)/2),(.165,.1,top-h),PLASTER)
        b.beam((-w/2,y-.06,h),(0,y-.06,ridge),.16,WOOD)
        b.beam((w/2,y-.06,h),(0,y-.06,ridge),.16,WOOD)
        b.beam((0,y-.08,h),(0,y-.08,ridge),.16,WOOD)
    slope=math.atan2(rise,w/2)
    # Individual staggered shingles descend outward from the ridge.
    roof_half=w/2+.38
    for side in [-1,1]:
        for row in range(9):
            x=side*(row+.5)*roof_half/9
            z=ridge-abs(x)*math.tan(slope)+.08
            for col in range(13):
                y=-d/2-.35+(col+.5)*(d+.7)/13+(row%2)*.06
                tile_w=roof_half/9/math.cos(slope)+.06
                b.block((x,y,z),(tile_w,(d+.7)/13-.015,.085),roof_mat,rot=(0,side*slope,0))
        for y in [-d/2-.4,d/2+.4]: b.beam((0,y,ridge+.03),(side*roof_half,y,h-.28),.16,WOOD)
        b.block((side*roof_half,0,h-.23),(.18,d+.9,.19),WOOD)
    b.tube((0,0,ridge+.10),.13,.13,d+.9,roof_mat,12,(math.pi/2,0,0))
    # Planked door with frame and forged strap hinges.
    front=-d/2-.10
    b.block((0,front,1.2),(1.06,.15,2.2),METAL)
    for i in range(6): b.block((-.45+i*.18,front-.09,1.2),(.166,.08,2.1),LIGHTWOOD)
    for x in [-.61,.61]: b.block((x,front-.1,1.2),(.15,.19,2.4),WOOD)
    b.block((0,front-.1,2.4),(1.35,.19,.18),WOOD)
    for z in [.65,1.7]: b.block((-.13,front-.16,z),(.74,.045,.075),METAL)
    b.tube((.32,front-.20,1.22),.045,.045,.06,METAL,12,(math.pi/2,0,0))
    b.block((0,front-.32,.1),(1.7,.75,.2),STONE)
    for x in [-w*.30,w*.30]: window(b,x,front,1.75,.85,1.04)
    # Masonry chimney and cap: a clear roof silhouette.
    for layer in range(12):
        z=h+.14+layer*.18
        for side in [-1,1]:
            b.block((-w*.31+side*.23,d*.19,z),(.20,.62,.16),STONE)
            b.block((-w*.31,d*.19+side*.23,z),(.62,.20,.16),STONE)
    b.block((-w*.31,d*.19,h+2.35),(.84,.84,.16),STONE)
    if upper:
        window(b,0,front-.01,h+.53,.65,.6)
        # Painted guild sign on a forged bracket.
        b.beam((w*.44,front,2.65),(w*.44,front-.95,2.65),.06,METAL)
        b.block((w*.44,front-.82,2.2),(.75,.12,.67),WOOD)
        b.tube((w*.44,front-.90,2.2),.21,.21,.04,METAL,16,(math.pi/2,0,0))
    if porch:
        for x in [-1.2,1.2]:
            b.block((x,front-.95,1.35),(.13,.13,2.7),WOOD)
            b.beam((x,front-.95,2),(x,front-.4,2.75),.10,WOOD)
        for i in range(8):
            b.block((0,front-.12-i*.16,2.94-i*.07),(2.8,.18,.10),roof_mat,rot=(.4,0,0))
    return b.object(.012)


def barrel(b,p=(0,0,0),scale=1):
    x,y,z=p
    # Bulged wooden staves, with four iron hoops.
    for i in range(16):
        a=i*math.tau/16
        for height,radius in [(.15,.28),(.40,.32),(.65,.32),(.9,.28)]:
            b.block((x+math.cos(a)*radius*scale,y+math.sin(a)*radius*scale,z+height*scale),(.11*scale,.055*scale,.25*scale),LIGHTWOOD,rot=(0,0,a+math.pi/2))
    for height,radius in [(.14,.30),(.32,.34),(.72,.34),(.91,.30)]:
        for i in range(16):
            a=i*math.tau/16
            b.block((x+math.cos(a)*radius*scale,y+math.sin(a)*radius*scale,z+height*scale),(.13*scale,.035*scale,.05*scale),METAL,rot=(0,0,a+math.pi/2))
    b.tube((x,y,z+.96*scale),.28*scale,.28*scale,.045*scale,LIGHTWOOD,16)
    for n in range(-2,3): b.block((x+n*.095*scale,y,z+.988*scale),(.012*scale,.48*scale,.004*scale),WOOD)


def crate_asset():
    b=Builder('crate')
    for side in [-1,1]:
        for n in range(5):
            b.block((side*.32,0,.08+n*.14),(.065,.64,.125),LIGHTWOOD)
            b.block((0,side*.32,.08+n*.14),(.64,.065,.125),LIGHTWOOD)
        for x in [-.27,.27]: b.block((x,side*.36,.36),(.07,.05,.72),WOOD)
        b.beam((-.26,side*.37,.1),(.26,side*.37,.61),.07,WOOD)
    for x in np.arange(-.28,.3,.14): b.block((float(x),0,.70),(.125,.65,.05),LIGHTWOOD)
    return b.object(.007)


def well():
    b=Builder('well')
    for row in range(4):
        for i in range(16):
            a=(i+(row%2)*.5)*math.tau/16
            b.block((math.cos(a)*.98,math.sin(a)*.98,.13+row*.23),(.40,.29,.22),STONE,rot=(0,0,a+math.pi/2))
    b.tube((0,0,.43),.78,.78,.025,WATER,32)
    for side in [-1,1]:
        b.block((side*1.24,0,1.52),(.18,.20,3.04),WOOD)
        b.beam((side*1.24,0,2.3),(side*.7,0,2.9),.12,WOOD)
    b.tube((0,0,2.1),.10,.10,2.7,LIGHTWOOD,16,(0,math.pi/2,0))
    b.tube((0,0,1.58),.018,.018,1.1,LIGHTWOOD,10)
    for side in [-1,1]:
        for row in range(5):
            x=side*(row+.5)*.30
            for col in range(6):
                b.block((x,-.95+col*.37,3.25-abs(x)*.55),(.37,.35,.075),ROOF,rot=(0,side*.5,0))
    barrel(b,(.2,.15,.45),.4)
    return b.object(.01)


def market():
    b=Builder('market_stall')
    for x in [-2.7,2.7]:
        for y in [-1.15,1.15]: b.block((x,y,1.55),(.14,.14,3.1),WOOD)
        b.beam((x,-1.15,2.3),(x,-.50,3.0),.10,WOOD)
    for y in [-1.15,1.15]: b.block((0,y,2.9),(5.7,.15,.15),WOOD)
    # Curved fabric canopy as a continuous strip mesh.
    for stripe in range(12):
        left=-2.9+stripe*5.8/12; right=left+5.8/12
        start=len(b.v)
        for j in range(9):
            y=-1.5+j*.37; z=3.2-.31*(abs(y)/1.5)**1.5
            b.v.extend([(left,y,z),(right,y,z)])
        for j in range(8): b.face((start+j*2,start+j*2+1,start+j*2+3,start+j*2+2),CLOTH if stripe%2 else CLOTH_LIGHT)
        b.block(((left+right)/2,-1.51,2.83),(right-left,.035,.19),CLOTH if stripe%2 else CLOTH_LIGHT)
    for x in [-1.8,0,1.8]:
        for z in [.55,.73,.91]: b.block((x,-.65,z),(1.65,.10,.15),LIGHTWOOD)
        for y in [-.7,.5]:
            for dx in [-.72,.72]: b.block((x+dx,y,.53),(.10,.10,1.06),WOOD)
        for n in range(7): b.block((x,-.55+n*.16,1.05),(1.7,.145,.08),LIGHTWOOD)
        for a in range(4):
            for c in range(3): b.ellipsoid((x-.48+a*.28,-.38+c*.25,1.17),(.13,.12,.12),FRUIT,8,5)
    barrel(b,(2.2,.55,0),.9)
    return b.object(.006)


def cart():
    b=Builder('handcart')
    for x in np.arange(-.65,.7,.16): b.block((float(x),0,.65),(.14,1.8,.12),LIGHTWOOD)
    for side in [-1,1]:
        for z in [.82,1.02,1.22]: b.block((side*.72,0,z),(.10,1.9,.16),LIGHTWOOD)
        for y in [-.85,.85]: b.block((side*.73,y,1.04),(.10,.10,.95),WOOD)
        b.beam((side*.55,-.2,.57),(side*.55,-2.1,.86),.09,WOOD)
        for i in range(16):
            a=i*math.tau/16
            b.block((side*.89,math.sin(a)*.55,.57+math.cos(a)*.55),(.10,.23,.09),METAL,rot=(a,0,0))
        for i in range(8):
            a=i*math.tau/8
            b.beam((side*.89,0,.57),(side*.89,math.sin(a)*.5,.57+math.cos(a)*.5),.055,LIGHTWOOD)
    b.beam((-.99,0,.57),(.99,0,.57),.12,METAL)
    barrel(b,(.15,.2,.71),.7)
    return b.object(.008)


def oak():
    b=Builder('oak')
    b.tube((0,0,1.65),.34,.19,3.3,WOOD,12)
    for i in range(9):
        a=i*2.4; h=2.15+i*.28
        p=(math.cos(a)*1.35,math.sin(a)*1.35,h+.8)
        b.beam((0,0,h),p,.13,WOOD)
        b.ellipsoid(p,(1.35,1.15,1.05),LEAF if i%2 else LEAF_LIGHT,12,7)
    b.ellipsoid((0,0,4.4),(1.25,1.2,1.1),LEAF_LIGHT,12,7)
    return b.object()

assets=[house('cottage',5,4,3.15,ROOF,False,True),house('workshop',7,5.6,3.6,SLATE,True,True),house('townhouse',5.5,4.7,4.25,ROOF,True,False),crate_asset(),well(),market(),cart(),oak()]
b=Builder('barrel'); barrel(b); assets.append(b.object(.004))
for obj in assets:
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True); bpy.context.view_layer.objects.active=obj
    target=OUT/(obj.name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_yup=True,export_animations=False)
    print('VILLAGE_EXPORT',obj.name,'triangles',sum(len(p.vertices)-2 for p in obj.data.polygons),'bytes',target.stat().st_size)
# Editable library is arranged for convenient inspection in Blender.
for i,obj in enumerate(assets): obj.location=((i%3)*10,(i//3)*10,0)
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'village_kit.blend'))
# Render one cottage and market grouping as an authoring proof.
for obj in assets: obj.hide_render=obj.name not in ['cottage','market_stall','handcart']
assets[0].location=(0,0,0)
next(o for o in assets if o.name=='market_stall').location=(6,0,0)
next(o for o in assets if o.name=='handcart').location=(3,-3,0)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.04))
plane=bpy.context.object; plane.data.materials.append(MATERIALS[STONE])
cam=bpy.data.objects.new('Preview camera',bpy.data.cameras.new('Preview camera'))
bpy.context.collection.objects.link(cam); cam.location=(12,-18,12)
target=Vector((2,0,2)); cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler(); cam.data.type='ORTHO'; cam.data.ortho_scale=15
scene=bpy.context.scene; scene.camera=cam
world=bpy.data.worlds.new('Village daylight'); world.use_nodes=True; world.node_tree.nodes['Background'].inputs[0].default_value=(.45,.58,.70,1); world.node_tree.nodes['Background'].inputs[1].default_value=.4; scene.world=world
for p,e,size in [((-3,-5,10),1500,7),((8,3,8),1200,6)]:
    light=bpy.data.objects.new('Preview area',bpy.data.lights.new('Preview area','AREA')); bpy.context.collection.objects.link(light); light.location=p; light.data.energy=e; light.data.shape='DISK'; light.data.size=size; light.rotation_euler=(target-light.location).to_track_quat('-Z','Y').to_euler()
scene.render.engine='CYCLES'; scene.cycles.samples=24; bpy.context.view_layer.cycles.use_denoising=False
scene.render.resolution_x=1200; scene.render.resolution_y=900; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'; scene.render.filepath=str(ART/'village_kit_preview.png')
bpy.ops.render.render(write_still=True)
