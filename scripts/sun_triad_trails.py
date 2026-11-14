#!/usr/bin/env python3
"""Export the original bilateral Ninjato trail skins and their source bindings.

Only animations with all eight authored trail bones are bound. Their source
renderers remain enabled throughout the authored clip: geometry, not a guessed
combat attack window, opens and collapses the trail. The original meshes omit
UV1, so the source shader's color input is its default (0,0); source repeat and
bilinear sampling are applied before the three player palette operations.
"""
from __future__ import annotations
import argparse, hashlib, json, warnings
from pathlib import Path
import numpy as np
from sun_triad_assets import C, CI, require, private_output, write_private, skin_slots, CONFIG_FILES
from sun_triad_materials import paint_rgba
from sun_triad_source_bones import parse_bones_data

BUNDLE='9e0ac3ba87e002425eeb76668aab567d.bin'
BUNDLE_SHA256='71b33699f5de3c3a0f2e16afcfa37b428dc0f8f8d31aab700340ad15c158663c'
ALPHA_SHA256='c8a01bc4e4574aff6e7dbf3615fbc673301364f776c1bd8483f509025f8fc386'


def rgba_at_zero(texture):
    """Bilinear-repeat's UV origin lies halfway across both texture seams."""
    settings=texture.m_TextureSettings
    require(settings.m_FilterMode==1 and settings.m_WrapU==0 and settings.m_WrapV==0,
            'Original trail color texture sampling changed')
    pixels=np.asarray(texture.image.convert('RGBA'),dtype=float)/255
    return (pixels[0,0]+pixels[-1,0]+pixels[0,-1]+pixels[-1,-1])/4


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--models',type=Path,required=True)
    parser.add_argument('--profile',type=Path,required=True)
    parser.add_argument('--alpha',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();output=private_output(args.output)
    import UnityPy
    from UnityPy.helpers.MeshHelper import MeshHandler
    require(UnityPy.__version__=='1.25.4','Use reviewed UnityPy 1.25.4')
    UnityPy.config.FALLBACK_UNITY_VERSION='6000.3.11f1';warnings.filterwarnings('ignore',category=Warning,module='UnityPy')
    raw=(args.models/BUNDLE).read_bytes();require(hashlib.sha256(raw).hexdigest()==BUNDLE_SHA256,'Original Ninjato bundle differs')
    bone_name,bone_digest=CONFIG_FILES['weapon'];raw_bones=(args.models/bone_name).read_bytes()
    require(hashlib.sha256(raw_bones).hexdigest()==bone_digest,'Original Ninjato bone IDs differ')
    ids={name:i for i,name in parse_bones_data(raw_bones)['bones'].items()}
    profile=json.loads(args.profile.read_text());require(profile['id']=='sun_triad','Unexpected target profile')
    character=args.profile.with_name(profile['resourceName']+'.glb')
    require(hashlib.sha256(character.read_bytes()).hexdigest()==profile['sha256'],'Target character digest differs')
    alpha=args.alpha.read_bytes();require(hashlib.sha256(alpha).hexdigest()==ALPHA_SHA256,'Original trail alpha texture differs')
    write_private(output/args.alpha.name,alpha)
    environment=UnityPy.load(raw);meshes=[];audit=[]
    for path,pointer in sorted(environment.container.items()):
        if '/m/meshes/' not in path or '__trail_' not in path or not path.endswith('.prefab'):continue
        obj=pointer.read();renderers=[c.component.read() for c in obj.m_Component if c.component.deref().type.name=='SkinnedMeshRenderer']
        data=[c.component.deref().read_typetree() for c in obj.m_Component if c.component.deref().type.name=='MonoBehaviour']
        require(len(renderers)==1 and len(data)==1,'Original trail SkinData binding is ambiguous')
        renderer=renderers[0];mesh=renderer.m_Mesh.read();handler=MeshHandler(mesh);handler.process()
        bones=data[0]['_bindBonesName'];require(len(bones)==4 and all(n in ids for n in bones),'Original four-bone trail binding differs')
        require(renderer.m_Enabled and obj.m_IsActive,'Original trail renderer is not enabled')
        indices=np.asarray(handler.m_BoneIndices,dtype=int)
        if handler.m_BoneWeights is None:
            channels=mesh.m_VertexData.m_Channels
            require(indices.shape==(len(handler.m_Vertices),1) and channels[12].dimension==0
                    and channels[13].dimension==1,'Unexpected implicit source skin weights')
            weights=np.ones_like(indices,dtype=float)
        else:weights=np.asarray(handler.m_BoneWeights,dtype=float)
        joints,weights=skin_slots(indices,weights)
        require(handler.m_UV1 is None,'Source trail now has an explicit color UV channel')
        require(len(renderer.m_Materials)==1,'Original trail material count differs')
        material=renderer.m_Materials[0].read();envs=dict(material.m_SavedProperties.m_TexEnvs)
        floats=dict(material.m_SavedProperties.m_Floats)
        colors={k:[v.r,v.g,v.b,v.a] for k,v in material.m_SavedProperties.m_Colors}
        require(floats['_NumPaints']==3 and floats['_Cull']==2 and floats['_SrcBlend']==5
                and floats['_DstBlend']==10 and floats['_ZWrite']==0,'Original trail raster state differs')
        require(envs['_AlphaTex'].m_Texture.m_PathID==1394430195881985131,'Original trail alpha pointer differs')
        samples={slot:rgba_at_zero(envs[slot].m_Texture.read()) for slot in ('_MainTex','_Mask','_Mask2')}
        palette=[colors['_MaskPlayerColor'+(str(i+1) if i else '')] for i in range(3)]
        masks=[np.array([[samples['_Mask'][0]]]),np.array([[samples['_Mask'][3]]]),np.array([[samples['_Mask2'][0]]])]
        tint=paint_rgba(samples['_MainTex'][None,None,:],masks,palette)[0,0]
        tint[:3]*=np.asarray(colors['_MainColor'][:3])*np.asarray(colors['_ColorMultiplier'][:3])
        tint[:3]*=floats['_Alpha']*floats['_MultTransparentColor'];tint[3]=floats['_Alpha']
        binds=[]
        for source in mesh.m_BindPose:
            value=np.array([[getattr(source,f'e{y}{x}') for x in range(4)] for y in range(4)])
            binds.append((C@value@CI).T.reshape(16).tolist())
        uv=np.asarray(handler.m_UV0,dtype=float)[:,:2].copy();uv[:,1]=1-uv[:,1]
        triangles=np.asarray(handler.get_triangles()[0],dtype=np.uint16).reshape(-1,3)[:,[0,2,1]]
        side='left' if mesh.m_Name.endswith('_l') else 'right'
        meshes.append(dict(name=mesh.m_Name,side=side,bones=bones,sourceBoneIDs=[ids[n] for n in bones],
            positions=(np.asarray(handler.m_Vertices)[:,:3]*[.01,.01,-.01]).reshape(-1).tolist(),
            normals=(np.asarray(handler.m_Normals)[:,:3]*[1,1,-1]).reshape(-1).tolist(),uv=uv.reshape(-1).tolist(),
            weights=weights.reshape(-1).tolist(),joints=joints.reshape(-1).tolist(),indices=triangles.reshape(-1).tolist(),
            inverseBinds=binds,material=dict(shader='alpha-mask',alphaChannel='red',multiplyColorByCoverage=False,
                blend='alpha',doubleSided=False,cullMode='back',readsDepth=True,writesDepth=False,
                wrapS=1,wrapT=1,filter='linear',tint=tint.tolist())))
        audit.append(dict(mesh=mesh.m_Name,sourcePrefab=path,sourceMeshPathID=str(mesh.object_reader.path_id),
            sourceMaterial=material.m_Name,sourceSkinData=data[0],sourceColorUV1='absent: default zero',
            sourceColorSamplesAtUVZero={k:v.tolist() for k,v in samples.items()},sourcePlayerPalette=palette,
            implicitRigidSingleBoneWeight=handler.m_BoneWeights is None))
    require(len(meshes)==2 and {m['side'] for m in meshes}=={'left','right'},'Original bilateral trail inventory differs')
    required=set(range(260,268));clips=[c['name'] for c in profile['clips'] if required.issubset(c['sourceBoneIDs'])]
    require(len(clips)==18,'Authored source trail animation inventory differs')
    document=dict(version=2,profiles=[dict(id=profile['id'],characterSHA256=profile['sha256'],meshes=meshes,
        clips=clips,alpha=dict(name=args.alpha.name,bytes=len(alpha),sha256=ALPHA_SHA256,width=256,height=256),
        skeletonNode='skeleton',attachmentNode='SF3_Actor_Meters',
        clipWindows=[dict(clip=name,startPhaseBps=0,endPhaseBps=10000) for name in clips])])
    write_private(output/'SF3WE_Ninjato_Trails.json',json.dumps(document,separators=(',',':'),allow_nan=False).encode())
    write_private(output/'ninjato-trails-source-provenance-private.json',json.dumps(dict(
        sourceBundle=BUNDLE,sourceBundleSHA256=BUNDLE_SHA256,meshes=audit,
        visibility='Original enabled renderer, full source clip with all eight authored trail-bone channels; no attack-window inference.',
        shaderCoverage='AlphaTex.red multiplies output alpha only. Original three paint masks initialize from the player palette.'),indent=2).encode())
    print(json.dumps(dict(meshes=len(meshes),authoredClips=len(clips),tints=[m['material']['tint'] for m in meshes])))


if __name__=='__main__':main()
