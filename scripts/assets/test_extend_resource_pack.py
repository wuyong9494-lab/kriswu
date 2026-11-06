"""A scene addition must preserve every existing payload and theme property."""
import hashlib
import json
import struct
import tempfile
import unittest
from pathlib import Path

from build_resource_pack import MAGIC, build, verify
from extend_resource_pack import extend


class ExtendPackTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.original = self.root/'old.arenapack'
        self.output = self.root/'next.arenapack'
        self.spec_file = self.root/'additions.json'
        def item(path, data, kind):
            (self.root/path).write_bytes(data)
            return {'path':path,'kind':kind,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
        self.scene = item('scene.json', b'{"schemaVersion":1}', 'data')
        self.old_file = item('still.png', b'unchanged-test-image-payload', 'image')
        self.theme = {'id':'theme','title':'Title','backgroundFile':'still.png','musicCue':'OriginalCue'}
        self.manifest = {'schemaVersion':2,'id':'before','files':[self.old_file],
                         'themes':[self.theme], 'heroes':[], 'maps':[], 'music':[], 'musicBindings':{}}
        manifest_path=self.root/'manifest-input.json';manifest_path.write_text(json.dumps(self.manifest))
        build(manifest_path,self.root,self.original)
        self.binding = {'sceneFile':'scene.json','sceneExport':'background','sceneSourceRect':[-50,-50,50,50]}
        self.spec = {'files':[self.scene],'themeScenes':{'theme':self.binding}}

    def run_extension(self):
        self.spec_file.write_text(json.dumps(self.spec))
        return extend(self.original,self.spec_file,self.root,self.output,'after')

    def test_preserves_original_payload_and_theme_while_adding_bound_scene(self):
        old_digest = hashlib.sha256(self.original.read_bytes()).hexdigest()
        self.run_extension()
        self.assertEqual(hashlib.sha256(self.original.read_bytes()).hexdigest(),old_digest)
        self.assertEqual(verify(self.output)['files'],2)
        with self.output.open('rb') as stream:
            self.assertEqual(stream.read(len(MAGIC)),MAGIC)
            manifest = json.loads(stream.read(struct.unpack('<I',stream.read(4))[0]))
            self.assertEqual(stream.read(self.old_file['bytes']),b'unchanged-test-image-payload')
        self.assertEqual(manifest['themes'],[{**self.theme,**self.binding}])
        self.assertEqual(manifest['files'][0],self.old_file)

    def test_unknown_theme_changed_still_and_dangling_scene_are_rejected(self):
        for patch in [{'absent':self.binding},
                      {'theme':{**self.binding,'backgroundFile':'replacement.png'}},
                      {'theme':{**self.binding,'sceneFile':'missing.json'}}]:
            self.spec['themeScenes']=patch
            with self.subTest(patch=patch),self.assertRaises(AssertionError): self.run_extension()
            self.assertFalse(self.output.exists())
            self.assertFalse(self.output.with_name(self.output.name+'.partial').exists())

    def test_existing_scene_and_duplicate_payload_cannot_be_replaced(self):
        self.run_extension()
        self.original=self.output
        self.output=self.root/'third.arenapack'
        self.spec['files']=[]
        self.spec['themeScenes']['theme']['sceneExport']='different'
        with self.assertRaisesRegex(AssertionError,'replace existing'): self.run_extension()
        self.spec['themeScenes']={}
        self.spec['files']=[self.old_file]
        with self.assertRaises(AssertionError): self.run_extension()
        self.assertFalse(self.output.exists())


if __name__=='__main__': unittest.main()
