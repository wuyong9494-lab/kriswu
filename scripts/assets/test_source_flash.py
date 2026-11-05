"""Small authored SC fixtures; no supplied client data enters this repository."""
import copy
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import flatbuffers
import zstandard
from PIL import Image

from source_flash import FormatError, SourceFlash, Table
from export_source_interface import compact_atlases


def fixture(version=6):
    def finish(builder):
        root=builder.EndObject(); builder.Finish(root); return bytes(builder.Output())
    def vector(builder, values, stride, add):
        builder.StartVector(stride,len(values),stride)
        for value in reversed(values): add(value)
        return builder.EndVector()
    def chunk(data): return struct.pack('<I',len(data))+data
    b=flatbuffers.Builder(64)
    strings=[b.CreateString(''),b.CreateString('fixture')]
    sv=vector(b,strings,4,b.PrependUOffsetTRelative)
    vertices=b.CreateByteVector(struct.pack('<ffHH',0,0,0,0)+struct.pack('<ffHH',2,0,65535,0)+struct.pack('<ffHH',0,2,0,65535))
    b.StartObject(7); b.PrependUOffsetTRelativeSlot(0,sv,0); b.PrependUOffsetTRelativeSlot(5,vertices,0)
    storage=chunk(finish(b))
    b=flatbuffers.Builder(64)
    ids=vector(b,[7],2,b.PrependUint16); names=vector(b,[1],4,b.PrependUint32)
    b.StartObject(2); b.PrependUOffsetTRelativeSlot(0,ids,0); b.PrependUOffsetTRelativeSlot(1,names,0)
    exports=chunk(finish(b))
    def empty():
        b=flatbuffers.Builder(16); b.StartObject(1); return chunk(finish(b))
    b=flatbuffers.Builder(128)
    b.StartVector(16,1,4)
    for n in [0,3,0,0]: b.PrependUint32(n)
    commands=b.EndVector()
    b.StartObject(2); b.PrependUint16Slot(0,7,0); b.PrependUOffsetTRelativeSlot(1,commands,0)
    shape=b.EndObject(); shapes=vector(b,[shape],4,b.PrependUOffsetTRelative)
    b.StartObject(1); b.PrependUOffsetTRelativeSlot(0,shapes,0); shape_chunk=chunk(finish(b))
    payload=storage+exports+empty()+shape_chunk+empty()+empty()+empty()
    compressed=zstandard.ZstdCompressor().compress(payload)
    b=flatbuffers.Builder(64); b.StartObject(13)
    b.PrependUint32Slot(2,1,0);b.PrependUint32Slot(8,len(storage),0);b.PrependUint32Slot(11,len(compressed),0)
    header=finish(b)
    return b'SC'+struct.pack('<I',version)+(b'\0\0' if version==6 else b'')+chunk(header)+compressed


class SourceFlashTests(unittest.TestCase):
    def parse(self, data):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'fixture.sc';path.write_bytes(data)
            return SourceFlash(path)

    def test_version_5_and_6_keep_zero_based_names_and_exact_vertex_values(self):
        for version in (5,6):
            source=self.parse(fixture(version))
            self.assertEqual(source.exports,{'fixture':7})
            self.assertEqual(source.reachable(['fixture']),{7})
            self.assertEqual(source.objects[7]['commands'][0]['vertices'],[(0,0,0,0),(2,0,65535,0),(0,2,0,65535)])

    def test_truncation_unknown_flags_and_missing_exports_fail(self):
        raw=fixture()
        for data in (raw[:10],raw[:-3],raw[:6]+b'\1\0'+raw[8:]):
            with self.assertRaises((FormatError,zstandard.ZstdError,struct.error)):
                self.parse(data)
        with self.assertRaises(FormatError): self.parse(raw).reachable(['absent'])

    def test_cyclic_or_dangling_scene_is_not_flattened_to_empty_art(self):
        source=self.parse(fixture())
        source.objects[7]['children']=[{'objectID':7}]
        with self.assertRaises(FormatError): source.reachable(['fixture'])
        source.objects[7]['children']=[{'objectID':999}]
        with self.assertRaises(FormatError): source.reachable(['fixture'])

    def test_flatbuffer_never_reads_a_vector_past_its_buffer(self):
        with self.assertRaises(FormatError): Table(b'\xff\xff\xff\x7f')

    def test_compact_atlas_preserves_source_edge_clamping(self):
        source=self.parse(fixture())
        source.textures=[{'width':2,'height':2}]
        objects={'7':copy.deepcopy(source.objects[7])}
        image=Image.new('RGBA',(2,2));image.putdata([(255,0,0,255),(0,255,0,255),(0,0,255,255),(255,255,0,255)])
        with tempfile.TemporaryDirectory() as directory, patch('export_source_interface.decode_texture',return_value=image):
            entries=compact_atlases(source,objects,Path(directory),'ui')
            atlas=Image.open(Path(directory)/entries[0]['file'])
            # UV exactly 1 used to clamp to the original final pixel. It must
            # sample its replicated border, not a neighbouring packed sprite.
            vertices=objects['7']['commands'][0]['vertices']
            for vertex, expected in zip(vertices,[(255,0,0,255),(0,255,0,255),(0,0,255,255)]):
                x,y=round(vertex[2]/65535*4096),round(vertex[3]/65535*4096)
                self.assertEqual(atlas.getpixel((x,y)),expected)


if __name__=='__main__': unittest.main()
