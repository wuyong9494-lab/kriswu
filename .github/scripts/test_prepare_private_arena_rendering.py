"""Use synthetic data only; never attach original assets to public CI."""
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import struct
import tempfile
import unittest

from prepare_private_arena_rendering import prepare


class PrivateRenderingPreparationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root/'source'
        (self.source/'App/Resources').mkdir(parents=True)
        (self.source/'scripts/assets').mkdir(parents=True)
        shutil.copyfile(Path(__file__).resolve().parents[2]/'scripts/assets/build_resource_pack.py',
                        self.source/'scripts/assets/build_resource_pack.py')
        self.info = self.source/'App/Info.plist'
        self.info.write_bytes(plistlib.dumps({'ArenaPrivateInterfaceValidationRequired': True}))
        self.output = self.source/'Tests/PrivateResourceValidation/ArenaPrivateValidation'
        self.payloads = {'atlas.png':b'synthetic-pixels', 'still.png':b'synthetic-still',
                         'font.ttf':b'synthetic-font', 'localization.json':b'{}',
                         'bindings.json':b'{"sourceSCSHA256":"synthetic-source"}'}
        self.scene = {'schemaVersion':1,'sourceSCSHA256':'synthetic-source',
                      'sourceRect':[-512,-288,512,288],
                      'exports':{'background':{'status':'ready'}},
                      'textures':[{'file':'atlas.png','sha256':hashlib.sha256(self.payloads['atlas.png']).hexdigest(),
                                   'alphaEncoding':'straight'}]}
        self.manifest = {'schemaVersion':2,'id':'synthetic-private-check','heroes':[],
                         'maps':[],'music':[],'musicBindings':{},
                         'interfaceSceneFile':'scene.json','interfaceBindingsFile':'bindings.json',
                         'interfaceLocalizationFile':'localization.json',
                         'fonts':[{'id':str(i),'file':'font.ttf','postScriptName':'Synthetic'+str(i)} for i in range(4)],
                         'themes':[{'id':str(i),'backgroundFile':'still.png','sceneFile':'scene.json',
                                    'sceneExport':'background','sceneSourceRect':[-512,-288,512,288]} for i in range(8)]}

    def pack(self):
        self.payloads['scene.json'] = json.dumps(self.scene).encode()
        kinds = {'.png':'image','.json':'data','.ttf':'font'}
        self.manifest['files'] = [{'path':name,'kind':kinds[Path(name).suffix],'bytes':len(data),
                                  'sha256':hashlib.sha256(data).hexdigest()} for name,data in self.payloads.items()]
        header = json.dumps(self.manifest).encode()
        raw = b'KRISARENA1\n'+struct.pack('<I',len(header))+header+b''.join(self.payloads.values())
        (self.source/'App/Resources/arena-original-resources.arenapack').write_bytes(raw)
        return {'private_resource_pack':{'id':self.manifest['id'],'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}}

    def test_verified_subset_is_copied_and_unrelated_payload_stays_private(self):
        self.payloads['unrelated.json'] = b'{"unselected":"not-copied"}'
        result = prepare(self.source,self.pack(),self.output)
        self.assertEqual(result,{'required':True,'themes':8,'controls':10,'files':6})
        self.assertFalse((self.output/'unrelated.json').exists())
        for name,data in self.payloads.items():
            if name != 'unrelated.json': self.assertEqual((self.output/name).read_bytes(),data)
        self.assertEqual(json.loads((self.output/'manifest.json').read_bytes()),self.manifest)

    def test_older_source_does_not_require_unavailable_new_fixtures(self):
        self.info.write_bytes(plistlib.dumps({}))
        self.assertEqual(prepare(self.source,{},self.output),{'required':False})
        self.assertFalse(self.output.exists())

    def test_wrong_pack_identity_hash_size_and_symlink_fail_before_staging(self):
        for field,value in [('id','another-pack'),('sha256','0'*64),('bytes',1)]:
            request = self.pack();request['private_resource_pack'][field] = value
            with self.subTest(field=field),self.assertRaises(AssertionError): prepare(self.source,request,self.output)
            self.assertFalse(self.output.exists())
        request = self.pack()
        path = self.source/'App/Resources/arena-original-resources.arenapack'
        destination = self.root/'redirect.arenapack';path.rename(destination);path.symlink_to(destination)
        with self.assertRaises(AssertionError): prepare(self.source,request,self.output)

    def test_wrong_atlas_hash_alpha_crop_or_unready_scene_cannot_pass(self):
        for field,value in [('sha256','0'*64),('alphaEncoding','premultiplied')]:
            original = self.scene['textures'][0][field]
            self.scene['textures'][0][field] = value
            with self.subTest(field=field),self.assertRaises(AssertionError): prepare(self.source,self.pack(),self.output)
            self.scene['textures'][0][field] = original
            self.assertFalse(self.output.exists())
        self.scene['sourceRect'] = [-960,-540,960,540]
        with self.assertRaises(AssertionError): prepare(self.source,self.pack(),self.output)
        self.scene['sourceRect'] = [-512,-288,512,288]
        self.scene['exports']['background']['status'] = 'unsupported'
        with self.assertRaises(AssertionError): prepare(self.source,self.pack(),self.output)
        self.assertFalse(self.output.exists())

    def test_existing_fixtures_cannot_be_silently_reused(self):
        request = self.pack();self.output.mkdir(parents=True)
        (self.output/'sentinel').write_text('keep')
        with self.assertRaisesRegex(AssertionError,'already exists'): prepare(self.source,request,self.output)
        self.assertEqual((self.output/'sentinel').read_text(),'keep')


if __name__ == '__main__': unittest.main()
