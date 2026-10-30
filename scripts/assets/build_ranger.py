"""Original ranger v1. Rebuild with Blender 4.3.2 --background --python this_file.
All geometry, palette and animation are authored here; no KayKit geometry or clips.
Blender: Z up, -Y forward. glTF export: Y up, +Z forward, metre units.
"""
import bpy, math, json, pathlib, sys, struct
from mathutils import Vector, Quaternion, Matrix
from math import sin, cos, pi
ROOT = pathlib.Path(__file__).resolve().parents[2]
FACE_SAMPLE = '--face-sample' in sys.argv
ASSET_NAME = 'Ranger_FaceSample' if FACE_SAMPLE else 'Ranger_Original'
OUT = ROOT / ('art/ranger-face-sample' if FACE_SAMPLE else 'art/ranger')
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.render.fps = 30
PARTS=[]
# One opaque atlas material, 16 broad colour regions; no alpha, normal maps or runtime baking.
PALETTE=[('#EAB18B','skin'),('#BD795B','skin_shadow'),('#FFF0CF','ivory'),('#315268','trousers'),
         ('#237C8C','teal'),('#164653','teal_shadow'),('#B67A3C','copper'),('#67402E','leather'),
         ('#2B1C18','hair'),('#37251C','hair_lit'),('#1C2430','ink'),('#F7F2DF','eye'),
         ('#7B4930','iris'),('#71838D','steel'),('#A65349','lip'),('#C6A270','stitch')]
tex=bpy.data.images.new('Ranger_Atlas_512',width=512,height=512,alpha=False)
pixels=[]
def srgb(v): return v/12.92 if v < .04045 else ((v+.055)/1.055)**2.4
for y in range(512):
 for x in range(512):
  col=PALETTE[(y//128)*4+x//128][0]; c=[int(col[i:i+2],16)/255 for i in (1,3,5)]
  # Subtle authored value ramp; no noisy fabric normal/detail maps at combat scale.
  gain=.94+.09*(y%128)/127
  pixels.extend([min(1,v*gain) for v in c]+[1])
tex.pixels=pixels; tex.filepath_raw=str(OUT/'Ranger_Atlas_512.png');tex.file_format='PNG';tex.save();tex.pack()
mat=bpy.data.materials.new('Ranger_Original_Atlas');mat.use_nodes=True
bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Roughness'].default_value=.82
im=mat.node_tree.nodes.new('ShaderNodeTexImage');im.image=tex
mat.node_tree.links.new(im.outputs['Color'],bs.inputs['Base Color'])

def finish(obj,color,bone,weights=None,smooth=True):
 bpy.context.view_layer.objects.active=obj;obj.select_set(True)
 if obj.type!='MESH': bpy.ops.object.convert(target='MESH');obj=bpy.context.object
 bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 obj.data.materials.clear();obj.data.materials.append(mat)
 uv=obj.data.uv_layers.new(name='UVMap') if not obj.data.uv_layers else obj.data.uv_layers.active
 zs=[v.co.z for v in obj.data.vertices];lo=min(zs);height=max(max(zs)-lo,.001)
 for polygon in obj.data.polygons:
  polygon.use_smooth=smooth
  for li in polygon.loop_indices:
   v=obj.data.vertices[obj.data.loops[li].vertex_index]
   uv.data[li].uv=((color%4+.5)/4,(color//4+.25+.5*(v.co.z-lo)/height)/4)
 groups={}
 for v in obj.data.vertices:
  values=weights(v.co) if weights else {bone:1}
  for name,w in values.items():
   if name not in groups: groups[name]=obj.vertex_groups.new(name=name)
   if w>1e-6: groups[name].add([v.index],w,'REPLACE')
 PARTS.append(obj);obj.select_set(False);return obj

def mesh(name,verts,faces,color,bone,weights=None,smooth=True):
 d=bpy.data.meshes.new(name);d.from_pydata(verts,[],faces);d.update()
 o=bpy.data.objects.new(name,d);scene.collection.objects.link(o);return finish(o,color,bone,weights,smooth)

def box(name,center,size,color,bone,bevel=.035,rotation=(0,0,0)):
 bpy.ops.mesh.primitive_cube_add(size=1,location=center);o=bpy.context.object;o.name=name;o.dimensions=size;o.rotation_euler=rotation
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  m=o.modifiers.new('Authored soft edges','BEVEL');m.width=bevel;m.segments=2
  bpy.ops.object.modifier_apply(modifier=m.name)
  m=o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL');m.keep_sharp=True
  bpy.ops.object.modifier_apply(modifier=m.name)
 return finish(o,color,bone)

def ellipsoid(name,center,size,color,bone,segments=16,rings=10):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=rings,radius=1,location=center)
 o=bpy.context.object;o.name=name;o.scale=size;return finish(o,color,bone)

def tube(name,points,radii,color,bone,segments=8,weights=None):
 if ('hair' in name.lower() or 'fringe' in name or 'Crown' in name) and len(points)>2:
  old=[Vector(p) for p in points]; oldr=radii; points=[]; radii=[]
  for i in range(len(old)-1):
   p0,p1,p2,p3=old[max(0,i-1)],old[i],old[i+1],old[min(len(old)-1,i+2)]
   for step in range(4):
    t=step/4
    points.append(.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t))
    radii.append(tuple(a*(1-t)+b*t for a,b in zip(oldr[i],oldr[i+1])))
  points.append(old[-1]);radii.append(oldr[-1]);segments=7
 verts=[]
 for i,p in enumerate(points):
  tangent=Vector(points[min(i+1,len(points)-1)])-Vector(points[max(0,i-1)])
  tangent.normalize();side=tangent.cross(Vector((0,1,0)))
  if side.length<.01:side=tangent.cross(Vector((0,0,1)))
  side.normalize();up=tangent.cross(side).normalized()
  radius=radii[i] if isinstance(radii,list) else radii
  r1,r2=radius if isinstance(radius,tuple) else (radius,radius)
  for n in range(segments):verts.append(Vector(p)+side*cos(n*2*pi/segments)*r1+up*sin(n*2*pi/segments)*r2)
 faces=[]
 for i in range(len(points)-1):
  for n in range(segments):
   a=i*segments+n;b=i*segments+(n+1)%segments;faces.append((a,b,b+segments,a+segments))
 faces+=[tuple(reversed(range(segments))),tuple((len(points)-1)*segments+n for n in range(segments))]
 return mesh(name,verts,faces,color,bone,weights)

def loft(name,rings,color,bone,segments=20,weights=None):
 # rings are (z, x-radius, y-radius, centre-y); intentionally shaped jaw/torso rather than scaled spheres.
 verts=[]
 for z,rx,ry,cy in rings:
  for i in range(segments):
   t=2*pi*i/segments;verts.append((rx*cos(t),cy+ry*sin(t),z))
 faces=[]
 for j in range(len(rings)-1):
  for i in range(segments):a=j*segments+i;b=j*segments+(i+1)%segments;faces.append((a,b,b+segments,a+segments))
 faces.extend([tuple(reversed(range(segments))),tuple((len(rings)-1)*segments+i for i in range(segments))])
 return mesh(name,verts,faces,color,bone,weights)

# An independent deform rig: ready-to-fire rest pose and explicit right-hand weapon / muzzle anchors.
bones={
 'root':((0,0,0),(0,0,.15),None),
 'hips':((0,0,1.0),(0,0,1.11),'root'),
 'spine':((0,0,1.08),(0,0,1.35),'hips'),
 'chest':((0,0,1.35),(0,0,1.58),'spine'),
 'head':((0,0,1.61),(0,0,2.12),'chest'),
 'cape':((0,.13,1.55),(0,.23,1.15),'chest'),
 'upperarm.r':((-.34,0,1.48),(-.43,-.10,1.21),'chest'),
 'lowerarm.r':((-.43,-.10,1.21),(-.12,-.38,1.30),'upperarm.r'),
 'hand.r':((-.12,-.38,1.30),(-.10,-.49,1.30),'lowerarm.r'),
 'handslot.r':((-.10,-.49,1.30),(-.10,-.69,1.30),'hand.r'),
 'upperarm.l':((.34,0,1.48),(.43,-.10,1.22),'chest'),
 'lowerarm.l':((.43,-.10,1.22),(.13,-.56,1.30),'upperarm.l'),
 'hand.l':((.13,-.56,1.30),(.10,-.65,1.30),'lowerarm.l'),
 'handslot.l':((.10,-.65,1.30),(.10,-.75,1.30),'hand.l'),
 'upperleg.r':((-.18,0,1.0),(-.19,-.015,.59),'hips'),
 'lowerleg.r':((-.19,-.015,.59),(-.19,0,.18),'upperleg.r'),
 'foot.r':((-.19,0,.18),(-.19,-.28,.12),'lowerleg.r'),
 'upperleg.l':((.18,0,1.0),(.19,-.015,.59),'hips'),
 'lowerleg.l':((.19,-.015,.59),(.19,0,.18),'upperleg.l'),
 'foot.l':((.19,0,.18),(.19,-.28,.12),'lowerleg.l'),
 'weapon.slide':((0,-.54,1.37),(0,-.74,1.37),'handslot.r'),
 'muzzle':((0,-.93,1.34),(0,-1.00,1.34),'handslot.r')}
if FACE_SAMPLE:
 # Lower and project the weapon cradle away from the chest; retain both grips.
 # Authored adjustment, not a measurement inferred from cropped reference video.
 cradle=Vector((0,-.12,-.09))
 for name in ['hand.r','handslot.r','hand.l','handslot.l','weapon.slide','muzzle']:
  head,tail,parent=bones[name]
  bones[name]=(tuple(Vector(head)+cradle),tuple(Vector(tail)+cradle),parent)
 for name in ['lowerarm.r','lowerarm.l']:
  head,tail,parent=bones[name]
  bones[name]=(head,tuple(Vector(tail)+cradle),parent)
 for side,x in [('r',-.123),('l',.123)]:
  bones['brow.'+side]=((x,-.23,2.08),(x,-.23,2.14),'head')
  bones['eye.'+side]=((x,-.24,1.978),(x,-.24,2.04),'head')
 bones['mouth']=((0,-.20,1.80),(0,-.20,1.86),'head')
arm=bpy.data.armatures.new('Ranger_Rig');rig=bpy.data.objects.new('Ranger_Rig',arm);scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
for name,(head,tail,parent) in bones.items():
 b=arm.edit_bones.new(name);b.head=head;b.tail=tail
 if parent:b.parent=arm.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT');rig.select_set(False)
for b in rig.pose.bones:b.rotation_mode='QUATERNION'

# Boots: grounded soles, toe boxes, cuff panels, straps. Compact accessories never exceed the shoulders.
for side,x in [('r',-.19),('l',.19)]:
 foot='foot.'+side;lower='lowerleg.'+side;upper='upperleg.'+side
 box('Boot sole '+side,(x,-.095,.055),(.265,.46,.11),10,foot,.035)
 box('Leather toe '+side,(x,-.125,.16),(.26,.43,.21),7,foot,.08)
 tube('Boot shaft '+side,[(x,.015,.15),(x,.01,.32),(x,-.008,.49)],[(.12,.13),(.12,.115),(.145,.125)],7,lower,12)
 tube('Boot cuff '+side,[(x,-.006,.42),(x,-.008,.51)],[(.157,.14),(.15,.13)],7,lower,12)
 box('Boot buckle '+side,(x,-.14,.31),(.12,.035,.075),6,lower,.014)
 box('Boot inset '+side,(x,-.16,.31),(.065,.015,.035),7,lower,.008)
 tube('Trouser leg '+side,[(x,0,.44),(x,-.02,.58),(x,0,.73),(x,0,.97)],[(.122,.115),(.133,.132),(.15,.14),(.165,.16)],3,upper,14,
      weights=lambda p,u=upper,l=lower:{u:min(1,max(0,(p.z-.51)/.22)),l:1-min(1,max(0,(p.z-.51)/.22))})
 # Seamed kneepad: broad, quiet shape, not a large metallic accessory.
 # The knee remains part of the continuous trouser mesh, without intersecting pads.
loft('Trousers waist',[(.88,.26,.17,0),(1.02,.28,.185,0),(1.09,.25,.16,0)],3,'hips',16)
# Tailored cream shirt and raised folded collar.
loft('Shirt',[(1.02,.25,.16,0),(1.13,.27,.18,0),(1.32,.30,.185,0),(1.48,.34,.16,0),(1.57,.19,.105,0)],2,'chest',20,
 weights=lambda p:{'spine':max(0,min(1,(1.35-p.z)/.3)), 'chest':1-max(0,min(1,(1.35-p.z)/.3))})
ellipsoid('Neck',(0,0,1.62),(.115,.105,.15),0,'head')
for x in [-.1,.1]:
 box('Collar',(x,-.10,1.58),(.13,.07,.15),2,'chest',.02,(0,(-1 if x<0 else 1)*.28,0))
# Cross-body leather sash and the utility belt.
tube('Chest harness',[(.23,-.14,1.51),(.12,-.195,1.39),(-.04,-.198,1.23),(-.20,-.175,1.09)],[(.054,.017)]*4,7,'chest',8)
box('Harness buckle',(.085,-.222,1.35),(.115,.035,.105),6,'chest',.015,(0,-.55,0))
loft('Belt',[(1.01,.285,.20,0),(1.10,.285,.20,0)],7,'hips',20)
box('Belt buckle',(0,-.214,1.055),(.15,.045,.10),6,'hips',.018)
box('Belt buckle inset',(0,-.24,1.055),(.09,.012,.053),10,'hips',.007)
for x in [-.29,.29]:
 box('Belt pouch',(x,-.045,1.00),(.16,.17,.20),7,'hips',.035,(0,.10 if x<0 else -.10,0))
 box('Pouch flap',(x,-.138,1.045),(.17,.034,.09),6,'hips',.02)
 ellipsoid('Pouch stud',(x,-.162,1.045),(.016,.01,.016),15,'hips',10,6)
# A short, directional mantle: front opening clear, back below shoulders only.
verts=[];segs=24
for row in range(4):
 for i in range(segs+1):
  a=-pi*.83+i/segs*pi*1.66
  # opening towards -Y; back drapes to 1.23, sides 1.38.
  radii=[.15,.27,.40,.48];r=radii[row]
  x=sin(a)*r; y=cos(a)*r*.52+.035
  z=[1.63,1.57,1.46,1.33][row]+(.09*abs(sin(a)) if row==3 else 0)
  verts.append((x,y,z))
faces=[]
for row in range(3):
 for i in range(segs):a=row*(segs+1)+i;faces.append((a,a+1,a+segs+2,a+segs+1))
cape=mesh('Short teal mantle',verts,faces,4,'cape')
bpy.context.view_layer.objects.active=cape;cape.select_set(True)
sol=cape.modifiers.new('Opaque cloth thickness','SOLIDIFY');sol.thickness=.018;bpy.ops.object.modifier_apply(modifier=sol.name);cape.select_set(False)
tube('Mantle piping',verts[-(segs+1):],.008,15,'cape',5)
ellipsoid('Folded hood',(0,.20,1.55),(.21,.16,.115),5,'cape',16,8)
tube('Hood seam',[(-.15,.23,1.61),(0,.34,1.53),(.15,.23,1.61)],.01,4,'cape',6)
box('Cloak clasp',(-.16,-.13,1.56),(.115,.045,.105),6,'chest',.018,(0,-.2,0))
# Sleeves, bracers, articulated hands; both support the same compact crossbow in the rest pose.
for side in ['r','l']:
 up='upperarm.'+side;low='lowerarm.'+side;hand='hand.'+side
 shoulder=Vector(bones[up][0]);elbow=Vector(bones[up][1]);wrist=Vector(bones[low][1]);tip=Vector(bones[hand][1])
 tube('Tailored rolled sleeve '+side,[shoulder.lerp(elbow,t) for t in [-.08,.05,.25,.56,.69,.74,.88,.93]],[(.01,.01),(.11,.10),(.144,.133),(.137,.12),(.12,.11),(.145,.132),(.14,.128),(.11,.105)],2,up,16)
 tube('Forearm '+side,[elbow,elbow.lerp(wrist,.35),wrist],[(.105,.10),(.10,.09),(.075,.075)],0,low,12)
 tube('Leather bracer '+side,[elbow.lerp(wrist,.32),elbow.lerp(wrist,.50),elbow.lerp(wrist,.88)],[(.112,.101),(.10,.09),(.091,.085)],7,low,12)
 tube('Bracer rim '+side,[elbow.lerp(wrist,.36),elbow.lerp(wrist,.44)],.115,6,low,10)
 ellipsoid('Glove '+side,wrist.lerp(tip,.65),(.09,.10,.075),7,hand,12,8)
 ellipsoid('Thumb '+side,wrist.lerp(tip,.6)+Vector((-.065 if side=='r' else .065,-.005,.048)),(.042,.07,.04),0,hand,10,6)
 for f in range(3):
  p=wrist.lerp(tip,.9)+Vector(((f-1)*.04,-.015,-.025))
  ellipsoid('Curled finger '+side,p,(.023,.047,.034),0,hand,8,6)
# Distinct rounded jaw, broad cheeks, nose bridge, small chin. Face is geometric and survives top-down.
loft('Face',[(1.66,.10,.10,-.025),(1.70,.18,.145,-.025),(1.78,.245,.19,0),(1.90,.283,.23,0),
             (2.03,.28,.235,.015),(2.15,.255,.22,.018),(2.23,.19,.17,.02),(2.26,.07,.075,.02)],0,'head',32)
for x in [-.283,.283]:
 ellipsoid('Ear',(x,.015,1.92),(.075,.064,.115),0,'head',14,10)
 ellipsoid('Ear inset',(x,-.038,1.92),(.042,.012,.069),1,'head',12,8)
# Eyes follow the face surface: almond patches with low-relief lids, no separate floating eyeballs.
for side,x in [('r',-.123),('l',.123)]:
 eye_bone='eye.'+side if FACE_SAMPLE else 'head'
 brow_bone='brow.'+side if FACE_SAMPLE else 'head'
 def eye_patch(name,cx,y,z,width,height,color):
  ps=[(cx-width/2,y+.015,z),(cx-width*.40,y+.001,z+height*.29),(cx-width*.20,y-.007,z+height*.46),(cx+width*.12,y-.008,z+height*.48),(cx+width*.35,y+.001,z+height*.32),(cx+width/2,y+.015,z),
      (cx+width*.32,y+.001,z-height*.29),(cx+width*.10,y-.008,z-height*.40),(cx-width*.20,y-.007,z-height*.36),(cx-width*.40,y+.001,z-height*.19)]
  ps.append((cx,y-.015,z));return mesh(name,ps,[(10,i,(i+1)%10) for i in range(10)],color,eye_bone)
 eye_patch('Eye lid '+side,x,-.212,1.978,.193,.105,8)
 eye_patch('Eye white '+side,x,-.221,1.978,.169,.083,11)
 ellipsoid('Iris '+side,(x+.007,-.244,1.978),(.034,.006,.039),12,eye_bone,16,8)
 ellipsoid('Pupil '+side,(x+.007,-.253,1.978),(.017,.004,.028),10,eye_bone,14,8)
 ellipsoid('Eye glint '+side,(x-.005,-.261,1.997),(.011,.005,.014),11,eye_bone,10,6)
 s=-1 if x<0 else 1
 tube('Expressive brow '+side,[(x-s*.09,-.218,2.062),(x,-.246,2.079),(x+s*.081,-.206,2.094)],[(.018,.021),(.024,.024),(.010,.012)],8,brow_bone,7)
# Low-poly shaped nose has actual bridge and soft wings, not a spherical button.
mesh('Nose', [(-.043,-.224,1.94),(.043,-.224,1.94),(-.045,-.236,1.865),(.045,-.236,1.865),
              (0,-.27,1.88),(0,-.24,1.965),(0,-.25,1.855)],
     [(0,1,5),(0,5,4),(5,1,4),(0,4,2),(4,1,3),(2,4,6),(4,3,6),(2,6,3)],0,'head')
tube('Smile',[(-.092,-.188,1.805),(-.032,-.202,1.792),(.035,-.205,1.794),(.102,-.189,1.817)],.0045,7,'mouth' if FACE_SAMPLE else 'head',6)
tube('Lower lip',[(-.042,-.196,1.779),(.01,-.201,1.778),(.053,-.194,1.786)],.004,14,'mouth' if FACE_SAMPLE else 'head',6)
# Sculpted hair cap and swept clumps, individually tapered silhouettes.
loft('Hair cap',[(1.96,.27,.23,.055),(2.08,.29,.25,.04),(2.22,.265,.245,.035),(2.30,.19,.18,.025),(2.33,.025,.025,.025)],8,'head',24)
# Sample refinement: five broad directional hair masses including the cap.
# Original geometry stays byte-for-byte reproducible in the comparison branch.
if FACE_SAMPLE:
 tube('Swept fringe broad',[(.17,-.075,2.28),(.075,-.21,2.285),(-.13,-.275,2.22),(-.265,-.23,2.10)],
      [(.13,.075),(.145,.065),(.12,.045),(.009,.008)],8,'head',9)
 tube('Swept fringe accent',[(.24,-.015,2.25),(.23,-.16,2.245),(.12,-.255,2.18),(.025,-.26,2.11)],
      [(.085,.06),(.10,.055),(.075,.038),(.006,.006)],9,'head',9)
 tube('Side hair sweep',[(-.16,.10,2.24),(-.285,.04,2.20),(-.34,.08,2.07),(-.31,.15,1.98)],
      [(.11,.075),(.12,.065),(.085,.045),(.008,.008)],8,'head',9)
 tube('Nape hair mass',[(.02,.18,2.18),(0,.28,2.06),(-.015,.265,1.93),(-.035,.21,1.85)],
      [(.23,.075),(.24,.07),(.18,.045),(.07,.014)],8,'head',10)
else:
 # Front fringe: swept from character left to right, clear brows and both eyes.
 for i in range(6):
  x=-.24+i*.087
  pts=[(x+.10,-.09,2.29-i*.003),(x+.055,-.205,2.27),(x-.035,-.267,2.20),(x-.065,-.255,2.095+(i%2)*.035)]
  tube('Swept fringe %d'%i,pts,[(.064,.048),(.078,.055),(.055,.036),(.003,.003)],9 if i in [1,4] else 8,'head',9)
 for side in [-1,1]:
  for i in range(4):
   pts=[(side*.16,.12-i*.05,2.24),(side*.28,.11-i*.06,2.21-i*.035),
        (side*(.335+i*.006),.15-i*.075,2.12-i*.048),(side*.345,.18-i*.06,2.14-i*.067)]
   tube('Side hair',pts,[(.075,.05),(.065,.042),(.033,.025),(.002,.002)],8 if i%2 else 9,'head',8)
  for i in range(3):
   x=side*(.08+i*.07)
   tube('Nape hair',[(x,.20,2.12),(x,.267,2.01),(x*.9,.23,1.85+(i*.022))],[(.08,.06),(.075,.04),(.002,.002)],8,'head',8)
 tube('Crown sweep',[(.02,.09,2.27),(-.06,.105,2.32),(-.14,.12,2.37),(-.20,.14,2.41)],[(.09,.07),(.07,.045),(.03,.025),(.001,.001)],9,'head',10)
# Crossbow: broad copper limbs, dark grip, central steel rail and visible release mechanism.
weapon='handslot.r'
box('Crossbow stock',(0,-.52,1.31),(.145,.49,.12),7,weapon,.03)
box('Crossbow rail',(0,-.65,1.38),(.068,.50,.046),13,weapon,.012)
box('Crossbow grip',(-.10,-.405,1.255),(.075,.10,.17),7,weapon,.022,(.18,0,0))
box('Crossbow foregrip',(0,-.69,1.305),(.16,.12,.085),6,weapon,.018)
for side in [-1,1]:
 tube('Copper bow limb',[(0,-.78,1.35),(side*.18,-.81,1.36),(side*.30,-.75,1.36),(side*.34,-.63,1.35)],[(.035,.044),(.035,.04),(.03,.034),(.021,.025)],6,weapon,8)
 box('Bow limb tip',(side*.34,-.63,1.35),(.058,.063,.075),13,weapon,.012)
 tube('Taut string',[(side*.34,-.63,1.35),(0,-.44,1.365)],.006,10,'weapon.slide',5,
      weights=lambda p:{weapon:min(1,max(0,abs(p.x)/.34)), 'weapon.slide':1-min(1,max(0,abs(p.x)/.34))})
tube('Loaded bolt',[(0,-.52,1.41),(0,-.91,1.41)],.011,13,'weapon.slide',6)
tube('Bolt head',[(0,-.87,1.41),(0,-.95,1.41)],[(.027,.02),(.001,.001)],13,'weapon.slide',6)
box('Trigger housing',(0,-.43,1.39),(.12,.09,.08),6,weapon,.012)
# Small hip bolt case opposite the firing hand; restrained silhouette.
box('Bolt case',(.31,.055,1.05),(.13,.15,.22),7,'hips',.03,(0,-.15,0))
for i in range(3):
 x=.265+i*.039
 tube('Spare bolt',[(x,.055,1.12),(x+.025,.055,1.28)],.012,13,'hips',6)
 box('Bolt fletching',(x+.024,.055,1.25),(.027,.05,.06),6,'hips',.004)

if FACE_SAMPLE:
 # Weapon geometry is authored in rest coordinates above; match the moved anchors.
 for part in PARTS:
  groups={g.name for g in part.vertex_groups}
  if groups and groups.issubset({'handslot.r','weapon.slide'}):
   for vertex in part.data.vertices: vertex.co += cradle

# Merge to a single skinned primitive / single material. Vertex groups are preserved.
bpy.ops.object.select_all(action='DESELECT')
for o in PARTS:o.select_set(True)
bpy.context.view_layer.objects.active=PARTS[0];bpy.ops.object.join();body=bpy.context.object;body.name='Ranger_Body'
# Unify duplicate slots created by joining; every face uses the same atlas.
body.data.materials.clear();body.data.materials.append(mat)
for p in body.data.polygons:p.material_index=0
# All normals oriented outwards before export; no double-sided bandaid.
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT')
mod=body.modifiers.new('Ranger skin','ARMATURE');mod.object=rig;body.parent=rig
# Source keeps the named mesh regions as vertex groups. Triangulation is export-only.
rig['asset_author']='Original geometry, rig, palette and clips authored for kriswu; procedural source build_ranger.py'
rig['forward']='Blender -Y / glTF +Z';rig['release_seconds']=0.0

# Dedicated actions. Game uses linear time for this rig, with no generic pose exaggeration.
rest={b.name:b.matrix_local.copy() for b in arm.bones}
def reset():
 for b in rig.pose.bones:b.location=(0,0,0);b.rotation_quaternion=(1,0,0,0);b.scale=(1,1,1)
def rotate(name,axis,angle):
 q=rest[name].to_quaternion();rig.pose.bones[name].rotation_quaternion=q.inverted()@Quaternion(Vector(axis),angle)@q

def translate_world(name,vec):
 rig.pose.bones[name].location=rest[name].to_quaternion().inverted()@Vector(vec)

def leg_ik(side,target,hip_drop):
 # Analytic two-link, sagittal knee-forward solution. Foot orientation stays level during contact.
 upper='upperleg.'+side;lower='lowerleg.'+side;foot='foot.'+side
 h=Vector(bones[upper][0])+Vector((0,0,hip_drop));t=Vector(target)
 l1=(Vector(bones[upper][1])-Vector(bones[upper][0])).length
 l2=(Vector(bones[lower][1])-Vector(bones[lower][0])).length
 d=(t-h).length;d=min(d,l1+l2-.001);direction=(t-h).normalized()
 a=(l1*l1-l2*l2+d*d)/(2*d);height=math.sqrt(max(0,l1*l1-a*a))
 bend=Vector((0,-1,0));bend=(bend-direction*bend.dot(direction)).normalized();k=h+direction*a+bend*height
 desired={upper:(h,k),lower:(k,t)}
 worldrot={}
 for name,(head,tail) in desired.items():
  q0=rest[name].to_quaternion();rvec=q0@Vector((0,1,0));q=rvec.rotation_difference((tail-head).normalized())@q0
  parent=arm.bones[name].parent
  parent_world=worldrot.get(parent.name,rest[parent.name].to_quaternion())
  local_rest=rest[parent.name].inverted()@rest[name]
  rig.pose.bones[name].rotation_quaternion=local_rest.to_quaternion().inverted()@parent_world.inverted()@q
  worldrot[name]=q
 local_rest=rest[lower].inverted()@rest[foot]
 rig.pose.bones[foot].rotation_quaternion=local_rest.to_quaternion().inverted()@worldrot[lower].inverted()@rest[foot].to_quaternion()

def pose(clip,t,duration):
 reset();u=t/duration
 if clip=='Ranger_Idle':
  rotate('chest',(1,0,0),sin(u*2*pi)*.012);rotate('head',(0,0,1),sin(u*2*pi)*.018)
  rotate('cape',(1,0,0),sin(u*2*pi+.4)*.025)
 elif clip=='Ranger_Run':
  drop=-.185+.010*cos(u*4*pi);translate_world('hips',(0,0,drop))
  for side,phase in [('r',u%1),('l',(u+.5)%1)]:
   if phase<.6:
    a=phase/.6; y=-.48+.96*a;lift=0
   else:
    a=(phase-.6)/.4;y=.48-.96*a;lift=.19*sin(pi*a)
   x=bones['foot.'+side][0][0];leg_ik(side,(x,y,.18+lift),drop)
  rotate('chest',(0,0,1),sin(u*2*pi)*.035);rotate('cape',(1,0,0),.12+sin(u*2*pi)*.07)
 elif clip in ['Ranger_Shoot','Ranger_Skill']:
  strength=1 if clip=='Ranger_Shoot' else 1.7
  # Release is at t=0, recoil peaks at ~40 ms; no delayed projectile after an anticipation pose.
  kick=max(0,sin(min(t/.15,1)*pi))*strength
  rotate('chest',(1,0,0),-.055*kick);rotate('upperarm.r',(1,0,0),-.11*kick)
  rotate('upperarm.l',(1,0,0),-.095*kick);rotate('lowerarm.r',(0,0,1),-.045*kick)
  rotate('head',(1,0,0),.04*kick);rotate('cape',(1,0,0),.10*kick)
  translate_world('weapon.slide',(0,-.19*max(0,1-t/.12),0))
 elif clip=='Hit_A':
  kick=sin(pi*u)*(1-u);rotate('chest',(1,0,0),-.20*kick);rotate('head',(0,1,0),.13*kick)
 elif clip=='1H_Ranged_Reload':
  wave=sin(pi*u);rotate('lowerarm.l',(0,0,1),-.52*wave);rotate('hand.l',(1,0,0),.25*wave)
  rotate('upperarm.l',(1,0,0),-.17*wave);rotate('head',(1,0,0),.10*wave)
  translate_world('weapon.slide',(0,.07*wave,0))
 elif clip=='Death_A':
  a=min(1,u/.8);e=a*a*(3-2*a)
  rotate('hips',(1,0,0),-pi*.43*e);translate_world('hips',(0,.10*e,-.70*e))
  rotate('upperleg.r',(1,0,0),.6*e);rotate('upperleg.l',(1,0,0),.75*e)
  rotate('lowerleg.r',(1,0,0),-.8*e);rotate('lowerleg.l',(1,0,0),-.7*e)
  rotate('chest',(0,1,0),.18*e);rotate('head',(0,0,1),.15*e)
 elif clip=='Cheer':
  wave=sin(pi*u)**2;rotate('chest',(0,0,1),.08*sin(u*2*pi))
  rotate('upperarm.r',(1,0,0),-.55*wave);rotate('upperarm.l',(0,0,1),-.3*wave)
  rotate('head',(1,0,0),-.07*wave);rotate('cape',(1,0,0),.08*wave)

 # Bone-only facial compatibility sample: all channels use the existing TRS loader.
 if FACE_SAMPLE:
  blink=max(0,1-abs(u-.72)/.055) if clip=='Ranger_Idle' else 0
  focus=max(0,1-u) if clip in ['Ranger_Shoot','Ranger_Skill'] else 0
  hurt=sin(pi*u) if clip=='Hit_A' else 0
  joy=sin(pi*u)**2 if clip=='Cheer' else 0
  for side,sign in [('r',-1),('l',1)]:
   rotate('brow.'+side,(0,1,0),sign*(.18*focus+.12*hurt-.12*joy))
   rig.pose.bones['eye.'+side].scale=(1,max(.08,1-.92*blink-.35*hurt),1)
  translate_world('mouth',(0,0,.018*joy-.01*hurt))

actions=[('Ranger_Idle',2.4),('Ranger_Run',.6666667),('Ranger_Shoot',.32),('Ranger_Skill',.62),
         ('Hit_A',.24),('1H_Ranged_Reload',.65),('Death_A',.8),('Cheer',1.6)]
rig.animation_data_create()
for name,duration in actions:
 action=bpy.data.actions.new(name);rig.animation_data.action=action
 frames=max(2,round(duration*30))
 for i in range(frames+1):
  pose(name,duration*i/frames,duration)
  frame=i+1
  for b in rig.pose.bones:
   b.keyframe_insert('rotation_quaternion',frame=frame,group=b.name)
   if b.name in ['hips','weapon.slide'] or (FACE_SAMPLE and b.name=='mouth'):b.keyframe_insert('location',frame=frame,group=b.name)
   if FACE_SAMPLE and b.name.startswith('eye.'):b.keyframe_insert('scale',frame=frame,group=b.name)
 for curve in action.fcurves:
  for k in curve.keyframe_points:k.interpolation='LINEAR'
 action.use_fake_user=True
rig.animation_data.action=None;reset();scene.frame_set(1)
# Export only the actual asset, not the QA stage/cameras/lights.
bpy.ops.object.select_all(action='DESELECT');body.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig
path=ROOT/'App/Arena3D'/f'{ASSET_NAME}.glb'
bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
 export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,
 export_force_sampling=True,export_optimize_animation_size=True,
 export_yup=True,export_apply=False,export_skins=True,export_all_influences=False,
 export_extras=True,export_materials='EXPORT',export_image_format='AUTO')
# Remove only channels identical to the bind pose. Keep constant non-rest poses.
# This avoids sampling root/anchor transforms and scale tracks every frame on iOS.
raw=path.read_bytes();length=struct.unpack_from('<I',raw,12)[0]
gltf=json.loads(raw[20:20+length]);binary=raw[28+length:]
def values(index):
 a=gltf['accessors'][index];v=gltf['bufferViews'][a['bufferView']];width={'SCALAR':1,'VEC3':3,'VEC4':4}[a['type']]
 off=v.get('byteOffset',0)+a.get('byteOffset',0)
 return [struct.unpack_from('<'+'f'*width,binary,off+i*width*4) for i in range(a['count'])]
for animation in gltf['animations']:
 kept=[]
 for channel in animation['channels']:
  target=channel['target']; node=gltf['nodes'][target['node']]; prop=target['path']
  default=node.get(prop,{'translation':[0,0,0],'rotation':[0,0,0,1],'scale':[1,1,1]}[prop])
  output=values(animation['samplers'][channel['sampler']]['output'])
  if not all(max(abs(a-b) for a,b in zip(row,default))<1e-6 for row in output):kept.append(channel)
 animation['channels']=kept
json_bytes=json.dumps(gltf,separators=(',',':')).encode();json_bytes+=b' '*((-len(json_bytes))%4)
path.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(json_bytes)+len(binary))+struct.pack('<I4s',len(json_bytes),b'JSON')+json_bytes+struct.pack('<I4s',len(binary),b'BIN\0')+binary)
# Editable source includes original topology / UVs / groups and every action.
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/f'{ASSET_NAME}.blend'), compress=True)

# Actual asset renders; never labelled game screenshots. CPU Cycles is reproducible headlessly.
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=32
scene.cycles.use_denoising=True;scene.render.resolution_x=720;scene.render.resolution_y=900;scene.render.resolution_percentage=100
if '--quick-qa' in sys.argv:
 scene.cycles.samples=16;scene.render.resolution_percentage=67
scene.render.image_settings.file_format='JPEG';scene.render.image_settings.quality=92
scene.world.color=(.22,.22,.22)
scene.view_settings.view_transform='Standard';scene.view_settings.look='Medium High Contrast';scene.view_settings.exposure=0;scene.view_settings.gamma=1
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.015));floor=bpy.context.object
floor_mat=bpy.data.materials.new('QA floor');floor_mat.diffuse_color=(.12,.105,.17,1);floor.data.materials.append(floor_mat)
def area(name,loc,power,size,color):
 d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=size;d.color=color
 o=bpy.data.objects.new(name,d);scene.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,0,1.2))-o.location).to_track_quat('-Z','Y').to_euler()
area('Soft key',(-3,-4,6),450,4,(1,.88,.74));area('Cool fill',(3,-2,3.5),230,3,(.73,.85,1));area('Rim',(1,3,4.5),380,3,(.74,.83,1))
d=bpy.data.cameras.new('QA camera');cam=bpy.data.objects.new('QA camera',d);scene.collection.objects.link(cam);scene.camera=cam;d.type='ORTHO';d.ortho_scale=2.85
if '--no-render' not in sys.argv:
 for label,loc in [('front',(0,-6,2.0)),('side',(6,0,1.7)),('back',(0,6,2.0)),('combat',(3,-5,7.0))]:
  cam.location=loc;target=Vector((0,-.08,1.19));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
  scene.render.filepath=str(OUT/f'model-{label}.jpg');bpy.ops.render.render(write_still=True)
 if FACE_SAMPLE:
  cam.location=(0,-6,2.0);cam.rotation_euler=(Vector((0,-.08,1.19))-cam.location).to_track_quat('-Z','Y').to_euler()
  for name,fraction in [('Ranger_Idle',.72),('Ranger_Shoot',0),('Cheer',.5)]:
   action=bpy.data.actions.get(name);rig.animation_data.action=action
   start,end=action.frame_range;scene.frame_set(int(start+(end-start)*fraction))
   scene.render.filepath=str(OUT/f'face-{name}.jpg');bpy.ops.render.render(write_still=True)
 if '--motions' in sys.argv:
  cam.location=(3,-5,4.8);cam.rotation_euler=(Vector((0,0,1.15))-cam.location).to_track_quat('-Z','Y').to_euler()
  for name,fraction in [('Ranger_Run',.15),('Ranger_Run',.75),('Ranger_Shoot',.15),('1H_Ranged_Reload',.5),('Death_A',1.0)]:
   action=bpy.data.actions.get(name);rig.animation_data.action=action
   start,end=action.frame_range;scene.frame_set(int(start+(end-start)*fraction))
   scene.render.filepath=str(OUT/f'pose-{name}-{fraction}.jpg');bpy.ops.render.render(write_still=True)
print('RANGER_ASSET_READY',path,flush=True)
