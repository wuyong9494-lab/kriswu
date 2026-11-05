#!/usr/bin/env python3
"""Convert named source UI exports into private, bounded display-list assets.

This does not declare a screen playable or visually accepted. State, text and
layout bindings still belong to the native interface adapter. The output must
remain outside the public repository along with the supplied IPA.
Dependencies: numpy, zstandard, Pillow, texture2ddecoder.
"""
import argparse
import copy
import hashlib
import json
import math
import struct
from pathlib import Path

from PIL import Image
import texture2ddecoder

from source_flash import SourceFlash, require


def decode_texture(texture):
    data = texture['data']
    require(not texture['external'], 'External texture must be resolved explicitly')
    require(data[:12] == b'\xabKTX 11\xbb\r\n\x1a\n', 'Unsupported source texture container')
    endian, gl_type, _, gl_format, internal, _, width, height, depth, arrays, faces, levels, metadata = struct.unpack_from('<13I',data,12)
    require(endian == 0x04030201 and gl_type == 0 and gl_format == 0 and depth == 0
            and arrays == 0 and faces == 1 and levels >= 1, 'Unsupported KTX layout')
    require((width,height) == (texture['width'],texture['height']), 'KTX size mismatch')
    require(width > 0 and height > 0 and width*height <= 32_000_000, 'KTX exceeds budget')
    sizes = [(4,4),(5,4),(5,5),(6,5),(6,6),(8,5),(8,6),(8,8),(10,5),(10,6),(10,8),(10,10),(12,10),(12,12)]
    require(0x93B0 <= internal < 0x93B0+len(sizes), 'Unsupported ASTC format')
    bx, by = sizes[internal-0x93B0]
    offset = 64 + metadata
    require(offset+4 <= len(data), 'Truncated KTX metadata')
    length = struct.unpack_from('<I',data,offset)[0]
    require(length == math.ceil(width/bx)*math.ceil(height/by)*16 and offset+4+length <= len(data), 'Invalid ASTC byte count')
    pixels = texture2ddecoder.decode_astc(data[offset+4:offset+4+length],width,height,bx,by)
    return Image.frombytes('RGBA',(width,height),pixels,'raw','BGRA')


def compact_atlases(source, objects, output, prefix):
    """Copy referenced texels at native resolution, preserving all source UVs."""
    rectangles = {}
    for item in objects.values():
        for command in item['commands']:
            index = command['textureIndex']
            require(0 <= index < len(source.textures), 'Invalid source texture reference')
            texture = source.textures[index]
            w,h = texture['width'],texture['height']
            points = command['vertices']
            box = (max(0,math.floor(min(v[2] for v in points)*w/65535)-2),
                   max(0,math.floor(min(v[3] for v in points)*h/65535)-2),
                   min(w,math.ceil(max(v[2] for v in points)*w/65535)+3),
                   min(h,math.ceil(max(v[3] for v in points)*h/65535)+3))
            require(box[2] > box[0] and box[3] > box[1], 'Empty UV rectangle')
            key = (index,box)
            rectangles[key] = None
            command['_rectangle'] = key
    size = 4096
    padding = 2
    placements, pages = {}, []
    x=y=row=0; page=-1
    for key in sorted(rectangles,key=lambda k: (-(k[1][3]-k[1][1]),k)):
        _,box = key; w,h = box[2]-box[0]+2*padding,box[3]-box[1]+2*padding
        require(w <= size and h <= size, 'Source crop exceeds atlas size')
        if page < 0 or y+h > size:
            pages.append(Image.new('RGBA',(size,size))); page+=1; x=y=row=0
        if x+w > size:
            x=0; y+=row; row=0
            if y+h > size:
                pages.append(Image.new('RGBA',(size,size))); page+=1; x=y=row=0
        placements[key] = (page,x+padding,y+padding)
        x+=w; row=max(row,h)
    require(len(pages) <= 16, 'Source UI exceeds atlas count budget')
    # Decode one original atlas at a time; do not retain nine 4K images.
    for index in sorted({k[0] for k in rectangles}):
        image = decode_texture(source.textures[index])
        for key,(page,x,y) in placements.items():
            if key[0] == index:
                crop=image.crop(key[1]); w,h=crop.size
                pages[page].paste(crop,(x,y))
                # Original textures clamp their edge. Preserve that sampling
                # after moving the crop into an atlas, including UV == 65535.
                for yy in (-padding,h):
                    edge=crop.crop((0,0 if yy<0 else h-1,w,1 if yy<0 else h))
                    pages[page].paste(edge.resize((w,padding)),(x,y+yy))
                for xx in (-padding,w):
                    edge=crop.crop((0 if xx<0 else w-1,0,1 if xx<0 else w,h))
                    pages[page].paste(edge.resize((padding,h)),(x+xx,y))
                for xx in (-padding,w):
                    for yy in (-padding,h):
                        pixel=crop.getpixel((0 if xx<0 else w-1,0 if yy<0 else h-1))
                        pages[page].paste(pixel,(x+xx,y+yy,x+xx+padding,y+yy+padding))
        image.close()
    entries=[]
    for i,image in enumerate(pages):
        name=f'{prefix}/atlas-{i}.png'; path=output/name; path.parent.mkdir(parents=True,exist_ok=True)
        image.save(path,optimize=True)
        entries.append({'file':name,'width':size,'height':size,'alphaEncoding':'straight',
                        'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
        image.close()
    for item in objects.values():
        for command in item['commands']:
            key = command.pop('_rectangle'); page,dx,dy = placements[key]; index,box=key
            texture=source.textures[index]
            command['textureIndex']=page
            command['vertices']=[[x,y,(u*texture['width']/65535-box[0]+dx)/size*65535,
                                     (v*texture['height']/65535-box[1]+dy)/size*65535] for x,y,u,v in command['vertices']]
    return entries


def export(source, names, output, prefix='source-interface'):
    require(names and len(names)==len(set(names)), 'Empty or duplicated export selection')
    reachable=source.reachable(names)
    objects={str(i):copy.deepcopy(source.objects[i]) for i in sorted(reachable)}
    matrices,colors=[],[]; matrix_ids,color_ids={},{}
    for item in objects.values():
        if '_bank' not in item:
            continue
        index=item.pop('_bank'); bank=source.banks[index]
        for frame in item['frames']:
            for element in frame['elements']:
                for slot,table,ids,values in [(1,bank[0],matrix_ids,matrices),(2,bank[1],color_ids,colors)]:
                    key=(index,element[slot])
                    if element[slot] == 65535:
                        element[slot]=-1
                    else:
                        if key not in ids:
                            ids[key]=len(values); values.append(table[element[slot]].tolist())
                        element[slot]=ids[key]
    textures=compact_atlases(source,objects,output,prefix)
    result={'schemaVersion':1,'sourceSCMember':'Payload/NB.app/res/sc/'+source.path.name,
        'sourceSCSHA256':source.sha256,'sourceSCVersion':source.version,'canvasSize':[1920,1080],
        'sourceRect':[-960,-540,960,540],'uvDivisor':65535,'primitiveMode':'triangle_strip',
        'clockPolicy':'independent_absolute_clip_fps','textures':textures,'objects':objects,
        'matrices':matrices,'colors':colors,'exclusions':[],
        'exports':{n:{'objectID':source.exports[n],'status':'requires_layout_text_and_state_bindings'} for n in names}}
    path=output/prefix/'scene.json';path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(result,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--export',action='append',required=True,dest='exports')
    args=parser.parse_args()
    repo=Path(__file__).resolve().parents[2]
    require(not args.output.resolve().is_relative_to(repo),'Private output must be outside the public checkout')
    result=export(SourceFlash(args.source),args.exports,args.output)
    print(json.dumps({'objects':len(result['objects']),'matrices':len(result['matrices']),
                      'atlases':len(result['textures']),'exports':len(result['exports'])}))


if __name__=='__main__':
    main()
