#!/usr/bin/env python3
"""Author the original LIVING WORLD humanoids in Blender 4.x.

blender -b --factory-startup --python scripts/generate_characters.py
Editable .blend sources, packed hand-generated texture maps, and animated GLBs
are produced together. Source characters face Blender -Y; exports face Godot -Z.
"""
from pathlib import Path
import math
import json
import bpy
import numpy as np
from mathutils import Vector, Quaternion

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'game/assets/characters'
SOURCE = ROOT / 'art/characters'
OUT.mkdir(parents=True, exist_ok=True)
(SOURCE / 'textures').mkdir(parents=True, exist_ok=True)
RIG = None
TAU = math.tau


def image_map(name, color, surface):
    size = 256
    rng = np.random.default_rng(sum(ord(c) for c in name))
    yy, xx = np.mgrid[0:size, 0:size]
    noise = rng.normal(0, .025, (size, size))
    if surface == 'cloth':
        grain = .035*np.sin(xx*math.pi/2) + .025*np.cos(yy*math.pi/2) + noise
    elif surface == 'leather':
        grain = .025*np.sin(xx*.11)*np.sin(yy*.13) + noise*.8
    elif surface == 'metal':
        grain = .024*np.sin(xx*.8) + noise*.5
    elif surface == 'skin':
        grain = noise*.45 + .008*np.sin(xx*.045)*np.sin(yy*.065)
    else:
        grain = .03*np.sin(xx*.22) + noise*.7
    rgba = np.ones((size, size, 4), dtype=np.float32)
    rgba[:,:,:3] = np.clip(np.array(color)[None,None,:] * (1+grain[:,:,None]), 0, 1)
    image = bpy.data.images.new(name + '_albedo', width=size, height=size, alpha=False)
    image.pixels.foreach_set(rgba.ravel())
    image.filepath_raw = str(SOURCE / 'textures' / (name + '.png'))
    image.file_format = 'PNG'
    image.save()
    image.pack()
    return image


def material(name, color, surface='cloth', roughness=.8, metallic=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic
    if surface:
        tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image = image_map(name, color, surface)
        mat.node_tree.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    return mat


def bind(obj, bone='Torso', weights=None):
    obj.parent = RIG
    if weights is None:
        group = obj.vertex_groups.new(name=bone)
        group.add(list(range(len(obj.data.vertices))), 1, 'REPLACE')
    else:
        groups = {}
        for i, mapping in enumerate(weights):
            for name, amount in mapping.items():
                if amount <= 0: continue
                if name not in groups: groups[name] = obj.vertex_groups.new(name=name)
                groups[name].add([i], amount, 'REPLACE')
    mod = obj.modifiers.new('Deformation', 'ARMATURE')
    mod.object = RIG
    for face in obj.data.polygons: face.use_smooth = True
    return obj


def surface(name, verts, faces, mat, bone='Torso', weights=None, uvs=None):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(mat)
    uv = mesh.uv_layers.new(name='UVMap')
    if uvs:
        for face in mesh.polygons:
            for li in face.loop_indices:
                uv.data[li].uv = uvs[mesh.loops[li].vertex_index]
    return bind(obj, bone, weights)


def rings(name, rows, mat, bone='Torso', sides=32, folds=0, weights_fn=None):
    # Each row is (z, half_width, depth, center_y); continuous quad surface.
    verts, faces, uvs, weights = [], [], [], []
    for i,(z,rx,ry,cy) in enumerate(rows):
        for j in range(sides+1):
            a = j*TAU/sides
            ripple = 1 + folds*math.sin(a*12 + z*13)
            verts.append((rx*math.cos(a)*ripple, cy+ry*math.sin(a)*ripple, z))
            uvs.append((j/sides, i/(len(rows)-1)))
            if weights_fn: weights.append(weights_fn(z))
    for i in range(len(rows)-1):
        for j in range(sides):
            a=i*(sides+1)+j
            faces.append((a,a+1,a+sides+2,a+sides+1))
    faces.append(tuple(reversed(range(sides))))
    last=(len(rows)-1)*(sides+1)
    faces.append(tuple(last+j for j in range(sides)))
    return surface(name,verts,faces,mat,bone,weights if weights_fn else None,uvs)


def tube(name, path, widths, mat, bone='Torso', sides=12, weights_fn=None):
    verts, faces, uvs, weights = [], [], [], []
    for i,point in enumerate(path):
        center=Vector(point)
        tangent=Vector(path[min(i+1,len(path)-1)])-Vector(path[max(i-1,0)])
        tangent.normalize()
        axis=Vector((0,1,0))
        if abs(tangent.dot(axis))>.9: axis=Vector((1,0,0))
        u=tangent.cross(axis).normalized()
        v=tangent.cross(u).normalized()
        radii=widths[i] if isinstance(widths[i],tuple) else (widths[i],widths[i])
        for j in range(sides+1):
            a=j*TAU/sides
            p=center+u*math.cos(a)*radii[0]+v*math.sin(a)*radii[1]
            verts.append(tuple(p)); uvs.append((j/sides,i/(len(path)-1)))
            if weights_fn: weights.append(weights_fn(point[2]))
    for i in range(len(path)-1):
        for j in range(sides):
            a=i*(sides+1)+j
            faces.append((a,a+1,a+sides+2,a+sides+1))
    faces.extend([tuple(reversed(range(sides))),tuple((len(path)-1)*(sides+1)+j for j in range(sides))])
    return surface(name,verts,faces,mat,bone,weights if weights_fn else None,uvs)


def oval(name,point,scale,mat,bone='Torso',sides=16,rings_count=10):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=sides, ring_count=rings_count, location=point)
    obj=bpy.context.object; obj.name=name; obj.scale=scale
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    obj.data.materials.append(mat)
    return bind(obj,bone)


def cube(name,point,size,mat,bone='Torso',bevel=.006):
    bpy.ops.mesh.primitive_cube_add(size=1,location=point)
    obj=bpy.context.object; obj.name=name; obj.scale=size
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    obj.data.materials.append(mat)
    if bevel:
        mod=obj.modifiers.new('Rounded crafted edge','BEVEL'); mod.width=bevel; mod.segments=2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return bind(obj,bone)


def seam(name,points,mat,bone='Torso',width=.002):
    return tube(name,points,[width]*len(points),mat,bone,sides=6)


def armature():
    global RIG
    bpy.ops.object.armature_add(enter_editmode=True)
    RIG=bpy.context.object; RIG.name='VillageHumanRig'
    bones=RIG.data.edit_bones
    root=bones[0]; root.name='Root'; root.head=(0,0,0); root.tail=(0,0,1)
    parts={
      'Torso':('Root',(0,0,1.00),(0,0,1.48)),
      'Head':('Torso',(0,0,1.48),(0,0,1.79)),
    }
    for s,tag in [(-1,'L'),(1,'R')]:
        parts.update({
          'UpperArm_'+tag:('Torso',(s*.225,0,1.45),(s*.31,0,1.19)),
          'Forearm_'+tag:('UpperArm_'+tag,(s*.31,0,1.19),(s*.345,-.018,.965)),
          'Hand_'+tag:('Forearm_'+tag,(s*.345,-.018,.965),(s*.345,-.02,.862)),
          'Thigh_'+tag:('Root',(s*.108,0,1.01),(s*.112,-.01,.56)),
          'Shin_'+tag:('Thigh_'+tag,(s*.112,-.01,.56),(s*.112,0,.13)),
          'Foot_'+tag:('Shin_'+tag,(s*.112,0,.13),(s*.112,-.15,.07)),
        })
    for name,(parent,head,tail) in parts.items():
        bone=bones.new(name); bone.head=head; bone.tail=tail; bone.parent=bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    for pb in RIG.pose.bones: pb.rotation_mode='QUATERNION'


def face(skin, lip, hair, eye, iris, black, kind):
    # A continuous human head surface: jaw, cheeks, eye sockets and nasal bridge.
    rows=[(1.565,.027,.034,-.023),(1.578,.045,.050,-.016),(1.596,.060,.064,-.007),
          (1.615,.071,.074,0),(1.637,.080,.081,.003),(1.659,.084,.083,.004),
          (1.681,.085,.085,.004),(1.703,.085,.087,.006),(1.727,.084,.089,.008),
          (1.750,.080,.089,.010),(1.773,.070,.081,.012),(1.793,.051,.062,.012),
          (1.808,.029,.038,.011),(1.815,.004,.006,.01)]
    obj=rings('Anatomical_head',rows,skin,'Head',sides=40)
    for vertex in obj.data.vertices:
        x,y,z=vertex.co
        if y < -.028:
            forward=max(0,min(1,(-y-.028)/.045))
            bridge=.020*math.exp(-(x/.014)**2-((z-1.669)/.043)**2)
            tip=.016*math.exp(-(x/.018)**2-((z-1.647)/.012)**2)
            sockets=.009*sum(math.exp(-((x-s*.034)/.020)**2-((z-1.687)/.014)**2) for s in [-1,1])
            muzzle=.005*math.exp(-(x/.035)**2-((z-1.616)/.014)**2)
            vertex.co.y += (sockets-bridge-tip-muzzle)*forward
    # Shaped nasal bridge: a narrow continuous patch runs into the cheek surface.
    nose_rows=[(1.706,.007,-.081,-.079),(1.690,.010,-.094,-.081),
               (1.671,.011,-.109,-.085),(1.653,.017,-.121,-.088),
               (1.645,.019,-.120,-.089),(1.638,.013,-.104,-.088)]
    vertices=[]; faces=[]; uvs=[]
    for i,(z,w,front,edge) in enumerate(nose_rows):
        for j in range(7):
            a=(j-3)/3
            vertices.append((a*w,edge+(front-edge)*(1-a*a),z)); uvs.append((j/6,i/5))
    for i in range(5):
        for j in range(6):
            a=i*7+j; faces.append((a,a+1,a+8,a+7))
    surface('Nasal_bridge',vertices,faces,skin,'Head',uvs=uvs)
    # Narrow eyes fitted into the sockets, with separate eyelid rims.
    for s in [-1,1]:
        ex=s*.035
        oval('Eye_'+str(s),(ex,-.078,1.686),(.018,.010,.0065),eye,'Head',20,10)
        oval('Iris_'+str(s),(ex,-.0874,1.686),(.0050,.0019,.0050),iris,'Head',16,8)
        oval('Pupil_'+str(s),(ex,-.0891,1.686),(.0021,.001,.0029),black,'Head',12,8)
        upper=[]; lower=[]
        for j in range(9):
            t=j/8; x=ex+(t-.5)*.038
            upper.append((x,-.0805-.004*math.sin(t*math.pi),1.686+.0065*math.sin(t*math.pi)))
            lower.append((x,-.0805-.004*math.sin(t*math.pi),1.685-.0045*math.sin(t*math.pi)))
        seam('Upper_eyelid',upper,skin,'Head',.002)
        seam('Lower_eyelid',lower,skin,'Head',.0015)
        seam('Eyebrow',[(ex-.019,-.078,1.704),(ex-.006,-.086,1.708),(ex+.011,-.084,1.707),(ex+.021,-.076,1.702)],hair,'Head',.0024)
        oval('Ear',(s*.084,.007,1.668),(.012,.011,.027),skin,'Head',16,12)
        oval('Ear_concha',(s*.091,-.001,1.667),(.007,.006,.017),lip,'Head',12,8)
        oval('Ear_helix',(s*.091,.000,1.675),(.008,.006,.013),skin,'Head',12,8)
        oval('Nostril',(s*.010,-.112,1.642),(.003,.0018,.0020),lip,'Head',12,8)
    seam('Upper_lip',[(-.024,-.079,1.618),(-.011,-.086,1.620),(0,-.088,1.618),(.011,-.086,1.620),(.024,-.079,1.618)],lip,'Head',.0023)
    seam('Lower_lip',[(-.021,-.079,1.615),(0,-.087,1.613),(.021,-.079,1.615)],lip,'Head',.0021)
    # Scalp and swept locks remain within an adult skull silhouette.
    scalp=rings('Hair_scalp',[(1.733,.086,.090,.012),(1.746,.084,.094,.013),(1.769,.076,.091,.015),(1.791,.058,.071,.016),(1.811,.032,.042,.017),(1.815,.004,.006,.017)],hair,'Head',sides=32)
    for j in range(15):
        a=-math.pi*.95+j*math.pi*1.9/14
        x=.075*math.sin(a)
        y=.014-.078*math.cos(a)
        z=1.754+.013*math.cos(a)
        path=[(x,y,z),(x*.88,y*.78,1.792),(x*.50+.009,y*.35,1.811),(.020,.018,1.810)]
        tube('Swept_hair',path,[.003,.0055,.005,.0015],hair,'Head',sides=7)
    for s in [-1,1]:
        tube('Sideburn',[(s*.082,.014,1.751),(s*.087,.006,1.715),(s*.080,.001,1.687)],[.010,.009,.003],hair,'Head',sides=8)
    if kind in ['merchant','healer']:
        for j in range(9):
            x=(j-4)*.017
            tube('Tied_back_hair',[(x,.071,1.765),(x*.8,.092,1.68),(x*.45,.095,1.596)],[.016,.015,.006],hair,'Head',sides=7)
        oval('Hair_tie',(0,.102,1.61),(.039,.016,.012),lip,'Head',16,8)


def blend_weights(z,pivot,upper,lower,width=.07):
    weight=max(0,min(1,(z-pivot)/width+.5))
    return {upper:weight,lower:1-weight}


def weight_garment_hem(obj, upper=1.04, lower=.91):
    # Cloth below the belt follows the corresponding thigh rather than clipping
    # through it during a forward step. The centre blends both legs smoothly.
    torso=obj.vertex_groups.get('Torso')
    left=obj.vertex_groups.new(name='Thigh_L')
    right=obj.vertex_groups.new(name='Thigh_R')
    for vertex in obj.data.vertices:
        amount=max(0,min(1,(upper-vertex.co.z)/(upper-lower)))
        if amount==0: continue
        split=max(0,min(1,.5+vertex.co.x/.08))
        torso.add([vertex.index],1-amount,'REPLACE')
        left.add([vertex.index],amount*(1-split),'REPLACE')
        right.add([vertex.index],amount*split,'REPLACE')
    return obj


def outfit(kind,m):
    skin,cloth,trim,leather,metal,dark=m['skin'],m['cloth'],m['trim'],m['leather'],m['metal'],m['dark']
    rings('Neck',[(1.46,.052,.048,0),(1.51,.050,.046,0),(1.565,.047,.043,0)],skin,'Head',sides=20)
    # The fitted torso is one contiguous garment; shaped shoulders and waist.
    torso_rows=[(.905,.175,.112,0),(.94,.181,.119,0),(1.00,.179,.121,0),(1.07,.165,.115,0),
                (1.15,.169,.119,0),(1.25,.190,.125,0),(1.35,.213,.126,0),(1.43,.237,.112,0),
                (1.47,.219,.095,0),(1.492,.118,.070,0),(1.51,.062,.050,0)]
    weight_garment_hem(rings('Tailored_linen_tunic',torso_rows,cloth,folds=.012))
    rings('Standing_collar',[(1.485,.072,.055,0),(1.525,.059,.050,0)],trim,sides=24)
    weight_garment_hem(rings('Woven_hem',[(.906,.178,.115,0),(.928,.181,.119,0)],trim))
    rings('Waist_belt',[(1.035,.184,.129,0),(1.084,.177,.126,0)],leather)
    cube('Buckle',(0,-.135,1.06),(.047,.016,.043),metal,bevel=.007)
    cube('Buckle_inner',(0,-.145,1.06),(.030,.005,.027),dark,bevel=.003)
    seam('Collar_placket',[(0,-.057,1.51),(0,-.096,1.45),(0,-.128,1.34)],trim,width=.004)
    for z in [1.37,1.41,1.45]: oval('Tunic_button',(0,-.13 if z==1.37 else -.12,z),(.004,.003,.004),metal,sides=10,rings_count=6)
    for s in [-1,1]:
        # Continuous bent sleeve, skin weights smoothly span the elbow.
        path=[(s*.185,0,1.44),(s*.230,0,1.418),(s*.269,0,1.35),(s*.294,0,1.26),(s*.310,0,1.19),
              (s*.326,-.005,1.11),(s*.337,-.012,1.035),(s*.344,-.018,.979)]
        tube('Fitted_sleeve',path,[.035,.072,.071,.061,.055,.055,.048,.040],cloth,sides=18,
             weights_fn=lambda z,s=s: blend_weights(z,1.19,'UpperArm_'+('L' if s<0 else 'R'),'Forearm_'+('L' if s<0 else 'R')))
        tag='L' if s<0 else 'R'
        tube('Sleeve_cuff',[(s*.341,-.017,.997),(s*.345,-.018,.968)],[.045,.043],leather,'Forearm_'+tag,sides=16)
        # Palm, thumb and four fingers have human scale and rest naturally.
        oval('Palm',(s*.345,-.02,.927),(.033,.020,.045),skin,'Hand_'+tag,16,10)
        for finger,length in enumerate([.048,.056,.052,.041]):
            fx=s*.345+(finger-1.5)*.015
            tube('Finger',[(fx,-.021,.905),(fx,-.027,.905-length*.55),(fx,-.032,.905-length)],
                 [.008,.007,.0045],skin,'Hand_'+tag,sides=8)
        tube('Thumb',[(s*.320,-.02,.945),(s*.306,-.028,.925),(s*.312,-.036,.910)],[.011,.009,.006],skin,'Hand_'+tag,sides=9)
        x=s*.108
        path=[(x,0,1.00),(x,0,.94),(x,-.002,.83),(x,-.008,.70),(x,-.012,.58),
              (x,-.009,.53),(x,.005,.44),(x,.012,.31),(x,.005,.19)]
        widths=[(.101,.105),(.104,.11),(.092,.096),(.077,.080),(.065,.069),(.065,.068),(.068,.073),(.054,.062),(.042,.046)]
        tube('Tailored_trousers',path,widths,trim,sides=18,
             weights_fn=lambda z,tag=tag:blend_weights(z,.56,'Thigh_'+tag,'Shin_'+tag,.10))
        tube('Boot_shaft',[(x,0,.12),(x,.006,.20),(x,.01,.30),(x,.01,.34)],
             [(.048,.055),(.052,.061),(.062,.068),(.065,.07)],leather,'Shin_'+tag,sides=18)
        oval('Boot_vamp',(x,-.055,.09),(.057,.127,.067),leather,'Foot_'+tag,20,10)
        cube('Boot_sole',(x,-.056,.026),(.118,.25,.035),dark,'Foot_'+tag,bevel=.012)
        cube('Stacked_heel',(x,.025,.039),(.102,.079,.050),dark,'Foot_'+tag,bevel=.008)
        for z in [.20,.265,.327]:
            tube('Boot_strap',[(x-.054,-.052,z),(x,-.064,z),(x+.054,-.052,z)],[.008]*3,dark,'Shin_'+tag,sides=6)
            cube('Boot_strap_buckle',(x+s*.047,-.048,z),(.018,.012,.020),metal,'Shin_'+tag,bevel=.002)
        seam('Trouser_outer_seam',[(x+s*.094,.005,.91),(x+s*.075,.0,.72),(x+s*.063,.003,.57)],leather,'Thigh_'+tag,.002)
        seam('Sleeve_stitching',[(s*.264,-.052,1.36),(s*.289,-.05,1.28),(s*.312,-.053,1.205)],trim,'UpperArm_'+tag,.002)
    # Role equipment changes silhouettes and visually explains village professions.
    if kind=='farmer':
        apron_verts=[(-.13,-.126,1.34),(.13,-.126,1.34),(-.16,-.144,1.04),(.16,-.144,1.04),(-.18,-.13,.84),(.18,-.13,.84)]
        weight_garment_hem(surface('Leather_work_apron',apron_verts,[(0,2,3,1),(2,4,5,3)],leather,uvs=[(0,1),(1,1),(0,.5),(1,.5),(0,0),(1,0)]))
        for s in [-1,1]:
            seam('Apron_strap',[(s*.13,-.13,1.34),(s*.15,-.105,1.43),(s*.15,-.07,1.48)],leather,width=.012)
            weight_garment_hem(seam('Apron_edge',[(s*.13,-.129,1.34),(s*.16,-.147,1.04),(s*.18,-.133,.84)],trim,width=.002))
        cube('Apron_pocket',(0,-.151,1.05),(.19,.012,.11),dark,bevel=.01)
    elif kind=='merchant':
        weight_garment_hem(rings('Brocade_waistcoat',[(.96,.184,.125,0),(1.08,.178,.129,0),(1.25,.199,.134,0),(1.42,.235,.118,0)],leather,folds=.008))
        for s in [-1,1]:
            seam('Vest_braid',[(s*.10,-.11,1.42),(s*.06,-.137,1.28),(s*.045,-.139,1.06),(s*.08,-.135,.98)],metal,width=.003)
        for z in [1.13,1.19,1.25]: oval('Vest_button',(0,-.140,z),(.006,.003,.006),metal,sides=10,rings_count=6)
    elif kind=='healer':
        seam('Satchel_shoulder_strap',[(-.20,-.087,1.44),(-.08,-.137,1.29),(.07,-.139,1.12),(.20,-.10,1.0)],leather,width=.015)
        cube('Herbalist_satchel',(.21,-.012,.99),(.13,.13,.17),leather,bevel=.020)
        cube('Satchel_flap',(.21,-.088,1.025),(.14,.02,.08),dark,bevel=.01)
        for i in range(3):
            tube('Herbalist_vial',[(.15+i*.041,-.087,1.02),(.15+i*.041,-.087,1.095)],[.013,.011],m['glass'],sides=12)
            cube('Cork',(.15+i*.041,-.087,1.10),(.019,.019,.015),trim,bevel=.002)
    elif kind=='guard':
        # Fitted cuirass, layered shoulder plates, rivets and leather bracers.
        rings('Steel_cuirass',[(1.11,.180,.128,0),(1.23,.199,.139,0),(1.34,.219,.136,0),(1.42,.232,.119,0)],metal,sides=32)
        for s,tag in [(-1,'L'),(1,'R')]:
            for i in range(3):
                oval('Shoulder_lamella',(s*(.225+i*.022),-.003,1.46-i*.025),(.061,.092,.027),metal,'UpperArm_'+tag,16,8)
            tube('Leather_bracer',[(s*.326,-.005,1.115),(s*.342,-.017,1.005)],[.063,.049],leather,'Forearm_'+tag,sides=16)
            for z in [1.14,1.23,1.32,1.40]:
                oval('Cuirass_rivet',(s*.16,-.10,z),(.004,.004,.004),dark,sides=8,rings_count=6)
        seam('Cuirass_centre_ridge',[(0,-.134,1.11),(0,-.144,1.25),(0,-.140,1.37)],dark,width=.003)
    # Shared stitched belt purse and knife sheath.
    cube('Belt_purse',(-.19,-.047,1.018),(.095,.087,.10),leather,bevel=.018)
    cube('Purse_flap',(-.19,-.094,1.045),(.102,.012,.05),dark,bevel=.01)
    oval('Purse_clasp',(-.19,-.103,1.038),(.006,.003,.007),metal,sides=10,rings_count=6)
    tube('Utility_knife_sheath',[(.185,.063,1.057),(.185,.063,.89)],[.023,.012],dark,sides=10)
    tube('Knife_grip',[(.185,.063,1.055),(.185,.063,1.12)],[.015,.014],leather,sides=10)


def animate():
    scene=bpy.context.scene; scene.render.fps=30
    RIG.animation_data_create()
    clips={'Idle':(60,True),'Walk':(30,True),'Run':(22,True),'Attack':(27,False)}
    for name,(last,loop) in clips.items():
        action=bpy.data.actions.new(name)
        action.use_fake_user=True
        RIG.animation_data.action=action
        for frame in range(1,last+1,2):
            scene.frame_set(frame)
            phase=(frame-1)/(last-1)*TAU
            for pb in RIG.pose.bones:
                pb.rotation_quaternion=(1,0,0,0); pb.location=(0,0,0)
            if name=='Idle':
                RIG.pose.bones['Torso'].rotation_quaternion=Quaternion((1,0,0),math.sin(phase)*.009)
                RIG.pose.bones['Head'].rotation_quaternion=Quaternion((0,1,0),math.sin(phase)*.025)
            elif name in ['Walk','Run']:
                amp=.34 if name=='Walk' else .61
                knee=.52 if name=='Walk' else 1.0
                for s,tag in [(1,'L'),(-1,'R')]:
                    stride=math.sin(phase+(0 if s==1 else math.pi))
                    RIG.pose.bones['Thigh_'+tag].rotation_quaternion=Quaternion((1,0,0),stride*amp)
                    RIG.pose.bones['Shin_'+tag].rotation_quaternion=Quaternion((1,0,0),max(0,stride)*knee)
                    RIG.pose.bones['Foot_'+tag].rotation_quaternion=Quaternion((1,0,0),-max(0,stride)*.24)
                    RIG.pose.bones['UpperArm_'+tag].rotation_quaternion=Quaternion((1,0,0),-stride*amp*.65)
                    RIG.pose.bones['Forearm_'+tag].rotation_quaternion=Quaternion((1,0,0),.20 if name=='Walk' else .65)
                RIG.pose.bones['Torso'].rotation_quaternion=Quaternion((0,1,0),math.sin(phase)*.035)
                # Ground the lowest sole at every authored key. Root local +Y is
                # Blender world +Z; using local Z would wrongly bob forward.
                bpy.context.view_layer.update()
                body=next(obj for obj in scene.objects if obj.type=='MESH')
                evaluated=body.evaluated_get(bpy.context.evaluated_depsgraph_get())
                mesh=evaluated.to_mesh()
                lowest=min((evaluated.matrix_world@vertex.co).z for vertex in mesh.vertices)
                evaluated.to_mesh_clear()
                RIG.pose.bones['Root'].location.y=.0085-lowest
            else:
                t=(frame-1)/(last-1)
                wind=math.sin(min(1,t/.43)*math.pi/2)
                cut=max(0,min(1,(t-.43)/.28))
                recovery=max(0,min(1,(t-.72)/.28))
                angle=(-1.2*wind+1.8*cut)*(1-recovery)
                RIG.pose.bones['UpperArm_R'].rotation_quaternion=Quaternion((1,0,0),angle)
                RIG.pose.bones['Forearm_R'].rotation_quaternion=Quaternion((1,0,0),.45*wind*(1-recovery))
                RIG.pose.bones['Torso'].rotation_quaternion=Quaternion((0,1,0),(-.22*wind+.35*cut)*(1-recovery))
                RIG.pose.bones['UpperArm_L'].rotation_quaternion=Quaternion((1,0,0),-.25*wind*(1-recovery))
            for pb in RIG.pose.bones:
                pb.keyframe_insert(data_path='rotation_quaternion',frame=frame,group=pb.name)
                if pb.name=='Root': pb.keyframe_insert(data_path='location',frame=frame,group=pb.name)
        # Exact closed loop endpoints (odd/even clip lengths both supported).
        for curve in action.fcurves:
            curve.keyframe_points.insert(last, curve.evaluate(1 if loop else last-1))
            for point in curve.keyframe_points: point.interpolation='LINEAR'
        track=RIG.animation_data.nla_tracks.new(); track.name=name
        strip=track.strips.new(name,1,action); strip.name=name
        track.mute=True
    RIG.animation_data.action=None
    for pb in RIG.pose.bones: pb.rotation_quaternion=(1,0,0,0); pb.location=(0,0,0)
    scene.frame_set(1)
    return clips


PALETTES={
 'farmer':dict(skin=(.48,.30,.20),lips=(.25,.115,.08),hair=(.11,.065,.038),cloth=(.19,.25,.17),trim=(.43,.38,.28),leather=(.22,.13,.071),eyes=(.18,.23,.14)),
 'merchant':dict(skin=(.66,.45,.30),lips=(.37,.17,.12),hair=(.19,.08,.035),cloth=(.23,.16,.23),trim=(.45,.37,.24),leather=(.28,.17,.10),eyes=(.14,.21,.23)),
 'healer':dict(skin=(.59,.36,.24),lips=(.33,.14,.10),hair=(.07,.047,.038),cloth=(.13,.22,.23),trim=(.40,.40,.31),leather=(.22,.16,.10),eyes=(.24,.20,.14)),
 'guard':dict(skin=(.39,.235,.16),lips=(.22,.09,.065),hair=(.045,.038,.031),cloth=(.18,.20,.18),trim=(.35,.29,.21),leather=(.18,.10,.055),eyes=(.12,.19,.18))
}


def build(kind,palette):
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    for action in list(bpy.data.actions): bpy.data.actions.remove(action)
    armature()
    m={}
    for label,surface_kind in [('skin','skin'),('hair','hair'),('cloth','cloth'),('trim','cloth'),('leather','leather')]:
        m[label]=material(kind+'_'+label,palette[label],surface_kind)
    m['lip']=material(kind+'_lips',palette['lips'],None,.78)
    m['dark']=material(kind+'_dark_leather',(.055,.042,.028),'leather',.8)
    m['metal']=material(kind+'_aged_steel',(.30,.32,.31),'metal',.42,.72)
    m['eye']=material(kind+'_eye_white',(.58,.59,.52),None,.32)
    m['iris']=material(kind+'_iris',palette['eyes'],None,.27)
    m['black']=material(kind+'_pupil',(.009,.011,.008),None,.26)
    m['glass']=material(kind+'_ceramic',(.17,.27,.21),None,.34)
    face(m['skin'],m['lip'],m['hair'],m['eye'],m['iris'],m['black'],kind)
    outfit(kind,m)
    bpy.ops.object.select_all(action='DESELECT')
    meshes=[obj for obj in bpy.context.scene.objects if obj.type=='MESH']
    for obj in meshes: obj.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0]
    bpy.ops.object.join(); body=bpy.context.object; body.name=kind+'_body'
    # Recalculate authored winding and normals for consistent viewport lighting.
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT'); bpy.ops.mesh.normals_make_consistent(inside=False); bpy.ops.object.mode_set(mode='OBJECT')
    clips=animate()
    body.data.calc_loop_triangles()
    triangles=len(body.data.loop_triangles)
    bounds=[list(min(v.co[i] for v in body.data.vertices) for i in range(3)),list(max(v.co[i] for v in body.data.vertices) for i in range(3))]
    bpy.context.scene['asset_note']='Original authored adult humanoid. Front -Y. Godot export front -Z.'
    bpy.context.scene['asset_version']='0.3.0'
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(kind+'.blend')),compress=True)
    # glTF Y-up conversion maps Blender -Y to +Z; rotate only the export root.
    RIG.rotation_euler.z=math.pi
    bpy.ops.object.select_all(action='SELECT')
    bpy.context.view_layer.objects.active=RIG
    target=OUT/(kind+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_yup=True,
                             export_animations=True,export_animation_mode='ACTIONS',export_nla_strips=True,
                             export_all_influences=False,export_force_sampling=True)
    print('CHARACTER_EXPORT',kind,'triangles',triangles,'bytes',target.stat().st_size,flush=True)
    return dict(triangles=triangles,bounds=bounds,animations=clips,file=target.name)


if __name__=='__main__':
    metadata={kind:build(kind,palette) for kind,palette in PALETTES.items()}
    (SOURCE/'manifest.json').write_text(json.dumps(metadata,indent=2)+'\n')
