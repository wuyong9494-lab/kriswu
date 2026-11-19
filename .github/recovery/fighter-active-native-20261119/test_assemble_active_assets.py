import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import assemble_active_assets as a

def r(name,data):
    return dict(name=name,bytes=len(data),sha256=hashlib.sha256(data).hexdigest())

class StageTests(unittest.TestCase):
    def test_clean_source_parent_and_full_539_fixture_closure(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t).resolve()
            app=p/"App"; app.mkdir()
            dst=app/"Resources"/"FighterPrivate"
            self.assertFalse(dst.parent.exists())
            self.assertEqual(a.prepare_app_resources(p,dst),dst)
            self.assertTrue(dst.parent.is_dir())
            self.assertFalse(dst.exists())
            source=p/"source";source.mkdir()
            rows=[]
            for i in range(539):
                name="Synthetic_%03d.dat"%i
                raw=f"synthetic-byte-fixture-{i}".encode()
                rows.append(r(name,raw));(source/name).write_bytes(raw)
            with patch.object(a,"active_inventory",return_value=(rows,"fixture")):
                self.assertEqual(a.stage_new(p,dst,[source],[])["stagedFiles"],539)
                self.assertEqual(a.flat_resources(dst,rows)["verifiedFiles"],539)
                with self.assertRaisesRegex(ValueError,"already exists"):
                    a.prepare_app_resources(p,dst)

    def test_clean_source_parent_never_follows_a_symlink(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t).resolve()
            app=p/"App"; app.mkdir()
            outside=p/"outside";outside.mkdir()
            resources=app/"Resources";resources.symlink_to(outside,target_is_directory=True)
            with self.assertRaises(a.CheckError) as error:
                a.prepare_app_resources(p,resources/"FighterPrivate")
            self.assertEqual(error.exception.code,"symlink")
            self.assertFalse((outside/"FighterPrivate").exists())

    def test_partial_pack_never_written(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t); source=p/"source";source.mkdir(); (source/"one.dat").write_bytes(b"old")
            rows=[r("one.dat",b"old"),r("two.dat",b"new")]
            with patch.object(a,"active_inventory",return_value=(rows,"digest")):
                with self.assertRaisesRegex(ValueError,"1/2"):
                    a.stage_new(p,p/"FighterPrivate",[source],[])
                self.assertFalse((p/"FighterPrivate").exists())

    def test_complete_atomic_write_prefers_authentic_byte_identity(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t); old=p/"old";old.mkdir(); source=p/"source";source.mkdir()
            (old/"old-name.dat").write_bytes(b"old")
            (source/"one.dat").write_bytes(b"bad");(source/"two.dat").write_bytes(b"new")
            rows=[r("one.dat",b"old"),r("two.dat",b"new")]
            with patch.object(a,"active_inventory",return_value=(rows,"digest")):
                receipt=a.stage_new(p,p/"FighterPrivate",[source],[(old,[r("old-name.dat",b"old")])])
                self.assertEqual(receipt["stagedFiles"],2)
                self.assertEqual((p/"FighterPrivate/one.dat").read_bytes(),b"old")
                self.assertEqual((p/"FighterPrivate/two.dat").read_bytes(),b"new")
                with self.assertRaisesRegex(ValueError,"existing"):
                    a.stage_new(p,p/"FighterPrivate",[source],[])

    def test_archive_roundtrip_and_extra_member_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t); f=p/"source"; f.write_bytes(b"one")
            rows=[r("file.dat",b"one")]
            result=a.make_local_archive(p/"source.zip",rows,{"file.dat":f})
            self.assertEqual(result,hashlib.sha256((p/"source.zip").read_bytes()).hexdigest())
            self.assertEqual(a.extract_local_archive(p/"source.zip",p/"valid",rows),1)
            with zipfile.ZipFile(p/"source.zip","a") as z:z.writestr("../extra",b"x")
            with self.assertRaisesRegex(ValueError,"closure"):
                a.extract_local_archive(p/"source.zip",p/"invalid",rows)
            self.assertFalse((p/"invalid").exists())

if __name__=="__main__": unittest.main()
