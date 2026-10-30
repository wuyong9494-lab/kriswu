#!/usr/bin/env python3
"""Dependency-free GLB contract check, including inverse binds and animated foot contact."""
import struct,json,pathlib,math,hashlib,bisect,sys
from gltf_contract import unsupported_features
ROOT=pathlib.Path(__file__).resolve().parents[2]

def load(path):
 b=path.read_bytes();assert b[:4]==b'glTF';assert struct.unpack_from('<I',b,8)[0]==len(b)
 n=struct.unpack_from('<I',b,12)[0];j=json.loads(b[20:20+n]);start=20+n+8;data=b[start:]
 def acc(i):
  a=j['accessors'][i];v=j['bufferViews'][a['bufferView']];w={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
  fmt,size={5121:('B',1),5123:('H',2),5125:('I',4),5126:('f',4)}[a['componentType']]
  offset=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',size*w)
  values=[list(struct.unpack_from('<'+fmt*w,data,offset+k*stride)) for k in range(a['count'])]
  assert all(math.isfinite(x) for row in values for x in row)
  return values
 return j,acc,b

def mul(a,b):return [[sum(a[r][k]*b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]
def matrix(t=(0,0,0),q=(0,0,0,1),s=(1,1,1)):
 x,y,z,w=q
 return [[(1-2*(y*y+z*z))*s[0],2*(x*y-z*w)*s[1],2*(x*z+y*w)*s[2],t[0]],
 [2*(x*y+z*w)*s[0],(1-2*(x*x+z*z))*s[1],2*(y*z-x*w)*s[2],t[1]],
 [2*(x*z-y*w)*s[0],2*(y*z+x*w)*s[1],(1-2*(x*x+y*y))*s[2],t[2]],[0,0,0,1]]
def worlds(j,pose=None):
 parents={c:i for i,n in enumerate(j['nodes']) for c in n.get('children',[])};out={}
 def world(i):
  if i in out:return out[i]
  n=j['nodes'][i];p=(pose or {}).get(i,n)
  m=matrix(p.get('translation',n.get('translation',(0,0,0))),p.get('rotation',n.get('rotation',(0,0,0,1))),p.get('scale',n.get('scale',(1,1,1))))
  if 'matrix' in n:m=[[n['matrix'][c*4+r] for c in range(4)] for r in range(4)]
  out[i]=mul(world(parents[i]),m) if i in parents else m
  return out[i]
 for i in range(len(j['nodes'])):world(i)
 return out

def sampled(j,acc,clip,t):
 pose={}
 for c in clip['channels']:
  s=clip['samplers'][c['sampler']];times=[r[0] for r in acc(s['input'])];values=acc(s['output'])
  k=max(0,min(len(times)-2,bisect.bisect_right(times,t)-1));u=max(0,min(1,(t-times[k])/max(times[min(k+1,len(times)-1)]-times[k],1e-9)))
  a=values[k];b=values[min(k+1,len(values)-1)];path=c['target']['path']
  if s.get('interpolation')=='STEP':u=0
  if path=='rotation' and sum(x*y for x,y in zip(a,b))<0:b=[-x for x in b]
  v=[x+(y-x)*u for x,y in zip(a,b)]
  if path=='rotation':norm=math.sqrt(sum(x*x for x in v));v=[x/norm for x in v]
  pose.setdefault(c['target']['node'],{})[path]=v
 return worlds(j,pose)

def stats(j,b):
 return {'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest(),'meshes':len(j['meshes']),
 'primitives':sum(len(m['primitives']) for m in j['meshes']), 'materials':len(j.get('materials',[])),
 'triangles':sum(j['accessors'][p['indices']]['count']//3 for m in j['meshes'] for p in m['primitives']),
 'joints':len(j['skins'][0]['joints']),'clips':len(j.get('animations',[]))}

def main():
 face='--face-sample' in sys.argv
 asset='Ranger_FaceSample' if face else 'Ranger_Original'
 j,acc,b=load(ROOT/f'App/Arena3D/{asset}.glb');old,_,oldb=load(ROOT/'App/Arena3D/Rogue.glb')
 errors=unsupported_features(j);assert not errors,'Unsupported Arena features: '+ '; '.join(errors)
 required={'Ranger_Idle','Ranger_Run','Ranger_Shoot','Ranger_Skill','Hit_A','1H_Ranged_Reload','Death_A','Cheer'}
 clips={a['name']:a for a in j['animations']};assert required==set(clips)
 names={n.get('name'):i for i,n in enumerate(j['nodes'])};assert {'muzzle','handslot.r','spine','chest','head','foot.l','foot.r'}<=names.keys()
 if face:
  assert {'eye.r','eye.l','brow.r','brow.l','mouth'}<=names.keys()
  for clip,node,path in [('Ranger_Idle','eye.r','scale'),('Ranger_Shoot','brow.r','rotation'),('Cheer','mouth','translation')]:
   channels=[c for c in clips[clip]['channels'] if c['target']['node']==names[node] and c['target']['path']==path]
   assert channels,(clip,node,path)
   values=acc(clips[clip]['samplers'][channels[0]['sampler']]['output'])
   assert max(max(abs(a-b) for a,b in zip(v,values[0])) for v in values)>.01,(clip,node,'static channel')
 newstats=stats(j,b);assert newstats['primitives']==1 and newstats['materials']==1 and newstats['joints']<=(28 if face else 24)
 assert newstats['triangles']<=16000 and len(b)<1000000
 assert j['materials'][0].get('alphaMode','OPAQUE')=='OPAQUE'
 world=worlds(j);skin=j['skins'][0];bind=acc(skin['inverseBindMatrices'])
 err=0
 for i,node in enumerate(skin['joints']):
  inv=[[bind[i][c*4+r] for c in range(4)] for r in range(4)];m=mul(world[node],inv)
  err=max(err,max(abs(m[r][c]-(1 if r==c else 0)) for r in range(4) for c in range(4)))
 assert err<1e-4,('inverse bind mismatch',err)
 positions=[]
 for m in j['meshes']:
  for p in m['primitives']:
   a=p['attributes'];positions+=acc(a['POSITION'])
   for weights,joints in zip(acc(a['WEIGHTS_0']),acc(a['JOINTS_0'])):
    assert abs(sum(weights)-1)<1e-5 and all(w>=0 for w in weights)
    assert all(0<=i<len(skin['joints']) for i in joints)
   assert all(abs(sum(x*x for x in n)-1)<.005 for n in acc(a['NORMAL']))
 low=[min(p[i] for p in positions) for i in range(3)];high=[max(p[i] for p in positions) for i in range(3)]
 assert abs(low[1])<.002 and 2.2<high[1]<2.5,(low,high)
 for name,a in clips.items():
  for s in a['samplers']:
   assert s.get('interpolation','LINEAR') in ['LINEAR','STEP']
   times=[v[0] for v in acc(s['input'])];assert all(y>x for x,y in zip(times,times[1:]));acc(s['output'])
  if name in ['Ranger_Idle','Ranger_Run']:
   duration=max(acc(s['input'])[-1][0] for s in a['samplers']);start=sampled(j,acc,a,0);end=sampled(j,acc,a,duration)
   assert max(abs(start[i][r][c]-end[i][r][c]) for i in skin['joints'] for r in range(4) for c in range(4))<1e-4,name+' loop seam'
 # Contact portion of the gait: feet travel backwards at constant speed relative to the actor,
 # remain level and keep their ankle exactly 0.18 m above ground. World locomotion is unmodified.
 run=clips['Ranger_Run'];duration=max(acc(s['input'])[-1][0] for s in run['samplers']);contact=[]
 for side,offset in [('r',0),('l',.5)]:
  for frame in range(61):
   u=frame/60;phase=(u+offset)%1
   if .025<phase<.575:
    w=sampled(j,acc,run,u*duration)[names['foot.'+side]];contact.append(abs(w[1][3]-.18))
 assert max(contact)<.015,('foot contact error',max(contact))
 # Bow tips must stay attached when the release channel moves the string centre.
 fired=sampled(j,acc,clips['Ranger_Shoot'],0); tip_drifts=[]
 for mesh in j['meshes']:
  for primitive in mesh['primitives']:
   attrs=primitive['attributes']
   for p,ws,js in zip(acc(attrs['POSITION']),acc(attrs['WEIGHTS_0']),acc(attrs['JOINTS_0'])):
    if .333<abs(p[0])<.347 and abs(p[1]-(1.26 if face else 1.35))<.009 and abs(p[2]-(.75 if face else .63))<.009:
     out=[0.,0.,0.]
     for weight,joint in zip(ws,js):
      inv=[[bind[joint][c*4+r] for c in range(4)] for r in range(4)]
      m=mul(fired[skin['joints'][joint]],inv)
      for r in range(3):out[r]+=weight*(sum(m[r][c]*p[c] for c in range(3))+m[r][3])
     tip_drifts.append(math.sqrt(sum((x-y)**2 for x,y in zip(p,out))))
 assert len(tip_drifts)>=10 and max(tip_drifts)<.005,('bow string tip detached',tip_drifts)
 report={'asset':asset,'legacy':stats(old,oldb),'new':newstats,'bounds':{'min':low,'max':high},
 'inverseBindMaxError':err,'contactAnkleMaxErrorM':max(contact),'bowTipReleaseMaxDriftM':max(tip_drifts),'clips':sorted(clips),
 'source':'Original Blender geometry / atlas / rig / actions. No third-party character asset.',
 'limits':['CPU asset validation; not iOS visual acceptance','No physical-device FPS, GPU or thermal evidence']}
 out=ROOT/('docs/ranger-face-sample-validation.json' if face else 'docs/ranger-asset-validation.json');out.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':main()
