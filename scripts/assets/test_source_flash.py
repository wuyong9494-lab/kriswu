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
from export_source_interface import compact_atlases, straight_alpha_image
from source_interface_bindings import inventory
from export_source_localization import table


class InterfaceBindingTests(unittest.TestCase):
    def testLocalizationSelectsExactLocaleAndPreservesSourceTokens(self):
        data = b'TID,EN,CN\nstring,string,string\nTID_EXAMPLE,English,"Value <NUM>, second line"\n'
        self.assertEqual(table(data,'CN'),{'TID_EXAMPLE':'Value <NUM>, second line'})
        with self.assertRaises(AssertionError):
            table(data,'CNT')
        with self.assertRaises(AssertionError):
            table(data + b'TID_EXAMPLE,Other,Conflicting\n','CN')

    def scene(self):
        return {'sourceSCSHA256':'a'*64, 'exports': {'hud': {'objectID':1}}, 'objects': {
            '1': {'children': [{'objectID':2,'name':n,'blendMode':0} for n in ['', 'counter', 'counter']]},
            '2': {'frameCount':3, 'frameLabels':['idle','','ready'],
                  'children':[{'objectID':3,'name':'value','blendMode':0}]},
            '3': {'textField': {'fontName':'Synthetic','text':''}}}}

    def testReusedObjectsRetainIndependentInstancePathsAndSourceFrameIndices(self):
        nodes = inventory(self.scene())['exports']['hud']
        self.assertEqual([n['path'] for n in nodes],
                         ['', '#0:', '#0:/value', '#1:counter', '#1:counter/value', '#2:counter', '#2:counter/value'])
        self.assertEqual(nodes[1]['labels'], [{'name':'idle','frameIndex':0},{'name':'ready','frameIndex':2}])
        self.assertEqual(nodes[1]['frameCount'],3)

    def testCyclesAndMissingChildrenFailInsteadOfProducingPartialBindings(self):
        for target in [1,99]:
            scene = self.scene()
            scene['objects']['2']['children'][0]['objectID'] = target
            with self.assertRaises(FormatError):
                inventory(scene)


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

    def test_png_alpha_boundary_preserves_translucent_source_color(self):
        source = Image.new('RGBA',(4,1))
        source.putdata([(128,64,0,128),(17,0,0,0),(255,120,30,255),(40,80,120,128)])
        converted = straight_alpha_image(source,'premultiplied')
        self.assertEqual([converted.getpixel((x,0)) for x in range(4)],[(255,128,0,128),(0,0,0,0),(255,120,30,255),(80,159,239,128)])
        # PNG decoding premultiplies exactly once. Half-red must remain 128,
        # rather than becoming 64 after an accidental second multiplication.
        r,g,b,a = converted.getpixel((0,0))
        self.assertEqual(tuple(round(c*a/255) for c in (r,g,b)),(128,64,0))
        straight = Image.new('RGBA',(1,1),(255,128,0,128))
        self.assertIs(straight_alpha_image(straight,'straight'),straight)
        with self.assertRaises(FormatError): straight_alpha_image(straight,'guessed')


if __name__=='__main__': unittest.main()
