"""Synthetic-only tests. Prepared but deliberately NOT RUN during packaging."""
import json
import os
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import music_package as pack


class MusicPackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.destination = self.root / 'destination'
        self.destination.mkdir()
        self.files = (('one.wav', 3, pack.digest(b'one')), ('two.json', 3, pack.digest(b'two')))
        header = json.dumps({'version': 1, 'purpose': pack.PURPOSE, 'files': [
            {'file': n, 'bytes': s, 'sha256': h} for n, s, h in self.files
        ]}, sort_keys=True, separators=(',', ':')).encode('ascii')
        self.prefix = pack.MAGIC + struct.pack('>I', len(header)) + header
        self.data = self.prefix + b'onetwo'
        self.archive = self.root / 'synthetic.musicpack'
        self.archive.write_bytes(self.data)
        patches = patch.multiple(pack, FILES=self.files, HEADER=header, PREFIX=self.prefix,
                                 ARCHIVE_BYTES=len(self.data), ARCHIVE_SHA256=pack.digest(self.data))
        patches.start()
        self.addCleanup(patches.stop)

    def test_prepare_reproduces_pinned_bytes_and_refuses_overwrite(self):
        source = self.root / 'source'
        source.mkdir()
        (source / 'one.wav').write_bytes(b'one')
        (source / 'two.json').write_bytes(b'two')
        output = self.root / 'prepared.musicpack'
        pack.prepare(source, output)
        self.assertEqual(output.read_bytes(), self.data)
        with self.assertRaises(FileExistsError):
            pack.prepare(source, output)
        self.assertEqual(output.read_bytes(), self.data)

    def test_prepare_validates_all_inputs_before_writing(self):
        source = self.root / 'source'
        source.mkdir()
        (source / 'one.wav').write_bytes(b'one')
        (source / 'two.json').write_bytes(b'bad')
        output = self.root / 'prepared.musicpack'
        with self.assertRaises(ValueError):
            pack.prepare(source, output)
        self.assertFalse(output.exists())
        self.assertEqual(list(self.root.glob('.music-prepare-*')), [])

    def test_verified_payload_and_idempotent_stage(self):
        self.assertEqual(pack.verify(self.archive), {'one.wav': b'one', 'two.json': b'two'})
        pack.stage(self.archive, self.destination)
        pack.stage(self.archive, self.destination)
        self.assertEqual((self.destination / 'one.wav').read_bytes(), b'one')

    def test_nonmatching_destination_preflight_no_partial_writes(self):
        (self.destination / 'two.json').write_bytes(b'bad')
        with self.assertRaises(ValueError):
            pack.stage(self.archive, self.destination)
        self.assertFalse((self.destination / 'one.wav').exists())
        self.assertEqual((self.destination / 'two.json').read_bytes(), b'bad')

    def test_missing_extra_truncated_and_tampered(self):
        for data in (b'', self.data[:-1], self.data + b'x', self.data[:-1] + b'x'):
            with self.subTest(data_length=len(data)), self.assertRaises(ValueError):
                pack.verify_bytes(data)

    def test_noncanonical_entry_names_duplicates_and_symlink_metadata(self):
        for name in ('../evil', '/evil', 'one.wav/child', 'two.json', 'symlink'):
            changed = self.data.replace(b'one.wav', name.encode(), 1)
            with self.subTest(name=name), self.assertRaises(ValueError):
                pack.verify_bytes(changed)

    def test_archive_and_destination_symlinks(self):
        link = self.root / 'link'
        link.symlink_to(self.archive)
        with self.assertRaises(OSError):
            pack.verify(link)
        (self.destination / 'one.wav').symlink_to(self.archive)
        with self.assertRaises(OSError):
            pack.stage(self.archive, self.destination)

    def test_parent_symlink_and_traversal(self):
        link = self.root / 'directory-link'
        link.symlink_to(self.destination, target_is_directory=True)
        with self.assertRaises(OSError):
            pack.stage(self.archive, link)
        with self.assertRaises(ValueError):
            pack.stage(self.archive, self.destination / '..' / 'destination')

    def test_nonregular_file_rejected_without_blocking(self):
        fifo = self.root / 'fifo'
        os.mkfifo(fifo)
        with self.assertRaises(ValueError):
            pack.verify(fifo)

    def test_member_digest_still_checked_if_archive_pin_changes(self):
        corrupted = self.data[:-1] + b'x'
        with patch.object(pack, 'ARCHIVE_SHA256', pack.digest(corrupted)):
            with self.assertRaises(ValueError):
                pack.verify_bytes(corrupted)

    def test_race_created_destination_never_overwritten(self):
        real_link = os.link
        def raced_link(src, dst, **kwargs):
            (self.destination / dst).write_bytes(b'new')
            return real_link(src, dst, **kwargs)
        with patch.object(pack.os, 'link', side_effect=raced_link):
            with self.assertRaises(FileExistsError):
                pack.stage(self.archive, self.destination)
        self.assertEqual((self.destination / 'one.wav').read_bytes(), b'new')
        self.assertEqual(list(self.destination.glob('.music-stage-*')), [])


if __name__ == '__main__':
    unittest.main()
