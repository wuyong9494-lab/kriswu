#!/usr/bin/env python3
"""New extraction/status boundary checks; no Apple compilation or rendering."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import check_fighter_public_shaders as check


class PublicShaderExtractionChecks(unittest.TestCase):
    def test_changed_production_boundaries_fail_closed(self):
        originals = {name: (check.ROOT/name).read_bytes() for name in (check.MORPH, check.SHADOW)}
        changes = [
            (check.MORPH, b'let library = try device.makeLibrary(source: ',
             b'let library = try device.makeLibrary(source: let library = try device.makeLibrary(source: '),
            (check.MORPH, b'private static func sourceUV()', b'private static func renamedSourceUV()'),
            (check.SHADOW, b'#include <metal_stdlib>', b'#include <metal_stdlib>\n\\#(unboundExpression)'),
        ]
        for name, old, new in changes:
            with self.subTest(name=name, change=old.decode()):
                altered = dict(originals)
                self.assertIn(old, altered[name])
                altered[name] = altered[name].replace(old, new, 1)
                reads = []
                def read(path, maximum):
                    key = str(path.relative_to(check.ROOT))
                    reads.append(key)
                    return altered[key]
                with patch.object(check, 'regular', side_effect=read):
                    with self.assertRaises(check.CheckFailure):
                        check.extract_sources(check.ROOT)
                self.assertEqual(reads, [check.MORPH, check.SHADOW])

    def check_status(self, prepare):
        with tempfile.TemporaryDirectory(prefix='fighter-public-shader-boundary-') as temporary:
            output = Path(temporary).resolve()/'result'
            args = ['check_fighter_public_shaders.py', '--output', str(output)]
            if prepare:
                args.append('--prepare-only')
            with patch.object(check.sys, 'argv', args), patch.object(check.sys, 'platform', 'linux'), \
                 patch.object(check.subprocess, 'Popen', side_effect=AssertionError('Native command was attempted')), \
                 contextlib.redirect_stdout(io.StringIO()):
                code = check.main()
            report = json.loads((output/'public-shader-result.json').read_bytes())
            self.assertEqual(code, 0 if prepare else 3)
            self.assertEqual(report['status'], 'prepared' if prepare else 'unavailable')
            self.assertEqual(report['commands'], [])
            self.assertEqual(report['privateProgramsChecked'], 0)
            self.assertFalse(report['iOSDeviceRenderingObserved'])
            self.assertEqual([item['path'] for item in report['inputs']], [check.MORPH, check.SHADOW, check.CLI])
            for item in report['inputs']:
                raw = (check.ROOT/item['path']).read_bytes()
                self.assertEqual((len(raw), check.digest(raw)), (item['bytes'], item['sha256']))
            self.assertEqual(check.digest((output/'ExtractedProductionShaders.swift').read_bytes()),
                             report['extractedSwiftSHA256'])

    def test_preparation_is_not_a_shader_pass(self):
        self.check_status(True)

    def test_missing_platform_is_unavailable_without_native_commands(self):
        self.check_status(False)


if __name__ == '__main__':
    unittest.main(verbosity=2)
