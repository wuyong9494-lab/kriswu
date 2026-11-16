#!/usr/bin/env python3
"""Add an explicitly generated personal neck bridge; preserve the whole face.

The supplied portrait has no usable neck segment. Every original portrait
vertex, normal, UV, index, and image remains byte-identical. A small separate
mesh follows the actual source neck/head joints in their original bind space.
It is an application fitting adaptation, not recovered D15 source geometry.
"""
from __future__ import annotations

import argparse
import copy
import io
import json
from pathlib import Path

import numpy as np
from PIL import Image

from build_erlang_source_assets import checked, encoded, record, sha, write_new
from sun_triad_assets import Writer, accessor_read, glb_read, private_output, require, world_poses


RECOVERED_PROFILE_SHA = 'bb058e221c6402c3c1562e0c18c2f24970682d73b8052ef372e09c194c7604ff'
RECOVERED_CHARACTER_SHA = '7abc2955e2779c23541d14d51823369ec11d1954c8b3212ca0301834646460b3'


def validate_input(profile, digest, recovered):
    require(profile['id'] == profile['hero'] == 'wuyong_erlang'
            and 'imperialHeavyPassiveMirrored' in profile['roles'],
            'Expected the original Wu mirrored source actor')
    if recovered:
        require(digest == RECOVERED_PROFILE_SHA
                and profile['schema'] == 'erlang-recovered-runtime-profile-v1'
                and profile['sha256'] == RECOVERED_CHARACTER_SHA
                and profile['bytes'] == 18_576_776 and len(profile['clips']) == 62
                and profile['recoveryBoundary']['personalNeckBridgeIncluded'] is False
                and len(profile['summonTracks']) == 15
                and len(profile['erlangRules']['attacks']) == 36,
                'Expected the authenticated recovered D15 runtime input')
    else:
        require(len(profile['clips']) in (55, 56), 'Expected source mirror candidate')


def skin_color(g,b,primitive):
    material=g['materials'][primitive['material']]
    pbr=material['pbrMetallicRoughness']
    image=g['images'][g['textures'][pbr['baseColorTexture']['index']]['source']]
    view=g['bufferViews'][image['bufferView']]
    raw=bytes(b[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']])
    pixels=np.asarray(Image.open(io.BytesIO(raw)).convert('RGB'))
    positions=accessor_read(g,b,primitive['attributes']['POSITION'])
    uv=accessor_read(g,b,primitive['attributes']['TEXCOORD_0'])
    # Sample the original lower side/back skin, away from the mouth, eyes and
    # hair. This derives a plain bridge colour; it never changes the portrait.
    selected=(positions[:,1]>=.015)&(positions[:,1]<=.095)&(positions[:,2]<.025)
    require(int(selected.sum())>=20,'No bounded original skin-colour region')
    coords=np.mod(uv[selected],1.)
    x=np.minimum(pixels.shape[1]-1,(coords[:,0]*pixels.shape[1]).astype(int))
    y=np.minimum(pixels.shape[0]-1,(coords[:,1]*pixels.shape[0]).astype(int))
    srgb=np.median(pixels[y,x],axis=0)/255.
    linear=np.where(srgb<=.04045,srgb/12.92,((srgb+.055)/1.055)**2.4)
    require(np.isfinite(linear).all() and np.min(srgb)>.1,'Original sampled skin colour is unavailable')
    return linear.tolist(),dict(originalMaterial=material.get('name'),textureSHA256=sha(raw),
        sampledOriginalVertices=int(selected.sum()),medianSRGB=srgb.tolist(),linearBaseColor=linear.tolist())


def bridge(neck):
    # These dimensions are declared fitting choices, not original SF3 rules.
    upper=.055;lower=float(neck[1])-.025
    require(-.25<lower<-.08,'Source neck/head distance is outside the fitting scope')
    vertices=[];weights=[];joints=[]
    rings,segments=7,32
    for row in range(rings):
        t=row/(rings-1);height=lower+(upper-lower)*t
        radius_x=.060*(1-t)+.050*t;radius_z=.049*(1-t)+.043*t
        center=np.array(neck[:3])*(1-t)+np.array([0.,upper,.018])*t;center[1]=height
        h=t*t*(3-2*t)
        for col in range(segments):
            angle=2*np.pi*col/segments
            vertices.append(center+[radius_x*np.cos(angle),0,radius_z*np.sin(angle)])
            weights.append([h,1-h,0,0]);joints.append([0,1,0,0])
    triangles=[]
    for row in range(rings-1):
        for col in range(segments):
            a=row*segments+col;b=row*segments+(col+1)%segments;c=a+segments;d=b+segments
            triangles.extend([(a,c,b),(b,c,d)])
    for row,top in [(0,False),(rings-1,True)]:
        center=np.mean(vertices[row*segments:(row+1)*segments],axis=0)
        index=len(vertices);vertices.append(center);weights.append([int(top),int(not top),0,0]);joints.append([0,1,0,0])
        for col in range(segments):
            a=row*segments+col;b=row*segments+(col+1)%segments
            triangles.append((index,b,a) if top else (index,a,b))
    positions=np.asarray(vertices,dtype=np.float32);faces=np.asarray(triangles,dtype=np.uint32)
    normals=np.zeros_like(positions)
    for face in faces:
        a,b,c=positions[face];n=np.cross(b-a,c-a)
        for i in face:normals[i]+=n
    lengths=np.linalg.norm(normals,axis=1)
    require((lengths>1e-8).all(),'Degenerate personal bridge geometry')
    normals/=lengths[:,None]
    weights=np.asarray(weights,dtype=np.float32)
    require(np.max(abs(weights.sum(1)-1))<1e-7,'Invalid personal bridge weights')
    return positions,normals,faces,weights,np.asarray(joints,dtype=np.uint16)


def bind(args):
    raw=checked(args.profile,args.profile_sha256,48_000_000);profile=json.loads(raw)
    model=args.profile.parent/(profile['resourceName']+'.glb')
    checked(model,profile['sha256'],48_000_000)
    recovered = getattr(args, 'recovered_source', False)
    validate_input(profile, args.profile_sha256, recovered)
    g,b=glb_read(model);before=copy.deepcopy(g)
    writer=Writer();writer.g=g;writer.b=bytearray(b[:g['buffers'][0]['byteLength']]);original_binary=bytes(writer.b)
    names={n.get('name'):i for i,n in enumerate(g['nodes'])}
    require('Personal_Neck_Bridge' not in names,'Personal bridge already exists')
    portrait=names['WuYong_Personal_Head'];head=names['head'];neck=names['neck']
    require(portrait in g['nodes'][head].get('children',[]) and 'skin' not in g['nodes'][portrait],
            'Original rigid portrait binding differs')
    world,_,_=world_poses(g['nodes']);placement=world[portrait]
    neck_local=np.linalg.inv(placement)@world[neck][:,3]
    primitives=g['meshes'][g['nodes'][portrait]['mesh']]['primitives']
    require(len(primitives)==1,'Unexpected portrait primitive inventory')
    contour = getattr(args, 'source_contour', False)
    require(not contour or recovered, 'The source-contour entry requires the pinned recovered actor')
    if contour:
        from erlang_personal_neck_contour import fit
        positions,normals,faces,weights,joints,uv,png,material_source,auxiliary = fit(
            g,b,primitives[0],world,portrait,head,neck)
    else:
        color,material_source=skin_color(g,b,primitives[0])
        positions,normals,faces,weights,joints=bridge(neck_local)
    outer=names['SF3_Actor_Meters'];local=np.linalg.inv(world[outer])@placement
    # Use the same original skin as the six body meshes. A second skin with a different bind-shape matrix
    # can make importers reinterpret shared bone binds and move a rigid child.
    # Bake the generated bridge into that existing actor bind space instead.
    require(len(g['skins'])==1,'Expected the unchanged original actor skin')
    source_skin=g['skins'][0]
    slots=[source_skin['joints'].index(i) for i in (head,neck)]
    original_inverse=accessor_read(g,b,source_skin['inverseBindMatrices'])
    for node,slot in zip((head,neck),slots):
        expected=np.linalg.inv(np.linalg.inv(world[outer])@world[node])
        require(np.max(abs(original_inverse[slot].reshape(4,4).T-expected))<.001,
                'Original actor inverse bind differs')
    positions=(np.c_[positions,np.ones(len(positions))]@local.T)[:,:3].astype(np.float32)
    normals=normals@np.linalg.inv(local[:3,:3]);normals/=np.linalg.norm(normals,axis=1)[:,None]
    if not contour:
        joints[:,0]=slots[0];joints[:,1]=slots[1]
    used_slots = sorted(set(map(int,joints[weights > 0].tolist())))
    used_nodes = [source_skin['joints'][slot] for slot in used_slots]
    used_names = [g['nodes'][node]['name'] for node in used_nodes]
    if contour:
        image = len(g['images'])
        g['images'].append(dict(name='Personal_Neck_Source_Contour_Gradient',
            bufferView=writer.block(png),mimeType='image/png'))
        sampler = len(g['samplers'])
        g['samplers'].append(dict(magFilter=9729,minFilter=9729,wrapS=33071,wrapT=33071))
        texture = len(g['textures'])
        g['textures'].append(dict(source=image,sampler=sampler))
        pbr = dict(baseColorFactor=[1.,1.,1.,1.],baseColorTexture=dict(index=texture),
                   metallicFactor=0,roughnessFactor=.72)
    else:
        pbr = dict(baseColorFactor=color+[1.],metallicFactor=0,roughnessFactor=.72)
    material=len(g['materials']);g['materials'].append(dict(name='Personal_Neck_Bridge_Derived_Skin',
        pbrMetallicRoughness=pbr,
        doubleSided=False,extras=dict(generatedPersonalFitting=True,materialSource=material_source)))
    attributes=dict(POSITION=writer.acc(positions,'VEC3'),NORMAL=writer.acc(normals,'VEC3'),
        JOINTS_0=writer.acc(joints,'VEC4',5123),WEIGHTS_0=writer.acc(weights,'VEC4'))
    if contour:
        attributes['TEXCOORD_0'] = writer.acc(uv,'VEC2')
    generated_primitives=[dict(
        attributes=attributes,
        indices=writer.acc(faces.reshape(-1),'SCALAR',5125),material=material)]
    if contour:
        for part in auxiliary:
            generated_primitives.append(dict(attributes=attributes,
                indices=writer.acc(part['indices'].reshape(-1),'SCALAR',5125),material=part['sourceMaterial']))
    triangle_count = len(faces) + (sum(len(part['indices']) for part in auxiliary) if contour else 0)
    mesh=len(g['meshes']);g['meshes'].append(dict(name='Personal_Neck_Bridge',primitives=generated_primitives,
        extras=dict(generatedPersonalFitting=True,originalSF3Geometry=False)))
    # Keep the existing joint hierarchy and rigid portrait parent untouched.
    # A skinned mesh is a sibling under the actor, not a child of either joint.
    # Its inverse binds already supply the original joint animation in mesh space.
    node=len(g['nodes']);g['nodes'].append(dict(name='Personal_Neck_Bridge',mesh=mesh,skin=0))
    g['nodes'][outer]['children'].append(node)
    require(g['meshes'][g['nodes'][portrait]['mesh']]==before['meshes'][before['nodes'][portrait]['mesh']],
            'Personal bridge changed a portrait accessor')
    require(bytes(writer.b[:len(original_binary)])==original_binary,'Personal bridge changed original bytes')
    require(g['animations']==before['animations'],'Personal bridge changed source animation')
    require(g['skins']==before['skins'],'Personal bridge changed source inverse binds')
    for key in ('textures','images','samplers'):
        require(g[key][:len(before[key])]==before[key],'Personal bridge changed original '+key)
        require(len(g[key])==len(before[key])+int(contour),'Unexpected personal bridge '+key+' count')
    if recovered:
        g['extras'] = dict(g['extras'], personalNeckBridgeIncluded=True)
        profile['recoveryBoundary'] = dict(profile['recoveryBoundary'], personalNeckBridgeIncluded=True)
    require(not args.output.exists(),'Refuse to replace a private candidate');output=private_output(args.output)
    identity=writer.save(output/model.name);profile.update(identity)
    profile['personalNeckBridge']=dict(generatedGeometry=True,originalPortraitVerticesChanged=0,
        sourceJoints=used_names if contour else ['head','neck'],vertices=len(positions),triangles=triangle_count)
    if contour:
        profile['personalNeckBridge'].update(fitting='original-open-contour-v2',
            originalBoundaryHalfEdges=material_source['contour']['halfEdges'],
            originalPositionQuantizationUsed=False,sourceEndpointNormalsAndUVColour=True,
            bodyBoundaryVertices=15,dynamicBodyVertexAttributesPreserved=True,localSourceHoleEdges=10)
    write_new(output/'SF3_Erlang_Profile.json',encoded(profile))
    portrait_points=accessor_read(before,b,primitives[0]['attributes']['POSITION'])
    receipt=dict(sourceProfile=record(args.profile),character=record(output/model.name),
        profile=record(output/'SF3_Erlang_Profile.json'),originalPortraitVertices=len(portrait_points),
        originalPortraitVerticesChanged=0,changedPortraitVertexPercent=0,
        originalPortraitAttributesIndicesImagesUnchanged=True,allOriginalEmbeddedBytesUnchanged=len(original_binary),
        sourceAnimationCountUnchanged=len(g['animations']),sourceNeckInPortraitBindSpace=neck_local.tolist(),
        generatedGeometry=dict(name='Personal_Neck_Bridge',vertices=len(positions),triangles=len(faces),
            skinJoints=['head','neck'],skinJointNodes=[head,neck],originalSkin=0,skinJointSlots=slots,
            bridgeToOriginalActorBindSpace=local.tolist(),
            upperY=.055,lowerY=float(neck_local[1])-.025,topRadii=[.050,.043],bottomRadii=[.060,.049]),
        material=material_source,boundaries=['Generated neck fitting mesh, not recovered D15 or original portrait geometry.',
            'Plain skin colour derived from original lower side/back portrait texture; original face, UV and image bytes remain unchanged.',
            'Original two-joint bind space and smooth weights provide pose continuity; native renderer acceptance is still required.'])
    if contour:
        receipt['generatedGeometry'] = dict(name='Personal_Neck_Bridge',vertices=len(positions),triangles=triangle_count,
            skinJoints=used_names,skinJointNodes=used_nodes,originalSkin=0,skinJointSlots=used_slots,
            bridgeToOriginalActorBindSpace=local.tolist(),fitting='original-open-contour-v2')
        receipt['boundaries'] = [
            'Only the new fitting mesh and its derived gradient image are generated; the original portrait and all source animation bytes remain unchanged.',
            'All 182 source head edges are retained as the 172-edge neck opening and a 10-edge local source-UV cap; the body boundary copies 15 real source vertices and their complete skin attributes.',
            'Only generated interior fitting weights prune a tiny influence tail within the recorded bound; original body/portrait weights and the exact body boundary copies do not change.',
            'Source shader parity and native renderer acceptance are still unverified.']
    write_new(output/'erlang-personal-neck-bridge-private.json',encoded(receipt))
    return {k:v for k,v in receipt.items() if k not in ('generatedGeometry','material','boundaries')}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile',type=Path,required=True);parser.add_argument('--profile-sha256',required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--recovered-source', action='store_true',
                        help='Bind only the pinned recovered 62-clip runtime candidate.')
    parser.add_argument('--source-contour', action='store_true',
                        help='Fit the new bridge to exact original head half edges and actual body collar triangles.')
    print(json.dumps(bind(parser.parse_args())))


if __name__=='__main__':main()
