#!/usr/bin/env python3
"""Offline identity-checked H17 particle mesh, material and texture adapter."""
from __future__ import annotations
import hashlib, io, json
from pathlib import Path
import numpy as np
from sun_triad_assets import require, write_private
from sun_triad_effects import EFFECTS


def sha(raw):return hashlib.sha256(raw).hexdigest()


class SourceAssets:
    def __init__(self,models,effects,output):
        import UnityPy
        UnityPy.config.FALLBACK_UNITY_VERSION='6000.3.11f1'
        raw=(models/EFFECTS[0]).read_bytes();require(sha(raw)==EFFECTS[1],'Original H17 effect bundle digest differs')
        self.environment=UnityPy.load(raw);self.local={o.path_id:o for o in self.environment.objects}
        self.source_cab=next(o.assets_file for o in self.environment.objects)
        self.effects,self.output=effects,output
        self.records=[]
        for name in ['recovered-dependencies-private.json','recovered-material-textures-private.json']:
            self.records.extend(json.loads((effects/'external-objects'/name).read_text())['records'])
        self.mesh_records=json.loads((effects/'external-objects/mesh-arrays-private.json').read_text())['records']
        self.shader_document=json.loads((effects/'shader-source/h17-shader-material-bindings-private.json').read_text())
        self.program_patch=json.loads((effects/'metal-programs/h17-metal-material-patches-private.json').read_text())
        self.color_space=json.loads((effects/'shader-source/source-color-space-private.json').read_text())
        require(self.color_space['memberSHA256']=='1ddbe17aab3a2997a1913e122eb9099da5ed17b94aff84fecd288914fecb2e0f'
                and self.color_space['playerSettingsSHA256']=='5fe9e533c9b17a8cafe0aa25387a6a6ff738641b27d5334ff117e276cc293cb9'
                and self.color_space['projectActiveColorSpace']==0,'Original project color-space evidence differs')
        self.physics_quality=json.loads((effects/'shader-source/source-physics-quality-private.json').read_text())
        physics=[item for item in self.physics_quality if item['type']=='PhysicsManager']
        require(len(physics)==1 and physics[0]['completeTypeTreeRead']
                and physics[0]['sha256']=='3180439a7fe54ae70297e236f16f23003b72b8dbae6bf179dc043c2e9a5be8ee',
                'Original project gravity evidence differs')
        self.gravity=np.array([physics[0]['values']['m_Gravity'][axis] for axis in ('x','y','z')],dtype=float)
        require(np.isfinite(self.gravity).all(),'Original project gravity is invalid')
        quality=[item for item in self.physics_quality if item['type']=='QualitySettings']
        require(len(quality)==1 and quality[0]['completeTypeTreeRead']
                and quality[0]['sha256']=='7e1c4004b906f69308e973ecc7d3d09105e4f8933aea2e601931a0edc9e1cf8c',
                'Original serialized quality evidence differs')
        selected=quality[0]['values']['m_CurrentQuality'];self.anisotropic=quality[0]['values']['m_QualitySettings'][selected]['anisotropicTextures']
        require(self.anisotropic in (0,1),'Unadapted original anisotropic quality mode')
        self.files={};self.texture_bindings={};self.materials={};self.meshes={};self.audit=[]

    def key(self,pointer):
        file_id,path_id=pointer['m_FileID'],int(pointer['m_PathID'])
        if file_id==0:return None,path_id
        require(1<=file_id<=len(self.source_cab.externals),'Original effect PPtr file index is out of bounds')
        return self.source_cab.externals[file_id-1].path.rsplit('/',1)[-1],path_id

    def record(self,kind,cab,path_id):
        choices=[r for r in self.records if r['type']==kind and int(r['pathID'])==path_id
                 and (cab is None or r['externalCAB'].rsplit('/',1)[-1]==cab)]
        require(choices and len({r['sourceObjectSHA256'] for r in choices})==1,
                'Original external object missing or ambiguous: '+kind+' '+str(path_id))
        result=choices[0]
        require(sha(Path(result['rawFile']).read_bytes())==result['sourceObjectSHA256'],
                'Recovered original object digest differs')
        return result

    def texture(self,path_id,*,cab=None,default=None):
        from PIL import Image
        identity=(cab,path_id,default)
        if identity in self.texture_bindings:return self.texture_bindings[identity]
        if path_id==0:
            require(default in ('white','black','gray','bump'),'Unproven source shader default texture')
            pixel={'white':(255,255,255,255),'black':(0,0,0,255),'gray':(128,128,128,255),'bump':(128,128,255,255)}[default]
            image=Image.new('RGBA',(1,1),pixel);settings=dict(m_FilterMode=1,m_WrapU=0,m_WrapV=0,m_Aniso=1)
            mip_count=1;color_space=0;texture_format=4;texture_data=bytes(pixel);source_name='Unity shader default '+default
            receipt=dict(sourceBuiltinDefault=default)
        elif cab is None and path_id in self.local and self.local[path_id].type.name=='Texture2D':
            obj=self.local[path_id];texture=obj.read();image=texture.image.convert('RGBA')
            settings=obj.read_typetree()['m_TextureSettings'];mip_count=texture.m_MipCount;color_space=texture.m_ColorSpace;source_name=texture.m_Name
            texture_format=texture.m_TextureFormat;texture_data=bytes(texture.get_image_data())
            receipt=dict(sourceCAB=self.source_cab.name,sourcePathID=str(path_id),sourceObjectSHA256=sha(obj.get_raw_data()))
        else:
            record=self.record('Texture2D',cab,path_id);raw=Path(record['pngFile']).read_bytes()
            require(sha(raw)==record['pngSHA256'],'Recovered source texture PNG digest differs')
            image=Image.open(io.BytesIO(raw)).convert('RGBA');metadata=json.loads(Path(record['metadataFile']).read_text())
            settings=metadata['m_TextureSettings'];mip_count=metadata['m_MipCount'];color_space=metadata['m_ColorSpace'];source_name=record['sourceName']
            texture_format=metadata['m_TextureFormat'];texture_data=Path(record['textureFile']).read_bytes()
            require(sha(texture_data)==record['sourceTextureSHA256'],'Original compressed texture digest differs')
            receipt={k:record[k] for k in ('externalCAB','pathID','sourceObjectSHA256','sourceTextureSHA256')}
        require(1<=image.width<=2048 and 1<=image.height<=2048,'Original particle texture exceeds target bounds')
        require(texture_format in (4,45,47) and 1<=mip_count<=16,'Unsupported original texture format or mip count')
        expected_bytes=0
        for level in range(mip_count):
            width,height=max(1,image.width>>level),max(1,image.height>>level)
            expected_bytes+=(width*height*4 if texture_format==4 else
                ((width+3)//4)*((height+3)//4)*(8 if texture_format==45 else 16))
        require(len(texture_data)==expected_bytes,'Original texture mip-chain byte length differs')
        data_digest=sha(texture_data);data_filename='SF3FX_H17_T_'+data_digest[:20]+'.texture'
        if data_filename not in self.files:
            write_private(self.output/data_filename,texture_data)
            self.files[data_filename]=dict(name=data_filename,bytes=len(texture_data),sha256=data_digest)
        stream=io.BytesIO();image.save(stream,format='PNG');raw=stream.getvalue();digest=sha(raw)
        filename='SF3FX_H17_T_'+digest[:20]+'.png'
        require(len(raw)<=4_000_000,'Original particle PNG exceeds target size bound')
        if filename not in self.files:
            write_private(self.output/filename,raw)
            self.files[filename]=dict(name=filename,bytes=len(raw),sha256=digest)
            self.audit.append(dict(type='texture',file=filename,sourceName=source_name,width=image.width,height=image.height,**receipt))
        result=dict(file=filename,dataFile=data_filename,width=image.width,height=image.height,sourceTextureFormat=int(texture_format),
                    wrapS=int(settings['m_WrapU']),wrapT=int(settings['m_WrapV']),
                    filter=int(settings['m_FilterMode']),mip=int(mip_count),
                    maxAnisotropy=max(1,int(settings['m_Aniso'])),sourceColorSpace=int(color_space))
        require(result['wrapS'] in (0,1) and result['wrapT'] in (0,1),'Unsupported original particle texture wrap')
        self.texture_bindings[identity]=result
        return result

    def material(self,pointer):
        cab,path_id=self.key(pointer);key='m_'+str(path_id)
        if key in self.materials:return key
        if cab is None:
            obj=self.local[path_id];require(obj.type.name=='Material','Original material PPtr has wrong type')
            source=obj.read_typetree();raw_digest=sha(obj.get_raw_data())
        else:
            record=self.record('Material',cab,path_id);source=json.loads(Path(record['metadataFile']).read_text())
            raw_digest=record['sourceObjectSHA256']
        choices=[m for m in self.shader_document['materials'] if m['sourcePathID']==str(path_id)
                 and m['sourceObjectSHA256']==raw_digest]
        require(len(choices)==1,'Original material shader identity is not uniquely recorded')
        binding=choices[0]
        require(binding['matchedExactly'] and len(binding['exactMatches'])==1,
                'Original material has no unique source shader variant: '+source['m_Name'])
        shader=next(s for s in self.shader_document['shaders'] if s['pathID']==binding['shaderPathID'])
        variant=binding['exactMatches'][0]
        require(sha(Path(variant['glslFile']).read_bytes())==variant['glslSHA256'],'Original shader variant digest differs')
        parsed=json.loads(Path(shader['parsedFile']).read_text())
        props=parsed.get('m_PropInfo',{}).get('m_Props',[])
        defaults={p['m_Name']:p.get('m_DefTexture',{}).get('m_DefaultName') for p in props}
        textures={}
        # The recovered object collection proves uniqueness for texture path
        # IDs before resolving an external material's local PPtr ordinal.
        # A differing byte identity is always rejected, never name-matched.
        for slot,environment in source['m_SavedProperties']['m_TexEnvs']:
            texture_pointer=environment['m_Texture'];texture_id=int(texture_pointer['m_PathID'])
            tex=self.texture(texture_id,default=defaults.get(slot))
            textures[slot]=dict(**tex,scale=[environment['m_Scale'][k] for k in ('x','y')],
                               offset=[environment['m_Offset'][k] for k in ('x','y')])
        result=dict(sourceName=source['m_Name'],sourceMaterialSHA256=raw_digest,projectColorSpace=self.color_space['projectActiveColorSpace'],
            projectAnisotropicFiltering=self.anisotropic,
            shaderPathID=binding['shaderPathID'],sourceShaderSHA256=shader['sourceObjectSHA256'],
            variantSHA256=variant['glslSHA256'],keywords=source['m_ValidKeywords'],
            floats=dict(source['m_SavedProperties']['m_Floats']),
            colors={k:[v[c] for c in ('r','g','b','a')] for k,v in source['m_SavedProperties']['m_Colors']},textures=textures)
        patches=[p for p in self.program_patch['materials'] if p['sourceMaterialPathID']==str(path_id)
                 and p['sourceMaterialSHA256']==raw_digest]
        require(len(patches)==1,'Private source shader program binding missing or ambiguous')
        patch=patches[0]
        require(patch['sourceShaderSHA256']==result['sourceShaderSHA256'] and patch['variantSHA256']==result['variantSHA256'],
                'Private source shader program provenance differs')
        require(patch['projectColorSpace']==result['projectColorSpace']
                and patch['projectAnisotropicFiltering']==result['projectAnisotropicFiltering'],
                'Private shader project sampling state differs')
        program=patch['program'];program_raw=(self.effects/'metal-programs'/program['file']).read_bytes()
        require(len(program_raw)==program['bytes'] and sha(program_raw)==program['sha256'],'Private shader adapter digest differs')
        write_private(self.output/program['file'],program_raw)
        self.files[program['file']]=dict(name=program['file'],bytes=program['bytes'],sha256=program['sha256'])
        result.update(program=program,raster=patch['raster'])
        self.materials[key]=result
        return key

    def geometry(self,pointer,submesh=0):
        cab,path_id=self.key(pointer);key=(cab,path_id,submesh)
        if key in self.meshes:return self.meshes[key]
        if cab is None:
            from UnityPy.helpers.MeshHelper import MeshHandler
            obj=self.local[path_id];require(obj.type.name=='Mesh','Original mesh PPtr has wrong type')
            mesh=obj.read();handler=MeshHandler(mesh);handler.process()
            arrays=dict(positions=handler.m_Vertices,normals=handler.m_Normals,uv0=handler.m_UV0)
            for attribute,name in [('uv1','m_UV1'),('colors','m_Colors'),('tangents','m_Tangents')]:
                value=getattr(handler,name,None)
                if value is not None and len(value):arrays[attribute]=value
            triangles=handler.get_triangles()
            require(submesh<len(triangles),'Original particle submesh missing')
            arrays['triangles']=triangles[submesh];source_name=mesh.m_Name;source_digest=sha(obj.get_raw_data())
        else:
            choices=[r for r in self.mesh_records if int(r['pathID'])==path_id
                     and r['externalCAB'].rsplit('/',1)[-1]==cab]
            require(len(choices)==1,'Original external mesh array identity is ambiguous')
            record=choices[0];raw=Path(record['arraysFile']).read_bytes()
            require(sha(raw)==record['arraysSHA256'],'Original mesh arrays digest differs')
            with np.load(io.BytesIO(raw),allow_pickle=False) as data:arrays={k:data[k].copy() for k in data.files}
            arrays['triangles']=arrays['triangles'+str(submesh)];source_name=record['name'];source_digest=record['sourceObjectSHA256']
        positions=np.asarray(arrays['positions'],dtype=float)[:,:3]*[1,1,-1]
        normals=np.asarray(arrays['normals'],dtype=float)[:,:3]*[1,1,-1]
        uv=np.asarray(arrays['uv0'],dtype=float)[:,:2].copy();uv[:,1]=1-uv[:,1]
        indices=np.asarray(arrays['triangles'],dtype=np.uint32).reshape(-1,3)[:,[0,2,1]].reshape(-1)
        require(3<=len(positions)<=50_000 and np.isfinite(positions).all() and len(indices)%3==0,
                'Invalid original particle mesh geometry')
        result=dict(positions=positions.reshape(-1).tolist(),normals=normals.reshape(-1).tolist(),
                    uv=uv.reshape(-1).tolist(),indices=indices.tolist())
        if 'uv1' in arrays:
            uv1=np.asarray(arrays['uv1'],dtype=float)[:,:2].copy();uv1[:,1]=1-uv1[:,1];result['uv1']=uv1.reshape(-1).tolist()
        if 'colors' in arrays:result['colors']=np.asarray(arrays['colors'],dtype=float).reshape(-1).tolist()
        if 'tangents' in arrays:
            tangents=np.asarray(arrays['tangents'],dtype=float)*[1,1,-1,-1];result['tangents']=tangents.reshape(-1).tolist()
        self.meshes[key]=result
        self.audit.append(dict(type='mesh',sourceName=source_name,sourcePathID=str(path_id),sourceCAB=cab,
                               sourceObjectSHA256=source_digest,vertices=len(positions),triangles=len(indices)//3))
        return result
